# Create the Grafana admin secret before syncing the monitoring Application in prod.

```bash
kubectl -n monitoring create secret generic grafana-admin-credentials \
  --from-literal=admin-user=admin \
  --from-literal=admin-password="$(openssl rand -base64 24)"
```

The prod `monitoring` Application references this secret via `grafana.admin.existingSecret`.
