# Configuration Files

Docker Compose stack configuration for step-ca deployment.

## Directory Structure

```
config/
└── step-ca-stack.yml    # Docker Compose file for step-ca container
```

## Files

| File | Description | Customization |
|------|-------------|---------------|
| `step-ca-stack.yml` | step-ca Docker Compose deployment | ⚠️ Edit ports if conflicts |

## Quick Start

```bash
# Create required directories
sudo mkdir -p /opt/step-ca/{certs,secrets,config,db}
sudo chown -R 1000:1000 /opt/step-ca

# Deploy step-ca container
docker compose -f config/step-ca-stack.yml up -d

# Verify
docker ps | grep step-ca
```

## Configuration Reference

### step-ca-stack.yml

| Setting | Default | Description |
|---------|---------|-------------|
| `ports[0]` | `9200:9000` | HTTP-01 ACME challenges |
| `ports[1]` | `9643:9443` | HTTPS Admin API |
| `user` | `1000:1000` | Container UID:GID (match volume owner) |
| `healthcheck.interval` | `30s` | Health check frequency |

### Port Customization

If ports conflict with existing services:

```yaml
# Option 1: Different host ports
ports:
  - "8200:9000"   # Changed from 9200
  - "8643:9443"   # Changed from 9643

# Option 2: Bind to specific IP
ports:
  - "192.168.1.50:9200:9000"
  - "192.168.1.50:9643:9443"
```

## Volume Mounts

| Container Path | Host Path | Purpose |
|----------------|-----------|---------|
| `/home/step/config` | `/opt/step-ca/config` | CA configuration (ca.json) |
| `/home/step/db` | `/opt/step-ca/db` | Certificate database |
| `/home/step/certs` | `/opt/step-ca/certs` | CA certificates |
| `/home/step/secrets` | `/opt/step-ca/secrets` | Private keys |

**Important**: Create these directories and configure `ca.json` before first start. See [docs/SETUP.md](../docs/SETUP.md) for complete instructions.

## See Also

- [← Back to Root](../README.md)
- [Setup Guide](../docs/SETUP.md)
- [Architecture](../docs/ARCHITECTURE.md)
