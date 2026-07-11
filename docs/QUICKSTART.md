# Quick start (plug and play)

Get staging (and optionally prod) running on **AWS EKS** with minimal manual steps. Platform components deploy automatically via Argo CD after the cluster exists.

For full detail see [bootstrap.md](bootstrap.md). For Azure see [azure.md](azure.md).

## Prerequisites

| Tool | Purpose |
|------|---------|
| [Terraform](https://www.terraform.io/downloads) `>= 1.5` | Creates VPC and EKS |
| [AWS CLI](https://aws.amazon.com/cli/) | Authentication and `kubectl` config |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | Verify cluster and Argo CD |
| AWS account | Permissions for VPC, EKS, IAM, EC2, ELB, S3, DynamoDB |

Authenticate AWS:

```bash
aws configure
# or export AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY / AWS_SESSION_TOKEN
```

## One-command bootstrap (recommended)

```bash
export TF_STATE_BUCKET="your-org-terraform-state"
export TF_LOCK_TABLE="your-org-terraform-locks"
export AWS_REGION="us-east-1"
export GITOPS_REPO_URL="https://github.com/panagiod/infra"
export GITOPS_REVISION="main"

# Optional: create S3 + DynamoDB automatically
export CREATE_STATE="true"

# Staging only (default)
chmod +x scripts/bootstrap-aws.sh
./scripts/bootstrap-aws.sh

# Or staging + prod
ENVIRONMENT=both ./scripts/bootstrap-aws.sh

# Config only — no terraform apply
SKIP_APPLY=true ./scripts/bootstrap-aws.sh
```

The script will:

1. Verify `terraform`, `aws`, and `kubectl`
2. Optionally create remote state (S3 + DynamoDB)
3. Generate `backend.hcl` and `terraform.tfvars` from examples
4. Run two-phase Terraform apply (VPC/EKS first, then Helm addons + Argo CD)
5. Configure `kubectl` and show node / Argo CD status

After bootstrap, run the verification script: [verify-staging.md](verify-staging.md).

```bash
./scripts/verify-platform.sh
```

## Manual path (same result)

```bash
cp terraform/environments/staging/backend.hcl.example terraform/environments/staging/backend.hcl
cp terraform/environments/staging/terraform.tfvars.example terraform/environments/staging/terraform.tfvars
# edit both files, then:
cd terraform/environments/staging
terraform init -backend-config=backend.hcl
terraform apply -target=module.vpc -target=module.eks
terraform apply
```

## Verify platform

```bash
kubectl -n argocd get applications
kubectl -n cert-manager get pods
kubectl -n istio-system get pods
kubectl -n mtls-demo get pods
```

Argo CD admin password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d && echo
```

mTLS demo (from frontend to backend):

```bash
kubectl -n mtls-demo exec deploy/frontend -- wget -qO- http://backend:8080/
```

## GitHub Actions (CI + plan on PRs)

| Workflow | Purpose |
|----------|---------|
| `terraform.yml` | `fmt` + `validate` on every PR |
| `terraform-plan.yml` | AWS `terraform plan` on PRs using OIDC |
| `terraform-plan-azure.yml` | Azure `terraform plan` on PRs using OIDC |

Set up OIDC once: [github-actions-aws-oidc.md](github-actions-aws-oidc.md) (AWS), [github-actions-azure-oidc.md](github-actions-azure-oidc.md) (Azure)

## Azure quick start

Same plug-and-play flow on **AKS** — see [azure.md](azure.md) for full detail:

```bash
export TF_STATE_RG="infra-tfstate-rg"
export TF_STATE_STORAGE_ACCOUNT="yourorgtfstate"
export AZURE_REGION="westeurope"
chmod +x scripts/bootstrap-azure.sh
./scripts/bootstrap-azure.sh
```

## Next steps

- Tighten `cluster_endpoint_public_access_cidrs` (AWS) or `api_server_authorized_ip_ranges` (Azure) in `terraform.tfvars`
- Replace bootstrap cert-manager CA with your PKI ([cert-manager-provider.md](cert-manager-provider.md))
- Promote platform chart changes staging → prod via GitOps
