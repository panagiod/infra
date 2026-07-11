# infra

Production-ready, multi-cloud Kubernetes platform. **Phase 1** delivers AWS EKS and Azure AKS with staging and prod clusters, a GitOps-managed platform bundle (cert-manager, Istio mTLS, monitoring), and a demo application.

## What this repository contains

| Path | Purpose |
|------|---------|
| [`terraform/`](terraform/) | AWS EKS + Azure AKS for staging and prod |
| [`gitops/`](gitops/) | Argo CD app-of-apps, platform components, workloads |
| [`docs/`](docs/) | Architecture, [QUICKSTART](docs/QUICKSTART.md), [local dev](docs/local-dev.md), [Azure](docs/azure.md) |
| [`.github/workflows/`](.github/workflows/) | Terraform and manifest validation CI |

## Architecture (phase 1)

- **Managed Kubernetes:** AWS EKS and Azure AKS (staging + prod)
- **GitOps:** Argo CD app-of-apps per cluster
- **mTLS:** Istio with STRICT peer authentication + cert-manager via istio-csr
- **Observability:** kube-prometheus-stack (Prometheus, Grafana, Alertmanager)
- **Ingress:** Istio Gateway API gateway with TLS from cert-manager

See [docs/architecture.md](docs/architecture.md) for details.

## Prerequisites

- AWS account with permissions for VPC, EKS, IAM, EC2, ELB
- Terraform `>= 1.5`
- `kubectl` `>= 1.28`
- AWS CLI configured (`aws configure` or environment credentials)
- An S3 bucket and DynamoDB table for Terraform remote state (see [docs/bootstrap.md](docs/bootstrap.md))
- Helm `>= 3.12` (for optional manual bootstrap steps)

## Quick start (plug and play)

**Local (free)** — see [docs/local-dev.md](docs/local-dev.md):

```bash
chmod +x scripts/bootstrap-local.sh
./scripts/bootstrap-local.sh
```

**AWS** — see [docs/QUICKSTART.md](docs/QUICKSTART.md):

```bash
export TF_STATE_BUCKET="your-org-terraform-state"
export TF_LOCK_TABLE="your-org-terraform-locks"
chmod +x scripts/bootstrap-aws.sh
./scripts/bootstrap-aws.sh
```

**Azure** — see [docs/azure.md](docs/azure.md):

```bash
export TF_STATE_RG="infra-tfstate-rg"
export TF_STATE_STORAGE_ACCOUNT="yourorgtfstate"
chmod +x scripts/bootstrap-azure.sh
./scripts/bootstrap-azure.sh
```

## Manual quick start

### 1. Bootstrap remote state

Create an S3 bucket and DynamoDB lock table, then copy backend config:

```bash
cp terraform/environments/staging/backend.hcl.example terraform/environments/staging/backend.hcl
cp terraform/environments/prod/backend.hcl.example terraform/environments/prod/backend.hcl
# Edit bucket, key, region, and dynamodb_table in each file
```

### 2. Configure environments

```bash
cp terraform/environments/staging/terraform.tfvars.example terraform/environments/staging/terraform.tfvars
cp terraform/environments/prod/terraform.tfvars.example terraform/environments/prod/terraform.tfvars
```

Set at minimum:

- `aws_region`
- `cluster_name` (e.g. `infra-staging`, `infra-prod`)
- `gitops_repo_url` (this repository URL for Argo CD)

### 3. Provision staging

```bash
cd terraform/environments/staging
terraform init -backend-config=backend.hcl

# First apply creates VPC + EKS; second apply installs Helm addons (Argo CD, ALB controller).
terraform apply -target=module.vpc -target=module.eks
terraform plan -out=tfplan
terraform apply tfplan
```

Repeat for prod in `terraform/environments/prod`.

> **Note:** On first bootstrap, set `gitops_target_revision` in `terraform.tfvars` to the branch that contains the GitOps manifests (e.g. `main` after merge, or your feature branch while testing).

### 4. Access clusters

```bash
aws eks update-kubeconfig --region <region> --name infra-staging
kubectl get nodes
```

Argo CD is installed by Terraform and syncs the platform bundle from this repo.

### 5. Verify mTLS demo

```bash
kubectl -n mtls-demo get pods
kubectl -n istio-system get peerauthentication
```

Follow [docs/bootstrap.md](docs/bootstrap.md) for Argo CD UI access, Grafana credentials, and ingress DNS.

## Repository layout

```
terraform/
  modules/
    vpc/                 # Multi-AZ VPC
    eks/                 # EKS cluster, node groups, IRSA, add-ons
  environments/
    staging/
    prod/
gitops/
  bootstrap/argocd/      # Helm values for Argo CD
  clusters/              # Per-cluster app-of-apps roots
  platform/              # cert-manager, istio, monitoring, policies
  apps/mtls-demo/        # Sample mTLS workload
docs/
```

## Environments

| | Staging | Prod |
|---|---------|------|
| Purpose | Soak tests, upgrade validation | Production workloads |
| Nodes | Smaller instance types, 2–4 nodes | Larger types, 3–6+ nodes |
| mTLS | STRICT (same as prod) | STRICT |
| Platform versions | Latest stable from upstream indexes | Latest stable from upstream indexes |

## Multi-cloud roadmap

AWS and Azure Terraform paths are implemented with shared GitOps. GCP modules will mirror the same layout:

- `terraform/modules/` cloud-specific networking and Kubernetes modules
- Shared `gitops/platform/` bundle across all clusters

## Contributing

1. Branch from `main` using `feat/`, `fix/`, `chore/`, or `docs/` prefixes (e.g. `feat/my-change`)
2. Run `terraform fmt -recursive` and open a PR
3. CI validates Terraform and Kubernetes manifests

## License

Private / internal — adjust as needed.
