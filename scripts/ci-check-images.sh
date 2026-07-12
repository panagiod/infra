#!/usr/bin/env bash
# Preflight: verify container images used by Kind smoke exist before creating a cluster.
# Fails fast on ImagePullBackOff risks (saves ~10+ minutes per bad image).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENVIRONMENT="${ENVIRONMENT:-staging}"
APPS_FILE="${REPO_ROOT}/gitops/clusters/${ENVIRONMENT}/applications.yaml"
METALLB_MANIFEST_URL="${METALLB_MANIFEST_URL:-https://raw.githubusercontent.com/metallb/metallb/v0.14.9/config/manifests/metallb-native.yaml}"
PARALLEL="${PARALLEL:-8}"
WORKDIR=""

cleanup() {
  [[ -n "${WORKDIR}" ]] && rm -rf "${WORKDIR}"
}
trap cleanup EXIT

log() { printf '==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

install_crane_if_missing() {
  if command -v crane >/dev/null 2>&1; then
    return 0
  fi
  local version="${CRANE_VERSION:-0.20.3}"
  local arch
  arch="$(uname -m)"
  case "${arch}" in
    x86_64|amd64) arch="x86_64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) die "Unsupported arch for crane install: ${arch}" ;;
  esac
  log "Installing crane v${version}"
  curl -fsSL "https://github.com/google/go-containerregistry/releases/download/v${version}/go-containerregistry_Linux_${arch}.tar.gz" \
    | tar xz -C /tmp crane
  install /tmp/crane "${HOME}/.local/bin/crane" 2>/dev/null || sudo install /tmp/crane /usr/local/bin/crane
  export PATH="${HOME}/.local/bin:/usr/local/bin:${PATH}"
  require_cmd crane
}

install_kustomize_if_missing() {
  if command -v kustomize >/dev/null 2>&1; then
    return 0
  fi
  local version
  version="$(curl -fsSL https://api.github.com/repos/kubernetes-sigs/kustomize/releases/latest | grep '"tag_name"' | head -1 | sed -E 's/.*kustomize\/v?([^"]+)".*/\1/')"
  log "Installing kustomize v${version}"
  curl -fsSL "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${version}/kustomize_v${version}_linux_amd64.tar.gz" \
    | tar xz -C /tmp
  install /tmp/kustomize "${HOME}/.local/bin/kustomize" 2>/dev/null || sudo install /tmp/kustomize /usr/local/bin/kustomize
  export PATH="${HOME}/.local/bin:/usr/local/bin:${PATH}"
  require_cmd kustomize
}

install_helm_if_missing() {
  if command -v helm >/dev/null 2>&1; then
    return 0
  fi
  local version="${HELM_VERSION:-3.16.4}"
  log "Installing helm v${version}"
  curl -fsSL "https://get.helm.sh/helm-v${version}-linux-amd64.tar.gz" | tar xz -C /tmp linux-amd64/helm
  install /tmp/linux-amd64/helm "${HOME}/.local/bin/helm" 2>/dev/null || sudo install /tmp/linux-amd64/helm /usr/local/bin/helm
  export PATH="${HOME}/.local/bin:/usr/local/bin:${PATH}"
  require_cmd helm
}

helm_repo_add() {
  local name="$1" url="$2"
  if helm repo list 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx "${name}"; then
    return 0
  fi
  helm repo add "${name}" "${url}" >/dev/null
}

setup_helm_repos() {
  require_cmd helm
  helm_repo_add jetstack https://charts.jetstack.io
  helm_repo_add istio https://istio-release.storage.googleapis.com/charts
  helm_repo_add prometheus-community https://prometheus-community.github.io/helm-charts
  helm_repo_add kyverno https://kyverno.github.io/kyverno
  helm_repo_add argo https://argoproj.github.io/argo-helm
  log "Updating Helm chart indexes"
  helm repo update >/dev/null
}

