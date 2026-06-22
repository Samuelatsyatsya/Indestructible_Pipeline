output "ecr_repository_urls" {
  description = "ECR image URLs for Jenkins"
  value       = module.ecr.repository_urls
}

output "codeartifact_npm_arn" {
  description = "ARN of the FinCorp npm CodeArtifact repository"
  value       = module.codeartifact.npm_repo_arn
}

output "db_secret_arn" {
  description = "Secrets Manager ARN holding RDS credentials"
  value       = module.secrets.secret_arn
}

output "rds_endpoint" {
  description = "Primary RDS endpoint"
  value       = module.rds.db_endpoint
}

output "rds_instance_arn" {
  value = module.rds.db_instance_arn
}

output "app_server_ip" {
  description = "Open http://<this IP> in your browser to see the running app"
  value       = module.ec2.public_ip
}

output "backup_plan_id" {
  value = module.backup.backup_plan_id
}

output "dr_vault_arn" {
  value = module.backup.dr_vault_arn
}
