output "function_arn" {
  value = aws_lambda_function.dr_failover.arn
}

output "function_name" {
  value = aws_lambda_function.dr_failover.function_name
}
