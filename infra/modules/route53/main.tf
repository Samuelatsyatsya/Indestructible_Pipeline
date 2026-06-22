# Private hosted zone — internal DNS visible only within the VPC.
resource "aws_route53_zone" "internal" {
  name = "db.fincorp.internal"

  vpc {
    vpc_id = var.vpc_id
  }

  tags = var.tags
}

# CNAME the app connects to — Lambda updates this record on failover.
resource "aws_route53_record" "primary" {
  zone_id = aws_route53_zone.internal.zone_id
  name    = "primary.db.fincorp.internal"
  type    = "CNAME"
  ttl     = 30

  records = [var.primary_rds_endpoint]
}
