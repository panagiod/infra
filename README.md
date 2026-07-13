# infra

Multi-cloud Kubernetes platform (phase 1): GitOps-managed Istio mTLS, cert-manager, monitoring, Couchbase, and KubeShip — on local kind, AWS EKS, or Azure AKS.

**Documentation:** [docs/README.md](docs/README.md)

**New here?** [docs/start/getting-started.md](docs/start/getting-started.md)

## Repository layout

| Path | Purpose |
|------|---------|
| [`terraform/`](terraform/) | AWS EKS and Azure AKS modules and environments |
| [`gitops/`](gitops/) | Argo CD app-of-apps, platform bundle, applications |
| [`apps/`](apps/) | Application source (KubeShip) |
| [`scripts/`](scripts/) | Bootstrap and verification scripts |
| [`docs/`](docs/) | Formal documentation index |

## Platform summary

- **GitOps:** Argo CD app-of-apps per environment
- **mTLS:** Istio STRICT with cert-manager istio-csr
- **Observability:** kube-prometheus-stack
- **Ingress:** Istio gateway with platform CA TLS
- **Application:** KubeShip (Go API + web console)

Design details: [docs/reference/architecture.md](docs/reference/architecture.md)

## Project status

Phase 1 scaffold — feature-complete in repository; not production-proven until verified on a real cluster. See [docs/reference/project-status.md](docs/reference/project-status.md) and the [GitHub Project backlog](docs/reference/github-project.md).

## Contributing

Branch from `main`, open a pull request. CI validates Terraform and GitOps (Kind smoke on `gitops/**` changes).

- No cluster: [docs/paths/ci-only.md](docs/paths/ci-only.md)
- Cloud Agent: [docs/paths/cloud-agent.md](docs/paths/cloud-agent.md)

## License

Private / internal — adjust as needed.
