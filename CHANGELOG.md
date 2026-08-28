# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned
- ACME protocol support for automated certificate requests
- Web UI for certificate management
- Additional service integration examples (GitLab, Grafana, Authentik, Keycloak)
- Grafana dashboard templates for certificate expiry visualization
- mTLS examples for service-to-service authentication

## [1.3.8] - 2026-08-28: GitHub identifies the project as MIT-licensed

### Changed

- **The repository page shows the MIT licence, and licence-filtered searches
  find the project.** `LICENSE` carried the repository URL on its own line
  under the copyright notice. GitHub reads a licence text with an extra line as
  modified and reports `NOASSERTION`, which leaves the licence field on the
  repository page empty. The line is gone; the MIT text and the copyright
  notice are byte-for-byte unchanged, and the URL is still in `README.md`.

## [1.3.7] - 2026-08-27: Editorial sections state what holds, not how much did not

A release page says what now holds. How long something was wrong, how many statements a
check did not survive and which internal steps led there address the maintainer, not the
reader, and they push the corrections themselves into the background. The rule this
repository follows now is that the tally stays out of the release page while every
correction keeps its own entry, with its effect and its anchor in the code.

Nothing in the scripts, the systemd templates, the CA configuration or the monitoring
rules changed; a CA in operation needs no action.

### Changed
- **The editorial sections open with what was put right, not with a count of what was
  wrong.** The introductions to `[1.3.3]`, `[1.3.4]` and `[1.3.5]` no longer carry the
  number of corrected statements, the span of time they had stood, or the count of manual
  steps that preceded the fix. Each individual correction stays exactly where it was, as
  its own entry with its effect and its file, function or tag reference.
- **The `[1.3.3]` headline names the pass, not its yield.** It carried a count of corrected
  statements, which made the tally the first thing a visitor read in the release list and
  on the release page. The published title of `v1.3.3` was set to match.

### Upgrade notes

Nothing to do. This release changes changelog text only.

## [1.3.6] - 2026-08-27: Published body matches the changelog section byte for byte

The title extraction added in 1.3.5 worked on the first tag that used it, and the check
that followed found the one remaining difference between a published body and the section
it comes from: a single leading blank line, contributed by the workflow rather than by the
changelog.

### Fixed

- **The release body no longer starts with a blank line.** `release.yml` printed the empty
  line that follows a section heading, so comparing the published body against its
  changelog section byte for byte reported a difference on every release, while GitHub
  rendered both identically. The extraction now drops leading blank lines
  (`sed -e '/./,$!d'`). This release is the first one produced with it; the body of 1.3.5
  was corrected in place with `gh release edit`

## [1.3.5] - 2026-08-27: Release titles survive the next tag push

Every release since 1.0.0 was published by `.github/workflows/release.yml`, which handed
`softprops/action-gh-release` a body but no name. The action then falls back to the tag,
so each release page opened with the bare version that the release list already shows
next to it, and the title had to be corrected by hand afterwards. The workflow now derives
the title from the changelog itself, which removes the manual step rather than repeating
it.

### Changed

- **A tag push now produces the finished release title, with no manual correction.**
  `release.yml` reads the headline from the section heading it already cuts the body from
  and passes it to the action as `name:`, so title and body come from one source and
  cannot drift apart. Without a headline the workflow logs a warning and falls back to the
  bare tag, which is the old behaviour rather than a failure
- **Every version heading carries its headline** (`## [X.Y.Z] - YYYY-MM-DD: <headline>`).
  The headlines are the titles published on 27 August 2026, moved into the file that the
  workflow reads. This is what makes the change above work: the heading is now the single
  place a release title comes from
- **The body extraction anchors on the start of the line.** It used
  `sed -n "/^## \[${VERSION}\]/,/^## \[/p"`, and now that headings carry prose, a version
  number appearing inside a headline could match before the real heading does. The `awk`
  form tests `index($0, head) == 1`

### Fixed

