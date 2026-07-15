#!/usr/bin/env bash
# Run kube-bench CIS benchmark as a one-shot Job (kind, EKS, or AKS).
# Does not fail the shell by default — review logs for [FAIL] lines.
#
# Usage:
#   ./scripts/run-kube-bench.sh
#   KUBE_BENCH_BENCHMARK=eks-1.7 ./scripts/run-kube-bench.sh
#   RUN_KUBE_BENCH=true ./scripts/verify-platform.sh  # optional hook
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="${KUBE_BENCH_NAMESPACE:-kube-system}"
JOB_NAME="${KUBE_BENCH_JOB_NAME:-kube-bench}"
TIMEOUT="${KUBE_BENCH_TIMEOUT:-300}"

detect_benchmark() {
  if [[ -n "${KUBE_BENCH_BENCHMARK:-}" ]]; then
    printf '%s' "${KUBE_BENCH_BENCHMARK}"
    return
  fi
  local ctx
  ctx="$(kubectl config current-context 2>/dev/null || true)"
  case "${ctx}" in
    kind-*)
      printf 'k8s-1.23'
      ;;
    *eks*|*EKS*)
      printf 'eks-1.7'
      ;;
    *aks*|*AKS*)
      printf 'aks-1.7'
      ;;
    *)
      printf 'k8s-1.23'
      ;;
  esac
}

main() {
  command -v kubectl >/dev/null 2>&1 || {
    echo "kubectl required" >&2
    exit 1
  }

  local benchmark rendered
  benchmark="$(detect_benchmark)"
  echo "==> kube-bench benchmark: ${benchmark}"

  kubectl -n "${NAMESPACE}" delete job "${JOB_NAME}" --ignore-not-found=true >/dev/null 2>&1 || true
  rendered="$(sed "s/BENCHMARK/${benchmark}/g" "${REPO_ROOT}/hack/security/kube-bench-job.yaml.tpl")"
  printf '%s\n' "${rendered}" | kubectl apply -f -

  echo "==> Waiting for Job/${JOB_NAME} (timeout ${TIMEOUT}s)"
  if ! kubectl -n "${NAMESPACE}" wait --for=condition=complete "job/${JOB_NAME}" --timeout="${TIMEOUT}s"; then
    echo "WARN: kube-bench job did not complete in time" >&2
    kubectl -n "${NAMESPACE}" logs "job/${JOB_NAME}" 2>/dev/null || true
    return 1
  fi

  echo "==> kube-bench report"
  kubectl -n "${NAMESPACE}" logs "job/${JOB_NAME}"
  echo "==> Done (search logs for [FAIL] to find gaps)"
}

main "$@"
