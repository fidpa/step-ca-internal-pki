# Generic Service Integration Template

Template for integrating any service with step-ca TLS termination via nginx.

---

## Overview

This template provides:
- nginx reverse proxy with TLS termination
- step-ca certificate integration
- WebSocket support (configurable)
- Auto-renewal via systemd timer

**Use this template when**:
- Your service doesn't have a dedicated example
- You need a starting point for custom integration
- You're adapting an existing service to use step-ca

---

## Prerequisites

- Docker & Docker Compose installed
- step-ca Root CA certificate installed on client machines (see [CLIENT_TRUST.md](../../docs/CLIENT_TRUST.md))
- step-ca certificate issued for your service (see below)

> **Port Conflict Warning**: This example binds to port `443:443`. If you have other services on the same host, you must either:
> - Use a shared reverse proxy (Traefik, nginx-proxy) for all services
> - Change port mappings in `docker-compose.yml` (e.g., `8443:443`)
> - Run services on separate hosts

---

## Certificate Request

Generate certificate for your service:

```bash
# Copy template
sudo cp ../../examples/cert-request-template.sh /tmp/myservice-cert-request.sh

# Edit DNS SANs and IP SANs
sudo nano /tmp/myservice-cert-request.sh
# Set:
# declare -a DNS_SANS=(
#     "myservice.internal"
#     "app.internal"           # Additional domains (optional)
# )
# declare -a IP_SANS=(
#     "192.168.1.100"          # Your server IP
# )
# SERVICE_NAME="myservice"

# Run as root
sudo /tmp/myservice-cert-request.sh

# Verify certificates created
ls -l /etc/ssl/step-ca/myservice*
# Expected:
# myservice.crt
# myservice.key
# myservice-fullchain.crt
```

---

## Deployment

### Option A: Docker Compose (Recommended)

#### 1. Create Project Directory

```bash
mkdir -p ~/myservice-step-ca
cd ~/myservice-step-ca
```

#### 2. Create docker-compose.yml

```yaml
version: '3.8'

services:
  # Your application container
  app:
    image: your-app:latest
    container_name: myservice-app
    restart: unless-stopped
    # ports:
    #   - "8080:8080"  # Don't expose directly, use nginx
    networks:
      - myservice-net
    # volumes:
    #   - app_data:/data

  # nginx TLS termination
  nginx:
    image: nginx:alpine
    container_name: myservice-nginx
    restart: unless-stopped
    ports:
      - "443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
      - /etc/ssl/step-ca/myservice-fullchain.crt:/etc/nginx/ssl/fullchain.crt:ro
      - /etc/ssl/step-ca/myservice.key:/etc/nginx/ssl/cert.key:ro
    networks:
      - myservice-net
    depends_on:
      - app

networks:
  myservice-net:
    driver: bridge

# volumes:
#   app_data:
```

#### 3. Create nginx.conf

```nginx
events {
    worker_connections 1024;
}

http {
    # Logging
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;

    # Upstream application
    upstream app {
        server app:8080;  # Adjust port to your application
    }

    # Redirect HTTP to HTTPS
    server {
        listen 80;
        server_name myservice.internal;
        return 301 https://$host$request_uri;
    }

    # HTTPS server
    server {
        listen 443 ssl http2;
        server_name myservice.internal;

        # TLS configuration
        ssl_certificate /etc/nginx/ssl/fullchain.crt;
        ssl_certificate_key /etc/nginx/ssl/cert.key;

        # Modern TLS settings
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
        ssl_prefer_server_ciphers off;

        # Security headers
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-XSS-Protection "1; mode=block" always;

        # Proxy settings
        location / {
            proxy_pass http://app;
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;

            # WebSocket support (uncomment if needed)
            # proxy_set_header Upgrade $http_upgrade;
            # proxy_set_header Connection "upgrade";
            # proxy_read_timeout 86400s;
        }
    }
}
```

#### 4. Start Services

```bash
docker compose up -d
docker compose logs -f
```

---

### Option B: Standalone nginx (No Docker)

#### 1. Install nginx

```bash
sudo apt update
sudo apt install nginx
```

#### 2. Create Site Configuration

```bash
sudo nano /etc/nginx/sites-available/myservice.conf
```

```nginx
server {
    listen 80;
    server_name myservice.internal;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name myservice.internal;

    ssl_certificate /etc/ssl/step-ca/myservice-fullchain.crt;
    ssl_certificate_key /etc/ssl/step-ca/myservice.key;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256;
    ssl_prefer_server_ciphers off;

    location / {
        proxy_pass http://localhost:8080;  # Your application port
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

#### 3. Enable Site

```bash
sudo ln -s /etc/nginx/sites-available/myservice.conf /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

---

## Verification

### HTTPS Test

