# infra

Multi-cloud Kubernetes platform (phase 1): **GitOps-managed** Istio mTLS, cert-manager, monitoring, and a demo app — on **local kind**, **AWS EKS**, or **Azure AKS**.

**New here?** → [docs/getting-started.md](docs/getting-started.md)

## Quick start (no cloud cost)

```bash
chmod +x scripts/bootstrap-local.sh
./scripts/bootstrap-local.sh
LOCAL=true ./scripts/verify-platform.sh
```

See [docs/local-dev.md](docs/local-dev.md).

## Quick start (cloud)

| Cloud | Command |
|-------|---------|
| AWS | [docs/QUICKSTART.md](docs/QUICKSTART.md) — `./scripts/bootstrap-aws.sh` |
| Azure | [docs/azure.md](docs/azure.md) — `./scripts/bootstrap-azure.sh` |

## What's in this repo

| Path | Purpose |
|------|---------|
| [`terraform/`](terraform/) | AWS EKS + Azure AKS modules and environments |
| [`gitops/`](gitops/) | Argo CD app-of-apps, platform bundle, mtls-demo |
| [`scripts/`](scripts/) | Bootstrap and verify scripts |
| [`docs/`](docs/) | [Full documentation index](docs/README.md) |

## Platform (same on every cluster)

- **GitOps:** Argo CD app-of-apps per environment
- **mTLS:** Istio STRICT + cert-manager via istio-csr
- **Observability:** kube-prometheus-stack
- **Ingress:** Istio gateway with platform CA TLS

Details: [docs/architecture.md](docs/architecture.md)

## Repository layout

```
terraform/
  modules/
    vpc/, eks/              # AWS
    azure/vnet/, azure/aks/ # Azure
  environments/
    staging/, prod/         # AWS
    azure/staging/, azure/prod/
  bootstrap/                # GitHub OIDC one-time stacks
gitops/
  clusters/                 # Per-env Argo CD roots (staging, prod)
  platform/                 # cert-manager, istio, monitoring, policies
  apps/mtls-demo/
scripts/                    # bootstrap-local, bootstrap-aws, verify-platform, …
hack/kind/                  # kind + MetalLB config for local dev
docs/                       # See docs/README.md
```

## Project status

Phase 1 **scaffold** — feature-complete in repo, **not** production-proven until you run verify on a real cluster. See [docs/project-status.md](docs/project-status.md).

## Contributing

1. Branch from `main` (`feat/`, `fix/`, `chore/`, `docs/`)
2. Open a PR — CI validates Terraform and GitOps (Kind smoke on `gitops/**` changes)
3. No cloud needed for manifest-only changes

## License

Private / internal — adjust as needed.
