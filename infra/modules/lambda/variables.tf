variable "dr_region" {
  type = string
}

variable "dr_vault_name" {
  type = string
}

variable "backup_iam_role_arn" {
  type = string
}

variable "restored_db_id" {
  type    = string
  default = "fincorp-restored-db"
}

variable "route53_zone_id" {
  type = string
}

variable "route53_record" {
  type = string
}

variable "sns_topic_arn" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
