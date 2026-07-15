# cert-manager provider (custom CA)

Phase 1 ships a **bootstrap PKI** using cert-manager's built-in issuers so Istio mTLS works out of the box. This document states what is acceptable in lab environments and what must change before production.

## Lab stance (phase 1 default)

The repository **intentionally** uses an internal bootstrap CA for all environments in GitOps today:

| Property | Lab value | Acceptable for |
|----------|-----------|----------------|
| Root of trust | `bootstrap-issuer` (`selfSigned`) → `platform-ca` | kind, Codespaces, dev/staging clusters |
| CA private key | Kubernetes Secret `platform-ca-secret` in `cert-manager` | Non-compliance, learning, short-lived clusters |
| CA lifetime | ~10 years (`87600h`) | Convenience; not a security control |
| Mesh certs | Short-lived via istio-csr + `platform-ca-issuer` | All phase-1 environments |
| Ingress certs | `platform-ca-issuer` (not public CA) | Lab hostnames (`*.gateway.example.com`) |
| Staging vs prod | Separate overlays, separate clusters | **Never share CA secrets between clusters** |

**Explicit decision:** bootstrap PKI is **dev/lab only**. It is not audited, not HSM-backed, and not suitable for compliance or customer-facing production TLS where public trust is required.

Manifests: `gitops/platform/cert-manager/overlays/`

### Bootstrap flow (unchanged)

1. `bootstrap-issuer` — `selfSigned` ClusterIssuer creates a one-time root
2. `platform-ca` — `Certificate` resource creates a CA cert signed by bootstrap
3. `platform-ca-issuer` — `CA` ClusterIssuer uses the platform CA secret
4. `istio-csr` — requests mesh certificates from `platform-ca-issuer`

## Production stance (required before go-live)

Before calling a cluster production-ready, make an explicit PKI decision and implement it. The mesh layout (istio-csr, ClusterIssuer names, ingress `Certificate` CRs) can stay; **only the issuer implementation changes**.

| Requirement | Lab (current) | Production target |
|-------------|---------------|-------------------|
| Root CA custody | Secret in etcd | Offline ceremony or cloud CA (AWS PCA, Vault, etc.) |
| Intermediate per env | `platform-ca` in cluster | Dedicated intermediate per staging/prod cluster |
| Key storage | Kubernetes Secret | KMS / HSM / Vault |
| Ingress TLS | Platform CA (private trust) | Public CA or org PKI trusted by clients |
| Audit | None | Issuance logging and access control |
| Rotation | cert-manager renewal | Documented runbooks for CA and mesh cert rotation |

### Production checklist

- [ ] Choose issuer option (see below)
- [ ] Provision staging intermediate — validate mesh + ingress with new issuer
- [ ] Provision prod intermediate — separate keys and trust chain
- [ ] Update `platform-ca-issuer` or replace with named ClusterIssuer per overlay
- [ ] Update istio-csr `issuerRef` if ClusterIssuer name changes
- [ ] Confirm alert rules fire for cert expiry (see [alerting.md](alerting.md))
- [ ] Document rotation runbook for platform CA and ingress certs

## Target: your custom provider

Implement a cert-manager **issuer** (or use an existing one) that:

- Signs short-lived certificates (24–72h for mesh, 90d for ingress)
- Stores private keys in **AWS KMS** (or CloudHSM)
- Audits every issuance
- Uses **separate intermediates** for staging vs prod

### Option A: cert-manager + AWS Private CA

Use the upstream [AWS PCA issuer](https://github.com/cert-manager/aws-privateca-issuer) if AWS Private CA meets your policy.

### Option B: Vault PKI issuer

Run Vault (or use HCP Vault) and configure a `Vault` ClusterIssuer.

### Option C: Custom HTTP issuer / signer service

Build a signing API and implement a [cert-manager external issuer](https://cert-manager.io/docs/concepts/issuer/#external-issuers) or contribute a native issuer.

## Integration points (do not change)

| Consumer | cert-manager resource | Notes |
|----------|----------------------|-------|
| Istio mesh | istio-csr → `CertificateRequest` | Keep `platform-ca-issuer` name or update istio-csr Helm values |
| Ingress gateway | `Certificate` in `istio-system` | DNS names from `gateway_hostname` |
| App workloads | optional per-namespace `Certificate` | Same ClusterIssuer |

## Rotation

- Mesh certs: automatic via istio-csr and cert-manager renewal
- Platform CA: rotate by issuing new intermediate, updating `Certificate` CR, rolling istiod
- Root CA: offline ceremony; document in runbook

## Staging vs prod

Use Kustomize overlays:

- `gitops/platform/cert-manager/overlays/staging/` — staging intermediate
- `gitops/platform/cert-manager/overlays/prod/` — prod intermediate

Never share private keys between clusters. Trust bundles may include both intermediates only if cross-cluster mesh is required.

## Metrics and alerts

Alert rules: `gitops/platform/monitoring/alerts/cert-manager.yaml`. Setup guide: [alerting.md](alerting.md).

Alert on:

- `certmanager_certificate_expiration_timestamp_seconds` < 7 days
- istio-csr approval failures
- `istiod` CSR errors
