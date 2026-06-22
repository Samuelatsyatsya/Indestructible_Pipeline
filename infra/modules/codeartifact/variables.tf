variable "domain_name" {
  description = "CodeArtifact domain name"
  type        = string
}

variable "npm_repo_name" {
  description = "Name of the npm CodeArtifact repository"
  type        = string
  default     = "fincorp-npm"
}

variable "tags" {
  type    = map(string)
  default = {}
}
