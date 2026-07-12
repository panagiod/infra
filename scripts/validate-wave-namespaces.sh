#!/usr/bin/env bash
# Validate that no Application references a namespace before it is created in bootstrap order.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENVIRONMENT="${ENVIRONMENT:-staging}"
RENDER_DIR="${RENDER_DIR:-}"

log() { printf '==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

install_tools() {
  # shellcheck source=scripts/ci-install-tools.sh
  source "${REPO_ROOT}/scripts/ci-install-tools.sh"
  require_cmd python3
  if ! python3 -c 'import yaml' 2>/dev/null; then
    die "Missing python3 PyYAML (pip install pyyaml)"
  fi
  ci_install_helm
  ci_install_kustomize
  require_cmd helm
  require_cmd kustomize
}

main() {
  install_tools

  local workdir="${RENDER_DIR}"
  local cleanup=0
  if [[ -z "${workdir}" ]]; then
    workdir="$(mktemp -d)"
    cleanup=1
    log "Rendering GitOps manifests (${ENVIRONMENT})"
    python3 "${REPO_ROOT}/scripts/ci_render_gitops.py" \
      --env "${ENVIRONMENT}" \
      --output "${workdir}"
  fi

  log "Checking namespace references vs bootstrap order (${ENVIRONMENT})"
  if ! python3 - "${workdir}" "${REPO_ROOT}/gitops/clusters/${ENVIRONMENT}/applications.yaml" \
    "${REPO_ROOT}/scripts/gitops-install-order.sh" <<'PY'; then
import sys
from pathlib import Path
import yaml

render_dir = Path(sys.argv[1])
apps_file = Path(sys.argv[2])
order_file = Path(sys.argv[3])

order: list[str] = []
in_array = False
for line in order_file.read_text(encoding="utf-8").splitlines():
    if "GITOPS_INSTALL_ORDER=(" in line:
        in_array = True
        continue
    if in_array:
        stripped = line.strip()
        if stripped == ")":
            break
        if stripped and not stripped.startswith("#"):
            order.append(stripped)

apps: dict[str, dict] = {}
with apps_file.open(encoding="utf-8") as fh:
    for doc in yaml.safe_load_all(fh):
        if doc and doc.get("kind") == "Application":
            apps[doc["metadata"]["name"]] = doc

CLUSTER_SCOPED = {
    "ClusterRole", "ClusterRoleBinding", "CustomResourceDefinition", "Namespace",
    "ClusterIssuer", "ClusterPolicy", "ClusterRole", "MutatingWebhookConfiguration",
    "ValidatingWebhookConfiguration", "PriorityClass", "RuntimeClass", "CSIDriver",
    "PersistentVolume", "StorageClass", "IngressClass",
}
PREEXISTING = {
    "default", "kube-system", "kube-public", "kube-node-lease", "argocd", "metallb-system",
}

created_by: dict[str, str] = {}
errors: list[str] = []

for idx, app_name in enumerate(order):
    app = apps[app_name]
    sync_opts = (app.get("spec", {}).get("syncPolicy") or {}).get("syncOptions") or []
    dest_ns = (app.get("spec", {}).get("destination") or {}).get("namespace")
    if dest_ns and "CreateNamespace=true" in sync_opts and dest_ns not in created_by:
        created_by[dest_ns] = app_name

    manifest = render_dir / f"{app_name}.yaml"
    if not manifest.is_file():
        errors.append(f"{app_name}: missing rendered manifest {manifest.name}")
        continue

    with manifest.open(encoding="utf-8") as fh:
        for doc in yaml.safe_load_all(fh):
            if not doc or not isinstance(doc, dict):
                continue
            kind = doc.get("kind")
            meta = doc.get("metadata") or {}
            if kind == "Namespace":
                ns_name = meta.get("name")
                if ns_name and ns_name not in created_by:
                    created_by[ns_name] = app_name
            ref_ns = meta.get("namespace")
            if not ref_ns or kind in CLUSTER_SCOPED or ref_ns in PREEXISTING:
                continue
            creator = created_by.get(ref_ns)
            if creator is None:
                continue  # provisioned outside app-of-apps (e.g. Argo CD)
            if order.index(creator) > idx:
                errors.append(
                    f"{app_name} (wave {idx + 1}) references namespace {ref_ns!r} "
                    f"created by {creator} (wave {order.index(creator) + 1}): "
                    f"{kind}/{ref_ns}/{meta.get('name')}"
                )

if errors:
    print("NAMESPACE ORDER VALIDATION FAILED:", file=sys.stderr)
    for err in errors:
        print(f"  - {err}", file=sys.stderr)
    sys.exit(1)

print(f"OK: namespace references respect bootstrap order ({len(order)} apps)")
PY
    die "Namespace order validation failed"
  fi

  [[ "${cleanup}" -eq 0 ]] || rm -rf "${workdir}"
  log "Namespace order validation passed for ${ENVIRONMENT}"
}

main "$@"
