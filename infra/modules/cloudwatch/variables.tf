variable "db_instance_id" {
  description = "RDS instance identifier to monitor"
  type        = string
}

variable "alert_email" {
  description = "Email address to notify on DR events"
  type        = string
}

variable "lambda_function_arn" {
  description = "ARN of the DR failover Lambda to trigger on alarm"
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
