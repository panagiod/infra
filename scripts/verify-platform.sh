#!/usr/bin/env bash
# Post-bootstrap verification — run after bootstrap-aws.sh or manual Terraform apply.
set -euo pipefail

ENVIRONMENT="${ENVIRONMENT:-staging}"
AWS_REGION="${AWS_REGION:-us-east-1}"
NAMESPACE_ARGOCD="argocd"
FAILURES=0

log() { printf '\n==> %s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
fail() { printf 'FAIL: %s\n' "$*" >&2; FAILURES=$((FAILURES + 1)); }
pass() { printf 'PASS: %s\n' "$*"; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { fail "Missing required command: $1"; return 1; }
}

check_tools() {
  log "Checking tools"
  require_cmd kubectl
  if [[ "${LOCAL:-false}" == "true" ]]; then
    pass "Local mode — skipping AWS CLI check"
    return 0
  fi
  require_cmd aws
  aws sts get-caller-identity >/dev/null 2>&1 && pass "AWS CLI authenticated" || fail "AWS CLI not authenticated"
}

resolve_cluster() {
  if [[ "${LOCAL:-false}" == "true" ]]; then
    local ctx="kind-${CLUSTER_NAME:-infra-local}"
    kubectl config use-context "${ctx}" >/dev/null 2>&1 || die "kind context ${ctx} not found — run bootstrap-local.sh first"
    CLUSTER_NAME="${CLUSTER_NAME:-infra-local}"
    pass "Using kind context ${ctx}"
    return 0
  fi

  local cluster_name="${CLUSTER_NAME:-}"
  if [[ -z "${cluster_name}" ]]; then
    cluster_name="infra-${ENVIRONMENT}"
  fi
  CLUSTER_NAME="${cluster_name}"
  log "Using cluster: ${CLUSTER_NAME} (region ${AWS_REGION})"
  aws eks update-kubeconfig --region "${AWS_REGION}" --name "${CLUSTER_NAME}" >/dev/null
  pass "kubeconfig updated"
}

check_nodes() {
  log "Checking nodes"
  local ready
  ready="$(kubectl get nodes --no-headers 2>/dev/null | awk '$2=="Ready"{c++} END{print c+0}')"
  if [[ "${ready}" -ge 1 ]]; then
    pass "Nodes Ready: ${ready}"
  else
    fail "No Ready nodes found"
  fi
}

check_argocd() {
  log "Checking Argo CD"
  if kubectl -n "${NAMESPACE_ARGOCD}" get pods -l app.kubernetes.io/name=argocd-server --no-headers 2>/dev/null | grep -q Running; then
    pass "argocd-server is Running"
  else
    fail "argocd-server is not Running"
  fi

  if [[ "${LOCAL:-false}" == "true" ]]; then
    pass "Local bootstrap — cluster-root not used (Kind smoke materializes apps wave-by-wave)"
    return 0
  fi

  if kubectl -n "${NAMESPACE_ARGOCD}" get application cluster-root >/dev/null 2>&1; then
    local sync health
    sync="$(kubectl -n "${NAMESPACE_ARGOCD}" get application cluster-root -o jsonpath='{.status.sync.status}' 2>/dev/null || true)"
    health="$(kubectl -n "${NAMESPACE_ARGOCD}" get application cluster-root -o jsonpath='{.status.health.status}' 2>/dev/null || true)"
    if [[ "${sync}" == "Synced" && "${health}" == "Healthy" ]]; then
      pass "cluster-root Application: Synced / Healthy"
    else
      warn "cluster-root sync=${sync:-Unknown} health=${health:-Unknown} (may still be progressing)"
    fi
  else
    fail "cluster-root Application not found"
  fi
}

check_platform_apps() {
  log "Checking platform Applications"
  local apps=(
    cert-manager
    platform-ca
    istiod
    istio-csr
    istio-gateway
    istio-ingress-tls
    istio-policies
    monitoring
    monitoring-alerts
    mtls-demo
    kubeship
  )
  for app in "${apps[@]}"; do
    if ! kubectl -n "${NAMESPACE_ARGOCD}" get application "${app}" >/dev/null 2>&1; then
      fail "Application missing: ${app}"
      continue
    fi
    local sync health
    sync="$(kubectl -n "${NAMESPACE_ARGOCD}" get application "${app}" -o jsonpath='{.status.sync.status}' 2>/dev/null || true)"
    health="$(kubectl -n "${NAMESPACE_ARGOCD}" get application "${app}" -o jsonpath='{.status.health.status}' 2>/dev/null || true)"
    if [[ "${sync}" == "Synced" && "${health}" == "Healthy" ]]; then
      pass "${app}: Synced / Healthy"
    else
      warn "${app}: sync=${sync:-Unknown} health=${health:-Unknown}"
    fi
  done
}

check_workloads() {
  log "Checking key namespaces"
  local checks=(
    "cert-manager:app.kubernetes.io/name=cert-manager"
    "istio-system:app=istiod"
    "istio-system:app=istio-ingressgateway"
    "mtls-demo:app=frontend"
    "mtls-demo:app=backend"
    "kubeship:app=kubeship-api"
  )
  for entry in "${checks[@]}"; do
    local ns selector
    ns="${entry%%:*}"
    selector="${entry#*:}"
    if kubectl -n "${ns}" get pods -l "${selector}" --no-headers 2>/dev/null | grep -q Running; then
      pass "${ns} (${selector}) has Running pods"
    else
      warn "${ns} (${selector}) not all Running yet"
    fi
  done
}

check_mtls_demo() {
  log "Checking mTLS demo connectivity"
  if kubectl -n mtls-demo exec deploy/frontend -- wget -qO- --timeout=5 http://backend:8080/ >/dev/null 2>&1; then
    pass "frontend -> backend request succeeded"
  else
    warn "frontend -> backend request failed (mesh may still be syncing)"
  fi
}

check_ingress_tls() {
  log "Checking ingress TLS"
  if kubectl -n istio-system get certificate istio-ingressgateway-certs >/dev/null 2>&1; then
    local ready
    ready="$(kubectl -n istio-system get certificate istio-ingressgateway-certs -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
    if [[ "${ready}" == "True" ]]; then
      pass "istio-ingressgateway-certs Certificate is Ready"
    else
      warn "istio-ingressgateway-certs not Ready yet"
    fi
  else
    warn "istio-ingressgateway-certs Certificate not found"
  fi
}

check_mtls_policy() {
  log "Checking STRICT mTLS policy"
  local mode
  mode="$(kubectl -n istio-system get peerauthentication default -o jsonpath='{.spec.mtls.mode}' 2>/dev/null || true)"
  if [[ "${mode}" == "STRICT" ]]; then
    pass "PeerAuthentication default mode is STRICT"
  else
    warn "PeerAuthentication default mode is ${mode:-not found}"
  fi
}

summary() {
  log "Verification summary"
  if [[ "${FAILURES}" -eq 0 ]]; then
    printf 'All critical checks passed.\n'
    exit 0
  fi
  printf '%d critical check(s) failed. Review output above.\n' "${FAILURES}"
  exit 1
}

main() {
  check_tools
  resolve_cluster
  check_nodes
  check_argocd
  check_platform_apps
  check_workloads
  check_ingress_tls
  check_mtls_policy
  check_mtls_demo
  summary
}

main "$@"
