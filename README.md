# step-ca Internal PKI

![Version](https://img.shields.io/badge/version-1.3.6-blue)
![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)
![Platform](https://img.shields.io/badge/platform-Linux-lightgrey?logo=linux)
![Bash](https://img.shields.io/badge/Bash-4.0%2B-blue?logo=gnu-bash)
![Docker](https://img.shields.io/badge/Docker-20.10%2B-blue?logo=docker)
![CI](https://github.com/fidpa/step-ca-internal-pki/actions/workflows/lint.yml/badge.svg)
![Status](https://img.shields.io/badge/status-production-brightgreen)
![step-ca](https://img.shields.io/badge/step--ca-production--ready-orange)
![Last Commit](https://img.shields.io/github/last-commit/fidpa/step-ca-internal-pki)

Production-ready PKI (Public Key Infrastructure) setup with [Smallstep's step-ca](https://smallstep.com/docs/step-ca) Certificate Authority. Includes scripts, documentation, and service integration examples for internal HTTPS without browser warnings.

**The Problem**: Self-hosted services like Vaultwarden, Nextcloud, or Portainer typically run on IP addresses (`https://192.168.1.50:8443`) with browser security warnings. Let's Encrypt doesn't work for internal domains. Manual OpenSSL certificate management is complex and doesn't scale. After setting up a production PKI for 6+ internal services with auto-renewal and monitoring, I've extracted the complete setup into this repository.

## Features

- **Two-Tier PKI** - Offline Root CA + Online Intermediate CA for enhanced security
- **Battle-Tested Scripts** - Air-gap verification, decrypt-verify, cleanup-trap, cross-platform secure-delete (`scripts/`)
- **Auto-Renewal** - systemd timers for automatic certificate renewal (30-day threshold, `--force` re-issue)
- **Failure Notifications** - `OnFailure=` hook template: a silently failing nightly renewal notifies you instead of surfacing as a browser warning weeks later
- **Prometheus Monitoring** - Certificate expiry metrics and alerts
- **Service Integration** - Examples for Vaultwarden, Nextcloud, Portainer, nginx
- **⚠️ CRL Support** - Certificate Revocation Lists (EXPERIMENTAL - see [Limitations](#known-limitations))
- **Client Trust** - Cross-platform Root CA installation (macOS, Linux, Windows)
- **Atomic Deployment** - Race-condition-free certificate deployment with flock locking
- **NTP Monitoring** - Time synchronization validation (critical for certificate validity)
- **Coexistence Patterns** - Documented integration with acme-dns, Tailscale/WireGuard MagicDNS, Active Directory DNS ([`docs/COEXISTENCE.md`](docs/COEXISTENCE.md))
- **Production-Tested** - Scripts and configs battle-tested in production

## ⚠️ Known Limitations

> **IMPORTANT**: The default workflow uses **direct OpenSSL signing**, which means:
>
> - ❌ **Revocation is NOT functional** - Certificates cannot be revoked via `step ca revoke`
> - ❌ Certificates are NOT tracked in step-ca's database (BadgerDB)
> - ✅ **Mitigation**: Short-lived certificates (90 days) minimize exposure window
>
> See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md#-critical-revocation-limitations) for details and workarounds.

## Quick Start

```bash
# Clone the repository
git clone https://github.com/fidpa/step-ca-internal-pki.git
cd step-ca-internal-pki
```

### Prerequisites

**Production server:**
- Docker & Docker Compose
- OpenSSL
- Root access for certificate deployment

**Air-gapped machine (Root CA + Intermediate signing):**
- `step` CLI ≥ 0.25 — `brew install step` (macOS) or [smallstep.com/docs](https://smallstep.com/docs/step-cli/installation)
- `gpg` ≥ 2.2 — `brew install gnupg` / `apt install gnupg`
- `coreutils` (macOS only, for stronger `shred`) — `brew install coreutils`

> **macOS Brew-PATH gotcha**: Non-login SSH sessions and cron jobs don't auto-source `~/.zshrc`. The provided scripts prepend `/opt/homebrew/bin:/usr/local/bin` to `$PATH` automatically.

### 1. Create Root CA (Offline, on air-gapped machine)

```bash
# Run on air-gapped laptop (Wi-Fi off, Ethernet unplugged, VPN disconnected).
# Script aborts if it detects network connectivity.
CA_NAME="My Internal Root CA 2026" ./scripts/create-root-ca.sh

# Output: ~/.ca-creation-YYYYMMDD-HHMMSS/
#   - root_ca.crt           → copy to production server
#   - root_ca.key.gpg       → keep on USB stick in safe (3-2-1 rule)
#   - checksums.sha256
```

### 2. Generate Intermediate CSR (on production server)

```bash
INTERMEDIATE_CN="My Internal Intermediate CA 2026" \
INTERMEDIATE_O="My Org" \
INTERMEDIATE_C="DE" \
  ./scripts/generate-intermediate-csr.sh

# Output:
#   /opt/step-ca/secrets/intermediate_ca_key   (ECDSA P-256)
#   /tmp/intermediate_ca.csr                   → transport to air-gapped machine
```

### 3. Sign Intermediate (back on air-gapped machine)

```bash
# Insert USB with root_ca.crt, root_ca.key.gpg, intermediate_ca.csr
USB_MOUNT="/Volumes/USB" ./scripts/sign-intermediate-ca.sh

# Output written to USB:
#   intermediate_ca.crt      → transport back to production server
```

### 4. Deploy step-ca

```bash
# Install signed intermediate + create empty password file (REQUIRED, see Phase 3 docs)
sudo install -o 1000 -g 1000 -m 644 intermediate_ca.crt /opt/step-ca/certs/
sudo install -o 1000 -g 1000 -m 600 /dev/null /opt/step-ca/secrets/password

# Trust Root CA on the server
sudo install -m 644 root_ca.crt /usr/local/share/ca-certificates/my-internal-root-ca.crt
sudo update-ca-certificates

# Deploy container
cd /opt/step-ca && docker compose -f step-ca-stack.yml up -d
curl -k https://localhost:9643/health   # → {"status":"ok"}
```

### 5. Request Service Certificate

```bash
# Customize the template for your service
cp examples/cert-request-template.sh /tmp/myservice-cert-request.sh
# Edit DNS_SANS and IP_SANS

# Run as root
sudo /tmp/myservice-cert-request.sh
# Output: /etc/ssl/step-ca/myservice.{crt,key} + myservice-fullchain.crt
```

### 6. Configure Auto-Renewal

```bash
# Install systemd timer
cp systemd/step-ca-renew.service.template /etc/systemd/system/myservice-renew.service
cp systemd/step-ca-renew.timer.template /etc/systemd/system/myservice-renew.timer

# Edit environment variables in service file
sudo systemctl daemon-reload
sudo systemctl enable --now myservice-renew.timer
```

### 7. Set up Monitoring (Optional)

```bash
# Install cert-exporter
cp monitoring/cert-exporter.sh /usr/local/bin/
chmod +x /usr/local/bin/cert-exporter.sh

# Configure for Prometheus textfile collector
# See monitoring/README.md
```

## Use Cases

- ✅ **Homelab Security** - Internal services with trusted HTTPS
- ✅ **SMB Internal PKI** - Affordable alternative to enterprise PKI solutions
- ✅ **Kubernetes TLS** - Local k3s/k8s clusters with internal certificates
- ✅ **Development** - Local HTTPS development with trusted certificates
- ✅ **IoT/Embedded** - Raspberry Pi, ESP32 with TLS

## 🎯 When to Use This System

**Perfect for:**
- 🏠 **Homelab/Self-hosted** services needing trusted HTTPS without public DNS
- 🔧 **SMB Internal PKI** (<100 devices, no budget for enterprise PKI)
- 🐳 **Docker stacks** requiring TLS without Let's Encrypt (no public domains)
- 🎓 **Learning PKI fundamentals** (Certificate Authority, TLS, mTLS)
- 🌐 **IoT/Embedded** devices (Raspberry Pi, ESP32) with internal HTTPS

**NOT recommended for:**
- ☁️ **Public-facing services** → Use Let's Encrypt (free, automated, trusted by all browsers)
- 🏢 **Enterprise PKI** (500+ devices) → Use HashiCorp Vault or commercial PKI solutions
- 📱 **Mobile apps** requiring publicly trusted certificates → Let's Encrypt or commercial CA
- 🔐 **Hardware Security Modules (HSM)** → Requires step-ca Enterprise Edition

**Alternative solutions**: Let's Encrypt (public domains), HashiCorp Vault (enterprise scale), AWS Certificate Manager (cloud-only), commercial PKI (support contracts). See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for detailed comparison.

## Key Concepts

### The Two-Tier PKI Architecture

**Most important design decision in this project**:

```
Root CA (Offline)
    ↓ Signs
Intermediate CA (Online, step-ca)
    ↓ Issues
Service Certificates (Auto-renewed)
```

**Why Two-Tier instead of Single-Tier**:
- **Security**: Root CA private key NEVER touches production (air-gapped)
- **Compromise Recovery**: If Intermediate CA compromised, only reissue Intermediate + service certs (NOT all clients)
- **Compliance**: Meets PCI DSS, SOC 2, ISO 27001 requirements
- **Operational Flexibility**: Root CA only needed for Intermediate renewal (~every 2-5 years)

**Alternative**: Single-Tier PKI (Root CA issues certs directly) → Root CA must be online 24/7, higher compromise risk.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for technical deep dive.

### The Offline Root CA Pattern

**Critical for production PKI**:

1. **Air-gapped Machine**: Raspberry Pi with no WiFi/Ethernet (USB disabled in firmware)
2. **GPG Encryption**: `root_ca_key.pem.gpg` (encrypted private key)
3. **Multiple Backups**: 3-2-1 rule (3 copies, 2 media types, 1 offsite)
4. **Physical Security**: Locked safe, multi-person authorization

**Why Offline**:
- Root CA compromise = re-trust all clients (catastrophic)
- Online exposure = attack surface
- Offline = ONLY used for Intermediate CA renewal (every 2-5 years)

## Repository Structure

```
step-ca-internal-pki/
├── config/               # Docker Compose stack configuration
│   ├── README.md         # Configuration guide
│   └── step-ca-stack.yml # step-ca container deployment
├── scripts/              # Battle-tested PKI lifecycle scripts (v1.2.0+)
│   ├── README.md         # Scripts overview + workflow diagram
│   ├── create-root-ca.sh           # Offline Root CA (air-gap verified)
│   ├── generate-intermediate-csr.sh # Server-side Intermediate key + CSR
│   └── sign-intermediate-ca.sh     # Offline Intermediate signing
├── docs/                 # Documentation (7 guides)
│   ├── README.md         # Navigation hub
│   ├── SETUP.md          # Installation guide
│   ├── ARCHITECTURE.md   # PKI design decisions
│   ├── CLIENT_TRUST.md   # Cross-platform Root CA installation
│   ├── NGINX_TLS.md      # nginx TLS termination
│   ├── COEXISTENCE.md    # Integration with acme-dns, Tailscale, AD-DNS (v1.2.0+)
│   ├── BACKUP.md         # 3-2-1 backup strategy
│   └── TROUBLESHOOTING.md# Common issues + DNS coexistence pitfalls
├── examples/             # Service integration examples
│   ├── README.md         # Examples overview
│   ├── cert-request-template.sh
│   ├── vaultwarden/      # Password manager
│   ├── nextcloud/        # Cloud storage
│   ├── portainer/        # Docker management
│   └── generic/          # nginx reverse proxy
├── monitoring/           # Prometheus metrics exporters
│   ├── README.md         # Monitoring guide
│   ├── cert-exporter.sh  # Certificate expiry metrics
│   ├── check-time-sync.sh # NTP time synchronization validation
│   ├── prometheus-rules.yml    # Alert rules (expiry, staleness, container)
│   └── grafana-dashboard.json  # Certificate monitoring dashboard
├── renewal/              # Auto-renewal scripts
│   ├── README.md         # Renewal workflow
│   └── renew-service-cert.sh   # --force flag + pubkey match check (v1.3.0+)
├── revocation/           # Certificate revocation (⚠️ EXPERIMENTAL)
│   ├── README.md         # Revocation guide
│   └── revoke-cert.sh
├── systemd/              # systemd templates
│   ├── README.md         # Timer setup + ReadWritePaths hardening
│   ├── step-ca-renew.service.template
│   ├── step-ca-renew.timer.template
│   ├── step-ca-renew-failure-notify.service.template  # OnFailure hook (v1.3.0+)
│   ├── check-time-sync.service
│   └── check-time-sync.timer
├── CONTRIBUTING.md       # Contribution guidelines
├── CODE_OF_CONDUCT.md    # Community standards
├── SECURITY.md           # Security policy
├── CHANGELOG.md          # Version history
└── LICENSE               # MIT License
```

## Component Overview

| Component | Purpose | Technology | Complexity |
|-----------|---------|------------|-----------|
| `renewal/` | Auto-renewal of service certificates (30-day threshold) | Bash + systemd timers | Low (~100 LOC) |
| `monitoring/` | Certificate expiry metrics for Prometheus | Bash + node_exporter textfile | Low (~150 LOC) |
| `revocation/` | Certificate revocation (CRL distribution) | OpenSSL + Bash | Medium (~200 LOC, ⚠️ EXPERIMENTAL) |
| `examples/` | Service integration templates (Vaultwarden, Nextcloud, Portainer, generic nginx) | docker-compose + nginx | Varies (379-453 LOC per service) |
| `docs/` | Architecture guides, setup instructions, troubleshooting | Markdown (6 docs) | N/A |
| `systemd/` | Service/timer templates for auto-renewal | systemd unit files | Template-based |
| `config/` | step-ca Docker Compose stack configuration | YAML | Low (~50 LOC) |

## Service Integration Examples

**Available Examples:**
- **Vaultwarden** - Password manager with TLS (`examples/vaultwarden/`)
- **Nextcloud** - Cloud storage with TLS (`examples/nextcloud/`)
- **Portainer** - Docker management with TLS (`examples/portainer/`)
- **Generic** - nginx reverse proxy template (`examples/generic/`)

Each example includes:
- `docker-compose.yml` - Service container configuration
- `nginx.conf` - TLS termination configuration
- `README.md` - Setup instructions

## Documentation

| Document | Description |
|----------|-------------|
| [SETUP.md](docs/SETUP.md) | Complete installation guide |
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | PKI design decisions |
| [CLIENT_TRUST.md](docs/CLIENT_TRUST.md) | Cross-platform Root CA installation |
| [COEXISTENCE.md](docs/COEXISTENCE.md) | Integration with acme-dns / Tailscale / AD-DNS |
| [BACKUP.md](docs/BACKUP.md) | 3-2-1 backup strategy |
| [NGINX_TLS.md](docs/NGINX_TLS.md) | nginx TLS termination |
| [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Common issues |

📚 **Recommended reading order**: SETUP → ARCHITECTURE → CLIENT_TRUST → COEXISTENCE → NGINX_TLS → BACKUP → TROUBLESHOOTING

## vs. Alternatives

| Solution | Pros | Cons |
|----------|------|------|
| **Let's Encrypt** | Free, automatic | Public domains only |
| **OpenSSL (manual)** | Full control | Complex, no automation |
| **step-ca Official Docs** | Good basics | No production patterns |
| **Enterprise PKI** | Support, GUI | Expensive ($5,000+), overkill |
| **This Repo** | Production-ready, multi-service, monitoring | step-ca only, no GUI |

**Unique Value:**
- **Production Patterns** - Auto-renewal, monitoring, service integration
- **Multi-Service** - Tested with 6+ services (Vaultwarden, Nextcloud, etc.)
- **Monitoring** - Prometheus alerts, Grafana dashboards
- **Client Trust** - Cross-platform automation
- **Coexistence** - Documented patterns for living next to acme-dns / Tailscale / AD-DNS
- **Air-Gap Safety** - Scripts verify offline state before touching the Root key
- **CRL Architecture** - Certificate revocation support

## Requirements

- **OS**: Linux (tested on Ubuntu 22.04+, Debian 11+)
- **Docker**: 20.10+
- **OpenSSL**: 1.1.1+ (for certificate operations)
- **Bash**: 4.0+ (for scripts)

## Compatibility

**Fully supported**:
- Ubuntu 22.04 LTS, 24.04 LTS
- Debian 11 (Bullseye), 12 (Bookworm)
- Raspberry Pi OS (64-bit)

**Should work** (untested):
- Other systemd-based distros with Docker support
- macOS (for client trust scripts only)
- WSL2 (Windows Subsystem for Linux)

## Security

- **Offline Root CA** - Air-gapped, GPG-encrypted, multiple backups
- **Short-Lived Certificates** - 90 days validity (step-ca default)
- **Auto-Renewal** - 30-day threshold prevents expiry
- **CRL Distribution** - HTTP endpoint for revocation checking
- **Monitoring** - Prometheus alerts 30/7/1 days before expiry

## Real-World Results

**Proven in Production**:
- 🚀 **Pi 5 Router** (ARM64, 6 services): 100% certificate uptime, auto-renewal since Dec 2025
- 🚀 **NAS Server** (x86_64, AMD Ryzen 9, 38 Docker containers): Zero browser warnings across all services
- 🚀 **6+ integrated services**: Vaultwarden, Nextcloud, Portainer, Dashboard, Grafana, Prometheus

**Key Metrics**:
- Certificate expiry incidents: **0** (auto-renewal working)
- Manual certificate renewal required: **0** (systemd timers handle everything)
- Browser trust warnings: **0** (Root CA installed on all clients)
- Platforms tested: ARM64 (Raspberry Pi 5) + x86_64 (AMD Ryzen 9)
- Certificate validity: 90 days (step-ca default)
- Renewal threshold: 30 days before expiry

**Monitoring Coverage**:
- Prometheus metrics: Certificate expiry in days
- Grafana alerts: 30/7/1 day warnings
- Telegram notifications: Critical expiry warnings

## Contributing

Contributions welcome! Please:
1. Test changes in a local environment
2. Follow existing script patterns (SPDX headers, inline logging)
3. Update documentation
4. Submit pull request with clear description

**Areas where help is appreciated**:
- Additional service integration examples (GitLab, Grafana, Authentik, Keycloak)
- Testing on additional platforms (Alpine Linux, Arch, OpenSUSE, RHEL)
- ACME protocol support (automated certificate requests without manual CSR)
- Web UI for certificate management (dashboard for CA administration)
- Health check examples for container-specific validation
- Grafana dashboard examples for certificate expiry visualization
- mTLS examples for service-to-service authentication

## License

MIT License - see [LICENSE](LICENSE)

## Author

Marc Allgeier ([@fidpa](https://github.com/fidpa))

**Why I Built This**: After clicking through browser warnings for months (`https://192.168.1.50:8443` is not a great experience), I finally set up a proper internal PKI. The official step-ca documentation covers basics well, but lacks production patterns: multi-service integration, monitoring, auto-renewal automation, and client trust distribution. This repo consolidates everything I learned into a reusable setup.

## See Also

- [ubuntu-server-security](https://github.com/fidpa/ubuntu-server-security) - Security hardening (12 components, CIS Benchmark)
- [bash-production-toolkit](https://github.com/fidpa/bash-production-toolkit) - Production-ready Bash libraries
- [monitoring-templates](https://github.com/fidpa/monitoring-templates) - Bash/Python monitoring templates

## Support

- **Issues**: [GitHub Issues](https://github.com/fidpa/step-ca-internal-pki/issues)
- **Documentation**: See [docs/](docs/) directory
- **step-ca Docs**: https://smallstep.com/docs/step-ca

## Credits

Built with [Smallstep step-ca](https://github.com/smallstep/certificates) - A lightweight, open-source Certificate Authority.

---

**Production-tested since December 2025** | v1.3.6 (August 2026) | 8 scripts | 7 core docs + 12 READMEs
