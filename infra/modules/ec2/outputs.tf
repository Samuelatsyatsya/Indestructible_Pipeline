output "public_ip" {
  description = "Public IP of the app server — open this in your browser"
  value       = aws_instance.app.public_ip
}

output "public_dns" {
  value = aws_instance.app.public_dns
}
