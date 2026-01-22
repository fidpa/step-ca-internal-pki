#!/bin/bash
# Copyright (c) 2026 Marc Allgeier (fidpa)
# SPDX-License-Identifier: MIT
# https://github.com/fidpa/step-ca-internal-pki

# ╔════════════════════════════════════════════════════════════════════════════╗
# ║  ⚠️  EXPERIMENTAL - NOT COMPATIBLE WITH DEFAULT ARCHITECTURE  ⚠️           ║
# ╠════════════════════════════════════════════════════════════════════════════╣
# ║  This script uses 'step ca revoke' which requires certificates to be       ║
# ║  registered in step-ca's database. The default Two-Tier PKI architecture   ║
# ║  uses OpenSSL signing (not step-ca API), so certificates are NOT in the    ║
# ║  database and this script WILL NOT WORK.                                   ║
# ║                                                                            ║
# ║  For the default architecture, use manual OpenSSL revocation:              ║
# ║    1. openssl ca -revoke <cert> -config openssl.cnf                        ║
# ║    2. openssl ca -gencrl -out crl.pem -config openssl.cnf                  ║
# ║                                                                            ║
# ║  See docs/ARCHITECTURE.md § Revocation Process for details.                ║
# ╚════════════════════════════════════════════════════════════════════════════╝
#
# step-ca Certificate Revocation Script (EXPERIMENTAL)
#
# Purpose: Revoke certificates via step-ca API (requires API-issued certificates)
# Requirements: openssl, docker (for step-ca container access), curl (for CRL verification)
#
# Configuration via environment variables:
#   STEP_CA_HOME           - step-ca installation directory (default: /opt/step-ca)
#   STEP_CA_CONTAINER      - Docker container name (default: step-ca)
#   STEP_CA_CA_URL         - CA URL for step CLI (default: https://step-ca.internal:9643)
#   CRL_ENDPOINT           - CRL distribution endpoint (default: https://localhost:9643/1.0/crl)
#
# Usage:
#   revoke-cert.sh --serial <SERIAL> --reason <REASON>
#   revoke-cert.sh --cert <CERT_FILE> --reason <REASON>
#
# Reasons: keyCompromise, affiliationChanged, superseded, cessationOfOperation, unspecified

set -uo pipefail

# Configuration (override via environment)
readonly STEP_CA_HOME="${STEP_CA_HOME:-/opt/step-ca}"
readonly STEP_CA_CONTAINER="${STEP_CA_CONTAINER:-step-ca}"
readonly STEP_CA_CA_URL="${STEP_CA_CA_URL:-https://step-ca.internal:9643}"
readonly CRL_ENDPOINT="${CRL_ENDPOINT:-https://localhost:9643/1.0/crl}"

# Derived paths
readonly LOG_PREFIX="[step-ca-revoke]"

# Valid revocation reasons (RFC 5280)
readonly VALID_REASONS=("keyCompromise" "affiliationChanged" "superseded" "cessationOfOperation" "unspecified")

# Variables
SERIAL=""
CERT_FILE=""
REASON=""
DRY_RUN=false

# Simple inline logging
log_info()  { echo "[INFO]  $(date '+%Y-%m-%d %H:%M:%S') $LOG_PREFIX $*"; }
log_error() { echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') $LOG_PREFIX $*" >&2; }
log_warn()  { echo "[WARN]  $(date '+%Y-%m-%d %H:%M:%S') $LOG_PREFIX $*" >&2; }

# Check required dependencies
check_dependencies() {
    local missing=()

    # Required dependencies
    if ! command -v openssl >/dev/null 2>&1; then
        missing+=("openssl")
    fi

    if ! command -v docker >/dev/null 2>&1; then
        missing+=("docker")
    fi

    # Optional dependencies (warn but don't fail)
    if ! command -v curl >/dev/null 2>&1; then
        log_warn "curl not found - CRL verification will be skipped"
    fi

    # Exit if required dependencies are missing
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing[*]}"
        log_error "Install with: apt-get install ${missing[*]}"
        exit 1
    fi
}

# Usage
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Revoke a certificate from the step-ca PKI.

Options:
  --serial <SERIAL>     Certificate serial number (hex or decimal)
  --cert <FILE>         Certificate file (extracts serial automatically)
  --reason <REASON>     Revocation reason (required)
  --dry-run             Show what would be done without executing
  -h, --help            Show this help message

Valid Reasons:
  keyCompromise         Private key was compromised
  affiliationChanged    Certificate holder changed affiliation
  superseded            Certificate replaced by newer one
  cessationOfOperation  Service/entity no longer operating
  unspecified           No specific reason

Examples:
  # Revoke by serial number
  $(basename "$0") --serial 123456789abcdef --reason keyCompromise

  # Revoke by certificate file
  $(basename "$0") --cert /etc/ssl/step-ca/old-service.crt --reason superseded

  # Dry run (preview only)
  $(basename "$0") --cert /tmp/test.crt --reason unspecified --dry-run

EOF
    exit "${1:-0}"
}

# Validate reason
validate_reason() {
    local reason="$1"
    for valid in "${VALID_REASONS[@]}"; do
        if [[ "$reason" == "$valid" ]]; then
            return 0
        fi
    done
    return 1
}

# Extract serial from certificate file
extract_serial() {
    local cert_file="$1"

    if [[ ! -f "$cert_file" ]]; then
        log_error "Certificate file not found: $cert_file"
        return 1
    fi

    # Extract serial number (hex format, uppercase)
    local serial
    serial=$(openssl x509 -in "$cert_file" -noout -serial 2>/dev/null | cut -d= -f2)

    if [[ -z "$serial" ]]; then
        log_error "Failed to extract serial from: $cert_file"
        return 1
    fi

    echo "$serial"
}

