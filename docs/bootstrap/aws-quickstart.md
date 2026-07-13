# AWS quick start

> **Not sure which path to use?** See [getting-started.md](../start/getting-started.md).

Plug-and-play bootstrap for **AWS EKS** staging (and optionally prod). Platform components deploy via Argo CD after the cluster exists.

For manual Terraform steps see [aws-manual.md](aws-manual.md). For Azure see [azure.md](azure.md).

## Prerequisites

| Tool | Purpose |
|------|---------|
| [Terraform](https://www.terraform.io/downloads) `>= 1.5` | VPC + EKS |
| [AWS CLI](https://aws.amazon.com/cli/) | Auth + kubeconfig |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | Verification |
| AWS account | VPC, EKS, IAM, EC2, ELB, S3, DynamoDB |

```bash
aws configure
```

## One-command bootstrap

```bash
export TF_STATE_BUCKET="your-org-terraform-state"
export TF_LOCK_TABLE="your-org-terraform-locks"
export AWS_REGION="us-east-1"
export GITOPS_REPO_URL="https://github.com/panagiod/infra"
export GITOPS_REVISION="main"

# Optional: create S3 + DynamoDB automatically
export CREATE_STATE="true"

chmod +x scripts/bootstrap-aws.sh
./scripts/bootstrap-aws.sh

# Staging + prod
ENVIRONMENT=both ./scripts/bootstrap-aws.sh

# Config only
SKIP_APPLY=true ./scripts/bootstrap-aws.sh
```

The script: checks tools → optional remote state → generates config → two-phase Terraform apply → `kubectl` setup.

## Verify

```bash
./scripts/verify-platform.sh
```

Full checklist: [verify.md](../operations/verify.md)

## CI: Terraform plan on PRs

One-time setup: [github-actions-aws-oidc.md](../delivery/github-actions-aws-oidc.md) or `./scripts/setup-github-oidc-aws.sh`

## Next steps

- Tighten `cluster_endpoint_public_access_cidrs` in prod `terraform.tfvars`
- Configure alerting: [alerting.md](../operations/alerting.md)
- Replace bootstrap CA: [cert-manager-provider.md](../operations/cert-manager-provider.md)
- No cloud budget? Use [local-dev.md](../paths/local-dev.md) instead
