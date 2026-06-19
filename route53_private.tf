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

  alias {
    name                   = aws_vpc_endpoint.execute_api.dns_entry[0].dns_name
    zone_id                = aws_vpc_endpoint.execute_api.dns_entry[0].hosted_zone_id
    evaluate_target_health = false
  }
}