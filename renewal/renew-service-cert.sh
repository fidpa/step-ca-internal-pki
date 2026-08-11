#!/bin/bash
# Copyright (c) 2026 Marc Allgeier (fidpa)
# SPDX-License-Identifier: MIT
# https://github.com/fidpa/step-ca-internal-pki

# step-ca Service Certificate Renewal Script
#
# Purpose: Auto-renew service certificates signed by step-ca Intermediate CA
# Trigger: Run via systemd timer (recommended: daily)
# Requirements: openssl, root access (for service reload)
#
# Configuration via environment variables:
#   STEP_CA_HOME           - step-ca installation directory (default: /opt/step-ca)
#   STEP_CA_CERT_DIR       - Certificate storage directory (default: /etc/ssl/step-ca)
#   SERVICE_NAME           - Service identifier (default: service)
#   RENEWAL_THRESHOLD      - Days before expiry to renew (default: 30)
#   SERVICE_RELOAD_CMD     - Command to reload service (default: systemctl reload nginx)
#
# Example systemd timer setup:
#   OnCalendar=daily
#   Environment="SERVICE_NAME=myservice"

set -uo pipefail

# Serial file locking to prevent race conditions during concurrent renewals
readonly SERIAL_LOCKFILE="/var/lock/step-ca-serial.lock"

# Help function
usage() {
    cat << 'EOF'
step-ca Service Certificate Renewal Script

USAGE:
    renew-service-cert.sh [OPTIONS]

OPTIONS:
    -h, --help     Show this help message and exit
    --force        Renew immediately, bypassing the days-left threshold
                   (useful after editing the .san file: re-issue with new SANs)

DESCRIPTION:
    Auto-renew service certificates signed by step-ca Intermediate CA.
    Designed to run via systemd timer (daily checks).

ENVIRONMENT VARIABLES:
    STEP_CA_HOME           step-ca installation directory (default: /opt/step-ca)
    STEP_CA_CERT_DIR       Certificate storage directory (default: /etc/ssl/step-ca)
    SERVICE_NAME           Service identifier (default: service)
    RENEWAL_THRESHOLD      Days before expiry to renew (default: 30)
    SERVICE_RELOAD_CMD     Command to reload service (default: systemctl reload nginx)

REQUIREMENTS:
    - openssl
    - root access (for service reload)
    - Intermediate CA certificate and key in STEP_CA_HOME

EXAMPLES:
    # Renew certificate for "myservice"
    sudo SERVICE_NAME=myservice renew-service-cert.sh

    # Run with custom threshold (60 days)
    sudo SERVICE_NAME=nextcloud RENEWAL_THRESHOLD=60 renew-service-cert.sh

SEE ALSO:
    docs/SETUP.md - Certificate renewal setup
    systemd/step-ca-renew.timer.template - Automated renewal via systemd

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

    # Exit if required dependencies are missing
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') Missing required dependencies: ${missing[*]}" >&2
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') Install with: apt-get install ${missing[*]}" >&2
        exit 1
    fi
}

# Parse arguments
FORCE_RENEWAL=0
for arg in "$@"; do
    case "$arg" in
        -h|--help) usage ;;
        --force) FORCE_RENEWAL=1 ;;
        *)
            echo "[ERROR] Unknown argument: $arg" >&2
            echo "Usage: $0 [--force] [-h|--help]" >&2
            exit 1
            ;;
    esac
done

# Check dependencies before proceeding
check_dependencies

# Configuration (override via environment)
readonly STEP_CA_HOME="${STEP_CA_HOME:-/opt/step-ca}"
readonly STEP_CA_CERT_DIR="${STEP_CA_CERT_DIR:-/etc/ssl/step-ca}"
readonly SERVICE_NAME="${SERVICE_NAME:-service}"
readonly RENEWAL_THRESHOLD="${RENEWAL_THRESHOLD:-30}"
readonly SERVICE_RELOAD_CMD="${SERVICE_RELOAD_CMD:-systemctl reload nginx}"

# Derived paths
readonly LOG_PREFIX="[step-ca-renewal:${SERVICE_NAME}]"
readonly CERT_PATH="${STEP_CA_CERT_DIR}/${SERVICE_NAME}.crt"
readonly FULLCHAIN_PATH="${STEP_CA_CERT_DIR}/${SERVICE_NAME}-fullchain.crt"
readonly KEY_PATH="${STEP_CA_CERT_DIR}/${SERVICE_NAME}.key"
readonly CA_CERT="${STEP_CA_HOME}/certs/intermediate_ca.crt"
readonly CA_KEY="${STEP_CA_HOME}/secrets/intermediate_ca_key"
readonly CA_SERIAL="${STEP_CA_HOME}/certs/intermediate_ca.srl"
readonly ROOT_CA="${STEP_CA_HOME}/certs/root_ca.crt"

# Temporary directory (secure)
TMPDIR=""

