# Client Trust Setup

Cross-platform Root CA installation for trusting internal step-ca certificates.

## ⚡ TL;DR

Root CA-Zertifikat auf allen Clients installieren für Trust Chain Validation. Linux: update-ca-certificates, macOS: Keychain, Windows: certutil, Browser: Extra-Config nötig.

---

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Quick Install by OS](#quick-install-by-os)
- [Linux](#linux)
- [macOS](#macos)
- [Windows](#windows)
- [Firefox](#firefox)
- [Docker Containers](#docker-containers)
- [Mobile Devices](#mobile-devices)
- [Application-Specific](#application-specific)
- [Automation](#automation)
- [Verification](#verification)
- [Troubleshooting](#troubleshooting)
- [Security Considerations](#security-considerations)
- [Further Reading](#further-reading)

---

## 🚀 Quick Install by OS

| OS | Command | Verification |
|----|---------|--------------|
| **Ubuntu/Debian** | `sudo cp root_ca.crt /usr/local/share/ca-certificates/ && sudo update-ca-certificates` | `openssl verify -CAfile /etc/ssl/certs/ca-certificates.crt service.crt` |
| **RHEL/CentOS** | `sudo cp root_ca.crt /etc/pki/ca-trust/source/anchors/ && sudo update-ca-trust` | `openssl verify service.crt` |
| **macOS** | `sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain root_ca.crt` | `security verify-cert -c service.crt` |
| **Windows** | `certutil -addstore -f "ROOT" root_ca.crt` | PowerShell: `Get-ChildItem Cert:\LocalMachine\Root \| Where {$_.Subject -like "*Root CA*"}` |
| **Firefox** | GUI: Settings → Certificates → Import | CLI: `certutil -A -n "step-ca Root CA" -t "C,," -d sql:$PROFILE -i root_ca.crt` |

---

## Overview

For clients (browsers, OS, applications) to trust certificates issued by your step-ca Intermediate CA, they must trust the **Root CA certificate** (`root_ca.crt`).

This guide covers installation on:
- Linux (Debian/Ubuntu, RHEL/CentOS, Arch)
- macOS
- Windows
- Firefox (uses own trust store)
- Docker containers
- Mobile (iOS, Android)

---

## Prerequisites

Obtain the Root CA certificate from your step-ca host:

```bash
# On step-ca host
cat /opt/step-ca/certs/root_ca.crt
```

Copy this certificate to the client machine (e.g., `/tmp/root_ca.crt`).

---

## Linux

### Debian/Ubuntu

```bash
# Install ca-certificates package (if not installed)
sudo apt update
sudo apt install ca-certificates

# Copy Root CA to trusted directory
sudo cp /tmp/root_ca.crt /usr/local/share/ca-certificates/step-ca-root.crt

# Update certificate store
sudo update-ca-certificates

# Verify
openssl verify -CAfile /etc/ssl/certs/ca-certificates.crt /tmp/service.crt
```

**Expected output**: `/tmp/service.crt: OK`

### RHEL/CentOS/Fedora

```bash
# Install ca-certificates package
sudo yum install ca-certificates
# OR for newer versions
sudo dnf install ca-certificates

# Copy Root CA to trusted directory
sudo cp /tmp/root_ca.crt /etc/pki/ca-trust/source/anchors/step-ca-root.crt

# Update certificate store
sudo update-ca-trust

# Verify
openssl verify -CAfile /etc/pki/tls/certs/ca-bundle.crt /tmp/service.crt
```

### Arch Linux

```bash
# Copy Root CA to trusted directory
sudo cp /tmp/root_ca.crt /etc/ca-certificates/trust-source/anchors/step-ca-root.crt

# Update certificate store
sudo trust extract-compat

# Verify
openssl verify -CAfile /etc/ssl/certs/ca-certificates.crt /tmp/service.crt
```

---

## macOS

### GUI Method (Keychain Access)

1. Double-click `root_ca.crt` → Opens **Keychain Access**
2. Certificate is added to **login** keychain
3. Double-click the certificate in Keychain Access
4. Expand **Trust** section
5. Set **When using this certificate** to **Always Trust**
6. Close window (prompts for password)

### Command Line Method

```bash
# Add to System keychain (requires admin password)
sudo security add-trusted-cert -d -r trustRoot \
    -k /Library/Keychains/System.keychain \
    /tmp/root_ca.crt

# Verify
security verify-cert -c /tmp/service.crt
```

**Expected output**: `...certificate verification successful.`

### Remove Root CA (if needed)

```bash
# Find certificate hash
security find-certificate -a -c "Your Root CA Name" -Z | grep SHA-1

# Delete by hash
sudo security delete-certificate -Z <SHA1_HASH> /Library/Keychains/System.keychain
```

---

## Windows

### GUI Method (certmgr.msc)

1. Press `Win + R`, type `certmgr.msc`, press Enter
2. Navigate to: **Trusted Root Certification Authorities** → **Certificates**
3. Right-click → **All Tasks** → **Import...**
4. Browse to `root_ca.crt`, click **Next**
5. Place certificate in: **Trusted Root Certification Authorities**
6. Click **Finish**

### PowerShell Method (Admin)

```powershell
# Import Root CA to Trusted Root store
Import-Certificate -FilePath "C:\temp\root_ca.crt" `
    -CertStoreLocation Cert:\LocalMachine\Root

# Verify
Get-ChildItem Cert:\LocalMachine\Root | Where-Object {$_.Subject -like "*Your Root CA*"}
```

### Command Prompt Method (Admin)

```cmd
certutil -addstore Root C:\temp\root_ca.crt
```

### Remove Root CA (if needed)

```powershell
# List certificates
Get-ChildItem Cert:\LocalMachine\Root | Where-Object {$_.Subject -like "*Your Root CA*"}

# Remove by thumbprint
Remove-Item -Path Cert:\LocalMachine\Root\<THUMBPRINT>
```

---

## Firefox

**Firefox uses its own trust store** (ignores OS trust store).

### GUI Method

1. Open **Firefox** → **Settings** → **Privacy & Security**
2. Scroll to **Certificates** → Click **View Certificates...**
3. Click **Authorities** tab
4. Click **Import...**
5. Select `root_ca.crt`
6. Check **Trust this CA to identify websites**
7. Click **OK**

### Command Line Method (certutil)

**Linux/macOS**:

```bash
# Install NSS tools (if not installed)
sudo apt install libnss3-tools  # Debian/Ubuntu
# OR
brew install nss  # macOS

# Find Firefox profile directory
FIREFOX_PROFILE=$(find ~/.mozilla/firefox -name "*.default-release" | head -1)

# Import Root CA
certutil -A -n "step-ca Root CA" -t "C,," \
    -d sql:"$FIREFOX_PROFILE" -i /tmp/root_ca.crt

# Verify
certutil -L -d sql:"$FIREFOX_PROFILE"
```

**Windows**:

```powershell
# Find Firefox profile directory
$PROFILE = Get-ChildItem "$env:APPDATA\Mozilla\Firefox\Profiles" | Where-Object {$_.Name -like "*.default-release"} | Select-Object -First 1

# Import Root CA (requires certutil from NSS, included with Firefox)
& "C:\Program Files\Mozilla Firefox\certutil.exe" -A -n "step-ca Root CA" -t "C,," `
    -d sql:$PROFILE.FullName -i C:\temp\root_ca.crt
```

---

## Docker Containers

### Method 1: Bake into Image

**Dockerfile**:

```dockerfile
FROM ubuntu:22.04

# Copy Root CA
COPY root_ca.crt /usr/local/share/ca-certificates/step-ca-root.crt

# Update certificate store
RUN apt-get update && \
    apt-get install -y ca-certificates && \
    update-ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Your application setup
CMD ["your-app"]
```

### Method 2: Volume Mount (Runtime)

**docker-compose.yml**:

```yaml
services:
  app:
    image: your-app:latest
    volumes:
      - /etc/ssl/certs:/etc/ssl/certs:ro  # Mount host's trust store
    environment:
      - SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
```

### Method 3: Update at Runtime

**Entrypoint script**:

```bash
#!/bin/bash
# entrypoint.sh

# Copy Root CA (if not already present)
if [ ! -f /usr/local/share/ca-certificates/step-ca-root.crt ]; then
    cp /mnt/config/root_ca.crt /usr/local/share/ca-certificates/step-ca-root.crt
    update-ca-certificates
fi

# Start application
exec "$@"
```

---

## Mobile Devices

### iOS

1. **AirDrop** or **email** `root_ca.crt` to iPhone/iPad
2. Tap the file → **Install Profile**
3. Enter device passcode
4. Go to **Settings** → **General** → **About** → **Certificate Trust Settings**
5. Enable **Full Trust** for the Root CA

**Security Note**: iOS warns that this allows the CA to intercept traffic (expected behavior).

### Android

1. **Transfer** `root_ca.crt` to device (USB, email, cloud)
2. Open **Settings** → **Security** → **Encryption & Credentials**
3. Tap **Install a certificate** → **CA certificate**
4. Select `root_ca.crt`
5. Enter device PIN/password

**Android 7+**: User-installed CAs only trusted by apps that opt-in (add `network_security_config.xml`).

---

## Application-Specific

### curl

```bash
# Specify CA bundle
curl --cacert /path/to/root_ca.crt https://service.internal

# Add to curl's default CA bundle
cat /tmp/root_ca.crt >> /etc/ssl/certs/ca-certificates.crt
```

### Python (requests library)

```python
import requests

# Method 1: Per-request
response = requests.get('https://service.internal', verify='/path/to/root_ca.crt')

# Method 2: Set environment variable
import os
os.environ['REQUESTS_CA_BUNDLE'] = '/path/to/root_ca.crt'
response = requests.get('https://service.internal')

# Method 3: Use system trust store
# (works if Root CA installed via update-ca-certificates)
response = requests.get('https://service.internal')
```

### Node.js

```javascript
// Method 1: Set environment variable
process.env.NODE_EXTRA_CA_CERTS = '/path/to/root_ca.crt';

// Method 2: Use https module
const https = require('https');
const fs = require('fs');

const agent = new https.Agent({
    ca: fs.readFileSync('/path/to/root_ca.crt')
});

https.get('https://service.internal', { agent }, (res) => {
    console.log('Status:', res.statusCode);
});
```

### Java

```bash
# Import into Java keystore (requires admin)
sudo keytool -import -trustcacerts -alias step-ca-root \
    -file /tmp/root_ca.crt \
    -keystore $JAVA_HOME/lib/security/cacerts \
    -storepass changeit

# Verify
keytool -list -keystore $JAVA_HOME/lib/security/cacerts | grep step-ca
```

### Git

```bash
# Add Root CA to Git's CA bundle
git config --global http.sslCAInfo /path/to/root_ca.crt

# OR append to system bundle
cat /tmp/root_ca.crt >> /etc/ssl/certs/ca-certificates.crt
```

---

<details>
<summary>🔧 Automation (Ansible, Puppet, Chef) - Click to expand</summary>

## Automation

### Ansible Playbook

**playbook.yml**:

```yaml
---
- hosts: all
  become: yes
  tasks:
    - name: Copy Root CA certificate
      copy:
        src: files/root_ca.crt
        dest: /usr/local/share/ca-certificates/step-ca-root.crt
        mode: '0644'

    - name: Update CA certificates (Debian/Ubuntu)
      command: update-ca-certificates
      when: ansible_os_family == "Debian"

    - name: Update CA certificates (RHEL/CentOS)
      command: update-ca-trust
      when: ansible_os_family == "RedHat"
```

### Puppet Module

```puppet
file { '/usr/local/share/ca-certificates/step-ca-root.crt':
  ensure => file,
  source => 'puppet:///modules/pki/root_ca.crt',
  mode   => '0644',
  notify => Exec['update-ca-certificates'],
}

exec { 'update-ca-certificates':
  command     => '/usr/sbin/update-ca-certificates',
  refreshonly => true,
}
```

### Chef Recipe

```ruby
cookbook_file '/usr/local/share/ca-certificates/step-ca-root.crt' do
  source 'root_ca.crt'
  mode '0644'
  notifies :run, 'execute[update-ca-certificates]', :immediately
end

execute 'update-ca-certificates' do
  command '/usr/sbin/update-ca-certificates'
  action :nothing
end
```

</details>

---

## Verification

### Browser Test

1. Navigate to `https://service.internal` (or any service using step-ca cert)
2. Click **padlock** icon → **Certificate**
3. Verify:
   - **Issued to**: `service.internal`
   - **Issued by**: `Your Intermediate CA`
   - **Valid**: Yes (no warnings)

### OpenSSL CLI

```bash
# Verify certificate chain
openssl verify -CAfile /path/to/root_ca.crt /tmp/service.crt

# Expected: /tmp/service.crt: OK
```

### curl Test

```bash
curl -v https://service.internal

# Look for:
# * SSL connection using TLSv1.3 / TLS_AES_256_GCM_SHA384
# * Server certificate:
# *  subject: CN=service.internal
# *  issuer: CN=Your Intermediate CA
# * SSL certificate verify ok.
```

---

## Troubleshooting

### "Certificate not trusted" despite installation

**Cause**: Root CA installed in wrong location, or update command not run.

**Fix**:
```bash
# Debian/Ubuntu
sudo update-ca-certificates --fresh

# RHEL/CentOS
sudo update-ca-trust force-enable
sudo update-ca-trust extract
```

### Firefox still shows warning

**Cause**: Firefox uses NSS database, not OS trust store.

**Fix**: Install Root CA specifically in Firefox (see [Firefox section](#firefox)).

### Docker container can't verify certificates

**Cause**: Container doesn't have Root CA in its trust store.

**Fix**: Bake Root CA into image (see [Docker Containers](#docker-containers)).

### Intermediate CA shown as untrusted

**Cause**: nginx serving leaf certificate only (not fullchain).

**Fix**: Use `service-fullchain.crt` instead of `service.crt`:

```nginx
ssl_certificate /etc/ssl/step-ca/service-fullchain.crt;  # ← fullchain
ssl_certificate_key /etc/ssl/step-ca/service.key;
```

---

## Security Considerations

### Trust Anchor Protection

- ✅ Root CA certificate is **public** (not secret)
- ✅ Root CA **private key** must remain offline (see [BACKUP.md](BACKUP.md))
- ❌ Never distribute Root CA private key (`root_ca_key.pem`)

### Client-Side Risk

Installing a Root CA means:
- ✅ Trust internal services (expected)
- ⚠️ Could intercept traffic **if private key compromised**

**Mitigation**:
- Offline Root CA (air-gapped, never online)
- GPG-encrypted Root CA key
- Multi-person authorization for key usage

### Revocation

If Root CA is compromised:
1. Notify all clients to **remove** Root CA from trust stores
2. Generate new Root CA (entirely new key pair)
3. Redistribute new Root CA

**Timeline**: 1-2 weeks for full fleet update.

---

## Further Reading

- [ARCHITECTURE.md](ARCHITECTURE.md#trust-anchor-distribution) - Trust anchor design
- [NGINX_TLS.md](NGINX_TLS.md) - TLS termination with step-ca certs
- [Mozilla NSS Tools](https://developer.mozilla.org/en-US/docs/Mozilla/Projects/NSS/tools) - Firefox certificate management
- [Docker TLS Documentation](https://docs.docker.com/engine/security/certificates/) - Docker certificate configuration
