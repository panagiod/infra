#!/usr/bin/env bash
# Run everything from the Cursor Cloud Agent (or any machine without Docker).
# Local when possible; otherwise triggers GitHub Actions remotely.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CMD="${1:-help}"
shift || true

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

require_gh() {
  command -v gh >/dev/null 2>&1 || die "GitHub CLI (gh) required — authenticate with: gh auth login"
  gh auth status >/dev/null 2>&1 || die "gh not authenticated — run: gh auth login"
}

current_branch() {
  git -C "${REPO_ROOT}" branch --show-current
}

has_docker() {
  command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1
}

cmd_check() {
  local mode="${1:-local}"
  case "${mode}" in
    local)
      log "Running CI checks locally (Option B)"
      "${REPO_ROOT}/scripts/ci-validate.sh"
      ;;
    remote)
      require_gh
      local branch="${2:-$(current_branch)}"
      log "Triggering GitOps + Terraform workflows on branch: ${branch}"
      gh workflow run gitops.yml --ref "${branch}"
      gh workflow run terraform.yml --ref "${branch}"
      log "Watching latest runs (Ctrl+C to stop watching — workflows continue)"
      sleep 3
      cmd_status "${branch}"
      ;;
    *)
      die "Usage: from-here.sh check [local|remote] [branch]"
      ;;
  esac
}

cmd_lab() {
  if has_docker; then
    log "Docker available — starting local lab (Option A)"
    "${REPO_ROOT}/scripts/start-lab.sh"
    return 0
  fi

  require_gh
  local branch="${1:-$(current_branch)}"
  log "No Docker here — running remote kind lab via GitHub Actions"
  log "Branch: ${branch} (this is your cloud substitute for start-lab.sh)"
  gh workflow run kind-smoke.yml --ref "${branch}" -f "gitops_revision=${branch}"
  log "Waiting for Kind smoke workflow..."
  sleep 5
  local run_id
  run_id="$(gh run list --workflow=kind-smoke.yml --branch="${branch}" --limit=1 --json databaseId -q '.[0].databaseId')"
  [[ -n "${run_id}" && "${run_id}" != "null" ]] || die "Could not find workflow run — check: gh run list --workflow=kind-smoke.yml"
  gh run watch "${run_id}" --exit-status
  log "Remote lab smoke test passed"
}

cmd_shutdown() {
  if has_docker; then
    STOP_CODESPACE="${STOP_CODESPACE:-false}" "${REPO_ROOT}/scripts/shutdown-lab.sh"
    return 0
  fi
  log "No local cluster to shut down in this environment"
  log "GitHub Actions runners are ephemeral — nothing to stop after CI finishes"
  if [[ -n "${CODESPACE_NAME:-}" ]]; then
    STOP_CODESPACE=true "${REPO_ROOT}/scripts/shutdown-lab.sh"
  else
    log "If you have a Codespace running elsewhere: STOP_CODESPACE=true ./scripts/shutdown-lab.sh"
  fi
}

cmd_status() {
  require_gh
  local branch="${1:-$(current_branch)}"
  log "Branch: ${branch}"
  if gh pr view "${branch}" >/dev/null 2>&1; then
    gh pr view "${branch}" --json url,state,statusCheckRollup --jq '"PR: \(.url) (\(.state))\nChecks:\n" + (.statusCheckRollup[]? | "  \(.name): \(.state // .conclusion // "pending")")'
  else
    log "No open PR for current branch"
  fi
  log "Recent workflow runs:"
  gh run list --branch="${branch}" --limit=8
}

cmd_push() {
  require_gh
  local branch="${1:-$(current_branch)}"
  log "Pushing ${branch}"
  git -C "${REPO_ROOT}" push -u origin "${branch}"
  if gh pr view "${branch}" >/dev/null 2>&1; then
    log "PR already exists"
    gh pr view "${branch}" --web 2>/dev/null || gh pr view "${branch}"
  else
    log "Creating pull request"
    gh pr create --head "${branch}" --base main --fill
  fi
  cmd_status "${branch}"
}

cmd_help() {
  cat <<'EOF'
from-here.sh — run platform tasks from the Cursor Cloud Agent

This environment has no Docker, so "lab" runs Kind smoke in GitHub Actions instead.
You ask the agent; the agent runs these commands for you.

Usage:
  ./scripts/from-here.sh check [local|remote] [branch]   CI validation
  ./scripts/from-here.sh lab [branch]                    Local kind OR remote Kind smoke
  ./scripts/from-here.sh status [branch]                 PR checks + recent runs
  ./scripts/from-here.sh push [branch]                   git push + open/update PR
  ./scripts/from-here.sh shutdown                          Tear down local lab if any

Examples (agent runs these for you):
  ./scripts/from-here.sh check local
  ./scripts/from-here.sh lab
  ./scripts/from-here.sh push

Docs: docs/cloud-agent.md
EOF
}

case "${CMD}" in
  check) cmd_check "$@" ;;
  lab) cmd_lab "$@" ;;
  shutdown) cmd_shutdown "$@" ;;
  status) cmd_status "$@" ;;
  push) cmd_push "$@" ;;
  help|-h|--help) cmd_help ;;
  *) die "Unknown command: ${CMD}. Run: from-here.sh help" ;;
esac
