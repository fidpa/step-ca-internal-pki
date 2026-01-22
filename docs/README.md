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
| [TROUBLESHOOTING.md](TROUBLESHOOTING.md) | Common issues and solutions | All users |

## Reading Order

### New Users (Getting Started)

1. **[SETUP.md](SETUP.md)** - Install step-ca and create your PKI (~60 min)
2. **[CLIENT_TRUST.md](CLIENT_TRUST.md)** - Install Root CA on all clients
3. **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** - When things don't work

### Understanding the System

4. **[ARCHITECTURE.md](ARCHITECTURE.md)** - Why two-tier PKI? Design decisions
5. **[NGINX_TLS.md](NGINX_TLS.md)** - Service integration patterns

### Operations & Maintenance

6. **[BACKUP.md](BACKUP.md)** - Critical: Protect your Root CA!

## Document Overview

### SETUP.md (460 lines)

Complete installation guide with 6 phases:
- Phase 1: Create Root CA (offline, air-gapped)
- Phase 2: Create Intermediate CA
- Phase 3: Deploy step-ca Docker container
- Phase 4: Request first service certificate
- Phase 5: Set up auto-renewal
- Phase 6: Install client trust

### ARCHITECTURE.md (360 lines)

PKI design documentation covering:
- Two-tier CA hierarchy rationale
- Security boundaries
- Certificate lifecycle management
- Compliance mapping (PCI DSS, SOC 2, ISO 27001)

### CLIENT_TRUST.md (578 lines)

Cross-platform Root CA installation:
- Linux (Ubuntu/Debian, Fedora/RHEL)
- macOS (Keychain integration)
- Windows (certutil)
- Browsers (Firefox, Chrome)
- Docker containers

### NGINX_TLS.md (586 lines)

nginx TLS configuration patterns:
- TLS termination setup
- Security headers
- Certificate chain configuration
- Reverse proxy patterns

### BACKUP.md (574 lines)

PKI backup and disaster recovery:
- 3-2-1 backup strategy
- Root CA key protection (GPG encryption)
- Recovery procedures
- Backup verification

### TROUBLESHOOTING.md (426 lines)

Common issues and solutions:
- Certificate validation errors
- step-ca connection issues
- Browser trust problems
- Renewal failures

## Document Status

| Document | Lines | Status | Last Updated |
|----------|-------|--------|--------------|
| SETUP.md | 460 | ✅ Complete | 2026-01-20 |
| ARCHITECTURE.md | 360 | ✅ Complete | 2026-01-20 |
| CLIENT_TRUST.md | 578 | ✅ Complete | 2026-01-20 |
| NGINX_TLS.md | 586 | ✅ Complete | 2026-01-20 |
| BACKUP.md | 574 | ✅ Complete | 2026-01-20 |
| TROUBLESHOOTING.md | 426 | ✅ Complete | 2026-01-20 |

**Total**: ~2984 lines of documentation

## See Also

- [← Back to Root](../README.md)
- [Examples](../examples/)
- [Monitoring](../monitoring/)
- [systemd Templates](../systemd/)
