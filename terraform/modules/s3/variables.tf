variable "cluster_name" {
  type = string
}

variable "bucket_suffix" {
  type    = string
  default = "app-data"
}

variable "oidc_provider_arn" {
  type = string
}

variable "oidc_provider_url" {
  type = string
}

variable "app_namespace" {
  type    = string
  default = "demo-app"
}

variable "app_service_account" {
  type    = string
  default = "demo-app"
}
