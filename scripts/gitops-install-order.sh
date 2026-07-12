# Kind smoke / bootstrap Application order — single source of truth.
# shellcheck disable=SC2034
GITOPS_INSTALL_ORDER=(
  cert-manager
  platform-ca
  istio-base
  istio-csr
  istiod
  istio-gateway
  istio-ingress-tls
  istio-policies
  monitoring
  monitoring-alerts
  kyverno
  platform-policies
  mtls-demo
)
