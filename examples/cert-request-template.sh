#!/bin/bash
# Copyright (c) 2026 Marc Allgeier (fidpa)
# SPDX-License-Identifier: MIT
# https://github.com/fidpa/step-ca-internal-pki

# step-ca Service Certificate Request Template
#
# Purpose: Request a new certificate from step-ca Intermediate CA
# Usage: Customize this template for your service
#
# Configuration: Edit the variables below
#   SERVICE_NAME  - Your service identifier (e.g., "myservice")
#   DNS_SANS      - DNS Subject Alternative Names
#   IP_SANS       - IP Subject Alternative Names
#
# Example:
#   SERVICE_NAME="vaultwarden"
#   DNS_SANS=("vaultwarden.internal" "passwords.internal")
#   IP_SANS=("10.0.0.2")

set -uo pipefail

# Serial file locking to prevent race conditions during concurrent requests
readonly SERIAL_LOCKFILE="/var/lock/step-ca-serial.lock"

# ============================================================================
# CUSTOMIZE THESE VARIABLES
# ============================================================================

# Service name (used for certificate filename AND Common Name)
# Note: CN = SERVICE_NAME (short name), SANs contain FQDNs
# Modern TLS clients validate SANs, not CN - this is RFC 6125 compliant
readonly SERVICE_NAME="myservice"

# DNS Subject Alternative Names (SANs)
declare -a DNS_SANS=(
    "myservice.internal"
    # "myservice.example.com"  # Add more if needed
)

# IP Subject Alternative Names
declare -a IP_SANS=(
    "10.0.0.2"
    # "192.168.1.100"  # Add more if needed
)

# ============================================================================
# CONFIGURATION (usually no need to change)
# ============================================================================

readonly STEP_CA_HOME="${STEP_CA_HOME:-/opt/step-ca}"
readonly STEP_CA_CERT_DIR="${STEP_CA_CERT_DIR:-/etc/ssl/step-ca}"

readonly CA_CERT="${STEP_CA_HOME}/certs/intermediate_ca.crt"
readonly CA_KEY="${STEP_CA_HOME}/secrets/intermediate_ca_key"
readonly CA_SERIAL="${STEP_CA_HOME}/certs/intermediate_ca.srl"
readonly ROOT_CA="${STEP_CA_HOME}/certs/root_ca.crt"

readonly CERT_VALIDITY_DAYS=90

# Temporary directory
TMPDIR=""

# ============================================================================
# FUNCTIONS
# ============================================================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
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
        error "Missing required dependencies: ${missing[*]}"
        error "Install with: apt-get install ${missing[*]}"
        exit 1
    fi
}

cleanup() {
    if [[ -n "$TMPDIR" && -d "$TMPDIR" ]]; then
        rm -rf "$TMPDIR"
    fi
}

trap cleanup EXIT

# ============================================================================
# PRE-FLIGHT CHECKS
# ============================================================================

# Check dependencies before proceeding
check_dependencies

# Root check
if [[ $EUID -ne 0 ]]; then
    error "Must run as root (required for certificate deployment)"
    exit 1
fi

# Check CA files exist
if [[ ! -f "$CA_CERT" ]]; then
    error "Intermediate CA not found: $CA_CERT"
    exit 1
fi

if [[ ! -f "$CA_KEY" ]]; then
    error "Intermediate CA key not found: $CA_KEY"
    exit 1
fi

if [[ ! -f "$ROOT_CA" ]]; then
    error "Root CA not found: $ROOT_CA"
    exit 1
fi

# Create certificate directory if it doesn't exist
if [[ ! -d "$STEP_CA_CERT_DIR" ]]; then
    log "Creating certificate directory: $STEP_CA_CERT_DIR"
    mkdir -p "$STEP_CA_CERT_DIR"
    chmod 755 "$STEP_CA_CERT_DIR"
fi

# ============================================================================
# MAIN
# ============================================================================

log "=== Certificate Request for ${SERVICE_NAME} ==="
log "DNS SANs: ${DNS_SANS[*]}"
log "IP SANs: ${IP_SANS[*]}"

