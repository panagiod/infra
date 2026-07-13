# Application repository template

Starter layout for a **separate application repo** that deploys to the `panagiod/infra` Kubernetes platform via Argo CD.

## What you get

| Path | Purpose |
|------|---------|
| `src/` | Minimal HTTP service (replace with your app) |
| `Dockerfile` | Non-root container image |
| `deploy/` | Kustomize manifests (base + staging/prod overlays) |
| `.github/workflows/ci.yml` | PR checks: Python smoke test + Kustomize validate |
| `.github/workflows/release.yml` | Tag push → build and push image to GHCR |

## Create your app repo

From the **infra** repo root:

```bash
./scripts/scaffold-application-repo.sh myapp ~/projects/myapp
cd ~/projects/myapp
git init && git add . && git commit -m "chore: scaffold application from infra template"
gh repo create panagiod/myapp --private --source=. --push
```

Replace `myapp` and `panagiod/myapp` with your names.

## Configure CI (one-time)

In the new GitHub repo:

1. **Settings → Actions → General** — allow workflows.
2. **Settings → Actions → General → Workflow permissions** — read and write (needed for GHCR push on release).
3. **Packages** — after first release, set package visibility if needed.

Release workflow pushes to `ghcr.io/<owner>/<repo>:<tag>`. After tagging, update `deploy/overlays/staging/kustomization.yaml` `newTag` to match.

## Wire Argo CD (after first image exists)

1. Copy `gitops/clusters/staging/application-myapp.yaml.example` from the infra repo.
2. Set `spec.source.repoURL` to your app repo and `path` to `deploy/overlays/staging`.
3. Append the Application to `gitops/clusters/staging/applications.yaml` **after** platform apps (see install order in infra).
4. Repeat for prod when ready.

See [docs/applications/application-project.md](https://github.com/panagiod/infra/blob/main/docs/applications/application-project.md) in the infra repo for the full checklist.

## Local checks

```bash
python3 src/app.py &
curl -sf localhost:8080/health
kubectl kustomize deploy/overlays/staging
```

## Next steps

- Replace `src/app.py` with your real application.
- Add tests and extend `.github/workflows/ci.yml`.
- Decide backing services based on app needs; add them to infra GitOps later.
