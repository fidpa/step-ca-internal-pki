#!/bin/bash
# ==============================================================================
# create-root-ca.sh - Offline Root CA Creation for step-ca PKI
# ==============================================================================
# Purpose:  Create Root CA on an air-gapped machine.
# Run on:   Air-gapped machine (NO NETWORK!)
# Output:   ~/.ca-creation-YYYYMMDD-HHMMSS/
#             - root_ca.crt           (public certificate)
#             - root_ca.key.gpg       (GPG-encrypted private key)
#             - checksums.sha256
#             - creation.log
#
# Configuration via environment variables (defaults shown):
#   CA_NAME            "HomeLab Root CA"
#   CA_VALIDITY_HOURS  87600    (10 years)
#   CA_KEY_TYPE        EC
#   CA_CURVE           P-384
#
# Example:
#   CA_NAME="My Internal Root CA 2026" ./create-root-ca.sh
# ==============================================================================

set -uo pipefail

# ------------------------------------------------------------------------------
# Configuration (override via ENV)
# ------------------------------------------------------------------------------
readonly CA_NAME="${CA_NAME:-HomeLab Root CA}"
readonly VALIDITY_HOURS="${CA_VALIDITY_HOURS:-87600}"  # 10 years
readonly KEY_TYPE="${CA_KEY_TYPE:-EC}"
readonly CURVE="${CA_CURVE:-P-384}"

readonly WORK_DIR="${HOME}/.ca-creation-$(date +%Y%m%d-%H%M%S)"
readonly LOG_FILE="${WORK_DIR}/creation.log"

readonly ROOT_CRT="root_ca.crt"
readonly ROOT_KEY="root_ca.key"
readonly ROOT_KEY_GPG="root_ca.key.gpg"
readonly CHECKSUMS="checksums.sha256"

# Brew-PATH for non-login SSH shells (macOS Apple Silicon + Intel)
export PATH="/opt/homebrew/bin:/usr/local/bin:${PATH}"

