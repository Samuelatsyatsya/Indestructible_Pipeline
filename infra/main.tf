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

  # These images must exist in ECR before the instance starts — Jenkins pushes them.
  backend_image  = "309797288544.dkr.ecr.eu-central-1.amazonaws.com/fincorp/loan-api:latest"
  frontend_image = "309797288544.dkr.ecr.eu-central-1.amazonaws.com/fincorp/loan-ui:latest"

  tags = local.common_tags
}

locals {
  common_tags = {
    Project     = "FinCorp-Pipeline"
    Environment = "production"
    ManagedBy   = "Terraform"
  }
}
