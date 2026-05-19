# Complete PBX Installation System - Development Guide

## Project Status: Active Development

A production-ready, fully automated installation script for enterprise PBX systems with Asterisk 20, FreePBX 17, and comprehensive management tools.

## 🎯 Current Version: 3.0

### Latest Updates
- ✅ Asterisk 20.19.0 (18 for CentOS 6)
- ✅ FreePBX 17.0 (not 16 — upstream version bump)
- ✅ Full idempotency — script can be re-run safely (state in /etc/pbx/state.json)
- ✅ 72+ FreePBX modules automatic installation (explicit list via loop)
- ✅ Comprehensive demo applications (DEMO, 123, 947, 951, LENNY, etc.)
- ✅ TUI configuration tool (`pbx-config`) for extensions/trunks/routes
- ✅ VoIP provider templates (voip.ms, Flowroute, Telnyx, Twilio, Custom)
- ✅ Let's Encrypt certificate integration with auto-renewal
- ✅ Reverse proxy support (Nginx, Apache, Traefik, Caddy)
- ✅ Smart repository detection (prevents duplicates)
- ✅ Configuration backup system with timestamped directories
- ✅ AlmaLinux 9 compatibility fixes (pkgconf-pkg-config, dnf-plugins-core)
- ✅ AvantFax installation from SourceForge (official source) - v3.4.1
- ✅ Email-to-fax with secure random alias via /etc/pbx/.env
- ✅ Fax-to-email automatic forwarding configuration
- ✅ 45 management scripts in /usr/local/bin/pbx-* (scripts synced from GitHub on each run)
- ✅ PHP-FPM runs as `apache` user which is added to `asterisk` group (FreePBX files are 664 asterisk:asterisk — group membership gives write access)
- ✅ FreePBX admin user created via direct SQL for unattended installs
- ✅ HylaFax service detects binary path (package vs source-compiled)
- ✅ /var/spool/hylafax owned by uucp for FIFO creation
- ✅ freepbx.service (oneshot, RemainAfterExit=yes) started via systemd in finalize
- ✅ WebRTC WSS transport on port 8089 with STUN (stun.l.google.com)
- ✅ Health monitoring cron (every 5 min, auto-restart + email alerts)
- ✅ FOP2 Flash Operator Panel (optional, INSTALL_FOP2=yes)
- ✅ Phone auto-provisioning (TFTP + HTTP, pbx-tftp script, 4 vendor support)
- ✅ rclone remote backup to S3/Backblaze/SFTP (pbx-backup-remote)
- ✅ GPG backup encryption (pbx-backup-encrypt)
- ✅ FreePBX weekly auto-update with pre-update DB backup (pbx-autoupdate)
- ✅ Anonymous SIP inbound (for DID providers without registration)
- ✅ Download integrity via SHA256 checksum verification
- ✅ CentOS 6 and CentOS 7 compatibility layers
- ✅ /health JSON endpoint for external monitoring (public-safe, CORS)
- ✅ Installation summary email to admin
- ✅ 5 MOH classes (default, jazz, classical, holiday, ringback)
- ✅ 9 extended AGI scripts (IVR, TTS, DND, recording, wakeup, echo, etc.)
- ✅ All scripts: compliant headers, function prefixes, grep --, vim modelines (44 bash + 1 python)
- ✅ sngrep: gracefully warns and skips when unavailable instead of false success; autotools bootstrap (autoreconf -i) added to source compile fallback for RHEL/AlmaLinux 9
- ✅ Summary banner only lists sngrep when it is actually installed (command_exists check)

## 🏗️ Architecture

### Core Components
1. **Asterisk 20** - VoIP engine with PJSIP (chan_sip disabled)
2. **FreePBX 16** - Web-based PBX management with 70+ modules
3. **MariaDB** - Database backend
4. **Apache/HTTPD** - Web server with reverse proxy support
5. **PHP 7.4** - Primary PHP version for FreePBX and AvantFax
6. **PHP-FPM** - Runs the shared PHP 7.4 web runtime

