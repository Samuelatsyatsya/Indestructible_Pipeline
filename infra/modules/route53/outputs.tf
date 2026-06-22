output "zone_id" {
  value = aws_route53_zone.internal.zone_id
}

output "db_dns_name" {
  description = "DNS name the app uses to connect to the database"
  value       = aws_route53_record.primary.name
}
