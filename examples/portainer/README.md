# Portainer with step-ca TLS

Deploy Portainer CE (Docker management UI) with TLS termination using step-ca certificates.

---

## Overview

This example demonstrates:
- Portainer CE container with nginx TLS termination
- step-ca certificates for HTTPS
- WebSocket support (for Docker console/logs)
- Secure Docker Socket access

---

## Prerequisites

- Docker & Docker Compose installed
- step-ca Root CA certificate installed on client machines (see [CLIENT_TRUST.md](../../docs/CLIENT_TRUST.md))
- step-ca certificate issued for `portainer.internal` (see below)

> **Port Conflict Warning**: This example binds to ports `80:80` and `443:443`. If you have other services (e.g., Nextcloud, Vaultwarden) on the same host, you must either:
> - Use a shared reverse proxy (Traefik, nginx-proxy) for all services
> - Change port mappings in `docker-compose.yml` (e.g., `8443:443`)
> - Run services on separate hosts

---

## Certificate Request

Generate certificate for Portainer:

```bash
# Copy template
sudo cp ../../examples/cert-request-template.sh /tmp/portainer-cert-request.sh

# Edit DNS SANs and IP SANs
sudo nano /tmp/portainer-cert-request.sh
# Set:
# declare -a DNS_SANS=(
#     "portainer.internal"
#     "docker.internal"
# )
# declare -a IP_SANS=(
#     "192.168.1.100"  # Your server IP
# )
# SERVICE_NAME="portainer"

# Run as root
sudo /tmp/portainer-cert-request.sh

# Verify certificates created
ls -l /etc/ssl/step-ca/portainer*
# Expected:
# portainer.crt
# portainer.key
# portainer-fullchain.crt
```

---

## Deployment

### 1. Clone Configuration

```bash
# Create directory
mkdir -p ~/portainer-step-ca
cd ~/portainer-step-ca

# Copy files from this example
cp /path/to/step-ca-internal-pki/examples/portainer/* .
```

### 2. Review Docker Socket Security

**Warning**: Portainer requires access to Docker socket (`/var/run/docker.sock`), which grants **full control** over Docker daemon.

