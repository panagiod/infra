# Azure

> **Path overview:** [getting-started.md](getting-started.md)

Azure support mirrors the AWS layout: **Terraform creates the cluster and bootstraps Argo CD**, **Argo CD deploys the platform** from the shared `gitops/` tree.

## Status

| Component | Status |
|-----------|--------|
| VNet + AKS Terraform modules | `terraform/modules/azure/` |
| Argo CD bootstrap on AKS | Helm + root Application (parity with EKS) |
| Staging / prod environments | `terraform/environments/azure/` |
| Plug-and-play bootstrap | `scripts/bootstrap-azure.sh` |
| Terraform CI validate | `.github/workflows/terraform.yml` |
| GitHub Actions OIDC plan | `terraform/bootstrap/azure-github-oidc/` + `terraform-plan-azure.yml` |

## Layout

```text
terraform/
  modules/azure/
    vnet/          # Resource group, VNet, AKS subnet
    aks/           # AKS cluster, Argo CD, root Application
  environments/azure/
    staging/
    prod/
  bootstrap/azure-github-oidc/   # One-time OIDC for CI plan
```

The **same** `gitops/platform/` bundle runs on AKS after bootstrap — no Azure-specific GitOps tree is required initially.

## Quick start (plug and play)

```bash
export TF_STATE_RG="infra-tfstate-rg"
export TF_STATE_STORAGE_ACCOUNT="yourorgtfstate"
export TF_STATE_CONTAINER="tfstate"
export AZURE_REGION="westeurope"
export GITOPS_REPO_URL="https://github.com/panagiod/infra"
export GITOPS_REVISION="main"

# Optional: create storage account + container automatically
export CREATE_STATE="true"

chmod +x scripts/bootstrap-azure.sh
./scripts/bootstrap-azure.sh

# Or staging + prod
ENVIRONMENT=both ./scripts/bootstrap-azure.sh

# Config only — no terraform apply
SKIP_APPLY=true ./scripts/bootstrap-azure.sh
```

The script will:

1. Verify `terraform`, `az`, and `kubectl` (`az login`)
2. Optionally create remote state storage
3. Generate `backend.hcl` and `terraform.tfvars` from examples
4. Run two-phase Terraform apply (VNet/AKS first, then Argo CD)
5. Configure `kubectl` and show node / Argo CD status

## Manual bootstrap

```bash
az login
cp terraform/environments/azure/staging/backend.hcl.example terraform/environments/azure/staging/backend.hcl
cp terraform/environments/azure/staging/terraform.tfvars.example terraform/environments/azure/staging/terraform.tfvars
# Edit backend.hcl and terraform.tfvars (include gitops_repo_url)

cd terraform/environments/azure/staging
terraform init -backend-config=backend.hcl
terraform apply -target=module.vnet -target=module.aks
terraform apply
```

Get kubeconfig:

```bash
az aks get-credentials --resource-group infra-staging-rg --name infra-staging-aks
kubectl get nodes
kubectl -n argocd get applications
```

## Verify platform

After Argo CD syncs (same as AWS):

```bash
kubectl -n cert-manager get pods
kubectl -n istio-system get pods
kubectl -n mtls-demo get pods
```

## Remote state

Use an Azure Storage account backend. Example `backend.hcl`:

```hcl
resource_group_name  = "infra-tfstate-rg"
storage_account_name = "yourorgtfstate"
container_name       = "tfstate"
key                  = "infra/azure/staging/terraform.tfstate"
```

## GitHub Actions (CI + plan on PRs)

| Workflow | Purpose |
|----------|---------|
| `terraform.yml` | `fmt` + `validate` for AWS and Azure |
| `terraform-plan-azure.yml` | `terraform plan` on Azure PRs using OIDC |

Set up OIDC once: [github-actions-azure-oidc.md](github-actions-azure-oidc.md)

## AWS vs Azure differences

| Area | AWS | Azure |
|------|-----|-------|
| Cluster autoscaler | Helm + IRSA | AKS node pool `auto_scaling_enabled` |
| Load balancers | AWS Load Balancer Controller | Azure LB for `Service type=LoadBalancer` (Istio gateway) |
| Block storage | EBS CSI + IRSA | Azure Disk CSI (`storage_profile.disk_driver_enabled`) |
| Terraform state | S3 + DynamoDB | Storage account + blob lease |
| CI plan auth | GitHub OIDC → IAM role | GitHub OIDC → managed identity |

## Future hardening

- Separate ingress/LB subnet and NAT gateway for private-cluster topologies
- Workload Identity for cert-manager Azure DNS-01
- Azure AD RBAC for cluster admin instead of local accounts
