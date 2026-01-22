# Nextcloud with step-ca TLS

Deploy Nextcloud with TLS termination using step-ca certificates.

---

## Overview

This example demonstrates:
- Nextcloud container with nginx TLS termination
- MariaDB database backend
- step-ca certificates for HTTPS
- WebDAV, CalDAV, CardDAV support

---

## Prerequisites

- Docker & Docker Compose installed
- step-ca Root CA certificate installed on client machines (see [CLIENT_TRUST.md](../../docs/CLIENT_TRUST.md))
- step-ca certificate issued for `nextcloud.internal` (see below)

> **Port Conflict Warning**: This example binds to ports `80:80` and `443:443`. If you have other services (e.g., Portainer, Vaultwarden) on the same host, you must either:
> - Use a shared reverse proxy (Traefik, nginx-proxy) for all services
> - Change port mappings in `docker-compose.yml` (e.g., `8443:443`)
> - Run services on separate hosts

---

## Certificate Request

Generate certificate for Nextcloud:

```bash
# Copy template
sudo cp ../../examples/cert-request-template.sh /tmp/nextcloud-cert-request.sh

# Edit DNS SANs and IP SANs
sudo nano /tmp/nextcloud-cert-request.sh
# Set:
# declare -a DNS_SANS=(
#     "nextcloud.internal"
#     "cloud.internal"
# )
# declare -a IP_SANS=(
#     "192.168.1.100"  # Your server IP
# )
# SERVICE_NAME="nextcloud"

# Run as root
sudo /tmp/nextcloud-cert-request.sh

# Verify certificates created
ls -l /etc/ssl/step-ca/nextcloud*
# Expected:
# nextcloud.crt
# nextcloud.key
# nextcloud-fullchain.crt
```

---

## Deployment

### 1. Clone Configuration

```bash
# Create directory
mkdir -p ~/nextcloud-step-ca
cd ~/nextcloud-step-ca

# Copy files from this example
cp /path/to/step-ca-internal-pki/examples/nextcloud/* .
```

### 2. Configure Environment

Edit `docker-compose.yml`:

```yaml
services:
  nextcloud:
    environment:
      - MYSQL_DATABASE=nextcloud
      - MYSQL_USER=nextcloud
      - MYSQL_PASSWORD=changeme  # ← CHANGE THIS
      - MYSQL_HOST=db
      - NEXTCLOUD_ADMIN_USER=admin
      - NEXTCLOUD_ADMIN_PASSWORD=changeme  # ← CHANGE THIS
      - NEXTCLOUD_TRUSTED_DOMAINS=nextcloud.internal 192.168.1.100
      - OVERWRITEPROTOCOL=https
      - OVERWRITEHOST=nextcloud.internal

  db:
    environment:
      - MYSQL_ROOT_PASSWORD=changeme  # ← CHANGE THIS
      - MYSQL_PASSWORD=changeme  # ← MUST MATCH NEXTCLOUD PASSWORD
```

### 3. Start Services

```bash
# Start Nextcloud + MariaDB + nginx
docker compose up -d

# Check logs
docker compose logs -f

# Verify containers running
docker compose ps
# Expected:
# NAME                 STATUS
# nextcloud            Up
# nextcloud-db         Up
# nextcloud-nginx      Up
```

### 4. Verify HTTPS

```bash
# Test TLS connection
curl -v https://nextcloud.internal

# Expected:
# * SSL connection using TLSv1.3 / TLS_AES_256_GCM_SHA384
# * Server certificate:
# *  subject: CN=nextcloud
# *  issuer: CN=Your Intermediate CA
# * SSL certificate verify ok.
```

> **Note**: CN equals SERVICE_NAME (short name), SANs contain the FQDNs. Modern TLS clients validate SANs, not CN.

Open browser: `https://nextcloud.internal`

**Login**: `admin` / `<password-you-set>`

---

## Configuration

### nginx Customization

Edit `nginx.conf` if needed:

**Increase upload size** (default: 10 GB):

```nginx
client_max_body_size 20G;  # Allow 20 GB uploads
```

**Add custom domain**:

```nginx
server_name nextcloud.internal cloud.internal;  # Add additional domain
```

**Enable OCSP stapling** (requires additional volume mount):

```nginx
ssl_stapling on;
ssl_stapling_verify on;
ssl_trusted_certificate /etc/nginx/ssl/root_ca.crt;
```

> **Note**: Add this volume mount to `docker-compose.yml` nginx service:
> ```yaml
> - /etc/ssl/step-ca/root_ca.crt:/etc/nginx/ssl/root_ca.crt:ro
> ```

### Nextcloud Trusted Domains

Add domains via `occ` command:

```bash
docker exec -u www-data nextcloud php occ config:system:set \
    trusted_domains 2 --value=cloud.internal
```

### Nextcloud Apps

Install recommended apps:

```bash
# Install Calendar
docker exec -u www-data nextcloud php occ app:install calendar

# Install Contacts
docker exec -u www-data nextcloud php occ app:install contacts

# Install Talk (requires TURN server for video calls)
docker exec -u www-data nextcloud php occ app:install spreed
```

---

## Certificate Renewal

### Auto-Renewal Setup

Create systemd service for Nextcloud certificate renewal:

