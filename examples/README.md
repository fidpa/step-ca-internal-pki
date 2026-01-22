# Examples

Service integration examples demonstrating step-ca TLS configuration.

## Available Examples

| Example | Complexity | Description |
|---------|------------|-------------|
| [generic/](generic/) | ⭐ Beginner | nginx reverse proxy template |
| [vaultwarden/](vaultwarden/) | ⭐⭐ Intermediate | Password manager with TLS |
| [nextcloud/](nextcloud/) | ⭐⭐ Intermediate | Cloud storage with TLS |
| [portainer/](portainer/) | ⭐⭐ Intermediate | Docker management with TLS |

## Directory Structure

```
examples/
├── cert-request-template.sh    # Certificate request template script
├── generic/                    # Generic nginx reverse proxy
│   ├── docker-compose.yml
│   ├── nginx.conf
│   └── README.md
├── vaultwarden/                # Vaultwarden (Bitwarden-compatible)
│   ├── docker-compose.yml
│   ├── nginx.conf
│   └── README.md
├── nextcloud/                  # Nextcloud file sync
│   ├── docker-compose.yml
│   ├── nginx.conf
│   └── README.md
└── portainer/                  # Docker management UI
    ├── docker-compose.yml
    ├── nginx.conf
    └── README.md
```

## Quick Start

### Using cert-request-template.sh

```bash
# 1. Copy and customize the template
cp cert-request-template.sh /tmp/myservice-cert.sh

# 2. Edit DNS_SANS and IP_SANS for your service
nano /tmp/myservice-cert.sh

# 3. Run as root
sudo /tmp/myservice-cert.sh

# Output: /etc/ssl/step-ca/myservice.{crt,key,fullchain.crt}
```

### Using Service Examples

```bash
# Choose an example
cd examples/vaultwarden/

# Read the README
cat README.md

# Request certificate first
sudo ../cert-request-template.sh  # Edit DNS_SANS first!

# Deploy
docker compose up -d
```

## Example Descriptions

### generic/

Minimal nginx reverse proxy with TLS termination.

**Best for**: New services, learning, customization base

**Includes**:
- `docker-compose.yml` - nginx + backend service template
- `nginx.conf` - TLS configuration with modern ciphers
- `README.md` - Customization instructions

### vaultwarden/

Vaultwarden (Bitwarden-compatible) password manager with TLS.

**Best for**: Self-hosted password management

**Features**:
- Full TLS termination
- Security headers
- WebSocket support for real-time sync

### nextcloud/

Nextcloud file sync and collaboration with TLS.

**Best for**: Self-hosted cloud storage

**Features**:
- Large file upload support
- CalDAV/CardDAV paths
- Security headers

### portainer/

Portainer Docker management UI with TLS.

**Best for**: Docker container management

**Features**:
- WebSocket support for container console
- API endpoint protection

## Each Example Includes

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Service container configuration |
| `nginx.conf` | TLS termination and proxy settings |
| `README.md` | Service-specific setup instructions |

## Certificate Paths

All examples expect certificates at:

| File | Path | Description |
|------|------|-------------|
| Certificate | `/etc/ssl/step-ca/<service>.crt` | Server certificate |
| Private Key | `/etc/ssl/step-ca/<service>.key` | Private key |
| Fullchain | `/etc/ssl/step-ca/<service>-fullchain.crt` | Cert + Intermediate CA |

## See Also

- [← Back to Root](../README.md)
- [Setup Guide](../docs/SETUP.md)
- [nginx TLS Guide](../docs/NGINX_TLS.md)
- [Client Trust](../docs/CLIENT_TRUST.md)
