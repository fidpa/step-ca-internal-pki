# Troubleshooting Guide

Common issues and solutions for step-ca Production Setup.

## ⚡ TL;DR

Every entry is symptom, cause, fix. The four that come up most: certificate verification (trust chain), container start (permissions), auto-renewal (timer), browser warnings (client trust).

---

## Table of Contents

- [Certificate Issues](#certificate-issues)
- [step-ca Container Issues](#step-ca-container-issues)
- [DNS / Network Coexistence Issues](#dns--network-coexistence-issues)
- [Auto-Renewal Issues](#auto-renewal-issues)
- [nginx/Service Integration Issues](#nginxservice-integration-issues)
- [Monitoring Issues](#monitoring-issues)
- [Permission Errors](#permission-errors)
- [Recovery Procedures](#recovery-procedures)
- [Getting Help](#getting-help)

---

## 🔍 Symptom Index

| Symptom | Root Cause | Section |
|---------|------------|---------|
| `unable to get local issuer certificate` | Root CA not trusted | [Certificate Verification Fails](#certificate-verification-fails) |
| `certificate has expired` | Auto-renewal timer disabled | [Certificate Expired](#certificate-expired) |
| `certificate is valid for X, not Y` | Wrong SANs configured | [Wrong SANs](#wrong-sans-in-certificate) |
| Container won't start | Port conflicts or permissions | [Container Not Starting](#container-not-starting) |
| `error reading /home/step/secrets/password` | Empty `password` file missing | [Container Restart-Loop](#container-restart-loop-with-password-error) |
| Container `health: starting` forever | Healthcheck needs `step ca bootstrap` | [Health Check Stuck](#container-health-check-stuck-starting-but-service-is-up) |
| Health check fails | Container not listening | [Health Check Fails](#health-check-fails) |
| nginx won't start | Certificate file missing/wrong permissions | [nginx Won't Start](#nginx-wont-start) |
| Metrics not updating | Exporter timer disabled | [Metrics Not Updating](#metrics-not-updating) |
| Port 53 already in use | acme-dns/PiHole/dnsmasq conflict | [Port 53 Conflicts](#port-53-already-in-use-acme-dns-pihole-adguard-dnsmasq) |
| Tailscale MagicDNS broken | dnsmasq binding to tailscale interface | [dnsmasq Breaks Tailscale](#dnsmasq-breaks-tailscale-magicdns-or-other-vpn-dns) |
| Internal DNS returns empty answers | `stop-dns-rebind` strips private IPs | [DNS Rebind Protection](#dnsmasq-blocks-private-ips-in-responses-stop-dns-rebind) |

---

## Certificate Issues

### Certificate Verification Fails

**Symptom:**
```
error:20: unable to get local issuer certificate
```

**Cause**: Root CA not trusted on client

**Solution:**
```bash
# Verify Root CA is installed
# macOS:
security find-certificate -a -c "My Internal Root CA" -p /Library/Keychains/System.keychain

# Linux:
ls -l /usr/local/share/ca-certificates/my-internal-ca.crt
update-ca-certificates --fresh

# Test with curl
curl -v https://service.internal
```

**Quick Fix**: Install Root CA on client → See [CLIENT_TRUST.md](CLIENT_TRUST.md)

**Architecture**: See [ARCHITECTURE.md § Trust Anchor Distribution](ARCHITECTURE.md#trust-anchor-distribution) for design explanation

---

### Certificate Expired

**Symptom:**
```
certificate has expired or is not yet valid
```

**Solution:**
```bash
# Check certificate expiry
openssl x509 -in /etc/ssl/step-ca/service.crt -noout -enddate

# Manual renewal
sudo /usr/local/bin/renew-service-cert.sh

# Verify auto-renewal timer
systemctl status step-ca-renew-myservice.timer
journalctl -u step-ca-renew-myservice.service -n 50
```

**Auto-Renewal Setup**: See [SETUP.md § Phase 5: Set Up Auto-Renewal](SETUP.md#phase-5-set-up-auto-renewal)

---

### Wrong SANs in Certificate

**Symptom:**
```
certificate is valid for X, not Y
```

**Solution:**
```bash
# Check current SANs
openssl x509 -in /etc/ssl/step-ca/service.crt -noout -text | grep -A2 "Subject Alternative Name"

# Update SAN configuration
cat > /etc/ssl/step-ca/service.san << EOF
DNS.1 = service.internal
DNS.2 = service2.internal
IP.1 = 10.0.0.2
EOF

# Re-issue with the new SANs. --force skips the days-left threshold, which a
# fresh certificate would otherwise fail.
sudo SERVICE_NAME=service /usr/local/bin/renew-service-cert.sh --force
```

---

## step-ca Container Issues

### Container Not Starting

**Symptom:**
```bash
docker ps | grep step-ca
# (no output)
```

**Diagnosis:**
```bash
# Check logs
docker logs step-ca

# Common issues:
# 1. Port conflicts
# 2. Permission errors on volumes
# 3. Invalid ca.json configuration
```

**Solutions:**
```bash
# Port conflicts - change the published ports in /opt/step-ca/step-ca-stack.yml
# Default: 9200 (HTTP-01), 9643 (HTTPS)
# Change to: 9080, 9443 if conflicts exist

# Permission errors
sudo chown -R 1000:1000 /opt/step-ca/{certs,secrets,config,db}

# Validate ca.json
jq . /opt/step-ca/config/ca.json
```

---

### Container Restart-Loop with `password` Error

**Symptom:**
```bash
docker logs step-ca
# error reading /home/step/secrets/password: open /home/step/secrets/password: no such file or directory
# (repeats indefinitely)
```

**Cause**: step-ca's startup always tries to read a password file to unlock the intermediate CA key — even when the key itself is unencrypted on disk.

**Solution:**
```bash
# Create EMPTY password file (key is unencrypted on disk):
sudo install -o 1000 -g 1000 -m 600 /dev/null /opt/step-ca/secrets/password

# OR: if the intermediate key was encrypted with a passphrase:
echo -n 'your-passphrase' | sudo install -o 1000 -g 1000 -m 600 /dev/stdin /opt/step-ca/secrets/password

# Restart container
docker restart step-ca
```

> See `docs/SETUP.md` Phase 3 Step 3 for the same note in the setup flow.

---

### Health Check Fails

**Symptom:**
```bash
curl -k https://localhost:9643/health
# Connection refused
```

**Solution:**
```bash
# Check container status
docker inspect step-ca | grep -A10 Health

# Restart container
docker restart step-ca

# Check firewall
sudo ufw status | grep 9643
```

---

### Container Health Check Stuck "starting" (but service is up)

**Symptom:** `docker ps` shows `(health: starting)` indefinitely, but `curl -k https://localhost:9643/health` returns `{"status":"ok"}`.

**Cause**: The default healthcheck (`step ca health`) needs `step ca bootstrap` to have run inside the container to register the CA URL + fingerprint. For installations using the OpenSSL signing workflow (no bootstrap), the healthcheck stays in "starting" but is harmless.

**Solutions** (pick one):

```bash
# Option A: Bootstrap step inside the container (one-time)
ROOT_FINGERPRINT=$(step certificate fingerprint /opt/step-ca/certs/root_ca.crt)
docker exec step-ca step ca bootstrap \
    --ca-url https://localhost:9443 \
    --fingerprint "$ROOT_FINGERPRINT"

# Option B: Override the healthcheck with a simpler curl in docker-compose.yml:
# healthcheck:
#   test: ["CMD-SHELL", "wget --no-check-certificate -qO- https://localhost:9443/health || exit 1"]
```

---

## DNS / Network Coexistence Issues

### Port 53 Already in Use (acme-dns, PiHole, AdGuard, dnsmasq)

**Symptom:** When deploying a DNS resolver alongside step-ca's PKI infrastructure (e.g. for `*.internal` resolution), another service already occupies port 53.

```bash
sudo ss -lntup | grep ':53\b'
# Example: 0.0.0.0:53  -> acme-dns container, or PiHole, or dnsmasq
```

**Three strategies (pick by your stack):**

#### Strategy A: Move the existing DNS service to an alternative port

Best when the existing service is reached only from a fixed upstream (e.g. an external port-forwarding rule for acme-dns DNS-01 validation).

```yaml
# docker-compose.yml of the existing service (example: acme-dns):
ports:
  - "0.0.0.0:5343:53/tcp"   # was "0.0.0.0:53:53/tcp"
  - "0.0.0.0:5343:53/udp"
```

Then update the upstream:
- Router NAT port-forward: external `53/tcp+udp` → internal `5343/tcp+udp`
- Or: external resolvers configured to query `IP:5343`

#### Strategy B: Bind your new DNS resolver to a specific interface

Best when both services need to listen on port 53 but on different interfaces (e.g. LAN-only vs. tunnel-only).

```conf
# dnsmasq config (only listens on LAN-IP + loopback, not 0.0.0.0):
listen-address=192.0.2.5,127.0.0.1
bind-interfaces
```

> **Critical**: Without `bind-interfaces`, dnsmasq listens on ALL interfaces including any VPN-side interface — which can break upstream DNS proxies (e.g. Tailscale MagicDNS on 100.100.100.100).

#### Strategy C: Source-based DNAT (advanced)

Route DNS queries from LAN to one service, from WAN to another. Complex; only worth it if neither A nor B fit.

---

### dnsmasq Breaks Tailscale MagicDNS (or other VPN DNS)

**Symptom:** After starting dnsmasq, `dig @100.100.100.100 example.com` times out. Tailscale-managed `/etc/resolv.conf` no longer resolves anything.

**Cause:** dnsmasq's default behavior (`bind-dynamic` or `bind-interfaces` with `listen-address=` missing) binds to every interface — including the Tailscale-assigned IP on `tailscale0`. dnsmasq then intercepts queries that should reach `tailscaled`'s internal MagicDNS resolver.

**Logs to confirm:**
```
dnsmasq[NNNN]: LOUD WARNING: listening on 100.x.x.x may accept requests via interfaces other than tailscale0
```

**Solution:**
```conf
# /etc/dnsmasq.d/local.conf
listen-address=192.0.2.5,127.0.0.1   # LAN-IP + loopback ONLY
bind-interfaces                       # do not auto-bind to other interfaces
```

After change: `sudo systemctl restart dnsmasq` and verify Tailscale DNS still works:
```bash
dig @100.100.100.100 example.com +short   # must return an answer
```

---

### dnsmasq Blocks Private IPs in Responses (`stop-dns-rebind`)

**Symptom:** Forward to an upstream DNS server that legitimately returns private IPs (e.g. an Active Directory DNS responding with `192.168.x.x` for internal hostnames) returns empty answers via dnsmasq, but works when querying the upstream directly.

```bash
# Direct upstream — works:
dig @192.168.1.10 dc.corp.local +short
# 192.168.1.10

# Via dnsmasq — empty:
dig @127.0.0.1 dc.corp.local +short
# (nothing)
```

**Cause**: dnsmasq's `stop-dns-rebind` (DNS rebinding protection) strips RFC1918 IPs from responses by default.

**Solution**: Whitelist the internal domain(s):

```conf
# /etc/dnsmasq.d/local.conf
stop-dns-rebind
rebind-localhost-ok
rebind-domain-ok=/corp.local/
rebind-domain-ok=/internal/
```

---

## Auto-Renewal Issues

### Timer Not Running

**Symptom:**
```bash
systemctl list-timers | grep renew
# (no output)
```

**Solution:**
```bash
# Enable timer
systemctl enable --now step-ca-renew-myservice.timer

# Check timer status
systemctl status step-ca-renew-myservice.timer

# Force manual run
systemctl start step-ca-renew-myservice.service
journalctl -u step-ca-renew-myservice.service -f
```

---

### Renewal Fails Silently

**Symptom**: Certificate expired despite timer running

**Diagnosis:**
```bash
# Check recent runs
journalctl -u step-ca-renew-myservice.service --since "7 days ago"

# Check certificate days remaining
openssl x509 -in /etc/ssl/step-ca/service.crt -noout -enddate
```

**Common Causes:**
1. **Wrong RENEWAL_THRESHOLD**: Set too low (e.g., 1 day instead of 30)
2. **Permission errors**: Service can't write to /etc/ssl/step-ca/
3. **CA files missing**: Intermediate CA or Root CA moved/deleted

**Solution:**
```bash
# Verify environment in service file
systemctl cat step-ca-renew-myservice.service | grep Environment

# Test renewal manually
sudo RENEWAL_THRESHOLD=90 /usr/local/bin/renew-service-cert.sh
```

---

## nginx/Service Integration Issues

### nginx Won't Start

**Symptom:**
```
nginx: [emerg] cannot load certificate "/etc/ssl/step-ca/service.crt"
```

**Diagnosis:**
```bash
# Check certificate exists
ls -l /etc/ssl/step-ca/service.crt

# Verify nginx config syntax
nginx -t

# Check nginx error log
tail -50 /var/log/nginx/error.log
```

**Solution:**
```bash
# Verify certificate permissions
sudo chmod 644 /etc/ssl/step-ca/service.crt
sudo chmod 644 /etc/ssl/step-ca/service-fullchain.crt
sudo chmod 600 /etc/ssl/step-ca/service.key

# Use fullchain in nginx config
ssl_certificate /etc/ssl/step-ca/service-fullchain.crt;
ssl_certificate_key /etc/ssl/step-ca/service.key;
```

**nginx TLS Config**: See [NGINX_TLS.md § Basic TLS Configuration](NGINX_TLS.md#basic-tls-configuration)

---

### Service Doesn't Reload After Renewal

**Symptom**: Old certificate still in use after renewal

**Solution:**
```bash
# Check SERVICE_RELOAD_CMD in systemd service
systemctl cat step-ca-renew-myservice.service | grep SERVICE_RELOAD_CMD

# Should be:
Environment="SERVICE_RELOAD_CMD=systemctl reload nginx"

# Manual reload
systemctl reload nginx

# Verify new certificate
echo | openssl s_client -connect localhost:443 -servername service.internal 2>/dev/null | \
    openssl x509 -noout -dates
```

**Auto-Reload Setup**: See [NGINX_TLS.md § Certificate Auto-Reload](NGINX_TLS.md#certificate-auto-reload)

---

## Monitoring Issues

### Metrics Not Updating

**Symptom**: Prometheus shows stale metrics

**Diagnosis:**
```bash
# Check exporter timer
systemctl status step-ca-exporter.timer

# Check recent runs
journalctl -u step-ca-exporter.service --since "1 hour ago"

# Verify output file
cat /var/lib/node_exporter/textfile_collector/step_ca.prom
```

**Solution:**
```bash
# Run exporter manually
sudo OUTPUT_FILE=/var/lib/node_exporter/textfile_collector/step_ca.prom \
    /usr/local/bin/cert-exporter.sh

# Check permissions
ls -l /var/lib/node_exporter/textfile_collector/

# Restart node_exporter
systemctl restart node_exporter
```

---

### Prometheus Alerts Not Firing

**Symptom**: Certificate expiring but no alert

**Check:**
```bash
# Verify alert rules loaded
curl http://localhost:9090/api/v1/rules | jq '.data.groups[].rules[] | select(.name | contains("StepCA"))'

# Check alert state
curl http://localhost:9090/api/v1/alerts | jq '.data.alerts[] | select(.labels.alertname | contains("StepCA"))'
```

**Solution:**
```bash
# Reload Prometheus rules
curl -X POST http://localhost:9090/-/reload

# Verify metrics exist
curl http://localhost:9090/api/v1/query?query=step_ca_cert_days_remaining
```

---

## Permission Errors

### Docker UID/GID Mismatch

**Symptom:**
```
Permission denied: '/home/step/db'
```

**Solution:**
```bash
# step-ca container runs as UID 1000
# Fix ownership
sudo chown -R 1000:1000 /opt/step-ca/{db,certs,secrets,config}

# Verify
ls -ln /opt/step-ca/
```

---

## Recovery Procedures

### Lost Intermediate CA

**Recovery Time**: 15-30 minutes

**Steps:**
1. Restore from backup: `/opt/backups/step-ca/` (the location the backup script in BACKUP.md writes to)
2. Verify integrity: `openssl verify -CAfile root_ca.crt intermediate_ca.crt`
3. Restart step-ca: `docker restart step-ca`

**Full Recovery Guide**: See [BACKUP.md § Scenario 1: Intermediate CA Loss](BACKUP.md#scenario-1-intermediate-ca-loss-step-ca-host-failure)

---

### Intermediate CA Compromised

**Recovery Time**: 30-60 minutes

**Steps:**
1. Decrypt offline Root CA
2. Generate new Intermediate CA
3. Sign with Root CA
4. Deploy new Intermediate
5. Re-issue all service certificates with **new keys**
6. Replace the old Intermediate in every fullchain file and reload the services

There is no CRL step: certificates signed the OpenSSL way are not in step-ca's
database and cannot be revoked. The old Intermediate stays valid until it
expires.

**Full Recovery Guide**: See [ARCHITECTURE.md § Disaster Recovery - Intermediate CA Compromise](ARCHITECTURE.md#intermediate-ca-compromise)

---

## Getting Help

1. **Check Logs**: `docker logs -f step-ca` (step-ca runs as a container, not as a systemd unit)
2. **Search Issues**: [GitHub Issues](https://github.com/fidpa/step-ca-internal-pki/issues)
3. **step-ca Docs**: https://smallstep.com/docs/step-ca
4. **Community**: https://github.com/smallstep/certificates/discussions

---

**Common Commands Reference:**

```bash
# Certificate verification
openssl x509 -in cert.crt -noout -text
openssl verify -CAfile root.crt -untrusted intermediate.crt cert.crt

# Container operations
docker logs step-ca
docker exec -it step-ca step ca health

# systemd debugging
systemctl status step-ca-renew-myservice.timer
journalctl -u step-ca-renew-myservice.service -n 100

# Metric verification
curl http://localhost:9100/metrics | grep step_ca
```
