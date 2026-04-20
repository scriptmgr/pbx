# AI Project Settings & Rules

This file defines all rules, conventions, and settings for AI agents working on this project.
**Read this file in full before making any changes. All rules are non-negotiable.**

---

## ⚠️ Non-Negotiable Rules (Cannot Be Overridden)

These apply to every piece of code, script, UI, config, and documentation in this project.

| # | Rule |
|---|---|
| 1 | **Target audience:** self-hosted, SMB, and enterprise. Assume self-hosted/SMB users are **not tech savvy**. |
| 2 | **Validate everything.** All inputs, env vars, user data, API responses — validated before use. |
| 3 | **Sanitize where appropriate.** Inputs that touch files, SQL, shell, or the network are sanitized. |
| 4 | **Save only what is valid.** Never persist invalid or partial data. |
| 5 | **Only clear what is invalid.** Do not wipe valid data when handling errors. |
| 6 | **Test everything where applicable.** If something can be tested, it is tested. |
| 7 | **Show tooltips or documentation where needed.** Users should never be left guessing. |
| 8 | **Security and mobile first** (where applicable). |
| 9 | **Always set sane defaults** for every option, config value, and env var. |
| 10 | **Security must never get in the way of usability.** Find the balance — don't lock users out. |
| 11 | **Offer help where applicable.** Proactively suggest next steps, fixes, or relevant docs. |
| 12 | **Responses are short, concise, yet descriptive and helpful.** No padding, no waffle. |
| 13 | **Always use SERVER FQDN** — never "server name". In all configs, scripts, output, and docs. |
| 14 | **Never display `0.0.0.0`, `127.0.0.1`, `::1`, or `localhost`** to the user. Always resolve and show the single most relevant address: FQDN first, then global/public IP, then LAN IP. Show only one. |
| 15 | **Keep `README.md` in sync** with the project at all times. Section order: About → Official Site (if defined) → Production → Client CLI → Other → Development. Production always before development. |
| 16 | **Always use `TODO.AI.md`** when working on **2 or more tasks**. Keep it up to date throughout. When all tasks are completed, **empty the file** (do not delete it). |
| 17 | **`TODO.md`** is the human task backlog — humans add to it, AI executes from it. **Never add items to `TODO.md` unprompted.** `TODO.AI.md` is strictly the AI's session-level working scratchpad. |
| 18 | **Never assume or guess.** If anything is unclear, ask the user before proceeding. |
| 19 | **Always search and read existing code** before implementing or changing anything. |
| 20 | **Never reboot, power off, or shut down the host system.** Those actions are allowed only inside test containers or VMs. |

---

## 🔤 Variable & Literal Convention

- Anything wrapped in `{}` is a **variable** — e.g. `{projectname}`, `{org}`, `{version}`
- Anything **not** wrapped in `{}` is a **literal** and must not be treated as a template
- `/etc/letsencrypt/live/domain` — this is a **literal directory path**, not a template or variable
- `?` at the end of a user message means they are **asking a question**

---

## 📂 Project Identity

| Key | Value |
|---|---|
| Project name variable | `{projectname}` |
| Project org variable | `{projectorg}` |
| README | `README.md` |
| License | MIT → `LICENSE.md` |
| Third-party licenses | Appended to the **bottom** of `LICENSE.md` |

---

## 🔒 Hard Rules (Never Break)

1. **No Co-authored-by trailers** — AI runs on behalf of the user; never add `Co-authored-by` to commits.
2. **No AI/ML features** — This PBX targets homelab to enterprise; AI/ML adds too much overhead/resource usage. Do not add any.
3. **No silent failures** — All scripts must handle errors explicitly; never let `set -euo pipefail` kill scripts silently.
4. **Pretty output only** — Console output must be clean and formatted. Log verbose output (e.g., yum/apt) to files, not stdout.
5. **Never block SSH** — SSH port must always be whitelisted before any firewall change.
6. **No hardcoded paths that differ per distro** — Use the `PKG_*` variable map system.
7. **Test before claiming done** — Never say something is production-ready without running the test suite.
8. **Never reboot, power off, or shut down the host system** — those actions are allowed only inside test containers or VMs.

---

## 📝 Commit Rules

- **Never** add `Co-authored-by` trailers.
- **Always** write the commit message to `.git/COMMIT_MESS` before committing.
- **Always** commit with `git commit -F .git/COMMIT_MESS`.
- **Format:**

