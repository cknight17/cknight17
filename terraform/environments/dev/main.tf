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
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
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
  source = "git::https://github.com/cknight17/cknight17.git//terraform/modules/vpc?ref=v0.1.0"

  vpc_cidr     = var.vpc_cidr
  cluster_name = local.cluster_name
}

module "eks" {
  source = "git::https://github.com/cknight17/cknight17.git//terraform/modules/eks?ref=v0.1.0"

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

resource "random_password" "dex_demo_client_secret" {
  length  = 32
  special = false
}

resource "random_password" "oauth2_proxy_cookie_secret" {
  length  = 32
  special = false
}

module "argocd" {
  source = "git::https://github.com/cknight17/cknight17.git//terraform/modules/argocd?ref=v0.1.0"

  git_repo_url         = var.git_repo_url
  git_target_revision  = var.git_target_revision
  argocd_apps_path     = "k8s/argocd"
  argocd_chart_version = var.argocd_chart_version

  domain_name                = var.domain_name
  github_client_id           = var.github_oauth_client_id
  github_client_secret       = var.github_oauth_client_secret
  dex_demo_app_client_secret = random_password.dex_demo_client_secret.result

  depends_on = [module.eks]
}

################################################################################
# DNS + ALB Ingress
################################################################################

module "dns" {
  source = "git::https://github.com/cknight17/cknight17.git//terraform/modules/dns?ref=v0.1.0"

  domain_name  = var.domain_name
  cluster_name = local.cluster_name

  depends_on = [module.alb_controller]
}

################################################################################
# oauth2-proxy secret for demo app (uses ArgoCD Dex as OIDC provider)
################################################################################

resource "kubectl_manifest" "oauth2_proxy_secret" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Secret"
    metadata = {
      name      = "oauth2-proxy"
      namespace = "demo-app"
    }
    type = "Opaque"
    stringData = {
      client-id     = "demo-app"
      client-secret = random_password.dex_demo_client_secret.result
      cookie-secret = random_password.oauth2_proxy_cookie_secret.result
    }
  })

  depends_on = [module.argocd]
}

################################################################################
# ECR Repository for demo app
################################################################################

resource "aws_ecr_repository" "demo_app" {
  name                 = "cknight17/demo-app"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

module "alb_controller" {
  source = "git::https://github.com/cknight17/cknight17.git//terraform/modules/alb-controller?ref=v0.1.0"

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
#   source = "git::https://github.com/cknight17/cknight17.git//terraform/modules/aurora?ref=v0.1.0"
#
#   cluster_name                  = local.cluster_name
#   vpc_id                        = module.vpc.vpc_id
#   private_subnet_ids            = module.vpc.private_subnet_ids
#   eks_cluster_security_group_id = module.eks.cluster_security_group_id
#   oidc_provider_arn             = module.eks.oidc_provider_arn
#   oidc_provider_url             = module.eks.oidc_provider_url
# }

# module "dynamodb" {
#   source = "git::https://github.com/cknight17/cknight17.git//terraform/modules/dynamodb?ref=v0.1.0"
#
#   cluster_name      = local.cluster_name
#   oidc_provider_arn = module.eks.oidc_provider_arn
#   oidc_provider_url = module.eks.oidc_provider_url
# }

# module "s3" {
#   source = "git::https://github.com/cknight17/cknight17.git//terraform/modules/s3?ref=v0.1.0"
#
#   cluster_name      = local.cluster_name
#   oidc_provider_arn = module.eks.oidc_provider_arn
#   oidc_provider_url = module.eks.oidc_provider_url
# }
