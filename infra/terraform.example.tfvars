# Copy this file to terraform.tfvars and fill in your values.
# terraform.tfvars is gitignored — never commit real credentials.

aws_profile    = "CostDetective"
aws_account_id = "309797288544"
primary_region = "eu-central-1"
dr_region      = "eu-west-1"

# RDS master password — must be at least 8 characters.
db_password = "YourStrongPassword123!"

# Email address to receive DR failover notifications via SNS.
alert_email = "your-email@example.com"