```
{emoji} Subject line max 56 chars — never truncate {emoji}

Full body — explain what changed and why. Be specific.
List individual fixes/additions. No word wrap at 72 chars
needed, but keep lines readable.
```

- Subject must fit on one line — if it doesn't fit in 56 chars, shorten the wording, **never truncate mid-word**.
- Use relevant emojis that match the change type:
  - 🔧 Fix / bugfix
  - ✨ New feature
  - 📚 Documentation
  - 🚀 Performance
  - 🔒 Security
  - 🧹 Cleanup / refactor
  - 📦 Dependencies / packages
  - 🩺 Tests / health
  - 🐛 Bug

---

## 🧪 Testing Rules

- **Primary test containers:** `pbx-alma9` (AlmaLinux 9), `pbx-deb12` (Debian 12)
- **Full test suite:** `incus exec pbx-alma9 -- bash /root/full-script-test.sh`
- **Expected baseline:** 41P / 1W / 0F (1 WARN = rclone not installed, expected)
- **Syntax check all scripts before pushing:** `bash -n scriptname`
- **Always test on both alma9 AND deb12** — never just one distro.
- **Push scripts to containers:** `incus file push scripts/pbx-X pbx-alma9/usr/local/bin/pbx-X`
- **After any install.sh change:** test idempotency (re-run must not break anything).
- **Power actions:** never run `reboot`, `poweroff`, `shutdown`, or equivalent on the host. These are allowed only inside test containers or VMs.

---

## 🐳 Development Environment

Use **incus containers** (not Docker) — better systemd support:

- Host safety rule: do not reboot or power off the host system. If a test needs a reboot/power cycle, do it inside an incus container or VM only.

```bash
incus launch images:almalinux/9 pbx-alma9
incus launch images:debian/12   pbx-deb12
incus launch images:fedora/42   pbx-fedora42

# Push and run installer
incus file push install.sh pbx-alma9/root/install.sh
incus exec pbx-alma9 -- bash -c 'nohup bash /root/install.sh > /root/install.log 2>&1 &'
incus exec pbx-alma9 -- tail -f /root/install.log

# Push a single management script
incus file push scripts/pbx-status pbx-alma9/usr/local/bin/pbx-status
incus exec pbx-alma9 -- chmod +x /usr/local/bin/pbx-status
```

---

## 📁 Path Conventions

| Purpose | Path |
|---|---|
| Management scripts | `/usr/local/bin/pbx-*` |
| Credentials file | `/etc/pbx/pbx_passwords` (chmod 600) |
| Environment/config | `/etc/pbx/.env` (chmod 600) |
| MySQL root password file | `/etc/pbx/mysql_root_password` (chmod 600) |
| Install state JSON | `/etc/pbx/state.json` |
| Logs | `/var/log/pbx/` |
| Config backups | `/mnt/backups/pbx-config-backups/{epoch}/` |
| DB backups | `/mnt/backups/pbx/database/` |
| Call recordings | `/var/spool/asterisk/monitor/` |
| MOH files | `/var/lib/asterisk/moh/` |
| AGI scripts | `/var/lib/asterisk/agi-bin/` |
| TFTP root | `/var/lib/tftpboot/` |
| Health endpoint | `/var/www/html/health/index.php` |
| Status JSON | `/var/cache/pbx/status.json` |

---

## 🖥️ Output & Script Style

- All scripts use `set -euo pipefail`.
- Output helpers must be clean — no `_strip_e()` / `tr -dc` patterns:
  ```bash
  ok()   { printf "${GREEN}%s${NC}\n"   "$*"; }
  info() { printf "${BLUE}%s${NC}\n"    "$*"; }
  warn() { printf "${YELLOW}%s${NC}\n"  "$*"; }
  err()  { printf "${RED}%s${NC}\n"     "$*" >&2; }
  hdr()  { printf "\n${BOLD}%s${NC}\n" "$*"; }
  ```
- Detect tty for color: check `NO_COLOR`, `-t 1`, `TERM=dumb`, `CI=true`.
- **Verbose command output** (yum, apt, make, etc.) → log file, not stdout. Show a spinner or progress line.
- `grep` in pipelines under `pipefail` must use `|| VAR=default` **outside** the `$()`:
  ```bash
  COUNT=$(cmd | grep -c pattern) || COUNT=0   # correct
  COUNT=$(cmd | grep -c pattern || echo 0)    # WRONG — double-counts
  ```
