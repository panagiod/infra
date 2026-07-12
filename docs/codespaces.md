# GitHub Codespaces (browser lab, no own machine)

Run the full platform in a **cloud dev environment** from your browser. Free tier on personal GitHub accounts includes monthly Codespaces quota (see [GitHub billing](https://docs.github.com/billing/managing-billing-for-github-codespaces/about-billing-for-github-codespaces)).

## One-click start

1. Open your repo on GitHub: `https://github.com/panagiod/infra`
2. Click **Code** → **Codespaces** → **Create codespace on main**
3. Wait for the dev container to build (~2–3 min)
4. In the terminal:

```bash
./scripts/start-lab.sh
```

One command bootstraps kind, installs the platform, and runs health checks (~15 min first run).

The repo includes `.devcontainer/` with Docker-in-Docker, kubectl, Helm, Terraform, kind, and GitHub CLI pre-installed.

## Machine size

The devcontainer requests **4 CPU / 8 GB RAM** (Istio + Prometheus need memory). If creation fails or pods OOM:

1. Codespaces → **Change machine type** → pick **4-core** or **8-core**
2. Re-run bootstrap

**Stop the codespace when idle** — you pay (or use quota) only while it runs.

## Access UIs

**Argo CD** (after bootstrap):

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:80
```

Open the **Ports** tab in VS Code / Codespaces and click port `8080`.

**Grafana:**

```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80
```

## Test your branch

Codespaces builds from the branch you select when creating the codespace. To test a feature branch:

1. Create codespace from that branch, **or**
2. `git checkout feat/my-branch` then:

```bash
GITOPS_REVISION=feat/my-branch RECREATE_CLUSTER=true ./scripts/bootstrap-local.sh
```

## Tear down (save quota)

**Recommended — destroy kind and stop the codespace:**

```bash
STOP_CODESPACE=true ./scripts/shutdown-lab.sh
```

**Kind only** (codespace keeps running — still uses quota):

```bash
DESTROY=true ./scripts/bootstrap-local.sh
```

### Automatic shutdown (configured in `.devcontainer/`)

| Trigger | When |
|---------|------|
| **Idle timeout** | 15 minutes with no activity |
| **Max open duration** | 2 hours total |
| **On stop** | kind cluster deleted + Docker pruned |

Full details: [quota-automation.md](quota-automation.md)

## Known limitations

| Topic | Notes |
|-------|-------|
| Docker-in-Docker | kind runs inside Codespaces Docker; use latest kind (installed by setup script) |
| DNS issues | Rare in DinD; if pods fail DNS, recreate cluster with `RECREATE_CLUSTER=true` |
| MetalLB | Works with kind + `hack/kind/metallb.yaml` as on local Docker |
| Full platform weight | First sync 10–15 min; be patient |

## No Codespaces quota?

Use **Option B** — [ci-only.md](ci-only.md): edit on GitHub, open a PR, CI validates with no cluster.

## Option B from this codespace

You can also run CI checks locally before pushing:

```bash
./scripts/ci-validate.sh
```

See [ci-only.md](ci-only.md).

## Alternatives

| Service | Free tier | Fits this repo? |
|---------|-----------|-----------------|
| **GitHub Codespaces** | ~120 core-hrs/mo (personal) | **Best** — devcontainer included |
| **GitPod** | Limited free hours | Works with similar `.devcontainer` |
| **GitHub Actions only** | Public repo minutes | CI smoke, no interactive shell |
| **Play with Kubernetes** | 4h sessions | Too limited for full GitOps bootstrap |
| **Oracle Cloud free VM** | Always-free ARM VM | Possible but more setup |
