# Upgrade runbook

## Kubernetes (EKS)

### Staging

1. Update `kubernetes_version` in `terraform/environments/staging/terraform.tfvars`
2. `terraform plan` — review control plane and addon changes
3. `terraform apply`
4. Node groups roll automatically when `kubernetes_version` on the group changes
5. Verify:
   ```bash
   kubectl version
   kubectl -n mtls-demo rollout status deploy/frontend
   kubectl -n istio-system get pods
   ```

### Prod

1. Complete staging soak (minimum 48h recommended for platform changes)
2. Repeat Terraform steps in `terraform/environments/prod`
3. Monitor Grafana Istio and API server dashboards during rollout

### Node pool surge strategy (zero-downtime)

For large jumps, add a new node group on the target version, cordon/drain the old group, then remove it in Terraform.

## Platform components (GitOps)

Platform versions are pinned in Helm values under `gitops/platform/*/overlays/`.

1. Bump chart version in **staging** overlay
2. Commit → Argo CD syncs staging
3. Run smoke tests on `mtls-demo`
4. Promote same version to **prod** overlay
5. Argo CD syncs prod

| Component | Values file |
|-----------|-------------|
| cert-manager | `gitops/platform/cert-manager/overlays/*/values.yaml` |
| Istio | `gitops/platform/istio/overlays/*/values-istiod.yaml` |
| Prometheus | `gitops/platform/monitoring/overlays/*/values.yaml` |

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
