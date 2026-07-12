#!/usr/bin/env bash
# Shared tool installers for CI preflight scripts (no cluster required).
set -euo pipefail

ci_install_crane() {
  if command -v crane >/dev/null 2>&1; then
    return 0
  fi
  local version="${CRANE_VERSION:-0.20.3}"
  local arch
  arch="$(uname -m)"
  case "${arch}" in
    x86_64|amd64) arch="x86_64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) echo "ERROR: Unsupported arch for crane: ${arch}" >&2; return 1 ;;
  esac
  echo "==> Installing crane v${version}"
  curl -fsSL "https://github.com/google/go-containerregistry/releases/download/v${version}/go-containerregistry_Linux_${arch}.tar.gz" \
    | tar xz -C /tmp crane
  install /tmp/crane "${HOME}/.local/bin/crane" 2>/dev/null || sudo install /tmp/crane /usr/local/bin/crane
  export PATH="${HOME}/.local/bin:/usr/local/bin:${PATH}"
}

ci_install_kustomize() {
  if command -v kustomize >/dev/null 2>&1; then
    return 0
  fi
  local version
  version="$(curl -fsSL https://api.github.com/repos/kubernetes-sigs/kustomize/releases/latest | grep '"tag_name"' | head -1 | sed -E 's/.*kustomize\/v?([^"]+)".*/\1/')"
  echo "==> Installing kustomize v${version}"
  curl -fsSL "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${version}/kustomize_v${version}_linux_amd64.tar.gz" \
    | tar xz -C /tmp
  install /tmp/kustomize "${HOME}/.local/bin/kustomize" 2>/dev/null || sudo install /tmp/kustomize /usr/local/bin/kustomize
  export PATH="${HOME}/.local/bin:/usr/local/bin:${PATH}"
}

ci_install_helm() {
  if command -v helm >/dev/null 2>&1; then
    return 0
  fi
  local version="${HELM_VERSION:-3.16.4}"
  echo "==> Installing helm v${version}"
  curl -fsSL "https://get.helm.sh/helm-v${version}-linux-amd64.tar.gz" | tar xz -C /tmp linux-amd64/helm
  install /tmp/linux-amd64/helm "${HOME}/.local/bin/helm" 2>/dev/null || sudo install /tmp/linux-amd64/helm /usr/local/bin/helm
  export PATH="${HOME}/.local/bin:/usr/local/bin:${PATH}"
}
