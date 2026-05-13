# Initial Setup Guide

Complete installation guide for step-ca Production Setup.

## ⚡ TL;DR

Offline Root CA (10 years) → online Intermediate CSR → offline sign Intermediate → deploy step-ca → request certificates → auto-renewal. Total time: ~75 minutes. **You will go offline twice**, with one online step in between.

---

## Table of Contents

- [Workflow Overview](#workflow-overview)
- [Prerequisites](#prerequisites)
- [Phase 1: Create Root CA (Offline)](#phase-1-create-root-ca-offline)
- [Phase 2: Create Intermediate CA](#phase-2-create-intermediate-ca)
- [Phase 3: Deploy step-ca](#phase-3-deploy-step-ca)
- [Phase 4: Request First Service Certificate](#phase-4-request-first-service-certificate)
- [Phase 5: Set Up Auto-Renewal](#phase-5-set-up-auto-renewal)
- [Phase 6: Install Client Trust](#phase-6-install-client-trust)
- [Verification](#verification)
- [Next Steps](#next-steps)

---

## Workflow Overview

The two-tier PKI setup requires **two offline sessions** with one online step in between. This is enforced by the architecture: the Root CA private key must never touch the production server, but the Intermediate key must live there permanently.

```
┌────────────────────────────────────────────────────────────────────┐
│  AIR-GAPPED MACHINE (e.g. MacBook with WiFi/Ethernet disabled)     │
│                                                                    │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │ OFFLINE SESSION 1 — Phase 1                                  │  │
│  │   • Generate Root CA key pair (ECDSA P-384)                  │  │
│  │   • Self-sign Root CA certificate (10 years)                 │  │
│  │   • GPG-encrypt Root key, securely wipe plaintext            │  │
│  │   • USB ← root_ca.crt  (PUBLIC only)                         │  │
│  └──────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────┘
                              │
                              │  USB transports root_ca.crt
                              ▼
┌────────────────────────────────────────────────────────────────────┐
│  PRODUCTION SERVER (online)                                        │
│                                                                    │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │ ONLINE STEP — Phase 2 Steps 1–2                              │  │
│  │   • Install root_ca.crt → /opt/step-ca/certs/                │  │
│  │   • Generate Intermediate CA key pair (stays here)           │  │
│  │   • Generate CSR (Certificate Signing Request)               │  │
│  │   • USB ← intermediate_ca.csr  (signing request, public)     │  │
│  └──────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────┘
                              │
                              │  USB transports intermediate_ca.csr
                              ▼
┌────────────────────────────────────────────────────────────────────┐
│  AIR-GAPPED MACHINE again                                          │
│                                                                    │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │ OFFLINE SESSION 2 — Phase 2 Step 3                           │  │
│  │   • GPG-decrypt Root key (passphrase from password manager)  │  │
│  │   • Sign Intermediate CSR with Root → intermediate_ca.crt    │  │
│  │   • Securely wipe decrypted Root key from disk               │  │
│  │   • USB ← intermediate_ca.crt  (PUBLIC, 5-year validity)     │  │
│  └──────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────┘
                              │
                              │  USB transports intermediate_ca.crt
                              ▼
┌────────────────────────────────────────────────────────────────────┐
│  PRODUCTION SERVER — Phases 3–6                                    │
│   • Deploy step-ca Docker container                                │
│   • Issue service certificates (90-day validity)                   │
│   • systemd timer for auto-renewal                                 │
│   • Install Root CA on clients                                     │
│   • ONLINE only — no more offline sessions needed                  │
└────────────────────────────────────────────────────────────────────┘
```

**Why this sequence**: The Root key signs the Intermediate, so it must briefly come out of cold storage. But because the Intermediate key has to be born **on** the server (it will sign certificates there for years), the CSR-generation step happens online — forcing the two offline sessions to be split.

**After setup**: No further offline sessions needed for 5 years (until Intermediate renewal). See [ARCHITECTURE.md](ARCHITECTURE.md#why-two-offline-sessions) for the design rationale.

---

## 🎯 Phase Overview

| Phase | Task | Time | Criticality |
|-------|------|------|-------------|
| **1** | Create Root CA (offline) | 15 min | 🔴 CRITICAL |
| **2** | Create Intermediate CA | 20 min | 🔴 CRITICAL |
| **3** | Deploy step-ca Docker | 10 min | 🟠 HIGH |
| **4** | Request Service Cert | 10 min | 🟡 MEDIUM |
| **5** | Auto-Renewal Setup | 15 min | 🟠 HIGH |
| **6** | Client Trust Install | 5 min | 🟡 MEDIUM |

---

## Prerequisites

### On the production server

- Docker & Docker Compose
- OpenSSL 1.1.1+
- Root access

### On the air-gapped machine (Root CA creation)

- `step` CLI ≥ 0.25 — `brew install step` (macOS) or [smallstep.com/docs](https://smallstep.com/docs/step-cli/installation)
- `gpg` ≥ 2.2 — `brew install gnupg` (macOS) or `apt install gnupg` (Linux)
- `coreutils` (macOS only, for stronger `shred`) — `brew install coreutils`

> **macOS note — Brew PATH in non-login shells**: Homebrew installs to `/opt/homebrew/bin` (Apple Silicon) or `/usr/local/bin` (Intel). Non-login SSH sessions and cron jobs don't source `~/.zshrc`, so `step` / `gpg` won't be found unless you prepend the brew path:
> ```bash
> export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
> ```
> The shipped scripts in `scripts/` do this automatically.

### Recommended: use the provided scripts

This guide walks through the commands manually for transparency. If you'd rather use battle-tested scripts with built-in air-gap verification, decrypt-verification, and secure-delete cleanup, see [`scripts/README.md`](../scripts/README.md):

- `scripts/create-root-ca.sh` — replaces Phase 1 (manual commands below)
- `scripts/generate-intermediate-csr.sh` — replaces Phase 2 Steps 1–2
- `scripts/sign-intermediate-ca.sh` — replaces Phase 2 Step 3

---

## Phase 1: Create Root CA (Offline)

**IMPORTANT**: Create Root CA on an air-gapped machine for maximum security.

### Step 1: Generate Root CA Key

```bash
# Create secure directory
mkdir -p ~/step-ca-setup
cd ~/step-ca-setup
chmod 700 .

# Generate ECDSA P-384 key (higher security than P-256)
openssl ecparam -genkey -name secp384r1 -noout -out root_ca_key.pem
chmod 600 root_ca_key.pem
```

### Step 2: Create Root CA Certificate

⚠️ **IMPORTANT**: Replace the generic placeholder values below with your organization details!

```bash
# Create config
cat > root_ca.cnf << 'EOF'
[req]
distinguished_name = dn
x509_extensions = v3_ca
prompt = no

[dn]
CN = My Internal Root CA          # ← CHANGE THIS (e.g., "HomeLab Root CA 2026")
O = My Organization                # ← CHANGE THIS (e.g., "Your Company Name")
C = US                             # ← CHANGE THIS (e.g., "DE" for Germany)

[v3_ca]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:TRUE
keyUsage = critical, keyCertSign, cRLSign
EOF

# Generate self-signed Root CA (10 years)
openssl req -new -x509 \
    -key root_ca_key.pem \
    -sha384 \
    -days 3650 \
    -config root_ca.cnf \
    -out root_ca.crt
```

### Step 3: Encrypt Root CA Key

```bash
# Encrypt with GPG (AES-256)
gpg --symmetric --cipher-algo AES256 root_ca_key.pem

# Verify encrypted file exists
ls -lh root_ca_key.pem.gpg

# SECURELY DELETE unencrypted key
shred -vfz -n 10 root_ca_key.pem
```

### Step 4: Backup Root CA

Create **4 backups** (3-2-1 strategy):
1. Primary server (`/opt/step-ca/backups/`)
2. Secondary server (NAS, external drive)
3. Offline USB drive (locked safe)
4. Cloud backup (encrypted)

**Store GPG passphrase** in password manager (1Password, Bitwarden).

---

## Phase 2: Create Intermediate CA

### Step 1: Generate Intermediate Key

```bash
# On production server
mkdir -p /opt/step-ca/{certs,secrets,config,db}

# Set secure permissions FIRST
chmod 700 /opt/step-ca/secrets
chmod 700 /opt/step-ca/config

# Generate ECDSA P-256 key
openssl ecparam -genkey -name prime256v1 -noout \
    -out /opt/step-ca/secrets/intermediate_ca_key

chmod 600 /opt/step-ca/secrets/intermediate_ca_key
```

⚠️ **SECURITY WARNING**: The Intermediate CA private key is stored **unencrypted** on the production server. This is a design trade-off for automated certificate renewal. If the Docker container is compromised, ALL issued certificates are at risk.

**Mitigation Options**:
1. **GPG Encryption** (Manual): Encrypt key with GPG (requires manual decryption for renewal)
2. **Hardware Security Module (HSM)**: Store key in HSM (YubiKey, Nitrokey, AWS CloudHSM)
3. **Accept Risk**: For homelab/internal use, risk is acceptable with proper Docker security

For production environments, consider HSM integration or encrypt the Intermediate CA key and manually decrypt during renewals.

### Step 2: Create CSR

```bash
cat > /tmp/intermediate.cnf << 'EOF'
[req]
distinguished_name = dn
req_extensions = req_ext
prompt = no

[dn]
CN = My Internal Intermediate CA   # ← CHANGE THIS (must differ from Root CA CN)
O = My Organization                 # ← CHANGE THIS (should match Root CA)
C = US                              # ← CHANGE THIS (should match Root CA)

[req_ext]
basicConstraints = critical, CA:TRUE, pathlen:0
keyUsage = critical, keyCertSign, cRLSign
EOF

# Generate CSR
openssl req -new \
    -key /opt/step-ca/secrets/intermediate_ca_key \
    -config /tmp/intermediate.cnf \
    -out /tmp/intermediate.csr
```

### Step 3: Sign Intermediate with Root CA

**Transfer CSR to offline machine:**
```bash
# Copy intermediate.csr to offline machine
# Decrypt Root CA key:
gpg --decrypt root_ca_key.pem.gpg > root_ca_key.pem
```

**Sign CSR:**
```bash
cat > ext.cnf << 'EOF'
[v3_intermediate_ca]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:TRUE, pathlen:0
keyUsage = critical, keyCertSign, cRLSign
EOF

# Sign (5 years validity)
openssl x509 -req \
    -in intermediate.csr \
    -CA root_ca.crt \
    -CAkey root_ca_key.pem \
    -CAcreateserial \
    -out intermediate_ca.crt \
    -days 1825 \
    -sha256 \
    -extfile ext.cnf \
    -extensions v3_intermediate_ca

# Verify chain
openssl verify -CAfile root_ca.crt intermediate_ca.crt

# Re-encrypt Root CA key
shred -vfz -n 10 root_ca_key.pem
```

**Transfer signed certificate back** to production server.

**Verification**:
```bash
# Verify certificate chain is valid
openssl verify -CAfile root_ca.crt intermediate_ca.crt
# Expected: intermediate_ca.crt: OK

# Check certificate details
openssl x509 -in intermediate_ca.crt -noout -text | grep -A2 "Validity"
# Should show 5-year validity (1825 days)
```

---

## Phase 3: Deploy step-ca

> **Note**: The step-ca container is **optional** for the basic OpenSSL-based workflow described in Phase 4. The container provides:
> - **ACME protocol support** (certbot, acme.sh) for automated certificate requests
> - **Health endpoint** for monitoring (`/health`)
> - **Future extensibility** (API-based certificate management)
>
> If you only need manual certificate issuance via scripts, you can skip this phase. However, deploying the container enables easier migration to fully automated certificate management later.

### Step 1: Install Certificates

```bash
# Copy certificates to step-ca directory
cp intermediate_ca.crt /opt/step-ca/certs/
cp root_ca.crt /opt/step-ca/certs/

# Verify permissions
chmod 644 /opt/step-ca/certs/*.crt
chmod 600 /opt/step-ca/secrets/intermediate_ca_key
```

### Step 2: Create step-ca Configuration

```bash
cat > /opt/step-ca/config/ca.json << 'EOF'
{
  "root": "/home/step/certs/root_ca.crt",
  "crt": "/home/step/certs/intermediate_ca.crt",
  "key": "/home/step/secrets/intermediate_ca_key",
  "address": ":9443",
  "dnsNames": ["step-ca.internal", "localhost"],
  "logger": {"format": "text"},
  "db": {
    "type": "badger",
    "dataSource": "/home/step/db"
  },
  "authority": {
    "provisioners": [
      {
        "type": "ACME",
        "name": "acme"
      }
    ]
  }
}
EOF
```

**Note**: CRL configuration is omitted in this setup because certificates are signed via **Offline CA** (direct OpenSSL). step-ca cannot generate CRLs for certificates not registered in its database. For revocation, see `docs/ARCHITECTURE.md § Revocation Process`.

### Step 3: Create Password File (required even for unencrypted keys)

⚠️ **CRITICAL**: step-ca's startup expects a password file at `/home/step/secrets/password` to unlock the intermediate CA key. If the key is unencrypted (as in this guide), the file must still exist but can be empty. Otherwise the container restart-loops with:

```
error reading /home/step/secrets/password: open /home/step/secrets/password: no such file or directory
```

```bash
# Create empty password file (key is unencrypted)
sudo install -o 1000 -g 1000 -m 600 /dev/null /opt/step-ca/secrets/password

# OR: if you encrypted the intermediate key with a passphrase:
# echo -n 'your-passphrase' | sudo install -o 1000 -g 1000 -m 600 /dev/stdin /opt/step-ca/secrets/password
```

> **Security trade-off**: An unencrypted intermediate key with an empty password file means the key is protected only by filesystem permissions. For higher security, encrypt the intermediate key with `openssl ec -aes-256-cbc` and store the passphrase in the password file. See `docs/ARCHITECTURE.md § Security Boundaries`.

### Step 4: Deploy Docker Container

```bash
# Use provided docker-compose template
cp config/step-ca-stack.yml /opt/step-ca/

# Edit ports if needed (default: 9200 for HTTP-01, 9643 for HTTPS)

# Start container
cd /opt/step-ca
docker compose up -d

# Verify health
docker logs step-ca
curl -k https://localhost:9643/health
# Expected: {"status":"ok"}
```

---

## Phase 4: Request First Service Certificate

### Step 1: Customize Template

```bash
cp examples/cert-request-template.sh /tmp/myservice-cert.sh

# Edit variables (REPLACE with your actual service details):
# - SERVICE_NAME="myservice"           # ← CHANGE: e.g., "vaultwarden", "nextcloud"
# - DNS_SANS=("myservice.internal")    # ← CHANGE: e.g., "vault.example.com", "cloud.example.com"
# - IP_SANS=("10.0.0.2")               # ← CHANGE: Your service's IP address
```

**Example** (Vaultwarden):
```bash
SERVICE_NAME="vaultwarden"
DNS_SANS=("vault.homelab.internal" "vaultwarden.local")
IP_SANS=("192.168.1.50")
```

### Step 2: Run Request

```bash
sudo /tmp/myservice-cert.sh
```

**Output:**
- `/etc/ssl/step-ca/myservice.crt` - Certificate
- `/etc/ssl/step-ca/myservice.key` - Private key (chmod 600)
- `/etc/ssl/step-ca/myservice-fullchain.crt` - Full chain

**Verification**:
```bash
# Verify certificate was issued
openssl x509 -in /etc/ssl/step-ca/myservice.crt -noout -text | grep -A2 "Subject Alternative Name"
# Should show your DNS_SANS and IP_SANS

# Verify fullchain contains intermediate CA
grep -c "BEGIN CERTIFICATE" /etc/ssl/step-ca/myservice-fullchain.crt
# Expected: 2 (service cert + intermediate CA)

# Test with openssl verify
openssl verify -CAfile /opt/step-ca/certs/root_ca.crt \
    -untrusted /opt/step-ca/certs/intermediate_ca.crt \
    /etc/ssl/step-ca/myservice.crt
# Expected: /etc/ssl/step-ca/myservice.crt: OK
```

---

## Phase 5: Set Up Auto-Renewal

### Step 1: Install systemd Timer

```bash
# Copy templates (naming convention: step-ca-renew-<service>.*)
sudo cp systemd/step-ca-renew.service.template \
   /etc/systemd/system/step-ca-renew-myservice.service

sudo cp systemd/step-ca-renew.timer.template \
   /etc/systemd/system/step-ca-renew-myservice.timer
```

### Step 2: Configure Environment

Edit `/etc/systemd/system/step-ca-renew-myservice.service`:
```ini
[Service]
Environment="SERVICE_NAME=myservice"
Environment="SERVICE_RELOAD_CMD=systemctl reload nginx"
ExecStart=/usr/local/bin/renew-service-cert.sh
```

### Step 3: Enable Timer

```bash
# Install renewal script
cp renewal/renew-service-cert.sh /usr/local/bin/
chmod +x /usr/local/bin/renew-service-cert.sh

# Create SAN configuration file (required for auto-renewal)
cat > /etc/ssl/step-ca/myservice.san << EOF
DNS.1 = myservice.internal
IP.1 = 10.0.0.2
EOF

# Enable timer
sudo systemctl daemon-reload
sudo systemctl enable --now step-ca-renew-myservice.timer

# Verify
systemctl status step-ca-renew-myservice.timer
systemctl list-timers | grep step-ca-renew
```

**Verification**:
```bash
# Check timer is active and scheduled
systemctl list-timers step-ca-renew-myservice.timer
# Should show "NEXT" time (when it will run next)

# Manual trigger (WARNING: This will renew immediately if threshold is met!)
sudo systemctl start step-ca-renew-myservice.service
journalctl -u step-ca-renew-myservice.service -n 50
# Check logs for success

# Verify certificate was renewed (timestamp should be recent)
stat /etc/ssl/step-ca/myservice.crt
```

---

## Phase 6: Install Client Trust

### macOS

```bash
sudo security add-trusted-cert -d -r trustRoot \
    -k /Library/Keychains/System.keychain root_ca.crt
```

### Linux (Ubuntu/Debian)

```bash
sudo cp root_ca.crt /usr/local/share/ca-certificates/my-internal-ca.crt
sudo update-ca-certificates
```

### Windows (PowerShell Admin)

```powershell
Import-Certificate -FilePath root_ca.crt `
    -CertStoreLocation Cert:\LocalMachine\Root
```

See [CLIENT_TRUST.md](CLIENT_TRUST.md) for automation scripts.

---

## Verification

### Test Certificate Chain

```bash
openssl verify -CAfile /opt/step-ca/certs/root_ca.crt \
    -untrusted /opt/step-ca/certs/intermediate_ca.crt \
    /etc/ssl/step-ca/myservice.crt
# Expected: OK
```

### Test HTTPS

```bash
curl -v https://myservice.internal 2>&1 | grep "SSL certificate verify"
# Should show: SSL certificate verify ok
```

---

## Next Steps

1. **Set up Monitoring** - See [monitoring/README.md](../monitoring/README.md)
2. **Configure nginx** - See [NGINX_TLS.md](NGINX_TLS.md)
3. **Set up Backups** - See [BACKUP.md](BACKUP.md)
4. **Service Examples** - See `examples/` directory

---

**Estimated Time**: 75 minutes (45 min CA setup + 30 min first service)
