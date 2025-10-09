# Complete PBX Installation System

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![GitHub](https://img.shields.io/badge/GitHub-scriptmgr%2Fpbx-blue)](https://github.com/scriptmgr/pbx)
[![Platform](https://img.shields.io/badge/Platform-Linux-green)](https://www.linux.org/)
[![Asterisk](https://img.shields.io/badge/Asterisk-21_LTS-orange)](https://www.asterisk.org/)
[![FreePBX](https://img.shields.io/badge/FreePBX-17-red)](https://www.freepbx.org/)

A production-ready, fully automated installation script for deploying a complete enterprise PBX system with Asterisk, FreePBX, AvantFax, and comprehensive management tools.

## 🌟 Features

### Core PBX System
- **Asterisk 21 LTS** - Enterprise VoIP engine with full SIP/IAX support
- **FreePBX 17** - Modern web-based PBX management interface
- **70+ Free Modules** - All IncrediblePBX modules included
- **Multi-Transport SIP** - UDP, TCP, and TLS support
- **WebRTC Support** - Browser-based calling capabilities
- **Anonymous SIP** - Support for anonymous inbound calls
- **Demo Applications** - Built-in test applications (DEMO, 123, 947, 951, TODAY, LENNY, 4747)

### Enterprise Fax System
- **4 Virtual Fax Modems** - IAXmodem instances (ttyIAX0-3)
- **HylaFax+ Server** - Compiled from source for maximum compatibility
- **AvantFax Web Interface** - Modern fax management with email integration
- **Automatic Load Balancing** - Distribute faxes across modems
- **Fax-to-Email** - Automatic delivery to designated addresses

### Security & Monitoring
- **Fail2ban Protection** - Automated intrusion prevention
- **Intelligent Firewall** - PBX-optimized security rules
- **SSH Hardening** - Secure remote access configuration
- **SSL/TLS Support** - Let's Encrypt + self-signed fallback
- **Rate Limiting** - Protection against SIP attacks
- **Security Auditing** - Built-in vulnerability scanning

### Smart Backup System
- **Tiered Retention** - Config (30d), Database (14d), Daily (7d), Weekly (4w), Monthly (6m)
- **Size Management** - Never exceeds 10GB total space
- **Automatic Cleanup** - Intelligent retention management
- **Multiple Backup Types** - Configuration, database, and system backups
- **Backup Verification** - Integrity checking for all backups

### Management Suite
16 powerful `pbx-*` command-line tools for complete system control:
- `pbx-config` - **TUI Configuration Tool** (Extensions, Trunks, Routes)
- `pbx-status` - System overview and health monitoring
- `pbx-restart` - Safe service restart procedures
- `pbx-repair` - Automatic system repair and recovery
- `pbx-backup` - Manual backup operations
- `pbx-cleanup` - Backup retention management
- `pbx-firewall` - Firewall rule management
- `pbx-ssh` - SSH configuration and key management
- `pbx-security` - Security audit and vulnerability checks
- `pbx-services` - Service management and monitoring
- `pbx-logs` - Log analysis and management
- `pbx-network` - Network diagnostics
- `pbx-ssl` - SSL certificate management
- `pbx-passwords` - Credential management
- `pbx-docs` - Documentation generation
- `pbx-moh` - Music on Hold management

### Demo Applications & Features
**Built-in test applications accessible from any extension:**
- **DEMO** - System demonstration and information
- **123** - Speaking clock (time/date announcements)
- **947** - Weather report (TTS demonstration)
- **951 or TODAY** - Today's date announcement
- **4747 or LENNY** - Telemarketer bot (keep spam callers busy)
- ***43** - Echo test (audio quality check)
- ***469, *470** - Conference rooms (multi-party calling)
- ***97** - Voicemail main menu
- ***610** - Music on hold test

**Feature Codes:**
- ***72 / *73** - Call forwarding (enable/disable)
- ***76 / *77** - Do not disturb (enable/disable)
- ***78** - Call recording toggle
- ***68** - Wakeup call service
- ***500** - Call pickup
- ***501** - Directed call pickup
- ***41** - Caller ID test

## 📋 Prerequisites

### Supported Operating Systems

**Base Distributions:**
- **Ubuntu 22.04+** LTS (Recommended for production)
- **Debian 11+** (Bullseye or newer)
- **Rocky Linux 8+** (RHEL-compatible, recommended for enterprise)
- **AlmaLinux 8+** (RHEL-compatible)
- **RHEL 8+** (Requires valid subscription for package repositories)
- **Oracle Linux 8+** (RHEL-compatible)
- **Fedora 38+** (Rapid release cycle - suitable for testing/development)

**Derivative Distributions:**
The installer automatically detects and supports all distributions based on the above:
- **Debian-based**: Linux Mint, MX Linux, Kali Linux, Parrot OS, Deepin, etc.
- **Ubuntu-based**: Pop!_OS, Elementary OS, Zorin OS, Linux Mint, KDE neon, etc.
- **RHEL-based**: CentOS Stream, Scientific Linux, VzLinux, EuroLinux, etc.

### System Requirements
- Fresh OS installation (no existing web/database services)
- Root access
- 4GB RAM minimum (8GB recommended)
- 20GB disk space minimum (50GB recommended)
- Active internet connection
- Valid FQDN (for SSL certificates)

### ⚠️ Important Notes
- **RHEL**: Requires active subscription for repository access
- **Fedora**: Short support cycle (~13 months), frequent updates - use for testing/development
- **Production**: Recommended distributions are Ubuntu LTS, Debian, Rocky Linux, or AlmaLinux
- **CentOS**: End of Life - migrate to Rocky Linux or AlmaLinux

## 🚀 Quick Start

### One-Line Installation
```bash
wget https://raw.githubusercontent.com/scriptmgr/pbx/main/install.sh && chmod +x install.sh && ./install.sh
```

### Custom Installation
```bash
# Download the installer
wget https://raw.githubusercontent.com/scriptmgr/pbx/main/install.sh

# Make executable
chmod +x install.sh

# Set custom options
FREEPBX_ADMIN_PASSWORD='MySecurePass123' \
ADMIN_EMAIL='admin@company.com' \
TIMEZONE='America/New_York' \
./install.sh
```

## 🔧 Configuration

### Environment Variables
| Variable | Description | Default |
|----------|-------------|---------|
| `FREEPBX_ADMIN_PASSWORD` | FreePBX admin password | Auto-generated |
| `MYSQL_ROOT_PASSWORD` | MySQL root password | Auto-generated |
| `ADMIN_EMAIL` | Administrator email | admin@[domain] |
| `TIMEZONE` | System timezone | Auto-detected |
| `BEHIND_PROXY` | Running behind reverse proxy (yes/no) | no |

### SSL/TLS Configuration

The installer automatically detects and integrates existing Let's Encrypt certificates:

**Automatic Detection:**
- Scans `/etc/letsencrypt/live/` for certificates
- Matches domain or uses first available certificate
- Deploys to Asterisk automatically

**Certificate Deployment:**
```bash
# Certificates are deployed to:
/etc/asterisk/keys/asterisk.pem         # Full chain certificate
/etc/asterisk/keys/asterisk-key.pem     # Private key

# Renewal hook automatically updates certificates
/etc/letsencrypt/renewal-hooks/deploy/asterisk
```

**Manual Certificate Deployment:**
```bash
# Deploy certificates manually
/usr/local/bin/deploy-asterisk-certs /etc/letsencrypt/live/your-domain.com

# Check certificate status
pbx-ssl
```

**TLS Support Enabled For:**
- PJSIP (SIP over TLS) on port 5061
- Asterisk HTTP/HTTPS Manager Interface (port 8088/8089)
- Apache web server (if certificates available)

### Reverse Proxy Configuration

Configure the PBX to run behind a reverse proxy (Nginx, Apache, Traefik, Caddy, etc.):

**Installation with Reverse Proxy:**
```bash
# Set BEHIND_PROXY environment variable
BEHIND_PROXY=yes ./install.sh
```

**What Gets Configured:**
- Apache configured to trust `X-Forwarded-For` headers
- `X-Forwarded-Proto` detection for HTTPS
- RemoteIP module enabled
- Trusted proxy networks: 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16

**Example Nginx Configuration:**
```nginx
server {
    listen 443 ssl http2;
    server_name pbx.example.com;

    ssl_certificate /etc/letsencrypt/live/pbx.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/pbx.example.com/privkey.pem;

    location / {
        proxy_pass http://localhost:80;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

**Example Caddy Configuration:**
```caddy
pbx.example.com {
    reverse_proxy localhost:80
}
```

### Directory Structure
```
/var/www/apache/pbx/           # Web root
├── index.html                 # Main portal
├── admin/                     # FreePBX interface
├── avantfax/                  # AvantFax interface
└── status/                    # System status

/mnt/backups/pbx/              # Backup storage
├── config/                    # Configuration backups
├── database/                  # Database backups
├── daily/                     # Daily backups
├── weekly/                    # Weekly backups
├── monthly/                   # Monthly backups
└── system/                    # System file backups

/usr/local/bin/                # Management scripts
├── pbx-status
├── pbx-backup
├── pbx-cleanup
└── ... (15 scripts total)
```

## 🌐 Web Interfaces

After installation, access your PBX system through:

| Interface | URL | Description |
|-----------|-----|-------------|
| **Main Portal** | `http://your-fqdn/` | System overview with links to all services |
| **FreePBX Admin** | `http://your-fqdn/admin/` | Complete PBX configuration |
| **AvantFax** | `http://your-fqdn/avantfax/` | Fax management interface |
| **HTTPS Access** | `https://your-fqdn/` | Secure access (if SSL configured) |

Default credentials are stored in `/root/.pbx_passwords`

## 📚 Documentation

### Installation Process
The installer performs these steps automatically:
1. System detection and preparation
2. Repository configuration
3. Core dependency installation
4. MariaDB database setup
5. PHP 8.2 + PHP 7.4 installation (dual stack)
6. Apache web server configuration
7. Asterisk compilation and installation
8. FreePBX installation with all modules
9. AvantFax + HylaFax+ setup
10. Security hardening
11. SSL certificate configuration
12. Backup system setup
13. Management script deployment
14. Service optimization
15. Final configuration and testing

### Post-Installation Steps
1. **Access the Web Interface**: Navigate to `http://your-fqdn/`
2. **Login to FreePBX**: Use credentials from `/root/.pbx_passwords`
3. **Configure SIP Trunks**: Add your VoIP providers
4. **Create Extensions**: Set up user extensions
5. **Configure IVR**: Design your call flow
6. **Test the System**: Use demo applications
7. **Setup Backups**: Verify automatic backups are running
8. **Review Security**: Run `pbx-security` for audit

## 🛠️ Management Scripts

### PBX Configuration Tool (TUI)
```bash
# Launch interactive configuration tool
pbx-config

# Features:
# - Add Extensions (PJSIP with auto-generated passwords)
# - Add VoIP Trunks (voip.ms, Flowroute, Telnyx, Twilio, Custom)
# - Configure Inbound Routes (DID to extension mapping)
# - Configure Outbound Routes (dial patterns and trunk selection)
# - View Current Configuration
# - Apply & Reload FreePBX
```

**Supported VoIP Providers:**
- **voip.ms** - Full PJSIP configuration with registration
- **Flowroute** - Enterprise SIP trunking
- **Telnyx** - Carrier-grade VoIP service
- **Twilio** - Elastic SIP trunking
- **Custom** - Manual configuration for any provider

### System Management
```bash
# Check system status
pbx-status

# Restart all services safely
pbx-restart

# Repair system issues
pbx-repair

# View system logs
pbx-logs show
```

### Backup Management
```bash
# Manual backup
pbx-backup full

# Check backup status
pbx-backup status

# Cleanup old backups
pbx-cleanup

# Verify backup integrity
pbx-cleanup verify
```

### Security Management
```bash
# Security audit
pbx-security

# Firewall management
pbx-firewall status
pbx-firewall add 192.168.1.100

# SSH hardening
pbx-ssh harden

# SSL certificate management
pbx-ssl install  # Let's Encrypt
pbx-ssl status   # Check status
```

### Service Management
```bash
# Check all services
pbx-services status

# Monitor service health
pbx-services check

# Network diagnostics
pbx-network
```

## 🎵 Music on Hold

### Add Streaming Source
```bash
pbx-moh add "Jazz Radio" "https://ice2.somafm.com/jazzgroove-256-mp3"
```

### Add Local Files
```bash
pbx-moh add "Company Music" "/path/to/audio.wav"
```

### Manage Sources
```bash
pbx-moh list    # Show all sources
pbx-moh test    # Test playback
pbx-moh remove  # Remove source
```

## 🔍 Troubleshooting

### Common Issues

| Problem | Solution |
|---------|----------|
| Services not starting | Run `pbx-repair` for automatic fixes |
| Network connectivity | Use `pbx-network` for diagnostics |
| Storage issues | Check with `pbx-status`, cleanup with `pbx-cleanup force` |
| SSL problems | Run `pbx-ssl status` and `pbx-ssl test` |
| Login issues | Check `/root/.pbx_passwords` for credentials |

### Log Locations
- Installation: `/var/log/pbx-install.log`
- Asterisk: `/var/log/asterisk/`
- Apache: `/var/log/apache2/` or `/var/log/httpd/`
- System: `journalctl` or `/var/log/syslog`

### Recovery Procedures
1. Check service status: `pbx-services status`
2. Run system repair: `pbx-repair`
3. Review logs: `pbx-logs show`
4. Test connectivity: `pbx-network`
5. Restore from backup if needed

## 🤝 Contributing

We welcome contributions! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

### Development Guidelines
- Maintain bash script compatibility
- Include comprehensive error handling
- Add logging for all operations
- Update documentation for new features
- Test on all supported distributions

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [Asterisk](https://www.asterisk.org/) - The open source communications toolkit
- [FreePBX](https://www.freepbx.org/) - Web-based open source GUI
- [IncrediblePBX](http://incrediblepbx.com/) - For module inspiration
- [HylaFax+](https://hylafax.sourceforge.io/) - Enterprise fax server
- [AvantFax](https://www.avantfax.com/) - HylaFax web interface

## 📞 Support

- **Documentation**: Run `pbx-docs generate` for complete system documentation
- **Issues**: [GitHub Issues](https://github.com/scriptmgr/pbx/issues)
- **Wiki**: [GitHub Wiki](https://github.com/scriptmgr/pbx/wiki)

## 🚦 Status

- **Current Version**: 1.0
- **Asterisk Version**: 21 LTS
- **FreePBX Version**: 17
- **Last Updated**: 2024

---

**Note**: This installation creates a complete, production-ready PBX system. All default passwords are automatically generated and stored securely. The system is designed to "just work" out of the box while providing complete administrative control through both web interfaces and command-line tools.

---

Built with ❤️ for the open source community