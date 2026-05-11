################################################################################
# Karpenter — on-demand node provisioning for GPU workloads.
#
# Why Karpenter and not cluster-autoscaler:
#   - The cluster has no autoscaler today, so something new is needed regardless.
#   - The GPU workload is idle ~99% of the time and bursts to one node for a
#     few hours; Karpenter consolidates idle nodes in ~30s and natively
#     handles spot + on-demand fallback in a single NodePool.
#   - cluster-autoscaler would need two MNGs + a priority expander to do the
#     same thing.
#
# The default CPU node group (in modules/eks) is untouched and continues to
# host Karpenter itself plus all non-GPU workloads.
################################################################################

locals {
  karpenter_namespace       = "karpenter"
  karpenter_service_account = "karpenter"
  karpenter_chart_version   = "1.1.1"
}

################################################################################
# IAM role for Karpenter-managed nodes (separate from the default MNG role)
################################################################################

resource "aws_iam_role" "karpenter_node" {
  name = "${local.cluster_name}-karpenter-node"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "karpenter_node_worker" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_cni" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_ecr" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_ssm" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Karpenter nodes need an EKS access entry of type EC2_LINUX so they can
# register with the control plane (replaces the aws-auth ConfigMap mapping).
resource "aws_eks_access_entry" "karpenter_nodes" {
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_iam_role.karpenter_node.arn
  type          = "EC2_LINUX"
}

################################################################################
# SQS queue + EventBridge rules for spot interruption handling.
# Karpenter watches this queue; when AWS posts a 2-minute spot warning or a
# rebalance recommendation, Karpenter drains the node gracefully before it dies.
################################################################################

resource "aws_sqs_queue" "karpenter_interruption" {
  name                      = "${local.cluster_name}-karpenter-interruption"
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true
}

data "aws_iam_policy_document" "karpenter_interruption_queue" {
  statement {
    sid       = "EC2InterruptionEvents"
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.karpenter_interruption.arn]

    principals {
      type = "Service"
      identifiers = [
        "events.amazonaws.com",
        "sqs.amazonaws.com",
      ]
    }
  }
}

resource "aws_sqs_queue_policy" "karpenter_interruption" {
  queue_url = aws_sqs_queue.karpenter_interruption.id
  policy    = data.aws_iam_policy_document.karpenter_interruption_queue.json
}

locals {
  karpenter_event_rules = {
    spot_interruption = {
      description = "Spot Instance 2-min interruption warning"
      pattern = {
        source      = ["aws.ec2"]
        detail-type = ["EC2 Spot Instance Interruption Warning"]
      }
    }
    rebalance = {
      description = "Spot rebalance recommendation"
      pattern = {
        source      = ["aws.ec2"]
        detail-type = ["EC2 Instance Rebalance Recommendation"]
      }
    }
    instance_state = {
      description = "EC2 instance state change"
      pattern = {
        source      = ["aws.ec2"]
        detail-type = ["EC2 Instance State-change Notification"]
      }
    }
    scheduled_change = {
      description = "AWS scheduled maintenance affecting an instance"
      pattern = {
        source      = ["aws.health"]
        detail-type = ["AWS Health Event"]
      }
    }
  }
}

resource "aws_cloudwatch_event_rule" "karpenter" {
  for_each = local.karpenter_event_rules

  name          = "${local.cluster_name}-karpenter-${replace(each.key, "_", "-")}"
  description   = each.value.description
  event_pattern = jsonencode(each.value.pattern)
}

resource "aws_cloudwatch_event_target" "karpenter" {
  for_each = local.karpenter_event_rules

  rule      = aws_cloudwatch_event_rule.karpenter[each.key].name
  target_id = "karpenter-interruption-queue"
  arn       = aws_sqs_queue.karpenter_interruption.arn
}

################################################################################
# IAM role for the Karpenter controller (IRSA).
################################################################################

data "aws_iam_policy_document" "karpenter_controller_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:${local.karpenter_namespace}:${local.karpenter_service_account}"]
    }
  }
}

resource "aws_iam_role" "karpenter_controller" {
  name               = "${local.cluster_name}-karpenter-controller"
  assume_role_policy = data.aws_iam_policy_document.karpenter_controller_assume.json
}

resource "aws_iam_policy" "karpenter_controller" {
  name = "${local.cluster_name}-karpenter-controller"
  policy = templatefile("${path.module}/karpenter-controller-policy.json.tftpl", {
    cluster_name           = local.cluster_name
    aws_region             = var.aws_region
    interruption_queue_arn = aws_sqs_queue.karpenter_interruption.arn
    node_role_arn          = aws_iam_role.karpenter_node.arn
  })
}

resource "aws_iam_role_policy_attachment" "karpenter_controller" {
  role       = aws_iam_role.karpenter_controller.name
  policy_arn = aws_iam_policy.karpenter_controller.arn
}