- **The version in `README.md` had been stuck at 1.3.2 for two releases.** Both the badge
  in line 3 and the footer line said `1.3.2` while 1.3.3 and 1.3.4 were published;
  `git show v1.3.3:README.md` and `git show v1.3.4:README.md` carry the stale value. Both
  now read 1.3.5. The rest of the footer was counted and left as it stood: 8 scripts
  (`git ls-files | grep -c '.sh$'`), 7 core docs under `docs/`, 12 READMEs beside the
  top-level one

## [1.3.4] - 2026-08-27: Documentation entries lead with the effect, not the file name

Follow-up to the editorial pass in 1.3.3, which covered the entries that anchor
on code. Documentation and repository-metadata entries opened with a file name
instead of with what changed. The style guide exempts such entries from naming a
place in the code, because there is none, but not from stating what changed for
the reader.

### Changed

- **Seven documentation entries lead with what changed instead of with a file
  name.** They opened with a bold `docs/BACKUP.md`, `systemd/README.md`,
  `docs/TROUBLESHOOTING.md`, `docs/SETUP.md`, `docs/ARCHITECTURE.md`,
  `CODE_OF_CONDUCT.md` or `.gitignore` and left the consequence to the reader.
  Covering the paragraph, none of the seven bold lines made a statement. Each
  now names the effect and keeps the file in the paragraph below: the exFAT
  entry, for instance, opens with the offline USB stick being readable on Linux
  and macOS both. The entries span 1.2.0, 1.2.1, 1.3.0 and 1.3.1; no other text
  in those sections changed.

## [1.3.3] - 2026-08-27: Changelog rewritten against the style guide

Editorial pass over the whole file against a written style guide, not by feel.
Nothing in the scripts, the systemd templates, the CA configuration or the
monitoring rules changed; a CA in operation needs no action. Statements of fact
are corrected where the code contradicted them; they are listed below.

The rules live outside this repository and apply to all repositories of this
portfolio. They were settled after reading Keep a Changelog, Common Changelog
and the Kubernetes release-notes guide, and they differ from Common Changelog in
two deliberate points: entries are not single-line, and they anchor on a file,
function or config variable rather than on a commit, because this repository has
one commit per release and every commit reference would point at the release's
own commit.

### Fixed

#### Statements corrected against the code

- **The 1.0.0 feature list counted four scripts where the tag carries five.**
  It read "Scripts (4 total)" and named `renewal/renew-service-cert.sh`,
  `monitoring/cert-exporter.sh`, `revocation/revoke-cert.sh` and
  `examples/cert-request-template.sh`. `git ls-tree -r v1.0.0` lists five `.sh`
  files; `monitoring/check-time-sync.sh` shipped in that tag and was missing
  from the list. It is named now and the count says five.

- **The 1.0.0 entry claimed three browsers where the document covers one.** The
  `docs/CLIENT_TRUST.md` line read "5 OSes, 3 browsers". The five operating
  systems check out (Debian/Ubuntu, RHEL/CentOS/Arch, macOS, Windows, iOS and
  Android). Only Firefox has a section, because only Firefox keeps its own trust
  store; Chrome, Edge and Safari read the OS store the guide already covers. The
  entry says so instead of counting three.

- **The 1.0.0 documentation-quality claims were true of six files, not of all
  of them.** "All docs >100 lines have 20-word summaries" and "All docs >300
  lines have navigable ToC" hold for the six guides under `docs/`. Measured
  against the v1.0.0 tag, ten Markdown files over 100 lines carry no TL;DR
  (`README.md`, `SECURITY.md`, `docs/README.md` and the six example READMEs
  among them), and five files over 300 lines carry no table of contents. The
  entry now names the six guides as its scope.

### Changed

- **Entries lead with what changed for the operator, not with what changed in
  the code.** The bold first sentence now carries the effect and the paragraph
  below it the cause. Before this pass, 24 of 68 bold lines opened with a file
  or function name in backticks and left the consequence to the reader; the
  1.3.2 entry, for instance, began "Missing executable bit on 7 of 8 tracked
  scripts" and now begins with the `Permission denied` that an operator
  following the README actually hit.

- **Tense follows what is being described.** Past tense for what went wrong,
  present tense for what holds now, instead of forcing both into one form.

