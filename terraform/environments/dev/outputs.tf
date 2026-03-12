output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "configure_kubectl" {
  value = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region}"
}

output "argocd_initial_password" {
  value = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d"
}

output "oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
}

output "nameservers" {
  value       = module.dns.nameservers
  description = "Set these as nameservers in GoDaddy"
}

output "argocd_url" {
  value = "https://argocd.${var.domain_name}"
}

output "demo_app_url" {
  value = "https://demo.${var.domain_name}"
}

output "ecr_repo_url" {
  value = aws_ecr_repository.demo_app.repository_url
}
