# Core EKS module: cluster, IAM roles for pods, Helm addons, and Argo CD bootstrap
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    # AWS API access for EKS, IAM, and networking
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40"
    }
    # Installs Helm charts (ALB controller, autoscaler, Argo CD) into the cluster
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.12"
    }
    # Applies the Argo CD root Application manifest after Argo CD is installed
    kubectl = {
      source  = "alekc/kubectl"
      version = ">= 2.0"
    }
  }
}

# Human-readable EKS cluster name (e.g. infra-staging)
variable "cluster_name" {
  type = string
}

# Kubernetes control plane version (major.minor, e.g. 1.29)
variable "kubernetes_version" {
  type = string
}

# VPC that hosts this cluster
variable "vpc_id" {
  type = string
}

# Where worker nodes run — typically private subnets
variable "private_subnet_ids" {
  type = list(string)
}

# Where internet-facing load balancers may be created
variable "public_subnet_ids" {
  type = list(string)
}

# EC2 instance types for the default node group (e.g. t3.large)
variable "node_instance_types" {
  type = list(string)
}

# How many nodes the autoscaler should try to keep ready
variable "node_desired_size" {
  type = number
}

# Floor for cluster autoscaler — never scale below this many nodes
variable "node_min_size" {
  type = number
}

# Ceiling for cluster autoscaler — never scale above this many nodes
variable "node_max_size" {
  type = number
}

# staging or prod — used in tags and Argo CD paths
variable "environment" {
  type = string
}

# Git URL Argo CD reads to sync platform manifests (this repository)
variable "gitops_repo_url" {
  description = "Git repository URL for Argo CD."
  type        = string
}

# Git branch or tag Argo CD tracks (usually main)
variable "gitops_target_revision" {
  description = "Git branch, tag, or commit for Argo CD."
  type        = string
  default     = "main"
}

# Whether the Kubernetes API is reachable from the public internet
variable "cluster_endpoint_public_access" {
  type    = bool
  default = true
}

# IP ranges allowed to hit the public API endpoint (tighten in production)
variable "cluster_endpoint_public_access_cidrs" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}

# CIS / EKS best practice — control plane audit logs (api, audit, authenticator, etc.)
variable "cluster_enabled_log_types" {
  type = list(string)
  default = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler",
  ]
}

# Encrypt Kubernetes secrets at rest in etcd (AWS KMS)
variable "enable_cluster_secrets_encryption" {
  type    = bool
  default = true
}

# Optional extra AWS tags merged onto all resources
variable "tags" {
  type    = map(string)
  default = {}
}

locals {
  # Standard tags so we can filter resources by environment in the AWS console
  tags = merge(var.tags, {
    Environment = var.environment
    ManagedBy   = "terraform"
  })

  # EKS managed addons — always pull the latest compatible version from AWS
  addons = {
    # Internal DNS for Kubernetes services
    coredns = {
      most_recent = true
    }
    # Network proxy on each node
    kube-proxy = {
      most_recent = true
    }
    # AWS VPC CNI plugin — assigns pod IPs from VPC subnets
    vpc-cni = {
      most_recent = true
    }
    # Lets pods mount EBS volumes; uses IRSA role defined below
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.ebs_csi_irsa.arn
    }
  }
}

# Used if we need the AWS account ID for ARNs (reserved for future policies)
data "aws_caller_identity" "current" {}