################################################################################
# Karpenter Helm release.
#
# Uses the OCI chart from public ECR (the official distribution channel for
# Karpenter v1+). Lands on the default CPU node group; the GPU NodePool below
# is what it manages.
################################################################################

resource "helm_release" "karpenter" {
  name             = "karpenter"
  repository       = "oci://public.ecr.aws/karpenter"
  chart            = "karpenter"
  version          = local.karpenter_chart_version
  namespace        = local.karpenter_namespace
  create_namespace = true
  wait             = true
  timeout          = 600

  values = [yamlencode({
    settings = {
      clusterName       = module.eks.cluster_name
      interruptionQueue = aws_sqs_queue.karpenter_interruption.name
    }
    serviceAccount = {
      name = local.karpenter_service_account
      annotations = {
        "eks.amazonaws.com/role-arn" = aws_iam_role.karpenter_controller.arn
      }
    }
    controller = {
      resources = {
        requests = { cpu = "200m", memory = "256Mi" }
        limits   = { memory = "512Mi" }
      }
    }
  })]

  depends_on = [
    aws_iam_role_policy_attachment.karpenter_controller,
    aws_eks_access_entry.karpenter_nodes,
  ]
}

################################################################################
# EC2NodeClass: how Karpenter should provision the underlying EC2 instances.
################################################################################

resource "kubectl_manifest" "gpu_nodeclass" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata = {
      name = "gpu"
    }
    spec = {
      # AL2023 NVIDIA GPU-optimized AMI ships drivers + container toolkit.
      amiFamily = "AL2023"
      amiSelectorTerms = [
        { alias = "al2023@latest" },
      ]

      role = aws_iam_role.karpenter_node.name

      # Reuse the existing private subnets (tagged by the VPC module) and the
      # EKS-managed primary cluster security group.
      subnetSelectorTerms = [{
        tags = {
          "kubernetes.io/cluster/${local.cluster_name}" = "shared"
          "kubernetes.io/role/internal-elb"             = "1"
        }
      }]

      securityGroupSelectorTerms = [{
        tags = {
          "aws:eks:cluster-name" = local.cluster_name
        }
      }]

      # ML container images and model checkpoints are big — 200GB on gp3.
      blockDeviceMappings = [{
        deviceName = "/dev/xvda"
        ebs = {
          volumeSize          = "200Gi"
          volumeType          = "gp3"
          encrypted           = true
          deleteOnTermination = true
        }
      }]

      # Tag every instance so the budget filter and any future cost-allocation
      # work can identify GPU spend.
      tags = {
        "karpenter.sh/discovery" = local.cluster_name
        workload                 = "gpu-ml"
      }
    }
  })

  depends_on = [helm_release.karpenter]
}

################################################################################
# NodePool: which pods get GPU nodes, what shapes are allowed, when to consolidate.
################################################################################

resource "kubectl_manifest" "gpu_nodepool" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata = {
      name = "gpu"
    }
    spec = {
      template = {
        metadata = {
          labels = {
            workload         = "gpu-ml"
            "nvidia.com/gpu" = "true"
          }
        }
        spec = {
          # Only GPU pods may land here.
          taints = [{
            key    = "nvidia.com/gpu"
            value  = "true"
            effect = "NoSchedule"
          }]

          nodeClassRef = {
            group = "karpenter.k8s.aws"
            kind  = "EC2NodeClass"
            name  = "gpu"
          }

          requirements = [
            {
              key      = "karpenter.k8s.aws/instance-family"
              operator = "In"
              values   = ["g6", "g5"]
            },
            {
              key      = "karpenter.k8s.aws/instance-size"
              operator = "In"
              values   = ["xlarge", "2xlarge"]
            },
            {
              key      = "kubernetes.io/arch"
              operator = "In"
              values   = ["amd64"]
            },
            {
              key      = "karpenter.sh/capacity-type"
              operator = "In"
              values   = ["spot", "on-demand"]
            },
          ]

          # Terminate nodes after 30 days even if busy, to roll AMI updates.
          expireAfter = "720h"
        }
      }

      disruption = {
        # Kill empty nodes fast — this is the scale-to-zero behavior.
        consolidationPolicy = "WhenEmpty"
        consolidateAfter    = "30s"
      }

      # Hard ceiling on the NodePool. With g6.2xlarge = 8 vCPU, 32 vCPU caps
      # us at roughly 4 nodes simultaneously — defense in depth alongside the
      # AWS Budget alert.
      limits = {
        cpu = "32"
      }

      # Karpenter's two-track ordering: spot is cheaper, so weight it higher.
      # If spot can't be fulfilled (no capacity), Karpenter falls through to
      # on-demand because both are listed in requirements above.
      weight = 100
    }
  })

  depends_on = [kubectl_manifest.gpu_nodeclass]
}
