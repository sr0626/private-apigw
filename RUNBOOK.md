# Runbook — Deploy & Test the Private API Gateway with mTLS

Step-by-step procedure to stand up the private REST API behind an mTLS ALB,
generate certificates, deploy with Terraform, and verify mutual TLS works.

> **Status:** deployed and validated in `us-west-2` for `api.evolvity.com`.
> A request with a trusted client cert returns the Lambda body; a request with
> no cert (or an untrusted cert) is rejected at the TLS handshake. See §4.

> **Note on commands:** every `terraform` / `aws` / `curl` command below is run
> **by you**, not by the assistant. The assistant only writes the code.

---

## 0. Prerequisites

- An existing **VPC** and at least **two subnets** (one per AZ recommended).
- An **org PKI** issues the server and client certs. Here it's simulated by
  [scripts/gen-pki.sh](scripts/gen-pki.sh) (§2); Terraform imports the resulting
  server cert into ACM (Type IMPORTED, [acm.tf](acm.tf)) for the ALB listener and
  the API Gateway custom domain. No `acm_cert_arn` to supply by hand.
- Terraform with AWS provider **>= 5.34** (private custom domains) — the
  `aws_lb_trust_store` / listener `mutual_authentication` features also require
  a recent 5.x. The repo pins `~> 5.0` in [providers.tf](providers.tf).
- AWS credentials with permission to manage API Gateway, ELBv2, S3, EC2/VPC,
  Route 53, Lambda, and IAM.
- `openssl` and `curl` available locally / on the test host.
- The **SSM Session Manager plugin** on your workstation (separate from the AWS
  CLI) to reach the in-VPC test host:
  `brew install --cask session-manager-plugin`.

---

## 1. Fill in variables

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

| Variable | What to set |
|----------|-------------|
| `aws_region` | *(optional)* defaults to `us-west-2` |
| `vpc_id` | Your VPC id |
| `subnet_ids` | Two (or more) subnet ids in that VPC |
| `domain_name` | e.g. `api.evolvity.com` |
| `mtls_ca_bundle_path` | *(optional)* defaults to `certs/pki/ca.crt` |
| `server_cert_path` / `server_key_path` | *(optional)* default to `certs/pki/server.{crt,key}` |

The server cert is created externally by the org PKI (§2) and imported into ACM
by Terraform — there is no `acm_cert_arn` to supply.

---

## 2. Generate the org PKI (CA + server + client certs)

```bash
./scripts/gen-pki.sh                 # or: ./scripts/gen-pki.sh <domain>
```

One CA issues everything. This writes (all under the gitignored `certs/pki/`):

| File | Role |
|------|------|
| `ca.crt` | Org CA public cert — ALB **trust store**, server-cert **chain**, and client trust root |
| `ca.key` | Org CA private key — keep local, signs the server and client certs |
| `server.crt` / `server.key` | **Server cert** (CN/SAN = domain) — imported into ACM (Type IMPORTED) |
| `client.crt` / `client.key` | **Client cert** callers present for mTLS |

To mint additional client certs later, re-run the client `openssl` steps in the
script against the existing `ca.crt` / `ca.key`.

---

## 3. Deploy

```bash
terraform init
terraform plan      # review: ALB, trust store, target group, SG changes
terraform apply
```

What gets created/changed:

- **Two ACM imports** ([acm.tf](acm.tf)): the org-CA-signed server cert (ALB
  listener, client-facing) and a self-signed cert (private custom domain —
  a private domain won't serve a CA-signed cert; the ALB doesn't verify it)
- **S3 bucket + `ca.crt` object + `aws_lb_trust_store`** ([mtls_truststore.tf](mtls_truststore.tf))
- **Internal ALB**, security group, **mTLS HTTPS listener** (`verify` mode),
  and an **IP target group** pointing at the VPC endpoint ENIs ([mtls_alb.tf](mtls_alb.tf))
- **VPC endpoint SG** tightened to allow 443 **only from the ALB SG** ([vpc_endpoint.tf](vpc_endpoint.tf))
- **Route 53** alias record now points at the **ALB** ([route53_private.tf](route53_private.tf))

Capture the outputs:

```bash
terraform output mtls_alb_dns_name
terraform output mtls_trust_store_arn
terraform output custom_domain
```

