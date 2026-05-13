# Coexistence Guide

How step-ca and its supporting infrastructure (typically a private DNS resolver, a Let's Encrypt setup, a VPN, an existing AD) can live on the same host without breaking each other.

## ⚡ TL;DR

step-ca itself is unobtrusive (ports 9200 + 9443, no privileged binds), but most internal-PKI deployments also stand up a private DNS resolver on port 53 — and port 53 is heavily contested. This document collects the patterns that work in practice when port 53, the DNS resolver, a VPN's magic DNS, and an Active Directory live on the same network.

---

## Table of Contents

- [Scenarios](#scenarios)
- [Pattern 1: step-ca alongside an existing ACME-DNS Container](#pattern-1-step-ca-alongside-an-existing-acme-dns-container)
- [Pattern 2: step-ca alongside Tailscale / WireGuard MagicDNS](#pattern-2-step-ca-alongside-tailscale--wireguard-magicdns)
- [Pattern 3: step-ca alongside Windows Active Directory DNS](#pattern-3-step-ca-alongside-windows-active-directory-dns)
- [Pattern 4: Multiple step-ca instances per site](#pattern-4-multiple-step-ca-instances-per-site)
- [Verification Checklist](#verification-checklist)

---

## Scenarios

The patterns below assume this combined goal:

- **step-ca** serves internal X.509 certs for `*.internal` (or your chosen private TLD)
- **A local DNS resolver** (typically dnsmasq) resolves `*.internal` names to internal IPs
- One or more of these is also running:
  - **acme-dns** — to validate public Let's Encrypt certificates via DNS-01 (port 53 from the public Internet)
  - **Tailscale / WireGuard** — VPN with its own DNS resolver on `100.100.100.100` or similar
  - **Active Directory** — Windows DNS authoritative for an internal `*.local` (or other) domain

Each combination has working patterns. Pick the one that matches your stack.

---

## Pattern 1: step-ca alongside an existing acme-dns Container

**Conflict:** Both your private DNS resolver (e.g. dnsmasq for `*.internal`) and acme-dns want port 53 on the same host.

**Recommended:** Keep acme-dns reachable from the public Internet (Let's Encrypt's DNS validators query it), but move its host port off 53 and forward externally.

### Step 1 — Move acme-dns to alternative host port

```yaml
# docker-compose.yml of acme-dns
services:
  acme-dns:
    image: joohoi/acme-dns:v1.0
    ports:
      - "0.0.0.0:5343:53/tcp"     # was 0.0.0.0:53:53/tcp
      - "0.0.0.0:5343:53/udp"
      - "127.0.0.1:8053:80/tcp"   # API port (unchanged, internal use)
```

Recreate: `docker compose down && docker compose up -d`

### Step 2 — Reconfigure router port-forwarding

```
External 53/tcp + 53/udp  →  <internal-host>:5343
```

That's the only change Let's Encrypt sees: external port stays `53`, internal target is now `5343`.

### Step 3 — Install your `*.internal` resolver on port 53

```bash
# Now port 53 is free
sudo apt install dnsmasq
# Configure /etc/dnsmasq.d/internal.conf (see Pattern 2 for bind-interfaces)
```

### Step 4 — Verify end-to-end

```bash
# Local resolver works
dig @127.0.0.1 service.internal +short

# acme-dns still reachable via public IP / port 53
dig @<public-ip> auth.acme-dns.example.com +short

# Run a real Let's Encrypt dry-run renewal
sudo certbot renew --cert-name <some.example.com> --dry-run
```

---

## Pattern 2: step-ca alongside Tailscale / WireGuard MagicDNS

**Conflict:** Tailscale's `tailscaled` runs an internal DNS resolver on the Tailscale-assigned IP (typically `100.100.100.100`). dnsmasq's default behavior binds to **all interfaces**, intercepts queries on the Tailscale interface, and breaks MagicDNS — even if your dnsmasq config has `listen-address=` set, without `bind-interfaces` it can still grab additional sockets.

**Confirming the symptom:**

```bash
# dnsmasq logs at startup:
# LOUD WARNING: listening on 100.x.x.x may accept requests via interfaces other than tailscale0

# Tailscale DNS no longer answers:
dig @100.100.100.100 example.com +short
# (times out)
```

**Solution: `bind-interfaces` + explicit `listen-address=`**

```conf
# /etc/dnsmasq.d/internal.conf

# Bind ONLY to these IPs (LAN + loopback). Tailscale-IP must NOT be in this list.
listen-address=192.0.2.5,127.0.0.1

# Without bind-interfaces dnsmasq still wildcard-binds before filtering.
bind-interfaces

# Optional: explicit upstreams (don't follow /etc/resolv.conf which Tailscale rewrites)
no-resolv
server=192.0.2.1     # your gateway / internal AD-DNS
server=1.1.1.1       # fallback

# Internal zone:
local=/internal/
domain=internal
```

**After restart, verify Tailscale DNS still works:**

```bash
sudo systemctl restart dnsmasq
dig @100.100.100.100 example.com +short   # must return answer
dig @127.0.0.1 service.internal +short    # must return your internal IP
```

> If you have **multiple internal interfaces** (e.g. a VPN bridge + LAN), list each in `listen-address=`. Never use `0.0.0.0` or omit `listen-address=` on a host that also runs Tailscale/WireGuard.

---

## Pattern 3: step-ca alongside Windows Active Directory DNS

**Scenario:** Your Windows AD already has an authoritative DNS for `corp.local` (or similar). You want to add `*.internal` for non-Windows infrastructure without disturbing AD.

**Two layouts work; pick by who you control:**

### Layout A: You control both DNS servers (full coexistence)

Both DNS servers know about each other:

- **AD-DNS** (e.g. 192.0.2.10) is authoritative for `corp.local`. Add a **conditional forwarder** for `internal` → your step-ca host.
- **Your dnsmasq** (e.g. 192.0.2.5) is authoritative for `internal`. Forwards everything else (including `*.corp.local`) to AD-DNS.

```conf
# /etc/dnsmasq.d/internal.conf
listen-address=192.0.2.5,127.0.0.1
bind-interfaces
no-resolv
server=/corp.local/192.0.2.10    # forward AD-domain queries to AD-DNS
server=192.0.2.10                # everything else also via AD-DNS first
server=1.1.1.1                   # external fallback
local=/internal/
domain=internal
```

Windows admin adds in DNS Manager:
```
Conditional Forwarders → New → "internal" → 192.0.2.5
```

### Layout B: You can't touch AD-DNS

Windows clients have AD-DNS hardcoded by Group Policy; you can't add a conditional forwarder. Then:

- Add per-machine `hosts` entries on Windows clients that need to reach `*.internal` services.
- Or: configure individual non-domain-joined machines (Linux servers, Macs) to use your dnsmasq directly as their resolver.

This is uglier but real-world common.

### Sub-pitfall: AD-DNS returns private IPs

When dnsmasq forwards `dc.corp.local` to AD-DNS, AD returns `192.0.2.10`. By default, dnsmasq's `stop-dns-rebind` filter strips RFC1918 IPs from responses — your clients get empty answers.

**Fix:** Whitelist the AD domain:

```conf
stop-dns-rebind
rebind-localhost-ok
rebind-domain-ok=/corp.local/
rebind-domain-ok=/internal/
```

---

## Pattern 4: Multiple step-ca instances per site

**Scenario:** Multi-site organization where each site runs its own step-ca for its own `*.internal` namespace (e.g. headquarters + branch office, connected via VPN).

**Pitfall:** Both sites use plain `*.internal` for their local services. A laptop that roams between sites or uses VPN crossing sites sees overlapping namespaces (`db.internal` resolves to different IPs at HQ vs. branch). DNS cache and `/etc/hosts` make this worse.

**Two clean strategies:**

### A) Sub-namespace per site (recommended for new deployments)

- HQ uses `*.internal` (existing)
- Branch uses `*.branch.internal` (sub-namespace)

Browsers, certs, and DNS all see distinct names, no overlap.

### B) Disjoint service names within `*.internal`

If both sites must use plain `*.internal`, ensure **no service name overlaps**. Document the namespace map.

```
HQ:     bookstack.internal, nextcloud.internal, paperless.internal
Branch: crm.internal, scan.internal, devices.internal
```

Either strategy works; the first scales better.

> **Note on ICANN:** `.internal` is reserved by ICANN (Board Resolution 2024-01-28) for private use — guaranteed to never be delegated as a public TLD. Other historically-used private TLDs (`.lan`, `.home`, `.corp`) are **not** reserved; prefer `.internal` for greenfield deployments.

---

## Verification Checklist

After any change to DNS, port mapping, or VPN integration:

```bash
# 1. Local resolver answers internal names
dig @127.0.0.1 some-internal-service.internal +short

# 2. Tailscale/WireGuard DNS still works (if applicable)
dig @100.100.100.100 example.com +short

# 3. External DNS still works (forwarded chain)
dig @127.0.0.1 google.com +short

# 4. Active Directory names still resolve (if applicable)
dig @127.0.0.1 dc.corp.local +short

# 5. acme-dns still answers public queries (if applicable)
dig @<public-ip> auth.acme-dns.example.com +short

# 6. Real Let's Encrypt cycle works end-to-end
sudo certbot renew --cert-name <some-domain> --dry-run

# 7. step-ca itself still healthy
curl -k https://localhost:9643/health
```

If any of these break, see [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md) → DNS / Network Coexistence Issues.
