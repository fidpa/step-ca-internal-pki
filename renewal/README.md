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
2. **Threshold**: If expiry < `RENEWAL_THRESHOLD` days, renewal triggers
3. **Request**: New certificate requested from Intermediate CA
4. **Deploy**: Certificate placed in `STEP_CA_CERT_DIR`
5. **Reload**: `SERVICE_RELOAD_CMD` executes to apply new certificate

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