- FreePBX version detection: use `grep` on `module.xml`, NOT `FreePBX::Create()` in PHP (causes "modules class loaded more than once").

---

## 📦 Package Mapping System

- Never hardcode package names that differ per distro.
- Use `PKG_*` variable map; set per distro in OS detection.
- Common names shared across all distros can be in a global array to reduce duplication.
- Always install packages with a pre-check (idempotency).

---

## 🔁 Idempotency

- Every installation step uses `skip_if_done COMPONENT && return 0`.
- Mark complete with `mark_done COMPONENT`.
- State stored in `/var/lib/pbx/install_inventory` and `/etc/pbx/state.json`.
- Re-running install.sh on a fully installed system must produce zero errors.

---

## 🏗️ Architecture Decisions

| Decision | Choice | Reason |
|---|---|---|
| VoIP engine | Asterisk 22 LTS | Latest LTS; 21 for CentOS 7, 18 for CentOS 6 |
| PBX management | FreePBX 17 | Industry standard; 70+ modules |
| PHP main | 8.2 | Required by FreePBX 17 |
| PHP fax | 7.4 | Required by AvantFax 3.4.1 |
| PHP isolation | PHP-FPM sockets | Dual-version, per-app pool |
| PHP-FPM user | `asterisk` | FreePBX files owned by asterisk:asterisk (660) |
| SIP | PJSIP only | chan_sip disabled |
| Fax | HylaFax+ + IAXmodem + AvantFax | Full fax stack, 4 virtual modems |
| TTS | Flite (system) + gTTS | No AI/ML; Festival/espeak fallback |
| Web server | Apache/HTTPD | FreePBX requires Apache |
| Database | MariaDB | Dedicated `asterisk` DB user (not root) |
| Firewall | iptables | Direct; Fail2ban for brute-force |
| Remote mgmt | Webmin (port 9001) | Module-pruned install |
| Phone provisioning | TFTP + HTTP | Yealink/Polycom/Grandstream/Cisco templates |
| Backups | Local + rclone | GPG encryption optional |
| WebRTC | WSS port 8089 | STUN via stun.l.google.com |

---

## 🌐 Supported Distros

| Distro | Status | Asterisk | FreePBX |
|---|---|---|---|
| AlmaLinux 9 | ✅ Primary | 22 | 17 |
| Debian 12 | ✅ Primary | 22 | 17 |
| Rocky Linux 9 | ✅ Supported | 22 | 17 |
| Ubuntu 22.04 LTS | ✅ Supported | 22 | 17 |
| RHEL 8/9 | ✅ Supported | 22 | 17 |
| Oracle Linux 8/9 | ✅ Supported | 22 | 17 |
| Fedora 35+ | ✅ Supported | 22 | 17 |
| AlmaLinux/Rocky 8 | 🟡 Secondary | 22 | 17 |
| Ubuntu 18.04/20.04 | 🟡 Secondary | 22 | 17 |
| Debian 10/11 | 🟡 Secondary | 22 | 17 |
| CentOS 7 | 🟡 Legacy | 21 | 17 |
| CentOS 6 | 🟡 Legacy | 18 | 15 |

---

## 🔑 Environment Variables (install.sh)

| Variable | Description | Default |
|---|---|---|
| `ADMIN_USERNAME` | Unified admin username for FreePBX and shared web tools | `administrator` |
| `ADMIN_PASSWORD` | Unified admin password for FreePBX and shared web tools | (random) |
| `MYSQL_ROOT_PASSWORD` | Optional preset MariaDB root password for install | (random, then stored in `/etc/pbx/mysql_root_password`) |
| `ADMIN_EMAIL` | Administrator email for alerts | (required) |
| `TIMEZONE` | System timezone | `America/New_York` |
| `BEHIND_PROXY` | Enable reverse proxy mode (`yes`/`no`) | `yes` |
| `INSTALL_FOP2` | Install FOP2 operator panel (HTML5) (`yes`/`no`) | `yes` |
| `INSTALL_WIREGUARD` | Install WireGuard client tools only (`yes`/`no`) | `yes` |
| `BACKUP_ENCRYPT` | Enable GPG backup encryption | `no` |
| `FAX_EMAIL` | Email address for inbound fax delivery | (admin email) |
| `FAX_FROM_NAME` | From name for fax emails | `PBX Fax` |
| `FAX_FROM_EMAIL` | From address for fax emails | (admin email) |
| `FREEPBX_ADMIN_USERNAME` | Compatibility alias for `ADMIN_USERNAME` | `administrator` |
| `AVANTFAX_ADMIN_USERNAME` | AvantFax web admin username | `ADMIN_USERNAME` |
| `AVANTFAX_ADMIN_PASSWORD` | AvantFax web admin password | (random) |

