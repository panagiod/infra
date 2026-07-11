# cert-manager provider (custom CA)

Phase 1 ships a **bootstrap PKI** using cert-manager's built-in issuers so Istio mTLS works out of the box. Replace this with your own cert-manager issuer implementation without changing the mesh architecture.

## Current bootstrap flow

1. `bootstrap-issuer` — `selfSigned` ClusterIssuer creates a one-time root
2. `platform-ca` — `Certificate` resource creates a CA cert signed by bootstrap
3. `platform-ca-issuer` — `CA` ClusterIssuer uses the platform CA secret
4. `istio-csr` — requests mesh certificates from `platform-ca-issuer`

Manifests: `gitops/platform/cert-manager/overlays/`

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

Alert on:

- `certmanager_certificate_expiration_timestamp_seconds` < 7 days
- istio-csr approval failures
- `istiod` CSR errors

See `gitops/platform/monitoring/alerts/cert-manager.yaml`.
