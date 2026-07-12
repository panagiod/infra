#!/usr/bin/env bash
# Logical validation of GitOps app-of-apps: structure, dependsOn graph, no Application sync-waves.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV="${1:-staging}"
APPS_FILE="${REPO_ROOT}/gitops/clusters/${ENV}/applications.yaml"

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
waves = []
for d in apps:
    name = d['metadata']['name']
    ann = d.get('metadata', {}).get('annotations') or {}
    if 'argocd.argoproj.io/sync-wave' in ann:
        errors.append(f'{name}: must not use sync-wave on Application CR (use dependsOn)')
    src = d.get('spec', {}).get('source', {})
    if src.get('chart') and not src.get('targetRevision'):
        errors.append(f'{name}: Helm chart {src["chart"]} missing targetRevision pin')
    for dep in d.get('spec', {}).get('dependsOn') or []:
        dep_name = dep.get('name')
        if dep_name not in names:
            errors.append(f'{name}: dependsOn unknown app {dep_name!r}')
    waves.append(name)

# Topological order (dependsOn)
order, seen, visiting = [], set(), set()

def visit(n):
    if n in seen:
        return
    if n in visiting:
        raise SystemExit(f'ERROR: cycle involving {n}')
    visiting.add(n)
    doc = next(d for d in apps if d['metadata']['name'] == n)
    for dep in doc.get('spec', {}).get('dependsOn') or []:
        visit(dep['name'])
    visiting.remove(n)
    seen.add(n)
    order.append(n)

for n in waves:
    visit(n)

if errors:
    print('VALIDATION FAILED:')
    for e in errors:
        print(f'  - {e}')
    sys.exit(1)

print(f'OK: {len(apps)} Applications, no sync-waves on Application CRs')
print('Install order (dependsOn topological sort):')
for i, n in enumerate(order, 1):
    deps = [d['name'] for d in next(d for d in apps if d['metadata']['name'] == n).get('spec', {}).get('dependsOn') or []]
    dep_txt = f" (after: {', '.join(deps)})" if deps else ''
    print(f'  {i:2}. {n}{dep_txt}')
PY

log "Logical validation passed for ${ENV}"
