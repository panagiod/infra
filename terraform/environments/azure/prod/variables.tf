variable "azure_region" {
  type    = string
  default = "westeurope"
}

variable "resource_group_name" {
  type    = string
  default = "infra-prod-rg"
}

variable "cluster_name" {
  type    = string
  default = "infra-prod-aks"
}

variable "kubernetes_version" {
  type    = string
  default = "1.29"
}

variable "vnet_cidr" {
  type    = string
  default = "10.40.0.0/16"
}

variable "aks_subnet_cidr" {
  type    = string
  default = "10.40.1.0/24"
}

variable "node_vm_size" {
  type    = string
  default = "Standard_D4s_v3"
}

variable "node_desired_count" {
  type    = number
  default = 3
}

variable "node_min_count" {
  type    = number
  default = 3
}

variable "node_max_count" {
  type    = number
  default = 6
}
