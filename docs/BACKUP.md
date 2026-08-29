# Backup and Disaster Recovery

How the PKI gets backed up along the **3-2-1 rule**, and how it comes back.

## ⚡ TL;DR

3-2-1 backup rule: Root CA GPG-encrypted and offline, Intermediate CA and step-ca database daily plus an offsite copy. Recovery procedures for three disaster scenarios below.

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

**Copy 1: USB Drive (encrypted, Linux-only access)**
```bash
# LUKS-encrypted USB drive — strongest option, but Linux-only
cryptsetup luksFormat /dev/sdX
cryptsetup open /dev/sdX root_ca_backup
mkfs.ext4 /dev/mapper/root_ca_backup
mount /dev/mapper/root_ca_backup /mnt/usb
cp root-ca-backup-*.tar.gz /mnt/usb/
umount /mnt/usb
cryptsetup close root_ca_backup
```

**Copy 1 alternative: USB Drive (exFAT, cross-platform)**

If the same USB stick must be readable from both Linux and macOS (e.g. signing on a Mac, restoring on a Linux server), prefer **exFAT** over LUKS. The backup file is already GPG-encrypted, so filesystem-level encryption is redundant.

```bash
# Linux — format USB as exFAT
sudo apt install exfatprogs
sudo wipefs -a /dev/sdX
sudo sgdisk --zap-all /dev/sdX
sudo sgdisk -n 1:0:0 -t 1:0700 -c 1:"PKI Backup" /dev/sdX
sudo mkfs.exfat -L "PKI-BACKUP" /dev/sdX1   # ⚠ Label max 11 chars (exFAT limit)
```

**Pitfalls:**
- **exFAT label limit is 11 characters** — `mkfs.exfat` errors out with `input string is too long` otherwise.
- **macOS creates `._<filename>` AppleDouble files** when writing to exFAT/FAT — harmless metadata sidecars, ignored by `step` / `openssl` / `gpg`. Don't confuse them with the real files.
- **exFAT has no Unix permissions** — `chmod`/`chown` are no-ops on the volume. The backup file itself is GPG-encrypted, so this is acceptable, but never use exFAT for storing unencrypted secrets.

**Copy 2: Paper Backup (for key recovery)**
```bash
# Base64 first: qrencode takes text, and a raw GPG blob is binary.
base64 < root_ca_key.pem.gpg > paper-backup.txt

# One QR code holds ~2.9 KB, so split. A GPG-wrapped EC key needs one or two parts.
split -b 1000 paper-backup.txt qr-part-
for f in qr-part-*; do qrencode -o "$f.png" -r "$f"; done

# Alternative: print the base64 text itself (no scanner needed to restore)
# Restore: cat the parts back together, then `base64 -d > root_ca_key.pem.gpg`
```

Verify the restore path on a scratch copy **before** the paper goes into the safe.
A paper backup nobody has ever read back is a photograph of a backup.

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
# One line only: multiple OnCalendar= entries add up, so "daily" plus "04:00"
# would run at midnight AND at 04:00.
OnCalendar=*-*-* 04:00:00
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

   # Test certificate issuance. There is no --dry-run flag; issue into /tmp
   # and delete afterwards.
   docker exec step-ca step ca certificate test.internal /tmp/test.crt /tmp/test.key
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
   # Check key matches public certificate. Use pkey, not rsa: both CA keys
   # are ECDSA (P-384 Root, P-256 Intermediate) and `openssl rsa` rejects them.
   openssl pkey -in root_ca_key.pem -pubout | sha256sum
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

2. **Fetch the CRL** (only meaningful if certificates were issued through the CA
   API; the OpenSSL workflow of this repository puts nothing in the database):
   ```bash
   # There is no `step ca crl` subcommand. step-ca serves the CRL over HTTP,
   # on the API port 9643, not on 9200 (HTTP-01 challenges only).
   curl -k https://localhost:9643/1.0/crl | openssl crl -inform DER -text -noout
   ```

3. **Verify the CA answers again**:
   ```bash
   curl -k https://localhost:9643/health   # {"status":"ok"}
   ```

---

## Backup Testing

### Monthly Restore Test

**Purpose**: Verify backups are actually restorable (many backups fail at restore time).

**Procedure**:

1. **Create test environment**:
   ```bash
   # Spin up test step-ca container
   # Same tag as production (config/step-ca-stack.yml), not :latest -
   # a restore test against a different version tests the wrong thing.
   docker run -d --name step-ca-test \
       -v /tmp/step-ca-test:/home/step \
       smallstep/step-ca:0.29.0
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

These are the backup practices an auditor would ask about, mapped to the control
they usually come up under. The requirements about cardholder data itself
(PCI DSS 3.x) are about PANs, not CA keys, and do not apply to this repository.

### PCI DSS

- 3.6 / 3.7 (key management): Root key generated offline, GPG-encrypted at rest, passphrase held by two people, documented rotation
- 4.2.1 (transmission): backups travel over rsync-in-SSH, never in the clear
- 9.4 (media): the Root CA USB stick lives in a locked safe, the offsite copy is encrypted before upload

### SOC 2

- CC6.1 (logical access): backup files `chmod 600`, directory `chmod 700`, root only
- CC6.7 (key handling): GPG passphrases in a password manager, separate passphrase for the offsite copy
- A1.2 (backup and recovery): 3-2-1 layout, monthly restore test, annual recovery drill

</details>

---

## Monitoring

### Backup Success Metrics

**Prometheus Alerts** (optional). Neither metric below is produced by
`monitoring/cert-exporter.sh`; a backup job that writes them to the textfile
collector is yours to add:

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
