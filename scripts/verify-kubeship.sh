#!/usr/bin/env bash
# In-cluster KubeShip API sanity — proves the app serves real HTTP + Couchbase-backed APIs.
# Mirrors apps/kubeship/internal/api/server_test.go TestShipmentLifecycle.
set -euo pipefail

NAMESPACE="${KUBESHIP_NAMESPACE:-kubeship}"
SERVICE="${KUBESHIP_SERVICE:-kubeship-api}"
LOCAL_PORT="${KUBESHIP_LOCAL_PORT:-18080}"
BASE_URL="http://127.0.0.1:${LOCAL_PORT}"
TIMEOUT="${VERIFY_KUBESHIP_TIMEOUT:-120}"
PF_PID=""

log() { printf '==> %s\n' "$*"; }
pass() { printf 'PASS: %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

cleanup() {
  if [[ -n "${PF_PID}" ]]; then
    kill "${PF_PID}" 2>/dev/null || true
    wait "${PF_PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

wait_for_deployment() {
  log "Waiting for kubeship-api deployment"
  kubectl -n "${NAMESPACE}" rollout status "deploy/kubeship-api" --timeout="${TIMEOUT}s"
  pass "kubeship-api deployment is Available"
}

start_port_forward() {
  log "Port-forward svc/${SERVICE} -> ${LOCAL_PORT}"
  kubectl -n "${NAMESPACE}" port-forward "svc/${SERVICE}" "${LOCAL_PORT}:8080" >/dev/null 2>&1 &
  PF_PID=$!
  for _ in $(seq 1 60); do
    if curl -sf "${BASE_URL}/health" >/dev/null 2>&1; then
      pass "KubeShip API reachable at ${BASE_URL}"
      return 0
    fi
    sleep 2
  done
  die "KubeShip API not reachable via port-forward within ${TIMEOUT}s"
}

check_health() {
  log "GET /health"
  local body
  body="$(curl -sf "${BASE_URL}/health")"
  python3 -c "
import json, sys
body = json.loads(sys.argv[1])
assert body.get('status') == 'ok', body
assert body.get('service') == 'kubeship', body
" "${body}"
  pass "/health returns ok"
}

check_carriers() {
  log "GET /api/v1/carriers"
  local body count
  body="$(curl -sf "${BASE_URL}/api/v1/carriers")"
  count="$(python3 -c "import json,sys; print(len(json.loads(sys.argv[1])))" "${body}")"
  if [[ "${count}" -lt 2 ]]; then
    die "expected at least 2 carriers, got ${count}"
  fi
  pass "/api/v1/carriers returned ${count} carrier(s)"
}

check_shipment_lifecycle() {
  log "Shipment lifecycle (create → get → track → patch)"
  local create_body shipment_id tracking patch_body

  create_body="$(curl -sf -X POST "${BASE_URL}/api/v1/shipments" \
    -H 'Content-Type: application/json' \
    -d '{
      "origin": {"city": "Limassol", "country": "CY"},
      "destination": {"city": "Athens", "country": "GR"},
      "carrier": "med-express",
      "weight_kg": 3.5
    }')"

  read -r shipment_id tracking < <(python3 -c "
import json, sys
s = json.loads(sys.argv[1])
assert s.get('status') == 'created', s
tn = s.get('tracking_number', '')
assert tn.startswith('KS-'), tn
print(s['id'], tn)
" "${create_body}")

  curl -sf "${BASE_URL}/api/v1/shipments/${shipment_id}" >/dev/null
  pass "GET /api/v1/shipments/${shipment_id}"

  curl -sf "${BASE_URL}/api/v1/track/${tracking}" >/dev/null
  pass "GET /api/v1/track/${tracking}"

  patch_body="$(curl -sf -X PATCH "${BASE_URL}/api/v1/shipments/${shipment_id}/status" \
    -H 'Content-Type: application/json' \
    -d '{"status":"in_transit"}')"

  python3 -c "
import json, sys
s = json.loads(sys.argv[1])
assert s.get('status') == 'in_transit', s
" "${patch_body}"
  pass "PATCH /api/v1/shipments/${shipment_id}/status → in_transit"
}

main() {
  require_cmd kubectl
  require_cmd curl
  require_cmd python3
  wait_for_deployment
  start_port_forward
  check_health
  check_carriers
  check_shipment_lifecycle
  log "KubeShip API sanity checks passed"
}

main "$@"