# Create secure temp directory
TMPDIR=$(mktemp -d -p /tmp step-ca-cert-request.XXXXXX)
chmod 700 "$TMPDIR"

# Build SAN configuration
SAN_CONFIG=""
for i in "${!DNS_SANS[@]}"; do
    SAN_CONFIG+="DNS.$((i+1)) = ${DNS_SANS[$i]}\n"
done
for i in "${!IP_SANS[@]}"; do
    SAN_CONFIG+="IP.$((i+1)) = ${IP_SANS[$i]}\n"
done

# Create CSR configuration
log "Creating CSR configuration..."
cat > "$TMPDIR/csr.cnf" << EOF
[req]
prompt = no
default_md = sha256
req_extensions = req_ext
distinguished_name = dn

[dn]
# CN must match SERVICE_NAME for renewal compatibility (see renewal/renew-service-cert.sh)
CN = ${SERVICE_NAME}

[req_ext]
subjectAltName = @alt_names

[alt_names]
$(echo -e "$SAN_CONFIG")
EOF

# Generate private key
log "Generating private key (ECDSA P-256)..."
if ! openssl ecparam -genkey -name prime256v1 -noout -out "$TMPDIR/key.pem" 2>/dev/null; then
    error "Failed to generate private key"
    exit 1
fi
chmod 600 "$TMPDIR/key.pem"

# Create CSR
log "Creating Certificate Signing Request (CSR)..."
if ! openssl req -new -key "$TMPDIR/key.pem" -out "$TMPDIR/csr.pem" -config "$TMPDIR/csr.cnf" 2>/dev/null; then
    error "Failed to create CSR"
    exit 1
fi

# Create signing extensions
# Note: keyEncipherment removed - it's RSA-specific; ECDSA uses digitalSignature only
cat > "$TMPDIR/ext.cnf" << EOF
[v3_ca]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names

[alt_names]
$(echo -e "$SAN_CONFIG")
EOF

# Sign certificate with Intermediate CA
# Note: -CAserial uses explicit path (avoids CWD write issues)
# flock ensures serial number is not duplicated during concurrent requests
#
# Keep the lockfile world-writable: /var/lock is tmpfs (cleared on reboot) and
# the first process to recreate it owns it. In multi-user setups (e.g. remote
# signing over SSH as a non-root user) a root-owned 0644 lockfile would lock
# every other signer out.
touch "$SERIAL_LOCKFILE" 2>/dev/null || true
chmod 666 "$SERIAL_LOCKFILE" 2>/dev/null || true

# Signing stderr stays visible on purpose: suppressing it hides the actual
# CA error (bad extfile, unreadable key, serial trouble) behind a generic message
log "Signing certificate with Intermediate CA..."
(
    if ! flock -x -w 60 200; then
        error "Failed to acquire serial file lock (timeout after 60s)"
        exit 1
    fi

    if ! openssl x509 -req \
        -in "$TMPDIR/csr.pem" \
        -CA "$CA_CERT" \
        -CAkey "$CA_KEY" \
        -CAserial "$CA_SERIAL" -CAcreateserial \
        -out "$TMPDIR/cert.pem" \
        -days "$CERT_VALIDITY_DAYS" \
        -sha256 \
        -extfile "$TMPDIR/ext.cnf" \
        -extensions v3_ca; then
        error "Failed to sign certificate"
        exit 1
    fi
) 200>"$SERIAL_LOCKFILE"

# Check if subshell failed
if [[ ! -f "$TMPDIR/cert.pem" ]]; then
    error "Certificate signing failed (check previous errors)"
    exit 1
fi

# Create fullchain (cert + intermediate)
cat "$TMPDIR/cert.pem" "$CA_CERT" > "$TMPDIR/fullchain.pem"

# Verify certificate
log "Verifying certificate chain..."
if ! openssl verify -CAfile "$ROOT_CA" -untrusted "$CA_CERT" "$TMPDIR/cert.pem" >/dev/null 2>&1; then
    error "Certificate verification failed!"
    exit 1
fi

