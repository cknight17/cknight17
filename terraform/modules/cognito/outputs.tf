output "user_pool_id" {
  value = aws_cognito_user_pool.this.id
}

output "user_pool_arn" {
  value = aws_cognito_user_pool.this.arn
}

output "user_pool_domain" {
  value = "auth.${var.domain_name}"
}

output "alb_client_id" {
  value = aws_cognito_user_pool_client.alb.id
}
