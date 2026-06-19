# Private API Gateway with a Private Custom Domain

Terraform for an **internal-only** REST API Gateway, fronted by a **private
custom domain** and reachable only from inside a VPC through an interface VPC
endpoint. A small Lambda backs a `GET /hello` route as a working example.

## Architecture

```
            (inside the VPC)
client ──► Route 53 private zone (api.example.com)
              │  alias
              ▼
        Interface VPC endpoint (execute-api)
              │  domain-name access association
              ▼
        Private custom domain ──(base path mapping)──► REST API "prod" stage
              │  domain-name resource policy                    │
              ▼                                                 ▼
        aws:SourceVpce check                              Lambda (AWS_PROXY)
```

Access is gated by **three** independent controls, all scoped to the one VPC
endpoint:

1. **VPC endpoint security group** – only allows 443 from the VPC CIDR.
2. **REST API resource policy** – `aws:SourceVpce` condition ([api_gateway.tf](api_gateway.tf)).
3. **Domain-name resource policy** – `aws:SourceVpce` condition ([custom_domain.tf](custom_domain.tf)).
   Private custom domains are authorized against the `/domainnames/...` resource,
   which the REST API policy does **not** cover — this policy is required.

## Files

| File | Purpose |
|------|---------|
| [providers.tf](providers.tf) | AWS + archive providers, region `us-east-1` |
| [variables.tf](variables.tf) | Input variables |
| [api_gateway.tf](api_gateway.tf) | Private REST API, `/hello` method, integration, deployment, stage, resource policy |
| [lambda.tf](lambda.tf) / [code/lambda.py](code/lambda.py) | Lambda function, role, log group, and the API Gateway invoke permission |
| [vpc_endpoint.tf](vpc_endpoint.tf) | Interface VPC endpoint, its security group, and the domain-name access association |
| [custom_domain.tf](custom_domain.tf) | Private custom domain, its resource policy, and the base path mapping |
| [route53_private.tf](route53_private.tf) | Private hosted zone + alias record to the VPC endpoint |
| [ec2_test_instance.tf](ec2_test_instance.tf) | Optional test EC2 instance (SSM-managed) for in-VPC validation |
| [outputs.tf](outputs.tf) | API id, invoke URL, custom domain |

## Prerequisites

- An existing VPC and two subnets.
- A **regional ACM certificate** in `us-east-1` for your domain. For internal
  use a self-signed cert imported into ACM works — it must include a
  `subjectAltName` matching the domain (a CN-only cert is rejected by modern
  clients).
- Terraform with the AWS provider **>= 5.34** (pinned `~> 5.0` in
  [providers.tf](providers.tf); 5.34 is the first release with private custom
  domain support) and the `archive` provider `~> 2.4`.
- AWS credentials with permission to manage the resources.

## Usage

```bash
cp terraform.tfvars.example terraform.tfvars   # then fill in your values
terraform init
terraform apply
```

## Testing

From a host **inside the VPC** (e.g. the optional EC2 instance via SSM Session
Manager):

```bash
curl -s https://api.example.com/hello
# Hello from PRIVATE API
```

Notes:
- The stage is baked into the base path mapping, so the URL is `/hello`, **not**
  `/prod/hello`. The `/prod/...` form only applies to the raw `execute-api`
  `invoke_url` output.
- If the certificate is self-signed, clients must trust it (add it to the trust
  store or use `curl --cacert`). Otherwise add `-k` to skip verification.

## Notes / limitations

- `private_dns_enabled = false` on the VPC endpoint is intentional — private DNS
  must be off when routing through a private custom domain access association.
- State is local and gitignored. For team use, switch to a remote backend
  (S3 + DynamoDB lock).
- `ec2_test_instance.tf` is for testing only; remove or leave it disabled in
  real deployments.
```
