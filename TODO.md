# PBX Install Script — TODO

Progress tracker for the complete v3.0 rewrite.

## Legend
- `[ ]` Pending
- `[~]` In Progress
- `[x]` Done

---

## Phase 1 — Foundation (Core Infrastructure)

- [x] `os-detect` — Enhance OS detection for all target distros
- [x] `version-select` — Version selection by distro generation
- [x] `pkg-map` — Package mapping system (`PKG_*` vars, no hardcoded names)
- [x] `repo-setup` — Repository setup for all distros (EPEL, Remi, Ondrej, Sury, NodeSource)
- [x] `php-versions` — PHP version matrix per distro (8.2 main + 7.4 AvantFax)
- [x] `init-compat` — SysV init compatibility layer for CentOS 6
- [x] `output-formatting` — NO_COLOR-compliant output system (colors + emojis off when NO_COLOR set)
- [x] `install-profiles` — Installation profiles: minimal / standard / advanced
- [x] `preflight` — Pre-flight checks (root, OS, internet; warn on low RAM/disk)
- [x] `ssh-safety` — SSH never blocked (detect port, whitelist IP, dead-man switch)
- [x] `idempotency` — Re-run safety via state file + skip_if_done/mark_done helpers
- [x] `run-modes` — Run modes and `--help` with all env vars documented
- [x] `install-progress` — Step counter and progress display
- [x] `container-detect` — Detect LXC/Docker, skip iptables/sysctl
- [x] `derivative-distros` — Detect derivatives via `ID_LIKE` (Mint, Pop, Stream, etc.)
- [x] `centos6-compat` — CentOS 6 vault mirrors, SysV, EOL warnings
- [ ] `centos7-compat` — CentOS 7 specific quirks

---

## Phase 2 — Stack Installation

- [x] `core-deps` — Full core dependencies using `PKG_*` map
- [x] `dns-setup` — DNS resolver setup (8.8.8.8 / 1.1.1.1 / 4.4.4.4)
- [x] `ntp-setup` — NTP/time sync (chrony vs ntp per distro)
- [x] `disable-ipv6` — Disable IPv6 via sysctl (skip in containers)
- [x] `mysql-user` — MariaDB + dedicated `asterisk` DB user (not root)
- [x] `install-php` — PHP 8.2 + all required modules, per distro
- [x] `install-avantfax-php` — PHP 7.4 parallel install for AvantFax
- [x] `odbc-config` — ODBC for CDR (path differs per arch/distro)
- [x] `install-asterisk` — Asterisk compilation for version matrix (18/21/22)
- [x] `install-freepbx` — FreePBX install for version matrix (15/17)
- [ ] `freepbx-module-list` — Explicit module install list for FreePBX 17
- [x] `freepbx-modules` — Remove unsupported, install all supported modules
- [x] `web-root` — Web root at `/var/www/apache/pbx/` everywhere
- [x] `install-postfix` — Postfix mail server + voicemail-to-email
- [x] `voicemail-email` — Voicemail-to-email via Postfix
- [x] `logrotate` — Asterisk log rotation

---

## Phase 3 — Applications

- [x] `install-gtts` — gTTS + SpeechGen TTS
- [x] `install-webmin` — Webmin on port 9001 with module pruning
- [x] `install-knockd` — knockd port knocking (advanced profile only)
- [x] `install-openvpn` — OpenVPN (advanced profile only)
- [x] `install-sngrep` — sngrep SIP monitor (advanced profile only)
- [ ] `fop2` — FOP2 Flash Operator Panel (advanced profile only)
- [ ] `phone-provisioning` — TFTP + HTTP phone provisioning (advanced profile only)

---

## Phase 4 — Fax System

- [x] `install-avantfax` — AvantFax from SourceForge + PHP 7.4
- [x] `install-hylafax` — HylaFax+ + IAXmodem fax system
- [x] `email-to-fax` — Email-to-fax configuration
- [x] `fax-to-email` — Fax-to-email forwarding
- [x] `telephone-reminder` — Telephone Reminder app (`/reminder/`)
- [ ] `wakeup-reminder` — Wakeup calls (hotelwakeup module + `*68`)

