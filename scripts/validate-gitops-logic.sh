#!/usr/bin/env bash
# Logical validation of GitOps app-of-apps: structure, no Application sync-waves, no Helm pins.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV="${1:-staging}"
APPS_FILE="${REPO_ROOT}/gitops/clusters/${ENV}/applications.yaml"

# Expected bootstrap order — enforced by Kind smoke wait steps, not Argo CD dependsOn.
EXPECTED_ORDER=(
  cert-manager platform-ca istio-base istiod istio-csr istio-gateway
  istio-ingress-tls istio-policies monitoring monitoring-alerts
  kyverno platform-policies mtls-demo
)

log() { printf '==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing: $1"
}

log "Validating GitOps logic for cluster: ${ENV}"

require_cmd python3
require_cmd kustomize

log "kustomize build gitops/clusters/${ENV}"
kustomize build "${REPO_ROOT}/gitops/clusters/${ENV}" >/dev/null

python3 - "${APPS_FILE}" <<'PY'
import sys, yaml

path = sys.argv[1]
with open(path) as f:
    docs = list(yaml.safe_load_all(f))

apps = [d for d in docs if d and d.get('kind') == 'Application']
names = {d['metadata']['name'] for d in apps}

errors = []
for d in apps:
    name = d['metadata']['name']
    ann = d.get('metadata', {}).get('annotations') or {}
    if 'argocd.argoproj.io/sync-wave' in ann:
        errors.append(f'{name}: must not use sync-wave on Application CR (use Kind smoke wait order)')
    src = d.get('spec', {}).get('source', {})
    tr = src.get('targetRevision')
    if src.get('chart') and tr and tr not in ('*', 'x'):
        errors.append(f'{name}: Helm chart {src["chart"]} must use targetRevision * or x for latest stable, not pin {tr!r} (.cursor/rules/dependencies.mdc)')
    if src.get('chart') and not tr:
        errors.append(f'{name}: Helm chart {src["chart"]} must set targetRevision: \'*\' (Argo CD requires explicit latest wildcard)')
    if d.get('spec', {}).get('dependsOn'):
        errors.append(f'{name}: must not use spec.dependsOn (not supported on Application CRD; use Kind smoke wait order)')

if errors:
    print('VALIDATION FAILED:')
    for e in errors:
        print(f'  - {e}')
    sys.exit(1)

print(f'OK: {len(apps)} Applications, no sync-waves or dependsOn on Application CRs')
PY

# Verify Application manifest order matches the Kind smoke wait sequence.
mapfile -t manifest_order < <(python3 - "${APPS_FILE}" <<'PY'
import sys, yaml
with open(sys.argv[1]) as f:
    for doc in yaml.safe_load_all(f):
        if doc and doc.get('kind') == 'Application':
            print(doc['metadata']['name'])
PY
)

if ((${#manifest_order[@]} != ${#EXPECTED_ORDER[@]})); then
  die "applications.yaml has ${#manifest_order[@]} apps; expected ${#EXPECTED_ORDER[@]}"
fi

for i in "${!EXPECTED_ORDER[@]}"; do
  if [[ "${manifest_order[$i]}" != "${EXPECTED_ORDER[$i]}" ]]; then
    die "applications.yaml order mismatch at position $((i + 1)): got ${manifest_order[$i]!r}, want ${EXPECTED_ORDER[$i]!r}"
  fi
done

log "Install order matches Kind smoke wait sequence (${#EXPECTED_ORDER[@]} apps)"
log "Logical validation passed for ${ENV}"
