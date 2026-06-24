# Self-signed server certificate for the domain, imported into ACM.
#
# Used both by the ALB HTTPS listener (the cert clients see) and by the API
# Gateway private custom domain. It is a SERVER cert (subjectAltName matches
# the domain, required by modern clients) and is unrelated to the mTLS CA /
# client certs, which live in the ALB trust store (see mtls_truststore.tf).

resource "tls_private_key" "server" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "server" {
  private_key_pem = tls_private_key.server.private_key_pem

  subject {
    common_name  = var.domain_name
    organization = "poc"
  }

  dns_names = [var.domain_name]

  validity_period_hours = 87600 # 10 years

  allowed_uses = [
    "digital_signature",
    "key_encipherment",
    "server_auth",
  ]
}

resource "aws_acm_certificate" "server" {
  private_key      = tls_private_key.server.private_key_pem
  certificate_body = tls_self_signed_cert.server.cert_pem
}
