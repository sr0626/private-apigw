resource "aws_vpc_endpoint" "execute_api" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.execute-api"
  vpc_endpoint_type = "Interface"

  subnet_ids         = var.subnet_ids
  security_group_ids = [aws_security_group.vpce_sg.id]

  private_dns_enabled = false
}

data "aws_vpc" "this" {
  id = var.vpc_id
}

resource "aws_security_group" "vpce_sg" {
  name   = "vpce-sg"
  vpc_id = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Only the mTLS ALB may reach the VPC endpoint. Clients must go through the
  # ALB (and pass mutual TLS) rather than hitting the endpoint directly.
  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }
}


resource "aws_api_gateway_domain_name_access_association" "vpce" {
  domain_name_arn = aws_api_gateway_domain_name.custom.arn

  access_association_source_type = "VPCE"
  access_association_source      = aws_vpc_endpoint.execute_api.id
}