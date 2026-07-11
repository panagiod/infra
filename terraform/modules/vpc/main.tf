# Terraform block: declares which Terraform version and AWS provider we need
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40" # minimum AWS provider; latest stable is allowed
    }
  }
}

# Short name used as a prefix on VPC resources (e.g. infra-staging)
variable "name" {
  description = "Name prefix for VPC resources."
  type        = string
}

# Overall IP range for the virtual network (e.g. 10.10.0.0/16)
variable "cidr" {
  description = "VPC CIDR block."
  type        = string
  default     = "10.0.0.0/16"
}

# List of AWS availability zones to spread subnets across (e.g. us-east-1a/b/c)
variable "azs" {
  description = "Availability zones."
  type        = list(string)
}

# Subnet CIDRs with no direct route to the internet — worker nodes live here
variable "private_subnets" {
  description = "Private subnet CIDRs."
  type        = list(string)
}

# Subnet CIDRs that can reach the internet — used for load balancers and NAT
variable "public_subnets" {
  description = "Public subnet CIDRs."
  type        = list(string)
}

# true = one shared NAT gateway (cheaper staging); false = NAT per AZ (prod HA)
variable "single_nat_gateway" {
  description = "Use a single NAT gateway (cost saving for staging)."
  type        = bool
  default     = false
}

# Extra key/value labels applied to AWS resources for cost and ownership tracking
variable "tags" {
  description = "Additional tags."
  type        = map(string)
  default     = {}
}

locals {
  # Merge caller tags with the tag EKS expects so the cluster can use this VPC
  tags = merge(var.tags, {
    "kubernetes.io/cluster/${var.name}" = "shared"
  })
}

# Reusable community VPC module — creates VPC, subnets, routing, and NAT
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = ">= 5.0" # latest stable module version from the registry

  name = var.name
  cidr = var.cidr

  azs             = var.azs
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets

  # Workers in private subnets need NAT to pull images and reach AWS APIs
  enable_nat_gateway = true
  single_nat_gateway = var.single_nat_gateway

  # Tells Kubernetes which subnets may host internet-facing load balancers
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  # Tells Kubernetes which subnets may host internal load balancers
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }

  tags = local.tags
}

# VPC identifier passed into the EKS module
output "vpc_id" {
  value = module.vpc.vpc_id
}

# Subnet IDs where EKS worker nodes are placed
output "private_subnets" {
  value = module.vpc.private_subnets
}

# Subnet IDs for public-facing load balancers
output "public_subnets" {
  value = module.vpc.public_subnets
}

# Full VPC CIDR — useful for security group rules and peering
output "vpc_cidr_block" {
  value = module.vpc.vpc_cidr_block
}
