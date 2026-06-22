resource "aws_iam_role" "backup" {
  name = "fincorp-backup-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "backup.amazonaws.com" }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "backup" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_iam_role_policy_attachment" "backup_restore" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

resource "aws_backup_vault" "primary" {
  name = "fincorp-primary-vault"
  tags = var.tags
}

# DR vault lives in eu-west-1 — receives cross-region copies for disaster recovery.
resource "aws_backup_vault" "dr" {
  provider = aws.dr
  name     = "fincorp-dr-vault"
  tags     = var.tags
}

resource "aws_backup_plan" "daily" {
  name = "fincorp-daily-backup"

  rule {
    rule_name         = "daily-snapshot"
    target_vault_name = aws_backup_vault.primary.name
    schedule          = "cron(0 2 * * ? *)"

    lifecycle {
      delete_after = 30
    }

    # Cross-region copy: every daily snapshot is also sent to eu-west-1.
    copy_action {
      destination_vault_arn = aws_backup_vault.dr.arn

      lifecycle {
        delete_after = 30
      }
    }
  }

  tags = var.tags
}

resource "aws_backup_selection" "rds" {
  name         = "fincorp-rds-selection"
  plan_id      = aws_backup_plan.daily.id
  iam_role_arn = aws_iam_role.backup.arn

  resources = var.rds_arns
}
