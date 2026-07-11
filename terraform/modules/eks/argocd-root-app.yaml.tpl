# Argo CD Application rendered by Terraform after Argo CD Helm chart is installed
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cluster-root
  namespace: argocd
  finalizers:
    # Ensures child resources are cleaned up if this Application is deleted
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  # Git source for the app-of-apps manifest list for this environment
  source:
    repoURL: ${gitops_repo_url}
    targetRevision: ${gitops_target_revision}
    path: gitops/clusters/${environment}
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
