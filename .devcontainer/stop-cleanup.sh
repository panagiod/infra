#!/usr/bin/env bash
# Runs when a Codespace stops (idle timeout or manual Stop) — frees kind/Docker resources.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -x "${REPO_ROOT}/scripts/shutdown-lab.sh" ]]; then
  "${REPO_ROOT}/scripts/shutdown-lab.sh" || true
fi