---

## 🔧 Known Gotchas

1. **PHP-FPM pool user must be `asterisk`** — default `www-data`/`apache` causes HTTP 500 on FreePBX.
2. **FreePBX admin user** — `fwconsole userman --add` removed in FP17; use direct SQL INSERT with SHA1 hash.
3. **freepbx.service is oneshot** — must be started via `systemctl`, not directly; direct start leaves orphaned socket.
4. **HylaFax binary path differs** — source-compiled: `/usr/local/sbin/faxq`; packages: `/usr/sbin/faxq`. Auto-detect with `command -v`.
5. **HylaFax spool ownership** — `/var/spool/hylafax/` must be `uucp:uucp` for FIFO creation.
6. **AvantFax source** — GitHub repo (iFax/AvantFAX) is 404; use SourceForge v3.4.1.
7. **AlmaLinux 9 pkg-config** — package is `pkgconf-pkg-config`, not `pkgconfig`.
8. **dnf config-manager** — install `dnf-plugins-core` before using `dnf config-manager`.
9. **unixODBC-devel** — capital ODBC on RHEL-family distros.
10. **grep + pipefail** — `grep -c` exits 1 on no matches; use `|| VAR=0` outside `$()`.
11. **FreePBX version from PHP** — `FreePBX::Create()` in CLI causes "modules class loaded more than once"; use `grep` on `module.xml` instead.

---

## 📋 Management Scripts (32 total)

All in `/usr/local/bin/`, all support `--help`.

| Script | Purpose |
|---|---|
| `pbxstatus` | Quick compact status snapshot |
| `pbx-status` | Full column-aligned dashboard |
| `pbx-config` | TUI dialog tool: extensions, trunks, routes |
| `pbx-restart` | Safe service restart (warns of call drop) |
| `pbx-repair` | Asterisk/FreePBX auto-repair |
| `pbx-backup` | Config + DB backup with GPG + sha256 |
| `pbx-backup-encrypt` | GPG key management for backup encryption |
| `pbx-backup-remote` | rclone sync to S3/Backblaze/SFTP/GCS |
| `pbx-cleanup` | Backup retention (delete older than 30 days) |
| `pbx-firewall` | iptables rules management |
| `pbx-ssh` | SSH configuration and hardening |
| `pbx-security` | Full security audit |
| `pbx-services` | Service status badges |
| `pbx-logs` | Asterisk/FreePBX log viewer |
| `pbx-network` | Network interfaces, NAT, port check |
| `pbx-vpn` | VPN client setup guidance and status |
| `pbx-ssl` | Let's Encrypt certificate status |
| `pbx-passwords` | Credential display (masked by default) |
| `pbx-docs` | Quick reference documentation |
| `pbx-moh` | Music on Hold class management |
| `pbx-asterisk` | Asterisk CLI wrapper + status |
| `pbx-calls` | Active call monitoring + non-interactive count |
| `pbx-cdr` | CDR reporting (today/week/month) |
| `pbx-diag` | Full diagnostics report bundle |
| `pbx-recordings` | Call recording browser |
| `pbx-trunks` | SIP trunk registration health |
| `pbx-provision` | Phone auto-provisioning status |
| `pbx-tftp` | TFTP server + per-vendor config generation |
| `pbx-webmin` | Webmin status and management |
| `pbx-autoupdate` | FreePBX weekly module updates |
| `pbx-update` | Self-update management scripts from GitHub |
| `pbx-add-ip` | Dynamic firewall IP whitelist |
| `pbx-ip-checker` | Public IP change detector (cron) |

---

## 🩺 Health Endpoint

- **URL:** `http://{server}/health`
- **Returns:** JSON, public-safe (no private IPs, no passwords)
- **HTTP 200** when all core services are up; **HTTP 503** when degraded
- **Key fields:** `status`, `hostname`, `asterisk`, `freepbx`, `database`, `fax`, `system`, `features`, `data_age_seconds`
- **Updated by:** `/etc/cron.d/pbx-status-update` every 5 minutes

---

*Last updated: 2026-04-12*
*Maintained by: AI Development Team*
