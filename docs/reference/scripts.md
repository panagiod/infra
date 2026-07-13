# Scripts reference

Authoritative catalog of repository scripts. Path-specific guides link here instead of duplicating this table.

| Script | Purpose |
|--------|---------|
| `scripts/bootstrap-local.sh` | kind + Argo CD + GitOps; phases: `argocd`, `cluster-root`, `materialize`, `wait` |
| `scripts/wait-for-app.sh` | Wait for one Argo CD Application |
| `scripts/wait-for-apps.sh` | Wait for a dependency wave (parallel apps; Kind smoke) |
| `scripts/bootstrap-aws.sh` | AWS EKS staging and/or prod |
| `scripts/bootstrap-azure.sh` | Azure AKS staging and/or prod |
| `scripts/verify-platform.sh` | Post-bootstrap health checks |
| `scripts/from-here.sh` | Cloud Agent — check, lab, push, status |
| `scripts/start-lab.sh` | Codespaces — bootstrap and verify in one command |
| `scripts/shutdown-lab.sh` | Destroy kind cluster; optionally stop Codespace |
| `scripts/ci-validate.sh` | Run CI checks locally before push |
| `scripts/scaffold-application-repo.sh` | Copy `templates/application/` into a new app repo directory |
| `scripts/setup-github-oidc-aws.sh` | One-time AWS OIDC for Terraform plan on PRs |

Bootstrap semantics and wave order: [bootstrap/mechanics.md](../bootstrap/mechanics.md).
