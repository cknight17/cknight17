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
