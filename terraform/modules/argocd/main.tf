terraform {
  required_providers {
    kubectl = {
      source  = "alekc/kubectl"
      version = "~> 2.0"
    }
  }
}

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  namespace        = "argocd"
  create_namespace = true
  wait             = true
  timeout          = 600

  values = [yamlencode({
    server = {
      service = {
        type = "ClusterIP"
      }
    }
    configs = {
      params = {
        "server.url" = "https://argocd.${var.domain_name}"
      }
      cm = {
        "url" = "https://argocd.${var.domain_name}"
        "dex.config" = yamlencode({
          connectors = [{
            type = "github"
            id   = "github"
            name = "GitHub"
            config = {
              clientID     = var.github_client_id
              clientSecret = var.github_client_secret
            }
          }]
          staticClients = [{
            id           = "demo-app"
            name         = "Demo App"
            secret       = var.dex_demo_app_client_secret
            redirectURIs = ["https://demo.${var.domain_name}/oauth2/callback"]
          }]
        })
      }
      rbac = {
        "policy.csv" = "g, *, role:readonly"
      }
    }
  })]

  # Reduce resource usage for dev
  set {
    name  = "controller.resources.requests.cpu"
    value = "250m"
  }

  set {
    name  = "controller.resources.requests.memory"
    value = "256Mi"
  }

  set {
    name  = "server.resources.requests.cpu"
    value = "100m"
  }

  set {
    name  = "server.resources.requests.memory"
    value = "128Mi"
  }

  set {
    name  = "repoServer.resources.requests.cpu"
    value = "100m"
  }

  set {
    name  = "repoServer.resources.requests.memory"
    value = "128Mi"
  }
}

################################################################################
# App-of-Apps root application
################################################################################

resource "kubectl_manifest" "argocd_root_app" {
  depends_on = [helm_release.argocd]

  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "root"
      namespace = "argocd"
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.git_repo_url
        targetRevision = var.git_target_revision
        path           = var.argocd_apps_path
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "argocd"
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = ["CreateNamespace=true"]
      }
    }
  })
}
