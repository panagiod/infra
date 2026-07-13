# GitOps configuration

Per-cluster settings consumed by Kustomize replacements in each environment root.

## Files

| File | Purpose |
|------|---------|
| `gitops/clusters/staging/cluster.env` | Repository URL, target revision, gateway hostname (staging) |
| `gitops/clusters/prod/cluster.env` | Same for production |
| `gitops/clusters/*/applications.yaml` | Argo CD Application definitions |
| `gitops/clusters/*/kustomization.yaml` | Replacements from `cluster.env` into labeled Applications |

## Key variables

| Variable | Description |
|----------|-------------|
| `GITOPS_REPO_URL` | Git repository Argo CD syncs from |
| `GITOPS_TARGET_REVISION` | Branch or tag (production uses immutable release tags; see [delivery/release-pipeline.md](../delivery/release-pipeline.md)) |
| `GATEWAY_HOSTNAME` | Istio ingress gateway hostname for TLS |

Applications labeled `infra.platform/git-source=true` receive `GITOPS_REPO_URL` and `GITOPS_TARGET_REVISION` via Kustomize replacements.

Install order in `applications.yaml` is enforced by Kind smoke wait steps and operational runbooks — not Argo CD `dependsOn`. See [reference/architecture.md](architecture.md) and [bootstrap/mechanics.md](../bootstrap/mechanics.md).
