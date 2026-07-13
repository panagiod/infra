# KubeShip

Shipping management API and web console for the platform monorepo.

- API + UI: Go (`cmd/kubeship`), static assets embedded at `/`
- Tests: `go test ./...`
- Public URL: `kubeship.<env>.gateway.example.com` via Istio ingress
- Deploy: `gitops/apps/kubeship/`
- Docs: [docs/applications/kubeship.md](../../docs/applications/kubeship.md)