- **Typographic characters are gone from the whole file.** 33 lines carried an
  em dash, and single lines carried an arrow or a double arrow. The em dash
  stood for a colon, a parenthesis and a causal clause in the same paragraph,
  so each occurrence asked the reader to guess which one was meant. Value
  changes are written out (`644` to `755`), and the warning and severity emoji
  in the 1.0.0 section were replaced by the word they stood for. The file is
  plain ASCII now, which the release bodies cut from it inherit.

- **New behaviour states what it does when it cannot work.** The 1.3.0 entries
  for `--force`, for the public-key match check and for
  `EXPORT_CONTAINER_METRIC` now say what happens in the failure case, not only
  in the normal one.

- **The never-released 1.1.0 section no longer states a script count.** It read
  "All 4 scripts now verify required dependencies". Versions 1.1.0 and 0.9.0
  were documented here but never tagged, so there is no tree to count against
  and the number could not be checked either way. The scripts it names are
  unchanged; only the claim about their number is dropped.

### Notes

Every measured value, path, function name and config variable in this file is
unchanged. What changed is the order of the sentences, the tense, the
punctuation and the four counts named above.

## [1.3.2] - 2026-08-11: Documented script invocations work without bash

### Fixed

- **The script invocations printed in the README failed with `Permission
  denied`.** Seven of the eight tracked scripts were mode `644` in the
  repository: `monitoring/cert-exporter.sh`, `monitoring/check-time-sync.sh`,
  `renewal/renew-service-cert.sh`, `revocation/revoke-cert.sh`,
  `scripts/create-root-ca.sh`, `scripts/generate-intermediate-csr.sh` and
  `scripts/sign-intermediate-ca.sh`. `README.md` and `scripts/README.md`
  document direct invocation (`./scripts/create-root-ca.sh`,
  `./scripts/generate-intermediate-csr.sh`, `./scripts/sign-intermediate-ca.sh`),
  so following the documentation literally did not work; only
  `bash scripts/create-root-ca.sh` got around it. All seven are mode `755` now.
  `examples/cert-request-template.sh` stays at `644` on purpose: it is a
  template meant to be copied and edited, not executed in place. No script
  content changed.

## [1.3.1] - 2026-08-09: Root CA scripts covered by CI and release pages carry the changelog

Housekeeping release. **No behavioral changes**: the scripts, the systemd unit
templates, the CA configuration and the monitoring rules are byte-identical to
v1.3.0. Everything here is CI coverage, repository metadata and documentation
links. A CA already in operation needs no action.

### Fixed

- **The three most security-critical scripts of the project were never linted.**
  The `shellcheck` and `syntax-check` jobs in `.github/workflows/lint.yml` both
  listed `monitoring/ renewal/ revocation/ examples/` only, which left
  `scripts/create-root-ca.sh`, `scripts/generate-intermediate-csr.sh` and
  `scripts/sign-intermediate-ca.sh` out: Root CA creation and offline
  intermediate signing. Coverage was 5 of 8 tracked scripts and is 8 of 8 now.
  All three pass at `--severity=error`.

- **Three links in `CHANGELOG.md` answered with 404.** Versions 1.1.0 and 0.9.0
  are documented in this file but were never tagged and never released, so
  `compare/v1.0.1...v1.1.0`, `compare/v1.1.0...v1.2.0` and
  `releases/tag/v0.9.0` all pointed at nothing. `[1.2.0]` compares against the
  nearest existing tag (`v1.0.1`) now, and the link definitions for 1.1.0 and
  0.9.0 were dropped rather than invented: their headings render as plain text,
  which is an accurate reflection of their status. A comment at the end of the
  file records the reason. The missing tags are deliberately not created after
  the fact, because a tag push triggers the release workflow and would publish
  a release for a version that never shipped.

- **The 1.3.0 heading had been rendering as plain text since July.** Its link
  definition in `CHANGELOG.md` was missing, and `[Unreleased]` still compared
  against `v1.2.1`. Both are corrected.

- **The "Why I Built This" section of `README.md` used a second, unrelated
  example address.** It now reuses `192.168.1.50`, the address from the problem
  statement at the top of the same file.

### Changed

