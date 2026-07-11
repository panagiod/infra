# AWS region where the staging cluster and VPC are created
variable "aws_region" {
  type    = string
  default = "us-east-1"
}

# EKS cluster name — also used as a prefix for related AWS resources
variable "cluster_name" {
  type    = string
  default = "infra-staging"
}

# Kubernetes version for the control plane and node group
variable "kubernetes_version" {
  type    = string
  default = "1.29"
}

# Staging VPC IP range — separate from prod to avoid overlap if peered later
variable "vpc_cidr" {
  type    = string
  default = "10.10.0.0/16"
}

# One private subnet per AZ for worker nodes
variable "private_subnets" {
  type    = list(string)
  default = ["10.10.1.0/24", "10.10.2.0/24", "10.10.3.0/24"]
}

# One public subnet per AZ for load balancers and NAT
variable "public_subnets" {
  type    = list(string)
  default = ["10.10.101.0/24", "10.10.102.0/24", "10.10.103.0/24"]
}

# true keeps staging cheaper with a single NAT gateway
variable "single_nat_gateway" {
  type    = bool
  default = true
}

# EC2 instance type for staging workers
variable "node_instance_types" {
  type    = list(string)
  default = ["t3.large"]
}

# Target node count before autoscaling reacts
variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 4
}

# Git repository Argo CD syncs (this infra repo)
variable "gitops_repo_url" {
  type = string
}

# Branch Argo CD tracks for platform manifests
variable "gitops_target_revision" {
  type    = string
  default = "main"
}

# Allow kubectl access from outside the VPC during bootstrap
variable "cluster_endpoint_public_access" {
  type    = bool
  default = true
}

# Restrict this list in real deployments to your office/VPN CIDRs
variable "cluster_endpoint_public_access_cidrs" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}
