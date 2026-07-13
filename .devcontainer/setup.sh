#!/usr/bin/env bash
# Post-create setup for GitHub Codespaces — installs kind and prints next steps.
set -euo pipefail

log() { printf '==> %s\n' "$*"; }

log "Installing kind (Kubernetes in Docker)"
KIND_VERSION="$(curl -fsSL https://api.github.com/repos/kubernetes-sigs/kind/releases/latest | grep '"tag_name"' | head -1 | sed -E 's/.*"v([^"]+)".*/\1/')"
curl -fsSL "https://kind.sigs.k8s.io/dl/v${KIND_VERSION}/kind-linux-amd64" -o /usr/local/bin/kind
chmod +x /usr/local/bin/kind
kind version

log "Installing kustomize"
KUSTOMIZE_VERSION="$(curl -fsSL https://api.github.com/repos/kubernetes-sigs/kustomize/releases/latest | grep '"tag_name"' | head -1 | sed -E 's/.*kustomize\/v?([^"]+)".*/\1/')"
curl -fsSL "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE_VERSION}/kustomize_v${KUSTOMIZE_VERSION}_linux_amd64.tar.gz" | tar xz -C /usr/local/bin
kustomize version

cat <<'EOF'

╔══════════════════════════════════════════════════════════════╗
║  infra platform — Codespaces lab ready                       ║
╠══════════════════════════════════════════════════════════════╣
║  Start lab (Option A — bootstrap + verify):                    ║
║    ./scripts/start-lab.sh                                    ║
║                                                              ║
║  CI checks before push (Option B):                           ║
║    ./scripts/ci-validate.sh                                  ║
║                                                              ║
║  Argo CD UI (after bootstrap):                               ║
║    kubectl -n argocd port-forward svc/argocd-server 8080:80 ║
║    → Ports tab → open localhost:8080                         ║
║                                                              ║
║  Shutdown (save quota):                                      ║
║    STOP_CODESPACE=true ./scripts/shutdown-lab.sh             ║
║    Auto: 15 min idle stop · 2 h max open (devcontainer)      ║
║                                                              ║
║  Docs: docs/paths/codespaces.md · docs/paths/ci-only.md                  ║
╚══════════════════════════════════════════════════════════════╝

EOF
