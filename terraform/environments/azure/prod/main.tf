# Prod AKS environment — larger node pool defaults than staging
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0"
    }
  }

  backend "azurerm" {}
}

provider "azurerm" {
  features {}
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
}

output "cluster_name" {
  value = module.aks.cluster_name
}

output "resource_group_name" {
  value = module.vnet.resource_group_name
}

output "oidc_issuer_url" {
  value = module.aks.oidc_issuer_url
}