- **The release page of a tag now carries the changelog section of that tag.**
  `.github/workflows/release.yml` cuts the notes from `CHANGELOG.md` instead of
  generating them from commit messages. This repository's commits are bare
  `vX.Y.Z` lines, so `generate_release_notes: true` produced an essentially
  empty release page while the content sat in the changelog; the bodies of
  v1.0.1 through v1.3.0 were each pasted in by hand afterwards. For a PKI
  project that is more than cosmetic, because users decide from the release page
  whether an update is security-relevant. The workflow fails loudly when no
  changelog section exists for the tag, and `softprops/action-gh-release` moved
  from `@v1` (deprecated Node runtime) to `@v2`.

- **The `severity=warning` line in `.shellcheckrc` never had any effect.** It
  was replaced by a comment explaining why: ShellCheck has no `severity` key for
  `.shellcheckrc` and discards unknown keys without a message. Verified with
  ShellCheck 0.9.0, where `severity=warning`, `severity=style` and a made-up key
  produced identical output, while adding a code to `disable=` did change it.
  The binding threshold is the `--severity=` flag in `lint.yml`. The header
  comment of the same file described another project's device inventory and
  referenced a `script-audit.sh` that does not exist here; it describes this
  repository now.

- **Local agent tooling can no longer be committed by accident.** `.gitignore`
  covers `.claude/` now.

## [1.3.0] - 2026-07-03: Renewal failures become visible

Lessons from a production review of the renewal pipeline: short journald
retention had swallowed the nightly renewal logs, and a cert-consumer host had
run without expiry metrics for months. All changes are environment-neutral.

### Added

- **A certificate can be re-issued immediately after its SAN list changes.**
  `renewal/renew-service-cert.sh` takes a `--force` flag that bypasses the
  days-left threshold. Editing the `.san` file alone changed nothing until the
  threshold was reached, because the next timer run still saw a certificate with
  enough life left. Without `--force` the script keeps its previous behaviour
  and exits without renewing.

- **A renewal that produced a foreign or stale certificate is caught before
  deployment.** `renewal/renew-service-cert.sh` compares the public key of the
  signed certificate against the key it just generated and aborts the deployment
  on a mismatch, leaving the certificate in place that nginx is currently
  serving.

- **A failing nightly renewal reports itself.**
  `systemd/step-ca-renew-failure-notify.service.template` is an `OnFailure=`
  hook with webhook, mail and ntfy examples. Renewals run unattended at night,
  and without a hook the first symptom of a failing renewal was a browser
  warning weeks later. The template ships commented out, so a host that does not
  install it behaves as before.

- **A host with short journald retention can keep the renewal log.**
  `systemd/step-ca-renew.service.template` carries a commented
  `StandardOutput=append:` option. On a host whose retention is shorter than one
  night, a failed 03:30 run left no trace by morning.

- **A cert-consumer host no longer raises `StepCAContainerDown` forever.**
  `monitoring/cert-exporter.sh` takes an `EXPORT_CONTAINER_METRIC` toggle,
  default `true`. On a host without the step-ca container the hardcoded
  `step_ca_container_up 0` made the alert fire permanently; setting the toggle
  to `false` omits the metric entirely, so the alert has no series to fire on
  and the expiry metrics keep being written.

### Fixed

- **The renewal unit failed to load on Debian 12.**
  `systemd/step-ca-renew.service.template` carried `Restart=on-failure`, and
  systemd rejects `Restart=` for `Type=oneshot` units before v254, which is
  what Debian 12 ships (v252). The directive is removed; the daily timer is the
  retry mechanism.

### Changed

- **A failing CA call shows its actual error.** The `2>/dev/null` on the
  `openssl x509 -req` signing call in `renewal/renew-service-cert.sh` and
  `examples/cert-request-template.sh` is gone, so a bad extfile, an unreadable
  key or serial trouble is named instead of hidden behind a generic message.

- **A reboot no longer locks non-root signers out of the serial lockfile.** The
  lockfile is created with `touch` plus `chmod 666`. `/var/lock` is tmpfs, so
  after a reboot a root-owned `0644` lockfile shut out anyone signing without
  root, for example over SSH.

