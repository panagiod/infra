# Software licenses

This repository targets **open-source and no-commercial-license** components. Paid cloud services and optional enterprise tiers are documented but not enabled by default.

## Platform components (deployed)

| Component | License | Edition in this repo | Notes |
|-----------|---------|----------------------|-------|
| Kubernetes / kind | Apache 2.0 | OSS | Lab CI |
| Argo CD | Apache 2.0 | Community | No Enterprise features |
| cert-manager + istio-csr | Apache 2.0 | OSS | |
| Istio (base, istiod, gateway) | Apache 2.0 | OSS | Sidecar mesh |
| Kyverno | Apache 2.0 | OSS | Policy engine |
| kube-prometheus-stack | Apache 2.0 | OSS | Prometheus, Alertmanager, **Grafana OSS** |
| MetalLB | Apache 2.0 | OSS | kind LoadBalancer |
| Couchbase Operator | Apache 2.0 | OSS | Helm chart from couchbase-partners |
| **Couchbase Server** | [CE license](https://www.couchbase.com/downloads) | **Community Edition** | Pinned: `couchbase/server:community-8.0.1` in GitOps — **not** Enterprise |
| KubeShip | Internal | — | Application in `apps/kubeship/` |

### Couchbase Community Edition

Enterprise Edition requires a commercial license. GitOps pins the data-plane image explicitly:

```yaml
cluster:
  image: couchbase/server:community-8.0.1
```

Do not change this to `couchbase/server:8.x` or other enterprise tags without a valid license.

## Tooling (not deployed to clusters)

| Tool | License | Notes |
|------|---------|-------|
| Terraform + `hashicorp/*` providers | **BSL 1.1** | Free for normal internal use; not OSI-open-source |
| `alekc/kubectl` provider | MPL 2.0 | Argo root Application manifest |
| `terraform-aws-modules/*` | MPL 2.0 | EKS/VPC wrappers |
| Go, Helm, kustomize, crane | OSS | CI and local dev |

## Optional / documented but not default

| Item | Cost model | Status |
|------|------------|--------|
| AWS Private CA | Paid AWS service | PKI option in [cert-manager-provider.md](../operations/cert-manager-provider.md) |
| HashiCorp Vault / HCP Vault | Commercial tiers possible | Documented PKI alternative only |
| AKS `sku_tier = Standard` | Paid Azure SLA | Prod **example** tfvars only |
| Azure Log Analytics | Paid Azure Monitor | `enable_log_analytics` optional, off by default |
| Couchbase Enterprise / Capella | Commercial | **Not used** |

## Verification

- **Image pin:** `gitops/clusters/*/applications.yaml` → `couchbase` Application `cluster.image`
- **Preflight:** `scripts/ci-check-images.sh` validates rendered images before Kind smoke
- **App sanity:** `scripts/verify-kubeship.sh` exercises live API + Couchbase-backed shipment flow in-cluster

## Related

- [security-baseline.md](../operations/security-baseline.md) — CIS and cloud hardening
- [project-status.md](project-status.md) — lab vs production scope
