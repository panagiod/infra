# Bootstrap and Kind smoke

How the platform is installed on **kind** (CI), **local dev**, and **real clusters** (EKS/AKS).

## Models

### Real clusters (EKS / AKS)

1. Terraform provisions the cluster.
2. Argo CD is installed (bootstrap chart or operator).
3. A single **cluster-root** Application points at `gitops/clusters/<env>/`.
4. Argo CD syncs all child Application CRs from Git; components converge with retries.

Install **order** in `applications.yaml` is documentation and Kind smoke enforcement — Argo does not serialize child Applications.

### Kind smoke (CI) and local ordered bootstrap

Kind smoke must **not** register all child Applications at once. That caused:

- Gateway pods with `image: auto` before istiod’s mutating webhook was ready
- istiod/webhook TLS errors when istio-csr certs were not ready
- Stale ReplicaSets when reusing a failed cluster

**CI model:**

1. Install Argo CD only.
2. For each dependency **wave**: materialize **one** (or one parallel group of) Application CR(s), then wait until healthy.
3. Use a **fresh** kind cluster every run (`RECREATE_CLUSTER=true`).
4. Tear down only on success (keeps runner clean on green).

Materialization reads the same `gitops/clusters/<env>/applications.yaml` as production — no duplicate manifests.

```text
Wave 1: materialize cert-manager     → wait
Wave 2: materialize platform-ca      → wait
Wave 3: materialize istio-base       → wait
Wave 4: materialize istio-csr        → wait   # before istiod (cert-manager requirement)
Wave 5: materialize istiod           → wait
Wave 6: materialize istio-gateway + istio-policies (parallel wait)
…
```

`istio-policies` only targets **istio-system** (mesh control plane). App-namespace policies
(e.g. `mtls-demo` PeerAuthentication) ship with their Application so namespaces exist first.

### Istio + cert-manager (istio-csr)

Per [cert-manager istio-csr docs](https://cert-manager.io/docs/usage/istio-csr/):

1. cert-manager + platform CA
2. **istio-csr** (creates `istiod-tls`, `istio-ca-root-cert`)
3. **istiod** with `global.caAddress` and `pilot.env.ENABLE_CA_SERVER=false`

The istiod chart (1.30+) mounts `istiod-tls` and `istio-ca-root-cert` automatically — do **not** duplicate those volumes in Helm values.

### Istio ingress gateway

The gateway Helm chart uses `image: auto` and `inject.istio.io/templates: gateway`. The **istiod mutating webhook** replaces `auto` with `proxyv2` at pod admission.

Therefore:

- Gateway Application must be materialized **after** istiod is healthy.
- No `kubectl set image`, no `ignoreDifferences` on the Deployment image.

## Scripts

| Script / phase | Purpose |
|----------------|---------|
| `BOOTSTRAP_PHASE=argocd` | Install Argo CD |
| `BOOTSTRAP_PHASE=materialize` + `WAIT_APP` | Apply one Application CR from kustomize build |
| `BOOTSTRAP_PHASE=wait` + `WAIT_APP` | Wait for Synced + Healthy |
| `wait-for-app.sh` | materialize → wait (Kind smoke waves) |
| `wait-for-apps.sh` | materialize each app, then parallel wait |
| `BOOTSTRAP_PHASE=cluster-root` | Register cluster-root only (real clusters / local GitOps root) |

## Environment variables

| Variable | Kind smoke | Local default |
|----------|------------|---------------|
| `RECREATE_CLUSTER` | `true` | `false` |
| `CI_POD_DIAGNOSTICS` | `true` | `false` |
| `GITOPS_REVISION` | PR branch | `main` |
| `CLUSTER_ROOT_AUTOMATED_SYNC` | omit (no bulk cluster-root in CI) | `true` |

## Diagnostics

On wait timeout with `CI_POD_DIAGNOSTICS=true`, `scripts/ci-pod-diagnostics.sh` dumps pod events, describe, and logs. After two failures on the same step, read diagnostics before changing GitOps (see `ci-pod-diagnostics.mdc`).
