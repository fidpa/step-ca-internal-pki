# Troubleshooting Guide

Common issues and solutions for step-ca Production Setup.

## ⚡ TL;DR

Symptom → Ursache → Lösung Format. Häufigste Probleme: Certificate Verification (Trust Chain), Container-Start (Permissions), Auto-Renewal (Timer), Browser-Warnings (Client Trust).

---

## Table of Contents

- [Certificate Issues](#certificate-issues)
- [step-ca Container Issues](#step-ca-container-issues)
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
| Health check fails | Container not listening | [Health Check Fails](#health-check-fails) |
| nginx won't start | Certificate file missing/wrong permissions | [nginx Won't Start](#nginx-wont-start) |
| Metrics not updating | Exporter timer disabled | [Metrics Not Updating](#metrics-not-updating) |

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
systemctl status service-renew.timer
journalctl -u service-renew.service -n 50
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

# Request new certificate
sudo /tmp/service-cert-request.sh
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
# Port conflicts - change ports in docker-compose.yml
# Default: 9200 (HTTP-01), 9643 (HTTPS)
# Change to: 9080, 9443 if conflicts exist

# Permission errors
sudo chown -R 1000:1000 /opt/step-ca/{certs,secrets,config,db}

# Validate ca.json
jq . /opt/step-ca/config/ca.json
```

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
systemctl enable --now service-renew.timer

# Check timer status
systemctl status service-renew.timer

# Force manual run
systemctl start service-renew.service
journalctl -u service-renew.service -f
```

---

### Renewal Fails Silently

**Symptom**: Certificate expired despite timer running

**Diagnosis:**
```bash
# Check recent runs
journalctl -u service-renew.service --since "7 days ago"

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
systemctl cat service-renew.service | grep Environment

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
systemctl cat service-renew.service | grep SERVICE_RELOAD_CMD

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
1. Restore from backup: `/opt/step-ca/backups/`
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
5. Re-issue all service certificates
6. Distribute CRL

**Full Recovery Guide**: See [ARCHITECTURE.md § Disaster Recovery - Intermediate CA Compromise](ARCHITECTURE.md#intermediate-ca-compromise)

---

## Getting Help

1. **Check Logs**: `journalctl -u step-ca.service -f`
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
systemctl status service-renew.timer
journalctl -u service-renew.service -n 100

# Metric verification
curl http://localhost:9100/metrics | grep step_ca
```
