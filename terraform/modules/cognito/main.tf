################################################################################
# Cognito User Pool
################################################################################

resource "aws_cognito_user_pool" "this" {
  name = "${var.cluster_name}-auth"

  auto_verified_attributes = ["email"]

  admin_create_user_config {
    allow_admin_create_user_only = false
  }

  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = true

    string_attribute_constraints {
      min_length = 1
      max_length = 256
    }
  }
}

################################################################################
# GitHub Identity Provider
################################################################################

resource "aws_cognito_identity_provider" "github" {
  user_pool_id  = aws_cognito_user_pool.this.id
  provider_name = "GitHub"
  provider_type = "OIDC"

  provider_details = {
    client_id                 = var.github_client_id
    client_secret             = var.github_client_secret
    authorize_scopes          = "openid email profile"
    oidc_issuer               = "https://token.actions.githubusercontent.com"
    attributes_request_method = "GET"

    # GitHub doesn't support standard OIDC discovery, so we specify endpoints
    authorize_url  = "https://github.com/login/oauth/authorize"
    token_url      = "https://github.com/login/oauth/access_token"
    attributes_url = "https://api.github.com/user"
    jwks_uri       = "https://token.actions.githubusercontent.com/.well-known/jwks"
  }

  attribute_mapping = {
    email    = "email"
    username = "sub"
    name     = "name"
  }
}

################################################################################
# Cognito Domain (custom: auth.knighttechnology.net)
################################################################################

resource "aws_cognito_user_pool_domain" "this" {
  domain          = "auth.${var.domain_name}"
  user_pool_id    = aws_cognito_user_pool.this.id
  certificate_arn = var.certificate_arn
}

resource "aws_route53_record" "cognito" {
  zone_id = var.zone_id
  name    = "auth.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_cognito_user_pool_domain.this.cloudfront_distribution
    zone_id                = aws_cognito_user_pool_domain.this.cloudfront_distribution_zone_id
    evaluate_target_health = false
  }
}

################################################################################
# App Client (used by ALB for all apps)
################################################################################

resource "aws_cognito_user_pool_client" "alb" {
  name         = "${var.cluster_name}-alb"
  user_pool_id = aws_cognito_user_pool.this.id

  generate_secret = true

  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  allowed_oauth_flows_user_pool_client = true

  supported_identity_providers = ["GitHub"]

  callback_urls = var.callback_urls
  logout_urls   = var.logout_urls

  depends_on = [aws_cognito_identity_provider.github]
}
