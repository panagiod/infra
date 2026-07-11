# Helm values for the Argo CD chart installed by Terraform
global:
  # In-cluster DNS name for the Argo CD API server service
  domain: argocd-server.argocd.svc.cluster.local

configs:
  params:
    # Run server without TLS inside the cluster; terminate TLS at ingress if needed
    server.insecure: true
  cm:
    application.instanceLabelKey: argocd.argoproj.io/instance
    # Custom health check for nested Application resources (app-of-apps pattern)
    resource.customizations: |
      argoproj.io/Application:
        health.lua: |
          hs = {}
          hs.status = "Progressing"
          hs.message = ""
          if obj.status ~= nil then
            if obj.status.health ~= nil then
              hs.status = obj.status.health.status
              hs.message = obj.status.health.message
            end
          end
          return hs

server:
  service:
    type: ClusterIP
  ingress:
    enabled: false

repoServer:
  replicas: 1

controller:
  replicas: 1

applicationSet:
  enabled: true

notifications:
  enabled: false

dex:
  enabled: false

redis:
  enabled: true
