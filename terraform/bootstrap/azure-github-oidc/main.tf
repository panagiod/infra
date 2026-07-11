# Terraform block — pins providers for the one-time GitHub OIDC bootstrap stack
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0"
    }
  }
}

# Azure subscription where role assignments are created
variable "subscription_id" {
  type = string
}

# GitHub organization or username that owns the repository
variable "github_org" {
  type = string
}

# Repository name (without org), e.g. infra
variable "github_repo" {
  type = string
}

# Federated credential subject — defaults to pull_request for terraform plan on PRs
variable "github_subject" {
  type    = string
  default = ""
}

# Resource group for the managed identity (created if it does not exist)
variable "identity_resource_group_name" {
  type    = string
  default = "infra-github-oidc-rg"
}

# Azure region for the identity resource group
variable "location" {
  type    = string
  default = "westeurope"
}

# User-assigned managed identity name for GitHub Actions
variable "identity_name" {
  type    = string
  default = "infra-github-actions-plan"
}

# Resource group containing the Terraform state storage account
variable "tf_state_resource_group_name" {
  type = string
}

# Storage account holding Terraform remote state blobs
variable "tf_state_storage_account_name" {
  type = string
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

data "azurerm_client_config" "current" {}

data "azurerm_subscription" "current" {
  subscription_id = var.subscription_id
}

data "azurerm_storage_account" "tf_state" {
  name                = var.tf_state_storage_account_name
  resource_group_name = var.tf_state_resource_group_name
}

locals {
  github_subject = coalesce(
    var.github_subject,
    "repo:${var.github_org}/${var.github_repo}:pull_request"
  )
}

# Resource group hosting the GitHub Actions managed identity
resource "azurerm_resource_group" "oidc" {
  name     = var.identity_resource_group_name
  location = var.location
}

# Managed identity GitHub Actions assumes via OIDC (no long-lived secrets)
resource "azurerm_user_assigned_identity" "github_actions" {
  name                = var.identity_name
  location            = azurerm_resource_group.oidc.location
  resource_group_name = azurerm_resource_group.oidc.name
}

# Trust GitHub's OIDC issuer for pull request workflows from this repository
resource "azurerm_federated_identity_credential" "github" {
  name                = "github-actions-plan"
  resource_group_name = azurerm_resource_group.oidc.name
  parent_id           = azurerm_user_assigned_identity.github_actions.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = "https://token.actions.githubusercontent.com"
  subject             = local.github_subject
}

# Read-only access so terraform plan can refresh Azure resource state
resource "azurerm_role_assignment" "reader" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.github_actions.principal_id
}

# Read/write blobs so Terraform can read and lock remote state during plan
resource "azurerm_role_assignment" "tf_state" {
  scope                = data.azurerm_storage_account.tf_state.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.github_actions.principal_id
}

# Set these as GitHub repository variables for terraform-plan-azure.yml
output "github_actions_client_id" {
  value = azurerm_user_assigned_identity.github_actions.client_id
}

output "tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
}

output "subscription_id" {
  value = var.subscription_id
}

output "github_subject" {
  value = local.github_subject
}
