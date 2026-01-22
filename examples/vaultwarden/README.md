# Vaultwarden with step-ca TLS

Deploy Vaultwarden (Bitwarden-compatible password manager) with TLS termination using step-ca certificates.

---

## Overview

This example demonstrates:
- Vaultwarden container with nginx TLS termination
- step-ca certificates for HTTPS
- WebSocket support (for real-time sync)
- Secure credential storage for internal services

---

## Prerequisites

- Docker & Docker Compose installed
- step-ca Root CA certificate installed on client machines (see [CLIENT_TRUST.md](../../docs/CLIENT_TRUST.md))
- step-ca certificate issued for `vaultwarden.internal` (see below)

> **Port Conflict Warning**: This example binds to ports `80:80` and `443:443`. If you have other services (e.g., Nextcloud, Portainer) on the same host, you must either:
> - Use a shared reverse proxy (Traefik, nginx-proxy) for all services
> - Change port mappings in `docker-compose.yml` (e.g., `8443:443`)
> - Run services on separate hosts

---

## Certificate Request

Generate certificate for Vaultwarden:

```bash
# Copy template
sudo cp ../../examples/cert-request-template.sh /tmp/vaultwarden-cert-request.sh

# Edit DNS SANs and IP SANs
sudo nano /tmp/vaultwarden-cert-request.sh
# Set:
# declare -a DNS_SANS=(
#     "vaultwarden.internal"
#     "vault.internal"
# )
# declare -a IP_SANS=(
#     "192.168.1.100"  # Your server IP
# )
# SERVICE_NAME="vaultwarden"

# Run as root
sudo /tmp/vaultwarden-cert-request.sh

# Verify certificates created
ls -l /etc/ssl/step-ca/vaultwarden*
# Expected:
# vaultwarden.crt
# vaultwarden.key
# vaultwarden-fullchain.crt
```

---

## Deployment

### 1. Clone Configuration

```bash
# Create directory
mkdir -p ~/vaultwarden-step-ca
cd ~/vaultwarden-step-ca

# Copy files from this example
cp /path/to/step-ca-internal-pki/examples/vaultwarden/* .
```

### 2. Configure Environment

Edit `docker-compose.yml`:

```yaml
services:
  vaultwarden:
    environment:
      - ADMIN_TOKEN=changeme  # <- CHANGE THIS (generate: openssl rand -base64 48)
      - SIGNUPS_ALLOWED=false  # Disable public signups after initial setup
      - DOMAIN=https://vaultwarden.internal
```

**Generate secure admin token**:

```bash
openssl rand -base64 48
# Output: xK2m7n9p...  <- Use this as ADMIN_TOKEN
```

### 3. Start Services

```bash
# Start Vaultwarden + nginx
docker compose up -d

# Check logs
docker compose logs -f

# Verify containers running
docker compose ps
# Expected:
# NAME                 STATUS
# vaultwarden          Up
# vaultwarden-nginx    Up
```

### 4. Initial Setup

Open browser: `https://vaultwarden.internal`

1. **Create account** (first user becomes admin)
   - Email: `admin@example.com`
   - Password: **Strong master password** (16+ characters)

2. **Access Admin Panel** (optional):
   - URL: `https://vaultwarden.internal/admin`
   - Token: Your `ADMIN_TOKEN` from docker-compose.yml

3. **Disable signups** after creating accounts:
   - Edit `docker-compose.yml`: `SIGNUPS_ALLOWED=false`
   - Restart: `docker compose up -d`

---

## Verification

### HTTPS Test

```bash
# Test TLS connection
curl -v https://vaultwarden.internal

# Expected:
# * SSL connection using TLSv1.3 / TLS_AES_256_GCM_SHA384
# * Server certificate:
# *  subject: CN=vaultwarden
# *  issuer: CN=Your Intermediate CA
# * SSL certificate verify ok.
```

> **Note**: CN equals SERVICE_NAME (short name), SANs contain the FQDNs. Modern TLS clients validate SANs, not CN.

### WebSocket Test

Open browser DevTools -> **Network** tab -> Filter: **WS**

Login to Vaultwarden and check for WebSocket connection:

```
Status: 101 Switching Protocols
Upgrade: websocket
```

---

## Certificate Renewal

### Auto-Renewal Setup

Create systemd service for Vaultwarden certificate renewal:

**Service** (`/etc/systemd/system/step-ca-renew-vaultwarden.service`):

```ini
[Unit]
Description=Renew Vaultwarden step-ca Certificate
After=network.target

[Service]
Type=oneshot
Environment="SERVICE_NAME=vaultwarden"
Environment="STEP_CA_HOME=/opt/step-ca"
Environment="STEP_CA_CERT_DIR=/etc/ssl/step-ca"
Environment="RENEWAL_THRESHOLD=30"
Environment="SERVICE_RELOAD_CMD=docker exec vaultwarden-nginx nginx -s reload"
ExecStart=/usr/local/bin/renew-service-cert.sh
User=root
```

