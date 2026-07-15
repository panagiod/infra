# Alerting

Platform monitoring uses Prometheus rules and Alertmanager from `kube-prometheus-stack`.

## Lab default: null receiver

Staging and kind clusters ship with a **null receiver** — alerts are evaluated and visible in the Alertmanager UI, but **nothing is delivered** externally.

| Capability | Lab default |
|------------|-------------|
| Prometheus rules fire | Yes |
| Alerts visible in Alertmanager UI | Yes |
| Slack / email / PagerDuty delivery | **No** |
| Invalid webhook URLs in config | **No** (placeholders removed) |

This is intentional for kind, Codespaces, and staging clusters where on-call routing is not configured. Alerts are for **local inspection only**.

### Inspect alerts locally

```bash
kubectl -n monitoring get prometheusrules
kubectl -n monitoring port-forward svc/kube-prometheus-stack-alertmanager 9093:9093
# Open http://localhost:9093
```

Prometheus UI (if needed):

```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090
# Open http://localhost:9090/alerts
```

## Production: wire on-call receivers

Before relying on notifications in a real environment:

1. Create the notification channel (Slack incoming webhook, PagerDuty integration, etc.).
2. Store credentials in a Kubernetes Secret — **do not commit webhook URLs to Git**.
3. Update the `monitoring` Application Helm values in `gitops/clusters/<env>/applications.yaml`.

### Example: Slack via Secret file reference

Create the secret out of band:

```bash
kubectl -n monitoring create secret generic alertmanager-slack \
  --from-literal=webhook-url='https://hooks.slack.com/services/...'
```

Replace the `alertmanager.config` block with routing and receivers that reference the secret file (kube-prometheus-stack mounts secrets under `/etc/alertmanager/secrets/` when configured via `alertmanager.alertmanagerSpec.secrets`):

```yaml
alertmanager:
  enabled: true
  alertmanagerSpec:
    secrets:
      - alertmanager-slack
  config:
    global:
      resolve_timeout: 5m
    route:
      receiver: default
      group_by: ['alertname', 'namespace']
      routes:
        - matchers:
            - severity = critical
          receiver: critical
        - matchers:
            - severity = warning
          receiver: warning
    receivers:
      - name: default
      - name: critical
        slack_configs:
          - channel: '#platform-critical'
            send_resolved: true
            api_url_file: /etc/alertmanager/secrets/alertmanager-slack/webhook-url
      - name: warning
        slack_configs:
          - channel: '#platform-warning'
            send_resolved: true
            api_url_file: /etc/alertmanager/secrets/alertmanager-slack/webhook-url
```

Prefer Sealed Secrets or External Secrets Operator for GitOps-managed secret delivery in production.

### Verify production routing

1. Confirm Alertmanager config loaded: port-forward to `:9093` → **Status → Config**.
2. Trigger a test alert or wait for a low-risk warning rule to fire.
3. Confirm the notification arrives in the target channel.

## Related

- [cert-manager-provider.md](cert-manager-provider.md) — PKI and certificate expiry context
- [security-baseline.md](security-baseline.md) — production security checklist
- [reference/project-status.md](../reference/project-status.md) — lab vs production-proven scope
