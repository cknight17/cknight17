variable "cluster_name" {
  type = string
}

variable "table_name" {
  type    = string
  default = "items"
}

variable "hash_key" {
  type    = string
  default = "PK"
}

variable "range_key" {
  type    = string
  default = "SK"
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
