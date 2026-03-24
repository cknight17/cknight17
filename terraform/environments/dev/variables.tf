variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region for all resources"
}

variable "project" {
  type    = string
  default = "cknight17"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "cluster_version" {
  type    = string
  default = "1.35"
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}

variable "capacity_type" {
  type    = string
  default = "ON_DEMAND"
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "node_max_size" {
  type    = number
  default = 4
}

variable "git_repo_url" {
  type    = string
  default = "https://github.com/cknight17/cknight17.git"
}

variable "git_target_revision" {
  type    = string
  default = "main"
}

variable "argocd_chart_version" {
  type    = string
  default = "7.7.5"
}

variable "domain_name" {
  type    = string
  default = "knighttechnology.net"
}

variable "github_oauth_client_id" {
  description = "GitHub OAuth App client ID for Cognito federation"
  type        = string
  sensitive   = true
}

variable "github_oauth_client_secret" {
  description = "GitHub OAuth App client secret for Cognito federation"
  type        = string
  sensitive   = true
}
