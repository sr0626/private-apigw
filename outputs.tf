output "api_id" {
  value = aws_api_gateway_rest_api.api.id
}

output "invoke_url" {
  value = aws_api_gateway_stage.prod.invoke_url
}

output "custom_domain" {
  value = aws_api_gateway_domain_name.custom.domain_name
}

output "mtls_alb_dns_name" {
  description = "Internal ALB DNS name fronting the private API with mTLS."
  value       = aws_lb.mtls.dns_name
}

output "mtls_trust_store_arn" {
  value = aws_lb_trust_store.mtls.arn
}

output "server_certificate_arn" {
  description = "ACM server cert (Type IMPORTED, issued by the org CA) used by the ALB and custom domain."
  value       = aws_acm_certificate.server.arn
}