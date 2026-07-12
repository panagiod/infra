#!/usr/bin/env bash
# Wait for one Argo CD Application to reach Synced + Healthy (used by CI steps).
set -euo pipefail

APP="${1:?Usage: wait-for-app.sh <application-name>}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export BOOTSTRAP_PHASE=wait
export WAIT_APP="${APP}"
export STRICT_WAIT="${STRICT_WAIT:-true}"
exec "${REPO_ROOT}/scripts/bootstrap-local.sh"