**Security implications**:
- ✅ Container can manage all Docker resources (start/stop/exec)
- ⚠️ Potential privilege escalation (exec as root in containers)
- ✅ Mitigation: Use Docker Socket Proxy (see [Advanced Security](#advanced-security) below)

For trusted internal use (homelab, single-user), direct socket mount is acceptable.

### 3. Start Services

```bash
# Start Portainer + nginx
docker compose up -d

# Check logs
docker compose logs -f

# Verify containers running
docker compose ps
# Expected:
# NAME                 STATUS
# portainer            Up
# portainer-nginx      Up
```

### 4. Initial Setup

Open browser: `https://portainer.internal`

1. **Create admin account** (first time only)
   - Username: `admin`
   - Password: **Strong password** (12+ characters)

2. **Connect to local Docker environment**
   - Select **Local** (Docker socket already mounted)
   - Click **Connect**

3. **Verify**:
   - Dashboard shows containers, images, volumes, networks
   - Click **Containers** → See running containers
   - Click **Console** icon → WebSocket terminal opens

---

## Verification

### HTTPS Test

```bash
# Test TLS connection
curl -v https://portainer.internal

# Expected:
# * SSL connection using TLSv1.3 / TLS_AES_256_GCM_SHA384
# * Server certificate:
# *  subject: CN=portainer
# *  issuer: CN=Your Intermediate CA
# * SSL certificate verify ok.
```

> **Note**: CN equals SERVICE_NAME (short name), SANs contain the FQDNs. Modern TLS clients validate SANs, not CN.

### WebSocket Test

Open browser DevTools → **Network** tab → Filter: **WS**

Navigate to: **Containers** → Click any container → **Console**

**Expected**: WebSocket connection established (`ws://` upgraded to `wss://`):

```
Status: 101 Switching Protocols
Upgrade: websocket
Connection: Upgrade
```

---

## Configuration

### nginx Customization

Edit `nginx.conf` if needed:

**Add custom domain**:

```nginx
server_name portainer.internal docker.internal;  # Add additional domain
```

**Adjust WebSocket timeout** (default: 1 hour):

```nginx
location / {
    proxy_pass http://portainer:9000;
    proxy_read_timeout 7200s;  # 2 hours
}
```

### Portainer Settings

Access Portainer settings: **Settings** → **General**

**Recommended changes**:
- **Session lifetime**: 24 hours (default: 8 hours)
- **Enable Edge Compute**: Off (unless managing remote agents)
- **Telemetry**: Off (disable anonymous analytics)

---

## Certificate Renewal

### Auto-Renewal Setup

Create systemd service for Portainer certificate renewal:

**Service** (`/etc/systemd/system/step-ca-renew-portainer.service`):

```ini
[Unit]
Description=Renew Portainer step-ca Certificate
After=network.target

[Service]
Type=oneshot
Environment="SERVICE_NAME=portainer"
Environment="STEP_CA_HOME=/opt/step-ca"
Environment="STEP_CA_CERT_DIR=/etc/ssl/step-ca"
Environment="RENEWAL_THRESHOLD=30"
Environment="SERVICE_RELOAD_CMD=docker compose -f /path/to/portainer/docker-compose.yml restart nginx"
ExecStart=/usr/local/bin/renew-service-cert.sh
User=root
```

**Timer** (`/etc/systemd/system/step-ca-renew-portainer.timer`):

```ini
[Unit]
Description=Renew Portainer Certificate Timer

[Timer]
OnCalendar=*-*-* 04:00:00
Persistent=true

[Install]
WantedBy=timers.target
```

Enable timer:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now step-ca-renew-portainer.timer
```

---

## Monitoring

### Prometheus Metrics

Portainer exposes metrics at `http://portainer:9000/api/status` (internal).

Export certificate expiry to Prometheus:

```bash
# Create exporter service
sudo tee /etc/systemd/system/step-ca-exporter-portainer.service << 'EOF'
[Unit]
Description=step-ca Portainer Certificate Exporter

[Service]
Type=oneshot
Environment="SERVICE_NAME=portainer"
Environment="OUTPUT_FILE=/var/lib/node_exporter/textfile_collector/step_ca_portainer.prom"
ExecStart=/usr/local/bin/cert-exporter.sh
User=root
EOF

# Create timer
sudo tee /etc/systemd/system/step-ca-exporter-portainer.timer << 'EOF'
[Unit]
Description=step-ca Portainer Certificate Exporter Timer

[Timer]
OnCalendar=hourly
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Enable
sudo systemctl daemon-reload
sudo systemctl enable --now step-ca-exporter-portainer.timer
```

---

## Advanced Security

### Docker Socket Proxy

**Problem**: Mounting `/var/run/docker.sock` grants full Docker API access.

**Solution**: Use [Tecnativa's Docker Socket Proxy](https://github.com/Tecnativa/docker-socket-proxy) to restrict access.

**Modified docker-compose.yml**:

```yaml
services:
  socket-proxy:
    image: tecnativa/docker-socket-proxy
    container_name: portainer-socket-proxy
    restart: unless-stopped
    environment:
      - CONTAINERS=1
      - IMAGES=1
      - NETWORKS=1
      - VOLUMES=1
      - SERVICES=1
      - TASKS=1
      - NODES=1
      - BUILD=0  # Disable build API
      - COMMIT=0  # Disable commit API
      - CONFIGS=0
      - DISTRIBUTION=0
      - EXEC=1  # Enable exec (required for console)
      - GRPC=0
      - INFO=1
      - POST=1  # Enable POST (start/stop containers)
      - PLUGINS=0
      - SECRETS=0
      - SWARM=0
      - SYSTEM=1
      - VERSION=1
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    networks:
      - portainer-net

  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    restart: unless-stopped
    volumes:
      - portainer_data:/data
      # NOTE: NO docker.sock mount, uses socket-proxy instead
    environment:
      - DOCKER_HOST=tcp://socket-proxy:2375
    networks:
      - portainer-net
    depends_on:
      - socket-proxy
```

**Benefits**:
- ✅ Restricted Docker API access (only allowed operations)
- ✅ Read-only socket mount in proxy
- ✅ Portainer connects via TCP (no direct socket access)

---

## Backup

### Portainer Data Backup

```bash
# Backup Portainer data (database, configs)
docker run --rm \
    -v portainer_data:/data \
    -v $(pwd):/backup \
    alpine tar czf /backup/portainer-data-backup.tar.gz /data

# Restore
docker run --rm \
    -v portainer_data:/data \
    -v $(pwd):/backup \
    alpine tar xzf /backup/portainer-data-backup.tar.gz -C /
```

---

## Troubleshooting

### "Cannot connect to Docker daemon" Error

**Cause**: Docker socket not accessible, or wrong permissions.

**Fix**:

```bash
# Check socket exists
ls -l /var/run/docker.sock

# Verify Portainer container has socket mount
docker inspect portainer | grep -A 5 "Mounts"

# Restart Portainer
docker compose restart portainer
```

### WebSocket Connection Fails (Console/Logs)

**Cause**: nginx not configured for WebSocket upgrade.

**Fix**: Already configured in provided `nginx.conf`:

```nginx
location / {
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
}
```

Verify:

```bash
# Check nginx logs
docker compose logs nginx | grep -i websocket
```

### Certificate Not Trusted

**Cause**: Root CA not installed on client machine.

**Fix**: Install Root CA (see [CLIENT_TRUST.md](../../docs/CLIENT_TRUST.md)).

### Portainer Shows Old TLS Certificate

**Cause**: nginx cached old certificate.

**Fix**: Reload nginx after certificate renewal:

```bash
docker compose restart nginx
```

---

## Use Cases

### Manage Multiple Docker Hosts

Portainer supports managing remote Docker hosts:

1. **Settings** → **Endpoints** → **Add Endpoint**
2. Select **Docker** → **API**
3. Enter remote host URL: `tcp://<remote-host>:2375`
4. Configure TLS if remote host requires it

**Security Note**: Use TLS-protected Docker API (port 2376) for remote hosts.

### Deploy Stacks (docker-compose)

1. **Stacks** → **Add Stack**
2. **Upload** `docker-compose.yml` or paste content
3. **Deploy**

Portainer manages stack lifecycle (start, stop, remove).

### View Container Logs

1. **Containers** → Click container name
2. **Logs** tab → Real-time log streaming
3. **Console** tab → Interactive terminal (WebSocket)

---

## Further Reading

- [Portainer Documentation](https://docs.portainer.io/) - Official docs
- [Portainer CE vs Business](https://www.portainer.io/products) - Feature comparison
- [Docker Socket Proxy](https://github.com/Tecnativa/docker-socket-proxy) - Security hardening
- [NGINX_TLS.md](../../docs/NGINX_TLS.md) - TLS configuration details
- [SETUP.md](../../docs/SETUP.md) - step-ca setup guide
