output "table_name" {
  value = aws_dynamodb_table.this.name
}

output "table_arn" {
  value = aws_dynamodb_table.this.arn
}

output "irsa_role_arn" {
  value = aws_iam_role.dynamodb_access.arn
}