---

## 4. Test from inside the VPC

`api.evolvity.com` resolves (via the private hosted zone) to the internal ALB,
so tests must run **from a host in the VPC** — the EC2 instance in
[ec2_test_instance.tf](ec2_test_instance.tf) via SSM Session Manager:

```bash
aws ssm start-session --region us-west-2 --target <instance-id>
```

Find `<instance-id>` by tag:

```bash
aws ec2 describe-instances --region us-west-2 \
  --filters "Name=tag:Name,Values=private-api-test" \
            "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].InstanceId" --output text
```

Inside the session, drop your client cert/key onto the host (paste the contents
of the local `certs/pki/client.crt` and `client.key`):

```bash
cat > /tmp/client.crt <<'EOF'
<paste certs/pki/client.crt>
EOF
cat > /tmp/client.key <<'EOF'
<paste certs/pki/client.key>
EOF
```

`-k` is used below to skip *server* verification (the ALB server cert is issued
by the org CA, which the host doesn't trust by default) — mTLS *client* auth is
still fully enforced. To verify the server properly instead, also copy
`certs/pki/ca.crt` to the host and swap `-k` for `--cacert /tmp/ca.crt`.

### 4a. With a valid client cert → success ✅

```bash
curl -sk --cert /tmp/client.crt --key /tmp/client.key https://api.evolvity.com/hello
# Hello from PRIVATE API
```

### 4b. Without a client cert → rejected at the ALB ✅

```bash
curl -sk https://api.evolvity.com/hello; echo "exit=$?"
# (no body) exit=35   ← TLS handshake refused
```

`-s` hides the error text, so check the exit code: **35** is the handshake
failure that confirms mTLS is enforced.

### 4c. With an untrusted client cert → rejected ✅

A cert signed by some other CA (not in the trust store) is also refused,
proving the trust store — not just "any cert" — is what's enforced:

```bash
openssl req -x509 -newkey rsa:2048 -keyout /tmp/bad.key -out /tmp/bad.crt \
  -days 1 -nodes -subj "/CN=rogue" >/dev/null 2>&1
curl -sk --cert /tmp/bad.crt --key /tmp/bad.key https://api.evolvity.com/hello; echo "exit=$?"
# (no body) exit=35
```

**Result:** access succeeds only with a client cert signed by the trust-store
CA; all other requests fail at the handshake. ✔ Validated.

---

## 5. Troubleshooting

| Symptom | Likely cause / fix |
|---------|--------------------|
| `handshake failure` even with `--cert` | Client cert not signed by the CA in the trust store, or trust store object out of date. Re-run `gen-pki.sh`, `terraform apply` (the S3 object `etag` triggers re-upload). |
| `503` from the ALB | Target group unhealthy. Health check expects `200,403,404` from the ENI IPs; confirm the VPC endpoint is `available` and the ALB SG → VPCE SG rule exists. |
| `curl (56)` / connection reset *after* the handshake (mTLS succeeded, request sent, no response) | Backend hop, not mTLS. Check the VPCE↔domain **access association** points at the current domain id (`get-domain-name-access-associations`). Caused by recreating the domain without rebuilding the association/base-path-mapping, or by putting a **CA-signed cert on the private custom domain** (use self-signed there). A clean `destroy`+`apply` rebuilds the wiring in order. |
| `403 {"message":"Forbidden"}` returned to client | Request reached API Gateway but `aws:SourceVpce` / domain access association rejected it. Confirm the Host header is `api.evolvity.com` (don't override it) and the access association is in place. |
| Connection times out | DNS resolved to the ALB but the client host can't reach it — check the ALB SG ingress (443 from VPC CIDR) and that the client is in the VPC. |
| `SessionManagerPlugin is not found` on `aws ssm start-session` | Install the plugin on your workstation: `brew install --cask session-manager-plugin`, then retry. |
| `terraform plan` error: *Invalid for_each / count* on ENI data source | The VPC endpoint must exist with one ENI per subnet; `length(var.subnet_ids)` must match the actual subnet count. |

---

## 6. Teardown

```bash
terraform destroy
```

The trust store S3 bucket has `force_destroy = true`, so the `ca.crt` object is
removed with it. Local `certs/pki/` material is yours to delete manually.
