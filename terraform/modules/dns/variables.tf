variable "domain_name" {
  description = "Root domain name (e.g. knighttechnology.net)"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name (for ALB tag lookup)"
  type        = string
}