collect_gitops_images() {
  local tmpdir="$1"
  install_kustomize_if_missing

  log "Collecting images from Git paths in ${APPS_FILE}"
  python3 - "${APPS_FILE}" "${REPO_ROOT}" <<'PY' | while read -r rel; do
import sys, yaml
apps_file, repo_root = sys.argv[1:3]
with open(apps_file, encoding="utf-8") as fh:
    for doc in yaml.safe_load_all(fh):
        if not doc or doc.get("kind") != "Application":
            continue
        src = doc.get("spec", {}).get("source", {})
        if src.get("path"):
            print(src["path"])
PY
    [[ -n "${rel}" ]] || continue
    local full="${REPO_ROOT}/${rel}"
    [[ -d "${full}" ]] || die "GitOps path not found: ${rel}"
    log "  kustomize build ${rel}"
    kustomize build "${full}" >"${tmpdir}/kustomize-${rel//\//-}.yaml"
  done
}

collect_helm_images() {
  local tmpdir="$1"
  setup_helm_repos

  log "Collecting images from Helm Applications in ${APPS_FILE}"
  python3 - "${APPS_FILE}" "${tmpdir}" <<'PY'
import os, subprocess, sys, tempfile, yaml

apps_file, tmpdir = sys.argv[1:3]
repo_map = {
    "https://charts.jetstack.io": "jetstack",
    "https://istio-release.storage.googleapis.com/charts": "istio",
    "https://prometheus-community.github.io/helm-charts": "prometheus-community",
    "https://kyverno.github.io/kyverno": "kyverno",
}

with open(apps_file, encoding="utf-8") as fh:
    docs = list(yaml.safe_load_all(fh))

for doc in docs:
    if not doc or doc.get("kind") != "Application":
        continue
    src = doc.get("spec", {}).get("source", {})
    chart = src.get("chart")
    if not chart:
        continue
    name = doc["metadata"]["name"]
    repo_url = src["repoURL"]
    repo = repo_map.get(repo_url)
    if not repo:
        raise SystemExit(f"Unknown Helm repo URL for {name}: {repo_url}")
    helm_cfg = src.get("helm", {}) or {}
    release = helm_cfg.get("releaseName", name)
    values = helm_cfg.get("values", "") or ""
    values_file = None
    if values.strip():
        fd, values_file = tempfile.mkstemp(prefix=f"helm-values-{name}-", suffix=".yaml")
        with os.fdopen(fd, "w", encoding="utf-8") as out:
            out.write(values)
    out_path = os.path.join(tmpdir, f"helm-{name}.yaml")
    cmd = [
        "helm", "template", release, f"{repo}/{chart}",
        "--namespace", doc.get("spec", {}).get("destination", {}).get("namespace", "default"),
    ]
    if values_file:
        cmd.extend(["-f", values_file])
    print(f"  helm template {repo}/{chart} ({name})", flush=True)
    with open(out_path, "w", encoding="utf-8") as out:
        subprocess.run(cmd, check=True, stdout=out)
    if values_file:
        os.remove(values_file)
PY

  log "Collecting images from Argo CD bootstrap chart"
  helm template argocd argo/argo-cd \
    --namespace argocd \
    -f "${REPO_ROOT}/hack/argocd/bootstrap-values.yaml" \
    >"${tmpdir}/helm-argocd.yaml"
}

collect_metallb_images() {
  local tmpdir="$1"
  log "Collecting images from MetalLB manifest"
  curl -fsSL "${METALLB_MANIFEST_URL}" -o "${tmpdir}/metallb.yaml"
}

normalize_images() {
  local list_file="$1"
  python3 - "${list_file}" <<'PY'
import re, sys

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

# Istio gateway charts use image: auto; nodes pull proxyv2 at the same tag as pilot.
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

main() {
  WORKDIR="$(mktemp -d)"

  require_cmd python3
  require_cmd curl
  install_crane_if_missing
  install_helm_if_missing

  [[ -f "${APPS_FILE}" ]] || die "Missing ${APPS_FILE}"

  collect_gitops_images "${WORKDIR}"
  collect_helm_images "${WORKDIR}"
  collect_metallb_images "${WORKDIR}"

  local raw_list="${WORKDIR}/images-raw.txt"
  local final_list="${WORKDIR}/images.txt"
  find "${WORKDIR}" -name '*.yaml' -print0 | xargs -0 python3 -c "
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

  normalize_images "${raw_list}" >"${final_list}"

  log "Image inventory ($(wc -l <"${final_list}" | tr -d ' ') unique after filtering):"
  sed 's/^/  /' "${final_list}"

  verify_images "${final_list}"
}

main "$@"
