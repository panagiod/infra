#!/usr/bin/env bash
# Tear down the kind lab and optionally stop the GitHub Codespace to save quota.
set -euo pipefail

STOP_CODESPACE="${STOP_CODESPACE:-false}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
log() { printf '\n==> %s\n' "$*"; }

log "Destroying kind cluster (if present)"
DESTROY=true "${REPO_ROOT}/scripts/bootstrap-local.sh" || true

# Free Docker disk inside the codespace
if command -v docker >/dev/null 2>&1; then
  log "Pruning unused Docker resources"
  docker system prune -f --volumes >/dev/null 2>&1 || true
fi

if [[ -n "${CODESPACE_NAME:-}" ]]; then
  log "Codespace: ${CODESPACE_NAME}"
  if [[ "${STOP_CODESPACE}" == "true" ]]; then
    if command -v gh >/dev/null 2>&1; then
      log "Stopping codespace to save quota"
      gh codespace stop -c "${CODESPACE_NAME}" || log "Could not stop via gh — use the Codespaces UI Stop button"
    else
      log "Install GitHub CLI or click Stop in the Codespaces UI"
    fi
  else
    log "To stop this codespace and save quota, run:"
    printf '  STOP_CODESPACE=true %s\n' "$0"
    printf '  Or: gh codespace stop -c %s\n' "${CODESPACE_NAME}"
  fi
else
  log "Not running inside a Codespace — kind cluster destroyed locally"
fi

log "Shutdown complete"
