terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = "~> 2.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  backend "s3" {
    key            = "environments/dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "cknight17-terraform-locks"
    encrypt        = true
    # bucket is provided via -backend-config or backend.hcl
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "cknight17"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", local.cluster_name]
    }
  }
}

provider "kubectl" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", local.cluster_name]
  }
}

################################################################################
# Locals
################################################################################

data "aws_caller_identity" "current" {}

locals {
  cluster_name = "${var.project}-${var.environment}"
}

################################################################################
# Phase 1: VPC + EKS
################################################################################

module "vpc" {
  source = "../../modules/vpc"

  vpc_cidr     = var.vpc_cidr
  cluster_name = local.cluster_name
}

module "eks" {
  source = "../../modules/eks"

  cluster_name        = local.cluster_name
  cluster_version     = var.cluster_version
  vpc_id              = module.vpc.vpc_id
  private_subnet_ids  = module.vpc.private_subnet_ids
  public_subnet_ids   = module.vpc.public_subnet_ids
  node_instance_types = var.node_instance_types
  capacity_type       = var.capacity_type
  node_desired_size   = var.node_desired_size
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size

  admin_principal_arns = [
    "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/cknight"
  ]
}

################################################################################
# Phase 2: ArgoCD
################################################################################

module "argocd" {
  source = "../../modules/argocd"

  git_repo_url         = var.git_repo_url
  git_target_revision  = var.git_target_revision
  argocd_apps_path     = "k8s/argocd"
  argocd_chart_version = var.argocd_chart_version

  depends_on = [module.eks]
}

################################################################################
# DNS + ALB Ingress
################################################################################

module "dns" {
  source = "../../modules/dns"

  domain_name  = var.domain_name
  cluster_name = local.cluster_name

  depends_on = [module.alb_controller]
}

module "alb_controller" {
  source = "../../modules/alb-controller"

  cluster_name      = local.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  vpc_id            = module.vpc.vpc_id

  depends_on = [module.eks]
}

################################################################################
# Phase 3: External Resources (uncomment when ready)
################################################################################

# module "aurora" {
#   source = "../../modules/aurora"
#
#   cluster_name                  = local.cluster_name
#   vpc_id                        = module.vpc.vpc_id
#   private_subnet_ids            = module.vpc.private_subnet_ids
#   eks_cluster_security_group_id = module.eks.cluster_security_group_id
#   oidc_provider_arn             = module.eks.oidc_provider_arn
#   oidc_provider_url             = module.eks.oidc_provider_url
# }

# module "dynamodb" {
#   source = "../../modules/dynamodb"
#
#   cluster_name      = local.cluster_name
#   oidc_provider_arn = module.eks.oidc_provider_arn
#   oidc_provider_url = module.eks.oidc_provider_url
# }

# module "s3" {
#   source = "../../modules/s3"
#
#   cluster_name      = local.cluster_name
#   oidc_provider_arn = module.eks.oidc_provider_arn
#   oidc_provider_url = module.eks.oidc_provider_url
# }
