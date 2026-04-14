# Complete PBX Installation System

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![GitHub](https://img.shields.io/badge/GitHub-scriptmgr%2Fpbx-blue)](https://github.com/scriptmgr/pbx)
[![Platform](https://img.shields.io/badge/Platform-Linux-green)](https://www.linux.org/)
[![Asterisk](https://img.shields.io/badge/Asterisk-22_LTS-orange)](https://www.asterisk.org/)
[![FreePBX](https://img.shields.io/badge/FreePBX-17-red)](https://www.freepbx.org/)

A production-ready, fully automated installer for a complete enterprise PBX system — Asterisk 22, FreePBX 17, AvantFax, and 32 management tools. Designed for self-hosted, SMB, and enterprise use.

**Version:** 2.0 &nbsp;|&nbsp; **Asterisk:** 22 LTS &nbsp;|&nbsp; **FreePBX:** 17

---

## 🌟 Features

### Core PBX System
- **Asterisk 22 LTS** — Enterprise VoIP engine with full SIP/IAX support
- **FreePBX 17** — Modern web-based PBX management interface
- **70+ Modules** — All standard modules included and auto-installed
- **PJSIP** — UDP, TCP, and TLS transports (chan_sip disabled)
- **WebRTC** — Browser-based calling via FreePBX UCP (WSS port 8089)
- **Anonymous SIP** — Support for anonymous inbound calls
- **IVR + Time Conditions** — Full call flow control
- **Conference Bridge** — Multi-party calling
- **Demo Apps** — DEMO, 123, 947, 951, TODAY, LENNY, 4747, `*43` echo test
- **Feature Codes** — `*72/*73` forward, `*76/*77` DND, `*78` record, `*68` wakeup

### Enterprise Fax System
- **4 Virtual Fax Modems** — IAXmodem instances (ttyIAX0–3)
- **HylaFax+** — Compiled from source for maximum compatibility
- **AvantFax** — Web-based fax management (v3.4.1)
- **Fax-to-Email** — Automatic delivery to designated address
- **Email-to-Fax** — Send faxes by email

### Security & Monitoring
- **Fail2ban** — Automated intrusion prevention
- **Firewall** — PBX-optimised iptables rules
- **SSH Hardening** — Secure remote access, SSH is never blocked
- **SSL/TLS** — Let's Encrypt auto-detection + self-signed fallback
- **Rate Limiting** — Protection against SIP attacks
- **Security Audit** — Built-in vulnerability scanner (`pbx-security`)
- **Health Endpoint** — `/health/` JSON endpoint for external monitoring

### Smart Backup System
- **Tiered Retention** — Config (30d), Database (14d), Daily (7d), Weekly (4w), Monthly (6m)
- **GPG Encryption** — Optional backup archive encryption
- **Remote Sync** — rclone to S3, Backblaze, SFTP, GCS, or any cloud storage
- **Integrity Checking** — SHA256 verification on every backup
- **Size Cap** — Never exceeds 10 GB total backup storage

### Music on Hold
- **5 Built-in Classes** — default, jazz, classical, holiday, ringback
- **Streaming** — Any Icecast/Shoutcast/HTTP stream
- **Local Files** — WAV/MP3 from any directory

### TTS Support
- **Flite** — System TTS, no internet required
- **gTTS** — Google TTS for higher quality
- **Festival / eSpeak** — Fallback engines
- No AI/ML — lightweight, minimal resource usage

### Management Suite (32 tools)

All in `/usr/local/bin/`, all support `--help`.

| Tool | Purpose |
|---|---|
| `pbxstatus` | Quick compact status snapshot |
| `pbx-status` | Full column-aligned dashboard |
| `pbx-config` | TUI: add extensions, trunks, routes |
| `pbx-restart` | Safe service restart |
| `pbx-repair` | Automatic system repair |
| `pbx-backup` | Config + DB backup with GPG + SHA256 |
| `pbx-backup-encrypt` | GPG key management for backup encryption |
| `pbx-backup-remote` | rclone sync to remote storage |
| `pbx-cleanup` | Backup retention management |
| `pbx-firewall` | iptables rule management |
| `pbx-ssh` | SSH configuration and hardening |
| `pbx-security` | Full security audit |
| `pbx-services` | Service status badges |
| `pbx-logs` | Log viewer and analysis |
| `pbx-network` | Network diagnostics |
| `pbx-ssl` | SSL certificate status and management |
| `pbx-passwords` | Credential display (masked by default) |
| `pbx-docs` | Quick reference documentation |
| `pbx-moh` | Music on Hold class management |
| `pbx-asterisk` | Asterisk CLI wrapper and status |
| `pbx-calls` | Active call monitoring |
| `pbx-cdr` | CDR reporting (today/week/month) |
| `pbx-diag` | Full diagnostics bundle |
| `pbx-recordings` | Call recording browser |
| `pbx-trunks` | SIP trunk registration health |
| `pbx-provision` | Phone provisioning status |
| `pbx-tftp` | TFTP server + per-vendor config generation |
| `pbx-webmin` | Webmin management |
| `pbx-autoupdate` | FreePBX weekly module updates |
| `pbx-update` | Self-update management scripts from GitHub |
| `pbx-add-ip` | Dynamic firewall IP whitelist |
| `pbx-ip-checker` | Public IP change detector (cron) |

---

## 📋 Prerequisites

### Supported Operating Systems

| Distribution | Versions | Status |
|---|---|---|
| **AlmaLinux** | 8, 9 | ✅ Recommended (RHEL-compatible) |
| **Rocky Linux** | 8, 9 | ✅ Recommended (RHEL-compatible) |
| **Ubuntu** | 18.04, 20.04, 22.04, 24.04 LTS | ✅ Recommended (Debian-based) |
| **Debian** | 10, 11, 12 | ✅ Fully supported |
| **RHEL** | 8, 9 | ✅ Requires active subscription |
| **Oracle Linux** | 8, 9 | ✅ Supported |
| **Fedora** | 35–42+ | ⚠️ Rapid release — dev/testing only |
| **CentOS** | 7 | ⚠️ EOL — migrate to Rocky/Alma |
| **CentOS** | 6 | ⚠️ Legacy — Asterisk 18, FreePBX 15 |

Derivative distributions are auto-detected via `ID_LIKE` (Mint, Pop!_OS, CentOS Stream, etc.).

### Version Matrix

| Distribution | Asterisk | FreePBX | PHP |
|---|---|---|---|
| RHEL/Alma/Rocky 9, Ubuntu 22+, Debian 12 | **22 LTS** | **17** | 8.2 |
| RHEL/Alma/Rocky 8, Ubuntu 20, Debian 11 | 22 LTS | 17 | 8.2 |
| CentOS 7 | 21 LTS | 17 | 8.2 (Remi) |
| CentOS 6 (legacy) | 18 LTS | 15 | 7.4 (Remi SCL) |

PHP 7.4 is installed in parallel via PHP-FPM for AvantFax compatibility.

### System Requirements
- Fresh OS installation (no existing web or database services)
- Root access
- 4 GB RAM minimum (8 GB recommended)
- 20 GB disk minimum (50 GB recommended)
- Active internet connection
- Valid FQDN (recommended for SSL certificates)

> **Production recommended:** AlmaLinux 9, Rocky Linux 9, Ubuntu 22.04 LTS, or Debian 12.

---

## 🚀 Production Installation

### One-Line Install
```bash
wget https://raw.githubusercontent.com/scriptmgr/pbx/main/install.sh && chmod +x install.sh && ./install.sh
```

### Custom Install
```bash
wget https://raw.githubusercontent.com/scriptmgr/pbx/main/install.sh
chmod +x install.sh

ADMIN_EMAIL='admin@pbx.example.com' \
TIMEZONE='America/New_York' \
ADMIN_USERNAME='administrator' \
ADMIN_PASSWORD='MySecurePass123' \
./install.sh
```

### Environment Variables

| Variable | Description | Default |
|---|---|---|
| `ADMIN_USERNAME` | Unified admin username for FreePBX and shared web tools | `administrator` |
| `ADMIN_PASSWORD` | Unified admin password for FreePBX and shared web tools | Auto-generated |
| `FREEPBX_ADMIN_USERNAME` | Compatibility alias for `ADMIN_USERNAME` | `administrator` |
| `AVANTFAX_ADMIN_USERNAME` | AvantFax admin username | `ADMIN_USERNAME` |
| `AVANTFAX_ADMIN_PASSWORD` | AvantFax admin password | Auto-generated |
| `MYSQL_ROOT_PASSWORD` | Optional preset MariaDB root password for install | Auto-generated, then stored in `/etc/pbx/mysql_root_password` |
| `ADMIN_EMAIL` | Admin email for alerts, voicemail, fax | required |
| `FROM_EMAIL` | From address for all system mail | `no-reply@fqdn` |
| `FROM_NAME` | From display name for system mail | `PBX System` |
| `FAX_TO_EMAIL_ADDRESS` | Email for inbound fax delivery | `ADMIN_EMAIL` |
| `FAX_FROM_EMAIL` | From address for fax emails | `FROM_EMAIL` |
| `FAX_FROM_NAME` | From name for fax emails | `PBX Fax System` |
| `TIMEZONE` | System timezone | Auto-detected |
| `BEHIND_PROXY` | Running behind reverse proxy (`yes`/`no`) | `no` |
| `INSTALL_PROFILE` | `minimal` / `standard` / `advanced` | `standard` |
| `INSTALL_AVANTFAX` | Install fax system (`1`/`0`) | `1` |
| `FIREWALL_ENABLED` | Configure firewall (`1`/`0`) | `1` |
| `FAIL2BAN_ENABLED` | Install fail2ban (`1`/`0`) | `1` |
| `BACKUP_ENABLED` | Set up backup cron (`1`/`0`) | `1` |
| `INSTALL_WEBMIN` | Install Webmin (`yes`/`no`) | profile default |
| `INSTALL_FOP2` | FOP2 operator panel (HTML5) (`yes`/`no`) | `no` |
| `INSTALL_KNOCKD` | Port knocking daemon (`yes`/`no`) | advanced only |
| `INSTALL_OPENVPN` | OpenVPN server (`yes`/`no`) | advanced only |
| `INSTALL_SNGREP` | SIP traffic monitor (`yes`/`no`) | advanced only |
| `GITHUB_REPO` | GitHub repo for management scripts | `scriptmgr/pbx` |
| `SCRIPTS_REF` | Branch/tag for scripts | `main` |
| `GITHUB_TOKEN` | Token for private forks | optional |
| `NO_COLOR` | Disable colors and emojis | unset |

All generated passwords are stored in `/etc/pbx/pbx_passwords` (mode 600).

### SSL/TLS

The installer automatically detects and deploys existing Let's Encrypt certificates.

```bash
# Certificates are read from:
/etc/letsencrypt/live/pbx.example.com/fullchain.pem
/etc/letsencrypt/live/pbx.example.com/privkey.pem

# Deployed to Asterisk at:
/etc/asterisk/keys/asterisk.pem
/etc/asterisk/keys/asterisk-key.pem

# Auto-renewal hook:
/etc/letsencrypt/renewal-hooks/deploy/asterisk

# Manual deploy:
/usr/local/bin/deploy-asterisk-certs /etc/letsencrypt/live/pbx.example.com

# Check status:
pbx-ssl
```

TLS is enabled for PJSIP (port 5061) and Asterisk HTTPS Manager (ports 8088/8089).

### Reverse Proxy

To run behind Nginx, Caddy, Traefik, or Apache:

```bash
BEHIND_PROXY=yes ./install.sh
```

Apache binds to the loopback interface on a random port, persisted as `PROXY_HTTP_PORT` in `/etc/pbx/.env`.

**Nginx example:**
```nginx
server {
    listen 443 ssl http2;
    server_name pbx.example.com;
    ssl_certificate     /etc/letsencrypt/live/pbx.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/pbx.example.com/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:62543;   # port from: grep PROXY_HTTP_PORT /etc/pbx/.env
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

**Caddy example:**
```caddy
pbx.example.com {
    reverse_proxy 127.0.0.1:62543   # port from: grep PROXY_HTTP_PORT /etc/pbx/.env
}
```

### Directory Structure
```
/etc/pbx/
├── .env                    # Runtime config (mode 600)
├── pbx_passwords           # All credentials (mode 600)
└── state.json              # Installation state

/var/www/apache/pbx/        # Web root
├── admin/                  # FreePBX admin interface
├── avantfax/               # AvantFax fax interface
├── health/                 # JSON health endpoint
├── status/                 # Real-time status dashboard
├── callcenter/             # Asternic queue statistics
├── provisioning/           # HTTP phone provisioning
├── reminder/               # Telephone reminder app
└── ucp/                    # FreePBX User Control Panel

/var/lib/tftpboot/          # TFTP phone provisioning
/usr/local/bin/pbx-*        # Management scripts (32 tools)
/var/log/pbx/               # PBX-specific logs

/mnt/backups/pbx/           # Backup storage
├── config/                 # Configuration backups
├── database/               # Database backups
├── daily/ weekly/ monthly/ # Tiered retention
└── system/                 # System file backups
```

---

## 🌐 Web Interfaces

After installation, access your PBX through its FQDN:

| Interface | URL | Credentials |
|---|---|---|
| **Main Portal** | `https://pbx.example.com/` | — |
| **FreePBX Admin** | `https://pbx.example.com/admin/` | `/etc/pbx/pbx_passwords` |
| **User Control Panel** | `https://pbx.example.com/ucp/` | Extension credentials |
| **AvantFax** | `https://pbx.example.com/avantfax/` | `/etc/pbx/pbx_passwords` |
| **Webmin** | `https://pbx.example.com:9001/` | `/etc/pbx/pbx_passwords` |
| **Call Center Stats** | `https://pbx.example.com/callcenter/` | — |
| **System Status** | `https://pbx.example.com/status/` | — |
| **Health Endpoint** | `https://pbx.example.com/health/` | Public JSON |
| **Phone Provisioning** | `https://pbx.example.com/provisioning/` | — |
| **Reminder App** | `https://pbx.example.com/reminder/` | — |

> A self-signed certificate is generated by default. Run `pbx-ssl install` to replace it with a Let's Encrypt certificate.

---

## ✅ Post-Installation

1. Access the web interface at your FQDN
2. Log in to FreePBX — credentials in `/etc/pbx/pbx_passwords`
3. Add VoIP trunks: `pbx-config` → Add Trunk
4. Create extensions: `pbx-config` → Add Extension
5. Configure IVR and call flows in FreePBX Admin
6. Test with built-in demo apps (dial `DEMO`, `123`, `*43` for echo test)
7. Verify backups: `pbx-backup status`
8. Run security audit: `pbx-security`

---

## 🛠️ Management Scripts

### TUI Configuration Tool
```bash
pbx-config
# Add PJSIP extensions (auto-generated passwords)
# Add VoIP trunks (voip.ms, Flowroute, Telnyx, Twilio, Custom)
# Configure inbound routes (DID to extension)
# Configure outbound routes (dial patterns to trunk)
# View current config and apply/reload FreePBX
```

### System
```bash
pbx-status          # Full system dashboard
pbxstatus           # Compact snapshot
pbx-restart         # Safe restart (warns of active calls)
pbx-repair          # Auto-repair Asterisk/FreePBX
pbx-logs show       # View recent logs
pbx-diag            # Generate full diagnostics bundle
```

### Backup & Recovery
```bash
pbx-backup full          # Config + database backup
pbx-backup config        # Config only
pbx-backup db            # Database only
pbx-backup status        # List backups
pbx-cleanup              # Apply retention policy
pbx-cleanup --dry-run    # Preview removals
pbx-backup-remote sync   # Push to remote storage
pbx-backup-encrypt init  # Set up GPG encryption
```

### Security
```bash
pbx-security              # Full security audit
pbx-firewall status       # Show firewall rules
pbx-firewall add 203.0.113.10  # Whitelist an IP
pbx-ssh harden            # Apply SSH hardening
pbx-ssl status            # Certificate status
pbx-ssl install           # Install Let's Encrypt cert
```

### Calls & Reporting
```bash
pbx-calls active    # Current active calls
pbx-cdr --today     # Today's call records
pbx-cdr --week      # This week's records
pbx-trunks          # SIP trunk registration status
pbx-recordings list # Browse call recordings
```

### Phone Provisioning
```bash
pbx-tftp status                                   # TFTP service status
pbx-tftp add-device yealink AA:BB:CC:DD:EE:FF     # Add Yealink phone
pbx-tftp add-device polycom  AA:BB:CC:DD:EE:FF    # Add Polycom phone
pbx-tftp add-device grandstream AA:BB:CC:DD:EE:FF # Add Grandstream phone
pbx-tftp add-device cisco AA:BB:CC:DD:EE:FF       # Add Cisco phone
pbx-provision                                     # HTTP provisioning info
```

### Music on Hold
```bash
pbx-moh list                                              # Show MOH classes
pbx-moh add "Jazz Radio" "https://ice2.somafm.com/..."   # Add stream
pbx-moh add "Company Music" "/path/to/audio.wav"         # Add local file
pbx-moh remove                                            # Remove a source
```

---

## 🔍 Troubleshooting

| Problem | Solution |
|---|---|
| Services not starting | `pbx-repair` |
| Network issues | `pbx-network` |
| Disk space | `pbx-cleanup force` |
| SSL problems | `pbx-ssl status` then `pbx-ssl install` |
| Credential lookup | `pbx-passwords` or `/etc/pbx/pbx_passwords` |
| SIP trunk down | `pbx-trunks` |
| No active calls showing | `pbx-calls active` |

### Log Locations

| Log | Path |
|---|---|
| Installation | `/var/log/pbx-install.log` |
| Asterisk | `/var/log/asterisk/` |
| PBX tools | `/var/log/pbx/` |
| Apache | `/var/log/apache2/` or `/var/log/httpd/` |
| System | `journalctl` |

### Recovery
```bash
pbx-services status   # Check all services
pbx-repair            # Auto-repair
pbx-logs show         # Review logs
pbx-network           # Test connectivity
pbx-backup restore    # Restore from backup
```

---

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Test on AlmaLinux 9 and Debian 12
4. Open a Pull Request

### Development Environment
```bash
# Create test containers (incus — full systemd support)
incus launch images:almalinux/9 pbx-alma9
incus launch images:debian/12   pbx-deb12

# Push and run
incus file push install.sh pbx-alma9/root/install.sh
incus exec pbx-alma9 -- bash -c 'nohup bash /root/install.sh > /root/install.log 2>&1 &'
incus exec pbx-alma9 -- tail -f /root/install.log

# Run test suite
incus exec pbx-alma9 -- bash /root/full-script-test.sh
```

### Guidelines
- Test on both AlmaLinux 9 and Debian 12 before submitting
- Maintain idempotency — re-running `install.sh` must not break anything
- Use the `PKG_*` variable map — no hardcoded distro-specific package names
- All console output must be clean — verbose command output goes to log files
- Read `AI.md` for full project conventions

---

## 📄 License

MIT — see [LICENSE.md](LICENSE.md)

Third-party component licenses are listed at the bottom of [LICENSE.md](LICENSE.md).

## 🙏 Acknowledgments

- [Asterisk](https://www.asterisk.org/) — Open source communications toolkit
- [FreePBX](https://www.freepbx.org/) — Web-based open source GUI
- [IncrediblePBX](http://incrediblepbx.com/) — Inspiration and module reference
- [HylaFax+](https://hylafax.sourceforge.io/) — Enterprise fax server
- [AvantFax](https://sourceforge.net/projects/avantfax/) — HylaFax web interface

## 📞 Support

- **Docs**: `pbx-docs` — generates full reference on your server
- **Issues**: [GitHub Issues](https://github.com/scriptmgr/pbx/issues)
- **Wiki**: [GitHub Wiki](https://github.com/scriptmgr/pbx/wiki)

---

Built with ❤️ for the open source community