- **Two documents follow the same Markdown style as the rest.**
  `CODE_OF_CONDUCT.md` and `docs/ARCHITECTURE.md` use `-` list markers and
  `_italic_` now. Formatting only, no content changes.

## [1.2.1] - 2026-05-13: Why the setup needs two offline sessions

Patch release. Documentation only, no behavioral changes and no script changes.

### Added

- **The most common first-time question is answered in the architecture
  document.** `docs/ARCHITECTURE.md` has a new section, "Why Two Offline
  Sessions?", explaining the forced sequence (Root offline, Intermediate CSR
  online, Intermediate signing offline) and why each step has to live where it
  does. It includes a notary and vault analogy and a renewal-frequency table
  showing that no further offline session is needed for five years after the
  initial setup.

- **The air-gapped boundaries are visible before the first command.**
  `docs/SETUP.md` has a new "Workflow Overview" section near the top with an
  ASCII diagram of the three setup steps. Its TL;DR states explicitly that two
  offline sessions are required.

### Changed

- **`docs/COEXISTENCE.md` is findable from the documentation index.** It was
  added in v1.2.0 but missing from Quick Navigation and Reading Order in
  `docs/README.md`. The stale Document Status table there was removed.

- **Three documents no longer open in German.** The TL;DRs of
  `docs/ARCHITECTURE.md`, `docs/BACKUP.md` and `docs/CLIENT_TRUST.md` were
  translated to English, so the whole public repository reads in one language.

## [1.2.0] - 2026-05-13: Scripted Root CA sessions and DNS coexistence patterns

Lessons collected while deploying step-ca alongside an existing Let's Encrypt,
acme-dns, Tailscale and Active Directory stack. All additions are
environment-neutral and carry no organization-specific identifiers.

### Added

- **The Root CA and intermediate steps are scripted instead of manual command
  sequences.** A new `scripts/` directory carries three of them:
  - `scripts/create-root-ca.sh`: offline Root CA creation with air-gap
    verification, decrypt-verify, cross-platform secure-delete (shred, gshred or
    `rm -P`) and a cleanup trap on abort
  - `scripts/generate-intermediate-csr.sh`: server-side intermediate key and CSR
    generation with an ENV-configurable subject
  - `scripts/sign-intermediate-ca.sh`: USB-driven offline signing with input
    validation and chain verification

- **Running step-ca next to an existing DNS stack has documented patterns.**
  `docs/COEXISTENCE.md` is new and covers four of them: acme-dns and the port 53
  conflict, Tailscale and WireGuard MagicDNS, Windows Active Directory DNS, and
  multiple step-ca instances per site.

- **The DNS conflicts that break a fresh install have a symptom entry.**
  `docs/TROUBLESHOOTING.md` gained a DNS and network coexistence section
  covering port 53 conflicts with acme-dns, PiHole, AdGuard or dnsmasq with
  three resolution strategies; dnsmasq breaking Tailscale MagicDNS through
  implicit binding to VPN interfaces, with the `bind-interfaces` and explicit
  `listen-address=` fix; and `stop-dns-rebind` filtering legitimate private IPs
  out of AD-DNS answers, with the `rebind-domain-ok=` whitelist. Two entries were
  added alongside it: the container restart-loop with a `password` error, and a
  health check stuck in "starting", which explains why `step ca health` stays
  there without bootstrapping and gives two solutions.

- **A macOS cron or SSH job no longer fails with `step: command not found`.**
  The Prerequisites of `docs/SETUP.md` carry a Brew-PATH note: in non-login
  shells `step` and `gpg` are not in `$PATH` unless `/opt/homebrew/bin` is
  prepended.

- **The offline USB stick can be read on Linux and macOS both.**
  `docs/BACKUP.md` documents exFAT as the alternative for cases where LUKS does
  not fit, along with the two traps it brings: the 11-character exFAT label
  limit and the `._<filename>` AppleDouble sidecars macOS writes.

- **A hardened renewal unit no longer fails with `Read-only file system`.**
  `systemd/README.md` has a hardening section on the `ReadWritePaths=`
  requirement when `ProtectSystem=strict` meets a helper that writes state
  files, with a drop-in example.

