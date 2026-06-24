#!/usr/bin/env bash
#
# Generate a self-signed CA and a sample client certificate for mTLS.
#
# The CA certificate (certs/mtls/ca.crt) is uploaded to the ALB trust store by
# Terraform (see mtls_truststore.tf). The client cert/key are what callers
# present when invoking the API:
#
#   curl --cert certs/mtls/client.crt --key certs/mtls/client.key \
#        https://api.evolvity.com/hello
#
# Run from anywhere:  ./scripts/gen-mtls-ca.sh
# Everything lands in certs/mtls/ (gitignored, so keys are never committed).
# Re-run safely; it overwrites previous material.

set -euo pipefail

# Repo root = parent of this script's directory; write certs under certs/mtls/.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIR="$ROOT/certs/mtls"
mkdir -p "$DIR"
cd "$DIR"

CA_DAYS=3650
CLIENT_DAYS=825   # max accepted by modern clients

echo "==> Generating CA in $DIR"
openssl genrsa -out ca.key 4096
openssl req -x509 -new -nodes -key ca.key -sha256 -days "$CA_DAYS" \
  -subj "/CN=private-apigw mTLS CA/O=poc" \
  -out ca.crt

echo "==> Generating client certificate"
openssl genrsa -out client.key 2048
openssl req -new -key client.key \
  -subj "/CN=api-client/O=poc" \
  -out client.csr
openssl x509 -req -in client.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -sha256 -days "$CLIENT_DAYS" -out client.crt
rm -f client.csr ca.srl

echo "==> Done. Trust store bundle: $DIR/ca.crt"
echo "    Client cert/key:        $DIR/client.crt , $DIR/client.key"
