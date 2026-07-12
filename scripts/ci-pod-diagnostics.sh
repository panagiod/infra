#!/usr/bin/env bash
# Dump workload diagnostics when an Argo CD Application wait times out (Kind smoke / CI).
# Invoked from bootstrap-local.sh on wait timeout when CI_POD_DIAGNOSTICS=true.
set -euo pipefail

APP="${1:-}"
[[ -n "${APP}" ]] || {
  echo "Usage: ci-pod-diagnostics.sh <argo-application-name>" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "WARN: missing ${1}; skipping some diagnostics" >&2
    return 1
  }
}

section() { printf '\n========== %s ==========\n' "$*"; }

dump_namespace() {
  local ns="$1"
  section "Namespace ${ns}: pods"
  kubectl get pods -n "${ns}" -o wide 2>/dev/null || true
  section "Namespace ${ns}: deployments"
  kubectl get deploy -n "${ns}" -o wide 2>/dev/null || true
  section "Namespace ${ns}: events (last 40)"
  kubectl get events -n "${ns}" --sort-by='.lastTimestamp' 2>/dev/null | tail -40 || true

  local pod
  while IFS= read -r pod; do
    [[ -n "${pod}" ]] || continue
    section "Pod describe: ${ns}/${pod}"
    kubectl describe pod -n "${ns}" "${pod}" 2>/dev/null || true
    local containers
    containers="$(kubectl get pod -n "${ns}" "${pod}" -o jsonpath='{.spec.containers[*].name}' 2>/dev/null || true)"
    for c in ${containers}; do
      section "Logs: ${ns}/${pod} container=${c} (tail 120)"
      kubectl logs -n "${ns}" "${pod}" -c "${c}" --tail=120 2>/dev/null \
        || kubectl logs -n "${ns}" "${pod}" -c "${c}" --previous --tail=120 2>/dev/null \
        || echo "(no logs for ${c})"
    done
  done < <(kubectl get pods -n "${ns}" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null \
    | grep -v '^$' || true)
}

dump_workload() {
  local ns="$1" kind="$2" name="$3"
  section "Workload: ${ns}/${kind}/${name}"
  kubectl get "${kind}" -n "${ns}" "${name}" -o wide 2>/dev/null || true
  kubectl describe "${kind}" -n "${ns}" "${name}" 2>/dev/null || true
}

main() {
  require_cmd kubectl || exit 0

  section "Argo CD Application: ${APP}"
  kubectl -n argocd get application "${APP}" -o wide 2>/dev/null || true
  kubectl -n argocd get application "${APP}" -o yaml 2>/dev/null || true

  local dest_ns
  dest_ns="$(kubectl -n argocd get application "${APP}" -o jsonpath='{.spec.destination.namespace}' 2>/dev/null || true)"
  if [[ -n "${dest_ns}" ]]; then
    dump_namespace "${dest_ns}"
  fi

  case "${APP}" in
    cert-manager)
      dump_workload cert-manager deploy cert-manager
      dump_workload cert-manager deploy cert-manager-webhook
      dump_workload cert-manager deploy cert-manager-cainjector
      ;;
    platform-ca)
      kubectl get clusterissuer,issuer,certificate,certificaterequest -A 2>/dev/null || true
      ;;
    istio-csr)
      dump_workload cert-manager deploy cert-manager-istio-csr 2>/dev/null || true
      dump_workload cert-manager deploy istio-csr 2>/dev/null || true
      kubectl get certificate,certificaterequest,secret -n istio-system 2>/dev/null \
        | grep -E 'istiod|istio-ca|NAME' || true
      ;;
    istiod)
      dump_workload istio-system deploy istiod
      kubectl get secret istiod-tls -n istio-system -o yaml 2>/dev/null | head -30 || true
      kubectl get configmap istio-ca-root-cert -n istio-system -o yaml 2>/dev/null | head -30 || true
      ;;
    istio-gateway)
      dump_workload istio-system deploy istio-ingressgateway
      ;;
    istio-base|istio-policies|istio-ingress-tls|monitoring|monitoring-alerts|kyverno|platform-policies|mtls-demo|myapp)
      ;;
  esac

  section "Argo CD Application resources (status)"
  kubectl -n argocd get application "${APP}" -o jsonpath='{range .status.resources[*]}{.kind}/{.namespace}/{.name} health={.health.status} sync={.status}{"\n"}{end}' 2>/dev/null || true
}

main "$@"
