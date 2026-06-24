# Trust store for ALB mutual TLS: an S3 object holding the CA public cert
# bundle that client certificates are validated against.
#
# Generate the bundle locally first:  ./certs/gen-mtls-ca.sh
# That writes certs/mtls/ca.crt, which is uploaded below.

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "truststore" {
  bucket        = "mtls-truststore-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "truststore" {
  bucket = aws_s3_bucket.truststore.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "ca_bundle" {
  bucket = aws_s3_bucket.truststore.id
  key    = "ca.crt"
  source = var.mtls_ca_bundle_path
  etag   = filemd5(var.mtls_ca_bundle_path)
}

resource "aws_lb_trust_store" "mtls" {
  name                             = "private-apigw-mtls"
  ca_certificates_bundle_s3_bucket = aws_s3_bucket.truststore.id
  ca_certificates_bundle_s3_key    = aws_s3_object.ca_bundle.key
}
