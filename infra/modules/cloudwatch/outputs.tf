output "sns_topic_arn" {
  value = aws_sns_topic.dr_alerts.arn
}

output "alarm_name" {
  value = aws_cloudwatch_metric_alarm.rds_down.alarm_name
}
