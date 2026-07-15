# Prod AKS environment — larger node pool defaults than staging
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.12"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = ">= 2.0"
    }
  }

  backend "azurerm" {}
}

provider "azurerm" {
  features {}
}

provider "helm" {
  kubernetes = {
    host                   = module.aks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.aks.cluster_certificate_authority_data)
    client_certificate     = base64decode(module.aks.kube_client_certificate)
    client_key             = base64decode(module.aks.kube_client_key)
  }
}

provider "kubectl" {
  host                   = module.aks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.aks.cluster_certificate_authority_data)
  client_certificate     = base64decode(module.aks.kube_client_certificate)
  client_key             = base64decode(module.aks.kube_client_key)
  load_config_file       = false
}

module "vnet" {
  source = "../../../modules/azure/vnet"

  location            = var.azure_region
  resource_group_name = var.resource_group_name
  vnet_cidr           = var.vnet_cidr
  aks_subnet_cidr     = var.aks_subnet_cidr
  tags = {
    Project = "infra-platform"
  }
}

module "aks" {
  source = "../../../modules/azure/aks"

  cluster_name        = var.cluster_name
  location            = module.vnet.location
  resource_group_name = module.vnet.resource_group_name
  aks_subnet_id       = module.vnet.aks_subnet_id
  kubernetes_version  = var.kubernetes_version
  environment         = "prod"

  node_vm_size       = var.node_vm_size
  node_desired_count = var.node_desired_count
  node_min_count     = var.node_min_count
  node_max_count     = var.node_max_count

  gitops_repo_url        = var.gitops_repo_url
  gitops_target_revision = var.gitops_target_revision

  api_server_authorized_ip_ranges = var.api_server_authorized_ip_ranges

  sku_tier              = var.aks_sku_tier
  azure_policy_enabled  = var.azure_policy_enabled
  enable_log_analytics  = var.enable_log_analytics
}

output "cluster_name" {
  value = module.aks.cluster_name
}

output "cluster_endpoint" {
  value = module.aks.cluster_endpoint
}

output "resource_group_name" {
  value = module.vnet.resource_group_name
}

output "oidc_issuer_url" {
  value = module.aks.oidc_issuer_url
}
