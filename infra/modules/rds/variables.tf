variable "identifier" {
  description = "RDS instance identifier"
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for the DB subnet group (at least 2 AZs)"
  type        = list(string)
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to reach PostgreSQL"
  type        = list(string)
  default     = ["10.0.0.0/8"]
}

variable "instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "allocated_storage" {
  type    = number
  default = 20
}

variable "db_name" {
  type    = string
  default = "fincorp"
}

variable "secret_arn" {
  description = "ARN of the Secrets Manager secret containing db username and password"
  type        = string
}

variable "secret_version_arn" {
  description = "ARN of the secret version — ensures Terraform waits for it to exist before reading"
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
