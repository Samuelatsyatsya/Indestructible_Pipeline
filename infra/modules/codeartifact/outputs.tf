output "domain_name" {
  value = aws_codeartifact_domain.this.domain
}

output "npm_repo_name" {
  value = aws_codeartifact_repository.npm.repository
}

output "npm_repo_arn" {
  description = "ARN of the npm CodeArtifact repository"
  value       = aws_codeartifact_repository.npm.arn
}
