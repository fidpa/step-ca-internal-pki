# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in this project, please report it responsibly.

**Contact**: security@fidpa.dev

We will respond within 72 hours and provide a timeline for fixes.

**Please do NOT open a public issue for security vulnerabilities.**

---

## Supported Versions

We provide security updates for the following versions:

| Version | Supported          | Notes                          |
| ------- | ------------------ | ------------------------------ |
| 1.x     | ✅ Yes             | Active development             |
| 0.9.x   | ⚠️ Security fixes only | Upgrade to 1.0.0 recommended |
| < 0.9.0 | ❌ No              | No longer supported            |

---

## Security Features

This project implements the following security measures:

### PKI Security
- **Offline Root CA**: Air-gapped, GPG-encrypted private key, multiple backups (3-2-1 rule)
- **Short-Lived Certificates**: 90 days validity (step-ca default)
- **Auto-Renewal**: 30-day threshold prevents expiry
- **Certificate Revocation**: CRL support (⚠️ EXPERIMENTAL)

### Production Security
- **TLS 1.3/1.2 only**: Modern cipher suites (see [NGINX_TLS.md](docs/NGINX_TLS.md))
- **HSTS**: HTTP Strict Transport Security enabled
- **OCSP Stapling**: Privacy-preserving revocation checking
- **Monitoring**: Prometheus alerts 30/7/1 days before certificate expiry

### Operational Security
- **No Secrets in Code**: All sensitive data in environment variables or separate files
- **Minimal Privileges**: Scripts follow principle of least privilege
- **Secure Defaults**: Conservative TLS configurations (Modern/Intermediate profiles)

---

## Known Security Considerations

### Serial Number Race Condition (RESOLVED in v1.0.0)

✅ **Status**: Fixed via flock locking in v1.0.0

**Original Issue**: When multiple services request certificates simultaneously, the `-CAcreateserial` flag could cause serial number collisions.

**Resolution**: All signing operations now use `flock -x` to serialize access to the serial file (`intermediate_ca.srl`). Multiple services can renew concurrently - only the serial increment is serialized.

```bash
# How it works (internal implementation)
(
    flock -x -w 60 200  # Exclusive lock, 60s timeout
    openssl x509 -req ... -CAserial "$CA_SERIAL" -CAcreateserial ...
) 200>/var/lock/step-ca-serial.lock
```

**Files affected**: `renewal/renew-service-cert.sh`, `examples/cert-request-template.sh`

---

### Atomic Certificate Deployment (IMPLEMENTED in v1.0.0)

✅ **Status**: Implemented via staged deployment + atomic `mv`

**Original Issue**: Using `cp` for certificate deployment could leave partial files if interrupted (e.g., disk full, process killed).

**Resolution**: Certificates are now staged with `.new` suffix and atomically moved into place:
1. Copy to `cert.crt.new`, `cert.key.new`, `cert-fullchain.crt.new`
2. Set correct permissions
3. Atomic `mv` to final location
4. Trap handler cleans up `.new` files on failure

---

### Intermediate CA Key Storage

⚠️ **Trade-off**: The Intermediate CA private key is stored **unencrypted** on the production server for automated certificate renewal.

**Mitigation Options**:
1. **Accept Risk**: For homelab/internal use, risk is acceptable with proper Docker security
2. **GPG Encryption**: Encrypt key with GPG (requires manual decryption for renewal)
3. **Hardware Security Module (HSM)**: Store key in HSM (YubiKey, Nitrokey, AWS CloudHSM - requires step-ca Enterprise Edition)

**Impact**: If Docker container is compromised, attacker can issue certificates for your internal domain. Clients will trust these certificates until Root CA is rotated.

**Recommendation**:
- For **homelab/SMB**: Accept risk + monitor container security
- For **production enterprise**: Use HSM-backed Intermediate CA

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) § Security Trade-offs for detailed analysis.

---

## Security Disclosure Timeline

If you report a vulnerability, we follow this process:

1. **Day 0**: Vulnerability reported
2. **Day 1-3**: Initial response + severity assessment
3. **Day 3-14**: Fix development (depending on severity)
4. **Day 14-21**: Fix deployed + Security Advisory published
5. **Day 21+**: Full public disclosure (if applicable)

**Critical vulnerabilities** (e.g., Root CA key compromise, certificate validation bypass) are prioritized and fixed within 7 days.

---

## Security Best Practices for Users

When deploying this PKI system:

1. ✅ **Backup Root CA securely**: 3 copies, 2 media types, 1 offsite (see [BACKUP.md](docs/BACKUP.md))
2. ✅ **Limit Docker exposure**: Only expose step-ca container to internal network
3. ✅ **Monitor certificate expiry**: Set up Prometheus alerts (see [monitoring/](monitoring/))
4. ✅ **Use Strong Passwords**: Protect GPG-encrypted Root CA key with strong passphrase
5. ✅ **Regular Audits**: Review issued certificates quarterly (`step-ca certificates list`)
6. ✅ **Keep step-ca Updated**: Monitor [step-ca releases](https://github.com/smallstep/certificates/releases)

---

## Vulnerability Disclosure History

No security vulnerabilities have been reported as of 2026-01-20.

---

## Contact

For security-related questions or to report a vulnerability:

- **Email**: security@fidpa.dev
- **GPG Key**: Available on request
- **Response Time**: Within 72 hours

For general questions, use [GitHub Issues](https://github.com/fidpa/step-ca-internal-pki/issues).

---

**Last Updated**: 2026-01-20
