# Backup and Disaster Recovery

Comprehensive backup strategy for step-ca PKI infrastructure following the **3-2-1 rule**.

## ⚡ TL;DR

3-2-1 Backup-Regel: Root CA GPG-verschlüsselt offline, Intermediate täglich + offsite, step-ca DB alle 6h. Recovery-Prozeduren für 3 Disaster-Szenarien dokumentiert.

---

## Table of Contents

- [3-2-1 Backup Rule](#3-2-1-backup-rule)
- [Critical Files](#critical-files)
- [Backup Methods](#backup-methods)
- [Recovery Procedures](#recovery-procedures)
- [Backup Testing](#backup-testing)
- [Backup Security](#backup-security)
- [Compliance Checklists](#compliance-checklists)
- [Monitoring](#monitoring)
- [Further Reading](#further-reading)

---

## 🔄 Quick Recovery Commands

| Scenario | Command | Time |
|----------|---------|------|
| **Intermediate CA Loss** | `tar xzf /opt/backups/step-ca/latest.tar.gz -C /opt/step-ca && docker restart step-ca` | 10 min |
| **Database Corruption** | `rm -rf /opt/step-ca/db/* && tar xzf backup.tar.gz -C /opt/step-ca db/` | 5 min |
| **Root CA Recovery** | `gpg --decrypt root_ca_key.pem.gpg > root_ca_key.pem` | 2 min |

---

## 3-2-1 Backup Rule

The industry-standard backup strategy:

- **3** copies of data (1 primary + 2 backups)
- **2** different media types (e.g., disk + cloud, or SSD + HDD)
- **1** offsite copy (physical location or cloud)

---

## Critical Files

### Root CA (Highest Priority)

| File | Location | Sensitivity | Backup Frequency |
|------|----------|-------------|------------------|
| `root_ca_key.pem` | Offline machine | **CRITICAL** | After generation, never online |
| `root_ca.crt` | `/opt/step-ca/certs/` | Public | After generation |
| GPG-encrypted key | `root_ca_key.pem.gpg` | **CRITICAL** | Multiple copies (USB, paper backup) |

**Recovery Impact**: Loss = Complete PKI rebuild, all clients must update trust anchor.

### Intermediate CA (High Priority)

| File | Location | Sensitivity | Backup Frequency |
|------|----------|-------------|------------------|
| `intermediate_ca_key` | `/opt/step-ca/secrets/` | **HIGH** | Daily |
| `intermediate_ca.crt` | `/opt/step-ca/certs/` | Public | After generation |
| `ca.json` | `/opt/step-ca/config/` | Medium | Daily |

**Recovery Impact**: Loss = Reissue from Root CA (30-60 min downtime).

### step-ca Database

| File | Location | Purpose | Backup Frequency |
|------|----------|---------|------------------|
| `db/` directory | `/opt/step-ca/db/` | Issued certificate records | Daily |

**Recovery Impact**: Loss = Lose revocation/renewal history (CRL must be rebuilt).

### Service Certificates (Low Priority)

| File | Location | Sensitivity | Backup Frequency |
|------|----------|-------------|------------------|
| Service certs/keys | `/etc/ssl/step-ca/` | Medium | Optional (can reissue) |

**Recovery Impact**: Loss = Reissue certificates (automated via renewal scripts).

---

## Backup Methods

### 1. Root CA Backup (Manual, Offline)

#### Initial Backup (After Root CA Generation)

```bash
# On air-gapped machine
cd /path/to/root-ca

# Create GPG-encrypted backup
gpg --symmetric --cipher-algo AES256 root_ca_key.pem
# Output: root_ca_key.pem.gpg

# Verify encryption
gpg --decrypt root_ca_key.pem.gpg > /dev/null
# Should prompt for passphrase

# Create tarball with all Root CA materials
tar czf root-ca-backup-$(date +%Y%m%d).tar.gz \
    root_ca_key.pem.gpg \
    root_ca.crt \
    root_ca_metadata.txt

# Calculate checksums
sha256sum root-ca-backup-*.tar.gz > checksums.txt
```

#### Storage Locations

**Copy 1: USB Drive (encrypted)**
```bash
# LUKS-encrypted USB drive
cryptsetup luksFormat /dev/sdX
cryptsetup open /dev/sdX root_ca_backup
mkfs.ext4 /dev/mapper/root_ca_backup
mount /dev/mapper/root_ca_backup /mnt/usb
cp root-ca-backup-*.tar.gz /mnt/usb/
umount /mnt/usb
cryptsetup close root_ca_backup
```

**Copy 2: Paper Backup (for key recovery)**
```bash
# Generate QR code of GPG-encrypted key (split into chunks)
qrencode -o root_ca_qr.png < root_ca_key.pem.gpg

# Alternative: Print hexdump (tedious but works)
xxd root_ca_key.pem.gpg > root_ca_hex.txt
# Store in bank safe deposit box
```

**Copy 3: Offsite (Encrypted Cloud) - RECOMMENDED**

⚠️ **3-2-1 Rule Compliance**: Offsite backup is **NOT optional** for production PKI. Without offsite storage, you violate the "1 offsite copy" principle, leaving you vulnerable to:
- Fire, flood, theft at primary location
- Ransomware encrypting all local backups
- Hardware failure of both primary and local backup drives

```bash
# Encrypt again with different passphrase (defense in depth)
gpg --symmetric --cipher-algo AES256 root-ca-backup-*.tar.gz

# Upload to cloud (after verification of 2FA, zero-knowledge provider)
# Examples: Sync.com, Tresorit, ProtonDrive
rclone copy root-ca-backup-*.tar.gz.gpg offsite-cloud:/pki-backups/
```

**Recommendation**: Treat cloud backup as **mandatory** for production, **recommended** for homelab.

### 2. Intermediate CA Backup (Automated, Daily)

#### Backup Script

Create `/usr/local/bin/backup-step-ca.sh`:

```bash
#!/bin/bash
set -euo pipefail

BACKUP_DIR="/opt/backups/step-ca"
STEP_CA_HOME="/opt/step-ca"
DATE=$(date +%Y%m%d_%H%M%S)
RETENTION_DAYS=30

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Stop step-ca briefly (optional, for consistency)
# docker stop step-ca

# Backup critical files
tar czf "$BACKUP_DIR/step-ca-backup-$DATE.tar.gz" \
    -C "$STEP_CA_HOME" \
    secrets/ \
    config/ \
    db/ \
    certs/

# Restart step-ca
# docker start step-ca

# Calculate checksum
sha256sum "$BACKUP_DIR/step-ca-backup-$DATE.tar.gz" > \
    "$BACKUP_DIR/step-ca-backup-$DATE.sha256"

# Remove old backups
find "$BACKUP_DIR" -name "step-ca-backup-*.tar.gz" -mtime +$RETENTION_DAYS -delete
find "$BACKUP_DIR" -name "step-ca-backup-*.sha256" -mtime +$RETENTION_DAYS -delete

echo "[$(date)] step-ca backup completed: $BACKUP_DIR/step-ca-backup-$DATE.tar.gz"
```

#### systemd Timer

Create `/etc/systemd/system/step-ca-backup.service`:

```ini
[Unit]
Description=step-ca Daily Backup
After=docker.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/backup-step-ca.sh
User=root
```

Create `/etc/systemd/system/step-ca-backup.timer`:

```ini
[Unit]
Description=step-ca Daily Backup Timer

[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true

[Install]
WantedBy=timers.target
```

Enable timer:
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now step-ca-backup.timer
```

### 3. Offsite Replication (rsync)

#### Backup to Remote Host

```bash
# On step-ca host, create rsync job
cat > /usr/local/bin/rsync-step-ca-offsite.sh << 'EOF'
#!/bin/bash
set -euo pipefail

LOCAL_BACKUP="/opt/backups/step-ca"
REMOTE_HOST="backup.example.com"
REMOTE_PATH="/backups/step-ca"

# Sync to remote (SSH key-based auth)
rsync -avz --delete-after \
    "$LOCAL_BACKUP/" \
    "$REMOTE_HOST:$REMOTE_PATH/"

echo "[$(date)] Offsite sync completed"
EOF

chmod +x /usr/local/bin/rsync-step-ca-offsite.sh
```

#### systemd Timer (Daily, after local backup)

Create `/etc/systemd/system/step-ca-offsite-sync.service`:

```ini
[Unit]
Description=step-ca Offsite Backup Sync
After=step-ca-backup.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/rsync-step-ca-offsite.sh
User=root
```

Create `/etc/systemd/system/step-ca-offsite-sync.timer`:

```ini
[Unit]
Description=step-ca Offsite Sync Timer

[Timer]
OnCalendar=daily
OnCalendar=04:00
Persistent=true

[Install]
WantedBy=timers.target
```

### 4. Cloud Backup (Optional)

#### Using Restic (Encrypted, Deduplicated)

```bash
# Install restic
apt install restic

# Initialize repository (one-time)
export RESTIC_PASSWORD="<strong-passphrase>"
restic -r /path/to/backup/repo init

# Backup step-ca
restic -r /path/to/backup/repo backup /opt/step-ca

# Restore from backup
restic -r /path/to/backup/repo restore latest --target /opt/step-ca-restore
```

---

## Recovery Procedures

### Scenario 1: Intermediate CA Loss (step-ca host failure)

**Symptoms**: step-ca container won't start, `/opt/step-ca/secrets/` corrupted/missing.

**Recovery Steps**:

1. **Restore from backup**:
   ```bash
   # Stop step-ca
   docker stop step-ca

   # Restore latest backup
   cd /opt/backups/step-ca
   LATEST_BACKUP=$(ls -t step-ca-backup-*.tar.gz | head -1)
   tar xzf "$LATEST_BACKUP" -C /opt/step-ca

   # Verify checksum
   sha256sum -c "${LATEST_BACKUP%.tar.gz}.sha256"

   # Fix permissions
   chown -R 1000:1000 /opt/step-ca/secrets /opt/step-ca/db

   # Restart step-ca
   docker start step-ca
   ```

2. **Verify functionality**:
   ```bash
   # Check health
   curl -k https://localhost:9643/health

   # Test certificate issuance (dry-run)
   docker exec step-ca step ca certificate test.internal test.crt test.key --dry-run
   ```

3. **Monitor services**:
   ```bash
   # Check existing service certificates still valid
   openssl x509 -in /etc/ssl/step-ca/service.crt -noout -dates
   ```

**Downtime**: 10-15 minutes (existing certs continue working).

### Scenario 2: Root CA Loss (disaster)

**Symptoms**: Offline Root CA machine lost/destroyed, no backup accessible.

**Recovery Steps** (if paper backup exists):

1. **Reconstruct Root CA key**:
   ```bash
   # If QR code backup
   zbarimg --raw root_ca_qr.png > root_ca_key.pem.gpg
   gpg --decrypt root_ca_key.pem.gpg > root_ca_key.pem

   # If hexdump backup
   xxd -r root_ca_hex.txt > root_ca_key.pem.gpg
   gpg --decrypt root_ca_key.pem.gpg > root_ca_key.pem
   ```

2. **Verify key integrity**:
   ```bash
   # Check key matches public certificate
   openssl rsa -in root_ca_key.pem -pubout | sha256sum
   openssl x509 -in root_ca.crt -pubkey -noout | sha256sum
   # Checksums must match
   ```

3. **Resume operations** (Root CA restored).

**Recovery Steps** (if NO backup exists):

1. **Accept total PKI rebuild**:
   - Generate entirely new Root CA
   - Reissue Intermediate CA
   - Reissue all service certificates
   - Redistribute new Root CA to **all clients** (browsers, OS trust stores)

2. **Communication**:
   - Notify all users: "Update trust anchor by [DATE]"
   - Provide installation scripts (see [CLIENT_TRUST.md](CLIENT_TRUST.md))

3. **Timeline**: 4-8 hours work + client updates over 1-2 weeks.

**Prevention**: **NEVER** skip Root CA backup. Use 3-2-1 rule religiously.

### Scenario 3: Database Corruption (step-ca db/ errors)

**Symptoms**: step-ca logs show BadgerDB errors, CRL generation fails.

**Recovery Steps**:

1. **Restore database from backup**:
   ```bash
   docker stop step-ca
   rm -rf /opt/step-ca/db/*
   tar xzf /opt/backups/step-ca/step-ca-backup-<DATE>.tar.gz -C /opt/step-ca db/
   chown -R 1000:1000 /opt/step-ca/db
   docker start step-ca
   ```

2. **Rebuild CRL**:
   ```bash
   # Regenerate CRL from database
   docker exec step-ca step ca crl > /opt/step-ca/crl/current.crl
   ```

3. **Verify**:
   ```bash
   # Note: CRL endpoint not applicable for Offline CA design
   # (certificates signed via OpenSSL are not in step-ca database)
   # For manual CRL generation, see docs/ARCHITECTURE.md § Revocation Process
   #
   # If using step-ca API-based CA (certificates in database):
   # Use Admin API port 9643 for CRL, NOT port 9200 (HTTP-01 challenges only)
   # curl -k https://localhost:9643/1.0/crl | openssl crl -inform DER -text -noout
   ```

---

## Backup Testing

### Monthly Restore Test

**Purpose**: Verify backups are actually restorable (many backups fail at restore time).

**Procedure**:

1. **Create test environment**:
   ```bash
   # Spin up test step-ca container
   docker run -d --name step-ca-test \
       -v /tmp/step-ca-test:/home/step \
       smallstep/step-ca:latest
   ```

2. **Restore backup to test environment**:
   ```bash
   cd /opt/backups/step-ca
   LATEST_BACKUP=$(ls -t step-ca-backup-*.tar.gz | head -1)
   tar xzf "$LATEST_BACKUP" -C /tmp/step-ca-test
   ```

3. **Verify restored CA works**:
   ```bash
   docker exec step-ca-test step ca health
   docker exec step-ca-test step ca certificate test.internal test.crt test.key
   ```

4. **Cleanup**:
   ```bash
   docker stop step-ca-test
   docker rm step-ca-test
   rm -rf /tmp/step-ca-test
   ```

5. **Document results**:
   ```bash
   echo "[$(date)] Backup restore test: SUCCESS" >> /var/log/step-ca-backup-tests.log
   ```

### Annual Disaster Recovery Drill

**Purpose**: Practice full recovery from Root CA backup (muscle memory for actual disaster).

**Procedure**:

1. Schedule 2-hour downtime window
2. Shut down production step-ca
3. Restore Root CA from USB backup (decrypt, verify)
4. Restore Intermediate CA from latest backup
5. Restart step-ca, verify all services
6. Document lessons learned, update procedures

---

## Backup Security

### Encryption at Rest

- ✅ Root CA key: GPG-encrypted with AES-256
- ✅ Intermediate CA backups: Encrypted filesystem (LUKS, VeraCrypt)
- ✅ Cloud backups: Client-side encryption (Restic, rclone crypt)

### Access Control

- ✅ Backup files: `chmod 600` (root only)
- ✅ Backup directory: `chmod 700` (root only)
- ✅ Offsite credentials: Stored in password manager (Vaultwarden, Bitwarden)

### Passphrase Management

**Root CA GPG passphrase**:
- ✅ 20+ characters, generated randomly
- ✅ Stored in password manager (Vaultwarden)
- ✅ Written on paper, stored in bank safe deposit box
- ✅ Known by 2+ trusted individuals (bus factor)

**Backup encryption passphrase** (if different from GPG):
- ✅ Separate from Root CA passphrase (defense in depth)
- ✅ Rotated annually

---

<details>
<summary>📋 Compliance Checklists (PCI DSS, SOC 2) - Click to expand</summary>

## Compliance Checklists

### PCI DSS Requirements

- ✅ 3.1: Minimize cardholder data retention → Root CA key offline, never on network
- ✅ 3.4: Render PAN unreadable → GPG encryption for Root CA key
- ✅ 3.5.2: Encrypted transmission → TLS for backup transfers (rsync over SSH)
- ✅ 9.1: Physical access controls → Root CA USB in locked safe

### SOC 2 Controls

- ✅ CC6.1: Logical access → Backups readable only by root
- ✅ CC6.7: Encryption keys → GPG passphrases in password manager
- ✅ A1.2: Backup and recovery → 3-2-1 rule, monthly restore tests

</details>

---

## Monitoring

### Backup Success Metrics

**Prometheus Alerts** (optional):

```yaml
- alert: StepCABackupFailed
  expr: time() - step_ca_backup_last_success_timestamp > 86400 * 2
  for: 1h
  labels:
    severity: critical
  annotations:
    summary: "step-ca backup has not succeeded in 2 days"

- alert: StepCABackupSize
  expr: step_ca_backup_size_bytes < 1000000
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "step-ca backup size suspiciously small (<1MB)"
```

**Log Monitoring**:
```bash
# Check recent backup success
journalctl -u step-ca-backup.service --since "24 hours ago" | grep -i success
```

---

## Further Reading

- [ARCHITECTURE.md](ARCHITECTURE.md#disaster-recovery) - Disaster recovery architecture
- [Restic Documentation](https://restic.readthedocs.io/) - Modern backup tool
- [Borg Backup](https://www.borgbackup.org/) - Deduplicating backup alternative
- [NIST 800-53 CP-9](https://nvd.nist.gov/800-53/Rev4/control/CP-9) - Information System Backup control
