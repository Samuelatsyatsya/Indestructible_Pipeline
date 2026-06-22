output "secret_arn" {
  description = "ARN of the DB password secret — pass to RDS module"
  value       = aws_secretsmanager_secret.db_password.arn
}

output "secret_name" {
  value = aws_secretsmanager_secret.db_password.name
}

# Exposes the version ARN so dependents wait for the version to exist before reading.
output "secret_version_arn" {
  value = aws_secretsmanager_secret_version.db_password.arn
}