---

## Phase 5 — Dialplan & Demo Apps

- [x] `no-user-extensions` — ONLY app extensions installed, zero user extensions
- [x] `anon-sip` — Anonymous SIP inbound context
- [x] `stun-config` — STUN server for WebRTC/NAT
- [x] `webrtc` — WebRTC WSS transport
- [x] `freepbx-ucp` — FreePBX UCP module + WebRTC
- [x] `freepbx-wakeup` — FreePBX hotelwakeup module
- [x] `asteridex` — AsteriDex phonebook
- [x] `call-center-ui` — Asternic Call Center Stats (`/callcenter/`)

---

## Phase 6 — Security

- [x] `fail2ban-jails` — Fail2ban jails for Asterisk, Apache, SSH
- [x] `install-iptables` — iptables rules (standard: allow-list; advanced: DROP policy)
- [x] `qos-setup` — QoS traffic shaping (SIP/RTP priority)
- [x] `voip-tuning` — VoIP + kernel performance tuning

---

## Phase 7 — SSL & Web

- [x] `ssl-selfsigned` — Self-signed SSL fallback
- [x] `ssl-install` — Let's Encrypt via certbot + auto-renewal
- [x] `main-portal` — Main portal page (`/`) linking all apps
- [x] `status-page` — `/status/` JSON health endpoint
- [x] `health-endpoint` — `/health` JSON status endpoint

---

## Phase 8 — Backup & Management Scripts

- [x] `backup-tiers` — Tiered backups: daily/weekly/monthly/config/db to `/mnt/backups/pbx/`
- [ ] `backup-encryption` — GPG encryption for archives (advanced)
- [ ] `backup-verify` — Backup integrity checking
- [ ] `backup-before-update` — DB backup before FreePBX auto-update
- [ ] `remote-backup` — Remote backup via rclone (advanced)
- [x] `health-alerts` — Service health monitoring + email alerts
- [ ] `freepbx-autoupdate` — FreePBX weekly auto-update cron
- [x] `passwords-file` — `/root/.pbx_passwords` auto-generated credentials file
- [x] `install-summary` — Installation summary email + console output
- [x] `pbxstatus` — `pbxstatus` shows on SSH login
- [x] `root-scripts` — IncrediblePBX-style root management scripts
- [ ] `cdr-reporting` — CDR reporting script (`pbx-cdr`)
- [ ] `trunk-monitor` — SIP trunk health monitor (`pbx-trunks`)
- [ ] `download-integrity` — Checksum/GPG verification for tarballs
- [x] `fqdn-setup` — FQDN/hostname detection and setup

---

## Phase 9 — Management Scripts (`scripts/` dir → `/usr/local/bin/`)

- [~] `scripts-dir` — Creating `scripts/` directory (background agent running)
- [x] `github-api` — GitHub Contents API for dynamic script discovery/sync
- [x] `install-script-downloader` — Replace heredocs with API download loop
- [~] `pbx-update-script` — `pbx-update` for self-updating all scripts
- [~] `pbx-asterisk` — `pbx-asterisk` Asterisk management
- [~] `pbx-calls` — `pbx-calls` active call monitoring
- [~] `pbx-diag` — `pbx-diag` diagnostic/support info dump
- [~] `pbx-recordings` — `pbx-recordings` recording management
- [~] `pbx-docs-gen` — `pbx-docs generate` documentation output
- [~] All other 20 pbx-* scripts — background agent creating

---

## Phase 10 — Verification & Documentation

- [ ] `verify-update` — Update `verify_installation()` for all new components
- [ ] `readme-update` — Update `README.md` with expanded distro support
- [ ] `claude-md-update` — Update `CLAUDE.md` with architectural changes

---
