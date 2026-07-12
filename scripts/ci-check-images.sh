#!/usr/bin/env bash
# Preflight: verify container images used by Kind smoke exist before creating a cluster.
# Fails fast on ImagePullBackOff risks (saves ~10+ minutes per bad image).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/ci-install-tools.sh
source "${REPO_ROOT}/scripts/ci-install-tools.sh"

ENVIRONMENT="${ENVIRONMENT:-staging}"
RENDER_DIR="${RENDER_DIR:-}"

log() { printf '==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

normalize_images() {
  local list_file="$1"
  python3 - "${list_file}" <<'PY'
import sys

skip = {"auto", "pause", "placeholder"}
raw = open(sys.argv[1], encoding="utf-8").read().splitlines()
images = set()
for line in raw:
    img = line.strip().strip('"').strip("'")
    if not img or img in skip:
        continue
    if img.startswith("${") or "://" in img and not img[0].isalnum():
        continue
    if "/" not in img:
        continue
    images.add(img)

for img in list(images):
    if img.startswith("registry.istio.io/release/pilot:"):
        tag = img.rsplit(":", 1)[-1]
        images.add(f"registry.istio.io/release/proxyv2:{tag}")

for img in sorted(images):
    print(img)
PY
}

verify_image() {
  local image="$1"
  if crane manifest "${image}" >/dev/null 2>&1; then
    printf 'OK  %s\n' "${image}"
    return 0
  fi
  printf 'FAIL %s\n' "${image}" >&2
  return 1
}

verify_images() {
  local list_file="$1"
  local failed=0
  local total
  total="$(wc -l <"${list_file}" | tr -d ' ')"
  log "Verifying ${total} image(s) exist in registry (crane manifest)"
  while IFS= read -r image; do
    [[ -n "${image}" ]] || continue
    verify_image "${image}" || failed=1
  done <"${list_file}"
  if [[ "${failed}" -ne 0 ]]; then
    die "One or more images are missing or not pullable — fix before Kind smoke"
  fi
  log "All ${total} image(s) verified"
}

extract_images_from_render() {
  local render_dir="$1" raw_list="$2"
  find "${render_dir}" -name '*.yaml' -print0 | xargs -0 python3 -c "
import sys, yaml

def walk(obj, images):
    if isinstance(obj, dict):
        for k, v in obj.items():
            if k == 'image' and isinstance(v, str):
                images.add(v.strip())
            else:
                walk(v, images)
    elif isinstance(obj, list):
        for item in obj:
            walk(item, images)

images = set()
for path in sys.argv[1:]:
    with open(path, encoding='utf-8') as fh:
        for doc in yaml.safe_load_all(fh):
            if doc:
                walk(doc, images)
for img in sorted(images):
    print(img)
" >"${raw_list}"
}

main() {
  local cleanup=0
  local workdir="${RENDER_DIR}"
  if [[ -z "${workdir}" ]]; then
    workdir="$(mktemp -d)"
    cleanup=1
  fi

  require_cmd python3
  ci_install_crane
  ci_install_helm
  ci_install_kustomize
  require_cmd crane
  require_cmd helm
  require_cmd kustomize

  if [[ ! -f "${workdir}/cert-manager.yaml" ]]; then
    log "Rendering GitOps manifests (${ENVIRONMENT})"
    python3 "${REPO_ROOT}/scripts/ci_render_gitops.py" \
      --env "${ENVIRONMENT}" \
      --output "${workdir}" \
      --include-bootstrap \
      --include-metallb
  fi

  local raw_list="${workdir}/images-raw.txt"
  local final_list="${workdir}/images.txt"
  extract_images_from_render "${workdir}" "${raw_list}"
  normalize_images "${raw_list}" >"${final_list}"

  log "Image inventory ($(wc -l <"${final_list}" | tr -d ' ') unique after filtering):"
  sed 's/^/  /' "${final_list}"

  verify_images "${final_list}"

  [[ "${cleanup}" -eq 0 ]] || rm -rf "${workdir}"
}

main "$@"
