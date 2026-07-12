# KubeShip

**KubeShip** is a shipping management API on the platform — Kubernetes + Couchbase.

## Stack

| Layer | Technology |
|-------|------------|
| API | FastAPI (`apps/kubeship/`) |
| UI | Static console at `/` (`apps/kubeship/static/`) |
| Database | Couchbase (`gitops/platform/couchbase/`) |
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

## Web console

After deploy, open the KubeShip Service (or port-forward) at `/`:

```bash
kubectl -n kubeship port-forward svc/kubeship-api 8080:8080
# http://localhost:8080
```

The console supports creating shipments, tracking by code, viewing status history, and updating status.

## Sanity tests

API and UI smoke tests run in CI without Couchbase (in-memory mock):

```bash
cd apps/kubeship
pip install -r requirements-dev.txt
python3 -m pytest -q
```

Covers health, carriers, create → get → track → status update, validation errors, and static UI assets.

## Install order

```text
… → platform-policies → couchbase-config → couchbase → mtls-demo → kubeship
```

## Kind smoke

CI builds `apps/kubeship/Dockerfile`, tags the image as `ghcr.io/panagiod/infra/kubeship:staging`, and loads it into kind before bootstrap (same tag staging cloud uses).

## Delivery (staging → production)

| Environment | Git revision | Image |
|-------------|--------------|-------|
| Staging | `main` | `ghcr.io/panagiod/infra/kubeship:staging` |
| Production | tag `vX.Y.Z` | `ghcr.io/panagiod/infra/kubeship:vX.Y.Z` |

See [delivery.md](delivery.md) for the full promotion workflow and release checklist.

## Credentials (staging lab)

Couchbase admin secret: `gitops/platform/couchbase/base/secret.yaml` (`changeme-staging`).

## LinkedIn summary

> KubeShip — document-based shipping API on Kubernetes with Couchbase, GitOps, and CI-validated Kind smoke.
