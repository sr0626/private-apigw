# mTLS termination layer.
#
# Private API Gateway does not support native mutual TLS, so an internal ALB
# sits in front of the private API and terminates/validates client certs. The
# ALB forwards (over HTTPS) to the interface VPC endpoint ENIs; the API itself
# stays PRIVATE and is still only reachable through that VPC endpoint.
#
#   client (client cert) --mTLS--> ALB --HTTPS--> VPC endpoint --> private API

resource "aws_security_group" "alb_sg" {
  name   = "mtls-alb-sg"
  vpc_id = var.vpc_id

  # Clients in the VPC connect to the ALB on 443.
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.this.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "mtls" {
  name               = "private-apigw-mtls"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = var.subnet_ids
}

# One ENI per subnet for the interface endpoint. length(var.subnet_ids) is
# known at plan time, so count avoids the "for_each over unknown values" error
# that the (computed) network_interface_ids set would otherwise cause.
data "aws_network_interface" "vpce" {
  count = length(var.subnet_ids)
  id    = tolist(aws_vpc_endpoint.execute_api.network_interface_ids)[count.index]
}

resource "aws_lb_target_group" "api" {
  name        = "private-apigw-vpce"
  port        = 443
  protocol    = "HTTPS"
  target_type = "ip"
  vpc_id      = var.vpc_id

  # Health checks hit the ENI IP directly (no custom-domain Host header), so
  # the private custom domain does not match and API Gateway returns 403/404.
  # That still proves the endpoint is reachable.
  health_check {
    protocol = "HTTPS"
    path     = "/"
    matcher  = "200,403,404"
  }
}

resource "aws_lb_target_group_attachment" "vpce" {
  count            = length(var.subnet_ids)
  target_group_arn = aws_lb_target_group.api.arn
  target_id        = data.aws_network_interface.vpce[count.index].private_ip
  port             = 443
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.mtls.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.server.arn

  mutual_authentication {
    mode            = "verify"
    trust_store_arn = aws_lb_trust_store.mtls.arn
  }

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}
