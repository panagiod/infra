#!/usr/bin/env bash
# Option B — run the same checks as GitHub Actions CI locally (no cluster required).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_TERRAFORM="${RUN_TERRAFORM:-auto}"   # auto | true | false
RUN_GITOPS="${RUN_GITOPS:-auto}"         # auto | true | false
RUN_IMAGES="${RUN_IMAGES:-auto}"         # auto | true | false
RUN_PREFLIGHT="${RUN_PREFLIGHT:-auto}"   # auto | true | false — namespaces + images + kubeconform
RUN_SCRIPTS="${RUN_SCRIPTS:-true}"

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1 (install it or run in Codespaces)"
}

git_changed() {
  local path="$1"
  if ! git -C "${REPO_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    return 0
  fi
  local base="${CI_BASE_REF:-main}"
  if git -C "${REPO_ROOT}" rev-parse "${base}" >/dev/null 2>&1; then
    git -C "${REPO_ROOT}" diff --name-only "${base}...HEAD" | grep -q "^${path}" && return 0
    return 1
  fi
  return 0
}

should_run() {
  local mode="$1"
  local path="$2"
  case "${mode}" in
    true) return 0 ;;
    false) return 1 ;;
    auto) git_changed "${path}" ;;
    *) die "Invalid mode: ${mode} (use auto|true|false)" ;;
  esac
}

install_kustomize_if_missing() {
  if command -v kustomize >/dev/null 2>&1; then
    return 0
  fi
  log "Installing kustomize"
  KUSTOMIZE_VERSION="$(curl -fsSL https://api.github.com/repos/kubernetes-sigs/kustomize/releases/latest | grep '"tag_name"' | head -1 | sed -E 's/.*kustomize\/v?([^"]+)".*/\1/')"
  curl -fsSL "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE_VERSION}/kustomize_v${KUSTOMIZE_VERSION}_linux_amd64.tar.gz" | tar xz -C /tmp
  sudo install /tmp/kustomize /usr/local/bin/kustomize 2>/dev/null || install /tmp/kustomize "${HOME}/.local/bin/kustomize"
  export PATH="${HOME}/.local/bin:${PATH}"
  require_cmd kustomize
}

install_terraform_if_missing() {
  if command -v terraform >/dev/null 2>&1; then
    return 0
  fi
  log "Installing terraform"
  TF_VERSION="$(curl -fsSL https://api.github.com/repos/hashicorp/terraform/releases/latest | grep '"tag_name"' | head -1 | sed -E 's/.*"v([^"]+)".*/\1/')"
  curl -fsSL "https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_linux_amd64.zip" -o /tmp/terraform.zip
  unzip -qo /tmp/terraform.zip -d /tmp
  sudo install /tmp/terraform /usr/local/bin/terraform 2>/dev/null || install /tmp/terraform "${HOME}/.local/bin/terraform"
  export PATH="${HOME}/.local/bin:${PATH}"
  require_cmd terraform
}

validate_scripts() {
  [[ "${RUN_SCRIPTS}" == "true" ]] || return 0
  log "Checking shell script syntax"
  local script failed=0
  while IFS= read -r script; do
    bash -n "${script}" || failed=1
  done < <(find "${REPO_ROOT}/scripts" "${REPO_ROOT}/.devcontainer" -name '*.sh' -type f | sort)
  [[ "${failed}" -eq 0 ]] || die "Shell syntax check failed"
  log "All scripts passed bash -n"
}

validate_gitops_logic() {
  log "Validating GitOps app-of-apps logic (install order, no Application sync-waves)"
  for env in staging prod; do
    "${REPO_ROOT}/scripts/validate-gitops-logic.sh" "${env}"
  done
}

validate_images() {
  should_run "${RUN_IMAGES}" "gitops/" || { log "Skipping image preflight (no gitops/ changes vs ${CI_BASE_REF:-main})"; return 0; }
  log "Verifying Kind smoke container images are pullable"
  "${REPO_ROOT}/scripts/ci-check-images.sh"
}

validate_preflight() {
  should_run "${RUN_PREFLIGHT}" "gitops/" || { log "Skipping GitOps preflight bundle (no gitops/ changes vs ${CI_BASE_REF:-main})"; return 0; }
  log "Running GitOps preflight (namespaces + images + kubeconform)"
  "${REPO_ROOT}/scripts/ci-preflight-gitops.sh"
}

validate_gitops() {
  should_run "${RUN_GITOPS}" "gitops/" || { log "Skipping GitOps (no gitops/ changes vs ${CI_BASE_REF:-main})"; return 0; }
  install_kustomize_if_missing
  log "Building GitOps manifests (same paths as .github/workflows/gitops.yml)"
  local paths=(
    gitops/clusters/staging
    gitops/clusters/prod
    gitops/platform/cert-manager/overlays/staging
    gitops/platform/cert-manager/overlays/prod
    gitops/apps/mtls-demo/overlays/staging
    gitops/apps/mtls-demo/overlays/prod
    gitops/apps/kubeship/overlays/staging
    gitops/apps/kubeship/overlays/prod
    gitops/platform/couchbase/overlays/staging
    gitops/platform/couchbase/overlays/prod
    gitops/platform/istio/ingress-tls/overlays/staging
    gitops/platform/istio/ingress-tls/overlays/prod
    gitops/platform/monitoring/alerts
  )
  local path
  for path in "${paths[@]}"; do
    log "kustomize build ${path}"
    kustomize build "${REPO_ROOT}/${path}" >/dev/null
  done
}

validate_terraform() {
  should_run "${RUN_TERRAFORM}" "terraform/" || { log "Skipping Terraform (no terraform/ changes vs ${CI_BASE_REF:-main})"; return 0; }
  install_terraform_if_missing
  log "Terraform fmt check"
  (cd "${REPO_ROOT}/terraform" && terraform fmt -check -recursive .)
  log "Terraform validate (all environments)"
  local envs=(
    terraform/environments/staging
    terraform/environments/prod
    terraform/environments/azure/staging
    terraform/environments/azure/prod
  )
  local env
  for env in "${envs[@]}"; do
    log "validate ${env}"
    (cd "${REPO_ROOT}/${env}" && terraform init -backend=false >/dev/null && terraform validate)
  done
}

main() {
  log "CI validation (Option B) — mirrors GitHub Actions without a cluster"
  validate_scripts
  validate_gitops_logic
  validate_gitops
  validate_preflight
  validate_terraform
  log "All checks passed — safe to push and open a PR"
  printf '\nNext: git push origin <branch> → open PR → CI runs automatically\n'
  printf 'Guide: docs/ci-only.md\n\n'
}

main "$@"