### Fixed

- **A fresh container restart-looped even though the intermediate key was
  unencrypted.** step-ca reads `/home/step/secrets/password` at startup either
  way, and without the file the container failed with
  `error reading /home/step/secrets/password: no such file or directory`. Phase 3
  Step 3 of `docs/SETUP.md` now instructs creating that file, empty or filled
  with a passphrase. The same symptom was added to `docs/TROUBLESHOOTING.md`.

## [1.1.0] - 2026-01-21: CI linting and startup dependency checks

### Added
- **CI/CD Pipeline**: GitHub Actions workflows for automated code quality checks
  - ShellCheck linting for Bash scripts (monitoring, renewal, revocation, examples)
  - Bash syntax validation
  - Automated releases with release notes generation
- **.shellcheckrc**: ShellCheck configuration for consistent linting
- **CI Badge**: added to README.md for workflow status visibility
- **Dependency Checks**: the scripts verify their required dependencies at startup
  - `cert-exporter.sh`: openssl (required), docker (optional)
  - `renew-service-cert.sh`: openssl (required)
  - `revoke-cert.sh`: openssl and docker (required), curl (optional)
  - `cert-request-template.sh`: openssl (required)
  - Clear error messages with install instructions on missing dependencies

### Changed
- **Docker Image Version**: pinned `smallstep/step-ca` to `0.29.0` (was `latest`)
  - Ensures reproducible builds and prevents unexpected breaking changes
  - Version 0.29.0 was the current stable release on 2026-01-21
- **Container Security**: read-only filesystem enabled for the step-ca container
  - Volumes remain writable, so SQLite database functionality is preserved
  - Reduces attack surface if the container is compromised

## [1.0.1] - 2026-01-20: Abuse reports go through GitHub Issues

### Changed

- **Abuse reports go through GitHub Issues instead of email.**
  `CODE_OF_CONDUCT.md` named an email address as the reporting channel; it names
  GitHub Issues now, which is the channel this repository actually watches.

## [1.0.0] - 2026-01-20: Two-tier internal PKI with auto-renewal and expiry monitoring

First production release.

### Added
- **Two-Tier PKI Architecture**: offline Root CA plus online Intermediate CA (step-ca in Docker)
- **Auto-Renewal System**: systemd timers for automatic certificate renewal (30-day threshold)
- **Monitoring Integration**: Prometheus metrics exporter for certificate expiry tracking
- **Service Integration Examples**: Vaultwarden, Nextcloud, Portainer, generic nginx
- **Client Trust Automation**: cross-platform Root CA installation instructions (Linux, macOS, Windows, iOS, Android, Firefox)
- **CRL Support**: certificate revocation lists with HTTP distribution (EXPERIMENTAL)
- **Complete Documentation**:
  - [SETUP.md](docs/SETUP.md) - 6-phase setup guide with verification steps
  - [ARCHITECTURE.md](docs/ARCHITECTURE.md) - PKI design decisions and compliance mapping
  - [CLIENT_TRUST.md](docs/CLIENT_TRUST.md) - trust installation for five operating systems, plus Firefox, which keeps its own trust store; Chrome, Edge and Safari read the OS store
  - [BACKUP.md](docs/BACKUP.md) - 3-2-1 backup strategy with disaster recovery scenarios
  - [NGINX_TLS.md](docs/NGINX_TLS.md) - TLS termination best practices (3 security profiles)
  - [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) - symptom index with 7 common issues

### Features
- **Scripts** (5 total):
  - `renewal/renew-service-cert.sh` - automated certificate renewal with error handling
  - `monitoring/cert-exporter.sh` - Prometheus textfile collector for expiry metrics
  - `monitoring/check-time-sync.sh` - clock offset check before certificate operations
  - `revocation/revoke-cert.sh` - certificate revocation via the step-ca API (EXPERIMENTAL)
  - `examples/cert-request-template.sh` - template for new certificate requests
- **systemd Templates**: service and timer templates for auto-renewal
- **Configuration Templates**: step-ca Docker Compose stack, nginx TLS configs
- **Examples**: 4 service integrations (Vaultwarden, Nextcloud, Portainer, generic nginx)

