#!/usr/bin/env bash
# One-time setup: apply AWS GitHub OIDC bootstrap and push outputs to GitHub repo variables.
set -euo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"
GITHUB_ORG="${GITHUB_ORG:-panagiod}"
GITHUB_REPO="${GITHUB_REPO:-infra}"
TF_STATE_BUCKET="${TF_STATE_BUCKET:-}"
TF_LOCK_TABLE="${TF_LOCK_TABLE:-}"
SET_GITHUB_VARS="${SET_GITHUB_VARS:-true}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OIDC_DIR="${REPO_ROOT}/terraform/bootstrap/aws-github-oidc"

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

check_prerequisites() {
  log "Checking prerequisites"
  require_cmd terraform
  require_cmd aws
  require_cmd jq
  aws sts get-caller-identity >/dev/null || die "AWS CLI is not authenticated. Run: aws configure"
  [[ -n "${TF_STATE_BUCKET}" ]] || die "Set TF_STATE_BUCKET"
  [[ -n "${TF_LOCK_TABLE}" ]] || die "Set TF_LOCK_TABLE"
}

apply_oidc_stack() {
  log "Applying GitHub OIDC bootstrap stack"
  cd "${OIDC_DIR}"

  if [[ ! -f terraform.tfvars ]]; then
    cat >terraform.tfvars <<EOF
aws_region      = "${AWS_REGION}"
github_org      = "${GITHUB_ORG}"
github_repo     = "${GITHUB_REPO}"
tf_state_bucket = "${TF_STATE_BUCKET}"
tf_lock_table   = "${TF_LOCK_TABLE}"
EOF
    log "Wrote ${OIDC_DIR}/terraform.tfvars"
  fi

  terraform init -input=false
  terraform apply -auto-approve -input=false

  ROLE_ARN="$(terraform output -raw github_actions_role_arn)"
  export ROLE_ARN
}

set_github_variable() {
  local name="$1"
  local value="$2"

  if [[ "${SET_GITHUB_VARS}" != "true" ]]; then
    log "Skipping GitHub variable ${name} (SET_GITHUB_VARS=false)"
    return 0
  fi

  require_cmd gh
  gh auth status >/dev/null 2>&1 || die "gh CLI is not authenticated. Run: gh auth login"

  log "Setting GitHub repository variable: ${name}"
  if gh variable list --repo "${GITHUB_ORG}/${GITHUB_REPO}" --json name -q ".[] | select(.name==\"${name}\") | .name" | grep -q "^${name}$"; then
    gh variable set "${name}" --repo "${GITHUB_ORG}/${GITHUB_REPO}" --body "${value}"
  else
    gh variable create "${name}" --repo "${GITHUB_ORG}/${GITHUB_REPO}" --body "${value}"
  fi
}

push_github_variables() {
  log "Publishing GitHub Actions repository variables"
  set_github_variable "AWS_ROLE_ARN" "${ROLE_ARN}"
  set_github_variable "AWS_REGION" "${AWS_REGION}"
  set_github_variable "TF_STATE_BUCKET" "${TF_STATE_BUCKET}"
  set_github_variable "TF_LOCK_TABLE" "${TF_LOCK_TABLE}"
}

main() {
  check_prerequisites
  apply_oidc_stack
  push_github_variables
  log "Done. Open a PR touching terraform/environments/staging to confirm terraform-plan.yml runs."
  log "Role ARN: ${ROLE_ARN}"
}

main "$@"
