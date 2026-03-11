terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = "cknight17"
      ManagedBy   = "terraform"
      Environment = "bootstrap"
    }
  }
}

################################################################################
# Data Sources
################################################################################

data "aws_caller_identity" "current" {}

variable "admin_username" {
  type        = string
  default     = "cknight"
  description = "IAM username for day-to-day admin access"
}

################################################################################
# Terraform State Backend
################################################################################

resource "aws_s3_bucket" "terraform_state" {
  bucket = "cknight17-terraform-state-${data.aws_caller_identity.current.account_id}"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "terraform_locks" {
  name         = "cknight17-terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

################################################################################
# GitHub Actions OIDC Provider
################################################################################

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

################################################################################
# GitHub Actions IAM Role (assumed via OIDC — no static keys)
################################################################################

resource "aws_iam_role" "github_actions" {
  name = "cknight17-github-actions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:cknight17/cknight17:*"
        }
      }
    }]
  })

  max_session_duration = 3600
}

# AdministratorAccess is acceptable for a portfolio/dev account.
# In production, scope down to only the resources Terraform manages.
resource "aws_iam_role_policy_attachment" "github_actions_admin" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

################################################################################
# Admin IAM User (day-to-day CLI/console access — replaces root usage)
################################################################################

resource "aws_iam_user" "admin" {
  name = var.admin_username
}

resource "aws_iam_user_policy_attachment" "admin" {
  user       = aws_iam_user.admin.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_user_login_profile" "admin" {
  user = aws_iam_user.admin.name
}

resource "aws_iam_access_key" "admin" {
  user = aws_iam_user.admin.name
}

################################################################################
# Digger DynamoDB Lock Table (separate from Terraform state locks)
################################################################################

resource "aws_dynamodb_table" "digger_locks" {
  name         = "cknight17-digger-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"

  attribute {
    name = "PK"
    type = "S"
  }
}

################################################################################
# Outputs
################################################################################

output "state_bucket" {
  value = aws_s3_bucket.terraform_state.id
}

output "lock_table" {
  value = aws_dynamodb_table.terraform_locks.name
}

output "github_actions_role_arn" {
  value       = aws_iam_role.github_actions.arn
  description = "Set this as GitHub Actions secret: AWS_ROLE_ARN"
}

output "digger_lock_table" {
  value = aws_dynamodb_table.digger_locks.name
}

output "admin_user_name" {
  value = aws_iam_user.admin.name
}

output "admin_access_key_id" {
  value = aws_iam_access_key.admin.id
}

output "admin_secret_access_key" {
  value     = aws_iam_access_key.admin.secret
  sensitive = true
}

output "admin_console_password" {
  value     = aws_iam_user_login_profile.admin.password
  sensitive = true
}

output "admin_console_login_url" {
  value = "https://${data.aws_caller_identity.current.account_id}.signin.aws.amazon.com/console"
}
