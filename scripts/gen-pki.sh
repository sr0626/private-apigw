#!/usr/bin/env bash
#
# Simulate an org PKI: one CA issues both the SERVER cert (for the ALB / API
# Gateway custom domain) and a CLIENT cert (for mTLS). The same ca.crt is the
# ALB trust store, so it:
#   - signs the server cert        (imported into ACM, Type = IMPORTED)
#   - signs client certs           (presented by callers)
#   - validates client certs       (uploaded as the ALB trust store)
#   - lets clients verify the server (curl --cacert certs/pki/ca.crt)
#
# Usage:  ./scripts/gen-pki.sh [domain]      (domain defaults to api.evolvity.com)
#
# Everything lands in certs/pki/ (gitignored, so keys are never committed).
# Re-run safely; it overwrites previous material. Terraform's acm.tf and trust
# store read these files via file(), so run this before `terraform apply`.

set -euo pipefail

DOMAIN="${1:-api.evolvity.com}"
ORG="evolvity"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIR="$ROOT/certs/pki"
mkdir -p "$DIR"
cd "$DIR"

CA_DAYS=3650
LEAF_DAYS=825   # max accepted by modern clients

echo "==> [1/3] Org CA  ($DIR)"
openssl genrsa -out ca.key 4096
openssl req -x509 -new -nodes -key ca.key -sha256 -days "$CA_DAYS" \
  -subj "/CN=${ORG} Issuing CA/O=${ORG}" \
  -out ca.crt

echo "==> [2/3] Server cert  (CN=${DOMAIN})"
openssl genrsa -out server.key 2048
openssl req -new -key server.key -subj "/CN=${DOMAIN}/O=${ORG}" -out server.csr
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -sha256 -days "$LEAF_DAYS" -out server.crt \
  -extfile <(printf "subjectAltName=DNS:%s\nextendedKeyUsage=serverAuth\nkeyUsage=digitalSignature,keyEncipherment\n" "$DOMAIN")

echo "==> [3/3] Client cert  (CN=api-client)"
openssl genrsa -out client.key 2048
openssl req -new -key client.key -subj "/CN=api-client/O=${ORG}" -out client.csr
openssl x509 -req -in client.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -sha256 -days "$LEAF_DAYS" -out client.crt \
  -extfile <(printf "extendedKeyUsage=clientAuth\nkeyUsage=digitalSignature\n")

rm -f server.csr client.csr ca.srl

echo "==> Done. Issued by the org CA (certs/pki/):"
echo "    ca.crt                  trust store + server chain + client trust root"
echo "    server.crt / server.key   imported into ACM (Type IMPORTED)"
echo "    client.crt / client.key   presented by callers (curl --cert/--key)"
