# Certificate Renewal

Automatic certificate renewal scripts for step-ca issued certificates.

## Directory Structure

```
renewal/
└── renew-service-cert.sh    # Auto-renewal script for service certificates
```

## Files

| File | Description | Usage |
|------|-------------|-------|
| `renew-service-cert.sh` | Auto-renew service certificates | `./renew-service-cert.sh` |

## Quick Start

```bash
# Show help and usage
./renew-service-cert.sh --help

# Run renewal check (requires root for service reload)
sudo SERVICE_NAME=myservice ./renew-service-cert.sh

# Renew immediately, bypassing the threshold
# (e.g. after adding SANs to the .san file)
sudo SERVICE_NAME=myservice ./renew-service-cert.sh --force

# Configure via systemd timer (recommended)
# See ../systemd/ for templates
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `STEP_CA_HOME` | `/opt/step-ca` | step-ca installation directory |
| `STEP_CA_CERT_DIR` | `/etc/ssl/step-ca` | Certificate storage directory |
| `SERVICE_NAME` | `service` | Service identifier |
| `RENEWAL_THRESHOLD` | `30` | Days before expiry to renew |
| `SERVICE_RELOAD_CMD` | `systemctl reload nginx` | Command to reload service |

## Workflow

1. **Check Expiry**: Script checks certificate expiry date
2. **Threshold**: If expiry < `RENEWAL_THRESHOLD` days (or `--force`), renewal triggers
3. **Request**: New key + CSR generated, SANs loaded from `<SERVICE_NAME>.san` (single source)
4. **Sign**: flock-protected signing with the Intermediate CA
5. **Verify**: Public-key match (cert ↔ new key) + full chain verification
6. **Deploy**: Atomic staging + `mv` into `STEP_CA_CERT_DIR` (with `.bak` rollback)
7. **Reload**: `SERVICE_RELOAD_CMD` executes to apply the new certificate (rollback on failure)

**Changing SANs**: Edit `${STEP_CA_CERT_DIR}/${SERVICE_NAME}.san`, then run once
with `--force` — the next timer run alone would not re-issue until the threshold.

**Failure visibility**: Renewals run unattended — wire up
`../systemd/step-ca-renew-failure-notify.service.template` via `OnFailure=`
so a failed nightly run notifies you instead of surfacing as a browser
warning weeks later.

## Integration with systemd

For automated daily checks, use the systemd templates:

```bash
# Copy templates
sudo cp ../systemd/step-ca-renew.service.template /etc/systemd/system/myservice-renew.service
sudo cp ../systemd/step-ca-renew.timer.template /etc/systemd/system/myservice-renew.timer

# Edit service file with your settings
sudo systemctl edit myservice-renew.service

# Enable timer
sudo systemctl daemon-reload
sudo systemctl enable --now myservice-renew.timer
```

## Requirements

- **OpenSSL**: For certificate operations
- **Root access**: For service reload
- **Intermediate CA**: Must be available for signing

## See Also

- [← Back to Root](../README.md)
- [systemd Templates](../systemd/)
- [Setup Guide](../docs/SETUP.md)
