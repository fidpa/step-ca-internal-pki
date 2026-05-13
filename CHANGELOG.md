# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned
- ACME protocol support for automated certificate requests
- Web UI for certificate management
- Additional service integration examples (GitLab, Grafana, Authentik, Keycloak)
- Grafana dashboard templates for certificate expiry visualization
- mTLS examples for service-to-service authentication

## [1.2.1] - 2026-05-13

### Added — Documentation Clarity

Patch release. Documentation only — no behavioral changes, no script changes.

- **`docs/ARCHITECTURE.md`**: New section **"Why Two Offline Sessions?"** answering the most common first-time question. Explains the forced sequence (Root offline → Intermediate CSR online → Intermediate signing offline), why each step has to live where it does, includes a notary/vault analogy and a renewal-frequency table showing that no further offline sessions are needed for 5 years after initial setup.
- **`docs/SETUP.md`**: New **"Workflow Overview"** section near the top, with an ASCII diagram of the three setup steps making the air-gapped boundaries visible at a glance. TL;DR now states explicitly that two offline sessions are required.

### Changed

- **`docs/README.md`**: `COEXISTENCE.md` added to Quick Navigation and Reading Order (was missing since v1.2.0). Stale Document Status table removed.
- **`docs/ARCHITECTURE.md` / `docs/BACKUP.md` / `docs/CLIENT_TRUST.md`**: TL;DRs translated from German to English for language consistency across the public repo.

## [1.2.0] - 2026-05-13

### Added — Real-World Migration Lessons

Lessons collected while deploying step-ca alongside an existing Let's Encrypt + acme-dns + Tailscale + Active Directory stack. All additions are environment-neutral (no organization-specific identifiers).

- **`scripts/` directory** with three battle-tested scripts (replace previously manual command sequences):
  - `scripts/create-root-ca.sh` — Offline Root CA creation with air-gap verification, decrypt-verify, cross-platform secure-delete (shred/gshred/`rm -P`), and cleanup trap on script abort
  - `scripts/generate-intermediate-csr.sh` — Server-side Intermediate key + CSR generation with ENV-configurable Subject
  - `scripts/sign-intermediate-ca.sh` — USB-driven offline signing with input validation and chain verification
- **`docs/COEXISTENCE.md` (new)** — Four patterns for running step-ca alongside acme-dns (port 53 conflict), Tailscale/WireGuard MagicDNS, Windows Active Directory DNS, and multi-site deployments.

### Fixed — Setup Bug

- **`docs/SETUP.md` Phase 3**: Documented the **`/home/step/secrets/password` file requirement**. step-ca always tries to read this file at startup, even when the intermediate key is unencrypted — without it the container restart-loops with `error reading /home/step/secrets/password: no such file or directory`. Now Phase 3 Step 3 instructs creating an empty (or passphrase-filled) password file. Also added to `docs/TROUBLESHOOTING.md`.

### Added — TROUBLESHOOTING.md

- **DNS / Network Coexistence Issues** (new section):
  - Port 53 conflicts with acme-dns / PiHole / AdGuard / dnsmasq — three resolution strategies
  - dnsmasq breaking Tailscale MagicDNS (via implicit binding to VPN interfaces) — `bind-interfaces` + explicit `listen-address=` fix
  - `stop-dns-rebind` filtering legitimate private IPs from AD-DNS — `rebind-domain-ok=` whitelist
- **Container Restart-Loop with `password` Error** (new troubleshooting entry)
- **Container Health Check Stuck "starting"** (new entry) — explains why the `step ca health` healthcheck stays in "starting" without bootstrapping, plus two solutions

### Added — Other Docs

- **`docs/SETUP.md` Prerequisites**: Brew-PATH note for macOS non-login shells (Cron / SSH) — `step` / `gpg` are not in `$PATH` without prepending `/opt/homebrew/bin`.
- **`docs/BACKUP.md`**: USB-Stick formatting alternative — exFAT (cross-platform Linux ↔ macOS) when LUKS isn't suitable. Documents the **11-character exFAT label limit** and **macOS `._<filename>` AppleDouble sidecars**.
- **`systemd/README.md`**: Hardening section explaining the `ReadWritePaths=` requirement when combining `ProtectSystem=strict` with state-file-writing helpers. Includes drop-in example to avoid silent `Read-only file system` failures.

## [1.1.0] - 2026-01-21

### Added
- **CI/CD Pipeline**: GitHub Actions workflows for automated code quality checks
  - ShellCheck linting for all Bash scripts (monitoring, renewal, revocation, examples)
  - Bash syntax validation
  - Automated releases with release notes generation
- **.shellcheckrc**: ShellCheck configuration for consistent linting
- **CI Badge**: Added to README.md for workflow status visibility
- **Dependency Checks**: All 4 scripts now verify required dependencies at startup
  - `cert-exporter.sh`: openssl (required), docker (optional)
  - `renew-service-cert.sh`: openssl (required)
  - `revoke-cert.sh`: openssl + docker (required), curl (optional)
  - `cert-request-template.sh`: openssl (required)
  - Clear error messages with install instructions on missing dependencies

### Changed
- **Docker Image Version**: Pinned `smallstep/step-ca` to `0.29.0` (was: `latest`)
  - Ensures reproducible builds and prevents unexpected breaking changes
  - Version 0.29.0 is current stable release (2026-01-21)
