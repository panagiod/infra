#!/usr/bin/env bash
# Zero-cost local bootstrap: kind cluster + Argo CD + GitOps platform (no AWS/Azure).
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-infra-local}"
ENVIRONMENT="${ENVIRONMENT:-staging}"               # staging | prod — selects gitops/clusters/<env>
GITOPS_REPO_URL="${GITOPS_REPO_URL:-https://github.com/panagiod/infra}"
GITOPS_REVISION="${GITOPS_REVISION:-main}"
INSTALL_METALLB="${INSTALL_METALLB:-true}"            # LoadBalancer support for Istio gateway
RECREATE_CLUSTER="${RECREATE_CLUSTER:-false}"
DESTROY="${DESTROY:-false}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-900}"                   # seconds to wait for core apps
STRICT_WAIT="${STRICT_WAIT:-false}"                   # exit 1 on wait timeout (CI)
BOOTSTRAP_PHASE="${BOOTSTRAP_PHASE:-all}"             # all | argocd | cluster-root | wait
WAIT_APP="${WAIT_APP:-}"                              # single app when BOOTSTRAP_PHASE=wait

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KIND_CONFIG="${REPO_ROOT}/hack/kind/cluster.yaml"

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

check_prerequisites() {
  log "Checking prerequisites"
  require_cmd docker
  docker info >/dev/null 2>&1 || die "Docker is not running"
  require_cmd kind
  require_cmd kubectl
  require_cmd helm
}

destroy_cluster() {
  log "Deleting kind cluster: ${CLUSTER_NAME}"
  kind delete cluster --name "${CLUSTER_NAME}" 2>/dev/null || true
  log "Cluster deleted"
}

create_cluster() {
  if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
    if [[ "${RECREATE_CLUSTER}" == "true" ]]; then
      destroy_cluster
    else
      log "kind cluster ${CLUSTER_NAME} already exists — reusing"
      kubectl config use-context "kind-${CLUSTER_NAME}" >/dev/null
      return 0
    fi
  fi

  log "Creating kind cluster: ${CLUSTER_NAME}"
  kind create cluster --name "${CLUSTER_NAME}" --config "${KIND_CONFIG}"
  kubectl config use-context "kind-${CLUSTER_NAME}" >/dev/null
  kubectl cluster-info
}

install_metallb() {
  [[ "${INSTALL_METALLB}" == "true" ]] || return 0

  log "Installing MetalLB for LoadBalancer services"
  kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.9/config/manifests/metallb-native.yaml
  kubectl -n metallb-system rollout status deploy/controller --timeout=180s
  kubectl apply -f "${REPO_ROOT}/hack/kind/metallb.yaml"
}

install_argocd() {
  log "Installing Argo CD (latest stable chart; requires spec.dependsOn)"
  kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
  helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
  helm repo update argo

  helm upgrade --install argocd argo/argo-cd \
    --namespace argocd \
    --values "${REPO_ROOT}/hack/argocd/bootstrap-values.yaml" \
    --wait --timeout 10m

  kubectl -n argocd rollout status deploy/argocd-server --timeout=300s
  if ! kubectl explain application.spec.dependsOn >/dev/null 2>&1; then
    die "Argo CD CRD missing spec.dependsOn — upgrade Argo CD to v2.14+"
  fi
  log "Argo CD ready (dependsOn supported)"
}

materialize_cluster_applications() {
  log "Materializing all Application CRs from gitops/clusters/${ENVIRONMENT}"
  if ! kubectl explain application.spec.dependsOn >/dev/null 2>&1; then
    die "Cannot materialize apps: Argo CD Application CRD does not support spec.dependsOn"
  fi
  # dependsOn gates sync timing in Argo CD; it does not always create child Application
  # CRs until dependencies are healthy. Apply manifests directly so CI wait steps
  # can observe each app while dependsOn still orders actual sync.
  kustomize build "${REPO_ROOT}/gitops/clusters/${ENVIRONMENT}" | kubectl apply -f -
  kubectl -n argocd get applications -o wide || true
}

apply_cluster_root() {
  log "Registering cluster-root Application (gitops/clusters/${ENVIRONMENT})"
  kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cluster-root
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: ${GITOPS_REPO_URL}
    targetRevision: ${GITOPS_REVISION}
    path: gitops/clusters/${ENVIRONMENT}
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
EOF
  materialize_cluster_applications
  kubectl -n argocd annotate application cluster-root argocd.argoproj.io/refresh=hard --overwrite >/dev/null 2>&1 || true
}

