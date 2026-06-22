resource "aws_secretsmanager_secret" "db_password" {
  name                    = var.secret_name
  description             = "FinCorp RDS master password"
  recovery_window_in_days = 7
  tags                    = var.tags
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id = aws_secretsmanager_secret.db_password.id

  secret_string = jsonencode({
    username = var.db_username
    password = var.db_password
  })
}
