#!/bin/bash
# ==============================================================================
# sign-intermediate-ca.sh - Sign Intermediate CA with Offline Root CA
# ==============================================================================
# Purpose:  Sign step-ca Intermediate CA on the same air-gapped machine that
#           holds the Root CA private key.
# Run on:   Air-gapped machine (NO NETWORK!)
#
# Expected input files on USB:
#   root_ca.crt              (public Root cert)
#   root_ca.key.gpg          (GPG-encrypted Root private key)
#   intermediate_ca.csr      (Intermediate CSR, generated on production server)
#
# Output (written to USB):
#   intermediate_ca.crt
#   intermediate-checksums.sha256
#
# Configuration via environment variables (defaults shown):
#   USB_MOUNT             "/Volumes/USB"   (macOS) or "/mnt/usb" (Linux)
#   INTERMEDIATE_VALIDITY "43800h"         (5 years)
#
# Example:
#   USB_MOUNT="/Volumes/MyUSB" ./sign-intermediate-ca.sh
# ==============================================================================

set -euo pipefail

# Brew-PATH for non-login SSH shells
export PATH="/opt/homebrew/bin:/usr/local/bin:${PATH}"

# ------------------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------------------
readonly USB_MOUNT="${USB_MOUNT:-/Volumes/USB}"
readonly WORK_DIR="${HOME}/.ca-signing-$(date +%Y%m%d-%H%M%S)"
readonly INTERMEDIATE_VALIDITY="${INTERMEDIATE_VALIDITY:-43800h}"  # 5 years

readonly ROOT_CA_CRT="${USB_MOUNT}/root_ca.crt"
readonly ROOT_CA_KEY_GPG="${USB_MOUNT}/root_ca.key.gpg"
readonly INTERMEDIATE_CSR="${USB_MOUNT}/intermediate_ca.csr"

readonly DECRYPTED_ROOT_KEY="${WORK_DIR}/root_ca.key"
readonly INTERMEDIATE_CRT="${WORK_DIR}/intermediate_ca.crt"
readonly SIGNING_LOG="${WORK_DIR}/signing.log"
readonly CHECKSUMS="${WORK_DIR}/checksums.sha256"

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
    if [[ -f "${SIGNING_LOG}" ]]; then
        echo "[${timestamp}] $*" | tee -a "${SIGNING_LOG}"
    else
        echo "[${timestamp}] $*"
    fi
}

info()    { echo -e "${BLUE}ℹ️  $*${NC}"; log "INFO: $*"; }
success() { echo -e "${GREEN}✅ $*${NC}"; log "SUCCESS: $*"; }
warn()    { echo -e "${YELLOW}⚠️  $*${NC}"; log "WARN: $*"; }
error()   { echo -e "${RED}❌ $*${NC}" >&2; log "ERROR: $*"; }
die()     { error "$*"; exit 1; }

secure_delete() {
    local file="$1"
    [[ ! -f "${file}" ]] && return 0
    info "Securely deleting: ${file}"
    if command -v shred &> /dev/null; then
        shred -vfz -n 10 "${file}" 2>&1 | tee -a "${SIGNING_LOG}" || true
    elif command -v gshred &> /dev/null; then
        gshred -vfz -n 10 "${file}" 2>&1 | tee -a "${SIGNING_LOG}" || true
    else
        warn "Using rm -P (3-pass) — install coreutils for stronger shred"
        rm -Pv "${file}" 2>&1 | tee -a "${SIGNING_LOG}" || true
    fi
}

sha256_checksum() {
    if command -v sha256sum &> /dev/null; then
        sha256sum "$@"
    else
        shasum -a 256 "$@"   # macOS fallback
    fi
}

cleanup() {
    local exit_code=$?
    if [[ -f "${DECRYPTED_ROOT_KEY}" ]]; then
        warn "Cleaning up decrypted Root CA key..."
        secure_delete "${DECRYPTED_ROOT_KEY}"
        success "Decrypted key securely deleted"
    fi
    if [[ ${exit_code} -ne 0 ]]; then
        error "Script failed! Check ${SIGNING_LOG} for details."
    fi
    exit ${exit_code}
}

# ------------------------------------------------------------------------------
# Pre-flight Checks
# ------------------------------------------------------------------------------
preflight_checks() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🔐 Intermediate CA Signing (Offline)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    [[ ${EUID} -eq 0 ]] && die "Do not run as root! Use a regular user account."

    [[ ! -d "${USB_MOUNT}" ]] && die "USB not mounted! Expected: ${USB_MOUNT} (override via USB_MOUNT=...)"
    info "USB mounted: ${USB_MOUNT}"

    if ! touch "${USB_MOUNT}/.write-test" 2>/dev/null; then
        die "USB is not writable! Check permissions."
    fi
    rm -f "${USB_MOUNT}/.write-test"
    info "USB is writable"

    local missing=false
    for file in "${ROOT_CA_CRT}" "${ROOT_CA_KEY_GPG}" "${INTERMEDIATE_CSR}"; do
        if [[ ! -f "${file}" ]]; then
            error "Missing: ${file}"
            missing=true
        else
            info "Found: $(basename "${file}")"
        fi
    done
    [[ "${missing}" == "true" ]] && die "Required files missing on USB!"

    command -v step &> /dev/null || die "step CLI not installed! brew install step (macOS) or smallstep.com/docs"
    info "step CLI: $(step version 2>/dev/null | head -1)"

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

    success "Air-gap verified: No network connectivity"
    echo ""

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Root CA:           ${ROOT_CA_CRT}"
    echo "  Root Key (GPG):    ${ROOT_CA_KEY_GPG}"
    echo "  Intermediate CSR:  ${INTERMEDIATE_CSR}"
    echo "  Output validity:   ${INTERMEDIATE_VALIDITY}"
    echo "  Work Dir:          ${WORK_DIR}"
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
    touch "${SIGNING_LOG}"
    chmod 600 "${SIGNING_LOG}"
    log "=== Intermediate CA Signing Started ==="
    log "Hostname: $(hostname)"
    log "User: $(whoami)"
    log "Date: $(date -Iseconds)"
    success "Work directory: ${WORK_DIR}"
}

