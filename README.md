# step-ca Internal PKI

![Version](https://img.shields.io/badge/version-1.3.9-blue)
![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)
![Platform](https://img.shields.io/badge/platform-Linux-lightgrey?logo=linux)
![Bash](https://img.shields.io/badge/Bash-4.0%2B-blue?logo=gnu-bash)
![Docker](https://img.shields.io/badge/Docker-20.10%2B-blue?logo=docker)
![CI](https://github.com/fidpa/step-ca-internal-pki/actions/workflows/lint.yml/badge.svg)
![Status](https://img.shields.io/badge/status-production-brightgreen)
![step-ca](https://img.shields.io/badge/step--ca-0.29.0-orange)
![Last Commit](https://img.shields.io/github/last-commit/fidpa/step-ca-internal-pki)

A two-tier internal PKI built on [Smallstep's step-ca](https://smallstep.com/docs/step-ca):
scripts, documentation and service integration examples for internal HTTPS without
browser warnings.

Self-hosted services usually answer on an IP address (`https://192.168.1.50:8443`),
and every browser flags them. Let's Encrypt cannot help, because internal names have
no public DNS, and hand-rolled OpenSSL certificates stop scaling at the third service.
This repository is the setup behind six internal services, extracted with its renewal
timers, monitoring and client trust distribution intact.

## Features

- **Two-tier PKI** - offline Root CA signs an online Intermediate CA; the Root key never reaches the production host
- **Air-gap verification** - `scripts/create-root-ca.sh` probes 8.8.8.8, 1.1.1.1 and an HTTPS endpoint, and aborts if any of them answers
- **Offline signing workflow** - Intermediate key and CSR on the server, signature on the air-gapped machine, transport over USB
- **Auto-renewal** - systemd timers, renewal below 30 days left (`RENEWAL_THRESHOLD`), `--force` to re-issue with new SANs
- **Failure notifications** - `OnFailure=` hook template: a silently failing nightly renewal reaches you instead of surfacing as a browser warning weeks later
- **Prometheus monitoring** - certificate expiry metrics plus alert rules at 30, 7 and 1 day
- **Service integration** - working examples for Vaultwarden, Nextcloud, Portainer and a generic nginx proxy
- **Client trust** - Root CA installation for macOS, Linux and Windows ([`docs/CLIENT_TRUST.md`](docs/CLIENT_TRUST.md))
- **Atomic deployment** - certificates are written as `.new` files, verified, then moved into place; `flock` serialises concurrent renewals
- **NTP monitoring** - time sync validation, because a skewed clock invalidates every certificate
- **Coexistence patterns** - documented integration with acme-dns, Tailscale/WireGuard MagicDNS and Active Directory DNS ([`docs/COEXISTENCE.md`](docs/COEXISTENCE.md))
- **Experimental: CRL support** - see [Known Limitations](#known-limitations)

## Known Limitations

> **IMPORTANT**: The default workflow signs service certificates with OpenSSL
> directly, using the Intermediate CA key. That has consequences:
>
> - **Revocation does not work.** Certificates cannot be revoked via `step ca revoke`.
> - **Certificates are not tracked** in step-ca's database (BadgerDB).
> - **The CRL tooling in `revocation/` is experimental** and does not close this gap.
>   Where the feature list and the security section mention CRLs, they describe the
>   architecture, not a working revocation path.
> - **Mitigation**: 90-day certificates keep the exposure window short. A key that
>   leaks is still valid until it expires; plan for that, or move issuance to
>   step-ca provisioners.
>
> [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md#-critical-revocation-limitations)
> has the details and the workarounds.

## Quick Start

```bash
git clone https://github.com/fidpa/step-ca-internal-pki.git
cd step-ca-internal-pki
```

The full walkthrough is [docs/SETUP.md](docs/SETUP.md); the steps below are the
short form.

### Prerequisites

**Production server:**
- Docker & Docker Compose
- OpenSSL
- Root access for certificate deployment

**Air-gapped machine (Root CA + Intermediate signing):**
- `step` CLI >= 0.25 - `brew install step` (macOS) or [smallstep.com/docs](https://smallstep.com/docs/step-cli/installation)
- `gpg` >= 2.2 - `brew install gnupg` / `apt install gnupg`
- `coreutils` (macOS only, for `gshred`) - `brew install coreutils`

> **macOS Brew-PATH gotcha**: Non-login SSH sessions and cron jobs don't auto-source
> `~/.zshrc`. The scripts prepend `/opt/homebrew/bin:/usr/local/bin` to `$PATH`
> themselves.

### 1. Create Root CA (offline, on the air-gapped machine)

```bash
# Wi-Fi off, Ethernet unplugged, VPN disconnected.
# The script aborts if it reaches the network.
CA_NAME="My Internal Root CA 2026" ./scripts/create-root-ca.sh

# Output: ~/.ca-creation-YYYYMMDD-HHMMSS/
#   - root_ca.crt           -> copy to production server
#   - root_ca.key.gpg       -> keep on USB stick in safe (3-2-1 rule)
#   - checksums.sha256
```

Defaults: ECDSA, 10 years validity (`CA_VALIDITY_HOURS=87600`).

### 2. Generate Intermediate CSR (on the production server)

```bash
INTERMEDIATE_CN="My Internal Intermediate CA 2026" \
INTERMEDIATE_O="My Org" \
INTERMEDIATE_C="DE" \
  ./scripts/generate-intermediate-csr.sh

# Output:
#   /opt/step-ca/secrets/intermediate_ca_key   (ECDSA P-256, mode 600, owner 1000:1000)
#   /tmp/intermediate_ca.csr                   -> transport to air-gapped machine
```

### 3. Sign the Intermediate (back on the air-gapped machine)

```bash
# Insert USB with root_ca.crt, root_ca.key.gpg, intermediate_ca.csr
USB_MOUNT="/Volumes/USB" ./scripts/sign-intermediate-ca.sh

# Written back to the USB stick:
#   intermediate_ca.crt            -> transport to production server
#   intermediate-checksums.sha256
```

Default validity is 5 years (`INTERMEDIATE_VALIDITY=43800h`), with
`basicConstraints=CA:TRUE,pathlen:0`.

### 4. Deploy step-ca

```bash
# Install signed intermediate + create empty password file (REQUIRED, see docs/SETUP.md)
sudo install -o 1000 -g 1000 -m 644 intermediate_ca.crt /opt/step-ca/certs/
sudo install -o 1000 -g 1000 -m 600 /dev/null /opt/step-ca/secrets/password

# Trust Root CA on the server
sudo install -m 644 root_ca.crt /usr/local/share/ca-certificates/my-internal-root-ca.crt
sudo update-ca-certificates

# Deploy container. The image carries no DOCKER_STEPCA_INIT_* variables:
# /opt/step-ca/config/ca.json must exist before the first start (docs/SETUP.md, phase 3).
sudo install -m 644 config/step-ca-stack.yml /opt/step-ca/
cd /opt/step-ca && docker compose -f step-ca-stack.yml up -d
curl -k https://localhost:9643/health   # -> {"status":"ok"}
```

### 5. Request a service certificate

```bash
cp examples/cert-request-template.sh /tmp/myservice-cert-request.sh
# Edit SERVICE_NAME, DNS_SANS and IP_SANS

sudo /tmp/myservice-cert-request.sh
# Output: /etc/ssl/step-ca/myservice.{crt,key} + myservice-fullchain.crt
```

Certificates are valid for 90 days (`CERT_VALIDITY_DAYS` in the template).

### 6. Configure auto-renewal

```bash
# Naming convention: step-ca-renew-<service>
cp systemd/step-ca-renew.service.template /etc/systemd/system/step-ca-renew-myservice.service
cp systemd/step-ca-renew.timer.template /etc/systemd/system/step-ca-renew-myservice.timer

# Set SERVICE_NAME and SERVICE_RELOAD_CMD in the service file
sudo systemctl daemon-reload
sudo systemctl enable --now step-ca-renew-myservice.timer
```

### 7. Set up monitoring (optional)

```bash
cp monitoring/cert-exporter.sh /usr/local/bin/
chmod +x /usr/local/bin/cert-exporter.sh
# Wire it into the Prometheus textfile collector: see monitoring/README.md
```

## When to Use This

**Good fit:**
- Homelab and self-hosted services that need trusted HTTPS without public DNS
- SMB internal PKI below roughly 100 devices, where enterprise PKI has no budget
- Docker stacks that cannot use Let's Encrypt because they have no public domain
- Local k3s/k8s clusters and IoT devices (Raspberry Pi, ESP32) speaking TLS
- Learning PKI hands-on: Certificate Authority, chain of trust, mTLS

**Not recommended for:**
- **Public-facing services** - Let's Encrypt is free, automated, and trusted by every browser out of the box
- **Enterprise scale (500+ devices)** - HashiCorp Vault or a commercial PKI brings the lifecycle tooling this repo deliberately keeps small
- **Mobile apps** needing publicly trusted certificates - a private Root CA cannot be installed on other people's phones
- **HSM-backed keys** - that requires step-ca Enterprise Edition
- **Anything that depends on revocation** - see [Known Limitations](#known-limitations)

## Key Concepts

### The two-tier architecture

```
Root CA (offline)
    | signs
Intermediate CA (online, step-ca)
    | issues
Service certificates (auto-renewed)
```

The Root CA key is generated on an air-gapped machine, GPG-encrypted, and never
copied to the server; `create-root-ca.sh` refuses to run while the machine has
network. What lives in production is the Intermediate key, and that changes what a
break-in costs: if the Intermediate is compromised, you re-issue the Intermediate and
the service certificates, while every client keeps trusting the same Root. If the Root
were online and fell, every client would have to install a new trust anchor by hand.

Two tiers are also what PCI DSS, SOC 2 and ISO 27001 audits expect of an internal CA.
That is a statement about the architecture, not a certification of this repository:
nothing here has been audited.

The price is one extra offline session every five years, when the Intermediate needs
a new signature. [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) works through the
alternatives, including why three tiers are not worth it here.

### The offline Root CA in practice

1. **Air-gapped machine**: a spare laptop or Raspberry Pi with radios off and cable unplugged. The script checks by probing 8.8.8.8, 1.1.1.1 and an HTTPS endpoint before it touches a key.
2. **Encrypted at rest**: the private key leaves the script only as `root_ca.key.gpg` (symmetric GPG), and the plaintext key is wiped with `shred`, `gshred` or `rm -P`.
3. **Multiple backups**: 3-2-1 rule, three copies on two media types with one offsite ([docs/BACKUP.md](docs/BACKUP.md)).
4. **Physical security**: the USB stick belongs in a safe, not in a drawer.

## Repository Structure

```
step-ca-internal-pki/
|-- config/               # Docker Compose stack configuration
|   |-- README.md         # Configuration guide
|   `-- step-ca-stack.yml # step-ca container deployment (image pinned to 0.29.0)
|-- scripts/              # PKI lifecycle scripts
|   |-- README.md         # Scripts overview + workflow diagram
|   |-- create-root-ca.sh            # Offline Root CA (air-gap verified)
|   |-- generate-intermediate-csr.sh # Server-side Intermediate key + CSR
|   `-- sign-intermediate-ca.sh      # Offline Intermediate signing
|-- docs/                 # Documentation (7 guides)
|   |-- README.md         # Navigation hub
|   |-- SETUP.md          # Installation guide
|   |-- ARCHITECTURE.md   # PKI design decisions
|   |-- CLIENT_TRUST.md   # Cross-platform Root CA installation
|   |-- NGINX_TLS.md      # nginx TLS termination
|   |-- COEXISTENCE.md    # Integration with acme-dns, Tailscale, AD-DNS
|   |-- BACKUP.md         # 3-2-1 backup strategy
|   `-- TROUBLESHOOTING.md# Common issues + DNS coexistence pitfalls
|-- examples/             # Service integration examples
|   |-- README.md         # Examples overview
|   |-- cert-request-template.sh
|   |-- vaultwarden/      # Password manager
|   |-- nextcloud/        # Cloud storage
|   |-- portainer/        # Docker management
|   `-- generic/          # nginx reverse proxy
|-- monitoring/           # Prometheus metrics exporters
|   |-- README.md         # Monitoring guide
|   |-- cert-exporter.sh  # Certificate expiry metrics
|   |-- check-time-sync.sh # NTP time synchronization validation
|   |-- prometheus-rules.yml    # Alert rules (expiry, staleness, container)
|   `-- grafana-dashboard.json  # Certificate monitoring dashboard
|-- renewal/              # Auto-renewal
|   |-- README.md         # Renewal workflow
|   `-- renew-service-cert.sh   # threshold + --force, flock, pubkey match check
|-- revocation/           # Certificate revocation (EXPERIMENTAL)
|   |-- README.md         # Revocation guide
|   `-- revoke-cert.sh
|-- systemd/              # systemd units and templates
|   |-- README.md         # Timer setup + ReadWritePaths hardening
|   |-- step-ca-renew.service.template
|   |-- step-ca-renew.timer.template
|   |-- step-ca-renew-failure-notify.service.template  # OnFailure hook
|   |-- check-time-sync.service
|   `-- check-time-sync.timer
|-- CONTRIBUTING.md       # Contribution guidelines
|-- CODE_OF_CONDUCT.md    # Community standards
|-- SECURITY.md           # Security policy
|-- CHANGELOG.md          # Version history
`-- LICENSE               # MIT License
```

## Component Overview

| Component | Purpose | Technology |
|-----------|---------|------------|
| `scripts/` | Root CA creation, Intermediate CSR and offline signing | Bash + step CLI + OpenSSL |
| `renewal/` | Auto-renewal of service certificates below the 30-day threshold | Bash + systemd timers |
| `monitoring/` | Certificate expiry metrics and NTP validation | Bash + node_exporter textfile collector |
| `revocation/` | CRL generation and distribution (EXPERIMENTAL, see Known Limitations) | OpenSSL + Bash |
| `examples/` | Request template plus four service integrations | Bash + docker-compose + nginx |
| `systemd/` | Service and timer templates for renewal and time sync | systemd unit files |
| `config/` | step-ca Docker Compose stack | YAML |
| `docs/` | Architecture, setup, client trust, coexistence, backup, troubleshooting | Markdown |

## Service Integration Examples

- **Vaultwarden** - password manager (`examples/vaultwarden/`)
- **Nextcloud** - cloud storage (`examples/nextcloud/`)
- **Portainer** - Docker management (`examples/portainer/`)
- **Generic** - nginx reverse proxy template (`examples/generic/`)

Each one ships a `docker-compose.yml`, an `nginx.conf` for TLS termination, and a
`README.md` with the setup steps.

## Documentation

| Document | Description |
|----------|-------------|
| [SETUP.md](docs/SETUP.md) | Complete installation guide, six phases |
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | PKI design decisions |
| [CLIENT_TRUST.md](docs/CLIENT_TRUST.md) | Cross-platform Root CA installation |
| [COEXISTENCE.md](docs/COEXISTENCE.md) | Integration with acme-dns / Tailscale / AD-DNS |
| [BACKUP.md](docs/BACKUP.md) | 3-2-1 backup strategy |
| [NGINX_TLS.md](docs/NGINX_TLS.md) | nginx TLS termination |
| [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Common issues |

[docs/README.md](docs/README.md) has the reading order and says which guide is for whom.

## vs. Alternatives

| Solution | Strengths | Weaknesses |
|----------|-----------|------------|
| **Let's Encrypt** | Free, automated, trusted everywhere | Public domains only |
| **OpenSSL by hand** | Full control | No automation, no renewal, no inventory |
| **step-ca official docs** | Authoritative on the CA itself | Leaves multi-service operation to you |
| **HashiCorp Vault** | Full lifecycle, revocation, HSM | Another stateful service to run and back up |
| **Commercial PKI** | Support, GUI, audit trail | Cost, and overkill below a few hundred devices |
| **This repo** | Renewal timers, monitoring, client trust, four worked integrations | step-ca only, no GUI, revocation not functional |

What it adds over the upstream documentation is the operational half: renewal on a
timer with a failure hook, Prometheus metrics and alert rules, Root CA distribution
across three client platforms, and documented coexistence with acme-dns, Tailscale
MagicDNS and AD DNS.

## Requirements

- **OS**: Linux (tested on Ubuntu 22.04+, Debian 11+)
- **Docker**: 20.10+
- **OpenSSL**: 1.1.1+
- **Bash**: 4.0+

## Compatibility

**Fully supported**:
- Ubuntu 22.04 LTS, 24.04 LTS
- Debian 11 (Bullseye), 12 (Bookworm)
- Raspberry Pi OS (64-bit)

**Should work** (untested):
- Other systemd-based distros with Docker support
- macOS (client trust and offline signing scripts only)
- WSL2 (Windows Subsystem for Linux)

**Not supported**:
- Non-systemd init systems (the renewal timers have no fallback)
- HSM-backed CA keys (step-ca Enterprise Edition)

## Security

- **Offline Root CA** - air-gapped creation, GPG-encrypted at rest, plaintext key wiped
- **90-day certificates** - short lifetimes are the mitigation for missing revocation, not a bonus
- **Renewal at 30 days left** - with an `OnFailure=` hook, so failures are noticed
- **Hardened units** - `ProtectSystem=strict`, `NoNewPrivileges`, `ReadWritePaths` scoped to the cert directory
- **Container hardening** - `read_only: true`, non-root user 1000:1000, read-only config and secret mounts
- **Monitoring** - Prometheus alerts at 30, 7 and 1 day for service certs, 90 days for the Intermediate, 365 for the Root

Where these guarantees end is documented: [Known Limitations](#known-limitations)
for revocation, [SECURITY.md](SECURITY.md) for the reporting process.

## In Production

Running since December 2025 on two hosts: a Raspberry Pi 5 router (ARM64) and an
x86_64 NAS, together serving six internal services (Vaultwarden, Nextcloud,
Portainer, a dashboard, Grafana, Prometheus). Across that time no certificate has
expired and no renewal has needed a manual step, which is a statement about two
machines with daily timers, not a benchmark.

The number worth knowing is 90 and 30: certificates live 90 days, renewal starts at
30 days left. That leaves a 60-day window in which a broken renewal can be noticed
and fixed before anything expires, and the `OnFailure=` hook exists so the window is
actually used.

## Contributing

Test changes locally, keep the existing script conventions (SPDX headers, inline
logging, `set -euo pipefail`), update the affected documentation in the same commit,
and describe what you changed in the pull request. Details in
[CONTRIBUTING.md](CONTRIBUTING.md).

Help is especially welcome on: additional service integrations (GitLab, Grafana,
Authentik, Keycloak), testing on Alpine, Arch, openSUSE and RHEL, ACME support so
certificate requests skip the manual CSR, and mTLS examples for service-to-service
authentication.

## License

MIT License - see [LICENSE](LICENSE)

## Author

Marc Allgeier ([@fidpa](https://github.com/fidpa))

I built this after months of clicking through browser warnings on my own services.
The official step-ca documentation explains the CA well; what it left to me was
everything around it, and that is what this repository is.

## See Also

- [ubuntu-server-security](https://github.com/fidpa/ubuntu-server-security) - 14 security hardening components along the CIS Benchmark
- [bash-production-toolkit](https://github.com/fidpa/bash-production-toolkit) - Bash libraries for logging, security and monitoring
- [linux-monitoring-templates](https://github.com/fidpa/linux-monitoring-templates) - Bash/Python monitoring script templates

## Support

- **Issues**: [GitHub Issues](https://github.com/fidpa/step-ca-internal-pki/issues)
- **Documentation**: [docs/](docs/)
- **step-ca Docs**: https://smallstep.com/docs/step-ca

## Credits

Built on [Smallstep step-ca](https://github.com/smallstep/certificates), a
lightweight open-source Certificate Authority.

---

**Production-tested since December 2025** | v1.3.9 (August 2026) | 8 scripts | 7 core docs + 12 READMEs
