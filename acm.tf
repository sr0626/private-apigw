# Two server certs, both imported into ACM (Type = IMPORTED):
#
# 1. aws_acm_certificate.server — the CLIENT-FACING cert, created externally by
#    the org PKI (./scripts/gen-pki.sh): a server cert (CN/SAN = domain_name)
#    signed by the org CA, with that CA as the chain. This is what clients see
#    on the ALB HTTPS listener and verify against the org CA (certs/pki/ca.crt).
#
# 2. aws_acm_certificate.domain — a SELF-SIGNED cert used only by the private
#    API Gateway custom domain. A private custom domain will not serve a
#    CA-signed cert (its TLS frontend resets), and the ALB never verifies the
#    backend cert anyway, so this is internal plumbing kept self-signed.
#
# Run ./scripts/gen-pki.sh before `terraform apply` so the org-PKI files exist.

resource "aws_acm_certificate" "server" {
  private_key       = file(var.server_key_path)
  certificate_body  = file(var.server_cert_path)
  certificate_chain = file(var.mtls_ca_bundle_path)
}

resource "tls_private_key" "domain" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "domain" {
  private_key_pem = tls_private_key.domain.private_key_pem

  subject {
    common_name  = var.domain_name
    organization = "evolvity"
  }

  dns_names = [var.domain_name]

  validity_period_hours = 87600 # 10 years

  allowed_uses = [
    "digital_signature",
    "key_encipherment",
    "server_auth",
  ]
}

resource "aws_acm_certificate" "domain" {
  private_key      = tls_private_key.domain.private_key_pem
  certificate_body = tls_self_signed_cert.domain.cert_pem
}
