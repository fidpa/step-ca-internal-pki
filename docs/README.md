# Documentation

Comprehensive guides for step-ca Internal PKI setup, operation, and troubleshooting.

## Quick Navigation

| Document | Description | Audience |
|----------|-------------|----------|
| [SETUP.md](SETUP.md) | Complete 6-phase installation guide | All users |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Two-tier PKI design decisions | All users |
| [CLIENT_TRUST.md](CLIENT_TRUST.md) | Cross-platform Root CA installation | All users |
| [NGINX_TLS.md](NGINX_TLS.md) | nginx TLS termination patterns | Developers |
| [BACKUP.md](BACKUP.md) | 3-2-1 backup strategy for PKI | Admins |
| [COEXISTENCE.md](COEXISTENCE.md) | Run step-ca alongside acme-dns, Pi-hole, AD DNS | Admins |
| [TROUBLESHOOTING.md](TROUBLESHOOTING.md) | Common issues and solutions | All users |

## Reading Order

### New Users (Getting Started)

1. **[SETUP.md](SETUP.md)** — Install step-ca and create your PKI (~75 min)
2. **[CLIENT_TRUST.md](CLIENT_TRUST.md)** — Install Root CA on all clients
3. **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** — When things don't work

### Understanding the System

4. **[ARCHITECTURE.md](ARCHITECTURE.md)** — Why two-tier PKI? Why two offline sessions?
5. **[NGINX_TLS.md](NGINX_TLS.md)** — Service integration patterns

### Operations & Maintenance

6. **[BACKUP.md](BACKUP.md)** — Critical: protect your Root CA
7. **[COEXISTENCE.md](COEXISTENCE.md)** — Existing DNS/ACME infrastructure on the same host

## Document Overview

### SETUP.md

Complete installation guide with six phases. Includes a workflow diagram of the
**two offline sessions** required for setup (Root CA creation + Intermediate
signing) and the online intermediate step in between.

### ARCHITECTURE.md

PKI design documentation covering:
- Two-tier CA hierarchy rationale
- Why two offline sessions are required (and why only two)
- Security boundaries
- Certificate lifecycle management
- Compliance mapping (PCI DSS, SOC 2, ISO 27001)

### CLIENT_TRUST.md

Cross-platform Root CA installation:
- Linux (Ubuntu/Debian, Fedora/RHEL)
- macOS (Keychain integration)
- Windows (certutil, GPO)
- Browsers (Firefox, Chrome)
- Docker containers

### NGINX_TLS.md

nginx TLS configuration patterns:
- TLS termination setup
- Security headers
- Certificate chain configuration
- Reverse proxy patterns

### BACKUP.md

PKI backup and disaster recovery:
- 3-2-1 backup strategy
- Root CA key protection (GPG encryption)
- Recovery procedures
- Backup verification

### COEXISTENCE.md

Running step-ca alongside existing services on port 53 or 80:
- step-ca with acme-dns (port 53 conflict)
- step-ca with Pi-hole / dnsmasq
- step-ca with Active Directory DNS
- Split-horizon DNS patterns

### TROUBLESHOOTING.md

Common issues and solutions:
- Certificate validation errors
- step-ca container restart loops (missing `password` file)
- Browser trust problems
- DNS / TLS resolution issues
- Renewal failures

## See Also

- [← Back to Root](../README.md)
- [Examples](../examples/)
- [Monitoring](../monitoring/)
- [systemd Templates](../systemd/)
