# Monitoring Setup

Prometheus integration for step-ca certificate monitoring.

---

## Overview

Monitor certificate expiry, container health, and renewal status via Prometheus metrics.

**Metrics Exported:**
- `step_ca_cert_expiry_seconds` - Unix epoch of certificate expiry
- `step_ca_cert_days_remaining` - Days until expiry
- `step_ca_container_up` - Docker container health (1=up, 0=down)
- `step_ca_scrape_timestamp_seconds` - Last scrape timestamp

---

## Installation

### Step 1: Install cert-exporter

```bash
# Copy script
sudo cp cert-exporter.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/cert-exporter.sh

# Test run
sudo OUTPUT_FILE=/tmp/test.prom /usr/local/bin/cert-exporter.sh
cat /tmp/test.prom
```

### Step 2: Configure for Prometheus Textfile Collector

```bash
# Ensure node_exporter textfile collector is enabled
# node_exporter should be started with:
# --collector.textfile.directory=/var/lib/node_exporter/textfile_collector

# Create directory
sudo mkdir -p /var/lib/node_exporter/textfile_collector
sudo chown node_exporter:node_exporter /var/lib/node_exporter/textfile_collector
```

### Step 3: Set up systemd Timer

```bash
# Create service
sudo tee /etc/systemd/system/step-ca-exporter.service << 'EOF'
[Unit]
Description=step-ca Certificate Metrics Exporter
After=network.target

[Service]
Type=oneshot
Environment="OUTPUT_FILE=/var/lib/node_exporter/textfile_collector/step_ca.prom"
Environment="SERVICE_NAME=service"
ExecStart=/usr/local/bin/cert-exporter.sh
User=root
EOF

# Create timer
sudo tee /etc/systemd/system/step-ca-exporter.timer << 'EOF'
[Unit]
Description=step-ca Certificate Metrics Exporter Timer

[Timer]
OnCalendar=hourly
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Enable
sudo systemctl daemon-reload
sudo systemctl enable --now step-ca-exporter.timer
```

---

## Prometheus Configuration

### Alert Rules

Copy `prometheus-rules.yml` to Prometheus:

```bash
sudo cp prometheus-rules.yml /etc/prometheus/rules/step-ca.yml
```

**Included Alerts:**
| Alert | Threshold | Severity |
|-------|-----------|----------|
| `StepCAServiceCertExpiringSoon` | <30 days | warning |
| `StepCAServiceCertCritical` | <7 days | critical |
| `StepCAServiceCertEmergency` | <1 day | critical |
| `StepCAIntermediateExpiring` | <90 days | warning |
| `StepCARootCAExpiring` | <365 days | warning |
| `StepCAContainerDown` | 5 min down | critical |
| `StepCAMetricsStale` | >2h stale | warning |

### Prometheus Config

Add to `/etc/prometheus/prometheus.yml`:

```yaml
rule_files:
  - 'rules/step-ca.yml'

scrape_configs:
  - job_name: 'node_exporter'
    static_configs:
      - targets: ['localhost:9100']
```

Reload Prometheus:
```bash
curl -X POST http://localhost:9090/-/reload
# OR
sudo systemctl reload prometheus
```

---

## Grafana Dashboard

### Import Dashboard

1. Copy `grafana-dashboard.json` to Grafana
2. Import via UI: Configuration → Dashboards → Import
3. Dashboard ID: `step-ca-pki`

**Panels:**
- Certificate expiry timeline
- Days remaining gauge
- Container health status
- Renewal history

---

## Verification

### Test Metrics

```bash
# Check textfile exists
cat /var/lib/node_exporter/textfile_collector/step_ca.prom

# Verify Prometheus scrapes metrics
curl http://localhost:9100/metrics | grep step_ca_cert_days_remaining

# Query Prometheus API
curl 'http://localhost:9090/api/v1/query?query=step_ca_cert_days_remaining' | jq
```

### Test Alerts

```bash
# Check alert rules
curl http://localhost:9090/api/v1/rules | \
    jq '.data.groups[].rules[] | select(.name | contains("StepCA"))'

# Check active alerts
curl http://localhost:9090/api/v1/alerts | \
    jq '.data.alerts[] | select(.labels.alertname | contains("StepCA"))'
```

---

## Customization

### Multiple Services

Export metrics for multiple services by creating service+timer pairs:

```bash
# Create service unit
sudo tee /etc/systemd/system/step-ca-exporter-vaultwarden.service << 'EOF'
[Unit]
Description=Export Vaultwarden certificate metrics for Prometheus
After=network.target

[Service]
Type=oneshot
Environment="SERVICE_NAME=vaultwarden"
Environment="OUTPUT_FILE=/var/lib/node_exporter/textfile_collector/step_ca_vaultwarden.prom"
ExecStart=/usr/local/bin/cert-exporter.sh
EOF

# Create timer unit
sudo tee /etc/systemd/system/step-ca-exporter-vaultwarden.timer << 'EOF'
[Unit]
Description=Hourly Vaultwarden certificate metrics export

[Timer]
OnCalendar=hourly
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Reload and enable
sudo systemctl daemon-reload
sudo systemctl enable --now step-ca-exporter-vaultwarden.timer
```

Repeat for each service (nextcloud, portainer, etc.) with adjusted `SERVICE_NAME` and output file.

### Custom Alert Thresholds

Edit `prometheus-rules.yml`:

```yaml
- alert: StepCAServiceCertExpiringSoon
  expr: step_ca_cert_days_remaining{type="service"} < 45  # Change from 30
  for: 1h
  labels:
    severity: warning
```

---

## Troubleshooting

See [TROUBLESHOOTING.md](../docs/TROUBLESHOOTING.md#monitoring-issues)
