# Security baseline (CIS-aligned)

How this platform maps to the [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes) and cloud-specific hardening (EKS / AKS). This is a **starter posture** — not a certification claim.

Prerequisites: cluster bootstrapped and `platform-policies` Application synced.

## Summary

| Layer | Lab (kind / default staging) | Cloud production target |
|-------|------------------------------|------------------------|
| Pod security (Kyverno) | Enforce: no privileged, no host namespaces/path | Same + tighten Audit→Enforce on caps/seccomp |
| Pod Security Admission | `kubeship`: baseline enforce, restricted audit | Workload namespaces: restricted |
| Network | KubeShip NetworkPolicy (default-deny + explicit allows) | Extend per application namespace |
| Mesh | Istio STRICT mTLS | Same |
| EKS control plane | N/A on kind | Audit logs + KMS secrets encryption (Terraform) |
| AKS control plane | N/A on kind | Azure Policy add-on; optional Log Analytics |
| API access | Open CIDRs in staging examples | Restrict `cluster_endpoint_public_access_cidrs` / `api_server_authorized_ip_ranges` |
| PKI | Bootstrap platform CA (lab only) | See [cert-manager-provider.md](cert-manager-provider.md) |
| Benchmark scan | Optional `run-kube-bench.sh` | Run after cloud bootstrap |

## In-cluster controls (GitOps)

### Kyverno (`gitops/platform/policies/base/`)

| Policy | Mode | CIS theme |
|--------|------|-----------|
| `cis-disallow-privileged-containers` | Enforce | 5.2 — privileged containers |
| `cis-disallow-host-namespaces` | Enforce | 5.2 — hostPID / hostIPC / hostNetwork |
| `cis-disallow-host-path` | Enforce | 5.2 — hostPath volumes |
| `cis-require-run-as-non-root` | Audit | 5.2 — runAsNonRoot |
| `cis-require-drop-all-capabilities` | Audit | 5.2 — drop ALL capabilities |
| `cis-require-seccomp-runtime-default` | Audit | 5.2 — seccomp RuntimeDefault |
| `require-istio-injection-kubeship` | Enforce | Mesh guardrail (custom) |

Platform namespaces (`kube-system`, `cert-manager`, `istio-system`, `monitoring`, `kyverno`, `argocd`, `couchbase`) are **excluded** so Helm operators keep working. New application namespaces inherit enforcement.

Audit policies surface gaps via Kyverno Policy Reports without blocking Istio sidecar mutations. Promote to Enforce after validating workloads.

### Pod Security Admission

`kubeship` namespace labels:

- `pod-security.kubernetes.io/enforce: baseline`
- `pod-security.kubernetes.io/audit: restricted`
- `pod-security.kubernetes.io/warn: restricted`

### Network policies

`gitops/apps/kubeship/base/network-policy.yaml` — default-deny with explicit ingress from `istio-system` and egress to `couchbase`, DNS, and Istio control plane.

## AWS EKS (Terraform)

Module: `terraform/modules/eks/main.tf`

| Control | Implementation |
|---------|----------------|
| Private worker nodes | `private_subnet_ids` for node groups |
| API endpoint CIDR allowlist | `cluster_endpoint_public_access_cidrs` |
| Control plane audit logs | `cluster_enabled_log_types` (api, audit, authenticator, controllerManager, scheduler) |
| Secrets encryption at rest | `enable_cluster_secrets_encryption` + AWS KMS (`create_kms_key`) |
| IRSA | LB controller, cluster-autoscaler, EBS CSI |

Production example: `terraform/environments/prod/terraform.tfvars.example` — restrict API CIDRs.

## Azure AKS (Terraform)

Module: `terraform/modules/azure/aks/main.tf`

| Control | Implementation |
|---------|----------------|
| API authorized IPs | `api_server_authorized_ip_ranges` |
| Azure Policy add-on | `azure_policy_enabled` (default `true`) |
| Control plane SLA | `sku_tier` — `Standard` in prod example |
| Container Insights | `enable_log_analytics` (optional; adds cost) |
| Workload identity | `oidc_issuer_enabled`, `workload_identity_enabled` |

Production example: `terraform/environments/azure/prod/terraform.tfvars.example`.

## CIS benchmark scan

Optional post-bootstrap scan (does not fail `verify-platform.sh` unless you inspect output):

```bash
chmod +x scripts/run-kube-bench.sh
./scripts/run-kube-bench.sh
```

Or with verify:

```bash
RUN_KUBE_BENCH=true ./scripts/verify-platform.sh
```

Benchmark auto-detection:

| Context | Benchmark |
|---------|-----------|
| kind | `k8s-1.23` |
| EKS | `eks-1.7` |
| AKS | `aks-1.7` |

Override: `KUBE_BENCH_BENCHMARK=eks-1.7 ./scripts/run-kube-bench.sh`

Managed Kubernetes (EKS/AKS) node/control-plane checks differ from self-managed CIS sections — treat results as a gap list, not a pass/fail gate for CI.

## Verify policies

```bash
kubectl get clusterpolicies
kubectl get networkpolicies -A
kubectl get ns kubeship --show-labels
```

Kyverno Policy Reports (if enabled in chart):

```bash
kubectl get policyreport -A
```

## Remaining gaps (#26)

- Pin Helm chart versions (`targetRevision: '*'`)
- Promote Kyverno Audit policies to Enforce after sidecar validation
- NetworkPolicies for additional application namespaces
- API CIDR lockdown on staging when using real cloud
- Replace bootstrap PKI — [cert-manager-provider.md](cert-manager-provider.md)
- Image signing / admission scanning (not started)

## Related

- [alerting.md](alerting.md)
- [cert-manager-provider.md](cert-manager-provider.md)
- [reference/architecture.md](../reference/architecture.md)
- [reference/project-status.md](../reference/project-status.md)
