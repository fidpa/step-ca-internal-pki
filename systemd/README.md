# systemd Units

systemd service and timer templates for automatic certificate renewal.

## Directory Structure

```
systemd/
├── step-ca-renew.service.template    # Service unit template
└── step-ca-renew.timer.template      # Timer unit template
```

## Files

| File | Type | Description |
|------|------|-------------|
| `step-ca-renew.service.template` | Service | Renewal service template |
| `step-ca-renew.timer.template` | Timer | Daily execution timer |

## Quick Install

```bash
# Copy templates for your service (naming convention: step-ca-renew-<service>.*)
sudo cp step-ca-renew.service.template /etc/systemd/system/step-ca-renew-myservice.service
sudo cp step-ca-renew.timer.template /etc/systemd/system/step-ca-renew-myservice.timer

# Edit service file
sudo nano /etc/systemd/system/step-ca-renew-myservice.service
# Set: SERVICE_NAME, SERVICE_RELOAD_CMD

# Reload and enable
sudo systemctl daemon-reload
sudo systemctl enable --now step-ca-renew-myservice.timer

# Verify
systemctl list-timers | grep step-ca-renew
```

## Template Reference

### step-ca-renew.service.template

Key settings to customize:

```ini
[Service]
# Set your service name
Environment="SERVICE_NAME=myservice"

# Set reload command for your service
Environment="SERVICE_RELOAD_CMD=systemctl reload nginx"

# Optional: Custom paths
Environment="STEP_CA_HOME=/opt/step-ca"
Environment="STEP_CA_CERT_DIR=/etc/ssl/step-ca"
Environment="RENEWAL_THRESHOLD=30"
```

### step-ca-renew.timer.template

Default schedule: Daily at a random time

```ini
[Timer]
OnCalendar=daily
RandomizedDelaySec=3600
Persistent=true
```

## Multiple Services

For multiple services, create separate unit files:

```bash
# Service 1: Vaultwarden
sudo cp step-ca-renew.service.template /etc/systemd/system/step-ca-renew-vaultwarden.service
sudo cp step-ca-renew.timer.template /etc/systemd/system/step-ca-renew-vaultwarden.timer

# Service 2: Nextcloud
sudo cp step-ca-renew.service.template /etc/systemd/system/step-ca-renew-nextcloud.service
sudo cp step-ca-renew.timer.template /etc/systemd/system/step-ca-renew-nextcloud.timer

# Enable all timers
sudo systemctl enable --now step-ca-renew-vaultwarden.timer step-ca-renew-nextcloud.timer
```

## Monitoring

```bash
# Check timer status
systemctl list-timers --all | grep step-ca-renew

# Check last run
journalctl -u step-ca-renew-myservice.service -n 50

# Manual trigger (WARNING: This will renew immediately if threshold is met!)
sudo systemctl start step-ca-renew-myservice.service
```

## Troubleshooting

**Timer not running?**
```bash
systemctl status step-ca-renew-myservice.timer
```

**Service failed?**
```bash
journalctl -u step-ca-renew-myservice.service --since "1 hour ago"
```

**Check certificate expiry manually:**
```bash
openssl x509 -in /etc/ssl/step-ca/myservice.crt -noout -enddate
```

## Security Hardening — `ReadWritePaths` Caveat

If your service template uses `ProtectSystem=strict` for sandboxing, **every directory the renewal script writes to must be listed under `ReadWritePaths=`** — otherwise filesystem writes fail with `Read-only file system` even for the script's own user.

Common paths the renewal script writes to:

| Path | What's written | Required when |
|------|----------------|----------------|
| `/etc/ssl/step-ca/` | New service certificate + key | Always |
| `/run/<your-state-dir>/` | Alert cooldown state files | If you use alert-throttling helpers |
| `/var/log/<your-log>/` | Custom log file | If `StandardOutput=append:...` |

**Example drop-in**: `/etc/systemd/system/step-ca-renew-myservice.service.d/paths.conf`

```ini
[Service]
ReadWritePaths=/etc/ssl/step-ca
ReadWritePaths=/run/myproject-state
# Add any custom log directory here too
```

After creating the drop-in: `sudo systemctl daemon-reload`.

> **Real-world bug**: Without `ReadWritePaths`, an alert helper that writes a cooldown state file to `/run/...` would silently fail to throttle and could spam emails every cron interval. Always test the renewal once manually (`systemctl start step-ca-renew-myservice.service`) and inspect logs for `Read-only file system`.

## See Also

- [← Back to Root](../README.md)
- [Renewal Scripts](../renewal/)
- [Setup Guide](../docs/SETUP.md)
