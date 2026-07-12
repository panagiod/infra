#!/usr/bin/env bash
# Wait for one Argo CD Application: materialize CR then wait (Kind smoke waves).
set -euo pipefail

APP="${1:?Usage: wait-for-app.sh <application-name>}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export WAIT_APP="${APP}"
export STRICT_WAIT="${STRICT_WAIT:-true}"

BOOTSTRAP_PHASE=materialize "${REPO_ROOT}/scripts/bootstrap-local.sh"
export BOOTSTRAP_PHASE=wait
exec "${REPO_ROOT}/scripts/bootstrap-local.sh"
