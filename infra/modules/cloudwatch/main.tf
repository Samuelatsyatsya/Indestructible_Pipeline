# SNS topic — receives alarm notifications and fans out to Lambda + email.
resource "aws_sns_topic" "dr_alerts" {
  name = "fincorp-dr-alerts"
  tags = var.tags
}

# Email subscription — engineer gets notified whether DR succeeded or failed.
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.dr_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Lambda subscription — SNS triggers the auto-failover function on alarm.
resource "aws_sns_topic_subscription" "lambda" {
  topic_arn = aws_sns_topic.dr_alerts.arn
  protocol  = "lambda"
  endpoint  = var.lambda_function_arn
}

# Alarm: fires when RDS has zero connections for two consecutive 1-minute periods.
# Two data points prevents false positives from brief connection drops.
resource "aws_cloudwatch_metric_alarm" "rds_down" {
  alarm_name          = "fincorp-rds-primary-down"
  alarm_description   = "Primary RDS has had zero connections for 2 minutes — triggers DR failover."
  namespace           = "AWS/RDS"
  metric_name         = "DatabaseConnections"
  dimensions          = { DBInstanceIdentifier = var.db_instance_id }
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 0
  comparison_operator = "LessThanOrEqualToThreshold"
  treat_missing_data  = "breaching"

  alarm_actions = [aws_sns_topic.dr_alerts.arn]
  ok_actions    = [aws_sns_topic.dr_alerts.arn]

  tags = var.tags
}
