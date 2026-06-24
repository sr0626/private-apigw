resource "aws_api_gateway_domain_name" "custom" {
  domain_name     = var.domain_name
  certificate_arn = aws_acm_certificate.server.arn

  endpoint_configuration {
    types = ["PRIVATE"]
  }

  # Private custom domains are authorized by a resource policy on the
  # domain name itself (separate from the REST API resource policy).
  # Allow invoke only when the request arrives through our VPC endpoint.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = "*"
      Action    = "execute-api:Invoke"
      Resource  = "*"
      Condition = {
        StringEquals = {
          "aws:SourceVpce" = aws_vpc_endpoint.execute_api.id
        }
      }
    }]
  })
}

resource "aws_api_gateway_base_path_mapping" "custom" {
  api_id         = aws_api_gateway_rest_api.api.id
  stage_name     = aws_api_gateway_stage.prod.stage_name
  domain_name    = aws_api_gateway_domain_name.custom.domain_name
  domain_name_id = aws_api_gateway_domain_name.custom.domain_name_id
}