### Additional Features
- **AvantFax + IAXmodem** - 4 virtual fax modems with HylaFax+
- **TTS Engine** - Flite (system) + gTTS (Google) for text-to-speech
- **AGI Scripts** - Call logging, validation, business hours
- **Demo Dialplan** - Comprehensive test applications
- **Feature Codes** - Call forwarding, DND, recording, etc.
- **Conference Bridge** - Multi-party calling support
- **Music on Hold** - File-based and streaming support
- **WebRTC** - Browser-based calling via FreePBX UCP (WSS on 8089)
- **Phone Provisioning** - TFTP + HTTP auto-provisioning for Yealink/Cisco/Polycom
- **Remote Backup** - rclone sync to S3/Backblaze/SFTP/GCS
- **FOP2** - Flash Operator Panel 2 (optional)
- **Asternic** - Call center queue statistics dashboard
- **sngrep** - SIP traffic analyzer (optional)

## 📁 Repository Structure

```
/root/Projects/github/scriptmgr/pbx/
├── install.sh              # Main installation script (5500+ lines)
├── scripts/                # Management scripts (29 files)
│   ├── pbx-status          # System overview
│   ├── pbx-backup          # Backup management (with GPG encrypt + verify)
│   ├── pbx-config          # TUI extension/trunk/route configuration
│   ├── pbx-asterisk        # Asterisk management
│   ├── pbx-calls           # Active call monitoring
│   ├── pbx-cdr             # CDR call reporting
│   ├── pbx-diag            # Support diagnostics
│   ├── pbx-trunks          # SIP trunk health monitoring
│   ├── pbxstatus           # Quick status utility
│   └── ... (20 more)
├── README.md               # User-facing documentation
├── CLAUDE.md               # This file - development guide
├── TODO.md                 # Active task tracking
└── LICENSE                 # MIT License
```

## 🐳 Development Environment

### Incus Testing (preferred)

Use incus containers for testing — faster than Docker, better systemd support:

- Safety rule: never run `reboot`, `poweroff`, `shutdown`, or equivalent on the host system. Those commands are allowed only inside test containers or VMs.

```bash
# Create test containers
incus launch images:almalinux/9 pbx-alma9
incus launch images:debian/12 pbx-deb12

# Push installer to container
incus file push install.sh pbx-alma9/var/tmp/install.sh

# Run installation
incus exec pbx-alma9 -- bash -c 'nohup bash /var/tmp/install.sh > /var/log/pbx-test-install.log 2>&1 &'

# Monitor progress
incus exec pbx-alma9 -- tail -f /var/log/pbx-test-install.log

# Clean up
incus stop pbx-alma9 && incus delete pbx-alma9
```

### Docker Testing (alternative)

```bash
# Create test container
docker run -it --privileged --name pbx-test almalinux:9 /bin/bash

# Inside container
dnf install -y git
git clone /path/to/pbx /opt/pbx && cd /opt/pbx && ./install.sh

# Clean up
exit && docker rm pbx-test
```

