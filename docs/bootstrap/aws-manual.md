# AWS manual bootstrap

Manual Terraform workflow for **AWS EKS** when you do not use `scripts/bootstrap-aws.sh`.

For the plug-and-play script, see [aws-quickstart.md](aws-quickstart.md). For Azure, see [azure.md](azure.md).

## Prerequisites

| Requirement | Notes |
|-------------|--------|
| Terraform `>= 1.5` | [Install](https://www.terraform.io/downloads) |
| AWS CLI | `aws configure` or equivalent credentials |
| kubectl | Cluster access after apply |
| Remote state | S3 bucket and DynamoDB table for locking |

## Staging

```bash
export AWS_REGION="us-east-1"

cp terraform/environments/staging/backend.hcl.example terraform/environments/staging/backend.hcl
cp terraform/environments/staging/terraform.tfvars.example terraform/environments/staging/terraform.tfvars
# Edit backend.hcl (bucket, key, region, dynamodb_table) and terraform.tfvars

cd terraform/environments/staging
terraform init -backend-config=backend.hcl
terraform apply -target=module.vpc -target=module.eks
terraform apply
```

Configure kubectl:

```bash
aws eks update-kubeconfig --region "${AWS_REGION}" --name infra-staging
kubectl get nodes
```

## Production

Repeat with `terraform/environments/prod/` and cluster name `infra-prod`.

## Verify

```bash
ENVIRONMENT=staging ./scripts/verify-platform.sh
```

Details: [operations/verify.md](../operations/verify.md).

## CI Terraform plan (optional)

One-time OIDC setup: [delivery/github-actions-aws-oidc.md](../delivery/github-actions-aws-oidc.md).
