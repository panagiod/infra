# Documentation index

**New here?** Start with [getting-started.md](getting-started.md).

## Start here

| Doc | Audience |
|-----|----------|
| [getting-started.md](getting-started.md) | Everyone — decision tree and golden paths |
| [project-status.md](project-status.md) | What's complete, what's lab-only, what needs cloud |
| [local-dev.md](local-dev.md) | No cloud budget — kind cluster in Docker |

## Bootstrap (create a cluster)

| Doc | Cloud |
|-----|-------|
| [QUICKSTART.md](QUICKSTART.md) | AWS — plug-and-play script |
| [azure.md](azure.md) | Azure — plug-and-play script |
| [bootstrap.md](bootstrap.md) | AWS — detailed manual Terraform steps |

## Verify and operate

| Doc | Topic |
|-----|-------|
| [verify.md](verify.md) | Health checks (local, AWS, Azure) |
| [upgrades.md](upgrades.md) | Kubernetes and platform upgrades |
| [alerting.md](alerting.md) | Prometheus rules and Alertmanager |
| [cert-manager-provider.md](cert-manager-provider.md) | Replace bootstrap CA with production PKI |

## CI and automation

| Doc | Topic |
|-----|-------|
| [github-actions-aws-oidc.md](github-actions-aws-oidc.md) | Terraform plan on PRs (AWS) |
| [github-actions-azure-oidc.md](github-actions-azure-oidc.md) | Terraform plan on PRs (Azure) |

## Architecture

| Doc | Topic |
|-----|-------|
| [architecture.md](architecture.md) | Topology, platform bundle, security model |

## Scripts reference

| Script | Purpose |
|--------|---------|
| `scripts/bootstrap-local.sh` | kind + Argo CD + GitOps ($0) |
| `scripts/bootstrap-aws.sh` | AWS EKS staging/prod |
| `scripts/bootstrap-azure.sh` | Azure AKS staging/prod |
| `scripts/verify-platform.sh` | Post-bootstrap health checks |
| `scripts/setup-github-oidc-aws.sh` | One-time AWS OIDC for CI plan |

## GitOps configuration

| File | Purpose |
|------|---------|
| `gitops/clusters/staging/cluster.env` | Repo URL, branch, gateway hostname (staging) |
| `gitops/clusters/prod/cluster.env` | Same for prod |
| `gitops/clusters/*/applications.yaml` | Argo CD Application definitions |

Kustomize replaces `GITOPS_REPO_URL` and `GITOPS_TARGET_REVISION` from `cluster.env` into labeled Applications.