**Service** (`/etc/systemd/system/step-ca-renew-nextcloud.service`):

```ini
[Unit]
Description=Renew Nextcloud step-ca Certificate
After=network.target

[Service]
Type=oneshot
Environment="SERVICE_NAME=nextcloud"
Environment="STEP_CA_HOME=/opt/step-ca"
Environment="STEP_CA_CERT_DIR=/etc/ssl/step-ca"
Environment="RENEWAL_THRESHOLD=30"
Environment="SERVICE_RELOAD_CMD=docker compose -f /path/to/nextcloud/docker-compose.yml restart nginx"
ExecStart=/usr/local/bin/renew-service-cert.sh
User=root
```

**Timer** (`/etc/systemd/system/step-ca-renew-nextcloud.timer`):

```ini
[Unit]
Description=Renew Nextcloud Certificate Timer

[Timer]
OnCalendar=*-*-* 04:00:00
Persistent=true

[Install]
WantedBy=timers.target
```

Enable timer:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now step-ca-renew-nextcloud.timer
```

---

## Monitoring

### Prometheus Metrics

Export Nextcloud certificate expiry to Prometheus:

```bash
# Create exporter service
sudo tee /etc/systemd/system/step-ca-exporter-nextcloud.service << 'EOF'
[Unit]
Description=step-ca Nextcloud Certificate Exporter

[Service]
Type=oneshot
Environment="SERVICE_NAME=nextcloud"
Environment="OUTPUT_FILE=/var/lib/node_exporter/textfile_collector/step_ca_nextcloud.prom"
ExecStart=/usr/local/bin/cert-exporter.sh
User=root
EOF

# Create timer
sudo tee /etc/systemd/system/step-ca-exporter-nextcloud.timer << 'EOF'
[Unit]
Description=step-ca Nextcloud Certificate Exporter Timer

[Timer]
OnCalendar=hourly
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Enable
sudo systemctl daemon-reload
sudo systemctl enable --now step-ca-exporter-nextcloud.timer
```

---

## Backup

### Database Backup

```bash
# Backup Nextcloud database
docker exec nextcloud-db mysqldump -u root -p<root-password> nextcloud > nextcloud-db-backup.sql

# Restore
docker exec -i nextcloud-db mysql -u root -p<root-password> nextcloud < nextcloud-db-backup.sql
```

### Data Backup

```bash
# Backup Nextcloud data (files, config)
docker run --rm \
    -v nextcloud_data:/data \
    -v $(pwd):/backup \
    alpine tar czf /backup/nextcloud-data-backup.tar.gz /data

# Restore
docker run --rm \
    -v nextcloud_data:/data \
    -v $(pwd):/backup \
    alpine tar xzf /backup/nextcloud-data-backup.tar.gz -C /
```

---

## Troubleshooting

### "Access through untrusted domain" Error

**Cause**: Domain not in `trusted_domains` list.

**Fix**:

```bash
docker exec -u www-data nextcloud php occ config:system:set \
    trusted_domains 1 --value=your-domain.internal
```

### Large File Upload Fails (413 Request Entity Too Large)

**Cause**: `client_max_body_size` too small in nginx.

**Fix**: Edit `nginx.conf`:

```nginx
client_max_body_size 20G;  # Increase to desired size
```

Restart nginx:

```bash
docker compose restart nginx
```

### CalDAV/CardDAV Not Working

**Cause**: `.well-known` redirects not configured.

**Fix**: Already configured in provided `nginx.conf`:

```nginx
location = /.well-known/carddav {
    return 301 $scheme://$host/remote.php/dav;
}

location = /.well-known/caldav {
    return 301 $scheme://$host/remote.php/dav;
}
```

Verify:

```bash
curl -I https://nextcloud.internal/.well-known/carddav
# Expected: HTTP/1.1 301 Moved Permanently
```

### Certificate Not Trusted

**Cause**: Root CA not installed on client machine.

**Fix**: Install Root CA (see [CLIENT_TRUST.md](../../docs/CLIENT_TRUST.md)).

---

## Performance Tuning

### Enable Redis Caching

Edit `docker-compose.yml`, add Redis service:

```yaml
services:
  redis:
    image: redis:alpine
    restart: unless-stopped
    networks:
      - nextcloud-net

  nextcloud:
    environment:
      - REDIS_HOST=redis
```

Configure in Nextcloud:

```bash
docker exec -u www-data nextcloud php occ config:system:set \
    redis host --value=redis

docker exec -u www-data nextcloud php occ config:system:set \
    redis port --value=6379

docker exec -u www-data nextcloud php occ config:system:set \
    memcache.locking --value='\OC\Memcache\Redis'
```

### Enable Cron Background Jobs

```bash
# Set cron mode
docker exec -u www-data nextcloud php occ background:cron

# Add cron job to host
crontab -e
# Add:
# */5 * * * * docker exec -u www-data nextcloud php cron.php
```

---

## Further Reading

- [Nextcloud Documentation](https://docs.nextcloud.com/) - Official docs
- [Nextcloud Docker Image](https://hub.docker.com/_/nextcloud) - Docker Hub
- [NGINX_TLS.md](../../docs/NGINX_TLS.md) - TLS configuration details
- [SETUP.md](../../docs/SETUP.md) - step-ca setup guide
