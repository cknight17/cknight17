output "cluster_endpoint" {
  value = aws_rds_cluster.this.endpoint
}

output "cluster_reader_endpoint" {
  value = aws_rds_cluster.this.reader_endpoint
}

output "irsa_role_arn" {
  value = aws_iam_role.aurora_access.arn
}

output "security_group_id" {
  value = aws_security_group.aurora.id
}
