variable "secret_name" {
  description = "Name of the secret in AWS Secrets Manager"
  type        = string
  default     = "fincorp/rds/master-password"
}

variable "db_username" {
  type    = string
  default = "fincorp_admin"
}

variable "db_password" {
  description = "The actual password value — pass via TF_VAR_db_password env var, never in tfvars"
  type        = string
  sensitive   = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
