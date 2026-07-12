#!/usr/bin/env bash
# Short reminder when you open/reconnect to the Codespace (Option A).
set -euo pipefail

if [[ -n "${CODESPACE_NAME:-}" ]]; then
  cat <<'EOF'

Codespaces lab (Option A) — quick commands:
  ./scripts/start-lab.sh              # bootstrap + verify
  STOP_CODESPACE=true ./scripts/shutdown-lab.sh   # save quota

CI checks before push (Option B):
  ./scripts/ci-validate.sh

Docs: docs/getting-started.md · docs/ci-only.md

EOF
fi
