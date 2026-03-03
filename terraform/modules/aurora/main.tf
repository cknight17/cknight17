################################################################################
# Aurora PostgreSQL Serverless v2
# Phase 3 — Uncomment and configure when ready
################################################################################

resource "aws_rds_cluster" "this" {
  cluster_identifier     = "${var.cluster_name}-aurora"
  engine                 = "aurora-postgresql"
  engine_mode            = "provisioned"
  engine_version         = "16.4"
  database_name          = var.database_name
  master_username        = var.master_username
  manage_master_user_password = true
  storage_encrypted      = true
  skip_final_snapshot    = true # Set false for production

  vpc_security_group_ids = [aws_security_group.aurora.id]
  db_subnet_group_name   = aws_db_subnet_group.this.name

  serverlessv2_scaling_configuration {
    min_capacity = 0.5
    max_capacity = 2.0
  }
}

resource "aws_rds_cluster_instance" "this" {
  cluster_identifier = aws_rds_cluster.this.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.this.engine
  engine_version     = aws_rds_cluster.this.engine_version
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.cluster_name}-aurora"
  subnet_ids = var.private_subnet_ids
}

resource "aws_security_group" "aurora" {
  name_prefix = "${var.cluster_name}-aurora-"
  vpc_id      = var.vpc_id
  description = "Aurora PostgreSQL security group"

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.eks_cluster_security_group_id]
    description     = "Allow access from EKS"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

################################################################################
# IRSA Role for pods to access Aurora via IAM auth
################################################################################

resource "aws_iam_role" "aurora_access" {
  name = "${var.cluster_name}-aurora-access"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${var.oidc_provider_url}:sub" = "system:serviceaccount:${var.app_namespace}:${var.app_service_account}"
          "${var.oidc_provider_url}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "aurora_access" {
  name = "rds-connect"
  role = aws_iam_role.aurora_access.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["rds-db:connect"]
      Resource = "arn:aws:rds-db:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.this.cluster_resource_id}/*"
    }]
  })
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
