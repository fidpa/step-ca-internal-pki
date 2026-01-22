# Certificate Revocation

⚠️ **EXPERIMENTAL** - Certificate revocation tools for step-ca.

## Directory Structure

```
revocation/
└── revoke-cert.sh    # Certificate revocation script (EXPERIMENTAL)
```

## Files

| File | Description | Status |
|------|-------------|--------|
| `revoke-cert.sh` | Revoke certificates via step-ca API | ⚠️ EXPERIMENTAL |

## Important Notice

**This script is NOT compatible with the default Two-Tier PKI architecture.**

The default architecture uses OpenSSL signing (not step-ca API), so certificates are NOT registered in step-ca's database. The `revoke-cert.sh` script uses `step ca revoke` which requires database registration.

### For Default Architecture (OpenSSL-signed certificates)

Use manual OpenSSL revocation:

```bash
# 1. Revoke the certificate
openssl ca -revoke /path/to/cert.pem -config openssl.cnf

# 2. Generate updated CRL
openssl ca -gencrl -out crl.pem -config openssl.cnf

# 3. Distribute CRL to clients
```

### For ACME/API-issued certificates

If you're using step-ca's ACME protocol or API to issue certificates:

```bash
# Revoke by serial number
./revoke-cert.sh --serial <SERIAL> --reason keyCompromise

# Revoke by certificate file
./revoke-cert.sh --cert /path/to/cert.pem --reason superseded
```

## Revocation Reasons (RFC 5280)

| Reason | Use Case |
|--------|----------|
| `keyCompromise` | Private key exposed or stolen |
| `affiliationChanged` | Service ownership changed |
| `superseded` | Certificate replaced with new one |
| `cessationOfOperation` | Service decommissioned |
| `unspecified` | Other/unknown reason |

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `STEP_CA_HOME` | `/opt/step-ca` | step-ca installation directory |
| `STEP_CA_CONTAINER` | `step-ca` | Docker container name |
| `STEP_CA_CA_URL` | `https://step-ca.internal:9643` | CA URL |
| `CRL_ENDPOINT` | `https://localhost:9643/1.0/crl` | CRL distribution endpoint |

## See Also

- [← Back to Root](../README.md)
- [Architecture (Revocation Section)](../docs/ARCHITECTURE.md)
- [Troubleshooting](../docs/TROUBLESHOOTING.md)
