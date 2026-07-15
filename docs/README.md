# Documentation

Formal reference for the **infra** platform repository. Each topic has a single authoritative page; other pages link to it rather than repeat content.

**New to this repository?** Start with [start/getting-started.md](start/getting-started.md).

---

## 1. Choose your path

How you work with this repository depends on your environment.

| Document | When to use |
|----------|-------------|
| [paths/cloud-agent.md](paths/cloud-agent.md) | **Default** — Cursor Cloud Agent (`from-here.sh`); no local Docker |
| [paths/codespaces.md](paths/codespaces.md) | Browser lab via GitHub Codespaces |
| [paths/ci-only.md](paths/ci-only.md) | Contribute via pull request and CI only; no cluster |
| [paths/local-dev.md](paths/local-dev.md) | Local kind cluster; no cloud cost |

---

## 2. Bootstrap a cluster

| Document | Scope |
|----------|--------|
| [bootstrap/aws-quickstart.md](bootstrap/aws-quickstart.md) | AWS EKS — plug-and-play script |
| [bootstrap/aws-manual.md](bootstrap/aws-manual.md) | AWS EKS — manual Terraform |
| [bootstrap/azure.md](bootstrap/azure.md) | Azure AKS — script and manual steps |
| [bootstrap/mechanics.md](bootstrap/mechanics.md) | Kind smoke waves, istio-csr order, bootstrap scripts |

After bootstrap: [operations/verify.md](operations/verify.md).

---

## 3. Operate the platform

| Document | Topic |
|----------|--------|
| [operations/verify.md](operations/verify.md) | Post-deploy health checks |
| [operations/upgrades.md](operations/upgrades.md) | Kubernetes and platform upgrades |
| [operations/alerting.md](operations/alerting.md) | Prometheus rules and Alertmanager |
| [operations/cert-manager-provider.md](operations/cert-manager-provider.md) | Production PKI and issuers |
| [operations/security-baseline.md](operations/security-baseline.md) | CIS-aligned controls (Kyverno, network, EKS/AKS) |
| [operations/quota-automation.md](operations/quota-automation.md) | Codespaces shutdown and CI quota guards |

---

## 4. Delivery and CI integration

| Document | Topic |
|----------|--------|
| [delivery/release-pipeline.md](delivery/release-pipeline.md) | CI → staging → production promotion |
| [delivery/github-actions-aws-oidc.md](delivery/github-actions-aws-oidc.md) | AWS OIDC for Terraform plan on PRs |
| [delivery/github-actions-azure-oidc.md](delivery/github-actions-azure-oidc.md) | Azure OIDC for Terraform plan on PRs |

---

## 5. Reference

| Document | Topic |
|----------|--------|
| [reference/architecture.md](reference/architecture.md) | Topology, platform bundle, security model |
| [reference/project-status.md](reference/project-status.md) | Phase-1 completeness and maturity |
| [reference/github-project.md](reference/github-project.md) | GitHub Issues backlog, Project board, sync workflows |
| [reference/scripts.md](reference/scripts.md) | Bootstrap and validation scripts |
| [reference/gitops-configuration.md](reference/gitops-configuration.md) | Cluster env files and Argo CD roots |

---

## 6. Applications

| Document | Topic |
|----------|--------|
| [applications/kubeship.md](applications/kubeship.md) | KubeShip shipping API and web console |
| [applications/application-project.md](applications/application-project.md) | Adding applications and optional separate repos |

---

## Document conventions

- **Formal tone** — imperative steps, precise terminology, no marketing language.
- **Single source of truth** — one owner per topic; cross-link instead of duplicating tables or command blocks.
- **Navigation** — every page states its scope in the opening paragraph and links to prerequisites and next steps.
- **Future contributions** — follow [.cursor/rules/documentation.mdc](../.cursor/rules/documentation.mdc).
