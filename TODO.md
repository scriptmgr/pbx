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
- [~] `centos7-compat` — CentOS 7 specific quirks (basic support via Remi; edge cases TBD)

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
- [x] `freepbx-module-list` — Explicit module install list for FreePBX 17 (70+ modules via loop)
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
- [x] `fop2` — FOP2 Flash Operator Panel (advanced profile, INSTALL_FOP2=yes)
- [x] `phone-provisioning` — TFTP + HTTP phone provisioning (pbx-tftp + pbx-provision scripts)

---

## Phase 4 — Fax System

- [x] `install-avantfax` — AvantFax from SourceForge + PHP 7.4
- [x] `install-hylafax` — HylaFax+ + IAXmodem fax system
- [x] `email-to-fax` — Email-to-fax configuration
- [x] `fax-to-email` — Fax-to-email forwarding
- [x] `telephone-reminder` — Telephone Reminder app (`/reminder/`)
- [x] `wakeup-reminder` — Wakeup calls via hotelwakeup module + *68 feature code + AGI script

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
- [x] `backup-encryption` — GPG encryption via pbx-backup-encrypt script
- [x] `backup-verify` — SHA256 integrity checking on all backups
- [x] `backup-before-update` — DB backup before FreePBX auto-update (pbx-autoupdate)
- [x] `remote-backup` — Remote backup via rclone (pbx-backup-remote script)
- [x] `health-alerts` — Service health monitoring + email alerts
- [x] `freepbx-autoupdate` — FreePBX weekly auto-update cron (pbx-autoupdate script)
- [x] `passwords-file` — `/etc/pbx/pbx_passwords` auto-generated credentials file
- [x] `install-summary` — Installation summary email + console output
- [x] `pbxstatus` — `pbxstatus` shows on SSH login
- [x] `root-scripts` — IncrediblePBX-style root management scripts
- [x] `cdr-reporting` — CDR reporting script (pbx-cdr)
- [x] `trunk-monitor` — SIP trunk health monitor (pbx-trunks)
- [x] `download-integrity` — SHA256 checksum verification for tarballs
- [x] `fqdn-setup` — FQDN/hostname detection and setup

---

## Phase 9 — Management Scripts (`scripts/` dir → `/usr/local/bin/`)

- [x] `scripts-dir` — All 32 scripts created in `scripts/` directory
- [x] `github-api` — GitHub Contents API for dynamic script discovery/sync
- [x] `install-script-downloader` — Replace heredocs with API download loop
- [x] `pbx-update-script` — `pbx-update` self-updating all scripts
- [x] `pbx-asterisk` — `pbx-asterisk` Asterisk management
- [x] `pbx-calls` — `pbx-calls` active call monitoring
- [x] `pbx-diag` — `pbx-diag` diagnostic/support info dump
- [x] `pbx-recordings` — `pbx-recordings` recording management
- [x] `pbx-docs-gen` — `pbx-docs` documentation output
- [x] All other 20 pbx-* scripts — complete, tested 41P/1W/0F

---

## Phase 10 — Verification & Documentation

- [x] `verify-update` — `verify_installation()` covers Asterisk, FreePBX, MariaDB, Apache, PHP
- [x] `readme-update` — `README.md` updated with full distro support, section reorder
- [ ] `claude-md-update` — Update `CLAUDE.md` with current architecture (last updated 2025-01-09)

---
