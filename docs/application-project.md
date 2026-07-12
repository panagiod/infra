# Application project

How to create a **separate application repository**, track work in GitHub, and connect it to the platform when you are ready to deploy.

Backing services (databases, queues, etc.) are intentionally **out of scope** until you know what the application needs.

## Overview

```text
panagiod/infra          Platform + GitOps (this repo)
panagiod/<your-app>     Application code + deploy manifests + app CI/CD
```

| Repo | Owns |
|------|------|
| **infra** | Cluster, mesh, monitoring, policies, Argo bootstrap |
| **app** | Source code, Dockerfile, Kustomize overlays, build/release workflows |

## Step 1 — Scaffold the application repo

From this repository:

```bash
./scripts/scaffold-application-repo.sh myapp ~/projects/myapp panagiod/myapp
cd ~/projects/myapp
git init && git add . && git commit -m "chore: scaffold myapp from infra template"
gh repo create panagiod/myapp --private --source=. --push
```

The template includes:

- Minimal Python HTTP service in `src/`
- `deploy/` Kustomize layout (base + staging/prod overlays)
- Istio injection + STRICT mTLS `PeerAuthentication` for the app namespace
- PR CI (smoke test + `kubectl kustomize` validate)
- Release workflow (tag `v*` → push image to GHCR)

Template source: [`templates/application/`](../templates/application/).

## Step 2 — GitHub Project (roadmap)

Create a project board manually (the cloud agent token cannot create Projects on your account):

1. GitHub → **Projects** → **New project** → Table or Board.
2. Suggested title: **Platform & Application Roadmap**.
3. Columns or status field values:

| Status | Workstream |
|--------|------------|
| Platform | Infra hardening, cloud soak, Helm pins |
| Application | App repo, CI, first deploy |
| Backing services | Deferred until app requirements are known |
| Done | Completed milestones |

4. Link issues from `panagiod/infra` (and later from your app repo).

Roadmap issues in infra (create or use existing):

- Application repository — scaffold and CI green
- Argo CD — register application on staging
- Backing services — blocked on application requirements
- Cloud staging soak

## Step 3 — Application CI (app repo)

On every PR, `.github/workflows/ci.yml` runs:

- Python compile + `/health` smoke test
- `kubectl kustomize` on all overlays
- `docker build` (no registry push)

### First release

```bash
git tag v0.1.0
git push origin v0.1.0
```

`.github/workflows/release.yml` publishes `ghcr.io/panagiod/myapp:0.1.0` (and related tags).

Then update `deploy/overlays/staging/kustomization.yaml`:

```yaml
images:
  - name: ghcr.io/panagiod/myapp
    newTag: "0.1.0"
```

Commit and push to `main`.

## Granting the Cloud Agent access (no terminal)

The agent can write to **infra** but not **myapp** until you grant access in the GitHub UI:

### Option A — Collaborator (simplest)

1. Open https://github.com/panagiod/myapp/settings/access  
2. **Add people** → invite **`cursor[bot]`** with **Write** role  
3. Tell the agent **“try again”** — it will push fixes without you running commands  

### Option B — Infra workflow (no collaborator)

1. Create a fine-grained PAT: **myapp** repo only, **Contents: Read and write**  
2. Add it to **infra** → Settings → Secrets → Actions → name **`MYAPP_REPO_TOKEN`**  
3. Run **Actions → Sync myapp scaffold → Run workflow** on `panagiod/infra`  

### You do not need to fix myapp for the cluster

Deploy manifests for the running workload live in **infra** (`gitops/apps/myapp/` — see PR #20).  
The `myapp` repo is for **application source code** only; `OWNER/REPO` placeholders there do not affect the platform until you switch the Argo source to the app repo.

## Step 4 — Register with Argo CD (infra repo)

**Current setup:** deploy manifests for `myapp` live in **infra** at `gitops/apps/myapp/`. Application **source code** stays in `panagiod/myapp`. The Argo CD `Application` CR is in `gitops/clusters/*/applications.yaml` (after `mtls-demo`).

When a GHCR image is published from the app repo:

1. Update `gitops/apps/myapp/base/app.yaml` image to `ghcr.io/panagiod/myapp:<tag>`.
2. Open a PR in **infra** — Kind smoke materializes `myapp` in the final wave.

**Later (optional):** move `deploy/` to the app repo and point `spec.source.repoURL` at `https://github.com/panagiod/myapp`.

## Step 5 — Backing services (later)

When the application design is clear:

1. Add shared services under `gitops/platform/<service>/` in **infra**.
2. Insert them in `applications.yaml` **before** the app Application.
3. Reference connection strings via Kubernetes Secrets (External Secrets / Sealed Secrets / cloud secret manager — not committed to Git).

## Repository strategy summary

| Decision | Recommendation |
|----------|----------------|
| App code location | Separate repo |
| Deploy manifests | In app repo (`deploy/`) |
| Argo `Application` CR | Infra repo (`applications.yaml`) — Pattern A |
| Platform CI | Infra PRs — no app build required |
| App CI | App PRs — test, build, release |
| Backing services | Infra GitOps, added when app needs are known |

## Related docs

- [architecture.md](architecture.md) — platform topology
- [project-status.md](project-status.md) — current maturity
- [bootstrap.md](bootstrap.md) — install order and Kind smoke waves
- [ci-only.md](ci-only.md) — contributing to infra without a cluster
