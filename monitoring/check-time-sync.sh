#!/bin/bash
# Copyright (c) 2026 Marc Allgeier (fidpa)
# SPDX-License-Identifier: MIT
# https://github.com/fidpa/step-ca-internal-pki

# NTP Time Synchronization Check Script
#
# Purpose: Validate system clock synchronization before certificate operations
# Trigger: Run via systemd timer (recommended: hourly) or before renewals
#
# Why this matters for PKI:
#   - Certificates have notBefore/notAfter validity periods
#   - Incorrect system time can cause valid certs to appear expired
#   - Clock drift between CA and clients causes TLS handshake failures
#   - NTP desynchronization can lead to silent certificate validation failures
#
# Configuration:
#   MAX_OFFSET_SECONDS - Maximum acceptable clock offset (default: 60)
#
# Exit codes:
#   0 - Time synchronized within acceptable offset
#   1 - Time NOT synchronized or offset exceeds threshold

set -uo pipefail

# Configuration
readonly MAX_OFFSET_SECONDS="${MAX_OFFSET_SECONDS:-60}"
readonly LOG_PREFIX="[step-ca-time-sync]"

# Simple inline logging (no external dependencies)
log_info()  { echo "[INFO]  $(date '+%Y-%m-%d %H:%M:%S') $LOG_PREFIX $*"; }
log_error() { echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') $LOG_PREFIX $*" >&2; }
log_success() { echo "[OK]    $(date '+%Y-%m-%d %H:%M:%S') $LOG_PREFIX $*"; }

# Help function
usage() {
    cat << 'EOF'
NTP Time Synchronization Check Script

USAGE:
    check-time-sync.sh [OPTIONS]

OPTIONS:
    -h, --help     Show this help message and exit

DESCRIPTION:
    Validates system clock synchronization before certificate operations.
    Critical for PKI: clock drift causes certificate validation failures.

ENVIRONMENT VARIABLES:
    MAX_OFFSET_SECONDS    Maximum acceptable clock offset (default: 60)

EXIT CODES:
    0    Time synchronized within acceptable offset
    1    Time NOT synchronized or offset exceeds threshold

EXAMPLES:
    # Basic check with defaults (60 second threshold)
    check-time-sync.sh

    # Stricter threshold (5 seconds)
    MAX_OFFSET_SECONDS=5 check-time-sync.sh

    # Use in renewal script
    check-time-sync.sh || exit 1
    renew-service-cert.sh

EOF
    exit 0
}

# Parse arguments
[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && usage

# Check NTP synchronization status
check_time_sync() {
    log_info "Checking NTP synchronization (max offset: ${MAX_OFFSET_SECONDS}s)..."

    # Method 1: timedatectl (systemd)
    if command -v timedatectl >/dev/null 2>&1; then
        if ! timedatectl show 2>/dev/null | grep -q "NTPSynchronized=yes"; then
            log_error "NTP not synchronized (timedatectl reports NTPSynchronized=no)"
            log_error "Fix: systemctl restart systemd-timesyncd"
            return 1
        fi
        log_info "timedatectl: NTP synchronized"
    else
        log_info "timedatectl not available, skipping systemd check"
    fi

    # Method 2: chronyc offset check (if available)
    if command -v chronyc >/dev/null 2>&1; then
        # Get offset in seconds (may be float like 0.000123 or -0.000456)
        offset_raw=$(chronyc tracking 2>/dev/null | awk '/Last offset/ {print $4}')

        if [[ -z "$offset_raw" ]]; then
            log_info "chronyc: Could not determine offset (chrony may not be running)"
        else
            # Remove negative sign for absolute value comparison
            offset_abs=${offset_raw#-}

            # POSIX-compliant comparison: convert to milliseconds via awk (no bc required)
            offset_ms=$(echo "$offset_abs" | awk '{printf "%.0f", $1 * 1000}')
            threshold_ms=$((MAX_OFFSET_SECONDS * 1000))

            if [[ $offset_ms -gt $threshold_ms ]]; then
                log_error "Clock offset ${offset_raw}s exceeds ${MAX_OFFSET_SECONDS}s threshold"
                log_error "Fix: chronyc makestep"
                return 1
            fi

            log_info "chronyc: Clock offset ${offset_raw}s within threshold"
        fi
    else
        log_info "chronyc not available, skipping offset check"
    fi

    # Method 3: ntpstat (legacy NTP)
    if command -v ntpstat >/dev/null 2>&1; then
        if ! ntpstat >/dev/null 2>&1; then
            log_error "NTP not synchronized (ntpstat reports unsynchronized)"
            return 1
        fi
        log_info "ntpstat: NTP synchronized"
    fi

    log_success "Time synchronization OK"
    return 0
}

# Main
check_time_sync
