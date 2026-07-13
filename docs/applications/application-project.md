# Application projects

How to add or change applications deployed by this platform.

KubeShip is the reference application: [kubeship.md](kubeship.md).

## In-repo deployment (recommended)

| Item | Location |
|------|----------|
| Application source | `apps/<name>/` |
| GitOps manifests | `gitops/apps/<name>/` |
| Argo CD Application | `gitops/clusters/*/applications.yaml` |
| Install order | `scripts/gitops-install-order.sh` |
| CI / Kind smoke | Infra pull request checks |

## Add a new application

1. Add source under `apps/<name>/` (if applicable).
2. Add GitOps manifests under `gitops/apps/<name>/`.
3. Register the Argo CD Application in `gitops/clusters/staging/applications.yaml` and `prod/applications.yaml`.
4. Append the name to `scripts/gitops-install-order.sh`.
5. Open a pull request — Kind smoke validates the full stack.

## Separate application repository (optional)

Application source may live in a dedicated repository. The platform does not read it unless the Argo CD `Application` `spec.source.repoURL` points there.

```bash
./scripts/scaffold-application-repo.sh myapp ~/myapp panagiod/myapp
```

Enable the Cursor GitHub App on that repository if the Cloud Agent must push to it: https://github.com/settings/installations

## Backing services

Add platform services under `gitops/platform/<service>/` when requirements are defined (for example Couchbase for KubeShip).

## Related

- [reference/architecture.md](../reference/architecture.md) — platform bundle and install order
- [delivery/release-pipeline.md](../delivery/release-pipeline.md) — staging and production promotion
