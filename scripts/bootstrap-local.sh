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
FAIL_FAST="${FAIL_FAST:-true}"                        # exit early on terminal pod/sync errors (CI)
BOOTSTRAP_PHASE="${BOOTSTRAP_PHASE:-all}"             # all | argocd | cluster-root | materialize | wait
WAIT_APP="${WAIT_APP:-}"                              # single app when BOOTSTRAP_PHASE=materialize|wait
CLUSTER_ROOT_AUTOMATED_SYNC="${CLUSTER_ROOT_AUTOMATED_SYNC:-true}"  # real clusters: cluster-root syncs children from Git

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
  log "Installing Argo CD (latest stable chart)"
  kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
  helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
  helm repo update argo

  helm upgrade --install argocd argo/argo-cd \
    --namespace argocd \
    --values "${REPO_ROOT}/hack/argocd/bootstrap-values.yaml" \
    --wait --timeout 10m

  kubectl -n argocd rollout status deploy/argocd-server --timeout=300s
  kubectl -n argocd rollout status deploy/argocd-repo-server --timeout=300s
  kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=300s 2>/dev/null \
    || kubectl -n argocd rollout status deploy/argocd-application-controller --timeout=300s
  log "Argo CD ready"
}

materialize_application() {
  local app="$1"
  log "Materializing Application CR: ${app} (gitops/clusters/${ENVIRONMENT})"
  local cluster_dir="${REPO_ROOT}/gitops/clusters/${ENVIRONMENT}"
  local build_dir
  build_dir="$(mktemp -d)"
  cp -a "${cluster_dir}/." "${build_dir}/"
  sed -i "s|^GITOPS_TARGET_REVISION=.*|GITOPS_TARGET_REVISION=${GITOPS_REVISION}|" "${build_dir}/cluster.env"
  sed -i "s|^GITOPS_REPO_URL=.*|GITOPS_REPO_URL=${GITOPS_REPO_URL}|" "${build_dir}/cluster.env"
  kustomize build "${build_dir}" | python3 -c '
import sys, yaml

target = sys.argv[1]
found = False
for doc in yaml.safe_load_all(sys.stdin):
    if doc and doc.get("kind") == "Application" and doc.get("metadata", {}).get("name") == target:
        yaml.dump(doc, sys.stdout, default_flow_style=False)
        found = True
if not found:
    sys.stderr.write(f"ERROR: Application {target!r} not found in kustomize build\n")
    sys.exit(1)
' "${app}" | kubectl apply -f -
  rm -rf "${build_dir}"
}

apply_cluster_root() {
  log "Registering cluster-root Application (gitops/clusters/${ENVIRONMENT})"
  local sync_policy=""
  if [[ "${CLUSTER_ROOT_AUTOMATED_SYNC}" == "true" ]]; then
    sync_policy="  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true"
  else
    log "cluster-root automated sync disabled"
    sync_policy="  syncPolicy:
    syncOptions:
      - CreateNamespace=true"
  fi
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
${sync_policy}
EOF
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

app_workload_ready() {
  local app="$1"
  case "${app}" in
    istio-gateway)
      local available
      available="$(kubectl -n istio-system get deploy istio-ingressgateway -o jsonpath='{.status.availableReplicas}' 2>/dev/null || echo 0)"
      [[ "${available:-0}" -ge 1 ]]
      ;;
    mtls-demo)
      local backend frontend
      backend="$(kubectl -n mtls-demo get deploy backend -o jsonpath='{.status.availableReplicas}' 2>/dev/null || echo 0)"
      frontend="$(kubectl -n mtls-demo get deploy frontend -o jsonpath='{.status.availableReplicas}' 2>/dev/null || echo 0)"
      [[ "${backend:-0}" -ge 1 && "${frontend:-0}" -ge 1 ]]
      ;;
    kubeship)
      local available
      available="$(kubectl -n kubeship get deploy kubeship-api -o jsonpath='{.status.availableReplicas}' 2>/dev/null || echo 0)"
      [[ "${available:-0}" -ge 1 ]]
      ;;
    *)
      return 1
      ;;
  esac
}

app_is_ready() {
  local app="$1"
  local sync health phase
  sync="$(kubectl -n argocd get application "${app}" -o jsonpath='{.status.sync.status}' 2>/dev/null || true)"
  health="$(kubectl -n argocd get application "${app}" -o jsonpath='{.status.health.status}' 2>/dev/null || true)"
  phase="$(kubectl -n argocd get application "${app}" -o jsonpath='{.status.operationState.phase}' 2>/dev/null || true)"
  local comparison_err
  comparison_err="$(kubectl -n argocd get application "${app}" -o jsonpath='{.status.conditions[?(@.type=="ComparisonError")].message}' 2>/dev/null || true)"

  if [[ -n "${comparison_err}" ]]; then
    return 1
  fi
  # Synced apps whose Argo health lags behind Deployment readiness (gateway, demo workloads).
  if [[ "${sync}" == "Synced" && "${phase}" == "Succeeded" ]] && app_workload_ready "${app}"; then
    return 0
  fi
  if [[ "${health}" != "Healthy" ]]; then
    return 1
  fi
  if [[ "${sync}" == "Synced" ]]; then
    return 0
  fi
  # Istio and other Helm charts may stay OutOfSync while Healthy (benign live diff).
  if [[ "${sync}" == "OutOfSync" && "${phase}" == "Succeeded" ]]; then
    return 0
  fi
  return 1
}

app_destination_namespace() {
  local app="$1"
  kubectl -n argocd get application "${app}" -o jsonpath='{.spec.destination.namespace}' 2>/dev/null || true
}

