import json
import urllib.parse


def handler(event, context):
    # Headers arrive with inconsistent casing through API Gateway; normalize.
    raw_headers = event.get("headers") or {}
    headers = {k.lower(): v for k, v in raw_headers.items()}

    def get(name, default="(not present)"):
        return headers.get(name.lower(), default)

    # --- Client certificate (mTLS) ---
    # mTLS is terminated at the ALB. In "verify" mode the ALB injects the
    # validated client-cert details as X-Amzn-Mtls-Clientcert-* headers, which
    # API Gateway forwards to this Lambda.
    client_certificate = {
        "subject": get("x-amzn-mtls-clientcert-subject"),
        "issuer": get("x-amzn-mtls-clientcert-issuer"),
        "serial_number": get("x-amzn-mtls-clientcert-serial-number"),
        "validity": get("x-amzn-mtls-clientcert-validity"),
    }
    leaf = headers.get("x-amzn-mtls-clientcert-leaf")
    if leaf:
        # The leaf cert is URL-encoded PEM.
        client_certificate["leaf_pem"] = urllib.parse.unquote(leaf)

    # --- Server certificate ---
    # Not available to the Lambda: the server cert is what the ALB presents to
    # the CLIENT during the client<->ALB TLS handshake. It is terminated at the
    # ALB and is never forwarded to the backend, so this code cannot see it.
    server_certificate = (
        "Not visible to the Lambda. The server cert (org-CA-signed ALB listener "
        "cert that clients validate) is terminated at the ALB during the "
        "client<->ALB handshake and is not forwarded downstream."
    )

    body = {
        "message": "Hello from PRIVATE API (mTLS terminated at ALB)",
        "client_certificate": client_certificate,
        "server_certificate": server_certificate,
        # Full header set, so you can see exactly what the ALB / API Gateway
        # forwarded (and confirm the X-Amzn-Mtls-* headers survive the hops).
        "all_request_headers": headers,
    }

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body, indent=2) + "\n",
    }
