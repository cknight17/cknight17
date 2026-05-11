################################################################################
# NVIDIA Kubernetes device plugin.
#
# The AL2023 GPU AMI used by the Karpenter `gpu` NodeClass ships drivers and
# the nvidia container toolkit, but Kubernetes itself only sees GPUs as a
# schedulable resource (nvidia.com/gpu) once this DaemonSet is running.
#
# nodeSelector restricts the DaemonSet to GPU nodes, and the toleration lets
# it bypass the nvidia.com/gpu=true:NoSchedule taint applied by the NodePool.
#
# Installed via helm_release rather than ArgoCD to match the existing pattern
# for cluster-level system addons (alb-controller, argocd itself).
################################################################################

resource "helm_release" "nvidia_device_plugin" {
  name             = "nvidia-device-plugin"
  repository       = "https://nvidia.github.io/k8s-device-plugin"
  chart            = "nvidia-device-plugin"
  version          = "0.17.0"
  namespace        = "kube-system"
  create_namespace = false
  wait             = false # GPU nodes may not exist yet; don't block apply

  values = [yamlencode({
    nodeSelector = {
      workload = "gpu-ml"
    }
    tolerations = [{
      key      = "nvidia.com/gpu"
      operator = "Equal"
      value    = "true"
      effect   = "NoSchedule"
    }]
  })]

  depends_on = [module.eks]
}
