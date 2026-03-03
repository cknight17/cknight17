output "bucket_name" {
  value = aws_s3_bucket.this.id
}

output "bucket_arn" {
  value = aws_s3_bucket.this.arn
}

output "irsa_role_arn" {
  value = aws_iam_role.s3_access.arn
}
