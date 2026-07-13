#!/usr/bin/env bash
# One-time setup for the infra GitHub Project board.
# Requires: gh CLI authenticated as repo owner with project scope.
#
#   gh auth refresh -s project,read:project
#   ./scripts/setup-github-project.sh
set -euo pipefail

REPO="${GITHUB_REPOSITORY:-panagiod/infra}"
OWNER="${REPO%%/*}"
PROJECT_TITLE="infra — Phase 1"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

require_cmd gh
require_cmd python3

if ! gh auth status >/dev/null 2>&1; then
  echo "Run: gh auth login" >&2
  exit 1
fi

log() { printf '==> %s\n' "$*"; }

resolve_project() {
  python3 - "${OWNER}" "${PROJECT_TITLE}" <<'PY'
import json, subprocess, sys

owner, title = sys.argv[1], sys.argv[2]

def projects():
    out = subprocess.check_output(
        ["gh", "project", "list", "--owner", owner, "--format", "json"],
        text=True,
    )
    data = json.loads(out)
    if isinstance(data, list):
        return data
    return data.get("projects", [])

for p in projects():
    if p.get("title") == title:
        print(json.dumps({"number": p["number"], "url": p["url"]}))
        sys.exit(0)

created = subprocess.check_output(
    ["gh", "project", "create", "--owner", owner, "--title", title, "--format", "json"],
    text=True,
)
print(created.strip())
PY
}

log "Resolving or creating project"
PROJECT_JSON="$(resolve_project || true)"
if [[ -z "${PROJECT_JSON}" ]]; then
  echo "Could not create or find project. Run: gh auth refresh -s project,read:project" >&2
  exit 1
fi

PROJECT_NUMBER="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["number"])' <<<"${PROJECT_JSON}")"
PROJECT_URL="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["url"])' <<<"${PROJECT_JSON}")"
log "Project #${PROJECT_NUMBER}: ${PROJECT_URL}"

log "Linking repository to project"
gh project link "${PROJECT_NUMBER}" --owner "${OWNER}" --repo "${REPO}" 2>/dev/null || true

log "Adding open issues and PRs"
while IFS= read -r url; do
  [[ -n "${url}" ]] || continue
  gh project item-add "${PROJECT_NUMBER}" --owner "${OWNER}" --url "${url}" 2>/dev/null || true
done < <(
  gh issue list --repo "${REPO}" --state open --json url --jq '.[].url'
  gh pr list --repo "${REPO}" --state open --json url --jq '.[].url'
)

log "Done. Open the board:"
printf '  %s\n' "${PROJECT_URL}"
printf '\nRe-sync issues from backlog anytime:\n'
printf '  gh workflow run sync-project-backlog.yml --repo %s\n' "${REPO}"