# ------------------------------------------------------------------------------
# Helper Functions
# ------------------------------------------------------------------------------
if [[ -t 1 ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    BLUE='\033[0;34m'; NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' NC=''
fi

log() {
    local timestamp; timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    if [[ -f "${LOG_FILE}" ]]; then
        echo "[${timestamp}] $*" | tee -a "${LOG_FILE}"
    else
        echo "[${timestamp}] $*"
    fi
}

info()    { echo -e "${BLUE}ℹ️  $*${NC}"; log "INFO: $*"; }
success() { echo -e "${GREEN}✅ $*${NC}"; log "SUCCESS: $*"; }
warn()    { echo -e "${YELLOW}⚠️  $*${NC}"; log "WARN: $*"; }
error()   { echo -e "${RED}❌ $*${NC}" >&2; log "ERROR: $*"; }
die()     { error "$*"; exit 1; }

cleanup() {
    local exit_code=$?
    if [[ -f "${WORK_DIR}/${ROOT_KEY}" ]]; then
        warn "Cleaning up unencrypted private key..."
        secure_delete "${WORK_DIR}/${ROOT_KEY}"
    fi
    if [[ ${exit_code} -ne 0 ]]; then
        error "Script failed! Check ${LOG_FILE} for details."
    fi
    exit ${exit_code}
}

# Cross-platform secure delete (Linux: shred / macOS: gshred (coreutils) / fallback: rm -P)
secure_delete() {
    local file="$1"
    [[ ! -f "${file}" ]] && return 0

    if command -v shred &> /dev/null; then
        shred -vfz -n 10 "${file}" 2>&1 | tee -a "${LOG_FILE}"
    elif command -v gshred &> /dev/null; then
        gshred -vfz -n 10 "${file}" 2>&1 | tee -a "${LOG_FILE}"
    else
        warn "Using rm -P (3-pass) — install coreutils for stronger shred"
        rm -Pv "${file}" 2>&1 | tee -a "${LOG_FILE}"
    fi
}

# ------------------------------------------------------------------------------
# Pre-flight Checks
# ------------------------------------------------------------------------------
preflight_checks() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🔐 Offline Root CA Creation"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    [[ ${EUID} -eq 0 ]] && die "Do not run as root! Use a regular user account."

    if ! command -v step &> /dev/null; then
        die "step CLI not installed! Install via: brew install step (macOS) or smallstep.com/docs"
    fi
    info "step CLI: $(step version 2>/dev/null | head -1 || echo unknown)"

    command -v gpg &> /dev/null || die "GPG not installed!"
    info "GPG: $(gpg --version | head -1)"

    echo ""
    warn "CRITICAL: Verifying air-gap (network MUST be DISABLED)"
    echo ""

    local network_ok=false
    if ping -c 1 -W 2 8.8.8.8 &> /dev/null; then network_ok=true
    elif ping -c 1 -W 2 1.1.1.1 &> /dev/null; then network_ok=true
    elif curl -s --connect-timeout 2 https://example.com &> /dev/null; then network_ok=true
    fi

    if [[ "${network_ok}" == "true" ]]; then
        echo ""
        error "╔══════════════════════════════════════════════════════════════════╗"
        error "║  NETWORK DETECTED! This machine is NOT air-gapped.               ║"
        error "║  Disable WiFi/Ethernet/VPN and run again.                        ║"
        error "╚══════════════════════════════════════════════════════════════════╝"
        die "Aborting due to network connectivity."
    fi

    success "Air-gap verified: No network connectivity detected"
    echo ""

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  CA Name:      ${CA_NAME}"
    echo "  Algorithm:    ${KEY_TYPE} ${CURVE}"
    echo "  Validity:     ${VALIDITY_HOURS}h"
    echo "  Work Dir:     ${WORK_DIR}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    read -rp "Press ENTER to continue or Ctrl+C to abort..."
}

# ------------------------------------------------------------------------------
# Main Steps
# ------------------------------------------------------------------------------
setup_work_directory() {
    info "Creating secure work directory..."
    umask 077
    mkdir -p "${WORK_DIR}"
    chmod 700 "${WORK_DIR}"
    touch "${LOG_FILE}"
    log "=== Root CA Creation Started ==="
    log "Hostname: $(hostname)"
    log "User: $(whoami)"
    log "Date: $(date -Iseconds)"
    success "Work directory: ${WORK_DIR}"
}

create_root_ca() {
    echo ""
    info "Step 1/4: Creating Root CA Certificate (${KEY_TYPE} ${CURVE}, ${VALIDITY_HOURS}h)"
    echo "────────────────────────────────────────────────────────────────────"

    export GPG_AGENT_INFO=""

    # --no-password: key stored unencrypted on disk (we encrypt via GPG below).
    # This avoids double-passphrase and keeps GPG as the single source of truth.
    step certificate create \
        "${CA_NAME}" \
        "${WORK_DIR}/${ROOT_CRT}" \
        "${WORK_DIR}/${ROOT_KEY}" \
        --profile root-ca \
        --kty "${KEY_TYPE}" \
        --curve "${CURVE}" \
        --not-after "${VALIDITY_HOURS}h" \
        --no-password \
        --insecure \
        2>&1 | tee -a "${LOG_FILE}" \
        || die "Failed to create Root CA certificate"

    chmod 644 "${WORK_DIR}/${ROOT_CRT}"
    chmod 600 "${WORK_DIR}/${ROOT_KEY}"

    success "Root CA certificate created"
    echo ""
    info "Certificate details:"
    step certificate inspect "${WORK_DIR}/${ROOT_CRT}" --short
    log "Fingerprint: $(step certificate fingerprint "${WORK_DIR}/${ROOT_CRT}")"
}

encrypt_private_key() {
    echo ""
    info "Step 2/4: GPG-Encrypting Private Key (AES-256)"
    echo "────────────────────────────────────────────────────────────────────"
    echo ""
    warn "You will be asked for a passphrase TWICE."
    warn "IMPORTANT: Store this passphrase in your password manager IMMEDIATELY."
    echo ""

    gpg --symmetric \
        --cipher-algo AES256 \
        --no-symkey-cache \
        --pinentry-mode loopback \
        --output "${WORK_DIR}/${ROOT_KEY_GPG}" \
        "${WORK_DIR}/${ROOT_KEY}" \
        || die "GPG encryption failed"

    chmod 600 "${WORK_DIR}/${ROOT_KEY_GPG}"
    success "Private key encrypted: ${ROOT_KEY_GPG}"
}

wipe_unencrypted_key() {
    echo ""
    info "Step 3/4: Securely wiping unencrypted private key"
    echo "────────────────────────────────────────────────────────────────────"
    secure_delete "${WORK_DIR}/${ROOT_KEY}"
    success "Unencrypted key securely deleted"
}

verify_and_finalize() {
    echo ""
    info "Step 4/4: Verification and checksums"
    echo "────────────────────────────────────────────────────────────────────"

    echo ""
    info "Verifying GPG encryption (enter passphrase to confirm)..."
    if gpg --quiet --decrypt "${WORK_DIR}/${ROOT_KEY_GPG}" > /dev/null 2>&1; then
        success "GPG encryption verified — passphrase works"
    else
        die "GPG decryption FAILED! Passphrase wrong or file corrupt."
    fi

    echo ""
    info "Creating SHA256 checksums..."
    (cd "${WORK_DIR}" && sha256sum "${ROOT_CRT}" "${ROOT_KEY_GPG}" > "${CHECKSUMS}") \
        || die "Failed to create checksums"
    success "Checksums: ${CHECKSUMS}"
    cat "${WORK_DIR}/${CHECKSUMS}"
    log "Checksums: $(cat "${WORK_DIR}/${CHECKSUMS}")"
}

print_summary() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✅ ROOT CA CREATION COMPLETE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "📁 Files in ${WORK_DIR}:"
    ls -la "${WORK_DIR}/"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📋 NEXT STEPS:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "1. Copy files to USB drive (3-2-1 backup rule):"
    echo "   cp ${WORK_DIR}/${ROOT_CRT}     /path/to/usb/"
    echo "   cp ${WORK_DIR}/${ROOT_KEY_GPG} /path/to/usb/"
    echo "   cp ${WORK_DIR}/${CHECKSUMS}    /path/to/usb/"
    echo ""
    echo "2. Verify checksums on USB:"
    echo "   cd /path/to/usb && sha256sum -c ${CHECKSUMS}    # Linux"
    echo "   cd /path/to/usb && shasum -a 256 -c ${CHECKSUMS} # macOS"
    echo ""
    echo "3. Transport USB physically to your CA host"
    echo ""
    echo "4. Install Root cert to /opt/step-ca/certs/root_ca.crt"
    echo "5. KEEP the encrypted key on offline USB (Tresor/safe + redundant copy)"
    echo "6. Store passphrase in password manager — SEPARATE from USB"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    warn "Keep this machine OFFLINE until files are safely copied!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    log "=== Root CA Creation Completed Successfully ==="
}

# ------------------------------------------------------------------------------
main() {
    trap cleanup EXIT INT TERM
    preflight_checks
    setup_work_directory
    create_root_ca
    encrypt_private_key
    wipe_unencrypted_key
    verify_and_finalize
    print_summary
    trap - EXIT
}

main "$@"
