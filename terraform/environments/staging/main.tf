# Staging environment root module — wires VPC + EKS for pre-production testing
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40"
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

  # Remote state stored in S3 — bucket configured in backend.hcl at init time
  backend "s3" {}
}

# AWS region for all resources in this environment
provider "aws" {
  region = var.aws_region

  # Tags automatically applied to every AWS resource this stack creates
  default_tags {
    tags = {
      Project     = "infra-platform"
      Environment = "staging"
      ManagedBy   = "terraform"
    }
  }
}

# Discover healthy AZs in the account/region for subnet placement
data "aws_availability_zones" "available" {
  state = "available"
}

# Short-lived auth token so Helm/kubectl providers can talk to the new cluster
data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

# Helm provider uses the EKS API endpoint to install charts after the cluster exists
provider "helm" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

# kubectl provider applies the Argo CD root Application manifest
provider "kubectl" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
  load_config_file       = false
}

# Shared VPC module — staging uses a single NAT gateway to save cost
module "vpc" {
  source = "../../modules/vpc"

  name               = var.cluster_name
  cidr               = var.vpc_cidr
  azs                = slice(data.aws_availability_zones.available.names, 0, 3)
  private_subnets    = var.private_subnets
  public_subnets     = var.public_subnets
  single_nat_gateway = var.single_nat_gateway
}

# EKS cluster plus platform bootstrap (Argo CD, autoscaler, ALB controller)
module "eks" {
  source = "../../modules/eks"

  cluster_name       = var.cluster_name
  kubernetes_version = var.kubernetes_version
  environment        = "staging"

  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnets
  public_subnet_ids  = module.vpc.public_subnets

  node_instance_types = var.node_instance_types
  node_desired_size   = var.node_desired_size
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size

  gitops_repo_url        = var.gitops_repo_url
  gitops_target_revision = var.gitops_target_revision

  cluster_endpoint_public_access       = var.cluster_endpoint_public_access
  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "vpc_id" {
  value = module.vpc.vpc_id
}
