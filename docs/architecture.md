# Architecture

## Goals

- Managed Kubernetes on **AWS (EKS)**, **Azure (AKS)**, and **local kind** for zero-cost dev
- Staging and prod clusters with identical **GitOps** platform behavior
- mTLS everywhere via Istio
- Certificates issued and rotated by cert-manager (istio-csr for mesh, ClusterIssuer for ingress)
- GitOps-driven platform lifecycle with Argo CD

## Cluster topology

```mermaid
flowchart TB
  GIT["GitHub: panagiod/infra"]

  subgraph local["Local (kind)"]
    KIND["kind cluster"]
    KIND_ARGO["Argo CD"]
    KIND_PLAT["Platform bundle"]
  end

  subgraph aws["AWS"]
    STG["Staging EKS"]
    PRD["Prod EKS"]
  end

  subgraph azure["Azure"]
    ASTG["Staging AKS"]
    APRD["Prod AKS"]
  end

  GIT --> KIND_ARGO
  GIT --> STG
  GIT --> PRD
  GIT --> ASTG
  GIT --> APRD
  KIND_ARGO --> KIND_PLAT
```

Each environment syncs the same `gitops/platform/` tree; only Terraform (networking + cluster bootstrap) differs by cloud.

## Platform bundle (install order)

Argo CD sync waves enforce bootstrap order:

| Wave | Component | Namespace |
|------|-----------|-----------|
| 0 | cert-manager | cert-manager |
| 1 | ClusterIssuer + mesh CA | cert-manager |
| 2 | Istio base | istio-system |
| 3 | istiod | istio-system |
| 4 | istio-csr | cert-manager |
| 5 | Istio gateway + ingress TLS | istio-system |
| 6 | PeerAuthentication STRICT default | istio-system |
| 7 | kube-prometheus-stack + alert rules | monitoring |
| 8 | Kyverno policies | kyverno |
| 9 | mtls-demo app | mtls-demo |

## Certificate flow

```mermaid
flowchart LR
  CI["ClusterIssuer\nplatform-ca"] --> CM["cert-manager"]
  CM --> CSR["istio-csr"]
  CSR --> ISTIO["istiod"]
  ISTIO --> PODS["Envoy sidecars\nmTLS certs"]
  CM --> ING["Gateway TLS cert"]
```

Phase 1 uses a **platform CA ClusterIssuer** (bootstrap self-signed → CA issuer). Replace with your PKI without changing the mesh layout. See [cert-manager-provider.md](cert-manager-provider.md).

## Networking

| Cloud | Pattern |
|-------|---------|
| **AWS** | VPC with public/private subnets, NAT (single in staging), ALB controller |
| **Azure** | VNet + AKS subnet; Azure LB for `LoadBalancer` services |
| **Local** | kind + MetalLB for LoadBalancer IPs |

Restrict Kubernetes API access in prod via `cluster_endpoint_public_access_cidrs` (AWS) or `api_server_authorized_ip_ranges` (Azure).

## Identity

| Cloud | Cluster integrations | Mesh |
|-------|---------------------|------|
| **AWS** | IRSA for LB controller, autoscaler, EBS CSI | istio-csr |
| **Azure** | AKS managed identity; node pool autoscaling | istio-csr |
| **Local** | N/A | istio-csr |

## Observability

- Prometheus scrapes Kubernetes, Istio, and cert-manager metrics
- Grafana dashboards; Alertmanager routes (configure receivers — see [alerting.md](alerting.md))
- Certificate expiry alerts in `gitops/platform/monitoring/alerts/`

## Security baseline

- Istio `PeerAuthentication` STRICT in `istio-system`
- Kyverno: require Istio injection on demo namespaces
- Separate Terraform state and platform CA per environment
- Lab defaults (open API CIDRs, bootstrap CA) — tighten before production

## State and blast radius

- Separate Terraform state per environment and cloud
- Separate clusters (no shared control plane)
- Shared GitOps repo; per-env overlays in `gitops/clusters/` and `gitops/platform/*/overlays/`

## Upgrade strategy

See [upgrades.md](upgrades.md). Promote staging → prod after soak and `verify-platform.sh`.
