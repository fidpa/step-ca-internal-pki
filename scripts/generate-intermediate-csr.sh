#!/bin/bash
# ==============================================================================
# generate-intermediate-csr.sh - Generate Intermediate CA Key + CSR
# ==============================================================================
# Purpose:  Generate Intermediate CA private key + CSR on the production server.
#           The CSR is then transported to the air-gapped Root CA host for
#           signing (see sign-intermediate-ca.sh).
#
# Run on:   Production server (NOT air-gapped — Internet OK)
# Run as:   regular user with sudo
#
# Output:
#   /opt/step-ca/secrets/intermediate_ca_key   (ECDSA P-256, 600, owned by 1000:1000)
#   /tmp/intermediate_ca.csr                   (transfer this to the air-gapped host)
#
# Configuration via environment variables (defaults shown):
#   STEP_CA_DIR        "/opt/step-ca"
#   INTERMEDIATE_CN    "HomeLab Intermediate CA"
#   INTERMEDIATE_O     "HomeLab"
#   INTERMEDIATE_C     "US"
#   CONTAINER_UID      "1000"
#   CONTAINER_GID      "1000"
#
# Example:
#   INTERMEDIATE_CN="My Internal Intermediate CA 2026" \
#   INTERMEDIATE_O="Acme Corp" \
#   INTERMEDIATE_C="DE" \
#     ./generate-intermediate-csr.sh
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# Configuration (override via ENV)
# ------------------------------------------------------------------------------
readonly STEP_CA_DIR="${STEP_CA_DIR:-/opt/step-ca}"
readonly INTERMEDIATE_CN="${INTERMEDIATE_CN:-HomeLab Intermediate CA}"
readonly INTERMEDIATE_O="${INTERMEDIATE_O:-HomeLab}"
readonly INTERMEDIATE_C="${INTERMEDIATE_C:-US}"
readonly CONTAINER_UID="${CONTAINER_UID:-1000}"
readonly CONTAINER_GID="${CONTAINER_GID:-1000}"

readonly KEY_PATH="${STEP_CA_DIR}/secrets/intermediate_ca_key"
readonly CSR_PATH="/tmp/intermediate_ca.csr"

# ------------------------------------------------------------------------------
# Helper Functions
# ------------------------------------------------------------------------------
if [[ -t 1 ]]; then
    GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
else
    GREEN='' YELLOW='' RED='' NC=''
fi

info()    { echo -e "${GREEN}ℹ️  $*${NC}"; }
warn()    { echo -e "${YELLOW}⚠️  $*${NC}"; }
die()     { echo -e "${RED}❌ $*${NC}" >&2; exit 1; }

# ------------------------------------------------------------------------------
# Pre-flight Checks
# ------------------------------------------------------------------------------
[[ ${EUID} -eq 0 ]] && die "Do not run as root! Use a regular user account (script will sudo as needed)."

command -v openssl &> /dev/null || die "openssl not installed!"

if [[ ! -d "${STEP_CA_DIR}/secrets" ]]; then
    die "step-ca secrets directory missing: ${STEP_CA_DIR}/secrets (run setup first)"
fi

if [[ -f "${KEY_PATH}" ]]; then
    warn "Intermediate key already exists at ${KEY_PATH}"
    read -rp "Overwrite? This will INVALIDATE any existing signed Intermediate cert! [y/N] " confirm
    [[ "${confirm,,}" == "y" ]] || die "Aborted."
fi

# ------------------------------------------------------------------------------
# Generate Key + CSR
# ------------------------------------------------------------------------------
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔐 Intermediate CA Key + CSR Generation"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Subject:  /C=${INTERMEDIATE_C}/O=${INTERMEDIATE_O}/CN=${INTERMEDIATE_CN}"
echo "  Key:      ${KEY_PATH} (ECDSA P-256, 600, ${CONTAINER_UID}:${CONTAINER_GID})"
echo "  CSR:      ${CSR_PATH}"
echo ""
read -rp "Press ENTER to continue or Ctrl+C to abort..."

info "Generating ECDSA P-256 private key..."
sudo openssl ecparam -genkey -name prime256v1 -noout -out "${KEY_PATH}"
sudo chmod 600 "${KEY_PATH}"
sudo chown "${CONTAINER_UID}:${CONTAINER_GID}" "${KEY_PATH}"
info "Key created: ${KEY_PATH}"

echo ""
info "Generating CSR..."
# NOTE: --profile intermediate-ca in step certificate sign will inject the
# correct extensions (basicConstraints:CA, keyUsage:keyCertSign,cRLSign),
# so the CSR itself only carries Subject. Keeps it simple.
sudo openssl req -new \
    -key "${KEY_PATH}" \
    -out "${CSR_PATH}" \
    -subj "/C=${INTERMEDIATE_C}/O=${INTERMEDIATE_O}/CN=${INTERMEDIATE_CN}"
sudo chmod 644 "${CSR_PATH}"
sudo chown "$(id -u):$(id -g)" "${CSR_PATH}"

echo ""
info "Verifying CSR..."
openssl req -in "${CSR_PATH}" -verify -noout 2>&1 | head -2
openssl req -in "${CSR_PATH}" -text -noout | grep -E "Subject:|Public Key Algorithm|ASN1 OID" | head -5

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ DONE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Next steps:"
echo ""
echo "1. Transfer CSR to your air-gapped Root CA host:"
echo "   scp ${CSR_PATH} user@air-gapped-host:/path/to/usb/"
echo "   (or copy to USB stick)"
echo ""
echo "2. On the air-gapped host, run: scripts/sign-intermediate-ca.sh"
echo ""
echo "3. Bring back intermediate_ca.crt and install:"
echo "   sudo install -o ${CONTAINER_UID} -g ${CONTAINER_GID} -m 644 \\"
echo "       intermediate_ca.crt ${STEP_CA_DIR}/certs/intermediate_ca.crt"
echo ""
warn "Keep ${KEY_PATH} secure — anyone with this key can issue valid service certs!"
echo ""