**Timer** (`/etc/systemd/system/step-ca-renew-vaultwarden.timer`):

```ini
[Unit]
Description=Renew Vaultwarden Certificate Timer

[Timer]
OnCalendar=*-*-* 04:00:00
Persistent=true

[Install]
WantedBy=timers.target
```

Enable timer:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now step-ca-renew-vaultwarden.timer
```

---

## Monitoring

### Prometheus Metrics

Export Vaultwarden certificate expiry to Prometheus:

```bash
# Create exporter service
sudo tee /etc/systemd/system/step-ca-exporter-vaultwarden.service << 'EOF'
[Unit]
Description=step-ca Vaultwarden Certificate Exporter

[Service]
Type=oneshot
Environment="SERVICE_NAME=vaultwarden"
Environment="OUTPUT_FILE=/var/lib/node_exporter/textfile_collector/step_ca_vaultwarden.prom"
ExecStart=/usr/local/bin/cert-exporter.sh
User=root
EOF

# Create timer
sudo tee /etc/systemd/system/step-ca-exporter-vaultwarden.timer << 'EOF'
[Unit]
Description=step-ca Vaultwarden Certificate Exporter Timer

[Timer]
OnCalendar=hourly
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Enable
sudo systemctl daemon-reload
sudo systemctl enable --now step-ca-exporter-vaultwarden.timer
```

---

## Backup

### Vaultwarden Data Backup

**Important**: Vaultwarden stores all data in SQLite database (`/data/db.sqlite3`).

```bash
# Backup Vaultwarden data
docker run --rm \
    -v vaultwarden_data:/data \
    -v $(pwd):/backup \
    alpine tar czf /backup/vaultwarden-backup-$(date +%Y%m%d).tar.gz /data

# Restore
docker compose down
docker run --rm \
    -v vaultwarden_data:/data \
    -v $(pwd):/backup \
    alpine tar xzf /backup/vaultwarden-backup-YYYYMMDD.tar.gz -C /
docker compose up -d
```

### Automated Backup Script

```bash
#!/bin/bash
# /usr/local/bin/backup-vaultwarden.sh

BACKUP_DIR="/opt/backups/vaultwarden"
RETENTION_DAYS=30

mkdir -p "$BACKUP_DIR"

# Create backup
docker run --rm \
    -v vaultwarden_data:/data \
    -v "$BACKUP_DIR":/backup \
    alpine tar czf "/backup/vaultwarden-$(date +%Y%m%d-%H%M%S).tar.gz" /data

# Remove old backups
find "$BACKUP_DIR" -name "vaultwarden-*.tar.gz" -mtime +$RETENTION_DAYS -delete
```

---

## Troubleshooting

### "Invalid credentials" After Restore

**Cause**: Browser cached old session.

**Fix**: Clear browser cache or use incognito mode.

### WebSocket Connection Fails (Sync Issues)

**Cause**: nginx not configured for WebSocket upgrade.

**Fix**: Already configured in provided `nginx.conf`:

```nginx
location /notifications/hub {
    proxy_pass http://vaultwarden:3012;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
}
```

Verify:

```bash
docker compose logs nginx | grep -i websocket
```

### Certificate Not Trusted

**Cause**: Root CA not installed on client machine.

**Fix**: Install Root CA (see [CLIENT_TRUST.md](../../docs/CLIENT_TRUST.md)).

### Admin Panel Returns 404

**Cause**: `ADMIN_TOKEN` not set or container restarted.

**Fix**: Ensure `ADMIN_TOKEN` is set in `docker-compose.yml`:

```yaml
environment:
  - ADMIN_TOKEN=your-secure-token
```

Restart:

```bash
docker compose up -d
```

---

## Security Best Practices

### Disable Public Signups

After creating necessary accounts:

```yaml
environment:
  - SIGNUPS_ALLOWED=false
```

### Use Strong Admin Token

Generate cryptographically secure token:

```bash
openssl rand -base64 48
```

### Enable Two-Factor Authentication

1. Login to Vaultwarden
2. **Settings** -> **Two-step Login**
3. Enable **Authenticator App** (TOTP)

### Regular Backups

- Backup **before** any upgrade
- Test restore procedure periodically
- Store backups off-site (3-2-1 rule)

---

## Further Reading

- [Vaultwarden Wiki](https://github.com/dani-garcia/vaultwarden/wiki) - Official documentation
- [Vaultwarden Docker](https://hub.docker.com/r/vaultwarden/server) - Docker Hub
- [NGINX_TLS.md](../../docs/NGINX_TLS.md) - TLS configuration details
- [SETUP.md](../../docs/SETUP.md) - step-ca setup guide
