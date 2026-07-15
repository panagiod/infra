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

variable "gitops_repo_url" {
  description = "Git repository URL for Argo CD."
  type        = string
}

variable "gitops_target_revision" {
  description = "Git branch, tag, or commit for Argo CD."
  type        = string
  default     = "main"
}

variable "api_server_authorized_ip_ranges" {
  description = "CIDR blocks allowed to reach the public Kubernetes API."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "aks_sku_tier" {
  description = "AKS control plane SKU — Free for lab, Standard for production SLA."
  type        = string
  default     = "Standard"
}

variable "azure_policy_enabled" {
  description = "Enable Azure Policy add-on for CIS-oriented Kubernetes governance."
  type        = bool
  default     = true
}

variable "enable_log_analytics" {
  description = "Provision Log Analytics workspace and Container Insights oms_agent."
  type        = bool
  default     = false
}
