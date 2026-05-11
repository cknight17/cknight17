################################################################################
# Namespaced access for Cameron.
#
# Cameron gets:
#   - An IAM user (creds in Terraform outputs)
#   - An EKS access entry that maps the IAM user to a custom k8s group
#   - A `cameron` namespace with a ResourceQuota capping GPU/CPU/memory use
#   - A Role + RoleBinding granting full perms inside that namespace only
#
# He cannot modify infrastructure. He cannot schedule into other namespaces.
# A ResourceQuota of 2 GPUs is intentional: it's the NodePool ceiling
# anyway (32 vCPU ÷ 8 vCPU/node × 1 GPU/node = 4 GPUs max), and 2 leaves
# room for me to also experiment without contention.
################################################################################

locals {
  cameron_username  = "cameron"
  cameron_namespace = "cameron"
  cameron_k8s_group = "cameron-users"
}

resource "aws_iam_user" "cameron" {
  name = local.cameron_username
  tags = {
    Purpose = "EKS namespaced access"
  }
}

resource "aws_iam_access_key" "cameron" {
  user = aws_iam_user.cameron.name
}

# No IAM policies — all cluster auth is via the EKS access entry below.
# He doesn't need any AWS permissions outside of `eks:DescribeCluster` to
# fetch the token, which the access entry doesn't grant. So we attach a
# tiny inline policy for the get-token call.
resource "aws_iam_user_policy" "cameron_eks_describe" {
  name = "eks-describe-cluster"
  user = aws_iam_user.cameron.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "eks:DescribeCluster"
      Resource = "arn:aws:eks:${var.aws_region}:${data.aws_caller_identity.current.account_id}:cluster/${local.cluster_name}"
    }]
  })
}

resource "aws_eks_access_entry" "cameron" {
  cluster_name      = module.eks.cluster_name
  principal_arn     = aws_iam_user.cameron.arn
  kubernetes_groups = [local.cameron_k8s_group]
}

resource "kubectl_manifest" "cameron_namespace" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Namespace"
    metadata = {
      name = local.cameron_namespace
      labels = {
        owner = local.cameron_username
      }
    }
  })

  depends_on = [module.eks]
}

resource "kubectl_manifest" "cameron_quota" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "ResourceQuota"
    metadata = {
      name      = "default"
      namespace = local.cameron_namespace
    }
    spec = {
      hard = {
        "requests.cpu"            = "16"
        "requests.memory"         = "64Gi"
        "requests.nvidia.com/gpu" = "2"
        "limits.nvidia.com/gpu"   = "2"
      }
    }
  })

  depends_on = [kubectl_manifest.cameron_namespace]
}

resource "kubectl_manifest" "cameron_role" {
  yaml_body = yamlencode({
    apiVersion = "rbac.authorization.k8s.io/v1"
    kind       = "Role"
    metadata = {
      name      = "namespace-admin"
      namespace = local.cameron_namespace
    }
    rules = [{
      apiGroups = ["*"]
      resources = ["*"]
      verbs     = ["*"]
    }]
  })

  depends_on = [kubectl_manifest.cameron_namespace]
}

resource "kubectl_manifest" "cameron_rolebinding" {
  yaml_body = yamlencode({
    apiVersion = "rbac.authorization.k8s.io/v1"
    kind       = "RoleBinding"
    metadata = {
      name      = "namespace-admin"
      namespace = local.cameron_namespace
    }
    roleRef = {
      apiGroup = "rbac.authorization.k8s.io"
      kind     = "Role"
      name     = "namespace-admin"
    }
    subjects = [{
      kind     = "Group"
      name     = local.cameron_k8s_group
      apiGroup = "rbac.authorization.k8s.io"
    }]
  })

  depends_on = [kubectl_manifest.cameron_role]
}
