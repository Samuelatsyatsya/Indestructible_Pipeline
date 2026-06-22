variable "vpc_id" {
  description = "VPC ID to associate the private hosted zone with"
  type        = string
}

variable "primary_rds_endpoint" {
  description = "Endpoint of the primary RDS instance (without port)"
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
