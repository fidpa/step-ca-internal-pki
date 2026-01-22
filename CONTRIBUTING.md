# Contributing to step-ca Internal PKI

First off, thank you for considering contributing to step-ca-internal-pki!

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [How to Contribute](#how-to-contribute)
- [Development Setup](#development-setup)
- [Style Guidelines](#style-guidelines)
- [Commit Messages](#commit-messages)
- [Pull Request Process](#pull-request-process)

## Code of Conduct

This project adheres to the [Contributor Covenant Code of Conduct](CODE_OF_CONDUCT.md).
By participating, you are expected to uphold this code.

## Getting Started

- Make sure you have a [GitHub account](https://github.com/signup)
- Check existing [issues](https://github.com/fidpa/step-ca-internal-pki/issues) before creating new ones
- Fork the repository on GitHub

## How to Contribute

### Reporting Bugs

Before creating bug reports, please check existing issues.

**Great bug reports include:**
- A clear, descriptive title
- Steps to reproduce the issue
- Expected vs actual behavior
- System information (OS, Docker version, step-ca version)
- Relevant logs or error messages

### Suggesting Features

Feature suggestions are welcome! Please:
- Check if the feature was already requested
- Describe the use case clearly
- Explain why this would benefit users

**Areas where help is appreciated**:
- Additional service integration examples (GitLab, Grafana, Authentik, Keycloak)
- Testing on additional platforms (Alpine Linux, Arch, OpenSUSE, RHEL)
- ACME protocol support (automated certificate requests without manual CSR)
- Web UI for certificate management
- mTLS examples for service-to-service authentication

### Pull Requests

1. Fork the repo and create your branch from `main`
2. Make your changes
3. Test your changes in a local environment
4. Update documentation if needed
5. Submit a pull request

## Development Setup

```bash
# Clone your fork
git clone https://github.com/YOUR_USERNAME/step-ca-internal-pki.git
cd step-ca-internal-pki

# Set up step-ca test environment
mkdir -p /tmp/step-ca-test/{certs,secrets,config,db}
docker compose -f config/step-ca-stack.yml up -d

# Test scripts
./renewal/renew-service-cert.sh --help
./monitoring/cert-exporter.sh --help
```

### Prerequisites

- Docker 20.10+
- Bash 4.0+
- OpenSSL 1.1.1+
- shellcheck (for linting)

## Style Guidelines

### Bash Scripts

- Use `shellcheck` for linting
- Follow `set -uo pipefail` pattern
- Use lowercase for variables, UPPERCASE for constants
- Quote variables: `"$var"` not `$var`
- Include SPDX license header
- Use inline logging with timestamps

Example header:
```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Description: Brief description of script purpose
set -uo pipefail
```

### Documentation

- Use Markdown
- Include TL;DR section (20 words max) for new docs
- Include Table of Contents for docs >100 lines
- Include code examples
- Keep lines under 100 characters

## Commit Messages

Use clear, descriptive commit messages:
```
Add Grafana service integration example

- Created docker-compose.yml for Grafana with TLS
- Added nginx.conf for TLS termination
- Included README.md with setup instructions

Closes #42
```

## Pull Request Process

1. Update README.md if needed
2. Update CHANGELOG.md with your changes
3. PRs require one maintainer approval
4. Squash commits before merging

## Testing

Please test your changes:

1. **Scripts**: Run with `--help` and test basic functionality
2. **Docker configs**: Verify container starts successfully
3. **Documentation**: Check links and formatting

## Questions?

- Open an [Issue](https://github.com/fidpa/step-ca-internal-pki/issues)
- Check [Documentation](docs/)
- See [Troubleshooting](docs/TROUBLESHOOTING.md)

---

Thank you for contributing!