# Get certificate info for logging
get_cert_info() {
    local cert_file="$1"

    if [[ -f "$cert_file" ]]; then
        local subject cn expiry
        subject=$(openssl x509 -in "$cert_file" -noout -subject 2>/dev/null | sed 's/subject=//')
        cn=$(echo "$subject" | grep -oP 'CN\s*=\s*\K[^,]+' || echo "unknown")
        expiry=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | cut -d= -f2)
        echo "CN=$cn, Expires=$expiry"
    else
        echo "Serial=$SERIAL (no cert file)"
    fi
}

# Check if step-ca container is running
check_container() {
    if ! command -v docker >/dev/null 2>&1; then
        log_error "Docker not available"
        return 1
    fi

    if ! docker ps --filter "name=$STEP_CA_CONTAINER" --format "{{.Names}}" 2>/dev/null | grep -q "^${STEP_CA_CONTAINER}$"; then
        log_error "step-ca container is not running"
        return 1
    fi

    # Check health (optional, non-fatal)
    local status
    status=$(docker inspect --format='{{.State.Health.Status}}' "$STEP_CA_CONTAINER" 2>/dev/null || echo "unknown")

    if [[ "$status" != "healthy" && "$status" != "unknown" ]]; then
        log_warn "step-ca container health status: $status"
    fi

    return 0
}

# Revoke certificate using step CLI in container
revoke_certificate() {
    local serial="$1"
    local reason="$2"

    log_info "Revoking certificate: Serial=$serial, Reason=$reason"

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would execute: docker exec $STEP_CA_CONTAINER step ca revoke $serial --reason $reason"
        return 0
    fi

    # Execute revocation via step CLI in container
    local output
    if ! output=$(docker exec "$STEP_CA_CONTAINER" step ca revoke "$serial" \
        --reason "$reason" \
        --ca-url "$STEP_CA_CA_URL" \
        --root "/home/step/certs/root_ca.crt" 2>&1); then

        log_error "Revocation failed: $output"
        return 1
    fi

    log_info "Revocation successful: $output"
    return 0
}

# Verify CRL contains revoked certificate
verify_crl() {
    local serial="$1"

    log_info "Verifying CRL update..."

    # Download current CRL
    local crl_file
    crl_file=$(mktemp)
    trap 'rm -f "$crl_file"' RETURN

    if ! curl -s "$CRL_ENDPOINT" -o "$crl_file" 2>/dev/null; then
        log_warn "Could not download CRL for verification"
        return 1
    fi

    # Convert to text and check for serial
    local crl_text
    crl_text=$(openssl crl -in "$crl_file" -inform DER -text -noout 2>/dev/null || true)

    # Normalize serial (remove leading zeros, uppercase)
    local normalized_serial
    normalized_serial=$(echo "$serial" | tr '[:lower:]' '[:upper:]' | sed 's/^0*//')

    if echo "$crl_text" | grep -qi "$normalized_serial"; then
        log_info "✅ Certificate serial $serial found in CRL"
        return 0
    else
        log_warn "Certificate serial $serial not yet visible in CRL (may need refresh)"
        return 1
    fi
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --serial)
                SERIAL="$2"
                shift 2
                ;;
            --cert)
                CERT_FILE="$2"
                shift 2
                ;;
            --reason)
                REASON="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                usage 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage 1
                ;;
        esac
    done
}

# Main function
main() {
    parse_args "$@"

    # Check dependencies before proceeding
    check_dependencies

    # EXPERIMENTAL WARNING
    log_warn "╔════════════════════════════════════════════════════════════════════╗"
    log_warn "║  ⚠️  EXPERIMENTAL: This script may not work with your setup!        ║"
    log_warn "║  It requires certificates issued via step-ca API (in database).    ║"
    log_warn "║  Default architecture uses OpenSSL signing → certs NOT in DB.      ║"
    log_warn "║  See docs/ARCHITECTURE.md § Revocation for manual OpenSSL method.  ║"
    log_warn "╚════════════════════════════════════════════════════════════════════╝"
    echo ""

    # Validate inputs
    if [[ -z "$SERIAL" && -z "$CERT_FILE" ]]; then
        log_error "Either --serial or --cert is required"
        usage 1
    fi

    if [[ -z "$REASON" ]]; then
        log_error "--reason is required"
        usage 1
    fi

    if ! validate_reason "$REASON"; then
        log_error "Invalid reason: $REASON"
        log_error "Valid reasons: ${VALID_REASONS[*]}"
        exit 1
    fi

    # Extract serial from cert file if provided
    if [[ -n "$CERT_FILE" ]]; then
        SERIAL=$(extract_serial "$CERT_FILE")
        if [[ -z "$SERIAL" ]]; then
            exit 1
        fi
        log_info "Extracted serial from certificate: $SERIAL"
        log_info "Certificate info: $(get_cert_info "$CERT_FILE")"
    fi

    # Root check (required for docker exec in some configurations)
    if [[ $EUID -ne 0 && "$DRY_RUN" == false ]]; then
        log_error "Must run as root (required for docker exec)"
        exit 1
    fi

    # Check container
    if ! check_container; then
        exit 1
    fi

    # Perform revocation
    if ! revoke_certificate "$SERIAL" "$REASON"; then
        exit 1
    fi

    # Verify CRL (non-fatal if fails)
    if [[ "$DRY_RUN" == false ]]; then
        sleep 2  # Wait for CRL regeneration
        verify_crl "$SERIAL" || true
    fi

    log_info "Certificate revocation complete"
    return 0
}

# Entry point
main "$@"