### Security
- **Offline Root CA**: air-gapped, GPG-encrypted, multiple backups (3-2-1 rule)
- **Short-Lived Certificates**: 90 days validity (step-ca default)
- **Auto-Renewal**: 30-day threshold prevents expiry
- **TLS Best Practices**: Modern, Intermediate and Old profiles (nginx)
- **Monitoring Alerts**: Prometheus alerts 30, 7 and 1 days before expiry

### Production Validation
- **Platforms Tested**: ARM64 (Raspberry Pi 5) and x86_64 (AMD Ryzen 9)
- **Services Integrated**: 6 services on the maintainer's own deployment (Vaultwarden, Nextcloud, Portainer, Dashboard, Grafana, Prometheus)
- **Operating Record**: on that deployment, no certificate expired and no renewal had to be run by hand between December 2025 and this release
- **Distributions Tested**: Ubuntu 22.04 and 24.04, Debian 11 and 12, Raspberry Pi OS

### Documentation Quality
- **TL;DR Sections**: the six guides under `docs/` open with a 20-word summary
- **Table of Contents**: the six guides under `docs/` carry a navigable ToC
- **Quick Reference Tables**: OS-specific commands, symptom index, recovery commands
- **Cross-References**: 91 relative Markdown links between the files of this repository
- **Security Warnings**: warnings carry mitigation steps and use four severity markers
- **Progressive Disclosure**: optional content in `<details>` tags

### Known Limitations
- **CRL Support**: EXPERIMENTAL, the revocation scripts are not production-tested
- **Platform Support**: Linux only (macOS and Windows for client trust only)
- **GUI**: no web interface, certificate management is CLI-only
- **ACME Protocol**: not supported, a CSR has to be created by hand
- **HSM Support**: requires step-ca Enterprise Edition

## [0.9.0] - 2026-01-15: First development release of the two-tier CA

### Added
- Initial development release
- Basic Root CA and Intermediate CA setup
- Manual certificate renewal workflow
- Vaultwarden integration example

### Changed
- Restructured documentation for DIATAXIS framework compliance

### Known Issues
- No auto-renewal automation, renewal has to be run by hand
- Missing Prometheus monitoring integration
- Limited service integration examples (Vaultwarden only)

<!--
Link definitions. Versions 1.1.0 and 0.9.0 deliberately have none: they were
documented here but never tagged and never released, so every compare/tag URL
for them is a 404. Their headings therefore render as plain text, which is an
accurate reflection of their status. Do not add links back, and do not create
the missing tags retroactively - a tag push triggers .github/workflows/release.yml
and would publish a release for a version that never shipped.
-->

[Unreleased]: https://github.com/fidpa/step-ca-internal-pki/compare/v1.3.8...HEAD
[1.3.8]: https://github.com/fidpa/step-ca-internal-pki/compare/v1.3.7...v1.3.8
[1.3.7]: https://github.com/fidpa/step-ca-internal-pki/compare/v1.3.6...v1.3.7
[1.3.6]: https://github.com/fidpa/step-ca-internal-pki/compare/v1.3.5...v1.3.6
[1.3.5]: https://github.com/fidpa/step-ca-internal-pki/compare/v1.3.4...v1.3.5
[1.3.4]: https://github.com/fidpa/step-ca-internal-pki/compare/v1.3.3...v1.3.4
[1.3.3]: https://github.com/fidpa/step-ca-internal-pki/compare/v1.3.2...v1.3.3
[1.3.2]: https://github.com/fidpa/step-ca-internal-pki/compare/v1.3.1...v1.3.2
[1.3.1]: https://github.com/fidpa/step-ca-internal-pki/compare/v1.3.0...v1.3.1
[1.3.0]: https://github.com/fidpa/step-ca-internal-pki/compare/v1.2.1...v1.3.0
[1.2.1]: https://github.com/fidpa/step-ca-internal-pki/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/fidpa/step-ca-internal-pki/compare/v1.0.1...v1.2.0
[1.0.1]: https://github.com/fidpa/step-ca-internal-pki/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/fidpa/step-ca-internal-pki/releases/tag/v1.0.0
