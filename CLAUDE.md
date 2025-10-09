# Complete PBX Installation System - Development Guide

## Project Status: Active Development

A production-ready, fully automated installation script for enterprise PBX systems with Asterisk 21, FreePBX 17, and comprehensive management tools.

## 🎯 Current Version: 2.0

### Latest Updates
- ✅ Full idempotency - script can be re-run safely
- ✅ 70+ FreePBX modules automatic installation
- ✅ Comprehensive demo applications (DEMO, 123, 947, 951, LENNY, etc.)
- ✅ TUI configuration tool (`pbx-config`) for extensions/trunks/routes
- ✅ VoIP provider templates (voip.ms, Flowroute, Telnyx, Twilio, Custom)
- ✅ Let's Encrypt certificate integration with auto-renewal
- ✅ Reverse proxy support (Nginx, Apache, Traefik, Caddy)
- ✅ Smart repository detection (prevents duplicates)
- ✅ Configuration backup system with timestamped directories
- ✅ AlmaLinux 9 compatibility fixes (pkgconf-pkg-config, dnf-plugins-core)

## 🏗️ Architecture

### Core Components
1. **Asterisk 21 LTS** - VoIP engine with PJSIP (chan_sip disabled)
2. **FreePBX 17** - Web-based PBX management with 70+ modules
3. **MariaDB** - Database backend
4. **Apache/HTTPD** - Web server with reverse proxy support
5. **PHP 8.2** - Primary PHP version
6. **PHP 7.4** - For AvantFax compatibility

### Additional Features
- **AvantFax + IAXmodem** - 4 virtual fax modems with HylaFax+
- **TTS Engine** - Flite for text-to-speech
- **AGI Scripts** - Call logging, validation, business hours
- **Demo Dialplan** - Comprehensive test applications
- **Feature Codes** - Call forwarding, DND, recording, etc.
- **Conference Bridge** - Multi-party calling support
- **Music on Hold** - File-based and streaming support

## 📁 Repository Structure

```
/root/Projects/github/scriptmgr/pbx/
├── install.sh              # Main installation script (3800+ lines)
├── README.md               # User-facing documentation
├── CLAUDE.md              # This file - development guide
├── TODO.md                # Active task tracking
├── LICENSE                # MIT License
└── .tmp/                  # Temporary testing directory (git-ignored)
```

## 🐳 Development Environment

### Docker Testing (AlmaLinux 9)

Always use Docker for testing to keep the repository clean:

```bash
# Create test container
docker run -it --privileged --name pbx-test almalinux:9 /bin/bash

# Inside container, install git and clone repo
dnf install -y git
git clone /path/to/pbx /opt/pbx

# Run installation
cd /opt/pbx
./install.sh

# Clean up after testing
exit
docker rm pbx-test
```

### Testing Multiple Distributions

```bash
# Ubuntu 22.04
docker run -it --privileged ubuntu:22.04 /bin/bash

# Debian 12
docker run -it --privileged debian:12 /bin/bash

# Rocky Linux 9
docker run -it --privileged rockylinux:9 /bin/bash
```

## 🎯 Supported Operating Systems

### Primary Support (Tested)
- **AlmaLinux 9.x** ✅ (Current testing focus)
- **Rocky Linux 9.x** ✅
- **Ubuntu 22.04 LTS** ✅
- **Debian 11/12** ✅

### Secondary Support
- RHEL 8/9 (with subscription)
- AlmaLinux 8.x
- Rocky Linux 8.x
- Ubuntu 20.04 LTS

### Not Supported
- Oracle Linux (use Rocky/Alma instead)
- CentOS (EOL - migrate to Rocky/Alma)
- Fedora (testing only, not production)

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

### 9. Management Scripts (16 tools)
- `pbx-config` - TUI configuration tool
- `pbx-status` - System overview
- `pbx-restart` - Safe service restart
- `pbx-repair` - Automatic repair
- `pbx-backup` - Manual backups
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

## 🐛 Known Issues & Fixes

### AlmaLinux 9 Specific
1. **pkg-config package name**
   - Issue: `pkgconfig` not found
   - Fix: Use `pkgconf-pkg-config pkgconf pkgconfig pkg-config`
   - Status: ✅ Fixed

2. **dnf config-manager**
   - Issue: Command not found
   - Fix: Install `dnf-plugins-core` first
   - Status: ✅ Fixed

3. **CRB repository**
   - RHEL 9 uses `crb` instead of `powertools`
   - Status: ✅ Fixed

4. **unixodbc-devel**
   - Issue: Package not found (case-sensitive)
   - Fix: Use `unixODBC-devel` (capital ODBC) as primary
   - Status: ✅ Fixed

## 📝 Development Guidelines

### Adding New Features
1. Update CLAUDE.md first with planned changes
2. Use `/root/Projects/github/scriptmgr/pbx/.tmp/` for testing
3. Test in Docker (AlmaLinux 9 primary)
4. Update README.md when user-facing
5. Mark in TODO.md when complete

### Code Style
- POSIX-compliant shell script
- Use `set -e` for error handling
- Add idempotency checks before operations
- Backup configs before modification
- Use `info`, `success`, `warn`, `error` for output
- Track installations with `track_install`

### Testing Protocol
1. Create clean Docker container
2. Run `./install.sh` fully
3. Test re-run (idempotency)
4. Test management scripts
5. Test demo applications
6. Test TUI tool (`pbx-config`)

### Backup Strategy
- All config backups go to: `/mnt/backups/pbx-config-backups/{epoch}/`
- Mirrors original directory structure
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
6. PHP (8.2 + 7.4)
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
17. Fax system (optional - HylaFax+ + IAXmodem + AvantFax)
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

**Last Updated:** 2025-01-08
**Maintainer:** AI Development Team
**License:** MIT
