# nginx TLS Termination

Best practices for TLS termination with step-ca certificates in nginx reverse proxy configurations.

## ⚡ TL;DR

nginx with step-ca certificates: serve the fullchain plus the key, TLS 1.3 and 1.2, HSTS on, and a reload after every renewal. OCSP stapling is not available here - step-ca has no OCSP responder.

---

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Basic TLS Configuration](#basic-tls-configuration)
- [Mozilla SSL Configuration Generator](#mozilla-ssl-configuration-generator)
- [Security Headers](#security-headers)
- [OCSP Stapling: not available here](#ocsp-stapling-not-available-here)
- [Certificate Auto-Reload](#certificate-auto-reload)
- [Proxy Configuration Patterns](#proxy-configuration-patterns)
- [Rate Limiting](#rate-limiting)
- [Logging](#logging)
- [Testing TLS Configuration](#testing-tls-configuration)
- [Service-Specific Configurations](#service-specific-configurations)
- [Troubleshooting](#troubleshooting)
- [Production Checklist](#production-checklist)
- [Further Reading](#further-reading)

---

## Prerequisites

Before configuring nginx TLS termination:

- ✅ nginx 1.20+ installed
- ✅ step-ca certificates issued (see [SETUP.md](SETUP.md))
- ✅ Root CA installed on clients (see [CLIENT_TRUST.md](CLIENT_TRUST.md))
- ✅ Certificate files in `/etc/ssl/step-ca/`:
  - `service-fullchain.crt` (server cert + intermediate CA)
  - `service.key` (private key, chmod 600)

> **nginx 1.25.1 and newer**: `listen 443 ssl http2;` still works but is
> deprecated and logs a warning. Write `listen 443 ssl;` plus a separate
> `http2 on;` in the server block. The examples below keep the old form because
> it is what Debian 12 ships (nginx 1.22).

---

## Overview

nginx TLS termination provides:

- **Centralized certificate management** - One reverse proxy handles TLS for multiple backend services
- **Protocol offloading** - Backends use HTTP, nginx handles HTTPS
- **Security hardening** - Modern TLS configuration, security headers, rate limiting

---

## Basic TLS Configuration

### Minimal Working Example

```nginx
server {
    listen 443 ssl http2;
    server_name service.internal;

    # step-ca certificates
    ssl_certificate /etc/ssl/step-ca/service-fullchain.crt;
    ssl_certificate_key /etc/ssl/step-ca/service.key;

    # Proxy to backend
    location / {
        proxy_pass http://backend:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### Certificate Files

| File | Purpose | Required |
|------|---------|----------|
| `service.crt` | Server certificate (leaf) | ✅ |
| `service.key` | Private key | ✅ |
| `service-fullchain.crt` | Server cert + Intermediate CA | ✅ Preferred |

**Why fullchain?** Clients receive the entire certificate chain (leaf → intermediate → root) for validation.

---

## Mozilla SSL Configuration Generator

Use [Mozilla's SSL Config Generator](https://ssl-config.mozilla.org/) for up-to-date TLS settings.

### Modern Profile (Recommended)

**Target**: Modern browsers (Chrome 90+, Firefox 88+, Safari 14+)

```nginx
ssl_protocols TLSv1.3;
ssl_prefer_server_ciphers off;

# TLS 1.3 only (no explicit cipher configuration needed)
ssl_session_timeout 1d;
ssl_session_cache shared:SSL:10m;
ssl_session_tickets off;
```

**Pros**: Maximum security, forward secrecy, 0-RTT disabled
**Cons**: Drops IE 11, older Android devices

### Intermediate Profile (Balanced)

**Target**: 99%+ browser compatibility

```nginx
ssl_protocols TLSv1.2 TLSv1.3;
ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305';
ssl_prefer_server_ciphers off;

ssl_session_timeout 1d;
ssl_session_cache shared:SSL:10m;
ssl_session_tickets off;
```

**Pros**: Wide compatibility, strong ciphers only
**Cons**: Supports TLS 1.2 (needed for older clients)

### Old Profile (Compatibility)

**Target**: IE 11, Java 8, Android 4.4+ support

```nginx
ssl_protocols TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;
ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384';
ssl_prefer_server_ciphers on;
```

**Pros**: Maximum compatibility
**Cons**: Vulnerable to downgrade attacks (TLS 1.0/1.1)

⚠️ **SECURITY WARNING**: TLS 1.0 and 1.1 are **deprecated and insecure** (POODLE, BEAST attacks). Only use this profile for:
- ✅ **Testing/Lab environments** with legacy clients
- ✅ **Explicit compatibility requirements** (documented business need)
- ❌ **NEVER for production** without strong justification

**Recommendation**: Use **Intermediate** for internal services (homelabs, SMB networks).

---

## Security Headers

### Essential Headers

```nginx
# HSTS - Force HTTPS for 1 year
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

# Prevent MIME sniffing
add_header X-Content-Type-Options "nosniff" always;

# Clickjacking protection
add_header X-Frame-Options "SAMEORIGIN" always;

# X-XSS-Protection: Chrome, Edge and Safari removed the auditor this header
# controls, and Firefox never had it. It does nothing on a current browser;
# keep it only if a compliance checklist demands it.
# add_header X-XSS-Protection "1; mode=block" always;

# Referrer policy (don't leak URLs to external sites)
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
```

### Content Security Policy (CSP)

**Basic CSP** (allows same-origin resources only):

```nginx
add_header Content-Security-Policy "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; connect-src 'self'; frame-ancestors 'self';" always;
```

**Why `'unsafe-inline'` for style-src?** Many web apps use inline styles. Remove if your backend supports nonces/hashes.

**Testing CSP**: Use `Content-Security-Policy-Report-Only` header first, monitor violations before enforcing.

### Permissions Policy (formerly Feature-Policy)

```nginx
# Disable unused browser features
add_header Permissions-Policy "geolocation=(), microphone=(), camera=(), payment=()" always;
```

---

## OCSP Stapling: not available here

**What it would do**: the server fetches an OCSP response from the CA and staples
it to the TLS handshake, so the client does not have to ask the CA itself.

**Why it does not apply**: step-ca has no OCSP responder. Smallstep's
documentation says so plainly - the built-in revocation support is a minimal CRL
server, and OCSP is part of their commercial Certificate Manager. On top of that,
the default workflow in this repository signs certificates with OpenSSL, so they
carry no OCSP URL in an Authority Information Access extension for a client to
call.

Turning `ssl_stapling on;` anyway is not an error: nginx logs a warning that no
OCSP responder is available and serves the handshake without a stapled response.
It buys nothing, so leave it off and rely on the short 90-day lifetime instead.

```bash
# What a client sees today:
echo | openssl s_client -connect service.internal:443 -status 2>&1 | grep -i "OCSP"
# "OCSP response: no response sent"
```

---

## Certificate Auto-Reload

### Problem

nginx requires `nginx -s reload` after certificate renewal (cached in memory).

### Solution 1: systemd Timer (Recommended)

Reload nginx after certificate renewal:

**systemd service** (e.g., `/etc/systemd/system/nginx-reload-after-renewal.service`):

```ini
[Unit]
Description=Reload nginx after step-ca certificate renewal
After=step-ca-renew-myservice.service

[Service]
Type=oneshot
ExecStart=/usr/sbin/nginx -s reload
```

**systemd timer**:

```ini
[Unit]
Description=Reload nginx daily (for certificate renewal)

[Timer]
OnCalendar=*-*-* 04:00:00
Persistent=true

[Install]
WantedBy=timers.target
```

### Solution 2: inotify (Real-time)

Watch certificate file changes with `inotifywait`:

```bash
#!/bin/bash
# /usr/local/bin/nginx-cert-watcher.sh

inotifywait -m -e modify,create /etc/ssl/step-ca/ |
while read -r directory event filename; do
    if [[ "$filename" =~ \.crt$ ]]; then
        echo "[$(date)] Certificate changed: $filename, reloading nginx"
        nginx -s reload
    fi
done
```

**systemd service**:

```ini
[Unit]
Description=nginx Certificate Watcher
After=nginx.service

[Service]
ExecStart=/usr/local/bin/nginx-cert-watcher.sh
Restart=always

[Install]
WantedBy=multi-user.target
```

---

## Proxy Configuration Patterns

### WebSocket Support

**Required for**: Real-time apps (Vaultwarden notifications, Nextcloud Talk, Grafana Live, Portainer console)

```nginx
location /websocket {
    proxy_pass http://backend:8080;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_read_timeout 86400;  # 24 hours
}
```

### Large File Uploads

**Required for**: Nextcloud, file sharing services

```nginx
client_max_body_size 10G;
client_body_timeout 300s;
proxy_request_buffering off;

location / {
    proxy_pass http://backend:8080;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header Host $host;
}
```

### HTTP/2 Server Push

⚠️ **DEPRECATED**: HTTP/2 Server Push is **deprecated in Chrome 106+ and Firefox 103+**. Use `Link: rel=preload` headers instead.

**Modern Alternative** (Link headers):

```nginx
server {
    listen 443 ssl http2;
    server_name service.internal;

    location / {
        proxy_pass http://backend:8080;

        # Use Link headers instead (supported by all browsers)
        add_header Link "</static/app.css>; rel=preload; as=style" always;
        add_header Link "</static/app.js>; rel=preload; as=script" always;
    }
}
```

**Legacy** (for reference only):
```nginx
# DEPRECATED - Do not use in new configurations
http2_push /static/app.css;
http2_push /static/app.js;
```

---

## Rate Limiting

### Basic Rate Limit

**Purpose**: Prevent brute-force attacks, DoS protection.

```nginx
http {
    # Define rate limit zone (10 MB stores ~160k IP addresses)
    limit_req_zone $binary_remote_addr zone=login_limit:10m rate=5r/m;

    server {
        listen 443 ssl http2;
        server_name service.internal;

        # Apply rate limit to login endpoint
        location /login {
            limit_req zone=login_limit burst=5 nodelay;
            proxy_pass http://backend:8080;
        }
    }
}
```

**Parameters**:
- `rate=5r/m` - 5 requests per minute
- `burst=5` - Allow bursts up to 5 requests
- `nodelay` - Reject excess requests immediately (no queuing)

### Connection Limit

**Purpose**: Limit concurrent connections per IP (protects against slowloris attacks).

```nginx
http {
    limit_conn_zone $binary_remote_addr zone=conn_limit:10m;

    server {
        listen 443 ssl http2;
        server_name service.internal;

        # Max 10 concurrent connections per IP
        limit_conn conn_limit 10;
    }
}
```

---

## Logging

### Access Log

**Recommended format** (includes TLS protocol/cipher):

```nginx
log_format tls_combined '$remote_addr - $remote_user [$time_local] '
                        '"$request" $status $body_bytes_sent '
                        '"$http_referer" "$http_user_agent" '
                        'TLS=$ssl_protocol/$ssl_cipher';

access_log /var/log/nginx/access.log tls_combined;
```

### Error Log

```nginx
error_log /var/log/nginx/error.log warn;
```

**Analyze TLS usage**:

```bash
# Count TLS versions
awk '{print $NF}' /var/log/nginx/access.log | cut -d'/' -f2 | sort | uniq -c

# Count cipher suites
awk '{print $NF}' /var/log/nginx/access.log | cut -d'/' -f3 | sort | uniq -c
```

---

## Testing TLS Configuration

### SSL Labs Alternative (Local)

Use `testssl.sh` for internal hosts:

```bash
# Install
git clone https://github.com/drwetter/testssl.sh
cd testssl.sh

# Test
./testssl.sh https://service.internal

# Expected: A+ rating (TLS 1.3, strong ciphers only)
```

### Manual Tests

**Check certificate chain**:

```bash
openssl s_client -connect service.internal:443 -showcerts
```

**Verify TLS 1.3**:

```bash
openssl s_client -connect service.internal:443 -tls1_3 < /dev/null
```

**Check HSTS header**:

```bash
curl -I https://service.internal | grep -i strict-transport-security
```

---

## Service-Specific Configurations

### Vaultwarden (Password Manager)

See [examples/vaultwarden/nginx.conf](../examples/vaultwarden/nginx.conf)

**Key requirements**:
- WebSocket support (`/notifications/hub`)
- Large `client_max_body_size` (128 MB for attachments)
- Security headers (CSP)

### Nextcloud (Cloud Storage)

See [examples/nextcloud/nginx.conf](../examples/nextcloud/nginx.conf)

**Key requirements**:
- `/.well-known/` redirects (WebDAV, CalDAV, CardDAV)
- Very large `client_max_body_size` (10 GB+)
- `X-Forwarded-Proto` header (Nextcloud detects HTTPS)

### Portainer (Docker Management)

See [examples/portainer/nginx.conf](../examples/portainer/nginx.conf)

**Key requirements**:
- WebSocket support (Docker console)
- HTTP/2 for UI performance

---

## Troubleshooting

### Certificate Not Trusted by Browser

**Symptoms**: "Your connection is not private" (ERR_CERT_AUTHORITY_INVALID)

**Cause**: Root CA not installed in client's trust store.

**Fix**: Install Root CA on client (see [CLIENT_TRUST.md](CLIENT_TRUST.md)).

### Certificate Reload Not Working

**Symptoms**: nginx serves old certificate after renewal.

**Cause**: nginx caches certificates in memory.

**Fix**:
```bash
nginx -s reload
# OR
systemctl reload nginx
```

### `ssl_stapling` Has No Effect

**Symptoms**: `ssl_stapling on;` is configured, but no OCSP response is stapled,
and the error log shows `"ssl_stapling" ignored, no OCSP responder URL in the certificate`.

**Cause**: expected. step-ca provides no OCSP responder, and OpenSSL-signed
certificates carry no OCSP URL. See [OCSP Stapling: not available here](#ocsp-stapling-not-available-here).

**Fix**: remove the `ssl_stapling` directives.

### WebSocket Connection Drops

**Symptoms**: WebSocket closes after 60 seconds.

**Cause**: `proxy_read_timeout` too short.

**Fix**:
```nginx
location /websocket {
    proxy_pass http://backend:8080;
    proxy_read_timeout 86400;  # 24 hours
}
```

---

## Production Checklist

**Security**:
- ✅ TLS 1.2+ only (disable TLS 1.0/1.1) → [Mozilla SSL Config](#mozilla-ssl-configuration-generator)
- ✅ Strong cipher suites (ECDHE + AES-GCM) → [Intermediate Profile](#intermediate-profile-balanced)
- ✅ Fullchain certificate (`-fullchain.crt`) → [Certificate Files](#certificate-files)
- ✅ HSTS enabled (`max-age=31536000`) → [Security Headers](#essential-headers)
- ✅ Security headers (CSP, X-Frame-Options, etc.) → [Security Headers](#security-headers)

**Operational**:
- ✅ Rate limiting (login endpoints) → [Rate Limiting](#basic-rate-limit)
- ✅ Auto-reload after certificate renewal → [Certificate Auto-Reload](#certificate-auto-reload)

**Validation**:
- ✅ SSL Labs / testssl.sh rating: A or A+ → [Testing TLS Configuration](#testing-tls-configuration)

---

## Further Reading

- [Mozilla SSL Configuration Generator](https://ssl-config.mozilla.org/) - Up-to-date TLS configs
- [SSL Labs Test](https://www.ssllabs.com/ssltest/) - Public endpoint testing
- [testssl.sh](https://github.com/drwetter/testssl.sh) - Local TLS testing
- [nginx TLS Documentation](https://nginx.org/en/docs/http/configuring_https_servers.html) - Official docs
- [OWASP TLS Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Transport_Layer_Protection_Cheat_Sheet.html) - Security guidelines
