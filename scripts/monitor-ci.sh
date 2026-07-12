#!/usr/bin/env bash
# Monitor PR CI until green or failure — used by Cloud Agent monitor/fix loop.
set -euo pipefail

BRANCH="${1:-$(git branch --show-current)}"
PR="${2:-}"
MAX_MINUTES="${MAX_MINUTES:-120}"

log() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

if [[ -z "${PR}" ]]; then
  PR="$(gh pr view "${BRANCH}" --json number -q .number 2>/dev/null || true)"
fi
[[ -n "${PR}" ]] || die "No PR found for branch ${BRANCH}"

log "Monitoring PR #${PR} (branch ${BRANCH}) for up to ${MAX_MINUTES}m"

deadline=$((SECONDS + MAX_MINUTES * 60))
last_smoke=""

while (( SECONDS < deadline )); do
  # PR checks summary
  if gh pr checks "${PR}" 2>/dev/null | grep -qE '^smoke\s+fail'; then
    log "Kind smoke FAILED"
    run_id="$(gh run list --branch="${BRANCH}" --workflow=kind-smoke.yml --limit=1 --json databaseId -q '.[0].databaseId')"
    log "Run: https://github.com/panagiod/infra/actions/runs/${run_id}"
    gh run view "${run_id}" --json jobs --jq '.jobs[0].steps[] | select(.conclusion=="failure") | .name' 2>/dev/null || true
    exit 2
  fi

  if gh pr checks "${PR}" 2>/dev/null | grep -qE '^smoke\s+pass'; then
    if gh pr checks "${PR}" 2>/dev/null | grep -qE 'fail'; then
      log "Smoke passed but other checks failed"
      gh pr checks "${PR}" 2>/dev/null | grep fail || true
      exit 2
    fi
    log "ALL CHECKS GREEN on PR #${PR}"
    gh pr checks "${PR}" 2>/dev/null
    exit 0
  fi

  smoke_status="$(gh pr checks "${PR}" 2>/dev/null | awk '/^smoke/{print $2}' | head -1 || true)"
  run_id="$(gh run list --branch="${BRANCH}" --workflow=kind-smoke.yml --limit=1 --json databaseId -q '.[0].databaseId' 2>/dev/null || true)"

  step=""
  if [[ -n "${run_id}" && "${run_id}" != "null" ]]; then
    step="$(gh run view "${run_id}" --json jobs --jq '.jobs[0].steps[] | select(.status=="in_progress") | .name' 2>/dev/null | head -1 || true)"
  fi
  progress="${smoke_status:-pending} | ${step:-starting...}"
  if [[ "${progress}" != "${last_smoke}" ]]; then
    log "${progress}"
    last_smoke="${progress}"
  fi

  sleep 45
done

log "Timed out after ${MAX_MINUTES}m — still not green"
gh pr checks "${PR}" 2>/dev/null || true
exit 3
