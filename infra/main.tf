terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
      configuration_aliases = [aws.dr]
    }
  }
}

provider "aws" {
  region  = var.primary_region
  profile = var.aws_profile
}

provider "aws" {
  alias   = "dr"
  region  = var.dr_region
  profile = var.aws_profile
}

# ── VPC ────────────────────────────────────────────────────────────────────────
module "vpc" {
  source = "./modules/vpc"

  name = "fincorp-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["eu-central-1a", "eu-central-1b"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = ["10.0.11.0/24", "10.0.12.0/24"]

  tags = local.common_tags
}

# ── ECR ────────────────────────────────────────────────────────────────────────
module "ecr" {
  source = "./modules/ecr"

  repository_names = [
    "fincorp/loan-api",
    "fincorp/loan-ui",
  ]

  tags = local.common_tags
}

# ── CodeArtifact ───────────────────────────────────────────────────────────────
module "codeartifact" {
  source = "./modules/codeartifact"

  domain_name   = "fincorp"
  npm_repo_name = "fincorp-npm"

  tags = local.common_tags
}

# ── Secrets Manager ────────────────────────────────────────────────────────────
module "secrets" {
  source = "./modules/secrets"

  secret_name = "fincorp/rds/master-password"
  db_username = "fincorp_admin"
  db_password = var.db_password

  tags = local.common_tags
}

# ── RDS (primary — eu-central-1) ───────────────────────────────────────────────
module "rds" {
  source = "./modules/rds"

  identifier          = "fincorp-primary-db"
  vpc_id              = module.vpc.vpc_id
  subnet_ids          = module.vpc.private_subnet_ids
  secret_arn          = module.secrets.secret_arn
  secret_version_arn  = module.secrets.secret_version_arn

  tags = local.common_tags
}

# ── AWS Backup + Cross-Region Copy ─────────────────────────────────────────────
module "backup" {
  source = "./modules/backup"

  providers = {
    aws    = aws
    aws.dr = aws.dr
  }

  rds_arns = [module.rds.db_instance_arn]
  tags     = local.common_tags
}

# ── EC2 App Server ─────────────────────────────────────────────────────────────
module "ec2" {
  source = "./modules/ec2"

  vpc_id           = module.vpc.vpc_id
  public_subnet_id = module.vpc.public_subnet_ids[0]
  aws_region       = var.primary_region
  ecr_registry     = "${var.aws_account_id}.dkr.ecr.${var.primary_region}.amazonaws.com"

  backend_image  = "309797288544.dkr.ecr.eu-central-1.amazonaws.com/fincorp/loan-api:3-f365834"
  frontend_image = "309797288544.dkr.ecr.eu-central-1.amazonaws.com/fincorp/loan-ui:3-f365834"
  key_name       = "fincorp-ec2-key"

  tags = local.common_tags
}

# ── Route 53 private hosted zone ───────────────────────────────────────────────
module "route53" {
  source = "./modules/route53"

  vpc_id               = module.vpc.vpc_id
  # Strip the port suffix — Route 53 CNAME value must be a hostname only.
  primary_rds_endpoint = split(":", module.rds.db_endpoint)[0]

  tags = local.common_tags
}

# ── CloudWatch alarm + SNS topic (created first — Lambda needs the SNS ARN) ───
module "cloudwatch" {
  source = "./modules/cloudwatch"

  db_instance_id      = "fincorp-primary-db"
  alert_email         = var.alert_email
  lambda_function_arn = module.lambda.function_arn

  tags = local.common_tags
}

# ── DR Failover Lambda ─────────────────────────────────────────────────────────
module "lambda" {
  source = "./modules/lambda"

  dr_region           = var.dr_region
  dr_vault_name       = "fincorp-dr-vault"
  backup_iam_role_arn = "arn:aws:iam::${var.aws_account_id}:role/fincorp-backup-role"
  restored_db_id      = "fincorp-restored-db"
  route53_zone_id     = module.route53.zone_id
  route53_record      = module.route53.db_dns_name
  sns_topic_arn       = module.cloudwatch.sns_topic_arn

  tags = local.common_tags
}

locals {
  common_tags = {
    Project     = "FinCorp-Pipeline"
    Environment = "production"
    ManagedBy   = "Terraform"
  }
}
