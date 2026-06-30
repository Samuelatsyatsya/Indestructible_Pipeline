variable "domain_name" {
  description = "CodeArtifact domain name"
  type        = string
}

variable "npm_repo_name" {
  description = "Name of the npm CodeArtifact repository"
  type        = string
  default     = "fincorp-npm"
}

variable "ci_principal_name" {
  description = "IAM username of the CI principal (behind the indestructible-creds Jenkins credential) that needs CodeArtifact pull access"
  type        = string
  default     = "CostDetective"
}

variable "tags" {
  type    = map(string)
  default = {}
}