# Atomic deployment: Stage with .new suffix, then atomic mv
# This prevents partial deployment if interrupted mid-operation
log "Deploying certificate (atomic)..."
cp "$TMPDIR/cert.pem" "${STEP_CA_CERT_DIR}/${SERVICE_NAME}.crt.new"
cp "$TMPDIR/key.pem" "${STEP_CA_CERT_DIR}/${SERVICE_NAME}.key.new"
cp "$TMPDIR/fullchain.pem" "${STEP_CA_CERT_DIR}/${SERVICE_NAME}-fullchain.crt.new"

# Verify all .new files exist before swap
if [[ ! -f "${STEP_CA_CERT_DIR}/${SERVICE_NAME}.crt.new" ]] || \
   [[ ! -f "${STEP_CA_CERT_DIR}/${SERVICE_NAME}.key.new" ]] || \
   [[ ! -f "${STEP_CA_CERT_DIR}/${SERVICE_NAME}-fullchain.crt.new" ]]; then
    error "Staging failed - aborting deployment"
    rm -f "${STEP_CA_CERT_DIR}/${SERVICE_NAME}.crt.new" \
          "${STEP_CA_CERT_DIR}/${SERVICE_NAME}.key.new" \
          "${STEP_CA_CERT_DIR}/${SERVICE_NAME}-fullchain.crt.new"
    exit 1
fi

# Set permissions before atomic swap
chmod 644 "${STEP_CA_CERT_DIR}/${SERVICE_NAME}.crt.new"
chmod 644 "${STEP_CA_CERT_DIR}/${SERVICE_NAME}-fullchain.crt.new"
chmod 600 "${STEP_CA_CERT_DIR}/${SERVICE_NAME}.key.new"

# Cleanup function for partial deployment failure
cleanup_partial_deployment() {
    error "Deployment interrupted - cleaning up .new files"
    rm -f "${STEP_CA_CERT_DIR}/${SERVICE_NAME}.crt.new" \
          "${STEP_CA_CERT_DIR}/${SERVICE_NAME}.key.new" \
          "${STEP_CA_CERT_DIR}/${SERVICE_NAME}-fullchain.crt.new"
}
trap cleanup_partial_deployment EXIT

# Atomic swap (POSIX rename(2) - all or nothing per file)
mv "${STEP_CA_CERT_DIR}/${SERVICE_NAME}.crt.new" "${STEP_CA_CERT_DIR}/${SERVICE_NAME}.crt"
mv "${STEP_CA_CERT_DIR}/${SERVICE_NAME}.key.new" "${STEP_CA_CERT_DIR}/${SERVICE_NAME}.key"
mv "${STEP_CA_CERT_DIR}/${SERVICE_NAME}-fullchain.crt.new" "${STEP_CA_CERT_DIR}/${SERVICE_NAME}-fullchain.crt"

# Success - restore original cleanup trap
trap cleanup EXIT
log "Certificate deployment successful"

# Create SAN configuration file (required for auto-renewal)
log "Creating SAN configuration file for auto-renewal..."
cat > "${STEP_CA_CERT_DIR}/${SERVICE_NAME}.san" << EOF
$(echo -e "$SAN_CONFIG")
EOF
chmod 644 "${STEP_CA_CERT_DIR}/${SERVICE_NAME}.san"

log "Certificate issued successfully!"
log "Certificate: ${STEP_CA_CERT_DIR}/${SERVICE_NAME}.crt"
log "Private key: ${STEP_CA_CERT_DIR}/${SERVICE_NAME}.key"
log "Full chain: ${STEP_CA_CERT_DIR}/${SERVICE_NAME}-fullchain.crt"
log "Valid for: ${CERT_VALIDITY_DAYS} days"

# Display certificate details
log "Certificate details:"
openssl x509 -in "${STEP_CA_CERT_DIR}/${SERVICE_NAME}.crt" -noout -text | \
    grep -A 2 "Subject Alternative Name:"

log "Done! Remember to:"
log "1. Configure your service to use the new certificate"
log "2. Set up auto-renewal (see renewal/renew-service-cert.sh)"
log "3. Reload your service (e.g., systemctl reload nginx)"
