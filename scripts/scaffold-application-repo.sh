#!/usr/bin/env bash
# Copy templates/application/ to a new directory and substitute app/repo placeholders.
set -euo pipefail

usage() {
  echo "Usage: $(basename "$0") <app-name> <target-directory> [github-owner/repo]" >&2
  echo "Example: $(basename "$0") myapp ../myapp panagiod/myapp" >&2
  exit 1
}

APP_NAME="${1:-}"
TARGET="${2:-}"
GH_REPO="${3:-}"

[[ -n "${APP_NAME}" && -n "${TARGET}" ]] || usage
[[ "${APP_NAME}" =~ ^[a-z][a-z0-9-]*$ ]] || {
  echo "ERROR: app-name must be lowercase alphanumeric with hyphens (DNS-1123)" >&2
  exit 1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEMPLATE="${REPO_ROOT}/templates/application"

[[ -d "${TEMPLATE}" ]] || {
  echo "ERROR: template not found at ${TEMPLATE}" >&2
  exit 1
}

if [[ -e "${TARGET}" ]]; then
  echo "ERROR: target already exists: ${TARGET}" >&2
  exit 1
fi

if [[ -z "${GH_REPO}" ]]; then
  GH_REPO="OWNER/${APP_NAME}"
fi

IMAGE="ghcr.io/${GH_REPO}"

mkdir -p "${TARGET}"
cp -a "${TEMPLATE}/." "${TARGET}/"

# Replace placeholders in all text files (skip .git if ever present).
while IFS= read -r -d '' file; do
  if file -b --mime-type "${file}" | grep -q '^text/'; then
  sed -i \
    -e "s/myapp/${APP_NAME}/g" \
    -e "s|ghcr.io/OWNER/REPO|${IMAGE}|g" \
    -e "s|OWNER/REPO|${GH_REPO}|g" \
    "${file}"
  fi
done < <(find "${TARGET}" -type f -print0)

cat <<EOF

Scaffolded application repo at: ${TARGET}

Next steps:
  cd ${TARGET}
  git init
  git add .
  git commit -m "chore: scaffold ${APP_NAME} from infra template"
  gh repo create ${GH_REPO} --private --source=. --push

After first release tag (v0.1.0):
  - Update deploy/overlays/staging/kustomization.yaml image tag
  - Add Argo CD Application in infra (see docs/applications/application-project.md)

EOF
