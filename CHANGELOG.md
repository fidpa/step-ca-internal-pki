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

[Unreleased]: https://github.com/fidpa/step-ca-internal-pki/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/fidpa/step-ca-internal-pki/compare/v1.0.1...v1.1.0
[1.0.1]: https://github.com/fidpa/step-ca-internal-pki/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/fidpa/step-ca-internal-pki/releases/tag/v1.0.0
[0.9.0]: https://github.com/fidpa/step-ca-internal-pki/releases/tag/v0.9.0
