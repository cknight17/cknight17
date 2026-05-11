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

################################################################################
# Cameron — namespaced access
################################################################################

output "cameron_access_key_id" {
  value       = aws_iam_access_key.cameron.id
  description = "IAM access key id for cameron (share with him directly)"
}

output "cameron_secret_access_key" {
  value       = aws_iam_access_key.cameron.secret
  sensitive   = true
  description = "IAM secret access key for cameron (sensitive)"
}

output "cameron_kubeconfig" {
  description = "kubeconfig snippet for cameron — fill the AWS creds in his ~/.aws/credentials under [cameron]"
  value = yamlencode({
    apiVersion      = "v1"
    kind            = "Config"
    current-context = "cameron@${module.eks.cluster_name}"
    clusters = [{
      name = module.eks.cluster_name
      cluster = {
        server                     = module.eks.cluster_endpoint
        certificate-authority-data = module.eks.cluster_certificate_authority_data
      }
    }]
    contexts = [{
      name = "cameron@${module.eks.cluster_name}"
      context = {
        cluster   = module.eks.cluster_name
        user      = "cameron"
        namespace = "cameron"
      }
    }]
    users = [{
      name = "cameron"
      user = {
        exec = {
          apiVersion = "client.authentication.k8s.io/v1beta1"
          command    = "aws"
          args       = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region]
          env = [{
            name  = "AWS_PROFILE"
            value = "cameron"
          }]
        }
      }
    }]
  })
}
