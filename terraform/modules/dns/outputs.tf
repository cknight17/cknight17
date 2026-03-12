output "zone_id" {
  value = aws_route53_zone.this.zone_id
}

output "nameservers" {
  value       = aws_route53_zone.this.name_servers
  description = "Set these as nameservers in your domain registrar"
}

output "certificate_arn" {
  value = aws_acm_certificate.wildcard.arn
}