validate_input_files() {
    echo ""
    info "Step 1/5: Validating input files"
    echo "────────────────────────────────────────────────────────────────────"

    echo ""
    info "Root CA Certificate:"
    step certificate inspect "${ROOT_CA_CRT}" --short

    echo ""
    if ! step certificate verify "${ROOT_CA_CRT}" --roots "${ROOT_CA_CRT}" 2>/dev/null; then
        die "Root CA certificate is invalid or expired!"
    fi
    success "Root CA certificate is valid"

    echo ""
    info "Intermediate CA CSR:"
    step certificate inspect "${INTERMEDIATE_CSR}" --short

    echo ""
    if openssl req -in "${INTERMEDIATE_CSR}" -verify -noout 2>/dev/null; then
        success "CSR signature verified"
    else
        warn "Could not verify CSR signature (check format manually)"
    fi
}

decrypt_root_ca_key() {
    echo ""
    info "Step 2/5: Decrypting Root CA Private Key"
    echo "────────────────────────────────────────────────────────────────────"
    echo ""
    warn "Enter GPG passphrase (from password manager)"
    echo ""

    gpg --quiet --no-symkey-cache --decrypt "${ROOT_CA_KEY_GPG}" > "${DECRYPTED_ROOT_KEY}"
    chmod 600 "${DECRYPTED_ROOT_KEY}"
    success "Root CA key decrypted (temporary, will be securely deleted)"
}

sign_intermediate_csr() {
    echo ""
    info "Step 3/5: Signing Intermediate CA CSR"
    echo "────────────────────────────────────────────────────────────────────"

    # --profile intermediate-ca sets the correct extensions:
    # basicConstraints=CA:TRUE,pathlen:0 and keyUsage=keyCertSign,cRLSign
    step certificate sign \
        "${INTERMEDIATE_CSR}" \
        "${ROOT_CA_CRT}" \
        "${DECRYPTED_ROOT_KEY}" \
        --profile intermediate-ca \
        --not-after "${INTERMEDIATE_VALIDITY}" \
        > "${INTERMEDIATE_CRT}" \
        2>>"${SIGNING_LOG}"

    chmod 644 "${INTERMEDIATE_CRT}"
    success "Intermediate CA signed"
    echo ""
    info "Signed Intermediate CA details:"
    step certificate inspect "${INTERMEDIATE_CRT}" --short
    log "Fingerprint: $(step certificate fingerprint "${INTERMEDIATE_CRT}")"
}

verify_chain() {
    echo ""
    info "Step 4/5: Verifying Certificate Chain"
    echo "────────────────────────────────────────────────────────────────────"

    if step certificate verify "${INTERMEDIATE_CRT}" --roots "${ROOT_CA_CRT}" 2>&1 | tee -a "${SIGNING_LOG}"; then
        success "Certificate chain verified: Intermediate → Root"
    else
        die "Certificate chain verification FAILED!"
    fi
}

finalize() {
    echo ""
    info "Step 5/5: Finalizing and copying to USB"
    echo "────────────────────────────────────────────────────────────────────"

    # Delete decrypted key BEFORE copying anything — minimize attack window
    info "Securely deleting decrypted Root CA key..."
    secure_delete "${DECRYPTED_ROOT_KEY}"
    success "Decrypted key deleted"

    echo ""
    info "Creating SHA256 checksums..."
    (cd "${WORK_DIR}" && sha256_checksum "intermediate_ca.crt" > "checksums.sha256")
    success "Checksums created"
    cat "${CHECKSUMS}"

    echo ""
    info "Copying signed certificate to USB..."
    cp "${INTERMEDIATE_CRT}" "${USB_MOUNT}/intermediate_ca.crt"
    cp "${CHECKSUMS}"        "${USB_MOUNT}/intermediate-checksums.sha256"

    if diff -q "${INTERMEDIATE_CRT}" "${USB_MOUNT}/intermediate_ca.crt" > /dev/null; then
        success "Files copied and verified on USB"
    else
        die "File copy verification failed!"
    fi
}

print_summary() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✅ INTERMEDIATE CA SIGNING COMPLETE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "📁 Files on USB (${USB_MOUNT}):"
    ls -lh "${USB_MOUNT}/"*.crt "${USB_MOUNT}/"*.sha256 2>/dev/null || true
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📋 NEXT STEPS:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "1. Re-enable WiFi/network on this machine"
    echo "2. Eject USB safely:"
    echo "   macOS:  diskutil eject ${USB_MOUNT}"
    echo "   Linux:  sync && sudo umount ${USB_MOUNT}"
    echo ""
    echo "3. Transport USB to your CA host (physically or scp)"
    echo "4. Install intermediate_ca.crt to /opt/step-ca/certs/"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    warn "REMINDER: root_ca.key.gpg stays on USB → secure storage (safe + redundant copy)!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# ------------------------------------------------------------------------------
main() {
    trap cleanup EXIT INT TERM
    preflight_checks
    setup_work_directory
    validate_input_files
    decrypt_root_ca_key
    sign_intermediate_csr
    verify_chain
    finalize
    print_summary
    trap - EXIT
}

main "$@"
