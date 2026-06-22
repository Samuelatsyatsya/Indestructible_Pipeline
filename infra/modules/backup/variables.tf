variable "rds_arns" {
  description = "ARNs of RDS instances to back up"
  type        = list(string)
}

variable "tags" {
  type    = map(string)
  default = {}
}
