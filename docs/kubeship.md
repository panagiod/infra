# KubeShip

**KubeShip** is a shipping management API on the platform — Kubernetes + Couchbase.

## Stack

| Layer | Technology |
|-------|------------|
| API | FastAPI (`apps/kubeship/`) |
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
| PATCH | `/api/v1/shipments/{id}/status` | Update status |

## Install order

```text
… → platform-policies → couchbase-config → couchbase → mtls-demo → kubeship
```

## Kind smoke

CI builds `kubeship:ci` from `apps/kubeship/Dockerfile` and loads it into kind before bootstrap.

## Credentials (staging lab)

Couchbase admin secret: `gitops/platform/couchbase/base/secret.yaml` (`changeme-staging`).

## LinkedIn summary

> KubeShip — document-based shipping API on Kubernetes with Couchbase, GitOps, and CI-validated Kind smoke.