- **Container Security**: Enabled read-only filesystem for step-ca container
  - Volumes remain writable (SQLite database functionality preserved)
  - Reduces attack surface if container is compromised

## [1.0.1] - 2026-01-20

### Changed
- **CODE_OF_CONDUCT.md**: Updated contact method from email to GitHub Issues for abuse reporting

## [1.0.0] - 2026-01-20

### Added
- **Two-Tier PKI Architecture**: Offline Root CA + Online Intermediate CA (step-ca Docker)
- **Auto-Renewal System**: systemd timers for automatic certificate renewal (30-day threshold)
- **Monitoring Integration**: Prometheus metrics exporter for certificate expiry tracking
- **Service Integration Examples**: Vaultwarden, Nextcloud, Portainer, generic nginx
- **Client Trust Automation**: Cross-platform Root CA installation scripts (Linux, macOS, Windows, Firefox)
- **CRL Support**: Certificate Revocation Lists with HTTP distribution (⚠️ EXPERIMENTAL)
- **Complete Documentation**:
  - [SETUP.md](docs/SETUP.md) - 6-phase setup guide with verification steps
  - [ARCHITECTURE.md](docs/ARCHITECTURE.md) - PKI design decisions and compliance mapping
  - [CLIENT_TRUST.md](docs/CLIENT_TRUST.md) - Cross-platform trust installation (5 OSes, 3 browsers)
  - [BACKUP.md](docs/BACKUP.md) - 3-2-1 backup strategy with disaster recovery scenarios
  - [NGINX_TLS.md](docs/NGINX_TLS.md) - TLS termination best practices (3 security profiles)
  - [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) - Symptom index with 7 common issues

### Features
- **Scripts** (4 total):
  - `renewal/renew-service-cert.sh` - Automated certificate renewal with error handling
  - `monitoring/cert-exporter.sh` - Prometheus textfile collector for expiry metrics
  - `revocation/revoke-cert.sh` - Certificate revocation via step-ca API (⚠️ EXPERIMENTAL)
  - `examples/cert-request-template.sh` - Template for new certificate requests
- **systemd Templates**: Service + Timer templates for auto-renewal
- **Configuration Templates**: step-ca Docker Compose stack, nginx TLS configs
- **Examples**: 4 service integrations (Vaultwarden, Nextcloud, Portainer, generic nginx)

### Security
- **Offline Root CA**: Air-gapped, GPG-encrypted, multiple backups (3-2-1 rule)
- **Short-Lived Certificates**: 90 days validity (step-ca default)
- **Auto-Renewal**: 30-day threshold prevents expiry
- **TLS Best Practices**: Modern, Intermediate, Old profiles (nginx)
- **Monitoring Alerts**: Prometheus alerts 30/7/1 days before expiry

### Production Validation
- **Platforms Tested**: ARM64 (Raspberry Pi 5) + x86_64 (AMD Ryzen 9)
- **Services Integrated**: 6+ production services (Vaultwarden, Nextcloud, Portainer, Dashboard, Grafana, Prometheus)
- **Uptime**: 100% certificate uptime since December 2025
- **Zero Incidents**: No manual renewal required, no browser warnings
- **Multi-Architecture**: Tested on Ubuntu 22.04/24.04, Debian 11/12, Raspberry Pi OS

### Documentation Quality
- **TL;DR Sections**: All docs >100 lines have 20-word summaries
- **Table of Contents**: All docs >300 lines have navigable ToC
- **Quick Reference Tables**: OS-specific commands, symptom index, recovery commands
- **Cross-References**: 40+ bidirectional links across documentation
- **Security Warnings**: 8 warnings with mitigation steps (4 severity levels)
- **Progressive Disclosure**: Optional content in `<details>` tags
- **Quality Score**: 8.5/10 (internal audit, 20.01.2026)

### Known Limitations
- **CRL Support**: ⚠️ EXPERIMENTAL - Revocation scripts not production-tested
- **Platform Support**: Only Linux (macOS/Windows for client trust only)
- **GUI**: No web interface (CLI-only certificate management)
- **ACME Protocol**: Not supported (manual CSR required)
- **HSM Support**: Requires step-ca Enterprise Edition

## [0.9.0] - 2026-01-15

### Added
- Initial development release
- Basic Root CA + Intermediate CA setup
- Manual certificate renewal workflow
- Vaultwarden integration example

### Changed
- Restructured documentation for DIATAXIS framework compliance

### Known Issues
- No auto-renewal automation (manual renewal required)
- Missing Prometheus monitoring integration
- Limited service integration examples (only Vaultwarden)

[Unreleased]: https://github.com/fidpa/step-ca-internal-pki/compare/v1.2.1...HEAD
[1.2.1]: https://github.com/fidpa/step-ca-internal-pki/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/fidpa/step-ca-internal-pki/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/fidpa/step-ca-internal-pki/compare/v1.0.1...v1.1.0
[1.0.1]: https://github.com/fidpa/step-ca-internal-pki/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/fidpa/step-ca-internal-pki/releases/tag/v1.0.0
[0.9.0]: https://github.com/fidpa/step-ca-internal-pki/releases/tag/v0.9.0
