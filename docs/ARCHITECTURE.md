# PKI Architecture

Design decisions and architecture for the step-ca two-tier PKI implementation.

## ⚡ TL;DR

Two-tier PKI: offline Root CA (10-year validity) → online Intermediate CA (5y) → automated service certificates (90d). Air-gapped Root for maximum security. Two offline sessions required for initial setup (see [Why Two Offline Sessions?](#why-two-offline-sessions)).

---

## ⚠️ CRITICAL: Revocation Limitations

**Current Implementation Status:**
| Feature | Status | Notes |
|---------|--------|-------|
| Certificate Issuance | ✅ Functional | `examples/cert-request-template.sh` |
| Automated Renewal | ✅ Functional | `renewal/renew-service-cert.sh` |
| **Revocation** | ❌ **NON-FUNCTIONAL** | See below |

### Why Revocation Doesn't Work

The default workflow uses **direct OpenSSL signing** (`openssl x509 -req`), which bypasses the step-ca database. Certificates issued this way:

- ❌ **NOT tracked** in step-ca BadgerDB
- ❌ **CANNOT be revoked** via `step ca revoke`
- ❌ **NO CRL generation** possible (would require `openssl ca -gencrl`)
- ❌ **NO OCSP responder** support

### Current Mitigation

**Compromised certificates remain valid for their full 90-day lifetime.**

To "revoke" a compromised certificate:
1. **Rotate the service's private key immediately** (generate new key + CSR)
2. **Issue a new certificate** with the new key
3. **Block compromised service** at firewall level
4. **Wait 90 days** for old certificate to expire naturally

### Future Fix Options

1. **Migrate to step-ca native issuance** (`step ca certificate`) for revocation support
2. **Implement manual CRL generation** via `openssl ca -gencrl` (complex, manual)
3. **Accept the 90-day window** for internal-only services (current recommendation)

---

## Table of Contents

- [Overview](#overview)
- [Certificate Hierarchy](#certificate-hierarchy)
- [Why Two-Tier?](#why-two-tier)
- [Why Two Offline Sessions?](#why-two-offline-sessions)
- [Trust Anchor Distribution](#trust-anchor-distribution)
- [Security Boundaries](#security-boundaries)
- [Certificate Lifecycle](#certificate-lifecycle)
- [Service Integration Patterns](#service-integration-patterns)
- [Disaster Recovery](#disaster-recovery)
- [Scaling Considerations](#scaling-considerations)
- [Compliance Mapping](#compliance-mapping)
- [Further Reading](#further-reading)

---

## Overview

This PKI uses a **two-tier certificate authority (CA)** architecture with an offline Root CA and an online Intermediate CA. This design balances security, operational simplicity, and compliance with industry best practices.

---

## Certificate Hierarchy

```
┌─────────────────────────────────┐
│      Root CA (Offline)          │
│   Validity: 10-20 years         │
│   Private Key: Air-gapped       │
└────────────┬────────────────────┘
             │ Signs
             ▼
┌─────────────────────────────────┐
│   Intermediate CA (Online)      │
│   Validity: 2-5 years           │
│   Private Key: step-ca (Docker) │
└────────────┬────────────────────┘
             │ Issues
             ▼
┌─────────────────────────────────┐
│   Service Certificates          │
│   Validity: 90 days (default)   │
│   Auto-renewal: 30 days before  │
└─────────────────────────────────┘
```

---

## Why Two-Tier?

### Advantages Over Single-Tier

| Aspect | Single-Tier (Root Only) | Two-Tier (Root + Intermediate) |
|--------|------------------------|-------------------------------|
| **Root Key Security** | Online, exposed to attacks | Offline, air-gapped |
| **Compromise Recovery** | Must reissue ALL certificates | Only reissue Intermediate + downstream |
| **Operational Flexibility** | Root must be online 24/7 | Root only needed for Intermediate renewal |
| **Compliance** | Fails most security audits | Meets PCI DSS, SOC 2, ISO 27001 |

### Why Not Three-Tier?

Three-tier PKI (Root → Policy CA → Issuing CA) is typically used in:
- **Enterprise environments** with multiple departments/geographies
- **Public CAs** requiring strict policy separation
- **Regulatory compliance** (e.g., financial sector, government)

**For homelab/SMB use cases**, three-tier adds:
- ❌ **Complexity** - Additional certificate chain to manage
- ❌ **Overhead** - More renewal/revocation operations
- ❌ **No security benefit** - Offline Root already protects against compromise

**Conclusion**: Two-tier provides optimal security-to-complexity ratio for internal PKI.

---

## Why Two Offline Sessions?

A first-time question we get often: *why do I have to go offline twice, with a step on the production server in between? Can't I do it all in one go?*

The short answer: **the sequence is forced by the architecture.**

### The Three Forced Steps

```
Offline Session 1                  Online Step                  Offline Session 2
─────────────────                  ───────────                  ─────────────────
Create Root CA      ──────────►    Create Intermediate          Sign Intermediate
key + self-signed                  key + CSR on production      CSR with Root key
cert (10 years)     root_ca.crt    server (will live there      (5 years)
                    travels via    permanently, never           intermediate_ca.crt
                    USB            air-gapped again)            travels via USB
```

### Why Each Step Lives Where It Does

| Step | Location | Why? |
|------|----------|------|
| Root CA key + cert | Air-gapped machine | The Root key must **never** touch the production server. If it did, the whole "offline Root CA" security model collapses. |
| Intermediate key + CSR | Production server | The Intermediate key will sign service certs **for years**, fully automated. It has to live where the automation runs. Generating it elsewhere and transferring it would expose the private key during transport. |
| Intermediate signing | Air-gapped machine | Signing requires the Root key. The Root key only exists offline. So the CSR has to come to the Root, not the other way around. |

You can't merge steps without breaking one of these rules:
- **Merge 1 + 2** → Root key visits production server (forbidden).
- **Merge 2 + 3** → Intermediate key originates on air-gapped machine and travels via USB to production (private key transport risk).
- **Skip the online step** → You'd have to pre-generate Intermediate keys on the air-gapped machine for every CA refresh — same transport problem.

### The Analogy

Think of it like notarizing a document with a presidential seal locked in a vault:

- **Root CA** = the presidential seal (vault, used rarely, only for appointing notaries)
- **Intermediate CA** = the notary (works daily in their office)
- **Service cert** = the notarized document

You make two trips to the vault — once to forge the seal (create Root), once to use it to commission a notary (sign Intermediate). After that, the notary handles thousands of documents without ever bothering the vault.

### How Often in the Future?

| Trigger | Offline session needed? | Frequency |
|---------|------------------------|-----------|
| Service certs (90-day) | ❌ No — Intermediate signs them automatically | Continuously |
| Intermediate renewal | ✅ Yes — 1 offline session to re-sign | Every 5 years |
| Intermediate compromised | ✅ Yes — emergency re-sign | Rare |
| Root renewal | ✅ Yes — full setup from scratch | Every 10 years |

After initial setup: **no offline sessions for 5 years** in normal operation.

### See Also

- [SETUP.md → Workflow Overview](SETUP.md#workflow-overview) — visual diagram of the three steps
- [Security Boundaries](#security-boundaries) — what "offline" actually means in practice

---

## Trust Anchor Distribution

### Trust Model

Clients/services must trust the **Root CA certificate** (not the Intermediate CA). The trust anchor is the Root CA's public certificate (`root_ca.crt`).

**Why Root CA and not Intermediate?**
- Intermediate CA can be reissued/replaced without client updates
- Root CA change requires all clients to update trust store (rare event)

### Distribution Methods

| Platform | Installation Method | Path |
|----------|---------------------|------|
| **Linux** | `update-ca-certificates` | `/usr/local/share/ca-certificates/` |
| **macOS** | `security add-trusted-cert` | System Keychain |
| **Windows** | `certutil -addstore Root` | Trusted Root Certification Authorities |
| **Firefox** | Manual import | Preferences → Certificates |
| **Docker** | COPY to container | `/usr/local/share/ca-certificates/` + RUN update-ca-certificates |

See [CLIENT_TRUST.md](CLIENT_TRUST.md) for detailed installation scripts.

---

## Security Boundaries

### Offline Root CA

**Storage Requirements:**
- ✅ Air-gapped machine (no network connectivity)
- ✅ Full-disk encryption (LUKS, BitLocker, FileVault)
- ✅ GPG-encrypted private key (`root_ca_key.pem.gpg`)
- ✅ Multiple backups (3-2-1 rule: 3 copies, 2 media types, 1 offsite)

**Access Control:**
- ✅ Physical security (locked safe, HSM if available)
- ✅ Multi-person authorization (for key usage)
- ✅ Audit logging (who accessed when)

**Recommended Setup:**
- Raspberry Pi with no WiFi/Ethernet (USB disabled in firmware)
- Bootable USB with Tails OS (amnesic, leaves no traces)
- YubiKey/Nitrokey for GPG key storage

### Online Intermediate CA

**step-ca Container Security:**
- ✅ Runs as non-root user (`1000:1000`)
- ⚠️ Writable filesystem (`read_only: false` - required for step-ca database)
- ✅ Limited capabilities (no `CAP_SYS_ADMIN`)
- ✅ Private network (no direct internet exposure)

**Access Control:**
- ✅ TLS-protected Admin API (port 9643)
- ✅ Client certificate authentication (optional)
- ✅ Rate limiting (DoS protection)

**Monitoring:**
- ✅ Certificate expiry alerts (Prometheus)
- ✅ Container health checks (Docker)
- ✅ CRL distribution monitoring

---

## Certificate Lifecycle

### Issuance

This PKI supports **two certificate issuance workflows**:

#### Workflow A: OpenSSL-based (Default, Recommended for Simplicity)

1. **Request Generation** - Service generates CSR with SANs (DNS, IP)
2. **Validation** - Manual CSR validation (domain ownership, authorization)
3. **Signing** - **OpenSSL signing** (Intermediate CA signs directly, 90-day validity)
4. **Distribution** - Certificate + fullchain written to `/etc/ssl/step-ca/`

**Automation**: `examples/cert-request-template.sh` handles steps 1-4.

**Pros**: Simple, no container required, works offline
**Cons**: Certificates not in step-ca database (no OCSP, limited revocation)

#### Workflow B: ACME-based (Advanced, Requires step-ca Container)

1. **ACME Client** - certbot/acme.sh requests certificate from step-ca API
2. **Validation** - HTTP-01 or DNS-01 challenge
3. **Signing** - step-ca signs and registers in BadgerDB
4. **Distribution** - ACME client writes certificate to configured path

**Pros**: Fully automated, certificates in database, OCSP support, standard revocation
**Cons**: Requires running container, more complex setup

> **Design Decision**: The default workflow uses OpenSSL signing for simplicity and offline capability. The step-ca container is provided for users who want ACME automation or need OCSP/revocation features. Both workflows use the same Intermediate CA.

**Note**: This setup uses a **Two-Tier PKI architecture**:
- **Root CA**: Fully offline (air-gapped, encrypted backup, only used for signing Intermediate CA)
- **Intermediate CA**: Online in Docker container (issues service certificates via OpenSSL)

The Root CA private key NEVER touches the production server. The Intermediate CA key is stored in the Docker volume for automated certificate renewal.

### Renewal

**Automatic Renewal:**
- **Trigger**: systemd timer (daily checks)
- **Threshold**: 30 days before expiry
- **Process**: `renewal/renew-service-cert.sh` requests new certificate
- **Rollback**: Keeps old certificate if renewal fails

**Manual Renewal:**
```bash
sudo SERVICE_NAME=myservice /usr/local/bin/renew-service-cert.sh
```

### Revocation

**When to Revoke:**
- Private key compromise
- Service decommissioned
- Certificate replaced (superseded)
- Affiliation change (user left organization)

**Revocation Process:**

⚠️ **Note**: Due to the Offline CA design, certificates are not registered in step-ca's database. The `revocation/revoke-cert.sh` script requires manual CRL generation via OpenSSL.

**Manual Revocation Steps:**
1. Revoke certificate: `openssl ca -revoke <cert> -config openssl.cnf`
2. Generate CRL: `openssl ca -gencrl -out crl.pem -config openssl.cnf`
3. Distribute CRL to clients (via HTTP/HTTPS endpoint or file copy)
4. Clients check CRL before trusting certificate

**CRL Distribution:**
- **Method**: Manual distribution (HTTP endpoint or file-based)
- **Update Frequency**: Manual (after each revocation)
- **Caching**: Client-side (browsers cache 24h-7d)

---

## Service Integration Patterns

### Pattern 1: Direct TLS (No Reverse Proxy)

```
┌──────────────────┐
│   Service        │
│   (e.g. PostgreSQL)
│   TLS: 5432      │
└─────────┬────────┘
          │ Uses step-ca cert directly
          │
      [Clients connect via TLS]
```

**Use Cases**: Databases, LDAP, SMTP servers

**Certificate Location**: `/etc/ssl/step-ca/service.{crt,key}`

### Pattern 2: nginx TLS Termination

```
┌──────────────────┐       ┌──────────────────┐
│   nginx          │       │   Backend        │
│   TLS: 443       │◄─────►│   HTTP: 8080     │
└─────────┬────────┘       └──────────────────┘
          │ step-ca cert
          │
      [Clients connect via HTTPS]
```

**Use Cases**: Vaultwarden, Nextcloud, Portainer, Web UIs

**Certificate Location**: nginx mounts `/etc/ssl/step-ca/` volume

See [NGINX_TLS.md](NGINX_TLS.md) for detailed configuration.

### Pattern 3: Docker Internal Mesh (mTLS)

```
┌──────────────────┐       ┌──────────────────┐
│   Service A      │◄─────►│   Service B      │
│   mTLS: 443      │       │   mTLS: 443      │
└──────────────────┘       └──────────────────┘
    │                           │
    └───────────┬───────────────┘
                │ Both use step-ca certs
            [Mutual TLS authentication]
```

**Use Cases**: Microservices, service mesh (Consul, Linkerd)

**Certificate Location**: Each container mounts its own cert/key pair

---

## Disaster Recovery

### Root CA Compromise

**Indicators:**
- Unauthorized certificates issued
- Private key file accessed/modified
- Physical security breach

**Recovery Steps:**
1. **Immediately**: Revoke Intermediate CA certificate
2. **Generate new Root CA** (entirely new key pair)
3. **Reissue Intermediate CA** from new Root
4. **Redistribute new Root CA** to all clients (trust anchor update)
5. **Reissue all service certificates** (signed by new Intermediate)
6. **Incident report** (root cause analysis, lessons learned)

**Downtime**: 4-8 hours (depending on client count)

### Intermediate CA Compromise

**Indicators:**
- Unauthorized service certificates issued
- step-ca container breached
- Private key exposed

**Recovery Steps:**
1. **Immediately**: Stop step-ca container
2. **Revoke compromised Intermediate CA** (using offline Root CA)
3. **Issue new Intermediate CA** from Root
4. **Deploy new Intermediate CA** to step-ca
5. **Reissue service certificates** (old certs still valid but should rotate)
6. **Update CRL** with revoked certificates

**Downtime**: 30-60 minutes (clients keep using existing certs)

### step-ca Data Loss

**Critical Files:**
- `/opt/step-ca/secrets/intermediate_ca_key` - Intermediate CA private key
- `/opt/step-ca/config/ca.json` - CA configuration
- `/opt/step-ca/db/` - Certificate database (badger DB)

**Recovery:**
1. **Restore from backup** (see [BACKUP.md](BACKUP.md))
2. **Verify Intermediate CA cert/key integrity**
3. **Restart step-ca container**
4. **Test certificate issuance** (dry-run)

**Prevention**: Daily automated backups to `/opt/backups/` + offsite rsync

---

## Scaling Considerations

### Small Scale (1-50 services)

**Setup**: Single step-ca container (this repository)
- **CPU**: 1 core sufficient
- **RAM**: 512 MB sufficient
- **Storage**: 1 GB sufficient
- **Renewal**: systemd timers per service

### Medium Scale (50-500 services)

**Setup**: step-ca + ACME protocol
- **Automation**: ACME clients (certbot, acme.sh)
- **Load Balancing**: Multiple step-ca replicas (shared DB)
- **Monitoring**: Prometheus + Grafana dashboards

### Large Scale (500+ services)

**Setup**: step-ca cluster + HashiCorp Vault
- **High Availability**: Multi-region step-ca deployment
- **Secret Management**: Vault for key distribution
- **Orchestration**: Kubernetes cert-manager integration
- **Compliance**: CIS Kubernetes Benchmark, PCI DSS Level 1

---

## Compliance Mapping

| Standard | Requirement | Implementation |
|----------|-------------|----------------|
| **PCI DSS 4.1** | Strong cryptography for transmission | TLS 1.2+, ECDHE ciphers |
| **PCI DSS 4.2** | Never use default keys | Unique keys per service |
| **SOC 2 CC6.6** | Logical access controls | TLS client certs, key-based auth |
| **ISO 27001 A.10.1** | Cryptographic controls | 2048-bit RSA / 256-bit ECDSA |
| **NIST 800-53 SC-8** | Confidentiality/integrity | TLS 1.3, certificate pinning |

---

## Further Reading

- [SETUP.md](SETUP.md) - Installation and initial configuration
- [BACKUP.md](BACKUP.md) - Backup and disaster recovery procedures
- [NGINX_TLS.md](NGINX_TLS.md) - nginx TLS termination patterns
- [Smallstep Documentation](https://smallstep.com/docs/step-ca) - Official step-ca docs
- [RFC 5280](https://tools.ietf.org/html/rfc5280) - X.509 PKI Certificate standard
- [Mozilla SSL Configuration Generator](https://ssl-config.mozilla.org/) - TLS best practices