# Rocky Linux 9
docker run -it --privileged rockylinux:9 /bin/bash
```

## 🎯 Supported Operating Systems

### Primary Support (Tested)
- **AlmaLinux 9.x** ✅ (Primary testing platform)
- **Debian 12** ✅ (Primary testing platform)
- **Rocky Linux 9.x** ✅
- **Ubuntu 22.04 LTS** ✅

### Secondary Support
- RHEL 8/9 (with subscription)
- AlmaLinux 8.x / Rocky Linux 8.x
- Ubuntu 18.04/20.04 LTS
- Debian 10/11
- Oracle Linux 8/9
- Fedora 35+

### Legacy Support
- **CentOS 7** — Asterisk 20, FreePBX 16, PHP 7.4 via Remi
- **CentOS 6** — Asterisk 18 LTS, FreePBX 15, PHP 7.4 via Remi SCL, SysV init

## 🔧 Key Features in Detail

### 1. Idempotent Installation
- Script can be re-run without breaking existing setup
- Checks for installed components before proceeding
- Skips already-configured services
- Backs up configs to `/mnt/backups/pbx-config-backups/{epoch}/`
- Preserves user customizations

### 2. Smart Repository Management
- Detects existing repositories before adding
- Uses `grep -R` to search all repo files
- Prevents duplicate repository entries
- Supports apt and yum/dnf systems

### 3. FreePBX Module Suite (70+)
**Core:** framework, core, voicemail, pjsip
**Routing:** inbound_routes, outbound_routes, ringgroups, queues
**IVR:** ivr, timeconditions, daynight, miscapps
**Features:** callforward, findmefollow, donotdisturb, parking, paging
**Recording:** callrecording, recordings, announcement
**Conferencing:** conferences, conferenceapps
**Admin:** dashboard, backup, logfiles, asteriskinfo, cdr, certman
**Directory:** cidlookup, directory, phonebook
**And many more...**

### 4. pbx-config TUI Tool
Interactive dialog-based configuration:
- Add PJSIP extensions with auto-generated passwords
- Configure VoIP trunks (voip.ms, Flowroute, Telnyx, Twilio, Custom)
- Set up inbound routes (DID → extension)
- Configure outbound routes (dial patterns → trunk)
- View current configuration
- Apply and reload FreePBX

### 5. Demo Applications
Dial-able from any extension:
- `DEMO` - System information and demo menu
- `123` - Speaking clock (time/date)
- `947` - Weather report (TTS demo)
- `951` / `TODAY` - Today's date
- `4747` / `LENNY` - Telemarketer bot
- `*43` - Echo test
- `*469`, `*470` - Conference rooms
- `*97` - Voicemail main menu
- `*610` - Music on hold test

### 6. Feature Codes
- `*72` / `*73` - Call forwarding (enable/disable)
- `*76` / `*77` - Do not disturb
- `*78` - Call recording toggle
- `*68` - Wakeup call service
- `*500` - Call pickup
- `*501` - Directed call pickup
- `*41` - Caller ID test
- `*65` - Extension status

### 7. SSL/TLS Integration
- Automatic Let's Encrypt certificate detection
- Scans `/etc/letsencrypt/live/` for certificates
- Deploys to `/etc/asterisk/keys/`
- Auto-renewal hook at `/etc/letsencrypt/renewal-hooks/deploy/asterisk`
- TLS enabled for:
  - PJSIP (port 5061)
  - Asterisk HTTPS Manager (port 8089)
  - Apache/HTTPD web interface

### 8. Reverse Proxy Support
Set `BEHIND_PROXY=yes` before installation to:
- Configure Apache RemoteIP module
- Trust X-Forwarded-For headers
- Detect HTTPS from X-Forwarded-Proto
- Support Nginx, Apache, Traefik, Caddy, etc.

### 9. Management Scripts (31 tools)
- `pbx-config` - TUI configuration tool
- `pbx-status` - System overview
- `pbx-restart` - Safe service restart
- `pbx-repair` - Automatic repair
- `pbx-backup` - Manual backups (with GPG encrypt + sha256 verify)
- `pbx-cleanup` - Backup retention
- `pbx-firewall` - Firewall management
- `pbx-ssh` - SSH configuration
- `pbx-security` - Security audit
- `pbx-services` - Service monitoring
- `pbx-logs` - Log management
- `pbx-network` - Network diagnostics
- `pbx-ssl` - SSL certificate status
- `pbx-passwords` - Password management
- `pbx-docs` - Documentation generation
- `pbx-moh` - Music on Hold management
- `pbx-autoupdate` - FreePBX weekly module updates with pre-update DB backup
- `pbx-backup-encrypt` - GPG key management and backup archive encryption
- `pbx-backup-remote` - Sync backups to remote storage via rclone
- `pbx-provision` - Phone auto-provisioning info (TFTP + HTTP)
- `pbx-calls` - Active call monitoring (live refresh mode)
- `pbx-cdr` - Call Detail Record reporting (today/week/month)
- `pbx-diag` - Support diagnostics (collects logs + system info)
- `pbx-recordings` - Call recording management
- `pbx-trunks` - SIP trunk health monitoring
- `pbx-update` - Self-updating management scripts from GitHub
- `pbx-webmin` - Webmin management
- `pbx-add-ip` - Dynamic IP whitelist management
- `pbx-ip-checker` - IP change detection
- `pbxstatus` - Quick system status snapshot

## 🐛 Known Issues & Fixes

### Critical Fixes Applied
1. **PHP-FPM permission model**
   - FreePBX files owned by `asterisk:asterisk` (mode 664)
   - PHP-FPM pool runs as `apache` user — OK because `apache` is added to the `asterisk` group and files are group-writable (664)
   - Mechanism: `usermod -aG asterisk apache` + `usermod -aG apache asterisk` in `create_users()`
   - Status: ✅ Working (group membership, not pool user change)

2. **FreePBX admin user creation**
   - Use direct SQL INSERT into `ampusers` for unattended provisioning
   - Fix: Direct SQL INSERT into `ampusers` with SHA1 password hash
   - Status: ✅ Fixed

3. **Asterisk service management**
   - `freepbx.service` is oneshot (RemainAfterExit=yes) — must be started via systemd
   - Direct start during install leaves orphaned socket; systemd shows inactive
   - Fix: `finalize_installation()` stops direct Asterisk and starts via `systemctl start freepbx`
   - Status: ✅ Fixed

4. **HylaFax service unit binary path**
   - Source-compiled: `/usr/local/sbin/faxq`; packages: `/usr/sbin/faxq`
   - Fix: `create_hylafax_service()` detects path with `command -v faxq`
   - Status: ✅ Fixed

5. **HylaFax FIFO creation permission denied**
   - `/var/spool/hylafax/` must be owned by `uucp:uucp` (uid 3 on RHEL = adm)
   - Fix: `chown uucp:uucp /var/spool/hylafax/` after directory creation
   - Status: ✅ Fixed

### AlmaLinux 9 Specific
1. **pkg-config package name** — Use `pkgconf-pkg-config pkgconf` ✅
2. **dnf config-manager** — Install `dnf-plugins-core` first ✅
3. **CRB repository** — RHEL 9 uses `crb` not `powertools` ✅
4. **unixODBC-devel** — Capital ODBC on RHEL ✅
5. **AvantFax source** — SourceForge v3.4.1 (GitHub 404) ✅

### Known Non-Issues (Do Not Fix)
1. **npm CVE warnings in FreePBX UCP / pm2** — FreePBX bundles its own npm packages (`/var/www/html/admin/assets/js/`, UCP node_modules, pm2). These report upstream CVEs that are **not fixable by the installer**. They are transitive deps of FreePBX's own codebase; fixing them would require upstream FreePBX patches. `npm audit` reports are expected — do not treat as install failures.
2. **`fwconsole setting TIMEZONE` output** — FreePBX 17 removed the TIMEZONE setting key. The call emits "The setting TIMEZONE was not found!" to stdout but is harmless; timezone is correctly applied via `timedatectl`, `php.ini` date.timezone, and Asterisk dialplan. Suppressed with `> /dev/null 2>&1`.
3. **Credential banner** — Passwords are randomly generated per install and saved to `/etc/pbx/pbx_passwords` and `/etc/pbx/.env`. They are preserved across re-runs. The banner reminds admins to review them before internet exposure — not to "change defaults".

## 📝 Development Guidelines

### Adding New Features
1. Update CLAUDE.md first with planned changes
2. Use incus containers for testing (alma9, deb12)
3. Test on both AlmaLinux 9 and Debian 12
4. Update README.md when user-facing
5. Run `bash -n install.sh` to verify syntax after edits

### Code Style
- POSIX-compliant shell script
- Use `set -euo pipefail` for error handling
- Add idempotency checks before operations: `skip_if_done COMPONENT && return 0`
- Backup configs before modification: `backup_config /path/to/file`
- Use `info`, `success`, `warn`, `error`, `step` for output
- Track installations with `mark_done COMPONENT`

### Testing Protocol
1. Create clean incus containers: `incus launch images:almalinux/9 pbx-alma9`
2. Push install.sh: `incus file push install.sh pbx-alma9/var/tmp/install.sh`
3. Run: `incus exec pbx-alma9 -- bash /var/tmp/install.sh`
4. Test re-run (idempotency)
5. Test on Debian 12 as well
6. Clean up: `incus stop pbx-alma9 && incus delete pbx-alma9`

### Path Conventions
- Management scripts: `/usr/local/bin/pbx-*`
- System state: `/var/lib/pbx/install_inventory`
- Logs: `/var/log/pbx/`
- Credentials: `/etc/pbx/pbx_passwords` (chmod 600)
- Env file: `/etc/pbx/.env` (chmod 600)
- State JSON: `/etc/pbx/state.json`

### Backup Strategy
- All config backups go to: `/mnt/backups/pbx-config-backups/{epoch}/`
- Never overwrites user configurations
- Uses `backup_config()` function

### Repository Detection
```bash
# Check before adding repository
if ! repo_exists "rpms.remirepo.net"; then
    # Install repository
