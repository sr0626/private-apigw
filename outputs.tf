output "api_id" {
  value = aws_api_gateway_rest_api.api.id
}

output "invoke_url" {
  value = aws_api_gateway_stage.prod.invoke_url
}

output "custom_domain" {
  value = aws_api_gateway_domain_name.custom.domain_name
}