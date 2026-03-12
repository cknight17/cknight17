variable "domain_name" {
  description = "Root domain name (e.g. knighttechnology.net)"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name (for ALB tag lookup)"
  type        = string
}

variable "cognito_user_pool_arn" {
  description = "Cognito user pool ARN for ALB auth"
  type        = string
  default     = ""
}

variable "cognito_user_pool_client_id" {
  description = "Cognito app client ID for ALB auth"
  type        = string
  default     = ""
}

variable "cognito_user_pool_domain" {
  description = "Cognito user pool domain (e.g. auth.knighttechnology.net)"
  type        = string
  default     = ""
}

variable "enable_cognito_auth" {
  description = "Enable Cognito authentication on Ingress resources"
  type        = bool
  default     = false
}
