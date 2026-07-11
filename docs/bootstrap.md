# AWS bootstrap guide (manual)

> **Prefer the script?** Use [QUICKSTART.md](QUICKSTART.md) (`./scripts/bootstrap-aws.sh`).
>
> **No cloud?** Use [local-dev.md](local-dev.md).

Step-by-step manual Terraform for AWS staging and prod, plus post-bootstrap verification.

## 1. Remote state (one-time)

```bash
export AWS_REGION=us-east-1
export TF_STATE_BUCKET=your-org-terraform-state
export TF_LOCK_TABLE=your-org-terraform-locks

aws s3api create-bucket --bucket "$TF_STATE_BUCKET" --region "$AWS_REGION"
aws s3api put-bucket-versioning \
  --bucket "$TF_STATE_BUCKET" \
  --versioning-configuration Status=Enabled

aws dynamodb create-table \
  --table-name "$TF_LOCK_TABLE" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "$AWS_REGION"
```

```bash
cp terraform/environments/staging/backend.hcl.example terraform/environments/staging/backend.hcl
cp terraform/environments/prod/backend.hcl.example terraform/environments/prod/backend.hcl
```

## 2. Environment variables

```bash
cp terraform/environments/staging/terraform.tfvars.example terraform/environments/staging/terraform.tfvars
cp terraform/environments/prod/terraform.tfvars.example terraform/environments/prod/terraform.tfvars
```

| Variable | Staging | Prod |
|----------|---------|------|
| `cluster_name` | `infra-staging` | `infra-prod` |
| `gitops_repo_url` | This repo URL | Same |
| `single_nat_gateway` | `true` | `false` |

## 3. Apply Terraform

**Staging first:**

```bash
cd terraform/environments/staging
terraform init -backend-config=backend.hcl
terraform apply -target=module.vpc -target=module.eks
terraform apply
```

Repeat for `terraform/environments/prod`.

## 4. Configure kubectl

```bash
aws eks update-kubeconfig --region us-east-1 --name infra-staging
```

## 5. Verify

```bash
./scripts/verify-platform.sh
```

Post-bootstrap checks (Argo CD UI, Grafana, ingress, mTLS demo): [verify.md](verify.md)

## Troubleshooting

| Issue | Check |
|-------|-------|
| Argo apps OutOfSync | `kubectl -n argocd describe application <name>` |
| Istio pods not ready | cert-manager ClusterIssuer / istio-csr logs |
| Nodes not joining | EKS node group IAM, subnet tags |
| ALB not created | AWS Load Balancer Controller logs in `kube-system` |
