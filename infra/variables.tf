variable "aws_profile" {
  description = "AWS CLI profile to use"
  type        = string
  default     = "CostDetective"
}

variable "primary_region" {
  description = "Primary AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "dr_region" {
  description = "Disaster recovery AWS region"
  type        = string
  default     = "eu-west-1"
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
  default     = "309797288544"
}

variable "db_password" {
  description = "RDS master password"
  type        = string
  sensitive   = true
}