```bash
# Test TLS connection
curl -v https://myservice.internal

# Expected:
# * SSL connection using TLSv1.3 / TLS_AES_256_GCM_SHA384
# * Server certificate:
# *  subject: CN=myservice
# *  issuer: CN=Your Intermediate CA
# * SSL certificate verify ok.
```

> **Note**: CN equals SERVICE_NAME (short name), SANs contain the FQDNs. Modern TLS clients validate SANs, not CN.

### Certificate Details

```bash
echo | openssl s_client -connect myservice.internal:443 -servername myservice.internal 2>/dev/null | \
    openssl x509 -noout -subject -issuer -dates
```

---

## Certificate Renewal

### Auto-Renewal Setup

**Service** (`/etc/systemd/system/step-ca-renew-myservice.service`):

```ini
[Unit]
Description=Renew myservice step-ca Certificate
After=network.target

[Service]
Type=oneshot
Environment="SERVICE_NAME=myservice"
Environment="STEP_CA_HOME=/opt/step-ca"
Environment="STEP_CA_CERT_DIR=/etc/ssl/step-ca"
Environment="RENEWAL_THRESHOLD=30"
Environment="SERVICE_RELOAD_CMD=docker exec myservice-nginx nginx -s reload"
# Or for standalone: Environment="SERVICE_RELOAD_CMD=systemctl reload nginx"
ExecStart=/usr/local/bin/renew-service-cert.sh
User=root
```

**Timer** (`/etc/systemd/system/step-ca-renew-myservice.timer`):

```ini
[Unit]
Description=Renew myservice Certificate Timer

[Timer]
OnCalendar=*-*-* 04:00:00
Persistent=true

[Install]
WantedBy=timers.target
```

Enable:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now step-ca-renew-myservice.timer
```

---

## Monitoring

### Prometheus Metrics

```bash
# Create exporter service
sudo tee /etc/systemd/system/step-ca-exporter-myservice.service << 'EOF'
[Unit]
Description=step-ca myservice Certificate Exporter

[Service]
Type=oneshot
Environment="SERVICE_NAME=myservice"
Environment="OUTPUT_FILE=/var/lib/node_exporter/textfile_collector/step_ca_myservice.prom"
ExecStart=/usr/local/bin/cert-exporter.sh
User=root
EOF

# Create timer
sudo tee /etc/systemd/system/step-ca-exporter-myservice.timer << 'EOF'
[Unit]
Description=step-ca myservice Certificate Exporter Timer

[Timer]
OnCalendar=hourly
Persistent=true

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now step-ca-exporter-myservice.timer
```

---

## Customization

### Enable WebSocket Support

Uncomment in nginx.conf:

```nginx
location / {
    proxy_pass http://app;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header Upgrade $http_upgrade;        # Uncomment
    proxy_set_header Connection "upgrade";          # Uncomment
    proxy_read_timeout 86400s;                      # Uncomment (24h timeout)
}
```

### Multiple Backends (Load Balancing)

```nginx
upstream app {
    server app1:8080 weight=3;
    server app2:8080 weight=1;
    server app3:8080 backup;
}
```

### Health Check Endpoint

```nginx
location /health {
    proxy_pass http://app/health;
    access_log off;
}
```

### Large File Uploads

```nginx
server {
    client_max_body_size 100M;  # Allow 100 MB uploads

    location / {
        proxy_pass http://app;
        proxy_request_buffering off;  # Stream large uploads
    }
}
```

---

## Troubleshooting

### 502 Bad Gateway

**Cause**: Backend application not running or wrong port.

**Fix**:
```bash
# Check backend is running
docker compose ps
# Or: systemctl status myservice

# Verify port in nginx.conf matches application
```

### Certificate Not Trusted

**Cause**: Root CA not installed on client.

**Fix**: Install Root CA (see [CLIENT_TRUST.md](../../docs/CLIENT_TRUST.md)).

### Connection Timeout

**Cause**: Firewall blocking port 443.

**Fix**:
```bash
# Allow HTTPS
sudo ufw allow 443/tcp
```

### SSL Handshake Failure

**Cause**: Certificate/key mismatch or permissions.

**Fix**:
```bash
# Verify certificate and key match
openssl x509 -noout -modulus -in /etc/ssl/step-ca/myservice.crt | md5sum
openssl rsa -noout -modulus -in /etc/ssl/step-ca/myservice.key | md5sum
# Both should output the same hash

# Check permissions
ls -l /etc/ssl/step-ca/myservice.*
# Key should be 600 (root:root)
```

---

## Further Reading

- [NGINX_TLS.md](../../docs/NGINX_TLS.md) - Detailed TLS configuration
- [SETUP.md](../../docs/SETUP.md) - step-ca setup guide
- [CLIENT_TRUST.md](../../docs/CLIENT_TRUST.md) - Root CA installation
- [nginx Documentation](https://nginx.org/en/docs/) - Official nginx docs
