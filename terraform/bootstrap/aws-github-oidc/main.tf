# Terraform block — pins providers for the one-time GitHub OIDC bootstrap stack
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40"
    }
  }
}

# AWS region where IAM resources are created
variable "aws_region" {
  type    = string
  default = "us-east-1"
}

# GitHub organization or username that owns the repository
variable "github_org" {
  type = string
}

# Repository name (without org), e.g. infra
variable "github_repo" {
  type = string
}

# IAM role name created for GitHub Actions terraform plan
variable "role_name" {
  type    = string
  default = "infra-github-actions-plan"
}

# S3 bucket holding Terraform remote state — plan job needs read/list access
variable "tf_state_bucket" {
  type = string
}

# DynamoDB table used for Terraform state locking
variable "tf_lock_table" {
  type = string
}

provider "aws" {
  region = var.aws_region
}

# GitHub's OIDC issuer — lets Actions exchange a JWT for AWS credentials
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  # GitHub Actions OIDC thumbprint (may be rotated by GitHub — update if assume-role fails)
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

# Role GitHub Actions assumes when running terraform plan on pull requests
resource "aws_iam_role" "github_actions_plan" {
  name = var.role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            # Only workflows from this repository may assume the role
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/${var.github_repo}:*"
          }
        }
      },
    ]
  })
}

# Read-only AWS access so terraform plan can refresh state without mutating resources
resource "aws_iam_role_policy_attachment" "readonly" {
  role       = aws_iam_role.github_actions_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# Allow reading and locking remote state during plan
resource "aws_iam_role_policy" "tf_state" {
  name = "${var.role_name}-tf-state"
  role = aws_iam_role.github_actions_plan.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
        ]
        Resource = [
          "arn:aws:s3:::${var.tf_state_bucket}",
          "arn:aws:s3:::${var.tf_state_bucket}/*",
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
          "dynamodb:DescribeTable",
        ]
        Resource = "arn:aws:dynamodb:${var.aws_region}:*:table/${var.tf_lock_table}"
      },
    ]
  })
}

# Set this as GitHub repository variable AWS_ROLE_ARN
output "github_actions_role_arn" {
  value = aws_iam_role.github_actions_plan.arn
}

output "oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.github.arn
}
