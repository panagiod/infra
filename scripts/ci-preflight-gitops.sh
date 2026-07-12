#!/usr/bin/env bash
# Run all fast GitOps preflight checks (render once, validate many ways).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENVIRONMENT="${ENVIRONMENT:-staging}"
RENDER_DIR="$(mktemp -d)"

cleanup() { rm -rf "${RENDER_DIR}"; }
trap cleanup EXIT

export RENDER_DIR ENVIRONMENT

log() { printf '\n==> %s\n' "$*"; }

log "Rendering manifests once for preflight (${ENVIRONMENT})"
python3 "${REPO_ROOT}/scripts/ci_render_gitops.py" \
  --env "${ENVIRONMENT}" \
  --output "${RENDER_DIR}" \
  --include-bootstrap \
  --include-metallb

log "Wave-order namespace validation"
"${REPO_ROOT}/scripts/validate-wave-namespaces.sh"

log "Container image registry validation"
"${REPO_ROOT}/scripts/ci-check-images.sh"

log "kubeconform schema validation"
"${REPO_ROOT}/scripts/ci-kubeconform.sh"

log "All GitOps preflight checks passed"
