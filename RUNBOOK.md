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
- **No ACM cert to create by hand** — Terraform ([acm.tf](acm.tf)) generates a
  self-signed server cert for `domain_name` (with a matching `subjectAltName`)
  and imports it into ACM. It is the **ALB server certificate** and is also used
  by the API Gateway custom domain.
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
| `mtls_ca_bundle_path` | *(optional)* defaults to `certs/mtls/ca.crt` |

The ALB server certificate is generated and imported by Terraform — there is no
`acm_cert_arn` to supply.

---

## 2. Generate the mTLS CA and a client certificate

```bash
./scripts/gen-mtls-ca.sh
```

This writes (all under the gitignored `certs/mtls/`):

| File | Role |
|------|------|
| `ca.crt` | CA public cert — **uploaded to the ALB trust store** by Terraform |
| `ca.key` | CA private key — keep local, used only to sign client certs |
| `client.crt` | Sample **client certificate** callers present |
| `client.key` | Client private key |

To mint additional client certs later, re-run the relevant `openssl` steps in
the script (or copy them) against the existing `ca.crt` / `ca.key`.

---

## 3. Deploy

```bash
terraform init
terraform plan      # review: ALB, trust store, target group, SG changes
terraform apply
```

What gets created/changed:

- **Self-signed server cert imported into ACM** for `domain_name` ([acm.tf](acm.tf))
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
of the local `certs/mtls/client.crt` and `client.key`):

```bash
cat > /tmp/client.crt <<'EOF'
<paste certs/mtls/client.crt>
EOF
cat > /tmp/client.key <<'EOF'
<paste certs/mtls/client.key>
EOF
```

`-k` is used below because the ALB server cert is self-signed; this skips
*server* verification only — mTLS *client* auth is still fully enforced.

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
| `handshake failure` even with `--cert` | Client cert not signed by the CA in the trust store, or trust store object out of date. Re-run `gen-mtls-ca.sh`, `terraform apply` (the S3 object `etag` triggers re-upload). |
| `503` from the ALB | Target group unhealthy. Health check expects `200,403,404` from the ENI IPs; confirm the VPC endpoint is `available` and the ALB SG → VPCE SG rule exists. |
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
removed with it. Local `certs/mtls/` material is yours to delete manually.
