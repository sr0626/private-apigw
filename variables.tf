variable "aws_region" {
  type    = string
  default = "us-west-2"
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "domain_name" {
  type = string
}

# Org PKI material produced by ./scripts/gen-pki.sh (under certs/pki/).
# ca.crt is both the ALB trust store and the server cert's chain.
variable "mtls_ca_bundle_path" {
  type    = string
  default = "certs/pki/ca.crt"
}

variable "server_cert_path" {
  type    = string
  default = "certs/pki/server.crt"
}

variable "server_key_path" {
  type    = string
  default = "certs/pki/server.key"
}