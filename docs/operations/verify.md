# Platform verification

Run after bootstrap to confirm the platform is healthy. Works for **local kind**, **AWS EKS**, and **Azure AKS**.

## One command

```bash
chmod +x scripts/verify-platform.sh
./scripts/verify-platform.sh
```

### Local (kind)

```bash
LOCAL=true ./scripts/verify-platform.sh
```

Uses context `kind-infra-local` (override with `CLUSTER_NAME`).

### AWS

```bash
export AWS_REGION="us-east-1"
export ENVIRONMENT="staging"    # infra-staging by default
./scripts/verify-platform.sh
```

Requires `aws` CLI and `aws eks update-kubeconfig` access (script configures kubeconfig).

### Azure

After `bootstrap-azure.sh` or `az aks get-credentials`, run with the cluster name:

```bash
LOCAL=true CLUSTER_NAME="infra-staging-aks" ./scripts/verify-platform.sh
```

Or configure kubectl context manually and set `LOCAL=true`.

---

## What it checks

The script runs these checks in order (see `scripts/verify-platform.sh` for the authoritative list):

| Check | Pass criteria |
|-------|----------------|
| Nodes | At least one `Ready` node |
| Argo CD | `argocd-server` Running |
| cluster-root | Application exists, Synced/Healthy (**skipped** when `LOCAL=true`) |
| Platform Applications | `cert-manager`, `platform-ca`, `istiod`, `istio-csr`, `istio-gateway`, `istio-ingress-tls`, `istio-policies`, `monitoring`, `monitoring-alerts`, `mtls-demo`, `kubeship` |
| Workloads | Running pods in `cert-manager`, `istio-system` (istiod, gateway), `mtls-demo`, `kubeship` |
| Ingress TLS | `istio-ingressgateway-certs` Certificate Ready |
| mTLS policy | `PeerAuthentication` default mode `STRICT` in `istio-system` |
| mTLS demo | `frontend` → `backend` request over mesh |

**Not checked today:** `istio-base`, `kyverno`, `platform-policies`, `couchbase-config`, `couchbase` — confirm these in Argo CD manually if needed:

```bash
kubectl -n argocd get applications
kubectl -n couchbase get pods
```

Warnings (not hard failures) appear when apps are still syncing — wait 10–15 minutes on first run and re-try.

---

## Manual spot checks

```bash
kubectl -n argocd get applications
kubectl -n cert-manager get clusterissuer
kubectl -n istio-system get svc istio-ingressgateway
kubectl -n istio-system get certificate istio-ingressgateway-certs
kubectl -n mtls-demo get pods
```

**Argo CD admin password:**

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d && echo
```

**mTLS demo:**

```bash
kubectl -n mtls-demo exec deploy/frontend -- wget -qO- http://backend:8080/
```

---

## OIDC setup (AWS, one-time)

Required before `terraform-plan.yml` runs on PRs. Needs an existing S3 state bucket.

```bash
export TF_STATE_BUCKET="your-org-terraform-state"
export TF_LOCK_TABLE="your-org-terraform-locks"
./scripts/setup-github-oidc-aws.sh
```

Details: [github-actions-aws-oidc.md](../delivery/github-actions-aws-oidc.md)

---

## Confirm CI

| Workflow | Trigger |
|----------|---------|
| Kind smoke | PR changes under `gitops/**` or `apps/kubeship/**` |
| KubeShip tests | PR changes under `apps/kubeship/**` |
| Terraform plan (AWS) | PR changes under `terraform/environments/staging\|prod/` + OIDC vars set |
| Terraform plan (Azure) | PR changes under `terraform/environments/azure/**` + Azure OIDC vars |

---

## Troubleshooting

| Symptom | Action |
|---------|--------|
| `cluster-root` missing | Re-run bootstrap script or `terraform apply` |
| Apps `OutOfSync` | `kubectl -n argocd describe application <name>` |
| Istio pods pending | Check cert-manager issuers and `istio-csr` logs |
| Plan workflow skipped | Run OIDC setup; confirm GitHub repository variables |
| Nodes NotReady (cloud) | Check Terraform node pool / subnet config |
| kind context not found | Run `./scripts/bootstrap-local.sh` first |
| Timeouts on local | Increase Docker RAM; see [local-dev.md](../paths/local-dev.md) |
