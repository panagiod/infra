# Azure virtual network module — subnets for AKS nodes and future load balancers
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0"
    }
  }
}

# Azure region, e.g. westeurope
variable "location" {
  type = string
}

# Resource group that will own the VNet (created here if not passed in)
variable "resource_group_name" {
  type = string
}

# VNet address space, e.g. 10.30.0.0/16
variable "vnet_cidr" {
  type    = string
  default = "10.30.0.0/16"
}

# CIDR for the subnet where AKS nodes are placed
variable "aks_subnet_cidr" {
  type    = string
  default = "10.30.1.0/24"
}

variable "tags" {
  type    = map(string)
  default = {}
}

# Container for all networking resources in this environment
resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# Private network isolated from other workloads in the subscription
resource "azurerm_virtual_network" "this" {
  name                = "${var.resource_group_name}-vnet"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = [var.vnet_cidr]
  tags                = var.tags
}

# Subnet delegated to AKS — nodes receive IPs from this range
resource "azurerm_subnet" "aks" {
  name                 = "aks"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.aks_subnet_cidr]
}

output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "vnet_id" {
  value = azurerm_virtual_network.this.id
}

output "aks_subnet_id" {
  value = azurerm_subnet.aks.id
}

output "location" {
  value = azurerm_resource_group.this.location
}
