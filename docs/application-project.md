# Application project

The **application runs from this repo** (`gitops/apps/myapp/`). You do not need a separate GitHub repo or special bot access for deploy.

| What | Where |
|------|--------|
| Deploy manifests | `gitops/apps/myapp/` (this repo) |
| Argo CD Application | `gitops/clusters/*/applications.yaml` |
| App source (optional) | `apps/myapp/` or a separate repo later |
| CI / Kind smoke | Infra PR checks (same as platform) |

A separate `panagiod/myapp` repo is **optional** for application source code only. The platform does not read it unless you change the Argo `Application` `spec.source.repoURL`.

## Add or change the application

1. Edit manifests under `gitops/apps/myapp/`.
2. App is already in `gitops/clusters/*/applications.yaml` and `scripts/gitops-install-order.sh`.
3. Open a PR — Kind smoke deploys `myapp` in the final wave with `mtls-demo`.

## Image

`gitops/apps/myapp/base/app.yaml` uses `hashicorp/http-echo:0.2.3` until you build and publish your own image. Swap the image when ready.

## Scaffold a separate app repo (optional)

If you later want source code in its own repo:

```bash
./scripts/scaffold-application-repo.sh myapp ~/myapp panagiod/myapp
```

That repo needs the **Cursor GitHub App** enabled (same as infra) if you want the Cloud Agent to push there. Install it at https://github.com/settings/installations → Cursor → add the repo.

## Backing services (later)

Add under `gitops/platform/<service>/` when application requirements are clear.

## Related

- [architecture.md](architecture.md)
- [bootstrap.md](bootstrap.md)
