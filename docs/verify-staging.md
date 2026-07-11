# Staging verification guide

Run this after [QUICKSTART.md](QUICKSTART.md) or [bootstrap.md](bootstrap.md) to confirm the platform is healthy.

## Prerequisites

- AWS staging cluster provisioned (`infra-staging` by default)
- `kubectl` configured (`aws eks update-kubeconfig`)
- `jq` (for OIDC setup script only)

## One-command verification

```bash
export AWS_REGION="us-east-1"
export ENVIRONMENT="staging"
chmod +x scripts/verify-platform.sh
./scripts/verify-platform.sh
```

Override the cluster name if needed:

```bash
CLUSTER_NAME="my-staging-cluster" ./scripts/verify-platform.sh
```

### What it checks

| Check | Pass criteria |
|-------|----------------|
| Nodes | At least one `Ready` node |
| Argo CD | `argocd-server` Running |
| cluster-root | Application exists |
| Platform apps | cert-manager, Istio, monitoring, mtls-demo Applications present |
| Workloads | Key pods Running in cert-manager, istio-system, mtls-demo |
| mTLS | `PeerAuthentication` default mode `STRICT` |
| Ingress TLS | `istio-ingressgateway-certs` Certificate Ready |
| Demo | `frontend` can reach `backend` over the mesh |

Warnings (not hard failures) are emitted when apps are still syncing — wait a few minutes and re-run.

## OIDC setup (one-time, before PR plans work)

```bash
export TF_STATE_BUCKET="your-org-terraform-state"
export TF_LOCK_TABLE="your-org-terraform-locks"
export AWS_REGION="us-east-1"
export GITHUB_ORG="panagiod"
export GITHUB_REPO="infra"

chmod +x scripts/setup-github-oidc-aws.sh
./scripts/setup-github-oidc-aws.sh
```

This applies `terraform/bootstrap/aws-github-oidc/` and sets GitHub repository variables for `terraform-plan.yml`.

To apply the stack without writing GitHub variables:

```bash
SET_GITHUB_VARS=false ./scripts/setup-github-oidc-aws.sh
```

## Confirm CI terraform plan

1. Create a branch with a trivial Terraform change under `terraform/environments/staging/`
2. Open a pull request
3. Confirm the **Terraform plan** workflow runs and comments on the PR

If the workflow is skipped, verify repository variables: `AWS_ROLE_ARN`, `TF_STATE_BUCKET`, `TF_LOCK_TABLE`.

## Manual spot checks

```bash
kubectl -n argocd get applications
kubectl -n cert-manager get clusterissuer
kubectl -n istio-system get svc istio-ingressgateway
kubectl -n mtls-demo get pods
```

Argo CD admin password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d && echo
```

## Troubleshooting

| Symptom | Action |
|---------|--------|
| `cluster-root` missing | Re-run `terraform apply` in staging; check Argo CD Helm release |
| Apps `OutOfSync` | `kubectl -n argocd describe application <name>` |
| Istio pods pending | Check cert-manager issuers and `istio-csr` logs |
| Plan workflow skipped | Run `setup-github-oidc-aws.sh` and confirm GitHub variables |
| Nodes NotReady | Check EKS node group / subnet configuration in Terraform |
