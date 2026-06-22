variable "vpc_id" {
  type = string
}

variable "public_subnet_id" {
  description = "Public subnet to place the EC2 instance in"
  type        = string
}

variable "aws_region" {
  type    = string
  default = "eu-central-1"
}

variable "ecr_registry" {
  description = "ECR registry URL (account.dkr.ecr.region.amazonaws.com)"
  type        = string
}

variable "backend_image" {
  description = "Full ECR image URL for the backend"
  type        = string
}

variable "frontend_image" {
  description = "Full ECR image URL for the frontend"
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