app_terminal_pod_failures() {
  local app="$1"
  local ns
  ns="$(app_destination_namespace "${app}")"
  [[ -n "${ns}" ]] || return 0
  kubectl get namespace "${ns}" >/dev/null 2>&1 || return 0

  kubectl get pods -n "${ns}" -o json 2>/dev/null | python3 -c "
import json, sys
terminal = {
    'ImagePullBackOff', 'ErrImagePull', 'CrashLoopBackOff',
    'CreateContainerConfigError', 'InvalidImageName',
}
data = json.load(sys.stdin)
lines = []
for pod in data.get('items', []):
    name = pod['metadata']['name']
    for label, statuses in (('container', pod.get('status', {}).get('containerStatuses')),
                            ('init', pod.get('status', {}).get('initContainerStatuses'))):
        for cs in statuses or []:
            waiting = (cs.get('state') or {}).get('waiting') or {}
            reason = waiting.get('reason')
            if reason in terminal:
                msg = waiting.get('message', '')[:160]
                cname = cs.get('name', '?')
                prefix = f'{name}/{cname}'
                if label == 'init':
                    prefix += ' (init)'
                lines.append(f'{prefix}: {reason} — {msg}')
if lines:
    print('\n'.join(lines))
" 2>/dev/null || true
}

app_permanent_sync_error() {
  local app="$1"
  local phase msg
  phase="$(kubectl -n argocd get application "${app}" -o jsonpath='{.status.operationState.phase}' 2>/dev/null || true)"
  msg="$(kubectl -n argocd get application "${app}" -o jsonpath='{.status.operationState.message}' 2>/dev/null || true)"

  if [[ "${phase}" == "Failed" && -n "${msg}" ]]; then
    printf '%s\n' "${msg}"
    return 0
  fi
  if [[ "${msg}" == *'not found'* ]]; then
    printf '%s\n' "${msg}"
    return 0
  fi
  return 1
}

fail_fast_if_broken() {
  local app="$1"
  [[ "${FAIL_FAST}" == "true" ]] || return 0

  local pod_issues sync_err
  pod_issues="$(app_terminal_pod_failures "${app}")"
  if [[ -n "${pod_issues}" ]]; then
    warn "Terminal pod failure for ${app} — failing fast (FAIL_FAST=true)"
    printf '%s\n' "${pod_issues}" >&2
    if [[ "${CI_POD_DIAGNOSTICS:-false}" == "true" ]]; then
      "${REPO_ROOT}/scripts/ci-pod-diagnostics.sh" "${app}" || true
    fi
    [[ "${STRICT_WAIT}" == "true" ]] && exit 1
    return 0
  fi

  sync_err="$(app_permanent_sync_error "${app}" || true)"
  if [[ -n "${sync_err}" ]]; then
    warn "Permanent Argo CD sync error for ${app} — failing fast (FAIL_FAST=true)"
    printf '%s\n' "${sync_err}" >&2
    if [[ "${CI_POD_DIAGNOSTICS:-false}" == "true" ]]; then
      "${REPO_ROOT}/scripts/ci-pod-diagnostics.sh" "${app}" || true
    fi
    [[ "${STRICT_WAIT}" == "true" ]] && exit 1
  fi
}

wait_for_single_app() {
  local app="$1"
  local timeout="${2:-${WAIT_TIMEOUT}}"
  log "Waiting for Application: ${app} (timeout ${timeout}s)"
  local deadline=$((SECONDS + timeout))

  while (( SECONDS < deadline )); do
    if kubectl -n argocd get application "${app}" >/dev/null 2>&1; then
      if app_is_ready "${app}"; then
        local sync health
        sync="$(kubectl -n argocd get application "${app}" -o jsonpath='{.status.sync.status}' 2>/dev/null || true)"
        health="$(kubectl -n argocd get application "${app}" -o jsonpath='{.status.health.status}' 2>/dev/null || true)"
        log "${app}: ready (sync=${sync} health=${health})"
        kubectl -n argocd get application "${app}" -o wide || true
        return 0
      fi
      app_status_line "${app}"
      fail_fast_if_broken "${app}"
    else
      app_status_line "${app}"
    fi
    sleep "${WAIT_POLL_INTERVAL:-5}"
  done

  warn "Timed out waiting for ${app}"
  log "Argo CD applications (debug)"
  kubectl -n argocd get applications -o wide || true
  if [[ "${CI_POD_DIAGNOSTICS:-false}" == "true" ]]; then
    log "Pod diagnostics for ${app} (CI_POD_DIAGNOSTICS=true)"
    "${REPO_ROOT}/scripts/ci-pod-diagnostics.sh" "${app}" || true
  fi
  if [[ "${STRICT_WAIT}" == "true" ]]; then
    exit 1
  fi
  return 0
}

wait_for_apps() {
  log "Waiting for core Applications (timeout ${WAIT_TIMEOUT}s each, materialize per wave)"
  local apps=(cert-manager platform-ca istio-base istio-csr istiod istio-gateway istio-policies mtls-demo)
  local app
  for app in "${apps[@]}"; do
    materialize_application "${app}"
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
  printf '\nSee docs/paths/local-dev.md and docs/operations/verify.md for next steps.\n'
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
    materialize)
      require_cmd kubectl
      require_cmd kustomize
      [[ -n "${WAIT_APP}" ]] || die "WAIT_APP is required when BOOTSTRAP_PHASE=materialize"
      materialize_application "${WAIT_APP}"
      ;;
    wait)
      require_cmd kubectl
      [[ -n "${WAIT_APP}" ]] || die "WAIT_APP is required when BOOTSTRAP_PHASE=wait"
      wait_for_single_app "${WAIT_APP}" "${WAIT_TIMEOUT}"
      ;;
    *)
      die "Unknown BOOTSTRAP_PHASE: ${BOOTSTRAP_PHASE} (use all|argocd|cluster-root|materialize|wait)"
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