# Simple inline logging (no external dependencies)
log_info()  { echo "[INFO]  $(date '+%Y-%m-%d %H:%M:%S') $LOG_PREFIX $*"; }
log_error() { echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') $LOG_PREFIX $*" >&2; }
log_success() { echo "[OK]    $(date '+%Y-%m-%d %H:%M:%S') $LOG_PREFIX $*"; }

# Cleanup function - runs on EXIT (success or failure)
cleanup() {
    if [[ -n "$TMPDIR" && -d "$TMPDIR" ]]; then
        rm -rf "$TMPDIR"
    fi
}
trap cleanup EXIT

# Root check
if [[ $EUID -ne 0 ]]; then
    log_error "Must run as root (required for service reload)"
    exit 1
fi

# Verify certificate exists
if [[ ! -f "$CERT_PATH" ]]; then
    log_error "Certificate not found: $CERT_PATH"
    log_info "Hint: Run initial certificate request first"
    exit 1
fi

# Verify CA files exist
if [[ ! -f "$CA_CERT" ]]; then
    log_error "Intermediate CA not found: $CA_CERT"
    exit 1
fi

if [[ ! -f "$CA_KEY" ]]; then
    log_error "Intermediate CA key not found: $CA_KEY"
    exit 1
fi

if [[ ! -f "$ROOT_CA" ]]; then
    log_error "Root CA not found: $ROOT_CA"
    exit 1
fi

# Calculate days until expiry
EXPIRY_DATE=$(openssl x509 -in "$CERT_PATH" -noout -enddate | cut -d= -f2)
EXPIRY_EPOCH=$(date -d "$EXPIRY_DATE" +%s)
NOW_EPOCH=$(date +%s)
DAYS_LEFT=$(( (EXPIRY_EPOCH - NOW_EPOCH) / 86400 ))

log_info "Certificate expires in $DAYS_LEFT days (threshold: $RENEWAL_THRESHOLD)"

# Renew if less than threshold days remaining (or --force)
if [[ $DAYS_LEFT -lt $RENEWAL_THRESHOLD ]] || [[ $FORCE_RENEWAL -eq 1 ]]; then
    [[ $FORCE_RENEWAL -eq 1 ]] && log_info "Force renewal requested (--force) - bypassing threshold"
    log_info "Starting renewal..."

    # Create secure temporary directory
    TMPDIR=$(mktemp -d -p /tmp step-ca-renewal.XXXXXX)
    chmod 700 "$TMPDIR"

    # Load SAN configuration from external file if exists
    SAN_CONFIG="${STEP_CA_CERT_DIR}/${SERVICE_NAME}.san"
    if [[ -f "$SAN_CONFIG" ]]; then
        log_info "Loading SANs from: $SAN_CONFIG"
        # Expected format: DNS.1 = example.com\nIP.1 = 10.0.0.1
        cp "$SAN_CONFIG" "$TMPDIR/alt_names.tmp"
    else
        log_error "SAN configuration not found: $SAN_CONFIG"
        log_info "Create ${SERVICE_NAME}.san with your Subject Alternative Names"
        log_info "Example format:"
        log_info "  DNS.1 = service.internal"
        log_info "  IP.1 = 10.0.0.1"
        exit 1
    fi

    # Create CSR config
    cat > "$TMPDIR/renewal.cnf" << EOFCNF
[req]
prompt = no
default_md = sha256
req_extensions = req_ext
distinguished_name = dn

[dn]
CN = ${SERVICE_NAME}

[req_ext]
subjectAltName = @alt_names

[alt_names]
$(cat "$TMPDIR/alt_names.tmp")
EOFCNF

    # Generate new key and CSR
    if ! openssl ecparam -genkey -name prime256v1 -noout -out "$TMPDIR/key.pem" 2>/dev/null; then
        log_error "Failed to generate private key"
        exit 1
    fi
    chmod 600 "$TMPDIR/key.pem"

    if ! openssl req -new -key "$TMPDIR/key.pem" -out "$TMPDIR/renewal.csr" -config "$TMPDIR/renewal.cnf" 2>/dev/null; then
        log_error "Failed to generate CSR"
        exit 1
    fi

    # Create signing extensions config
    # Note: keyEncipherment removed - it's RSA-specific; ECDSA uses digitalSignature only
    cat > "$TMPDIR/renewal-ext.cnf" << EOFEXT
[v3_ca]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names

[alt_names]
$(cat "$TMPDIR/alt_names.tmp")
EOFEXT

    # Sign with Intermediate CA
    # Note: -CAserial uses explicit path (required for systemd ProtectSystem=strict)
    # flock ensures serial number is not duplicated during concurrent renewals
    #
    # Keep the lockfile world-writable: /var/lock is tmpfs (cleared on reboot) and
    # the first process to recreate it owns it. In multi-user setups (e.g. remote
    # signing over SSH as a non-root user) a root-owned 0644 lockfile would lock
    # every other signer out.
    touch "$SERIAL_LOCKFILE" 2>/dev/null || true
    chmod 666 "$SERIAL_LOCKFILE" 2>/dev/null || true

    # Signing stderr stays visible on purpose: suppressing it hides the actual
    # CA error (bad extfile, unreadable key, serial trouble) behind a generic message
    (
        if ! flock -x -w 60 200; then
            log_error "Failed to acquire serial file lock (timeout after 60s)"
            exit 1
        fi

        if ! openssl x509 -req \
            -in "$TMPDIR/renewal.csr" \
            -CA "$CA_CERT" \
            -CAkey "$CA_KEY" \
            -CAserial "$CA_SERIAL" -CAcreateserial \
            -out "$TMPDIR/renewal.crt" \
            -days 90 \
            -sha256 \
            -extfile "$TMPDIR/renewal-ext.cnf" \
            -extensions v3_ca; then
            log_error "Failed to sign certificate"
            exit 1
        fi
    ) 200>"$SERIAL_LOCKFILE"

    # Check if subshell failed
    if [[ ! -f "$TMPDIR/renewal.crt" ]]; then
        log_error "Certificate signing failed (check previous errors)"
        exit 1
    fi

    # Belt and suspenders: the signed certificate must embed the public key of
    # the key generated above (guards against deploying a stale or foreign cert)
    if [[ "$(openssl x509 -in "$TMPDIR/renewal.crt" -noout -pubkey 2>/dev/null)" != \
          "$(openssl pkey -in "$TMPDIR/key.pem" -pubout 2>/dev/null)" ]]; then
        log_error "Public key mismatch: signed certificate does not match generated key"
        exit 1
    fi

    # Create fullchain
    cat "$TMPDIR/renewal.crt" "$CA_CERT" > "$TMPDIR/renewal-fullchain.crt"

    # Verify new certificate
    if ! openssl verify -CAfile "$ROOT_CA" -untrusted "$CA_CERT" "$TMPDIR/renewal.crt" >/dev/null 2>&1; then
        log_error "Certificate verification failed!"
        exit 1
    fi

    log_info "Certificate verified, deploying..."

    # Backup old certs
    cp "$CERT_PATH" "${CERT_PATH}.bak"
    cp "$FULLCHAIN_PATH" "${FULLCHAIN_PATH}.bak"
    cp "$KEY_PATH" "${KEY_PATH}.bak"

    # Atomic deployment: Stage with .new suffix, then atomic mv
    # This prevents partial deployment if interrupted mid-operation
    cp "$TMPDIR/renewal.crt" "${CERT_PATH}.new"
    cp "$TMPDIR/key.pem" "${KEY_PATH}.new"
    cp "$TMPDIR/renewal-fullchain.crt" "${FULLCHAIN_PATH}.new"

    # Verify all .new files exist before swap
    if [[ ! -f "${CERT_PATH}.new" ]] || [[ ! -f "${KEY_PATH}.new" ]] || [[ ! -f "${FULLCHAIN_PATH}.new" ]]; then
        log_error "Staging failed - aborting deployment"
        rm -f "${CERT_PATH}.new" "${KEY_PATH}.new" "${FULLCHAIN_PATH}.new"
        exit 1
    fi

    # Set permissions before atomic swap
    chmod 644 "${CERT_PATH}.new" "${FULLCHAIN_PATH}.new"
    chmod 600 "${KEY_PATH}.new"

    # Cleanup function for partial deployment failure
    cleanup_partial_deployment() {
        log_error "Deployment interrupted - cleaning up .new files"
        rm -f "${CERT_PATH}.new" "${KEY_PATH}.new" "${FULLCHAIN_PATH}.new"
    }
    trap cleanup_partial_deployment EXIT

    # Atomic swap (POSIX rename(2) - all or nothing per file)
    mv "${CERT_PATH}.new" "$CERT_PATH"
    mv "${KEY_PATH}.new" "$KEY_PATH"
    mv "${FULLCHAIN_PATH}.new" "$FULLCHAIN_PATH"

    # Success - restore original cleanup trap
    trap cleanup EXIT
    log_info "Certificate deployment successful"

    # Reload service
    # SECURITY NOTE: SERVICE_RELOAD_CMD is admin-configured via environment variable.
    # Do NOT use user-provided input here. The eval is safe when configured by
    # trusted admins only (e.g., SERVICE_RELOAD_CMD="systemctl reload nginx").
    if ! eval "$SERVICE_RELOAD_CMD"; then
        log_error "Service reload failed, rolling back..."
        cp "${CERT_PATH}.bak" "$CERT_PATH"
        cp "${FULLCHAIN_PATH}.bak" "$FULLCHAIN_PATH"
        cp "${KEY_PATH}.bak" "$KEY_PATH"
        eval "$SERVICE_RELOAD_CMD" || true
        exit 1
    fi

    log_success "Certificate renewed successfully!"
else
    log_info "No renewal needed ($DAYS_LEFT days remaining)"
fi