app_status_line() {
  local app="$1"
  if ! kubectl -n argocd get application "${app}" >/dev/null 2>&1; then
    printf '  %s: not created yet\n' "${app}"
    return 0
  fi
  local sync health msg
  sync="$(kubectl -n argocd get application "${app}" -o jsonpath='{.status.sync.status}' 2>/dev/null || true)"
  health="$(kubectl -n argocd get application "${app}" -o jsonpath='{.status.health.status}' 2>/dev/null || true)"
  msg="$(kubectl -n argocd get application "${app}" -o jsonpath='{.status.conditions[?(@.type=="ComparisonError")].message}' 2>/dev/null || true)"
  if [[ -z "${msg}" ]]; then
    msg="$(kubectl -n argocd get application "${app}" -o jsonpath='{.status.operationState.message}' 2>/dev/null | head -c 120 || true)"
  fi
  if [[ -n "${msg}" ]]; then
    printf '  %s: sync=%s health=%s — %s\n' "${app}" "${sync:-pending}" "${health:-pending}" "${msg}"
  else
    printf '  %s: sync=%s health=%s\n' "${app}" "${sync:-pending}" "${health:-pending}"
  fi
}

wait_for_single_app() {
  local app="$1"
  local timeout="${2:-${WAIT_TIMEOUT}}"
  log "Waiting for Application: ${app} (timeout ${timeout}s)"
  local deadline=$((SECONDS + timeout))

  while (( SECONDS < deadline )); do
    if kubectl -n argocd get application "${app}" >/dev/null 2>&1; then
      local sync health
      sync="$(kubectl -n argocd get application "${app}" -o jsonpath='{.status.sync.status}' 2>/dev/null || true)"
      health="$(kubectl -n argocd get application "${app}" -o jsonpath='{.status.health.status}' 2>/dev/null || true)"
      if [[ "${sync}" == "Synced" && "${health}" == "Healthy" ]]; then
        log "${app}: Synced / Healthy"
        kubectl -n argocd get application "${app}" -o wide || true
        return 0
      fi
      app_status_line "${app}"
    else
      app_status_line "${app}"
    fi
    sleep 15
  done

  warn "Timed out waiting for ${app}"
  log "Argo CD applications (debug)"
  kubectl -n argocd get applications -o wide || true
  if [[ "${STRICT_WAIT}" == "true" ]]; then
    exit 1
  fi
  return 0
}

wait_for_apps() {
  log "Waiting for core Applications (timeout ${WAIT_TIMEOUT}s each)"
  local apps=(cert-manager platform-ca istiod mtls-demo)
  local app
  for app in "${apps[@]}"; do
    wait_for_single_app "${app}" "${WAIT_TIMEOUT}"
  done
}

warn() { printf 'WARN: %s\n' "$*" >&2; }

print_access_hints() {
  log "Local cluster ready"
  printf '\nContext: kind-%s\n' "${CLUSTER_NAME}"
  printf 'Argo CD UI:\n  kubectl -n argocd port-forward svc/argocd-server 8080:80\n  http://localhost:8080\n'
  printf 'Argo CD admin password:\n  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo\n'
  printf '\nVerify:\n  LOCAL=true CLUSTER_NAME=%s ./scripts/verify-platform.sh\n' "${CLUSTER_NAME}"
  printf '\nDestroy:\n  DESTROY=true ./scripts/bootstrap-local.sh\n'
  printf '\nSee docs/local-dev.md and docs/verify.md for next steps.\n'
}

run_phase() {
  case "${BOOTSTRAP_PHASE}" in
    all)
      check_prerequisites
      create_cluster
      install_metallb
      install_argocd
      apply_cluster_root
      wait_for_apps
      print_access_hints
      ;;
    argocd)
      require_cmd kubectl
      require_cmd helm
      install_argocd
      ;;
    cluster-root)
      require_cmd kubectl
      apply_cluster_root
      kubectl -n argocd get applications -o wide 2>/dev/null || true
      ;;
    wait)
      require_cmd kubectl
      [[ -n "${WAIT_APP}" ]] || die "WAIT_APP is required when BOOTSTRAP_PHASE=wait"
      wait_for_single_app "${WAIT_APP}" "${WAIT_TIMEOUT}"
      ;;
    *)
      die "Unknown BOOTSTRAP_PHASE: ${BOOTSTRAP_PHASE} (use all|argocd|cluster-root|wait)"
      ;;
  esac
}

main() {
  if [[ "${DESTROY}" == "true" ]]; then
    destroy_cluster
    exit 0
  fi

  run_phase
}

main "$@"
