# Scripts Directory

Battle-tested scripts for the three offline-touching operations in the PKI lifecycle.

## ⚡ TL;DR

| Script | Where to run | Purpose |
|--------|-------------|---------|
| `create-root-ca.sh` | Air-gapped machine | One-time Root CA creation (10y, ECDSA P-384, GPG-encrypted) |
| `generate-intermediate-csr.sh` | Production server | Generate Intermediate key + CSR |
| `sign-intermediate-ca.sh` | Air-gapped machine | Sign Intermediate CSR with Root key (5y) |

All three scripts share the same defensive patterns:

- **Air-gap verification** — `create-root-ca.sh` and `sign-intermediate-ca.sh` ping public hosts and **refuse to run** if any network is reachable.
- **Cross-platform secure delete** — `shred` (Linux) → `gshred` (macOS coreutils) → `rm -P` (BSD fallback)
- **Cleanup trap** — Decrypted private keys are always shredded on script exit, including errors and Ctrl+C
- **Verify after encrypt** — After GPG-encrypting the Root key, the script immediately decrypts to confirm the passphrase
- **SHA256 checksums** — Generated for integrity verification across USB transport
- **No emails, no telemetry, no network** — Scripts are inert on the offline machine

## Workflow

```
┌────────────────────────────────┐         ┌─────────────────────────────┐
│  Air-gapped machine            │         │  Production server          │
│  (laptop, no WiFi/Ethernet)    │         │  (where step-ca runs)       │
├────────────────────────────────┤         ├─────────────────────────────┤
│                                │         │                             │
│  1. create-root-ca.sh          │         │                             │
│     → root_ca.crt              │         │                             │
│     → root_ca.key.gpg          │         │                             │
│                                │         │                             │
│         ┌──── USB ─────────────┼─────────► 2. generate-intermediate-   │
│         │                      │         │    csr.sh                   │
│         │  root_ca.crt         │         │    → intermediate_ca.csr    │
│         │                      │ USB ◄───┤                             │
│         │                      │         │                             │
│  3. sign-intermediate-ca.sh    │         │                             │
│     (reads CSR + decrypts key) │         │                             │
│     → intermediate_ca.crt      │         │                             │
│         │                      │ USB ────► 4. Install into             │
│         │                      │         │    /opt/step-ca/certs/      │
│         └────────────────────────────────► 5. Start container          │
└────────────────────────────────┘         └─────────────────────────────┘
```

## Prerequisites

### On the air-gapped machine

```bash
# macOS (Homebrew):
brew install step gnupg coreutils

# Linux (Debian/Ubuntu):
sudo apt install step-cli gnupg coreutils
```

> **Why coreutils on macOS?** macOS ships BSD `rm -P` (3-pass overwrite). GNU `gshred` (10-pass) is stronger and is installed by Homebrew's `coreutils` package.

### On the production server

```bash
# Debian/Ubuntu:
sudo apt install openssl

# Plus Docker (for the step-ca container later)
```

## Configuration

All scripts read defaults from environment variables. See each script's header for the full list. Common overrides:

```bash
# Custom CA name (recommended: include year for rotation tracking):
CA_NAME="HomeLab Root CA 2026" ./scripts/create-root-ca.sh

# Custom Intermediate identity:
INTERMEDIATE_CN="HomeLab Intermediate CA 2026" \
INTERMEDIATE_O="My Org" \
INTERMEDIATE_C="DE" \
  ./scripts/generate-intermediate-csr.sh

# Custom USB mount point:
USB_MOUNT="/Volumes/MyUSB" ./scripts/sign-intermediate-ca.sh
```

## Security Notes

- **The Root CA private key (`root_ca.key.gpg`) MUST never touch the production server.** The sign script reads it from USB only on the air-gapped machine.
- **3-2-1 backup rule** for the encrypted Root key: 3 copies, 2 different media, 1 offsite.
- **Passphrase stored separately** from the encrypted file (password manager, NOT on the USB stick).
- **Filesystem permissions matter**: Scripts set `chmod 600` on private keys, `chmod 700` on work dirs. If the file is read by `step-ca` running in a Docker container, ownership must match the container's user (default `1000:1000`).

## Troubleshooting

See [`docs/TROUBLESHOOTING.md`](../docs/TROUBLESHOOTING.md) for common issues (port conflicts, DNS rebinding, healthcheck failures, etc.).
