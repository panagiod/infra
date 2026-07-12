#!/usr/bin/env bash
# Option A — start the kind lab (Codespaces or local Docker). Bootstrap + verify in one command.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKIP_VERIFY="${SKIP_VERIFY:-false}"
CLUSTER_NAME="${CLUSTER_NAME:-infra-local}"

log() { printf '\n==> %s\n' "$*"; }

log "Starting platform lab (Option A)"
"${REPO_ROOT}/scripts/bootstrap-local.sh"

if [[ "${SKIP_VERIFY}" != "true" ]]; then
  log "Running platform health checks"
  LOCAL=true CLUSTER_NAME="${CLUSTER_NAME}" "${REPO_ROOT}/scripts/verify-platform.sh"
else
  log "Skipping verify (SKIP_VERIFY=true)"
fi

cat <<EOF

╔══════════════════════════════════════════════════════════════╗
║  Lab is running                                              ║
╠══════════════════════════════════════════════════════════════╣
║  Argo CD UI:                                                 ║
║    kubectl -n argocd port-forward svc/argocd-server 8080:80 ║
║    → Codespaces: Ports tab → localhost:8080                  ║
║                                                              ║
║  Re-verify:                                                  ║
║    LOCAL=true ./scripts/verify-platform.sh                   ║
║                                                              ║
║  Test your branch:                                           ║
║    GITOPS_REVISION=\$(git branch --show-current) \\           ║
║      RECREATE_CLUSTER=true ./scripts/bootstrap-local.sh      ║
║                                                              ║
║  Shutdown (save quota):                                      ║
║    STOP_CODESPACE=true ./scripts/shutdown-lab.sh             ║
╚══════════════════════════════════════════════════════════════╝

EOF
