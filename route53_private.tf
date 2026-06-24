resource "aws_route53_zone" "private_zone" {
  name = var.domain_name

  vpc {
    vpc_id = var.vpc_id
  }
}

resource "aws_route53_record" "api" {
  zone_id = aws_route53_zone.private_zone.zone_id
  name    = var.domain_name
  type    = "A"

  # Points at the mTLS ALB (not the VPC endpoint directly) so clients land on
  # the mutual-TLS listener. The ALB then forwards to the VPC endpoint.
  alias {
    name                   = aws_lb.mtls.dns_name
    zone_id                = aws_lb.mtls.zone_id
    evaluate_target_health = false
  }
}