# Managed EKS control plane and default worker node group
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = ">= 20.0"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  vpc_id                   = var.vpc_id
  subnet_ids               = var.private_subnet_ids
  control_plane_subnet_ids = var.private_subnet_ids

  # API endpoint access: public for kubectl from CI/laptop; private for in-VPC access
  endpoint_public_access       = var.cluster_endpoint_public_access
  endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs
  endpoint_private_access      = true

  enabled_log_types = var.cluster_enabled_log_types

  create_kms_key = var.enable_cluster_secrets_encryption
  encryption_config = var.enable_cluster_secrets_encryption ? {
    resources = ["secrets"]
  } : {}

  # Grants the Terraform caller admin access to the cluster RBAC
  enable_cluster_creator_admin_permissions = true

  addons = local.addons

  # Single general-purpose node pool; cluster-autoscaler adjusts the count
  eks_managed_node_groups = {
    default = {
      instance_types = var.node_instance_types
      min_size       = var.node_min_size
      max_size       = var.node_max_size
      desired_size   = var.node_desired_size

      labels = {
        role = "general"
      }

      tags = local.tags
    }
  }

  tags = local.tags
}

# IAM role the EBS CSI driver pod assumes to create/attach volumes (no node-wide keys)
module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = ">= 5.0"

  name = "${var.cluster_name}-ebs-csi"

  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = local.tags
}

# IAM role for the cluster-autoscaler pod to change Auto Scaling Group sizes
module "cluster_autoscaler_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = ">= 5.0"

  name = "${var.cluster_name}-cluster-autoscaler"

  attach_cluster_autoscaler_policy = true
  cluster_autoscaler_cluster_names = [module.eks.cluster_name]

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:cluster-autoscaler"]
    }
  }

  tags = local.tags
}

# IAM role for AWS Load Balancer Controller to create ALB/NLB for Kubernetes Services
module "aws_load_balancer_controller_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = ">= 5.0"

  name = "${var.cluster_name}-aws-lb-ctrl"

  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }

  tags = local.tags
}

# Watches Ingress/Gateway services and provisions AWS load balancers automatically
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"

  set = [
    {
      name  = "clusterName"
      value = module.eks.cluster_name
    },
    {
      name  = "serviceAccount.create"
      value = "true"
    },
    {
      name  = "serviceAccount.name"
      value = "aws-load-balancer-controller"
    },
    {
      # Links the Kubernetes service account to the IRSA IAM role above
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = module.aws_load_balancer_controller_irsa.arn
    },
    {
      name  = "region"
      value = data.aws_region.current.id
    },
    {
      name  = "vpcId"
      value = var.vpc_id
    },
  ]

  depends_on = [module.eks]
}

# Current AWS region name (e.g. us-east-1) for Helm chart values
data "aws_region" "current" {}

# Scales worker nodes up/down based on pending pods
resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  namespace  = "kube-system"

  set = [
    {
      name  = "autoDiscovery.clusterName"
      value = module.eks.cluster_name
    },
    {
      name  = "awsRegion"
      value = data.aws_region.current.id
    },
    {
      name  = "rbac.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = module.cluster_autoscaler_irsa.arn
    },
    {
      name  = "rbac.serviceAccount.name"
      value = "cluster-autoscaler"
    },
  ]

  depends_on = [module.eks]
}

# GitOps controller — syncs platform charts from this repository into the cluster
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = "argocd"

  create_namespace = true

  values = [templatefile("${path.module}/argocd-values.yaml.tpl", {
    cluster_name = var.cluster_name
    environment  = var.environment
  })]

  depends_on = [module.eks]
}

# Registers the top-level Argo CD Application that points at gitops/clusters/<env>
resource "kubectl_manifest" "argocd_root_app" {
  yaml_body = templatefile("${path.module}/argocd-root-app.yaml.tpl", {
    environment            = var.environment
    gitops_repo_url        = var.gitops_repo_url
    gitops_target_revision = var.gitops_target_revision
  })

  depends_on = [helm_release.argocd]
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

# Sensitive TLS data kubectl and providers need to talk to the API server
output "cluster_certificate_authority_data" {
  value     = module.eks.cluster_certificate_authority_data
  sensitive = true
}

# Used when wiring IRSA trust policies for workload IAM roles
output "oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
}

output "cluster_autoscaler_role_arn" {
  value = module.cluster_autoscaler_irsa.arn
}

output "aws_load_balancer_controller_role_arn" {
  value = module.aws_load_balancer_controller_irsa.arn
}
