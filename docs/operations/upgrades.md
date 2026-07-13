# Upgrade runbook

> Platform verification after upgrades: [verify.md](verify.md)

## Kubernetes (EKS / AKS)

### Staging

1. Update `kubernetes_version` in `terraform/environments/staging/terraform.tfvars`
2. `terraform plan` — review control plane and addon changes
3. `terraform apply`
4. Node groups roll automatically when `kubernetes_version` on the group changes
5. Verify:
   ```bash
   kubectl version
   kubectl -n kubeship rollout status deploy/kubeship-api
   kubectl -n istio-system get pods
   ```

### Prod

1. Complete staging soak (minimum 48h recommended for platform changes)
2. Repeat Terraform steps in `terraform/environments/prod`
3. Monitor Grafana Istio and API server dashboards during rollout

### Node pool surge strategy (zero-downtime)

For large jumps, add a new node group on the target version, cordon/drain the old group, then remove it in Terraform.

### AKS (Azure)

Same flow in `terraform/environments/azure/staging` and `azure/prod` — update `kubernetes_version`, plan, apply, verify with `./scripts/verify-platform.sh`.

## Platform components (GitOps)

Platform Helm charts resolve to the **latest stable version** from each upstream Helm repository (no `targetRevision` pin). This is intentional for phase 1; pin versions before production or document promotions in the table below.

Git sources use `cluster.env` for repo URL and branch. See [reference/gitops-configuration.md](../reference/gitops-configuration.md).

## Istio revision tags (advanced)

For canary control planes, use Istio revision labels (`istio.io/rev`) and migrate namespaces gradually. Phase 1 uses a single revision `default`.

## Rollback

- **GitOps:** revert Git commit; Argo CD syncs previous manifests
- **Terraform:** `terraform apply` with previous state or version pin
- **EKS control plane:** AWS does not support downgrade; restore from backup/Veleiro if critical

## Version matrix (maintain manually)

| Date | Env | EKS | Istio | cert-manager | Notes |
|------|-----|-----|-------|--------------|-------|
| TBD | staging | 1.29 | 1.22.x | 1.14.x | initial |
