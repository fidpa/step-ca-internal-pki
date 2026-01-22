#!/bin/bash
# Copyright (c) 2026 Marc Allgeier (fidpa)
# SPDX-License-Identifier: MIT
# https://github.com/fidpa/step-ca-internal-pki

# step-ca Certificate Exporter for Prometheus
#
# Purpose: Export certificate expiry metrics for Prometheus textfile collector
# Output: Prometheus metrics to stdout or file
# Requirements: openssl, docker (for container health check)
#
# Configuration via environment variables:
#   STEP_CA_HOME          - step-ca installation directory (default: /opt/step-ca)
#   STEP_CA_CERT_DIR      - Certificate storage directory (default: /etc/ssl/step-ca)
#   OUTPUT_FILE           - Metrics output file (default: stdout)
#   SERVICE_NAME          - Service certificate name (default: service)
#   DOCKER_CONTAINER      - Docker container name (default: step-ca)
#
# Exported Metrics:
#   step_ca_cert_expiry_seconds{type,service_name|cn} - Unix epoch of expiry
#   step_ca_cert_days_remaining{type,service_name|cn} - Days until expiry
#   step_ca_container_up - Docker container health (1=up, 0=down)
#   step_ca_scrape_timestamp_seconds - Scrape timestamp
#
# Note: Service certs use 'service_name' label, CA certs use 'cn' label
#
# Example systemd timer:
#   OnCalendar=hourly
#   Environment="OUTPUT_FILE=/var/lib/node_exporter/textfile_collector/step_ca.prom"

set -uo pipefail

# Help function
usage() {
    cat << 'EOF'
step-ca Certificate Exporter for Prometheus

USAGE:
    cert-exporter.sh [OPTIONS]

OPTIONS:
    -h, --help     Show this help message and exit

DESCRIPTION:
    Export certificate expiry metrics for Prometheus textfile collector.
    Outputs metrics to stdout or file (for node_exporter textfile collector).

ENVIRONMENT VARIABLES:
    STEP_CA_HOME          step-ca installation directory (default: /opt/step-ca)
    STEP_CA_CERT_DIR      Certificate storage directory (default: /etc/ssl/step-ca)
    OUTPUT_FILE           Metrics output file (default: stdout)
    SERVICE_NAME          Service certificate name (default: service)
    DOCKER_CONTAINER      Docker container name (default: step-ca)

EXPORTED METRICS:
    step_ca_cert_expiry_seconds{type,cn}    Unix epoch of certificate expiry
    step_ca_cert_days_remaining{type,cn}    Days until certificate expiry
    step_ca_container_up                    Docker container health (1=up, 0=down)
    step_ca_scrape_timestamp_seconds        Scrape timestamp

REQUIREMENTS:
    - openssl
    - docker (for container health check)

EXAMPLES:
    # Output to stdout
    cert-exporter.sh

    # Write to Prometheus textfile collector directory
    OUTPUT_FILE=/var/lib/node_exporter/textfile_collector/step_ca.prom cert-exporter.sh

    # Monitor specific service
    SERVICE_NAME=nextcloud cert-exporter.sh

SEE ALSO:
    monitoring/prometheus-rules.yml - Alert rules for certificate expiry
    monitoring/grafana-dashboard.json - Certificate monitoring dashboard

EOF
    exit 0
}

# Check required dependencies
check_dependencies() {
    local missing=()

    # Required dependencies
    if ! command -v openssl >/dev/null 2>&1; then
        missing+=("openssl")
    fi

    # Optional dependencies (warn but don't fail)
    if ! command -v docker >/dev/null 2>&1; then
        echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') Docker not found - container health checks will be skipped" >&2
    fi

    # Exit if required dependencies are missing
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') Missing required dependencies: ${missing[*]}" >&2
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') Install with: apt-get install ${missing[*]}" >&2
        exit 1
    fi
}

