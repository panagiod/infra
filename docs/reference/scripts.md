# Scripts reference

Authoritative catalog of repository scripts. Path-specific guides link here instead of duplicating this table.

## Bootstrap and verification

| Script | Purpose |
|--------|---------|
| `scripts/bootstrap-local.sh` | kind + Argo CD + GitOps; phases: `argocd`, `cluster-root`, `materialize`, `wait` |
| `scripts/bootstrap-aws.sh` | AWS EKS staging and/or prod |
| `scripts/bootstrap-azure.sh` | Azure AKS staging and/or prod |
| `scripts/wait-for-app.sh` | Wait for one Argo CD Application (Kind smoke waves) |
| `scripts/wait-for-apps.sh` | Wait for a dependency wave (parallel apps) |
| `scripts/verify-platform.sh` | Post-bootstrap health checks |
| `scripts/verify-kubeship.sh` | In-cluster KubeShip API sanity (HTTP + shipment lifecycle via Couchbase) |
| `scripts/start-lab.sh` | Codespaces — bootstrap and verify in one command |
| `scripts/shutdown-lab.sh` | Destroy kind cluster; optionally stop Codespace |

## CI and validation

| Script | Purpose |
|--------|---------|
| `scripts/ci-validate.sh` | Run CI checks locally before push |
| `scripts/ci-preflight-gitops.sh` | Fast GitOps preflight (render, namespaces, images, kubeconform) |
| `scripts/validate-gitops-logic.sh` | Install order, no sync-waves, Helm pin rules |
| `scripts/validate-wave-namespaces.sh` | Namespace references vs bootstrap order |
| `scripts/ci-check-images.sh` | Verify container images exist in registry; optional `LIST_OUT` for preload |
| `scripts/ci-preload-kind-images.sh` | Pre-pull images and `kind load` before bootstrap (Kind smoke) |
| `scripts/ci-kubeconform.sh` | kubeconform on rendered manifests |
| `scripts/ci-pod-diagnostics.sh` | Pod diagnostics on Kind smoke wait timeout |
| `scripts/ci_render_gitops.py` | Render GitOps manifests for CI validation |
| `scripts/gitops-install-order.sh` | **Source of truth** for Application install order |

## Agent and scaffolding

| Script | Purpose |
|--------|---------|
| `scripts/from-here.sh` | Cloud Agent — check, lab, push, status |
| `scripts/monitor-ci.sh` | Poll GitHub Actions run status |
| `scripts/scaffold-application-repo.sh` | Copy `templates/application/` into a new app repo directory |
| `scripts/setup-github-oidc-aws.sh` | One-time AWS OIDC for Terraform plan on PRs |
| `scripts/run-kube-bench.sh` | Optional CIS kube-bench Job (kind / EKS / AKS) |
| `scripts/setup-github-project.sh` | One-time GitHub Project board and repo link |
| `scripts/sync-github-backlog.py` | Sync issues from `.github/project-backlog.json` |

Bootstrap semantics and wave order: [mechanics.md](../bootstrap/mechanics.md).
