################################################################################
# Ingress: ArgoCD
################################################################################

resource "kubectl_manifest" "argocd_ingress" {
  yaml_body = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "Ingress"
    metadata = {
      name      = "argocd-server"
      namespace = "argocd"
      annotations = {
        "kubernetes.io/ingress.class"                = "alb"
        "alb.ingress.kubernetes.io/scheme"           = "internet-facing"
        "alb.ingress.kubernetes.io/target-type"      = "ip"
        "alb.ingress.kubernetes.io/certificate-arn"  = aws_acm_certificate.wildcard.arn
        "alb.ingress.kubernetes.io/listen-ports"     = jsonencode([{ HTTPS = 443 }])
        "alb.ingress.kubernetes.io/ssl-redirect"     = "443"
        "alb.ingress.kubernetes.io/healthcheck-path" = "/healthz"
        "alb.ingress.kubernetes.io/backend-protocol" = "HTTPS"
        "alb.ingress.kubernetes.io/group.name"       = var.domain_name
      }
    }
    spec = {
      ingressClassName = "alb"
      rules = [{
        host = "argocd.${var.domain_name}"
        http = {
          paths = [{
            path     = "/"
            pathType = "Prefix"
            backend = {
              service = {
                name = "argocd-server"
                port = {
                  number = 443
                }
              }
            }
          }]
        }
      }]
    }
  })

  depends_on = [aws_acm_certificate_validation.wildcard]
}

################################################################################
# Ingress: Demo App (routes to oauth2-proxy sidecar on port 4180)
################################################################################

resource "kubectl_manifest" "demo_app_ingress" {
  yaml_body = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "Ingress"
    metadata = {
      name      = "demo-app"
      namespace = "demo-app"
      annotations = {
        "kubernetes.io/ingress.class"                = "alb"
        "alb.ingress.kubernetes.io/scheme"           = "internet-facing"
        "alb.ingress.kubernetes.io/target-type"      = "ip"
        "alb.ingress.kubernetes.io/certificate-arn"  = aws_acm_certificate.wildcard.arn
        "alb.ingress.kubernetes.io/listen-ports"     = jsonencode([{ HTTPS = 443 }])
        "alb.ingress.kubernetes.io/ssl-redirect"     = "443"
        "alb.ingress.kubernetes.io/healthcheck-path" = "/ping"
        "alb.ingress.kubernetes.io/group.name"       = var.domain_name
      }
    }
    spec = {
      ingressClassName = "alb"
      rules = [{
        host = "demo.${var.domain_name}"
        http = {
          paths = [{
            path     = "/"
            pathType = "Prefix"
            backend = {
              service = {
                name = "demo-app"
                port = {
                  number = 4180
                }
              }
            }
          }]
        }
      }]
    }
  })

  depends_on = [aws_acm_certificate_validation.wildcard]
}

################################################################################
# Wait for ALB Controller to provision the load balancer
################################################################################

resource "time_sleep" "wait_for_alb" {
  create_duration = "60s"

  depends_on = [
    kubectl_manifest.argocd_ingress,
    kubectl_manifest.demo_app_ingress,
  ]
}

data "aws_lb" "ingress" {
  tags = {
    "elbv2.k8s.aws/cluster"    = var.cluster_name
    "ingress.k8s.aws/resource" = "LoadBalancer"
    "ingress.k8s.aws/stack"    = var.domain_name
  }

  depends_on = [time_sleep.wait_for_alb]
}

################################################################################
# DNS Records (alias to the shared ALB)
################################################################################

resource "aws_route53_record" "argocd" {
  zone_id = aws_route53_zone.this.zone_id
  name    = "argocd.${var.domain_name}"
  type    = "A"

  alias {
    name                   = data.aws_lb.ingress.dns_name
    zone_id                = data.aws_lb.ingress.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "demo" {
  zone_id = aws_route53_zone.this.zone_id
  name    = "demo.${var.domain_name}"
  type    = "A"

  alias {
    name                   = data.aws_lb.ingress.dns_name
    zone_id                = data.aws_lb.ingress.zone_id
    evaluate_target_health = true
  }
}
