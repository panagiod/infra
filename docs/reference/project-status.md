# Project status

Honest assessment of what this repository delivers today.

## Phase 1 scope

A **multi-cloud Kubernetes platform scaffold** with:

- Terraform for **AWS EKS** and **Azure AKS** (staging + prod)
- Shared **GitOps** platform (Argo CD, Istio mTLS, cert-manager, monitoring, Kyverno, Couchbase, KubeShip)
- Plug-and-play bootstrap scripts (AWS, Azure, local kind)
- CI validation (Terraform, Kustomize, Kind smoke tests, OIDC plan workflows)

## What is complete

| Area | Status |
|------|--------|
| Terraform modules (VPC/EKS, VNet/AKS) | Done |
| Argo CD bootstrap via Terraform | Done |
| GitOps platform bundle (15 Applications) | Done |
| Bootstrap scripts | Done (AWS, Azure, local) |
| CI fmt/validate/kustomize | Done |
| Kind smoke tests on PRs | Done |
| KubeShip application (in-repo) | Done — PR #21 |
| Documentation structure | Reorganized — see [README.md](../README.md) and [MIGRATION.md](../MIGRATION.md) |

Planning and backlog: [github-project.md](github-project.md) (Issues + Project board).

## What is lab / scaffold (not production-proven)

| Item | Notes |
|------|-------|
| Bootstrap PKI | Self-signed platform CA — fine for dev, not for compliance |
| Grafana password | `changeme` on staging; prod expects a secret you create |
| Alertmanager | Rules exist; Slack webhooks are placeholders |
| Helm chart versions | Unpinned — always latest from upstream repos |
| Live cloud soak | Not required to use the repo; recommended before prod |
| GCP | Not started |

## What works without cloud

| Capability | How |
|------------|-----|
| Full GitOps platform | `./scripts/bootstrap-local.sh` |
| KubeShip workload | Syncs on kind like cloud |
| CI validation | PR checks without credentials |
| Terraform logic | `terraform validate` in CI |

## What still needs cloud (eventually)

| Capability | Why |
|------------|-----|
| Terraform plan against real state | OIDC workflows need S3/Storage backend |
| Cloud LB / IAM behavior | kind uses MetalLB; AWS/Azure controllers differ |
| Production DNS + public TLS | Route53 / Azure DNS not wired |
| Cost-controlled staging soak | Short-lived cluster: bootstrap → verify → destroy |

## Recommended maturity path

```text
1. Local kind green     →  ./scripts/bootstrap-local.sh + LOCAL=true ./scripts/verify-platform.sh
2. CI green on PRs      →  kustomize + kind-smoke workflows
3. Cloud staging soak   →  optional, when budget allows (destroy after)
4. Security hardening   →  PKI, API CIDRs, alerting webhooks, Helm pins
5. Prod                 →  only after staging soak
```

## How to call it "done"

For **personal / learning use:** green local bootstrap + verify is enough.

For **production use:** also need PKI decision, alerting configured, API access restricted, Helm versions pinned or promoted, and at least one cloud validation run.
