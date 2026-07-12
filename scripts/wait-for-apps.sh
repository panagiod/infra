#!/usr/bin/env bash
# Wait for multiple Argo CD Applications in parallel (Kind smoke dependency waves).
set -euo pipefail

[[ $# -ge 1 ]] || {
  echo "Usage: wait-for-apps.sh <application-name> [...]" >&2
  exit 1
}

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STRICT_WAIT="${STRICT_WAIT:-true}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-900}"

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

declare -a apps=()
for app in "$@"; do
  apps+=("${app}")
done

wait_one() {
  local app="$1"
  local logfile="${tmpdir}/${app}.log"
  local rcfile="${tmpdir}/${app}.rc"
  if BOOTSTRAP_PHASE=wait WAIT_APP="${app}" STRICT_WAIT="${STRICT_WAIT}" WAIT_TIMEOUT="${WAIT_TIMEOUT}" \
    "${REPO_ROOT}/scripts/bootstrap-local.sh" >"${logfile}" 2>&1; then
    echo 0 >"${rcfile}"
  else
    echo 1 >"${rcfile}"
  fi
}

log "Waiting for Applications in parallel (${#apps[@]}): ${apps[*]} (timeout ${WAIT_TIMEOUT}s each)"

for app in "${apps[@]}"; do
  BOOTSTRAP_PHASE=materialize WAIT_APP="${app}" "${REPO_ROOT}/scripts/bootstrap-local.sh"
done

declare -a pids=()
for app in "${apps[@]}"; do
  wait_one "${app}" &
  pids+=($!)
done

failed_apps=()
for i in "${!pids[@]}"; do
  wait "${pids[$i]}" || true
  app="${apps[$i]}"
  if [[ "$(cat "${tmpdir}/${app}.rc")" -ne 0 ]]; then
    failed_apps+=("${app}")
    printf '\n--- %s failed ---\n' "${app}"
    cat "${tmpdir}/${app}.log"
  fi
done

if ((${#failed_apps[@]} > 0)); then
  die "Application(s) not ready: ${failed_apps[*]}"
fi

log "All Applications ready: ${apps[*]}"
