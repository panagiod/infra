# Local development (zero cloud cost)

> **Start here if you have no cloud budget:** this is the recommended path. Overview: [getting-started.md](getting-started.md).

Run the full GitOps platform on a **kind** cluster in Docker — no AWS, Azure, or Terraform bill.

## Prerequisites

| Tool | Install |
|------|---------|
| [Docker](https://docs.docker.com/get-docker/) | Running daemon |
| [kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation) | `go install sigs.k8s.io/kind@latest` |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | `>= 1.28` |
| [Helm](https://helm.sh/docs/intro/install/) | `>= 3.12` |

Recommended: 8 GB+ RAM for Docker (Istio + Prometheus are heavy).

## Quick start

```bash
chmod +x scripts/bootstrap-local.sh
./scripts/bootstrap-local.sh
```

This will:

1. Create a **kind** cluster named `infra-local` (2 workers)
2. Install **MetalLB** so `LoadBalancer` services work (Istio gateway)
3. Install **Argo CD** via Helm
4. Register the **cluster-root** Application → `gitops/clusters/staging`
5. Wait for core apps (cert-manager, Istio, mtls-demo) to sync

### Verify

```bash
LOCAL=true ./scripts/verify-platform.sh
```

Details: [verify.md](verify.md)

### Tear down

```bash
DESTROY=true ./scripts/bootstrap-local.sh
```

## Configuration

| Variable | Default | Purpose |
|----------|---------|---------|
| `CLUSTER_NAME` | `infra-local` | kind cluster name |
| `ENVIRONMENT` | `staging` | `gitops/clusters/<env>` to sync |
| `GITOPS_REPO_URL` | `https://github.com/panagiod/infra` | Argo CD source |
| `GITOPS_REVISION` | `main` | Git branch or tag |
| `INSTALL_METALLB` | `true` | LoadBalancer support |
| `RECREATE_CLUSTER` | `false` | Delete and recreate if cluster exists |
| `WAIT_TIMEOUT` | `900` | Seconds to wait for core apps |

Use prod GitOps locally:

```bash
ENVIRONMENT=prod ./scripts/bootstrap-local.sh
```

## Testing local Git changes

Argo CD pulls from **GitHub**, not your working tree. To test uncommitted changes:

1. Push to a branch
2. Re-bootstrap or update the root app:

```bash
GITOPS_REVISION=feat/my-branch RECREATE_CLUSTER=true ./scripts/bootstrap-local.sh
```

Or patch the running root Application:

```bash
kubectl -n argocd patch application cluster-root --type merge -p \
  '{"spec":{"source":{"targetRevision":"feat/my-branch"}}}'
```

## Access services

**Argo CD UI**

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:80
# http://localhost:8080
```

**Grafana** (after monitoring syncs)

```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80
```

**Istio ingress** (after gateway syncs)

```bash
kubectl -n istio-system get svc istio-ingressgateway
# MetalLB assigns an IP from 172.18.255.200-250
```

## What works locally vs cloud

| Works on kind | Needs cloud |
|---------------|-------------|
| Argo CD + full GitOps sync | Terraform VPC/EKS/AKS |
| Istio mTLS + mtls-demo | Cloud-specific IAM / IRSA |
| cert-manager + platform CA | OIDC terraform plan against real state |
| Prometheus + Grafana | Production DNS / public TLS trust |
| MetalLB LoadBalancer | AWS LB Controller / Azure LB nuances |

## CI smoke tests

Pull requests that touch `gitops/**` run `.github/workflows/kind-smoke.yml` — an ephemeral kind cluster that installs Argo CD and confirms core Applications become healthy.

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Docker out of memory | Increase Docker RAM; or set `ENVIRONMENT=staging` and wait longer |
| Apps stuck Progressing | `kubectl -n argocd get applications` — first sync can take 10–15 min |
| LoadBalancer `<pending>` | Confirm MetalLB: `kubectl -n metallb-system get pods` |
| Wrong Git revision | Set `GITOPS_REVISION` to your branch |
| Stale cluster | `RECREATE_CLUSTER=true ./scripts/bootstrap-local.sh` |

## Cost comparison

| Path | Cost |
|------|------|
| **kind (this guide)** | $0 |
| AWS staging (always on) | ~$150–300/month |
| AWS staging (destroy when idle) | Pay only while cluster exists |
| GitHub Actions kind smoke | $0 (public repo minutes) |
