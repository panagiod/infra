#!/usr/bin/env bash
# Pre-pull platform images and load into kind nodes before GitOps bootstrap.
# Reduces ErrImagePull flakes from partial registry downloads during pod scheduling.
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-infra-local}"
LIST_FILE="${PRELOAD_FROM_LIST:-}"
MAX_RETRIES="${IMAGE_PULL_RETRIES:-5}"

log() { printf '==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

pull_with_retry() {
  local image="$1"
  local attempt
  for attempt in $(seq 1 "${MAX_RETRIES}"); do
    if docker pull "${image}"; then
      printf 'OK  pulled %s\n' "${image}"
      return 0
    fi
    printf 'WARN: docker pull %s failed (attempt %d/%d)\n' "${image}" "${attempt}" "${MAX_RETRIES}" >&2
    sleep $((attempt * 5))
  done
  die "docker pull failed after ${MAX_RETRIES} attempts: ${image}"
}

preload_image() {
  local image="$1"
  pull_with_retry "${image}"
  kind load docker-image "${image}" --name "${CLUSTER_NAME}"
  printf 'OK  loaded %s into kind cluster %s\n' "${image}" "${CLUSTER_NAME}"
}

main() {
  [[ -n "${LIST_FILE}" ]] || die "PRELOAD_FROM_LIST is required (path to image list from ci-check-images.sh)"
  [[ -f "${LIST_FILE}" ]] || die "Image list not found: ${LIST_FILE}"

  require_cmd docker
  require_cmd kind

  if ! kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
    die "kind cluster ${CLUSTER_NAME} does not exist — create it before preloading images"
  fi

  local total loaded=0
  total="$(grep -cve '^[[:space:]]*$' "${LIST_FILE}" || true)"
  log "Preloading ${total} image(s) into kind cluster ${CLUSTER_NAME}"

  while IFS= read -r image; do
    [[ -n "${image}" ]] || continue
    preload_image "${image}"
    loaded=$((loaded + 1))
  done <"${LIST_FILE}"

  log "Preloaded ${loaded} image(s) into kind"
}

main "$@"
