# Zip the Lambda source code at plan time — no external build step needed.
data "archive_file" "dr_failover" {
  type        = "zip"
  source_file = "${path.module}/src/dr_failover.py"
  output_path = "${path.module}/dr_failover.zip"
}

# IAM role the Lambda runs under.
resource "aws_iam_role" "lambda" {
  name = "fincorp-dr-failover-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

# Inline policy granting only what the Lambda needs.
resource "aws_iam_role_policy" "lambda" {
  name = "fincorp-dr-failover-policy"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Read recovery points and start restore jobs in the DR vault.
        Effect = "Allow"
        Action = [
          "backup:ListRecoveryPointsByBackupVault",
          "backup:StartRestoreJob",
        ]
        Resource = "*"
      },
      {
        # Poll the restored RDS instance status.
        Effect   = "Allow"
        Action   = ["rds:DescribeDBInstances"]
        Resource = "*"
      },
      {
        # Update the Route 53 CNAME to point to the restored endpoint.
        Effect   = "Allow"
        Action   = ["route53:ChangeResourceRecordSets"]
        Resource = "arn:aws:route53:::hostedzone/${var.route53_zone_id}"
      },
      {
        # Publish DR notification to SNS.
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = var.sns_topic_arn
      },
      {
        # Ship Lambda logs to CloudWatch.
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        # Pass the backup IAM role when starting the restore job.
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = var.backup_iam_role_arn
      },
    ]
  })
}

resource "aws_lambda_function" "dr_failover" {
  function_name    = "fincorp-dr-failover"
  role             = aws_iam_role.lambda.arn
  filename         = data.archive_file.dr_failover.output_path
  source_code_hash = data.archive_file.dr_failover.output_base64sha256
  handler          = "dr_failover.lambda_handler"
  runtime          = "python3.12"
  # Restore polling runs up to 40 minutes — set timeout to max.
  timeout          = 900

  environment {
    variables = {
      DR_REGION       = var.dr_region
      DR_VAULT_NAME   = var.dr_vault_name
      IAM_ROLE_ARN    = var.backup_iam_role_arn
      RESTORED_DB_ID  = var.restored_db_id
      ROUTE53_ZONE_ID = var.route53_zone_id
      ROUTE53_RECORD  = var.route53_record
      SNS_TOPIC_ARN   = var.sns_topic_arn
    }
  }

  tags = var.tags
}

# Allow SNS to invoke this Lambda.
resource "aws_lambda_permission" "sns" {
  statement_id  = "AllowSNSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.dr_failover.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = var.sns_topic_arn
}