# Parse arguments
[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && usage

# Check dependencies before proceeding
check_dependencies

# Configuration (override via environment)
readonly STEP_CA_HOME="${STEP_CA_HOME:-/opt/step-ca}"
readonly STEP_CA_CERT_DIR="${STEP_CA_CERT_DIR:-/etc/ssl/step-ca}"
readonly SERVICE_NAME="${SERVICE_NAME:-service}"
readonly DOCKER_CONTAINER="${DOCKER_CONTAINER:-step-ca}"
OUTPUT_FILE="${OUTPUT_FILE:-}"  # Empty = stdout

# Certificate paths
readonly SERVICE_CERT="${STEP_CA_CERT_DIR}/${SERVICE_NAME}.crt"
readonly INTERMEDIATE_CA="${STEP_CA_HOME}/certs/intermediate_ca.crt"
readonly ROOT_CA="${STEP_CA_HOME}/certs/root_ca.crt"

# Temp file for atomic writes
TMP_FILE=""

# Simple inline logging
log_error() { echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') $*" >&2; }

# Cleanup function
cleanup() {
    if [[ -n "$TMP_FILE" && -f "$TMP_FILE" ]]; then
        rm -f "$TMP_FILE"
    fi
}
trap cleanup EXIT

# Function: Get certificate expiry in seconds since epoch
get_cert_expiry() {
    local cert_path="$1"

    if [[ ! -f "$cert_path" ]]; then
        echo "0"  # Certificate not found
        return
    fi

    local expiry_date
    if ! expiry_date=$(openssl x509 -in "$cert_path" -noout -enddate 2>/dev/null | cut -d= -f2); then
        echo "0"  # Invalid certificate
        return
    fi

    date -d "$expiry_date" +%s 2>/dev/null || echo "0"
}

# Function: Get certificate common name
get_cert_cn() {
    local cert_path="$1"

    if [[ ! -f "$cert_path" ]]; then
        echo "unknown"
        return
    fi

    # Extract CN value only (stop at comma or end of line)
    openssl x509 -in "$cert_path" -noout -subject 2>/dev/null | \
        sed -n 's/^.*CN[[:space:]]*=[[:space:]]*//p' | \
        sed 's/[[:space:]]*$//' | \
        sed 's/,.*//' || echo "unknown"
}

# Function: Calculate days remaining
days_remaining() {
    local expiry_epoch="$1"
    local now_epoch
    now_epoch=$(date +%s)

    if [[ "$expiry_epoch" -eq 0 ]]; then
        echo "0"
        return
    fi

    echo $(( (expiry_epoch - now_epoch) / 86400 ))
}

# Function: Check Docker container health
check_container_health() {
    local container="$1"

    if ! command -v docker >/dev/null 2>&1; then
        echo "0"  # Docker not available
        return
    fi

    if docker ps --filter "name=${container}" --filter "status=running" --format '{{.Names}}' 2>/dev/null | grep -q "^${container}$"; then
        echo "1"  # Container running
    else
        echo "0"  # Container not running
    fi
}

# Collect metrics
NOW=$(date +%s)

SERVICE_EXPIRY=$(get_cert_expiry "$SERVICE_CERT")
# Use SERVICE_NAME directly for consistent alert grouping (not CN from certificate)
SERVICE_LABEL="$SERVICE_NAME"
SERVICE_DAYS=$(days_remaining "$SERVICE_EXPIRY")

INTERMEDIATE_EXPIRY=$(get_cert_expiry "$INTERMEDIATE_CA")
INTERMEDIATE_CN=$(get_cert_cn "$INTERMEDIATE_CA")
INTERMEDIATE_DAYS=$(days_remaining "$INTERMEDIATE_EXPIRY")

ROOT_EXPIRY=$(get_cert_expiry "$ROOT_CA")
ROOT_CN=$(get_cert_cn "$ROOT_CA")
ROOT_DAYS=$(days_remaining "$ROOT_EXPIRY")

CONTAINER_UP=$(check_container_health "$DOCKER_CONTAINER")

# Generate Prometheus metrics
{
    echo "# HELP step_ca_cert_expiry_seconds Unix epoch of certificate expiry"
    echo "# TYPE step_ca_cert_expiry_seconds gauge"
    echo "step_ca_cert_expiry_seconds{type=\"service\",service_name=\"${SERVICE_LABEL}\"} ${SERVICE_EXPIRY}"
    echo "step_ca_cert_expiry_seconds{type=\"intermediate\",cn=\"${INTERMEDIATE_CN}\"} ${INTERMEDIATE_EXPIRY}"
    echo "step_ca_cert_expiry_seconds{type=\"root\",cn=\"${ROOT_CN}\"} ${ROOT_EXPIRY}"

    echo ""
    echo "# HELP step_ca_cert_days_remaining Days until certificate expiry"
    echo "# TYPE step_ca_cert_days_remaining gauge"
    echo "step_ca_cert_days_remaining{type=\"service\",service_name=\"${SERVICE_LABEL}\"} ${SERVICE_DAYS}"
    echo "step_ca_cert_days_remaining{type=\"intermediate\",cn=\"${INTERMEDIATE_CN}\"} ${INTERMEDIATE_DAYS}"
    echo "step_ca_cert_days_remaining{type=\"root\",cn=\"${ROOT_CN}\"} ${ROOT_DAYS}"

    echo ""
    echo "# HELP step_ca_container_up step-ca Docker container health (1=up, 0=down)"
    echo "# TYPE step_ca_container_up gauge"
    echo "step_ca_container_up ${CONTAINER_UP}"

    echo ""
    echo "# HELP step_ca_scrape_timestamp_seconds Unix epoch of metric collection"
    echo "# TYPE step_ca_scrape_timestamp_seconds gauge"
    echo "step_ca_scrape_timestamp_seconds ${NOW}"
} | if [[ -z "$OUTPUT_FILE" ]]; then
    # Output to stdout
    cat
else
    # Atomic write to file (textfile collector pattern)
    TMP_FILE=$(mktemp "${OUTPUT_FILE}.XXXXXX")
    cat > "$TMP_FILE"
    chmod 644 "$TMP_FILE"
    mv "$TMP_FILE" "$OUTPUT_FILE"
    TMP_FILE=""  # Prevent cleanup of moved file
fi
