variable "cluster_name" {
  description = "EKS cluster name, used for resource naming"
  type        = string
}

variable "domain_name" {
  description = "Root domain name (e.g. knighttechnology.net)"
  type        = string
}

variable "github_client_id" {
  description = "GitHub OAuth App client ID"
  type        = string
  sensitive   = true
}

variable "github_client_secret" {
  description = "GitHub OAuth App client secret"
  type        = string
  sensitive   = true
}

variable "callback_urls" {
  description = "Allowed OAuth callback URLs"
  type        = list(string)
}

variable "logout_urls" {
  description = "Allowed logout URLs"
  type        = list(string)
}