fi
```

## 🚀 Installation Process

### Main Flow
1. System detection (OS, version, package manager)
2. System preparation (essential packages)
3. Repository setup (EPEL, Remi, NodeSource)
4. Core dependencies (build tools, libraries)
5. Database (MariaDB)
6. PHP 7.4
7. Apache/HTTPD
8. SSL/TLS configuration (Let's Encrypt detection)
9. Reverse proxy configuration
10. Asterisk compilation and installation
11. FreePBX installation (70+ modules)
12. FreePBX configuration (PJSIP, network, NAT)
13. Asterisk sounds and prompts
14. TTS engine (Flite)
15. AGI scripts
16. Demo applications
17. Fax system (REQUIRED - HylaFax+ + IAXmodem + AvantFax)
18. Security (Firewall + Fail2ban)
19. Backup system
20. Management scripts creation
21. Finalization and completion message

### Environment Variables
```bash
FREEPBX_ADMIN_PASSWORD='password'    # FreePBX admin password
MYSQL_ROOT_PASSWORD='password'       # MySQL root password
ADMIN_EMAIL='admin@domain.com'       # Administrator email
TIMEZONE='America/New_York'          # System timezone
BEHIND_PROXY='yes'                   # Reverse proxy mode
```

## 📊 Project Statistics

- **Total Lines:** ~3800+ in install.sh
- **Functions:** 50+
- **Modules Installed:** 70+
- **Management Scripts:** 16
- **Demo Applications:** 15+
- **Feature Codes:** 12+
- **Supported Distros:** 4 primary, 10+ derivatives

## 🔄 Current Development Focus

### Priority: AlmaLinux 9 Compatibility
- Testing full installation flow
- Fixing package name differences
- Ensuring all dependencies install
- Testing idempotency on re-run
- Validating demo applications
- Testing TUI tool functionality

### Next Steps (see TODO.md)
- Fix unixodbc-devel package issue
- Test complete installation end-to-end
- Validate certificate integration
- Test reverse proxy configuration
- Document any additional fixes needed

## 💡 Contributing

When making changes:
1. Test in Docker first
2. Update CLAUDE.md with changes
3. Update TODO.md status
4. Update README.md if user-facing
5. Keep commits atomic and well-described
6. Test on multiple distributions when possible

## 📚 References

- [Asterisk Documentation](https://docs.asterisk.org/)
- [FreePBX Wiki](https://wiki.freepbx.org/)
- [AlmaLinux Documentation](https://wiki.almalinux.org/)
- [Rocky Linux Documentation](https://docs.rockylinux.org/)

---

**Last Updated:** 2026-04-12
**Maintainer:** AI Development Team
**License:** MIT
