# Azure AKS module — cluster, platform bootstrap (Argo CD), and GitOps root Application
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    # Azure API access for AKS and managed identities
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0"
    }
    # Installs the Argo CD Helm chart into the cluster
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.12"
    }
    # Applies the Argo CD root Application manifest after Argo CD is installed
    kubectl = {
      source  = "alekc/kubectl"
      version = ">= 2.0"
    }
  }
}

variable "cluster_name" {
  type = string
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "aks_subnet_id" {
  type = string
}

variable "kubernetes_version" {
  type = string
}

variable "node_vm_size" {
  type    = string
  default = "Standard_D2s_v3"
}

variable "node_min_count" {
  type    = number
  default = 2
}

variable "node_max_count" {
  type    = number
  default = 4
}

variable "node_desired_count" {
  type    = number
  default = 2
}

# staging or prod — used in tags and Argo CD paths
variable "environment" {
  type = string
}

# Git URL Argo CD reads to sync platform manifests (this repository)
variable "gitops_repo_url" {
  description = "Git repository URL for Argo CD."
  type        = string
}

# Git branch or tag Argo CD tracks (usually main)
variable "gitops_target_revision" {
  description = "Git branch, tag, or commit for Argo CD."
  type        = string
  default     = "main"
}

# IP ranges allowed to reach the public Kubernetes API (tighten in production)
variable "api_server_authorized_ip_ranges" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}

# Azure Policy add-on — CIS-oriented Kubernetes policy initiatives on AKS
variable "azure_policy_enabled" {
  type    = bool
  default = true
}

# Free (dev) or Standard (SLA-backed control plane for production)
variable "sku_tier" {
  type    = string
  default = "Free"
}

# Optional Log Analytics + Container Insights (adds Azure cost)
variable "enable_log_analytics" {
  type    = bool
  default = false
}

variable "tags" {
  type    = map(string)
  default = {}
}

locals {
  tags = merge(var.tags, {
    Environment = var.environment
    ManagedBy   = "terraform"
  })

  log_analytics_name = "${var.cluster_name}-logs"
}

resource "azurerm_log_analytics_workspace" "this" {
  count = var.enable_log_analytics ? 1 : 0

  name                = local.log_analytics_name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = local.tags
}

# Managed Kubernetes control plane — Azure operates the API server and etcd
resource "azurerm_kubernetes_cluster" "this" {
  name                = var.cluster_name
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = var.cluster_name
  kubernetes_version  = var.kubernetes_version

  sku_tier = var.sku_tier

  azure_policy_enabled = var.azure_policy_enabled

  # Default system node pool — AKS cluster autoscaler scales between min and max
  default_node_pool {
    name                 = "default"
    vm_size              = var.node_vm_size
    vnet_subnet_id       = var.aks_subnet_id
    auto_scaling_enabled = true
    min_count            = var.node_min_count
    max_count            = var.node_max_count
    node_count           = var.node_desired_count
  }

  # Cluster admin identity used by Azure to manage the cluster
  identity {
    type = "SystemAssigned"
  }

  # Required for workload identity and modern app authentication patterns
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  # Keep local admin credentials so Terraform can install Helm charts during bootstrap
  local_account_disabled = false

  network_profile {
    network_plugin = "azure"
  }

  # Azure Disk CSI driver — persistent volumes for workloads (e.g. Prometheus)
  storage_profile {
    disk_driver_enabled = true
  }

  # Restrict who can reach the public API endpoint (same idea as EKS public CIDR allowlist)
  api_server_access_profile {
    authorized_ip_ranges = var.api_server_authorized_ip_ranges
  }

  dynamic "oms_agent" {
    for_each = var.enable_log_analytics ? [1] : []
    content {
      log_analytics_workspace_id = azurerm_log_analytics_workspace.this[0].id
    }
  }

  tags = local.tags
}

# GitOps controller — syncs platform charts from this repository into the cluster
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = "argocd"

  create_namespace = true

  # Reuse the same Argo CD values template as the AWS EKS module
  values = [templatefile("${path.module}/../../eks/argocd-values.yaml.tpl", {
    cluster_name = var.cluster_name
    environment  = var.environment
  })]

  depends_on = [azurerm_kubernetes_cluster.this]
}

# Registers the top-level Argo CD Application that points at gitops/clusters/<env>
resource "kubectl_manifest" "argocd_root_app" {
  yaml_body = templatefile("${path.module}/../../eks/argocd-root-app.yaml.tpl", {
    environment            = var.environment
    gitops_repo_url        = var.gitops_repo_url
    gitops_target_revision = var.gitops_target_revision
  })

  depends_on = [helm_release.argocd]
}

output "cluster_name" {
  value = azurerm_kubernetes_cluster.this.name
}

output "cluster_endpoint" {
  value = azurerm_kubernetes_cluster.this.kube_config[0].host
}

# TLS CA cert for Helm and kubectl providers
output "cluster_certificate_authority_data" {
  value     = azurerm_kubernetes_cluster.this.kube_config[0].cluster_ca_certificate
  sensitive = true
}

# Admin client cert/key used by providers during bootstrap (local accounts enabled)
output "kube_client_certificate" {
  value     = azurerm_kubernetes_cluster.this.kube_config[0].client_certificate
  sensitive = true
}

output "kube_client_key" {
  value     = azurerm_kubernetes_cluster.this.kube_config[0].client_key
  sensitive = true
}

output "oidc_issuer_url" {
  value = azurerm_kubernetes_cluster.this.oidc_issuer_url
}

output "kube_config_raw" {
  value     = azurerm_kubernetes_cluster.this.kube_config_raw
  sensitive = true
}
