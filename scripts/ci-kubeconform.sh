#!/usr/bin/env bash
# kubeconform — validate rendered manifests against Kubernetes OpenAPI schemas.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENVIRONMENT="${ENVIRONMENT:-staging}"
KUBERNETES_VERSION="${KUBERNETES_VERSION:-1.30.0}"
RENDER_DIR="${RENDER_DIR:-}"

log() { printf '==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

install_kubeconform_if_missing() {
  if command -v kubeconform >/dev/null 2>&1; then
    return 0
  fi
  local version="${KUBECONFORM_VERSION:-0.6.7}"
  local arch
  arch="$(uname -m)"
  case "${arch}" in
    x86_64|amd64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) die "Unsupported arch for kubeconform: ${arch}" ;;
  esac
  log "Installing kubeconform v${version}"
  curl -fsSL "https://github.com/yannh/kubeconform/releases/download/v${version}/kubeconform-linux-${arch}.tar.gz" \
    | tar xz -C /tmp kubeconform
  install /tmp/kubeconform "${HOME}/.local/bin/kubeconform" 2>/dev/null \
    || sudo install /tmp/kubeconform /usr/local/bin/kubeconform
  export PATH="${HOME}/.local/bin:/usr/local/bin:${PATH}"
  command -v kubeconform >/dev/null 2>&1 || die "kubeconform install failed"
}

ensure_rendered() {
  if [[ -n "${RENDER_DIR}" && -d "${RENDER_DIR}" ]]; then
    return 0
  fi
  RENDER_DIR="$(mktemp -d)"
  export RENDER_DIR
  log "Rendering GitOps manifests (${ENVIRONMENT})"
  python3 "${REPO_ROOT}/scripts/ci_render_gitops.py" \
    --env "${ENVIRONMENT}" \
    --output "${RENDER_DIR}" \
    --include-bootstrap \
    --include-metallb
}

main() {
  local cleanup=0
  if [[ -z "${RENDER_DIR}" ]]; then
    cleanup=1
  fi

  command -v python3 >/dev/null 2>&1 || die "Missing python3"
  install_kubeconform_if_missing
  ensure_rendered

  log "kubeconform on rendered manifests (kubernetes ${KUBERNETES_VERSION}, ignore missing CRD schemas)"
  # Custom CRDs (Istio, cert-manager, Kyverno, Prometheus) lack bundled schemas — core kinds still validated.
  kubeconform \
    -kubernetes-version "${KUBERNETES_VERSION}" \
    -ignore-missing-schemas \
    -summary \
    "${RENDER_DIR}"/*.yaml

  [[ "${cleanup}" -eq 0 ]] || rm -rf "${RENDER_DIR}"
  log "kubeconform validation passed"
}

main "$@"
