# Alerting setup

Configure Prometheus rules and Alertmanager receivers after the monitoring stack syncs.

See also: [getting-started.md](../start/getting-started.md) · [verify.md](verify.md)

## Prometheus rules

`cert-manager.yaml` defines alerts for certificate expiry (warning at 7 days, critical at 24 hours). Deployed by the `monitoring-alerts` Argo CD Application.

## Alertmanager receivers

The `monitoring` Application configures Alertmanager routing. **Replace placeholder Slack webhooks** before relying on notifications in production:

1. Create a Slack incoming webhook
2. Edit `gitops/clusters/<env>/applications.yaml` monitoring Helm values
3. Replace `REPLACE_WITH_SLACK_WEBHOOK` with your webhook URL, or use a SealedSecret / ExternalSecret and `api_url_file`

For production, prefer storing webhooks in Kubernetes Secrets rather than committing URLs to Git.

## Verify alerts

```bash
kubectl -n monitoring get prometheusrules
kubectl -n monitoring port-forward svc/kube-prometheus-stack-alertmanager 9093:9093
# Open http://localhost:9093
```
