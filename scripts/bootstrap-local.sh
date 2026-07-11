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
  log "Installing Argo CD"
  kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
  helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
  helm repo update argo

  helm upgrade --install argocd argo/argo-cd \
    --namespace argocd \
    --set configs.params.server.insecure=true \
    --set server.service.type=ClusterIP \
    --set server.ingress.enabled=false \
    --set applicationSet.enabled=true \
    --set dex.enabled=false \
    --set notifications.enabled=false \
    --wait --timeout 10m

  kubectl -n argocd rollout status deploy/argocd-server --timeout=300s
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
}

wait_for_apps() {
  log "Waiting for core Applications (timeout ${WAIT_TIMEOUT}s)"
  local apps=(cert-manager platform-ca istiod mtls-demo)
  local deadline=$((SECONDS + WAIT_TIMEOUT))

  for app in "${apps[@]}"; do
    log "Waiting for Application: ${app}"
    while (( SECONDS < deadline )); do
      if kubectl -n argocd get application "${app}" >/dev/null 2>&1; then
        local sync health
        sync="$(kubectl -n argocd get application "${app}" -o jsonpath='{.status.sync.status}' 2>/dev/null || true)"
        health="$(kubectl -n argocd get application "${app}" -o jsonpath='{.status.health.status}' 2>/dev/null || true)"
        if [[ "${sync}" == "Synced" && "${health}" == "Healthy" ]]; then
          log "${app}: Synced / Healthy"
          break
        fi
        printf '  %s: sync=%s health=%s\n' "${app}" "${sync:-pending}" "${health:-pending}"
      else
        printf '  %s: not created yet\n' "${app}"
      fi
      sleep 15
    done
    if (( SECONDS >= deadline )); then
      warn "Timed out waiting for ${app} — platform may still be syncing"
      return 0
    fi
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

main() {
  if [[ "${DESTROY}" == "true" ]]; then
    destroy_cluster
    exit 0
  fi

  check_prerequisites
  create_cluster
  install_metallb
  install_argocd
  apply_cluster_root
  wait_for_apps
  print_access_hints
}

main "$@"
