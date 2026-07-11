# Azure (preview skeleton)

Azure support mirrors the AWS layout: **Terraform creates the cluster**, **Argo CD deploys the platform** from the shared `gitops/` tree.

## Status

| Component | Status |
|-----------|--------|
| VNet + AKS Terraform modules | Skeleton in `terraform/modules/azure/` |
| Staging / prod environments | `terraform/environments/azure/` |
| Terraform CI validate (fmt + validate) | Included in `.github/workflows/terraform.yml` |
| Argo CD bootstrap on AKS | **Not yet** — use AWS path for plug-and-play today |
| GitHub Actions OIDC (Azure) | **Not yet** — see AWS [github-actions-aws-oidc.md](github-actions-aws-oidc.md) |

## Layout

```text
terraform/
  modules/azure/
    vnet/          # Resource group, VNet, AKS subnet
    aks/           # AKS cluster with workload identity
  environments/azure/
    staging/
    prod/
```

The **same** `gitops/platform/` bundle will run on AKS once Argo CD bootstrap is added (Helm install + root Application).

## Manual bootstrap (skeleton)

```bash
az login
cp terraform/environments/azure/staging/backend.hcl.example terraform/environments/azure/staging/backend.hcl
cp terraform/environments/azure/staging/terraform.tfvars.example terraform/environments/azure/staging/terraform.tfvars
# Edit backend.hcl and terraform.tfvars

cd terraform/environments/azure/staging
terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

Get kubeconfig:

```bash
az aks get-credentials --resource-group infra-staging-rg --name infra-staging-aks
kubectl get nodes
```

## Remote state

Use an Azure Storage account backend. Example `backend.hcl`:

```hcl
resource_group_name  = "infra-tfstate-rg"
storage_account_name = "yourorgtfstate"
container_name       = "tfstate"
key                  = "infra/azure/staging/terraform.tfstate"
```

## Next implementation steps

1. Add `azurerm` Helm/Argo CD bootstrap module (parity with `terraform/modules/eks`)
2. Wire `gitops_repo_url` variables into AKS environments
3. Add `scripts/bootstrap-azure.sh` plug-and-play script
4. Add GitHub Actions `azure/login` OIDC for `terraform plan`

## Why AWS first

The plug-and-play path (`scripts/bootstrap-aws.sh`, OIDC plan, full platform) is complete on AWS. Azure reuses GitOps; only the Terraform layer differs.
