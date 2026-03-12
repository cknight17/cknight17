variable "argocd_chart_version" {
  description = "ArgoCD Helm chart version"
  type        = string
  default     = "7.7.5"
}

variable "git_repo_url" {
  description = "Git repository URL for ArgoCD to watch"
  type        = string
}

variable "git_target_revision" {
  description = "Git branch/tag to track"
  type        = string
  default     = "main"
}

variable "argocd_apps_path" {
  description = "Path in the repo where ArgoCD app manifests live"
  type        = string
  default     = "k8s/argocd"
}

variable "domain_name" {
  description = "Root domain name for ArgoCD URL"
  type        = string
  default     = ""
}

variable "github_client_id" {
  description = "GitHub OAuth App client ID for Dex"
  type        = string
  default     = ""
  sensitive   = true
}

variable "github_client_secret" {
  description = "GitHub OAuth App client secret for Dex"
  type        = string
  default     = ""
  sensitive   = true
}

variable "dex_demo_app_client_secret" {
  description = "Shared secret for demo-app oauth2-proxy to authenticate with Dex"
  type        = string
  default     = ""
  sensitive   = true
}
