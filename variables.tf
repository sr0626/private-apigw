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

# Local path to the CA public cert bundle uploaded to the ALB trust store.
# Produced by ./certs/gen-mtls-ca.sh.
variable "mtls_ca_bundle_path" {
  type    = string
  default = "certs/mtls/ca.crt"
}