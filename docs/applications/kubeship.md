# KubeShip

**KubeShip** is a shipping management API on the platform — Kubernetes + Couchbase.

## Stack

| Layer | Technology |
|-------|------------|
| API | Go (`apps/kubeship/cmd/kubeship`) |
| UI | Static console at `/` (`apps/kubeship/static/`) |
| Database | Couchbase (`gitops/platform/couchbase/`) |
| Ingress | Istio VirtualService (`gitops/apps/kubeship/base/ingress.yaml`) |
| Deploy | Argo CD (`gitops/apps/kubeship/`) |
| Mesh | Istio STRICT mTLS in `kubeship` namespace |

## API (Phase 1)

| Method | Path | Description |
|--------|------|-------------|
| GET | `/health` | Liveness + Couchbase connectivity |
| GET | `/api/v1/carriers` | Seed carriers |
| POST | `/api/v1/shipments` | Create shipment |
| GET | `/api/v1/shipments/{id}` | Get shipment |
| GET | `/api/v1/track/{tracking_number}` | Track by code |
| PATCH | `/api/v1/shipments/{id}/status` | Update status (`{"status": "in_transit"}`) |

## Public URL

KubeShip is exposed on the platform Istio ingress gateway:

| Environment | Public host |
|-------------|-------------|
| Staging | `https://kubeship.staging.gateway.example.com` (HTTP on port 80 in staging) |
| Production | `https://kubeship.prod.gateway.example.com` |

### Local kind / Codespaces

After bootstrap, get the gateway LoadBalancer IP and map the host:

```bash
GW_IP=$(kubectl -n istio-system get svc istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "${GW_IP} kubeship.staging.gateway.example.com" | sudo tee -a /etc/hosts
curl -sf http://kubeship.staging.gateway.example.com/health
```

Open **http://kubeship.staging.gateway.example.com** in a browser for the console.

For cloud staging/prod, point DNS at the gateway LoadBalancer and replace `*.gateway.example.com` with your real domain in `cluster.env` / ingress overlays.

### Port-forward (debug)

```bash
kubectl -n kubeship port-forward svc/kubeship-api 8080:8080
# http://localhost:8080
```

## Sanity tests

### Unit tests (no Couchbase)

API and UI tests run in CI with an in-memory store:

```bash
cd apps/kubeship
go test ./...
```

Covers `/health`, carriers, and full shipment lifecycle (`TestShipmentLifecycle`).

### In-cluster API sanity

After bootstrap (kind or cloud), `verify-kubeship.sh` exercises the **live** API through Couchbase:

```bash
chmod +x scripts/verify-kubeship.sh
./scripts/verify-kubeship.sh
```

Kind smoke runs this automatically via `LOCAL=true ./scripts/verify-platform.sh`.

Checks: `GET /health`, `GET /api/v1/carriers`, create → get → track → patch shipment.

## Install order

KubeShip is the last Application in the platform bundle. Full order: [reference/architecture.md](../reference/architecture.md#platform-bundle-install-order) (`scripts/gitops-install-order.sh`).

## Kind smoke

CI builds `apps/kubeship/Dockerfile`, tags the image as `ghcr.io/panagiod/infra/kubeship:staging`, and loads it into kind before bootstrap (same tag staging cloud uses).

## Delivery

Promotion from staging to production: [release-pipeline.md](../delivery/release-pipeline.md).

## Credentials (staging lab)

Couchbase admin secret: `gitops/platform/couchbase/base/secret.yaml` (`changeme-staging`).

## LinkedIn summary

> KubeShip — document-based shipping API on Kubernetes with Couchbase, GitOps, and CI-validated Kind smoke.
