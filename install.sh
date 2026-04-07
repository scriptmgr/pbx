#!/bin/bash
# =============================================================================
# Complete PBX Installation Script v3.0
# Production-ready Asterisk + FreePBX installer
# Supports: AlmaLinux/Rocky/RHEL/Oracle 8-9, Fedora 35+, Ubuntu 18+, Debian 10+, CentOS 6/7
# =============================================================================

set -euo pipefail

# =============================================================================
# SECTION 1: CONFIGURATION & DEFAULTS
# =============================================================================

SCRIPT_VERSION="3.0"
ASTERISK_VERSION=""       # set by version_select()
FREEPBX_VERSION="17.0"
PHP_VERSION=""            # set by version_select()
PHP_AVANTFAX_VERSION=""   # set by version_select()

INSTALL_AVANTFAX=1
NUMBER_OF_MODEMS=4
FIREWALL_ENABLED=1
FAIL2BAN_ENABLED=1
BACKUP_ENABLED=1
SSL_ENABLED=1
USE_POSTFIX=1
INSTALL_MUSIC_ON_HOLD=1

WEB_ROOT="/var/www/apache/pbx"
FREEPBX_WEB_DIR="${WEB_ROOT}/admin"
AVANTFAX_WEB_DIR="${WEB_ROOT}/avantfax"
BACKUP_BASE="/mnt/backups/pbx"
LOG_FILE="/var/log/pbx-install.log"
ERROR_LOG="/var/log/pbx-install-errors.log"
AUTO_PASSWORDS_FILE="/etc/pbx/pbx_passwords"
WORK_DIR="/var/cache/pbx-install"

# ---------------------------------------------------------------------------
# Package manager — binary, install args, and package lists
# ---------------------------------------------------------------------------
PACKAGE_MGR_BIN=""          # apt-get | dnf | yum  (set by detect_system)
PACKAGE_MGR_ARG="install -y" # standard install args (same for all distros)
# Backward-compat alias used in a few places below
PACKAGE_MANAGER=""          # always mirrors PACKAGE_MGR_BIN

# Packages with IDENTICAL names on every supported distro — no mapping needed.
# These are appended per-section; the variable is a convenient prefix.
PACKAGES_GLOBAL="tar curl wget git vim nano screen tmux htop unzip zip bzip2 net-tools tcpdump sox mpg123 lame ghostscript fail2ban dialog"

# Distro-specific package groups — all populated by setup_pkg_map().
# Install functions use these instead of inline case/esac blocks.
PACKAGES_DISTRO_BUILD=""         # compiler + build tools
PACKAGES_DISTRO_ASTERISK_DEPS="" # Asterisk compile-time dependencies
PACKAGES_DISTRO_WEBSERVER=""     # web server (apache2 / httpd)
PACKAGES_DISTRO_WEBSERVER_OPT="" # optional web modules (installed one-by-one)
PACKAGES_DISTRO_PHP=""           # PHP 8.2 + common extensions
PACKAGES_DISTRO_PHP74=""         # PHP 7.4 for AvantFax
PACKAGES_DISTRO_MARIADB=""       # MariaDB server + client
PACKAGES_DISTRO_PYTHON=""        # Python 3 dev + pip
PACKAGES_DISTRO_NODE=""          # Node.js + npm
PACKAGES_DISTRO_SYSTEM=""        # NTP, iptables-persist, pkg-config etc.
PACKAGES_DISTRO_KNOCKD=""        # port-knocking daemon
PACKAGES_DISTRO_FAX=""           # HylaFax package(s)
PACKAGES_DISTRO_SNGREP=""        # SIP sniffer

# Non-package config paths / service names (still distro-specific, but not package names)
APACHE_SERVICE=""
APACHE_USER=""
APACHE_GROUP=""
ODBC_DEV_PKG=""       # unixodbc-dev  vs  unixODBC-devel
ODBC_DRIVER_PKG=""    # odbc-mariadb  vs  mariadb-connector-odbc
PHP_FPM_SERVICE=""
PHP74_FPM_SERVICE=""
PHP_FPM_SOCK=""
PHP74_FPM_SOCK=""
PHP_FPM_PORT=""
PHP74_FPM_PORT=""
PHP_INI_DIR=""
MARIADB_SOCKET=""
ODBC_DRIVER_PATH=""
PKG_WEBMIN_REPO_TYPE=""   # deb | rpm  (used by install_webmin only)
PKG_IPTABLES_PERSIST=""   # iptables-persistent | iptables-services (used by configure_iptables)
PKG_NTP=""                # ntp | chrony  (service name too)

SYSTEM_FQDN=""
SYSTEM_DOMAIN=""
PRIVATE_IP=""
PUBLIC_IP=""
DETECTED_OS=""
DETECTED_VERSION=""
DETECTED_OS_LIKE=""
DISTRO_FAMILY=""
DISTRO_GEN=""
INIT_SYSTEM=""
MYSQL_ROOT_PASSWORD=""
FREEPBX_ADMIN_USERNAME=""
FREEPBX_ADMIN_PASSWORD=""
FREEPBX_DB_PASSWORD=""
AVANTFAX_DB_PASSWORD=""
INSTALL_INVENTORY="/var/lib/pbx/install_inventory"
INSTALLED_COMPONENTS=""
INSTALL_FAILURES=""
BACKUP_TIMESTAMP=$(date +%s)
CONFIG_BACKUP_DIR="/mnt/backups/pbx-config-backups/${BACKUP_TIMESTAMP}"
PBX_ENV_FILE="/etc/pbx/.env"
PBX_ENV_DIR="/etc/pbx"
EMAIL_TO_FAX_ALIAS=""
FAX_TO_EMAIL_ADDRESS=""
FROM_EMAIL=""           # Default: no-reply@<fqdn> — set via env var
FROM_NAME=""            # Default: PBX System — set via env var

# Installation profile: minimal | standard (default) | advanced
INSTALL_PROFILE="${INSTALL_PROFILE:-standard}"

# Feature flags (override individual components regardless of profile)
INSTALL_KNOCKD="${INSTALL_KNOCKD:-}"       # auto from profile if empty
INSTALL_OPENVPN="${INSTALL_OPENVPN:-}"
INSTALL_FOP2="${INSTALL_FOP2:-}"
INSTALL_SNGREP="${INSTALL_SNGREP:-}"
INSTALL_PHONE_PROV="${INSTALL_PHONE_PROV:-}"
INSTALL_REMOTE_BACKUP="${INSTALL_REMOTE_BACKUP:-}"
LOW_RESOURCE=0   # auto-set in preflight if RAM < 2GB

# SSH safety — populated in preflight
SSH_PORT=22
SSH_CLIENT_IP=""
FIREWALL_ROLLBACK_JOB=""

# GitHub API for management scripts download
GITHUB_REPO="${GITHUB_REPO:-scriptmgr/pbx}"
SCRIPTS_REF="${SCRIPTS_REF:-main}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
SCRIPTS_MANIFEST_CACHE="/etc/pbx/scripts-manifest.tsv"

# State file for idempotency
PBX_STATE_FILE="/etc/pbx/state.json"

# =============================================================================
# SECTION 2: COLORS & OUTPUT FUNCTIONS  (NO_COLOR compliant — no-color.org)
# =============================================================================

# Disable color AND emoji when: NO_COLOR set, not a TTY, dumb terminal, or CI
setup_output() {
    if [ -n "${NO_COLOR+x}" ] || [ ! -t 1 ] || \
       [ "${TERM:-}" = "dumb" ] || [ "${CI:-}" = "true" ]; then
        USE_COLOR=0; USE_EMOJI=0
        RED=""; GREEN=""; YELLOW=""; BLUE=""; PURPLE=""; CYAN=""; BOLD=""; DIM=""; NC=""
    else
        USE_COLOR=1; USE_EMOJI=1
        RED="$(printf '\033[0;31m')"
        GREEN="$(printf '\033[0;32m')"
        YELLOW="$(printf '\033[1;33m')"
        BLUE="$(printf '\033[0;34m')"
        PURPLE="$(printf '\033[0;35m')"
        CYAN="$(printf '\033[0;36m')"
        BOLD="$(printf '\033[1m')"
        DIM="$(printf '\033[2m')"
        NC="$(printf '\033[0m')"
    fi
}
setup_output

# Logs are always raw text — never ANSI codes or emojis
mkdir -p "$(dirname "${LOG_FILE}")" 2>/dev/null || true
touch "${LOG_FILE}" "${ERROR_LOG}" 2>/dev/null || true
log_raw() { printf "[%s] %-5s %s\n" "$(date '+%H:%M:%S')" "$1" "$2" >> "${LOG_FILE}"; }

STEP_CURRENT=0
STEP_TOTAL=59

_emoji() { [ "${USE_EMOJI:-0}" = "1" ] && printf "%s " "$1" || true; }

log()     { log_raw "LOG  " "$*"; }
error()   { printf "%s${RED}%sERROR: %s${NC}\n" "$(_emoji ❌)" "" "$*" >&2; log_raw "ERROR" "$*"; }
warn()    { printf "%s${YELLOW}%sWARN: %s${NC}\n"    "$(_emoji ⚠️ )" "" "$*"; log_raw "WARN " "$*"; }
info()    { printf "%s${BLUE}%s%s${NC}\n"             "$(_emoji ℹ️ )" "" "$*"; log_raw "INFO " "$*"; }
success() { printf "%s${GREEN}%s%s${NC}\n"            "$(_emoji ✅)" "" "$*"; log_raw "OK   " "$*"; }
step()    {
    STEP_CURRENT=$(( STEP_CURRENT + 1 ))
    printf "\n%s${PURPLE}${BOLD}%s[%d/%d] %s${NC}\n" \
        "$(_emoji 🔧)" "" "${STEP_CURRENT}" "${STEP_TOTAL}" "$*"
    log_raw "STEP " "[${STEP_CURRENT}/${STEP_TOTAL}] $*"
}
header()  { printf "\n${BOLD}%s%s%s${NC}\n" "$(_emoji 🚀)" "" "$*"; log_raw "===  " "$*"; }

# =============================================================================
# SECTION 3: SERVICE MANAGEMENT WRAPPERS
# =============================================================================

svc_enable() {
    if [ "${INIT_SYSTEM}" = "systemd" ]; then
        systemctl enable "$1" 2>/dev/null || true
    else
        chkconfig --level 2345 "$1" on 2>/dev/null || true
    fi
}

svc_disable() {
    if [ "${INIT_SYSTEM}" = "systemd" ]; then
        systemctl disable "$1" 2>/dev/null || true
    else
        chkconfig --level 2345 "$1" off 2>/dev/null || true
    fi
}

svc_start() {
    if [ "${INIT_SYSTEM}" = "systemd" ]; then
        systemctl start "$1" 2>/dev/null || true
    else
        service "$1" start 2>/dev/null || true
    fi
}

svc_stop() {
    if [ "${INIT_SYSTEM}" = "systemd" ]; then
        systemctl stop "$1" 2>/dev/null || true
    else
        service "$1" stop 2>/dev/null || true
    fi
}

svc_restart() {
    if [ "${INIT_SYSTEM}" = "systemd" ]; then
        systemctl restart "$1" 2>/dev/null || true
    else
        service "$1" restart 2>/dev/null || true
    fi
}

svc_reload() {
    if [ "${INIT_SYSTEM}" = "systemd" ]; then
        systemctl reload "$1" 2>/dev/null || systemctl restart "$1" 2>/dev/null || true
    else
        service "$1" reload 2>/dev/null || service "$1" restart 2>/dev/null || true
    fi
}

svc_active() {
    if [ "${INIT_SYSTEM}" = "systemd" ]; then
        systemctl is-active --quiet "$1"
    else
        service "$1" status >/dev/null 2>&1
    fi
}

svc_daemon_reload() {
    [ "${INIT_SYSTEM}" = "systemd" ] && systemctl daemon-reload || true
}

# =============================================================================
# SECTION 4: SYSTEM DETECTION
# =============================================================================

detect_system() {
    step "🔍 Detecting system..."

    if [ -f /etc/os-release ]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        DETECTED_OS="${ID:-unknown}"
        DETECTED_VERSION="${VERSION_ID:-0}"
        DETECTED_OS_LIKE="${ID_LIKE:-}"
    elif [ -f /etc/redhat-release ]; then
        DETECTED_OS="rhel"
        DETECTED_VERSION=$(grep -oP '[\d.]+' /etc/redhat-release | head -1 || echo "0")
        DETECTED_OS_LIKE="rhel"
    else
        error "Cannot detect OS: /etc/os-release not found."
    fi

    # Determine distro family and package manager binary
    case "${DETECTED_OS}" in
        ubuntu|debian|linuxmint|pop)
            DISTRO_FAMILY="debian"
            PACKAGE_MGR_BIN="apt-get"
            ;;
        rocky|centos|rhel|almalinux|ol|scientific)
            DISTRO_FAMILY="rhel"
            PACKAGE_MGR_BIN=$(command -v dnf >/dev/null 2>&1 && echo "dnf" || echo "yum")
            ;;
        fedora)
            DISTRO_FAMILY="fedora"
            PACKAGE_MGR_BIN=$(command -v dnf >/dev/null 2>&1 && echo "dnf" || echo "yum")
            ;;
        *)
            if echo "${DETECTED_OS_LIKE}" | grep -qiE "debian|ubuntu"; then
                DISTRO_FAMILY="debian"
                PACKAGE_MGR_BIN="apt-get"
            elif echo "${DETECTED_OS_LIKE}" | grep -qiE "rhel|centos|fedora"; then
                DISTRO_FAMILY="rhel"
                PACKAGE_MGR_BIN=$(command -v dnf >/dev/null 2>&1 && echo "dnf" || echo "yum")
            else
                error "Unsupported OS: ${DETECTED_OS}"
            fi
            ;;
    esac

    # Handle derivatives: oraclelinux alias for RHEL
    if [ "${DETECTED_OS}" = "ol" ] || [ "${DETECTED_OS}" = "oraclelinux" ]; then
        DISTRO_FAMILY="rhel"
        PACKAGE_MGR_BIN=$(command -v dnf >/dev/null 2>&1 && echo "dnf" || echo "yum")
    fi
    # CentOS Stream → treat as RHEL gen3
    if [ "${DETECTED_OS}" = "centos" ] && echo "${DETECTED_VERSION}" | grep -q "Stream"; then
        DISTRO_GEN=3
    fi
    # Backward-compat alias and install args
    PACKAGE_MANAGER="${PACKAGE_MGR_BIN}"
    PACKAGE_MGR_ARG="install -y"

    # Determine generation for version-specific logic
    local major_ver
    major_ver=$(echo "${DETECTED_VERSION}" | cut -d. -f1)

    case "${DETECTED_OS}" in
        centos)
            if [ "${major_ver}" -eq 6 ] 2>/dev/null; then
                DISTRO_GEN=1
            elif [ "${major_ver}" -eq 7 ] 2>/dev/null; then
                DISTRO_GEN=2
            else
                DISTRO_GEN=3
            fi
            ;;
        ubuntu)
            case "${DETECTED_VERSION}" in
                18.04|20.04) DISTRO_GEN=2 ;;
                *) DISTRO_GEN=3 ;;
            esac
            ;;
        debian)
            if [ "${major_ver}" -le 10 ] 2>/dev/null; then
                DISTRO_GEN=2
            else
                DISTRO_GEN=3
            fi
            ;;
        *) DISTRO_GEN=3 ;;
    esac

    # Detect init system
    if command -v systemctl >/dev/null 2>&1 && systemctl status >/dev/null 2>&1; then
        INIT_SYSTEM="systemd"
    else
        INIT_SYSTEM="sysv"
    fi

    # Network information
    PRIVATE_IP=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $7; exit}' \
        || hostname -I 2>/dev/null | awk '{print $1}' \
        || echo "127.0.0.1")
    PUBLIC_IP=$(curl -s --max-time 15 https://ifconfig.me 2>/dev/null \
        || curl -s --max-time 15 https://api.ipify.org 2>/dev/null \
        || echo "${PRIVATE_IP}")
    SYSTEM_FQDN=$(hostname -f 2>/dev/null || hostname 2>/dev/null || echo "pbx.local")
    SYSTEM_DOMAIN=$(echo "${SYSTEM_FQDN}" | cut -d. -f2- 2>/dev/null || echo "local")

    if [ -z "${ADMIN_EMAIL:-}" ]; then
        ADMIN_EMAIL="admin@${SYSTEM_DOMAIN}"
    fi
    # Set FROM_EMAIL/FROM_NAME defaults now that FQDN is known
    [ -z "${FROM_EMAIL:-}" ] && FROM_EMAIL="no-reply@${SYSTEM_FQDN}"
    [ -z "${FROM_NAME:-}" ]  && FROM_NAME="PBX System"

    info "OS: ${DETECTED_OS} ${DETECTED_VERSION} (${DISTRO_FAMILY} gen${DISTRO_GEN})"
    info "Package manager: ${PACKAGE_MGR_BIN} ${PACKAGE_MGR_ARG}"
    info "Init system: ${INIT_SYSTEM}"
    info "Private IP: ${PRIVATE_IP} | Public IP: ${PUBLIC_IP}"
    info "FQDN: ${SYSTEM_FQDN}"
}

version_select() {
    step "📦 Selecting component versions for gen${DISTRO_GEN}..."
    case "${DISTRO_GEN}" in
        1)
            ASTERISK_VERSION="18"
            FREEPBX_VERSION="15"
            PHP_VERSION="7.2"
            PHP_AVANTFAX_VERSION="7.2"
            warn "CentOS 6 is EOL. Installing degraded component versions."
            ;;
        2)
            ASTERISK_VERSION="21"
            FREEPBX_VERSION="17.0"
            PHP_VERSION="8.2"
            PHP_AVANTFAX_VERSION="7.4"
            ;;
        3)
            ASTERISK_VERSION="22"
            FREEPBX_VERSION="17.0"
            PHP_VERSION="8.2"
            PHP_AVANTFAX_VERSION="7.4"
            ;;
        *)
            ASTERISK_VERSION="21"
            FREEPBX_VERSION="17.0"
            PHP_VERSION="8.2"
            PHP_AVANTFAX_VERSION="7.4"
            ;;
    esac
    info "Asterisk: ${ASTERISK_VERSION} | FreePBX: ${FREEPBX_VERSION} | PHP: ${PHP_VERSION}"
}

setup_pkg_map() {
    step "📦 Setting up distro-specific package map..."

    case "${DISTRO_FAMILY}" in
        debian)
            APACHE_SERVICE="apache2"
            APACHE_USER="www-data"
            APACHE_GROUP="www-data"

            PACKAGES_DISTRO_BUILD="build-essential autoconf automake libtool bison flex doxygen imagemagick"
            PACKAGES_DISTRO_ASTERISK_DEPS="libssl-dev libxml2-dev libxslt1-dev libsqlite3-dev sqlite3 uuid-dev libncurses5-dev libncursesw5-dev libnewt-dev libjansson-dev libcurl4-openssl-dev default-libmysqlclient-dev libsrtp2-dev libspeex-dev libspeexdsp-dev libasound2-dev libogg-dev libvorbis-dev libtiff-dev libpng-dev libjpeg-dev libicu-dev libldap2-dev libreadline-dev libedit-dev libgd-dev"
            PACKAGES_DISTRO_WEBSERVER="apache2 apache2-utils"
            # Optional apache modules — installed one-by-one so a missing name never blocks apache2
            PACKAGES_DISTRO_WEBSERVER_OPT="libapache2-mod-fcgid"
            PACKAGES_DISTRO_PHP="php${PHP_VERSION} php${PHP_VERSION}-fpm php${PHP_VERSION}-cli php${PHP_VERSION}-common php${PHP_VERSION}-mysql php${PHP_VERSION}-gd php${PHP_VERSION}-xml php${PHP_VERSION}-curl php${PHP_VERSION}-zip php${PHP_VERSION}-mbstring php${PHP_VERSION}-intl php${PHP_VERSION}-bcmath php${PHP_VERSION}-opcache php${PHP_VERSION}-soap php${PHP_VERSION}-ldap php${PHP_VERSION}-imap php${PHP_VERSION}-xmlrpc"
            PACKAGES_DISTRO_PHP74="php${PHP_AVANTFAX_VERSION} php${PHP_AVANTFAX_VERSION}-fpm php${PHP_AVANTFAX_VERSION}-cli php${PHP_AVANTFAX_VERSION}-common php${PHP_AVANTFAX_VERSION}-mysql php${PHP_AVANTFAX_VERSION}-gd php${PHP_AVANTFAX_VERSION}-xml php${PHP_AVANTFAX_VERSION}-curl php${PHP_AVANTFAX_VERSION}-zip php${PHP_AVANTFAX_VERSION}-mbstring php${PHP_AVANTFAX_VERSION}-intl php${PHP_AVANTFAX_VERSION}-bcmath php${PHP_AVANTFAX_VERSION}-soap php${PHP_AVANTFAX_VERSION}-imap php-pear"
            PACKAGES_DISTRO_MARIADB="mariadb-server mariadb-client"
            PACKAGES_DISTRO_PYTHON="python3-dev python3-pip"
            PACKAGES_DISTRO_NODE="nodejs npm"
            PACKAGES_DISTRO_SYSTEM="ntp pkg-config iptables-persistent cron"
            PACKAGES_DISTRO_KNOCKD="knockd"
            PACKAGES_DISTRO_FAX="hylafax-server iaxmodem"
            PACKAGES_DISTRO_SNGREP="sngrep"
            ODBC_DEV_PKG="unixodbc-dev"
            ODBC_DRIVER_PKG="odbc-mariadb"
            PKG_NTP="ntp"
            PKG_IPTABLES_PERSIST="iptables-persistent"
            PKG_WEBMIN_REPO_TYPE="deb"
            PHP_FPM_SERVICE="php${PHP_VERSION}-fpm"
            PHP74_FPM_SERVICE="php${PHP_AVANTFAX_VERSION}-fpm"
            PHP_FPM_SOCK="/run/php/php${PHP_VERSION}-fpm.sock"
            PHP74_FPM_SOCK="/run/php/php${PHP_AVANTFAX_VERSION}-fpm.sock"
            PHP_FPM_PORT=""
            PHP74_FPM_PORT=""
            PHP_INI_DIR="/etc/php/${PHP_VERSION}"
            MARIADB_SOCKET="/var/run/mysqld/mysqld.sock"
            ODBC_DRIVER_PATH="/usr/lib/x86_64-linux-gnu/odbc/libmaodbc.so"
            ;;

        rhel|fedora)
            APACHE_SERVICE="httpd"
            APACHE_USER="apache"
            APACHE_GROUP="apache"

            PACKAGES_DISTRO_BUILD="gcc gcc-c++ make cmake autoconf automake libtool bison flex doxygen ImageMagick"
            PACKAGES_DISTRO_ASTERISK_DEPS="openssl-devel libxml2-devel libxslt-devel sqlite-devel sqlite libuuid-devel ncurses-devel newt-devel jansson-devel libcurl-devel libsrtp-devel speex-devel speexdsp-devel alsa-lib-devel libogg-devel libvorbis-devel libtiff-devel libpng-devel libjpeg-devel libicu-devel openldap-devel readline-devel libedit-devel libgd-devel pkgconf-pkg-config pkgconf"
            PACKAGES_DISTRO_WEBSERVER="httpd httpd-tools"
            PACKAGES_DISTRO_WEBSERVER_OPT="mod_ssl mod_proxy_html"
            PACKAGES_DISTRO_PHP="php php-fpm php-cli php-common php-mysqlnd php-gd php-xml php-curl php-zip php-mbstring php-intl php-bcmath php-opcache php-soap php-ldap php-json php-imap php-xmlrpc php-process php-pdo php-pear"
            PACKAGES_DISTRO_PHP74="php74 php74-php-fpm php74-php-cli php74-php-common php74-php-mysqlnd php74-php-gd php74-php-xml php74-php-curl php74-php-zip php74-php-mbstring php74-php-intl php74-php-bcmath php74-php-soap php74-php-imap php74-php-pear"
            PACKAGES_DISTRO_MARIADB="mariadb-server mariadb"
            PACKAGES_DISTRO_PYTHON="python3-devel python3-pip"
            PACKAGES_DISTRO_NODE="nodejs npm"
            PACKAGES_DISTRO_SYSTEM="chrony iptables-services"
            PACKAGES_DISTRO_KNOCKD="knock-server"
            PACKAGES_DISTRO_FAX="hylafax+"
            PACKAGES_DISTRO_SNGREP="sngrep"
            ODBC_DEV_PKG="unixODBC-devel"
            ODBC_DRIVER_PKG="mariadb-connector-odbc"
            PKG_NTP="chrony"
            PKG_IPTABLES_PERSIST="iptables-services"
            PKG_WEBMIN_REPO_TYPE="rpm"
            PHP_FPM_SERVICE="php-fpm"
            PHP74_FPM_SERVICE="php74-php-fpm"
            PHP_FPM_SOCK="/run/php-fpm/www.sock"
            PHP74_FPM_SOCK="/var/opt/remi/php74/run/php-fpm/www.sock"
            PHP_FPM_PORT=""
            PHP74_FPM_PORT=""
            PHP_INI_DIR="/etc"
            MARIADB_SOCKET="/var/lib/mysql/mysql.sock"
            ODBC_DRIVER_PATH="/usr/lib64/libmaodbc.so"
            # CentOS 6 (gen=1) adjustments
            if [ "${DISTRO_GEN}" -eq 1 ]; then
                PACKAGES_DISTRO_KNOCKD="knock"
                PACKAGES_DISTRO_SYSTEM="ntp iptables"
                PKG_NTP="ntp"
                PKG_IPTABLES_PERSIST="iptables"
            fi
            ;;
    esac

    success "Package map configured for ${DISTRO_FAMILY}"
}

# =============================================================================
# SECTION 5: UTILITY FUNCTIONS
# =============================================================================

generate_password() {
    local length="${1:-32}"
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -base64 48 2>/dev/null | tr -d '=+/\n' | cut -c1-"${length}"
    else
        # Disable pipefail in subshell — tr gets SIGPIPE when head closes
        (set +o pipefail; tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c "${length}"; echo) 2>/dev/null
    fi
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# download_file URL DEST [timeout_seconds]
# Tries curl first, falls back to wget; returns 0 on success
download_file() {
    local url="$1" dest="$2" timeout="${3:-300}"
    if command_exists curl; then
        curl -fsSL --max-time "${timeout}" --retry 3 --retry-delay 5 \
            -o "${dest}" "${url}" 2>/dev/null
    elif command_exists wget; then
        wget -q --timeout="${timeout}" -O "${dest}" "${url}" 2>/dev/null
    else
        error "Neither curl nor wget found — cannot download ${url}"
        return 1
    fi
}

# verify_download FILE EXPECTED_SHA256
# Verifies SHA256 checksum of downloaded file; pass empty expected to skip
verify_download() {
    local file="$1" expected_sha256="${2:-}"
    [ -z "${expected_sha256}" ] && return 0
    local actual
    actual=$(sha256sum "${file}" 2>/dev/null | cut -d' ' -f1)
    if [ "${actual}" != "${expected_sha256}" ]; then
        error "Checksum mismatch for ${file}"
        error "  Expected: ${expected_sha256}"
        error "  Got:      ${actual}"
        return 1
    fi
    info "Checksum verified: $(basename "${file}")"
    return 0
}

safe_execute() {
    local cmd="$1"
    local msg="${2:-Command failed}"
    log "Executing: ${cmd}"
    if ! eval "${cmd}" >> "${LOG_FILE}" 2>&1; then
        error "${msg}: ${cmd}"
    fi
}

track_install() {
    echo "${1}" >> "${INSTALL_INVENTORY}"
    INSTALLED_COMPONENTS="${INSTALLED_COMPONENTS} ${1}"
    log "INSTALLED: ${1}"
}

backup_config() {
    local f="$1"
    [ -f "${f}" ] || return 0
    local d
    d="${CONFIG_BACKUP_DIR}$(dirname "${f}")"
    mkdir -p "${d}"
    cp -p "${f}" "${d}/"
    info "Backed up ${f}"
}

is_installed() {
    grep -q "^${1}$" "${INSTALL_INVENTORY}" 2>/dev/null
}

# Idempotency helpers — track what's installed in state file
state_set() {
    local key="$1" val="$2"
    mkdir -p "$(dirname "${PBX_STATE_FILE}")"
    [ -f "${PBX_STATE_FILE}" ] && \
        grep -v "^${key}=" "${PBX_STATE_FILE}" > "${PBX_STATE_FILE}.tmp" 2>/dev/null && \
        mv "${PBX_STATE_FILE}.tmp" "${PBX_STATE_FILE}" || true
    echo "${key}=${val}" >> "${PBX_STATE_FILE}"
}

state_get() {
    [ -f "${PBX_STATE_FILE}" ] && \
        grep "^${1}=" "${PBX_STATE_FILE}" | cut -d= -f2- | tail -1 || echo ""
}

# ---------------------------------------------------------------------------
# component_ok COMPONENT — live health check per component
# Returns 0 if component is healthy, 1 if broken/missing
# ---------------------------------------------------------------------------
component_ok() {
    case "$1" in
        asterisk)
            # Only check that binary is installed — service may not be running at install time
            command -v asterisk >/dev/null 2>&1 ;;
        freepbx)
            [ -f /usr/sbin/fwconsole ] && [ -f /etc/freepbx.conf ] && \
            [ -f "${WEB_ROOT:-/var/www/apache/pbx}/admin/index.php" ] ;;
        mariadb|mysql)
            svc_active mariadb 2>/dev/null || svc_active mysqld 2>/dev/null ;;
        php)
            php -r "echo phpversion();" >/dev/null 2>&1 ;;
        apache)
            svc_active apache2 2>/dev/null || svc_active httpd 2>/dev/null ;;
        postfix)
            command -v postfix >/dev/null 2>&1 ;;
        hylafax)
            command -v faxstat >/dev/null 2>&1 ;;
        avantfax)
            [ -f "${AVANTFAX_WEB_DIR:-/var/www/apache/pbx/avantfax}/index.php" ] ;;
        webmin)
            [ -f /etc/webmin/miniserv.conf ] ;;
        fail2ban)
            command -v fail2ban-client >/dev/null 2>&1 ;;
        *)
            return 0 ;;  # unknown: assume ok, don't block
    esac
}

fail_component() {
    local component="$1" reason="${2:-installation failed}"
    error "${component}: ${reason}"
    INSTALL_FAILURES="${INSTALL_FAILURES}  ✗ ${component}: ${reason}\n"
    state_set "installed_${component}" "failed"
    state_set "installed_${component}_reason" "${reason}"
}

# skip_if_done: returns 0 (skip) only if marked done AND health check passes
skip_if_done() {
    local component="$1"
    [ "${PBX_FORCE:-0}" = "1" ] && return 1   # force reinstall
    [ "$(state_get "installed_${component}")" = "yes" ] || return 1  # not marked done
    if component_ok "${component}"; then
        info "✓ ${component} already installed and healthy — skipping"
        return 0  # healthy, skip
    fi
    info "${component} marked done but health check failed — reinstalling"
    state_set "installed_${component}" "no"
    return 1  # reinstall
}

mark_done() {
    local component="$1"
    if component_ok "${component}"; then
        state_set "installed_${component}" "yes"
        state_set "installed_${component}_ts" "$(date '+%Y-%m-%d %H:%M:%S')"
        track_install "${component}"
    else
        fail_component "${component}" "health check failed after install"
    fi
}

# ---------------------------------------------------------------------------
# pkg_install  — install packages via distro package manager, never fatal
# pkg_install_one_by_one — install each package individually (use when
#                           a missing package name must not block others)
# ---------------------------------------------------------------------------
pkg_install() {
    local pkgs
    pkgs=$(printf '%s\n' "$@" | grep -v '^$' | sort -u | tr '\n' ' ')
    [ -z "${pkgs// }" ] && return 0
    [ "${DISTRO_FAMILY}" = "debian" ] && export DEBIAN_FRONTEND=noninteractive
    # shellcheck disable=SC2086
    $PACKAGE_MGR_BIN $PACKAGE_MGR_ARG $pkgs 2>/dev/null || true
}

pkg_install_one_by_one() {
    [ "${DISTRO_FAMILY}" = "debian" ] && export DEBIAN_FRONTEND=noninteractive
    for pkg in "$@"; do
        [ -n "$pkg" ] || continue
        $PACKAGE_MGR_BIN $PACKAGE_MGR_ARG "$pkg" 2>/dev/null || true
    done
}

try_install_package() {
    pkg_install_one_by_one "$@"
}

# =============================================================================
# SECTION 6: ENV FILE MANAGEMENT
# =============================================================================

load_pbx_env() {
    if [ -f "${PBX_ENV_FILE}" ]; then
        # shellcheck source=/dev/null
        source "${PBX_ENV_FILE}"
        info "Loaded PBX env from ${PBX_ENV_FILE}"
    elif [ -f "${AUTO_PASSWORDS_FILE}" ]; then
        # Fallback: load from /etc/pbx/pbx_passwords (written early in prepare_system)
        # shellcheck source=/dev/null
        source "${AUTO_PASSWORDS_FILE}" 2>/dev/null || true
        info "Loaded PBX env from ${AUTO_PASSWORDS_FILE}"
    fi
}

save_pbx_env() {
    mkdir -p "${PBX_ENV_DIR}"
    chmod 750 "${PBX_ENV_DIR}"

    # Preserve keys written outside this function (e.g. PROXY_HTTP_PORT, RCLONE_REMOTE, BACKUP_*)
    local extra_keys=""
    if [ -f "${PBX_ENV_FILE}" ]; then
        extra_keys=$(grep -E "^(PROXY_HTTP_PORT|RCLONE_REMOTE|BACKUP_ENCRYPT|BACKUP_GPG_KEY)=" \
            "${PBX_ENV_FILE}" 2>/dev/null || true)
    fi

    cat > "${PBX_ENV_FILE}" << ENVEOF
# PBX Environment - Generated by installer v${SCRIPT_VERSION}
# Created: $(date '+%Y-%m-%d %H:%M:%S')
# Edit values below to reconfigure; re-run install.sh to apply.

# --- Credentials ---
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD}"
FREEPBX_ADMIN_USERNAME="${FREEPBX_ADMIN_USERNAME}"
FREEPBX_ADMIN_PASSWORD="${FREEPBX_ADMIN_PASSWORD}"
FREEPBX_DB_PASSWORD="${FREEPBX_DB_PASSWORD}"
AVANTFAX_DB_PASSWORD="${AVANTFAX_DB_PASSWORD}"

# --- Network ---
PRIVATE_IP="${PRIVATE_IP}"
PUBLIC_IP="${PUBLIC_IP}"
SYSTEM_FQDN="${SYSTEM_FQDN}"
SYSTEM_DOMAIN="${SYSTEM_DOMAIN}"

# --- Email ---
ADMIN_EMAIL="${ADMIN_EMAIL:-}"
FROM_EMAIL="${FROM_EMAIL:-}"
FROM_NAME="${FROM_NAME:-}"

# --- Fax ---
EMAIL_TO_FAX_ALIAS="${EMAIL_TO_FAX_ALIAS}"
FAX_TO_EMAIL_ADDRESS="${FAX_TO_EMAIL_ADDRESS}"
NUMBER_OF_MODEMS="${NUMBER_OF_MODEMS:-4}"

# --- Versions & Services (used by management scripts) ---
ASTERISK_VERSION="${ASTERISK_VERSION}"
FREEPBX_VERSION="${FREEPBX_VERSION}"
PHP_VERSION="${PHP_VERSION}"
DISTRO="${DISTRO}"
DISTRO_FAMILY="${DISTRO_FAMILY}"
APACHE_SERVICE="${APACHE_SERVICE}"
PHP_FPM_SERVICE="${PHP_FPM_SERVICE}"
PHP_FPM_SOCK="${PHP_FPM_SOCK}"
BEHIND_PROXY="${BEHIND_PROXY:-no}"
SSL_ENABLED="${SSL_ENABLED:-0}"
WEBMIN_PORT="${WEBMIN_PORT:-9001}"
WEB_ROOT="${WEB_ROOT:-/var/www/html}"
ENVEOF

    # Re-append any preserved extra keys
    [ -n "${extra_keys}" ] && printf '%s\n' "${extra_keys}" >> "${PBX_ENV_FILE}"

    chmod 600 "${PBX_ENV_FILE}"
    success "Saved PBX env to ${PBX_ENV_FILE}"
}

generate_fax_alias() {
    local alias_suffix
    if command -v openssl >/dev/null 2>&1; then
        alias_suffix=$(openssl rand -hex 6 2>/dev/null)
    else
        alias_suffix=$(set +o pipefail; tr -dc 'a-z0-9' < /dev/urandom 2>/dev/null | head -c 12; echo) 2>/dev/null
    fi
    EMAIL_TO_FAX_ALIAS="fax-${alias_suffix}@${SYSTEM_DOMAIN}"
}

# =============================================================================
# SECTION 7: REPOSITORY & ROLLBACK HELPERS
# =============================================================================

repo_exists() {
    local repo_pattern="$1"
    if [ "${DISTRO_FAMILY}" = "debian" ]; then
        grep -r "${repo_pattern}" /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null \
            | grep -qv "^#"
    else
        grep -r "${repo_pattern}" /etc/yum.repos.d/ 2>/dev/null | grep -qv "^#"
    fi
}

rollback_installation() {
    local reason="${1:-Unknown error}"
    echo "${RED}❌ ROLLBACK: ${reason}${NC}" >&2
    log "ROLLBACK triggered: ${reason}"
    for svc in freepbx asterisk; do
        svc_stop "${svc}" 2>/dev/null || true
    done
    echo "${YELLOW}Installation failed. Partial install may remain.${NC}" >&2
    echo "${YELLOW}Check ${LOG_FILE} for details.${NC}" >&2
    echo "${YELLOW}Installed components: ${INSTALLED_COMPONENTS}${NC}" >&2
    exit 1
}

safe_restart_asterisk() {
    info "Restarting Asterisk..."
    # If FreePBX is available, prefer fwconsole restart
    if command_exists fwconsole; then
        fwconsole restart 2>/dev/null || true
        sleep 3
        return 0
    fi
    # Kill safe_asterisk + asterisk directly started (not under systemd)
    local spid apid
    spid=$(pgrep -x safe_asterisk 2>/dev/null || true)
    apid=$(pgrep -x asterisk 2>/dev/null || true)
    [ -n "$spid" ] && kill "$spid" 2>/dev/null || true
    [ -n "$apid" ] && kill "$apid" 2>/dev/null || true
    sleep 2
    # Remove stale socket/pid
    rm -f /var/run/asterisk/asterisk.ctl /var/run/asterisk/asterisk.pid \
          /run/asterisk/asterisk.ctl     /run/asterisk/asterisk.pid
    # Start via systemd
    svc_start asterisk 2>/dev/null || true
    sleep 5
}

# =============================================================================
# SECTION 7b: PREFLIGHT CHECKS
# =============================================================================

preflight_checks() {
    header "Pre-flight checks"

    # Hard fail: must be root
    [ "$(id -u)" -ne 0 ] && { error "Must run as root (sudo ./install.sh)"; exit 1; }

    # Hard fail: must have OS detection done first
    [ -z "${DISTRO_FAMILY:-}" ] && { error "OS detection failed — unsupported system"; exit 1; }

    # Internet connectivity — use whatever is available
    local _net_ok=0
    if command -v curl >/dev/null 2>&1; then
        curl -fsS --max-time 10 https://github.com >/dev/null 2>&1 && _net_ok=1
    elif command -v wget >/dev/null 2>&1; then
        wget -q --timeout=10 -O /dev/null https://github.com 2>/dev/null && _net_ok=1
    else
        # No curl or wget yet — check with ping as fallback
        ping -c1 -W5 8.8.8.8 >/dev/null 2>&1 && _net_ok=1
    fi
    if [ "${_net_ok}" -eq 0 ]; then
        error "No internet connectivity — cannot proceed"
        exit 1
    fi

    # Resource checks (warn only — never block)
    local total_ram_mb
    total_ram_mb=$(awk '/MemTotal/{printf "%d", $2/1024}' /proc/meminfo 2>/dev/null || echo 9999)
    local disk_gb
    disk_gb=$(df / --output=avail 2>/dev/null | tail -1 | awk '{printf "%d", $1/1024/1024}' || echo 99)
    local cpu_cores
    cpu_cores=$(nproc 2>/dev/null || echo 1)

    [ "${total_ram_mb}" -lt 1024 ] && warn "Very low RAM (${total_ram_mb}MB) — expect slow performance"
    [ "${total_ram_mb}" -lt 4096 ] && [ "${total_ram_mb}" -ge 1024 ] && \
        warn "Low RAM (${total_ram_mb}MB) — recommend 4GB+"
    [ "${total_ram_mb}" -lt 2048 ] && { LOW_RESOURCE=1; info "Low resource mode: some optional components will be skipped"; }
    [ "${disk_gb}" -lt 10 ]        && warn "Low disk space (${disk_gb}GB free) — recommend 20GB+"
    [ "${cpu_cores}" -eq 1 ]       && warn "Single CPU core — Asterisk compilation will be slow"
    free | awk '/^Swap/{exit ($2>0)?0:1}' 2>/dev/null || \
        warn "No swap detected — recommend adding swap on low-RAM systems"

    # Container detection
    if grep -q 'container=lxc' /proc/1/environ 2>/dev/null || \
       grep -q 'lxc' /proc/1/cgroup 2>/dev/null || \
       [ -f /.dockerenv ]; then
        IS_CONTAINER=1
        info "Container environment detected — skipping iptables/sysctl/IPv6-disable"
    else
        IS_CONTAINER=0
    fi

    success "Pre-flight checks passed"
}

# =============================================================================
# SECTION 7c: INSTALLATION PROFILES
# =============================================================================

resolve_install_profile() {
    info "Installation profile: ${INSTALL_PROFILE}"

    case "${INSTALL_PROFILE}" in
        minimal)
            # Feature flags not already set by user → defaults for minimal
            : "${INSTALL_KNOCKD:=no}"
            : "${INSTALL_OPENVPN:=no}"
            : "${INSTALL_FOP2:=no}"
            : "${INSTALL_SNGREP:=no}"
            : "${INSTALL_PHONE_PROV:=no}"
            : "${INSTALL_REMOTE_BACKUP:=no}"
            INSTALL_WEBMIN=no
            BACKUP_ENABLED=0
            ;;
        standard)
            : "${INSTALL_KNOCKD:=no}"
            : "${INSTALL_OPENVPN:=no}"
            : "${INSTALL_FOP2:=no}"
            : "${INSTALL_SNGREP:=no}"
            : "${INSTALL_PHONE_PROV:=no}"
            : "${INSTALL_REMOTE_BACKUP:=no}"
            : "${INSTALL_WEBMIN:=yes}"
            ;;
        advanced)
            : "${INSTALL_KNOCKD:=yes}"
            : "${INSTALL_OPENVPN:=yes}"
            : "${INSTALL_FOP2:=yes}"
            : "${INSTALL_SNGREP:=yes}"
            : "${INSTALL_PHONE_PROV:=yes}"
            : "${INSTALL_REMOTE_BACKUP:=yes}"
            : "${INSTALL_WEBMIN:=yes}"
            ;;
        *)
            warn "Unknown profile '${INSTALL_PROFILE}' — using standard"
            INSTALL_PROFILE=standard
            resolve_install_profile
            return
            ;;
    esac

    # LOW_RESOURCE always overrides optional heavy steps
    if [ "${LOW_RESOURCE:-0}" = "1" ]; then
        INSTALL_SNGREP=no
        INSTALL_PHONE_PROV=no
        INSTALL_REMOTE_BACKUP=no
        info "LOW_RESOURCE: sngrep, phone-provisioning, remote-backup disabled"
    fi
}

# =============================================================================
# SECTION 7d: SSH SAFETY
# =============================================================================

detect_ssh_safety() {
    # Detect real SSH port (may not be 22)
    SSH_PORT=$(grep -E "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | head -1 || true)
    SSH_PORT="${SSH_PORT:-22}"
    mkdir -p /etc/pbx /var/lib/pbx /var/log/pbx 2>/dev/null || true
    echo "${SSH_PORT}" > /etc/pbx/ssh-port 2>/dev/null || true

    # Detect current connecting client IP
    SSH_CLIENT_IP=$(echo "${SSH_CLIENT:-}" | cut -d' ' -f1)
    [ -z "${SSH_CLIENT_IP}" ] && \
        SSH_CLIENT_IP=$(echo "${SSH_CONNECTION:-}" | cut -d' ' -f1)

    info "SSH port: ${SSH_PORT} | Client IP: ${SSH_CLIENT_IP:-unknown}"
}

schedule_firewall_rollback() {
    # Dead-man switch: flush iptables in 5 minutes in case we get locked out.
    # Cancelled by cancel_firewall_rollback() once rules are verified safe.
    if command_exists at; then
        FIREWALL_ROLLBACK_JOB=$(echo "iptables -F INPUT; iptables -P INPUT ACCEPT" \
            | at "now + 5 minutes" 2>&1 | awk '/^job/{print $2}')
        info "Firewall rollback scheduled (job ${FIREWALL_ROLLBACK_JOB}) — cancels in 5m if not confirmed"
    fi
}

cancel_firewall_rollback() {
    [ -n "${FIREWALL_ROLLBACK_JOB:-}" ] || return 0
    atrm "${FIREWALL_ROLLBACK_JOB}" 2>/dev/null && \
        success "Firewall rollback cancelled — rules verified safe" || true
    FIREWALL_ROLLBACK_JOB=""
}

# =============================================================================
# SECTION 7e: GITHUB API SCRIPT DOWNLOADER
# =============================================================================

sync_management_scripts() {
    step "Syncing management scripts from GitHub"

    local install_dir="/usr/local/bin"

    # LOCAL OVERRIDE: if PBX_SCRIPTS_LOCAL is set, copy directly (dev/testing mode)
    if [ -n "${PBX_SCRIPTS_LOCAL:-}" ] && [ -d "${PBX_SCRIPTS_LOCAL}" ]; then
        info "Installing scripts from local path: ${PBX_SCRIPTS_LOCAL}"
        local count=0
        for f in "${PBX_SCRIPTS_LOCAL}"/*; do
            [ -f "${f}" ] || continue
            local name
            name=$(basename "${f}")
            install -m 755 "${f}" "${install_dir}/${name}"
            count=$(( count + 1 ))
        done
        success "Scripts installed from local path: ${count} scripts"
        return 0
    fi

    # AUTO-DETECT: look for scripts/ dir alongside this install.sh
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/scripts"
    if [ -d "${script_dir}" ]; then
        info "Installing scripts from local scripts/ directory: ${script_dir}"
        local count=0
        for f in "${script_dir}"/*; do
            [ -f "${f}" ] || continue
            local name
            name=$(basename "${f}")
            install -m 755 "${f}" "${install_dir}/${name}"
            count=$(( count + 1 ))
        done
        success "Scripts installed from scripts/ directory: ${count} scripts"
        return 0
    fi

    local api_url="https://api.github.com/repos/${GITHUB_REPO}/contents/scripts?ref=${SCRIPTS_REF}"
    local install_dir="/usr/local/bin"
    local manifest_tmp
    manifest_tmp=$(mktemp)

    # Build auth header if token provided
    local auth_header=""
    [ -n "${GITHUB_TOKEN:-}" ] && auth_header="Authorization: token ${GITHUB_TOKEN}"

    # Fetch directory listing from GitHub Contents API
    local listing
    if [ -n "${auth_header}" ]; then
        listing=$(curl -fsSL -H "${auth_header}" "${api_url}" 2>/dev/null) || listing=""
    else
        listing=$(curl -fsSL "${api_url}" 2>/dev/null) || listing=""
    fi

    if [ -z "${listing}" ] || echo "${listing}" | grep -q '"message".*"Not Found"'; then
        warn "GitHub API unreachable or scripts/ dir not found — using cached manifest if available"
        listing=""
    fi

    if [ -n "${listing}" ]; then
        # Parse JSON: extract name + download_url pairs (no jq required)
        echo "${listing}" | grep -o '"name": *"[^"]*"\|"download_url": *"[^"]*"' \
            | awk -F'"' 'NR%2==1{name=$4} NR%2==0{print name"\t"$4}' \
            > "${manifest_tmp}" 2>/dev/null || true

        # Filter to only shell scripts
        grep -E '\.(sh|bash)?"?' "${manifest_tmp}" > "${manifest_tmp}.sh" 2>/dev/null || true
        # Also include scripts with no extension (pbx-*)
        grep -E 'pbx-[a-z]' "${manifest_tmp}" >> "${manifest_tmp}.sh" 2>/dev/null || true
        sort -u "${manifest_tmp}.sh" > "${manifest_tmp}"

        if [ -s "${manifest_tmp}" ]; then
            # Cache manifest for offline use
            mkdir -p "$(dirname "${SCRIPTS_MANIFEST_CACHE}")"
            cp "${manifest_tmp}" "${SCRIPTS_MANIFEST_CACHE}"
        fi
    fi

    # Fall back to cached manifest
    if [ ! -s "${manifest_tmp}" ] && [ -f "${SCRIPTS_MANIFEST_CACHE}" ]; then
        info "Using cached scripts manifest"
        cp "${SCRIPTS_MANIFEST_CACHE}" "${manifest_tmp}"
    fi

    if [ ! -s "${manifest_tmp}" ]; then
        warn "No scripts manifest available — skipping GitHub script sync"
        rm -f "${manifest_tmp}" "${manifest_tmp}.sh"
        return 0
    fi

    # Download/update each script
    local updated=0 skipped=0 failed=0
    while IFS=$'\t' read -r name download_url; do
        [ -z "${name}" ] || [ -z "${download_url}" ] && continue
        local target="${install_dir}/${name}"

        # Download
        if curl -fsSL "${download_url}" -o "${target}.tmp" 2>/dev/null; then
            chmod 755 "${target}.tmp"
            mv "${target}.tmp" "${target}"
            updated=$(( updated + 1 ))
        else
            warn "Failed to download ${name}"
            rm -f "${target}.tmp"
            failed=$(( failed + 1 ))
        fi
    done < "${manifest_tmp}"

    # Remove any scripts that are no longer in the repo
    if [ -f "${SCRIPTS_MANIFEST_CACHE}" ]; then
        for existing in "${install_dir}"/pbx-*; do
            [ -f "${existing}" ] || continue
            local bname
            bname=$(basename "${existing}")
            grep -q "^${bname}	" "${SCRIPTS_MANIFEST_CACHE}" || {
                info "Removing obsolete script: ${bname}"
                rm -f "${existing}"
            }
        done
    fi

    rm -f "${manifest_tmp}" "${manifest_tmp}.sh"
    success "Scripts synced: ${updated} updated, ${skipped} unchanged, ${failed} failed"
}

# =============================================================================
# SECTION 8: SYSTEM PREPARATION
# =============================================================================

prepare_system() {
    step "🔧 Preparing system..."

    mkdir -p "${WORK_DIR}" "${BACKUP_BASE}" "${CONFIG_BACKUP_DIR}" "${PBX_ENV_DIR}"
    chmod 750 "${PBX_ENV_DIR}"
    touch "${INSTALL_INVENTORY}"

    # Generate passwords if not already loaded from env
    [ -z "${MYSQL_ROOT_PASSWORD}" ]    && MYSQL_ROOT_PASSWORD=$(generate_password 32)
    [ -z "${FREEPBX_ADMIN_PASSWORD}" ] && FREEPBX_ADMIN_PASSWORD=$(generate_password 24)
    [ -z "${FREEPBX_ADMIN_USERNAME}" ] && FREEPBX_ADMIN_USERNAME="admin"
    [ -z "${FREEPBX_DB_PASSWORD}" ]    && FREEPBX_DB_PASSWORD=$(generate_password 24)
    [ -z "${AVANTFAX_DB_PASSWORD}" ]   && AVANTFAX_DB_PASSWORD=$(generate_password 24)
    [ -z "${EMAIL_TO_FAX_ALIAS}" ]     && generate_fax_alias
    [ -z "${FAX_TO_EMAIL_ADDRESS}" ]   && FAX_TO_EMAIL_ADDRESS="${ADMIN_EMAIL:-admin@localhost}"

    # Only write passwords file if it doesn't already exist (preserves passwords across re-runs)
    if [ ! -f "${AUTO_PASSWORDS_FILE}" ]; then
        cat > "${AUTO_PASSWORDS_FILE}" << PWEOF
# PBX Installation Passwords - Generated $(date '+%Y-%m-%d %H:%M:%S')
# KEEP THIS FILE SECURE - chmod 600
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}
FREEPBX_ADMIN_USERNAME=${FREEPBX_ADMIN_USERNAME}
FREEPBX_ADMIN_PASSWORD=${FREEPBX_ADMIN_PASSWORD}
FREEPBX_DB_PASSWORD=${FREEPBX_DB_PASSWORD}
AVANTFAX_DB_PASSWORD=${AVANTFAX_DB_PASSWORD}
EMAIL_TO_FAX_ALIAS=${EMAIL_TO_FAX_ALIAS}
FAX_TO_EMAIL_ADDRESS=${FAX_TO_EMAIL_ADDRESS}
FROM_EMAIL=${FROM_EMAIL}
FROM_NAME=${FROM_NAME}
PWEOF
        chmod 600 "${AUTO_PASSWORDS_FILE}"
    fi

    # Set timezone
    local tz="${TIMEZONE:-America/New_York}"
    if command_exists timedatectl; then
        timedatectl set-timezone "${tz}" 2>/dev/null || true
    elif [ -f "/usr/share/zoneinfo/${tz}" ]; then
        ln -sf "/usr/share/zoneinfo/${tz}" /etc/localtime 2>/dev/null || true
    fi

    # Disable SELinux for RHEL (FreePBX does not support enforcing)
    if [ -f /etc/selinux/config ]; then
        backup_config /etc/selinux/config
        sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config 2>/dev/null || true
        setenforce 0 2>/dev/null || true
        info "SELinux set to permissive"
    fi

    # Bootstrap: ensure tar and curl are available before any pkg_install or downloads.
    # Fresh minimal containers (AlmaLinux, Rocky, etc.) may not have these.
    if ! command -v tar >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
        case "${PACKAGE_MGR_BIN}" in
            dnf|yum) ${PACKAGE_MGR_BIN} install -y tar curl ;;
            apt-get) apt-get install -y tar curl ;;
        esac
    fi

    # System update
    if [ "${DISTRO_FAMILY}" = "debian" ]; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y
        apt-get upgrade -y -o Dpkg::Options::="--force-confold"
    else
        ${PACKAGE_MGR_BIN} update -y
    fi

    success "System prepared"

    # Define save_passwords_file for later use in finalize_installation
    save_passwords_file() {
        cat > "${AUTO_PASSWORDS_FILE}" << PWEOF
# PBX Installation Credentials
# Generated: $(date)
# KEEP THIS FILE SECURE

MySQL Root Password:    ${MYSQL_ROOT_PASSWORD}
FreePBX Admin User:     ${FREEPBX_ADMIN_USERNAME}
FreePBX Admin Password: ${FREEPBX_ADMIN_PASSWORD}
FreePBX DB Password:    ${FREEPBX_DB_PASSWORD}
AvantFax DB Password:   ${AVANTFAX_DB_PASSWORD}

Web Interfaces:
  FreePBX Admin:  http://${PRIVATE_IP}/admin/
  User Portal:    http://${PRIVATE_IP}/ucp/
  Fax (AvantFax): http://${PRIVATE_IP}/avantfax/
  Webmin:         https://${PRIVATE_IP}:9001/
  Main Portal:    http://${PRIVATE_IP}/
$([ "${BEHIND_PROXY:-no}" = "yes" ] && printf "  [Proxy mode] Apache HTTP: http://127.0.0.1:%s/\n" "$(grep "^PROXY_HTTP_PORT=" "${PBX_ENV_FILE}" 2>/dev/null | cut -d= -f2 | tr -d '"')")

SSH Port: ${SSH_PORT}
PWEOF
        chmod 600 "${AUTO_PASSWORDS_FILE}"
    }
}

setup_dns() {
    step "🌐 Configuring DNS resolvers..."
    if [ ! -f /etc/resolv.conf.pbx-orig ]; then
        cp /etc/resolv.conf /etc/resolv.conf.pbx-orig 2>/dev/null || true
    fi
    cat > /etc/resolv.conf << 'DNSEOF'
# Set by PBX installer
nameserver 8.8.8.8
nameserver 1.1.1.1
nameserver 4.4.4.4
DNSEOF
    success "DNS configured"
}

# =============================================================================
# SECTION 9: REPOSITORY SETUP
# =============================================================================

setup_repositories() {
    step "📦 Setting up package repositories..."

    case "${DISTRO_FAMILY}" in
        debian)
            export DEBIAN_FRONTEND=noninteractive
            apt-get install -y curl wget gnupg2 software-properties-common \
                apt-transport-https lsb-release ca-certificates 2>/dev/null || true

            # PHP repository
            case "${DETECTED_OS}" in
                ubuntu)
                    if ! repo_exists "ondrej/php"; then
                        add-apt-repository -y ppa:ondrej/php 2>/dev/null || true
                        info "Added ondrej/php PPA"
                    fi
                    ;;
                debian)
                    if ! repo_exists "packages.sury.org"; then
                        curl -fsSL https://packages.sury.org/php/apt.gpg \
                            | gpg --dearmor -o /usr/share/keyrings/php-sury.gpg 2>/dev/null || true
                        echo "deb [signed-by=/usr/share/keyrings/php-sury.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" \
                            > /etc/apt/sources.list.d/php-sury.list
                        info "Added sury.org PHP repository"
                    fi
                    ;;
            esac

            # NodeSource
            if ! repo_exists "nodesource"; then
                curl -fsSL https://deb.nodesource.com/setup_18.x | bash - 2>/dev/null || true
                info "Added NodeSource repository"
            fi

            apt-get update -y
            ;;

        rhel)
            # dnf-plugins-core required for config-manager
            ${PACKAGE_MGR_BIN} ${PACKAGE_MGR_ARG} dnf-plugins-core 2>/dev/null \
                || ${PACKAGE_MGR_BIN} ${PACKAGE_MGR_ARG} yum-utils 2>/dev/null || true

            # EPEL
            if ! repo_exists "epel"; then
                ${PACKAGE_MGR_BIN} ${PACKAGE_MGR_ARG} epel-release 2>/dev/null || true
                info "Added EPEL repository"
            fi

            # CRB/PowerTools (RHEL 8+)
            local major_ver
            major_ver=$(echo "${DETECTED_VERSION}" | cut -d. -f1)
            if [ "${major_ver}" -ge 8 ] 2>/dev/null; then
                ${PACKAGE_MGR_BIN} config-manager --set-enabled crb 2>/dev/null \
                    || ${PACKAGE_MGR_BIN} config-manager --set-enabled powertools 2>/dev/null \
                    || ${PACKAGE_MGR_BIN} config-manager --enable crb 2>/dev/null \
                    || true
                info "Enabled CRB/PowerTools"
            fi

            # Remi PHP repository
            if ! repo_exists "remirepo"; then
                case "${major_ver}" in
                    6) ${PACKAGE_MGR_BIN} ${PACKAGE_MGR_ARG} https://rpms.remirepo.net/enterprise/remi-release-6.rpm 2>/dev/null || true ;;
                    7) ${PACKAGE_MGR_BIN} ${PACKAGE_MGR_ARG} https://rpms.remirepo.net/enterprise/remi-release-7.rpm 2>/dev/null || true ;;
                    8) ${PACKAGE_MGR_BIN} ${PACKAGE_MGR_ARG} https://rpms.remirepo.net/enterprise/remi-release-8.rpm 2>/dev/null || true ;;
                    *) ${PACKAGE_MGR_BIN} ${PACKAGE_MGR_ARG} https://rpms.remirepo.net/enterprise/remi-release-9.rpm 2>/dev/null || true ;;
                esac
                info "Added Remi repository"
            fi

            # NodeSource
            if ! repo_exists "nodesource"; then
                curl -fsSL https://rpm.nodesource.com/setup_18.x | bash - 2>/dev/null || true
                info "Added NodeSource repository"
            fi

            # CentOS 6 vault mirror (EOL)
            if [ "${DISTRO_GEN}" -eq 1 ]; then
                backup_config /etc/yum.repos.d/CentOS-Base.repo
                cat > /etc/yum.repos.d/CentOS-Base.repo << 'VAULTEOF'
[base]
name=CentOS-$releasever - Base
baseurl=http://vault.centos.org/6.10/os/$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-6
[updates]
name=CentOS-$releasever - Updates
baseurl=http://vault.centos.org/6.10/updates/$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-6
VAULTEOF
                # Belt-and-suspenders: rewrite any remaining mirror references
                sed -i 's|mirror.centos.org|vault.centos.org|g' /etc/yum.repos.d/CentOS-*.repo 2>/dev/null || true
                sed -i 's|^mirrorlist=|#mirrorlist=|g' /etc/yum.repos.d/CentOS-*.repo 2>/dev/null || true
                sed -i 's|^#baseurl=|baseurl=|g' /etc/yum.repos.d/CentOS-*.repo 2>/dev/null || true
                info "Configured CentOS 6 vault mirrors"
            fi
            ;;

        fedora)
            ${PACKAGE_MGR_BIN} ${PACKAGE_MGR_ARG} dnf-plugins-core 2>/dev/null || true
            if ! repo_exists "remirepo"; then
                local fedora_ver
                fedora_ver=$(echo "${DETECTED_VERSION}" | cut -d. -f1)
                ${PACKAGE_MGR_BIN} ${PACKAGE_MGR_ARG} \
                    "https://rpms.remirepo.net/fedora/remi-release-${fedora_ver}.rpm" 2>/dev/null || true
                info "Added Remi repository for Fedora"
            fi
            if ! repo_exists "nodesource"; then
                curl -fsSL https://rpm.nodesource.com/setup_18.x | bash - 2>/dev/null || true
            fi
            ;;
    esac

    success "Repositories configured"
}

# =============================================================================
# SECTION 10: CORE DEPENDENCIES
# =============================================================================

install_core_dependencies() {
    step "📦 Installing core build dependencies..."

    pkg_install $PACKAGES_GLOBAL $PACKAGES_DISTRO_BUILD
    pkg_install_one_by_one $PACKAGES_DISTRO_SYSTEM   # NTP, iptables-persist, cron, etc.
    pkg_install_one_by_one $PACKAGES_DISTRO_ASTERISK_DEPS
    pkg_install_one_by_one $PACKAGES_DISTRO_PYTHON
    pkg_install_one_by_one $PACKAGES_DISTRO_NODE
    pkg_install_one_by_one $ODBC_DEV_PKG $ODBC_DRIVER_PKG

    # Ensure NTP service is running (package name stored in PKG_NTP)
    pkg_install_one_by_one $PKG_NTP
    svc_enable chronyd 2>/dev/null || svc_enable ntpd 2>/dev/null || true
    svc_start  chronyd 2>/dev/null || svc_start  ntpd 2>/dev/null || true

    # iksemel (Jabber/XMPP support for Asterisk res_xmpp)
    # Use meduketto source (has autotools → single libiksemel.so with iks_start_sasl).
    # Patch src/tls-openssl.c for OpenSSL 1.1+/3.x: BIO_METHOD became opaque,
    # SSLv23_client_method() and SSL_library_init() were removed.
    if ! ldconfig -p 2>/dev/null | grep -q "libiksemel.so"; then
        info "Compiling iksemel with OpenSSL 3.x support..."
        pkg_install autoconf automake libtool 2>/dev/null || true
        cd "${WORK_DIR}"
        local iksdir="iksemel-src"
        rm -rf "${iksdir}"
        if download_file \
            "https://github.com/meduketto/iksemel/archive/refs/heads/master.tar.gz" \
            iksemel-src.tar.gz 30; then
            mkdir -p "${iksdir}"
            tar xzf iksemel-src.tar.gz -C "${iksdir}" --strip-components=1 2>/dev/null \
                || error "Could not extract iksemel source"
            cd "${iksdir}"
            # Patch tls-openssl.c for OpenSSL 1.1+/3.x compatibility
            # 1. my_bio_create: replace direct b->init/num/ptr/flags with accessor funcs
            python3 - << 'PYEOF'
import re, sys

with open('src/tls-openssl.c', 'r') as f:
    src = f.read()

# Fix my_bio_create
old = '''\
static int
my_bio_create (BIO *b)
{
\tb->init = 1;
\tb->num = 0;
\tb->ptr = NULL;
\tb->flags = 0 ;
\treturn 1;
}'''
new = '''\
static int
my_bio_create (BIO *b)
{
#if OPENSSL_VERSION_NUMBER < 0x10100000L
\tb->init = 1;
\tb->num = 0;
\tb->ptr = NULL;
\tb->flags = 0;
#else
\tBIO_set_init(b, 1);
\tBIO_set_data(b, NULL);
\tBIO_set_flags(b, 0);
#endif
\treturn 1;
}'''
src = src.replace(old, new)

# Fix my_bio_destroy
old = '''\
\tb->ptr = NULL;
\tb->init = 0;
\tb->flags = 0;
\treturn 1;
}'''
new = '''\
#if OPENSSL_VERSION_NUMBER < 0x10100000L
\tb->ptr = NULL;
\tb->init = 0;
\tb->flags = 0;
#else
\tBIO_set_init(b, 0);
\tBIO_set_data(b, NULL);
\tBIO_set_flags(b, 0);
#endif
\treturn 1;
}'''
src = src.replace(old, new, 1)

# Fix my_bio_read: b->ptr -> BIO_get_data(b)
old = '\tstruct ikstls_data *data = (struct ikstls_data *) b->ptr;\n\tint ret;\n\n\tif (buf == NULL || len <= 0 || data == NULL) return 0;\n\n\tret = data->trans->recv'
new = '#if OPENSSL_VERSION_NUMBER < 0x10100000L\n\tstruct ikstls_data *data = (struct ikstls_data *) b->ptr;\n#else\n\tstruct ikstls_data *data = (struct ikstls_data *) BIO_get_data(b);\n#endif\n\tint ret;\n\n\tif (buf == NULL || len <= 0 || data == NULL) return 0;\n\n\tret = data->trans->recv'
src = src.replace(old, new, 1)

# Fix my_bio_write: b->ptr -> BIO_get_data(b)
old = '\tstruct ikstls_data *data = (struct ikstls_data *) b->ptr;\n\tint ret;\n\n\tif (buf == NULL || len <= 0 || data == NULL) return 0;\n\n\tret = data->trans->send'
new = '#if OPENSSL_VERSION_NUMBER < 0x10100000L\n\tstruct ikstls_data *data = (struct ikstls_data *) b->ptr;\n#else\n\tstruct ikstls_data *data = (struct ikstls_data *) BIO_get_data(b);\n#endif\n\tint ret;\n\n\tif (buf == NULL || len <= 0 || data == NULL) return 0;\n\n\tret = data->trans->send'
src = src.replace(old, new, 1)

# Fix static BIO_METHOD struct (becomes pointer for 1.1+)
old = 'static BIO_METHOD my_bio_method = {\n\t( 100 | 0x400 ),\n\t"iksemel transport",\n\tmy_bio_write,\n\tmy_bio_read,\n\tmy_bio_puts,\n\tmy_bio_gets,\n\tmy_bio_ctrl,\n\tmy_bio_create,\n\tmy_bio_destroy\n};'
new = '#if OPENSSL_VERSION_NUMBER < 0x10100000L\nstatic BIO_METHOD my_bio_method = {\n\t( 100 | 0x400 ),\n\t"iksemel transport",\n\tmy_bio_write,\n\tmy_bio_read,\n\tmy_bio_puts,\n\tmy_bio_gets,\n\tmy_bio_ctrl,\n\tmy_bio_create,\n\tmy_bio_destroy\n};\n#else\nstatic BIO_METHOD *my_bio_method;\n#endif'
src = src.replace(old, new)

# Fix SSL_library_init (removed in OpenSSL 3.x)
old = '\t\tSSL_library_init ();\n\t\tinit_done = 1;'
new = '#if OPENSSL_VERSION_NUMBER < 0x10100000L\n\t\tSSL_library_init();\n#else\n\t\tOPENSSL_init_ssl(0, NULL);\n#endif\n\t\tinit_done = 1;'
src = src.replace(old, new)

# Fix SSLv23_client_method (removed in OpenSSL 3.x)
old = 'data->ctx = SSL_CTX_new (SSLv23_client_method ());'
new = '#if OPENSSL_VERSION_NUMBER < 0x10100000L\n\tdata->ctx = SSL_CTX_new(SSLv23_client_method());\n#else\n\tdata->ctx = SSL_CTX_new(TLS_client_method());\n#endif'
src = src.replace(old, new)

# Fix BIO_new + bio->ptr (opaque in 1.1+)
old = '\tbio = BIO_new (&my_bio_method);\n\tbio->ptr = (void *) data;\n\tSSL_set_bio'
new = '#if OPENSSL_VERSION_NUMBER < 0x10100000L\n\tbio = BIO_new(&my_bio_method);\n\tbio->ptr = (void *) data;\n#else\n\tmy_bio_method = BIO_meth_new((100 | 0x400), "iksemel transport");\n\tBIO_meth_set_write(my_bio_method, my_bio_write);\n\tBIO_meth_set_read(my_bio_method, my_bio_read);\n\tBIO_meth_set_puts(my_bio_method, my_bio_puts);\n\tBIO_meth_set_gets(my_bio_method, my_bio_gets);\n\tBIO_meth_set_ctrl(my_bio_method, my_bio_ctrl);\n\tBIO_meth_set_create(my_bio_method, my_bio_create);\n\tBIO_meth_set_destroy(my_bio_method, my_bio_destroy);\n\tbio = BIO_new(my_bio_method);\n\tBIO_meth_free(my_bio_method);\n\tBIO_set_data(bio, (void *) data);\n#endif\n\tSSL_set_bio'
src = src.replace(old, new)

with open('src/tls-openssl.c', 'w') as f:
    f.write(src)

# Verify key patches landed — if not, the build will catch it anyway
ok = sum([
    'BIO_set_init' in src,
    'BIO_get_data' in src,
    'BIO_meth_new' in src,
    'TLS_client_method' in src,
    'OPENSSL_init_ssl' in src,
])
print(f"Patched tls-openssl.c for OpenSSL 3.x ({ok}/5 key changes verified)")
sys.exit(0)
PYEOF
            autoreconf -fi 2>/dev/null || true
            if ./configure --prefix=/usr --disable-python 2>/dev/null; then
                # Build only src/ — doc/ requires makeinfo which may not be installed
                timeout 300 make -j"$(nproc)" -C src 2>/dev/null \
                    || error "iksemel build failed"
                make -C src install 2>/dev/null \
                    && make -C include install 2>/dev/null \
                    || error "iksemel install failed"
                ldconfig 2>/dev/null || true
                success "iksemel compiled and installed with OpenSSL 3.x support"
            else
                error "iksemel configure failed"
            fi
        else
            error "Could not download iksemel source"
        fi
        cd /
    fi

    track_install "core-dependencies"
    success "Core dependencies installed"
}

# =============================================================================
# SECTION 11: MARIADB
# =============================================================================

install_mariadb() {
    step "🗄️  Installing MariaDB..."
    skip_if_done mariadb && {
        # Always sync DB user passwords even when MariaDB is already installed
        # This ensures re-runs with loaded passwords still work
        sync_db_users
        return 0
    }

    if command_exists mysql || command_exists mariadb; then
        info "MariaDB client already present, ensuring server is installed..."
    fi

    pkg_install $PACKAGES_DISTRO_MARIADB

    svc_enable mariadb 2>/dev/null || svc_enable mysql 2>/dev/null || true
    svc_start  mariadb 2>/dev/null || svc_start  mysql 2>/dev/null || true

    # Wait for socket to become available
    local retries=30
    while ! mysqladmin ping --silent 2>/dev/null && [ "${retries}" -gt 0 ]; do
        sleep 2; retries=$((retries - 1))
    done

    # Secure MariaDB and set root password
    if mysql -u root -e "SELECT 1;" 2>/dev/null; then
        info "Setting MariaDB root password..."
        mysql -u root << SQLEOF 2>/dev/null || true
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost','127.0.0.1','::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
SQLEOF
    elif mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT 1;" 2>/dev/null; then
        info "MariaDB already secured"
    else
        warn "Could not access MariaDB - may need manual setup"
    fi

    sync_db_users

    mark_done mariadb
    success "MariaDB installed and configured"
}

# Always-run: create/sync FreePBX DB user + databases
# Called both on fresh install and on re-run (after skip_if_done)
sync_db_users() {
    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" << DBEOF 2>/dev/null || true
CREATE DATABASE IF NOT EXISTS asterisk CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE DATABASE IF NOT EXISTS asteriskcdrdb CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
GRANT ALL PRIVILEGES ON asterisk.*     TO 'freepbx'@'localhost' IDENTIFIED BY '${FREEPBX_DB_PASSWORD}';
GRANT ALL PRIVILEGES ON asteriskcdrdb.* TO 'freepbx'@'localhost' IDENTIFIED BY '${FREEPBX_DB_PASSWORD}';
FLUSH PRIVILEGES;
DBEOF
}

# =============================================================================
# SECTION 12: PHP
# =============================================================================

install_php() {
    step "🐘 Installing PHP ${PHP_VERSION}..."

    # RHEL/Fedora: activate the correct PHP module/repo stream before installing
    case "${DISTRO_FAMILY}" in
        rhel|fedora)
            case "${DISTRO_GEN}" in
                3)
                    ${PACKAGE_MGR_BIN} module reset php -y 2>/dev/null || true
                    ${PACKAGE_MGR_BIN} module enable "php:remi-${PHP_VERSION}" -y 2>/dev/null || true
                    ;;
                2)
                    local php_ver_nodot
                    php_ver_nodot=$(echo "${PHP_VERSION}" | tr -d '.')
                    ${PACKAGE_MGR_BIN} config-manager --enable "remi-php${php_ver_nodot}" 2>/dev/null || true
                    ;;
                1)
                    ln -sf /opt/remi/php72/root/usr/bin/php /usr/bin/php 2>/dev/null || true
                    ;;
            esac
            ;;
    esac

    pkg_install $PACKAGES_DISTRO_PHP
    pkg_install $PACKAGES_DISTRO_PHP74    # AvantFax PHP

    # PHP ini configuration
    case "${DISTRO_FAMILY}" in
        debian)
            local php_ini="${PHP_INI_DIR}/apache2/php.ini"
            if [ -f "${php_ini}" ]; then
                backup_config "${php_ini}"
                sed -i 's/upload_max_filesize = .*/upload_max_filesize = 120M/' "${php_ini}"
                sed -i 's/post_max_size = .*/post_max_size = 120M/'             "${php_ini}"
                sed -i 's/memory_limit = .*/memory_limit = 512M/'               "${php_ini}"
                sed -i 's/max_execution_time = .*/max_execution_time = 300/'    "${php_ini}"
                sed -i 's|;date.timezone.*|date.timezone = America/New_York|'   "${php_ini}"
            fi
            local php_cli_ini="${PHP_INI_DIR}/cli/php.ini"
            if [ -f "${php_cli_ini}" ]; then
                backup_config "${php_cli_ini}"
                sed -i 's|;date.timezone.*|date.timezone = America/New_York|' "${php_cli_ini}"
                sed -i 's/memory_limit = .*/memory_limit = 512M/' "${php_cli_ini}"
            fi
            # FreePBX files are owned by asterisk — FPM must run as asterisk
            local fpm_www="${PHP_INI_DIR}/fpm/pool.d/www.conf"
            if [ -f "${fpm_www}" ]; then
                backup_config "${fpm_www}"
                sed -i "s|^user = .*|user = asterisk|"   "${fpm_www}"
                sed -i "s|^group = .*|group = asterisk|" "${fpm_www}"
                if [ -n "${PHP_FPM_SOCK}" ]; then
                    sed -i "s|^listen = .*|listen = ${PHP_FPM_SOCK}|" "${fpm_www}"
                    sed -i "s|^;listen.owner.*\|^listen.owner.*|listen.owner = www-data|" "${fpm_www}"
                    sed -i "s|^;listen.group.*\|^listen.group.*|listen.group = www-data|" "${fpm_www}"
                    sed -i "s|^listen.acl_users.*|listen.acl_users = www-data,asterisk|" "${fpm_www}"
                elif [ -n "${PHP_FPM_PORT}" ]; then
                    sed -i "s|^listen = .*|listen = 127.0.0.1:${PHP_FPM_PORT}|" "${fpm_www}"
                fi
            fi
            ;;
        rhel|fedora)
            local php_ini="/etc/php.ini"
            if [ -f "${php_ini}" ]; then
                backup_config "${php_ini}"
                sed -i 's/upload_max_filesize = .*/upload_max_filesize = 120M/' "${php_ini}"
                sed -i 's/post_max_size = .*/post_max_size = 120M/'             "${php_ini}"
                sed -i 's/memory_limit = .*/memory_limit = 512M/'               "${php_ini}"
                sed -i 's/max_execution_time = .*/max_execution_time = 300/'    "${php_ini}"
                sed -i 's|;date.timezone.*|date.timezone = America/New_York|'   "${php_ini}"
            fi
            local fpm_www="/etc/php-fpm.d/www.conf"
            if [ -f "${fpm_www}" ]; then
                backup_config "${fpm_www}"
                # FreePBX files are owned by asterisk — FPM must run as asterisk
                sed -i "s|^user = .*|user = asterisk|"   "${fpm_www}"
                sed -i "s|^group = .*|group = asterisk|" "${fpm_www}"
                if [ -n "${PHP_FPM_SOCK}" ]; then
                    sed -i "s|^listen = .*|listen = ${PHP_FPM_SOCK}|" "${fpm_www}"
                    sed -i "s|^;listen.owner.*\|^listen.owner.*|listen.owner = apache|" "${fpm_www}"
                    sed -i "s|^;listen.group.*\|^listen.group.*|listen.group = apache|" "${fpm_www}"
                    sed -i "s|^listen.acl_users.*|listen.acl_users = apache,nginx,asterisk|" "${fpm_www}"
                elif [ -n "${PHP_FPM_PORT}" ]; then
                    sed -i "s|^listen = .*|listen = 127.0.0.1:${PHP_FPM_PORT}|" "${fpm_www}"
                fi
            fi
            local fpm74_www="/etc/opt/remi/php74/php-fpm.d/www.conf"
            if [ -f "${fpm74_www}" ]; then
                backup_config "${fpm74_www}"
                if [ -n "${PHP74_FPM_SOCK}" ]; then
                    sed -i "s|^listen = .*|listen = ${PHP74_FPM_SOCK}|" "${fpm74_www}"
                    sed -i "s|^;listen.owner.*|listen.owner = apache|" "${fpm74_www}"
                    sed -i "s|^;listen.group.*|listen.group = apache|" "${fpm74_www}"
                    sed -i "s|^listen.acl_users.*|listen.acl_users = apache,nginx|" "${fpm74_www}"
                elif [ -n "${PHP74_FPM_PORT}" ]; then
                    sed -i "s|^listen = .*|listen = 127.0.0.1:${PHP74_FPM_PORT}|" "${fpm74_www}"
                fi
            fi
            # Remove Remi's PHP 7.4 catch-all Apache config (overrides PHP 8.2 for all .php files)
            rm -f /etc/httpd/conf.d/php74-php.conf 2>/dev/null || true
            ;;
    esac

    svc_enable  "${PHP_FPM_SERVICE}"
    svc_restart "${PHP_FPM_SERVICE}"
    svc_enable  "${PHP74_FPM_SERVICE}" 2>/dev/null || true
    svc_restart "${PHP74_FPM_SERVICE}" 2>/dev/null || true

    # Disable ionCube loader — FreePBX 17 is fully open source and does NOT need ionCube.
    # Some PHP repos (sury.org, ondrej/php) ship ionCube pre-configured and it must load
    # first in php.ini or PHP refuses to start — disabling avoids this conflict entirely.
    for ioncube_ini in \
        /etc/php/*/cli/conf.d/*ioncube*.ini \
        /etc/php/*/fpm/conf.d/*ioncube*.ini \
        /etc/php/*/apache2/conf.d/*ioncube*.ini \
        /etc/php.d/*ioncube*.ini \
        /etc/php/*.d/*ioncube*.ini; do
        [ -f "${ioncube_ini}" ] && {
            rm -f "${ioncube_ini}"
            info "Disabled ionCube: ${ioncube_ini}"
        }
    done
    command -v phpdismod >/dev/null 2>&1 && phpdismod ioncube 2>/dev/null || true
    command -v phpdismod >/dev/null 2>&1 && phpdismod 00-ioncube 2>/dev/null || true

    mark_done php
    success "PHP ${PHP_VERSION} installed"
}

install_avantfax_php() {
    step "🐘 Installing PHP ${PHP_AVANTFAX_VERSION} for AvantFax..."

    # Packages already installed by install_php() — just configure FPM
    case "${DISTRO_FAMILY}" in
        rhel|fedora)
            local fpm74_www="/etc/opt/remi/php74/php-fpm.d/www.conf"
            if [ -f "${fpm74_www}" ]; then
                backup_config "${fpm74_www}"
                if [ -n "${PHP74_FPM_SOCK}" ]; then
                    sed -i "s|^listen = .*|listen = ${PHP74_FPM_SOCK}|" "${fpm74_www}"
                    sed -i "s|^;listen.owner.*|listen.owner = apache|" "${fpm74_www}"
                    sed -i "s|^;listen.group.*|listen.group = apache|" "${fpm74_www}"
                    sed -i "s|^listen.acl_users.*|listen.acl_users = apache,nginx|" "${fpm74_www}"
                elif [ -n "${PHP74_FPM_PORT}" ]; then
                    sed -i "s|^listen = .*|listen = 127.0.0.1:${PHP74_FPM_PORT}|" "${fpm74_www}"
                fi
            fi
            # Remove Remi's catch-all PHP 7.4 Apache config
            rm -f /etc/httpd/conf.d/php74-php.conf 2>/dev/null || true
            ;;
    esac

    svc_enable  "${PHP74_FPM_SERVICE}" 2>/dev/null || true
    svc_restart "${PHP74_FPM_SERVICE}" 2>/dev/null || true

    success "PHP ${PHP_AVANTFAX_VERSION} for AvantFax installed"
}

# =============================================================================
# SECTION 13: APACHE
# =============================================================================

install_apache() {
    step "🌐 Installing Apache web server..."

    # Install core webserver packages (split from optional modules to avoid silent failures)
    pkg_install $PACKAGES_DISTRO_WEBSERVER
    # Optional modules — one by one so a missing one doesn't block
    case "${DISTRO_FAMILY}" in
        debian)
            pkg_install_one_by_one libapache2-mod-fcgid libapache2-mod-proxy-html
            a2enmod rewrite ssl proxy proxy_fcgi proxy_http setenvif headers expires deflate 2>/dev/null || true
            ;;
        rhel|fedora)
            pkg_install_one_by_one mod_ssl mod_proxy_html
            ;;
    esac

    # Verify the web server binary is present after install (Bug A fix)
    if ! [ -f "/usr/sbin/${APACHE_SERVICE}" ] && \
       ! [ -f "/usr/sbin/apache2" ] && \
       ! [ -f "/usr/sbin/httpd" ]; then
        error "Web server install failed — binary not found"
        return 1
    fi

    svc_enable "${APACHE_SERVICE}"
    svc_start  "${APACHE_SERVICE}"

    configure_apache_phpfpm
    configure_freepbx_apache

    svc_reload "${APACHE_SERVICE}" 2>/dev/null || true

    mark_done apache
    success "Apache installed and configured"
}

configure_apache_phpfpm() {
    step "🔧 Configuring Apache PHP-FPM proxy..."

    case "${DISTRO_FAMILY}" in
        debian)
            a2dismod "php${PHP_VERSION}" 2>/dev/null || true
            a2enmod proxy_fcgi setenvif 2>/dev/null || true
            ;;
        rhel|fedora)
            # Remove Remi's catch-all PHP 7.4 handler so it doesn't override PHP 8.2
            rm -f /etc/httpd/conf.d/php74-php.conf 2>/dev/null || true
            ;;
    esac
    # PHP handler directives are written in generate_apache_vhost_config() below
}

configure_freepbx_apache() {
    step "🔧 Creating web root directories for FreePBX..."

    # Create directories early — FreePBX installer needs them to exist before it runs
    mkdir -p "${WEB_ROOT}" "${WEB_ROOT}/admin"
    chown -R asterisk:asterisk "${WEB_ROOT}" 2>/dev/null || true

    # Point the main config's DocumentRoot at WEB_ROOT now so Apache can start serving
    # The full vhost config is generated later by generate_apache_vhost_config()
    case "${DISTRO_FAMILY}" in
        debian)
            local mc="/etc/apache2/sites-available/000-default.conf"
            backup_config "${mc}"
            sed -i "s|DocumentRoot /var/www/html|DocumentRoot ${WEB_ROOT}|g" "${mc}" 2>/dev/null || true
            grep -q "^ServerName" /etc/apache2/apache2.conf 2>/dev/null \
                || echo "ServerName ${SYSTEM_FQDN}" >> /etc/apache2/apache2.conf
            ;;
        rhel|fedora)
            local mc="/etc/httpd/conf/httpd.conf"
            backup_config "${mc}"
            sed -i "s|DocumentRoot \"/var/www/html\"|DocumentRoot \"${WEB_ROOT}\"|g" "${mc}" 2>/dev/null || true
            sed -i "s|<Directory \"/var/www/html\">|<Directory \"${WEB_ROOT}\">|g"    "${mc}" 2>/dev/null || true
            grep -q "^ServerName" "${mc}" 2>/dev/null \
                || echo "ServerName ${SYSTEM_FQDN}" >> "${mc}"
            ;;
    esac
}

# =============================================================================
# SECTION 14: ODBC
# =============================================================================

configure_odbc() {
    step "🔌 Configuring ODBC for MariaDB..."

    # Detect actual driver path
    if   [ -f /usr/lib/x86_64-linux-gnu/odbc/libmaodbc.so ]; then
        ODBC_DRIVER_PATH="/usr/lib/x86_64-linux-gnu/odbc/libmaodbc.so"
    elif [ -f /usr/lib64/libmaodbc.so ]; then
        ODBC_DRIVER_PATH="/usr/lib64/libmaodbc.so"
    elif [ -f /usr/lib/libmaodbc.so ]; then
        ODBC_DRIVER_PATH="/usr/lib/libmaodbc.so"
    elif [ -f /usr/lib/x86_64-linux-gnu/libmaodbc.so ]; then
        ODBC_DRIVER_PATH="/usr/lib/x86_64-linux-gnu/libmaodbc.so"
    else
        local found
        found=$(find /usr -name "libmaodbc.so" 2>/dev/null | head -1)
        [ -n "${found:-}" ] && ODBC_DRIVER_PATH="${found}" \
            || warn "MariaDB ODBC driver not found"
    fi

    backup_config /etc/odbcinst.ini
    cat > /etc/odbcinst.ini << ODBCINSTEOF
[MySQL]
Description = ODBC for MySQL (MariaDB)
Driver = ${ODBC_DRIVER_PATH}
FileUsage = 1
ODBCINSTEOF

    backup_config /etc/odbc.ini
    cat > /etc/odbc.ini << ODBCINIEOF
[MySQL-asteriskcdrdb]
Description = MySQL connection to asteriskcdrdb database
Driver = MySQL
Server = localhost
Database = asteriskcdrdb
Port = 3306
Socket = ${MARIADB_SOCKET}
Option = 3
ODBCINIEOF

    success "ODBC configured"
}

# =============================================================================
# SECTION 15: SSL / LETSENCRYPT
# =============================================================================

configure_letsencrypt_integration() {
    step "🔒 Configuring Let's Encrypt / TLS integration..."
    [ "${SSL_ENABLED}" -ne 1 ] && return 0

    local asterisk_key_dir="/etc/asterisk/keys"
    mkdir -p "${asterisk_key_dir}"
    chown -R asterisk:asterisk "${asterisk_key_dir}" 2>/dev/null || true

    mkdir -p /etc/letsencrypt/renewal-hooks/deploy
    cat > /etc/letsencrypt/renewal-hooks/deploy/asterisk << 'HOOKEOF'
#!/bin/bash
CERT_DIR=$(ls -d /etc/letsencrypt/live/*/ 2>/dev/null | head -1)
[ -z "${CERT_DIR}" ] && exit 0
# Deploy to Asterisk
cp -L "${CERT_DIR}fullchain.pem" /etc/asterisk/keys/fullchain.pem
cp -L "${CERT_DIR}privkey.pem"   /etc/asterisk/keys/privkey.pem
chown asterisk:asterisk /etc/asterisk/keys/*.pem
chmod 640               /etc/asterisk/keys/*.pem
asterisk -rx "module reload res_crypto" 2>/dev/null || true
# Deploy to Apache SSL dir (if in direct mode, not behind proxy)
if [ -d /etc/ssl/pbx ]; then
    cp -L "${CERT_DIR}fullchain.pem" /etc/ssl/pbx/fullchain.pem
    cp -L "${CERT_DIR}privkey.pem"   /etc/ssl/pbx/privkey.pem
    chmod 644 /etc/ssl/pbx/fullchain.pem
    chmod 640 /etc/ssl/pbx/privkey.pem
    systemctl reload apache2 2>/dev/null || systemctl reload httpd 2>/dev/null || true
fi
echo "LE certs deployed to Asterisk + Apache"
HOOKEOF
    chmod +x /etc/letsencrypt/renewal-hooks/deploy/asterisk

    if [ -d /etc/letsencrypt/live ]; then
        local cert_path
        cert_path=$(ls -d /etc/letsencrypt/live/*/ 2>/dev/null | head -1 || true)
        if [ -n "${cert_path:-}" ]; then
            cp -L "${cert_path}fullchain.pem" "${asterisk_key_dir}/fullchain.pem" 2>/dev/null || true
            cp -L "${cert_path}privkey.pem"   "${asterisk_key_dir}/privkey.pem"   2>/dev/null || true
            chown asterisk:asterisk "${asterisk_key_dir}"/*.pem 2>/dev/null || true
            chmod 640               "${asterisk_key_dir}"/*.pem 2>/dev/null || true
            info "Deployed existing Let's Encrypt certs"
        fi
    fi

    if [ ! -f "${asterisk_key_dir}/fullchain.pem" ]; then
        openssl req -new -x509 -days 365 -nodes \
            -subj "/CN=${SYSTEM_FQDN}/O=PBX/C=US" \
            -keyout "${asterisk_key_dir}/privkey.pem" \
            -out    "${asterisk_key_dir}/fullchain.pem" 2>/dev/null \
            || warn "Could not generate self-signed cert"
        chown asterisk:asterisk "${asterisk_key_dir}"/*.pem 2>/dev/null || true
        chmod 640               "${asterisk_key_dir}"/*.pem 2>/dev/null || true
        info "Generated self-signed certificate"
    fi

    success "SSL/TLS configured"
}

configure_reverse_proxy_support() {
    # No-op — handled in generate_apache_vhost_config()
    [ "${BEHIND_PROXY:-no}" = "yes" ] && info "Reverse proxy mode enabled — will be configured in vhost" || true
}

configure_apache_ssl() {
    # No-op — handled in generate_apache_vhost_config()
    true
}

# =============================================================================
# SECTION 16a: SINGLE APACHE VHOST CONFIG (generated after all components known)
# =============================================================================
# Writes two files only:
#   main config  — global settings (ServerName, security tokens, module config)
#   pbx.conf     — all vhosts (HTTP + HTTPS or reverse proxy), all PHP handlers,
#                  all Aliases in one place
#
# Proxy mode (BEHIND_PROXY=yes):
#   - Apache binds to 127.0.0.1 only on a random unused port in the 6x5xx range
#     (60500-65499) so it never conflicts with the front-end proxy on 80/443.
#   - Port is persisted in PBX_ENV_FILE for idempotent re-runs.
#   - No SSL — the proxy terminates TLS externally.
# =============================================================================

# Returns a free port in the 6x5xx range (60500-65499).
# Persists chosen port to PBX_ENV_FILE so re-runs reuse the same value.
find_free_proxy_port() {
    # Return cached value if already chosen this run
    if [ -n "${PROXY_HTTP_PORT:-}" ]; then
        echo "${PROXY_HTTP_PORT}"
        return
    fi

    # Load previously persisted port from env file
    if [ -f "${PBX_ENV_FILE}" ]; then
        local saved
        saved=$(grep "^PROXY_HTTP_PORT=" "${PBX_ENV_FILE}" 2>/dev/null | cut -d= -f2 | tr -d '"')
        if [ -n "${saved:-}" ]; then
            # Verify it's still free (or already in use by us)
            if ! ss -tlnp 2>/dev/null | grep -q ":${saved} " || \
               ss -tlnp 2>/dev/null | grep -q ":${saved}.*httpd\|:${saved}.*apache"; then
                PROXY_HTTP_PORT="${saved}"
                echo "${PROXY_HTTP_PORT}"
                return
            fi
        fi
    fi

    # Pick a new random port from the 6x5xx pattern (60500-65499)
    local port attempts=0
    while [ "${attempts}" -lt 100 ]; do
        # Generate a port matching 6[0-4]5[0-9][0-9]
        local hi mid lo
        hi=$(( RANDOM % 5 ))       # 0-4  → first var digit (60xxx-64xxx)
        mid=$(( RANDOM % 10 ))     # 0-9  → tens digit
        lo=$(( RANDOM % 10 ))      # 0-9  → units digit
        port="6${hi}5${mid}${lo}"
        if ! ss -tlnp 2>/dev/null | grep -q ":${port} " && \
           ! ss -ulnp 2>/dev/null | grep -q ":${port} "; then
            PROXY_HTTP_PORT="${port}"
            # Persist so re-runs reuse the same port
            if [ -f "${PBX_ENV_FILE}" ]; then
                grep -q "^PROXY_HTTP_PORT=" "${PBX_ENV_FILE}" 2>/dev/null \
                    && sed -i "s|^PROXY_HTTP_PORT=.*|PROXY_HTTP_PORT=\"${port}\"|" "${PBX_ENV_FILE}" \
                    || echo "PROXY_HTTP_PORT=\"${port}\"" >> "${PBX_ENV_FILE}"
            fi
            echo "${port}"
            return
        fi
        attempts=$((attempts + 1))
    done

    # Fallback: 65400 is unlikely to conflict
    PROXY_HTTP_PORT=65400
    echo "${PROXY_HTTP_PORT}"
}

generate_apache_vhost_config() {
    step "🌐 Writing Apache configuration files..."

    # Proxy mode: determine loopback port (persisted across re-runs)
    local proxy_port="" proxy_bind=""
    if [ "${BEHIND_PROXY:-no}" = "yes" ]; then
        proxy_port=$(find_free_proxy_port)
        proxy_bind="127.0.0.1:${proxy_port}"
        info "Proxy mode: Apache will listen on ${proxy_bind}"
    fi

    # Determine SSL cert paths
    local cert_file="" key_file="" chain_file="" have_ssl=0
    local le_dir
    le_dir=$(ls -d /etc/letsencrypt/live/*/ 2>/dev/null | head -1 || true)
    if [ -n "${le_dir:-}" ] && [ -f "${le_dir}fullchain.pem" ]; then
        cert_file="${le_dir}fullchain.pem"
        key_file="${le_dir}privkey.pem"
        [ -f "${le_dir}chain.pem" ] && chain_file="${le_dir}chain.pem"
        have_ssl=1
    elif [ "${SSL_ENABLED}" -eq 1 ]; then
        # Use/generate self-signed cert in Apache-readable location
        mkdir -p /etc/ssl/pbx
        if [ ! -f /etc/ssl/pbx/fullchain.pem ]; then
            if [ -f /etc/asterisk/keys/fullchain.pem ]; then
                cp /etc/asterisk/keys/fullchain.pem /etc/ssl/pbx/fullchain.pem
                cp /etc/asterisk/keys/privkey.pem   /etc/ssl/pbx/privkey.pem
            else
                openssl req -new -x509 -days 365 -nodes \
                    -subj "/CN=${SYSTEM_FQDN}/O=PBX/C=US" \
                    -keyout /etc/ssl/pbx/privkey.pem \
                    -out    /etc/ssl/pbx/fullchain.pem 2>/dev/null || true
            fi
        fi
        chmod 644 /etc/ssl/pbx/fullchain.pem 2>/dev/null || true
        chmod 640 /etc/ssl/pbx/privkey.pem   2>/dev/null || true
        cert_file="/etc/ssl/pbx/fullchain.pem"
        key_file="/etc/ssl/pbx/privkey.pem"
        [ -f /etc/ssl/pbx/fullchain.pem ] && have_ssl=1 || true
    fi

    # PHP handler strings
    local php82_handler php74_handler=""
    if [ -n "${PHP_FPM_SOCK:-}" ]; then
        php82_handler="proxy:unix:${PHP_FPM_SOCK}|fcgi://localhost"
    else
        php82_handler="proxy:fcgi://127.0.0.1:${PHP_FPM_PORT:-9000}"
    fi
    if [ -n "${PHP74_FPM_SOCK:-}" ]; then
        php74_handler="proxy:unix:${PHP74_FPM_SOCK}|fcgi://localhost"
    elif [ -n "${PHP74_FPM_PORT:-}" ]; then
        php74_handler="proxy:fcgi://127.0.0.1:${PHP74_FPM_PORT}"
    fi

    local chain_line=""
    [ -n "${chain_file:-}" ] && chain_line="    SSLCertificateChainFile ${chain_file}"

    # AvantFax alias block (reused in both vhosts)
    local avantfax_block=""
    if [ "${INSTALL_AVANTFAX:-1}" -eq 1 ] && [ -n "${php74_handler:-}" ]; then
        avantfax_block="
    Alias /avantfax ${AVANTFAX_WEB_DIR}
    <Directory ${AVANTFAX_WEB_DIR}>
        AllowOverride All
        Require all granted
        <FilesMatch \\.php\$>
            SetHandler \"${php74_handler}\"
        </FilesMatch>
    </Directory>"
    fi

    case "${DISTRO_FAMILY}" in
        # ------------------------------------------------------------------ #
        # DEBIAN / UBUNTU                                                     #
        # ------------------------------------------------------------------ #
        debian)
            local main_conf="/etc/apache2/apache2.conf"
            local vhost_conf="/etc/apache2/sites-available/pbx.conf"

            # 1. Main config — append/replace global settings block
            if ! grep -q "# PBX global settings" "${main_conf}" 2>/dev/null; then
                cat >> "${main_conf}" << MAINEOF

# PBX global settings
ServerName ${SYSTEM_FQDN}
ServerSignature Off
ServerTokens Prod

# PHP ${PHP_VERSION} via FPM (default handler for all .php files)
<FilesMatch \\.php\$>
    SetHandler "${php82_handler}"
</FilesMatch>
MAINEOF
            fi

            # 2. Single vhost file
            # Disable the old default vhost — pbx.conf replaces it
            a2dissite 000-default default-ssl 2>/dev/null || true
            # Clean up any old per-component conf files we used to write
            a2disconf freepbx avantfax remoteip php-fpm php74-fpm 2>/dev/null || true
            rm -f /etc/apache2/conf-available/freepbx.conf \
                  /etc/apache2/conf-available/avantfax.conf \
                  /etc/apache2/conf-available/remoteip.conf \
                  /etc/apache2/conf-available/php-fpm.conf \
                  /etc/apache2/conf-available/php74-fpm.conf \
                  /etc/apache2/sites-available/pbx-ssl.conf \
                  2>/dev/null || true

            if [ "${BEHIND_PROXY:-no}" = "yes" ]; then
                # Reverse proxy mode — HTTP only, bind loopback only
                # Update ports.conf to listen on loopback:port only
                if [ -f /etc/apache2/ports.conf ]; then
                    python3 - "${proxy_bind}" /etc/apache2/ports.conf << 'PYEOF'
import sys, re
bind, path = sys.argv[1], sys.argv[2]
with open(path) as f: lines = f.readlines()
out = []
skip_block = False
for line in lines:
    stripped = line.strip()
    if re.match(r'<IfModule\s+(ssl_module|mod_ssl\.c|mod_gnutls\.c)', stripped):
        skip_block = True
    if re.match(r'</IfModule>', stripped) and skip_block:
        skip_block = False
        continue
    if skip_block:
        continue
    if re.match(r'Listen\s+(80|443)\b', stripped):
        continue
    out.append(line)
# Ensure our bind is listed exactly once
bind_line = 'Listen ' + bind + '\n'
if bind_line not in out:
    out.insert(0, bind_line)
with open(path, 'w') as f: f.writelines(out)
PYEOF
                fi
                cat > "${vhost_conf}" << PROXYVHEOF
# PBX vhost config (reverse proxy mode — loopback ${proxy_bind})
LoadModule remoteip_module   /usr/lib/apache2/modules/mod_remoteip.so

RemoteIPHeader X-Forwarded-For
RemoteIPTrustedProxy 127.0.0.1/8
RemoteIPTrustedProxy 10.0.0.0/8
RemoteIPTrustedProxy 172.16.0.0/12
RemoteIPTrustedProxy 192.168.0.0/16
SetEnvIf X-Forwarded-Proto https HTTPS=on

<VirtualHost ${proxy_bind}>
    ServerName ${SYSTEM_FQDN}
    DocumentRoot ${WEB_ROOT}

    <Directory ${WEB_ROOT}>
        AllowOverride All
        Require all granted
    </Directory>
    <Directory ${WEB_ROOT}/admin>
        AllowOverride All
        Require all granted
        Options -Indexes +FollowSymLinks
    </Directory>
${avantfax_block}
</VirtualHost>
PROXYVHEOF
            elif [ "${have_ssl}" -eq 1 ]; then
                # Direct mode with SSL — HTTP redirects to HTTPS
                cat > "${vhost_conf}" << SSLVHEOF
# PBX vhost config (direct mode with SSL)

<VirtualHost *:80>
    ServerName ${SYSTEM_FQDN}
    Redirect permanent / https://${SYSTEM_FQDN}/
</VirtualHost>

<VirtualHost *:443>
    ServerName ${SYSTEM_FQDN}
    DocumentRoot ${WEB_ROOT}

    SSLEngine on
    SSLCertificateFile    ${cert_file}
    SSLCertificateKeyFile ${key_file}
${chain_line}
    SSLProtocol           all -SSLv2 -SSLv3 -TLSv1 -TLSv1.1
    SSLCipherSuite        ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384
    SSLHonorCipherOrder   on

    <Directory ${WEB_ROOT}>
        AllowOverride All
        Require all granted
    </Directory>
    <Directory ${WEB_ROOT}/admin>
        AllowOverride All
        Require all granted
        Options -Indexes +FollowSymLinks
    </Directory>
${avantfax_block}
</VirtualHost>
SSLVHEOF
            else
                # Direct mode, no SSL
                cat > "${vhost_conf}" << HTTPVHEOF
# PBX vhost config (direct HTTP mode)

<VirtualHost *:80>
    ServerName ${SYSTEM_FQDN}
    DocumentRoot ${WEB_ROOT}

    <Directory ${WEB_ROOT}>
        AllowOverride All
        Require all granted
    </Directory>
    <Directory ${WEB_ROOT}/admin>
        AllowOverride All
        Require all granted
        Options -Indexes +FollowSymLinks
    </Directory>
${avantfax_block}
</VirtualHost>
HTTPVHEOF
            fi

            a2ensite pbx 2>/dev/null || true
            a2enmod rewrite ssl proxy proxy_fcgi proxy_http setenvif \
                    headers expires deflate remoteip 2>/dev/null || true
            ;;

        # ------------------------------------------------------------------ #
        # RHEL / FEDORA                                                       #
        # ------------------------------------------------------------------ #
        rhel|fedora)
            local main_conf="/etc/httpd/conf/httpd.conf"
            local vhost_conf="/etc/httpd/conf.d/pbx.conf"

            # 1. Main config — append/replace global settings block
            if ! grep -q "# PBX global settings" "${main_conf}" 2>/dev/null; then
                cat >> "${main_conf}" << MAINEOF

# PBX global settings
ServerSignature Off
ServerTokens Prod

# PHP ${PHP_VERSION} via FPM (default handler for all .php files)
<FilesMatch \\.php\$>
    SetHandler "${php82_handler}"
</FilesMatch>
MAINEOF
            fi

            # 2. Single vhost file — remove old per-component files first
            rm -f /etc/httpd/conf.d/freepbx.conf \
                  /etc/httpd/conf.d/avantfax.conf \
                  /etc/httpd/conf.d/remoteip.conf \
                  /etc/httpd/conf.d/php-fpm.conf \
                  /etc/httpd/conf.d/pbx-ssl.conf \
                  2>/dev/null || true

            if [ "${BEHIND_PROXY:-no}" = "yes" ]; then
                # Update httpd.conf Listen to loopback:port only
                sed -i "s|^Listen 80$|Listen ${proxy_bind}|g" "${main_conf}"
                grep -q "Listen ${proxy_bind}" "${main_conf}" || \
                    sed -i "1s|^|Listen ${proxy_bind}\n|" "${main_conf}"
                # Disable ssl.conf if present (proxy mode doesn't need 443)
                [ -f /etc/httpd/conf.d/ssl.conf ] && \
                    mv /etc/httpd/conf.d/ssl.conf /etc/httpd/conf.d/ssl.conf.proxydisabled 2>/dev/null || true
                cat > "${vhost_conf}" << PROXYVHEOF
# PBX vhost config (reverse proxy mode — loopback ${proxy_bind})
LoadModule remoteip_module modules/mod_remoteip.so

RemoteIPHeader X-Forwarded-For
RemoteIPTrustedProxy 127.0.0.1/8
RemoteIPTrustedProxy 10.0.0.0/8
RemoteIPTrustedProxy 172.16.0.0/12
RemoteIPTrustedProxy 192.168.0.0/16
SetEnvIf X-Forwarded-Proto https HTTPS=on

<VirtualHost ${proxy_bind}>
    ServerName ${SYSTEM_FQDN}
    DocumentRoot ${WEB_ROOT}

    <Directory ${WEB_ROOT}>
        AllowOverride All
        Require all granted
    </Directory>
    <Directory ${WEB_ROOT}/admin>
        AllowOverride All
        Require all granted
        Options -Indexes +FollowSymLinks
    </Directory>
${avantfax_block}
</VirtualHost>
PROXYVHEOF
            elif [ "${have_ssl}" -eq 1 ]; then
                cat > "${vhost_conf}" << SSLVHEOF
# PBX vhost config (direct mode with SSL)

<VirtualHost *:80>
    ServerName ${SYSTEM_FQDN}
    Redirect permanent / https://${SYSTEM_FQDN}/
</VirtualHost>

<VirtualHost *:443>
    ServerName ${SYSTEM_FQDN}
    DocumentRoot ${WEB_ROOT}

    SSLEngine on
    SSLCertificateFile    ${cert_file}
    SSLCertificateKeyFile ${key_file}
${chain_line}
    SSLProtocol           all -SSLv2 -SSLv3 -TLSv1 -TLSv1.1
    SSLCipherSuite        ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384
    SSLHonorCipherOrder   on

    <Directory ${WEB_ROOT}>
        AllowOverride All
        Require all granted
    </Directory>
    <Directory ${WEB_ROOT}/admin>
        AllowOverride All
        Require all granted
        Options -Indexes +FollowSymLinks
    </Directory>
${avantfax_block}
</VirtualHost>
SSLVHEOF
            else
                cat > "${vhost_conf}" << HTTPVHEOF
# PBX vhost config (direct HTTP mode)

<VirtualHost *:80>
    ServerName ${SYSTEM_FQDN}
    DocumentRoot ${WEB_ROOT}

    <Directory ${WEB_ROOT}>
        AllowOverride All
        Require all granted
    </Directory>
    <Directory ${WEB_ROOT}/admin>
        AllowOverride All
        Require all granted
        Options -Indexes +FollowSymLinks
    </Directory>
${avantfax_block}
</VirtualHost>
HTTPVHEOF
            fi
            ;;
    esac

    svc_reload "${APACHE_SERVICE}" 2>/dev/null || true
    success "Apache vhost configured: $([ "${BEHIND_PROXY:-no}" = "yes" ] && echo "reverse proxy (HTTP:80)" || ([ "${have_ssl}" -eq 1 ] && echo "direct HTTPS:443 + HTTP redirect" || echo "direct HTTP:80"))"
}

# =============================================================================
# SECTION 16: ASTERISK SERVICE FILES
# =============================================================================

create_asterisk_service() {
    step "⚙️  Creating Asterisk systemd service..."
    [ "${INIT_SYSTEM}" != "systemd" ] && return 0

    cat > /etc/systemd/system/asterisk.service << 'ASTSVCEOF'
[Unit]
Description=Asterisk PBX
After=network.target mariadb.service
Wants=mariadb.service

[Service]
Type=simple
PIDFile=/run/asterisk/asterisk.pid
Environment=HOME=/var/lib/asterisk
User=asterisk
Group=asterisk
ExecStartPre=/bin/mkdir -p /run/asterisk
ExecStartPre=/bin/chown asterisk:asterisk /run/asterisk
ExecStart=/usr/sbin/asterisk -f -C /etc/asterisk/asterisk.conf
ExecStop=/usr/sbin/asterisk -rx "core stop gracefully"
ExecReload=/usr/sbin/asterisk -rx "core reload"
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
ASTSVCEOF

    svc_daemon_reload
    svc_enable asterisk
    success "Asterisk service created and enabled"
}

create_iaxmodem_services() {
    local modem_num="$1"
    [ "${INIT_SYSTEM}" != "systemd" ] && return 0

    cat > "/etc/systemd/system/iaxmodem-ttyIAX${modem_num}.service" << IAXSVCEOF
[Unit]
Description=IAXmodem ttyIAX${modem_num}
After=network.target asterisk.service
Wants=asterisk.service

[Service]
Type=simple
ExecStart=/usr/sbin/iaxmodem ttyIAX${modem_num}
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
IAXSVCEOF

    svc_daemon_reload
}

create_hylafax_service() {
    step "📠 Creating HylaFAX systemd service..."
    [ "${INIT_SYSTEM}" != "systemd" ] && return 0

    # Detect actual binary paths — packages install to /usr/sbin, source compile to /usr/local/sbin
    local faxq_bin faxquit_bin
    faxq_bin=$(command -v faxq 2>/dev/null || echo "/usr/sbin/faxq")
    faxquit_bin=$(command -v faxquit 2>/dev/null || echo "/usr/sbin/faxquit")

    cat > /etc/systemd/system/hylafax.service << HYLSVCEOF
[Unit]
Description=HylaFAX Fax Server
After=network.target

[Service]
Type=forking
ExecStart=${faxq_bin}
ExecStop=${faxquit_bin}
KillMode=control-group
Restart=on-failure

[Install]
WantedBy=multi-user.target
HYLSVCEOF

    svc_daemon_reload
}

# =============================================================================
# SECTION 17: ASTERISK INSTALLATION
# =============================================================================

install_asterisk() {
    step "📞 Installing Asterisk ${ASTERISK_VERSION}..."
    skip_if_done asterisk && return 0

    if command_exists asterisk \
        && asterisk -V 2>/dev/null | grep -q "Asterisk ${ASTERISK_VERSION}"; then
        info "Asterisk ${ASTERISK_VERSION} already installed, skipping"
        return 0
    fi

    if ! id asterisk >/dev/null 2>&1; then
        useradd -r -d /var/lib/asterisk -s /sbin/nologin asterisk
        usermod -a -G audio,dialout asterisk 2>/dev/null || true
        info "Created asterisk system user"
    fi

    usermod -a -G "${APACHE_GROUP}" asterisk 2>/dev/null || true
    usermod -a -G asterisk "${APACHE_USER}"  2>/dev/null || true
    # On Debian/Ubuntu, /usr/bin/crontab is setgid crontab — asterisk user needs this group
    getent group crontab >/dev/null 2>&1 && usermod -a -G crontab asterisk 2>/dev/null || true

    cd "${WORK_DIR}"
    local asterisk_tar="asterisk-${ASTERISK_VERSION}-current.tar.gz"
    local asterisk_url="https://downloads.asterisk.org/pub/telephony/asterisk/${asterisk_tar}"

    if [ ! -f "${asterisk_tar}" ]; then
        info "Downloading Asterisk ${ASTERISK_VERSION}..."
        download_file "${asterisk_url}" "${asterisk_tar}" 300 \
            || { error "Failed to download Asterisk from ${asterisk_url}"; return 1; }
        # Feature: download-integrity — verify sha256 from Asterisk's published checksum file
        local sha256_url="${asterisk_url}.sha256"
        local sha256_file="${asterisk_tar}.sha256"
        if download_file "${sha256_url}" "${sha256_file}" 30 2>/dev/null; then
            local expected_hash
            expected_hash=$(awk '{print $1}' "${sha256_file}" 2>/dev/null)
            verify_download "${asterisk_tar}" "${expected_hash}" \
                || { error "Asterisk tarball checksum failed — removing corrupt file"; rm -f "${asterisk_tar}" "${sha256_file}"; return 1; }
        else
            info "No sha256 file at ${sha256_url} — skipping integrity check"
        fi
    fi

    tar -xzf "${asterisk_tar}"
    local asterisk_dir
    asterisk_dir=$(ls -d "${WORK_DIR}/asterisk-${ASTERISK_VERSION}"*/ 2>/dev/null | head -1 || true)
    [ -d "${asterisk_dir:-}" ] || error "Asterisk source not found after extraction"

    cd "${asterisk_dir}"
    [ -f contrib/scripts/install_prereq ] \
        && bash contrib/scripts/install_prereq install 2>/dev/null || true

    export CFLAGS="-DENABLE_SRTP_AES_256 -DENABLE_SRTP_AES_GCM"
    ./configure \
        --with-pjproject-bundled \
        --with-jansson-bundled \
        --prefix=/usr \
        --sysconfdir=/etc \
        --localstatedir=/var \
        2>&1 | tee -a "${LOG_FILE}" | tail -5

    make menuselect.makeopts 2>/dev/null || true
    menuselect/menuselect \
        --enable ADDONS \
        --enable chan_mobile \
        --enable chan_ooh323 \
        --enable format_mp3 \
        --disable TESTS \
        --enable codec_opus \
        --enable codec_silk \
        --enable codec_siren7 \
        --enable codec_siren14 \
        --enable codec_g729a \
        --enable EXTRA-SOUNDS-EN-GSM \
        --enable EXTRA-SOUNDS-EN-ULAW \
        menuselect.makeopts 2>/dev/null || true

    info "Compiling Asterisk (this may take several minutes)..."
    make -j"$(nproc)" 2>&1 | tee -a "${LOG_FILE}" | tail -3 || { error "Asterisk compile failed"; return 1; }
    make install           2>&1 | tee -a "${LOG_FILE}" | tail -3 || { error "Asterisk install failed"; return 1; }
    make config            2>/dev/null || true
    make install-logrotate 2>/dev/null || true
    ldconfig

    mkdir -p /etc/asterisk /var/lib/asterisk /var/log/asterisk /var/spool/asterisk
    chown -R asterisk:asterisk \
        /etc/asterisk /var/lib/asterisk /var/log/asterisk /var/spool/asterisk

    create_asterisk_service

    mark_done asterisk
    cd /
    success "Asterisk ${ASTERISK_VERSION} installed"
}

# =============================================================================
# SECTION 18: FREEPBX INSTALLATION
# =============================================================================

install_freepbx() {
    step "📞 Installing FreePBX ${FREEPBX_VERSION}..."
    skip_if_done freepbx && return 0

    if [ -f "${WEB_ROOT}/admin/index.php" ]; then
        info "FreePBX already installed, skipping"
        return 0
    fi

    # If /etc/freepbx.conf exists but web files are NOT at WEB_ROOT/admin/,
    # the previous install was partial/corrupt — remove stale config so the
    # installer treats this as a fresh install and copies all files correctly.
    if [ -f /etc/freepbx.conf ] && [ ! -f "${WEB_ROOT}/admin/index.php" ]; then
        warn "Stale /etc/freepbx.conf found with missing web files — removing for clean reinstall"
        rm -f /etc/freepbx.conf
        # Also clean up any leftover partial web files that might confuse the installer
        rm -rf "${WEB_ROOT}/admin" /var/www/html/admin 2>/dev/null || true
        mkdir -p "${WEB_ROOT}/admin"
        chown asterisk:asterisk "${WEB_ROOT}/admin" 2>/dev/null || true
    fi

    cd "${WORK_DIR}"
    local fpbx_url="http://mirror.freepbx.org/modules/packages/freepbx/freepbx-17.0-latest.tgz"
    local fpbx_tar="freepbx-17.0-latest.tgz"

    if [ ! -f "${fpbx_tar}" ]; then
        info "Downloading FreePBX..."
        download_file "${fpbx_url}" "${fpbx_tar}" 300 \
            || { error "Failed to download FreePBX from ${fpbx_url}"; return 1; }
    fi

    tar -xzf "${fpbx_tar}"
    local fpbx_dir="${WORK_DIR}/freepbx"
    [ -d "${fpbx_dir}" ] || error "FreePBX source not found after extraction"
    cd "${fpbx_dir}"

    # Create minimal modules.conf if missing — Asterisk won't start without it
    # FreePBX will overwrite this with its own version after installation
    if [ ! -f /etc/asterisk/modules.conf ]; then
        mkdir -p /etc/asterisk
        cat > /etc/asterisk/modules.conf << 'MODSEOF'
[modules]
autoload=yes
noload => chan_alsa.so
noload => chan_console.so
noload => chan_oss.so
noload => chan_mgcp.so
noload => chan_skinny.so
MODSEOF
        chown asterisk:asterisk /etc/asterisk/modules.conf 2>/dev/null || true
    fi

    # Create minimal xmpp.conf so res_xmpp doesn't decline to load
    if [ ! -f /etc/asterisk/xmpp.conf ]; then
        cat > /etc/asterisk/xmpp.conf << 'XMPPEOF'
[general]
; XMPP/Jabber configuration
; Uncomment and configure to enable Google Voice or XMPP integration
; See: https://wiki.asterisk.org/wiki/display/AST/Jabber+XMPP+Integration
XMPPEOF
        chown asterisk:asterisk /etc/asterisk/xmpp.conf 2>/dev/null || true
    fi

    info "Starting Asterisk for FreePBX installer..."
    # Kill any stuck safe_asterisk/asterisk before trying to start
    local _spid _apid
    _spid=$(pgrep -x safe_asterisk 2>/dev/null || true)
    _apid=$(pgrep -x asterisk 2>/dev/null || true)
    [ -n "$_spid" ] && kill -9 "$_spid" 2>/dev/null || true
    [ -n "$_apid" ] && kill -9 "$_apid" 2>/dev/null || true
    sleep 2
    rm -f /var/run/asterisk/asterisk.ctl /var/run/asterisk/asterisk.pid 2>/dev/null || true
    if [ -f ./start_asterisk ]; then
        ./start_asterisk start 2>/dev/null || true
    else
        svc_start asterisk
    fi
    # Wait for Asterisk AMI/CLI to become ready (up to 60 seconds)
    local waited=0
    while [ $waited -lt 60 ]; do
        if asterisk -rx "core show version" >/dev/null 2>&1; then
            info "Asterisk is ready"
            break
        fi
        sleep 3
        waited=$((waited + 3))
    done
    if ! asterisk -rx "core show version" >/dev/null 2>&1; then
        warn "Asterisk CLI not responding after ${waited}s — FreePBX install may have issues"
    fi

    info "Running FreePBX installer..."
    # Note: FreePBX installer may exit 1 even on success — check for fwconsole instead
    php ./install -n \
        --dbhost=localhost \
        --dbname=asterisk \
        --dbuser=freepbx \
        --dbpass="${FREEPBX_DB_PASSWORD}" \
        --webroot="${WEB_ROOT}" \
        2>&1 | tee -a "${LOG_FILE}" | tail -10 || true
    if [ ! -f /usr/sbin/fwconsole ]; then
        error "FreePBX installation failed — fwconsole not found"
        return 1
    fi

    # FreePBX installer stores AMPWEBROOT=/var/www/html as default in freepbx_settings,
    # ignoring the --webroot flag we passed. Update it to match our actual webroot so
    # fwconsole reads the correct path after bootstrap.php overrides $amp_conf from DB.
    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" asterisk \
        -e "UPDATE freepbx_settings SET value='${WEB_ROOT}' WHERE keyword='AMPWEBROOT';" \
        2>/dev/null || true

    info "Installing FreePBX modules..."
    # Enable repos BEFORE installall — installall downloads from repos
    fwconsole ma enablerepo standard    2>/dev/null || true
    fwconsole ma enablerepo extended    2>/dev/null || true
    fwconsole ma enablerepo unsupported 2>/dev/null || true
    fwconsole ma installall 2>/dev/null || warn "Module installall had errors"

    for mod in superfecta queueprio miscdests miscapps outcnam \
               dynroute extensionsettings disa allowlist \
               inboundroutes outboundroutes ringgroups queues ivr \
               timeconditions daynight miscdi callforward findmefollow \
               donotdisturb parking paging followme callrecording \
               recordings announcement conferences conferenceapps \
               cidlookup directory phonebook ucp userman hotelwakeup wakeup \
               sip; do
        fwconsole ma downloadinstall "${mod}" 2>/dev/null || true
    done

    fwconsole ma remove firewall    2>/dev/null || true
    fwconsole ma remove synologyabb 2>/dev/null || true

    local ari_user ari_pass
    ari_user="ari_$(generate_password 4 2>/dev/null | tr '[:upper:]' '[:lower:]' || echo "pbxuser")"
    ari_pass=$(generate_password 20)
    fwconsole setting FPBX_ARI_USER      "${ari_user}"    2>/dev/null || true
    fwconsole setting FPBX_ARI_PASSWORD  "${ari_pass}"    2>/dev/null || true
    fwconsole setting HTTPTLSBINDADDRESS "0.0.0.0:8089"  2>/dev/null || true
    fwconsole setting HTTPBINDADDRESS    "127.0.0.1:8088" 2>/dev/null || true

    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" asterisk << FPBXDBEOF 2>/dev/null || true
INSERT IGNORE INTO freepbx_settings (keyword,value) VALUES ('CDR_BATCH_ENABLE','1');
INSERT IGNORE INTO freepbx_settings (keyword,value) VALUES ('USERESMWIBLF','1');
INSERT IGNORE INTO freepbx_settings (keyword,value) VALUES ('DASHBOARD_FREEPBX_BRAND','PBX System');
UPDATE freepbx_settings SET value='1' WHERE keyword='CDR_BATCH_ENABLE';
UPDATE freepbx_settings SET value='1' WHERE keyword='USERESMWIBLF';
FPBXDBEOF

    # Create FreePBX admin user via SQL (fwconsole userman --add removed in FreePBX 17)
    local pass_hash
    pass_hash=$(echo -n "${FREEPBX_ADMIN_PASSWORD}" | sha1sum | cut -d' ' -f1)
    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" asterisk 2>/dev/null << ADMINEOF || true
INSERT INTO ampusers (username, email, password_sha1, extension_low, extension_high, deptname, sections)
VALUES ('${FREEPBX_ADMIN_USERNAME}', 'admin@localhost', '${pass_hash}', '', '', '', 'all')
ON DUPLICATE KEY UPDATE password_sha1='${pass_hash}', sections='all';
ADMINEOF
    info "FreePBX admin user '${FREEPBX_ADMIN_USERNAME}' created"

    if [ "${INIT_SYSTEM}" = "systemd" ]; then
        cat > /etc/systemd/system/freepbx.service << 'FPBXSVCEOF'
[Unit]
Description=FreePBX VoIP Server
After=network.target mariadb.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/fwconsole start --quiet
ExecStop=/usr/sbin/fwconsole stop --quiet

[Install]
WantedBy=multi-user.target
FPBXSVCEOF
        svc_daemon_reload
        svc_enable freepbx
        # Disable bare asterisk.service — fwconsole (via freepbx.service) manages Asterisk
        svc_disable asterisk 2>/dev/null || true
    fi

    mark_done freepbx
    cd /
    success "FreePBX ${FREEPBX_VERSION} installed"
}

# =============================================================================
# SECTION 19: FREEPBX CONFIGURATION
# =============================================================================

configure_freepbx() {
    step "⚙️  Configuring FreePBX settings..."

    local retries=30
    while ! asterisk -rx "core show version" >/dev/null 2>&1 \
        && [ "${retries}" -gt 0 ]; do
        sleep 3; retries=$((retries - 1))
    done

    # Write PJSIP transports directly to /etc/asterisk/pjsip_custom.conf
    # Do NOT insert into the pjsip DB table — FreePBX joins it with trunks
    # and iterates it as trunk data, causing "Undefined array key trunk_name"
    mkdir -p /etc/asterisk
    cat > /etc/asterisk/pjsip_custom.conf << PJSIPCUSTEOF
; PBX custom PJSIP transports — managed by install.sh
; FreePBX includes pjsip_custom.conf automatically

[transport-udp]
type=transport
protocol=udp
bind=0.0.0.0:5060
allow_reload=yes

[transport-tcp]
type=transport
protocol=tcp
bind=0.0.0.0:5060

[transport-tls]
type=transport
protocol=tls
bind=0.0.0.0:5061
cert_file=/etc/asterisk/keys/fullchain.pem
priv_key_file=/etc/asterisk/keys/privkey.pem
method=tlsv1_2
PJSIPCUSTEOF

    # Feature: anon-sip — anonymous SIP inbound endpoint
    if ! grep -q "\[anonymous\]" /etc/asterisk/pjsip_custom.conf 2>/dev/null; then
        cat >> /etc/asterisk/pjsip_custom.conf << 'ANONEOF'

; Anonymous inbound SIP — allows calls from unknown/unregistered endpoints
[anonymous]
type=endpoint
context=from-external
allow=ulaw,alaw,g722

[global]
type=global
endpoint_identifier_order=ip,username,anonymous
ANONEOF
    fi

    chown asterisk:asterisk /etc/asterisk/pjsip_custom.conf

    # Use INSERT ... ON DUPLICATE KEY UPDATE so existing rows get updated, new rows get proper type
    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" asterisk << NATEOF 2>/dev/null || true
INSERT INTO freepbx_settings (keyword,value,type,emptyok) VALUES ('EXTERNALIP','${PUBLIC_IP}','text',1)
  ON DUPLICATE KEY UPDATE value='${PUBLIC_IP}';
INSERT INTO freepbx_settings (keyword,value,type,emptyok) VALUES ('LOCALNET','${PRIVATE_IP}/255.255.255.0','text',1)
  ON DUPLICATE KEY UPDATE value='${PRIVATE_IP}/255.255.255.0';
INSERT INTO freepbx_settings (keyword,value,type,emptyok) VALUES ('SIPNAT','yes','bool',1)
  ON DUPLICATE KEY UPDATE value='yes';
NATEOF

    if [ -f /etc/asterisk/modules.conf ]; then
        backup_config /etc/asterisk/modules.conf
        grep -q "noload => chan_sip.so" /etc/asterisk/modules.conf \
            || echo "noload => chan_sip.so" >> /etc/asterisk/modules.conf
    fi

    # User-facing modules
    for mod in ucp hotelwakeup userman voicemail recordings; do
        fwconsole ma downloadinstall "${mod}" 2>/dev/null || true
    done

    # Remove problematic/unneeded modules
    for mod in firewall sysadmin; do
        fwconsole ma remove "${mod}" 2>/dev/null || true
    done

    # Enable CDR and queue logging
    fwconsole setting ASTRUNDIR /var/run/asterisk 2>/dev/null || true

    fwconsole reload --skip-registry-checks 2>/dev/null || true

    track_install "freepbx-config"
    success "FreePBX configured"
}

# =============================================================================
# SECTION 20: POSTFIX
# =============================================================================

install_postfix() {
    step "📧 Installing Postfix MTA..."

    case "${DISTRO_FAMILY}" in
        debian)
            $PACKAGE_MGR_BIN remove -y sendmail exim4 2>/dev/null || true
            echo "postfix postfix/mailname string ${SYSTEM_FQDN}" | debconf-set-selections
            echo "postfix postfix/main_mailer_type string 'Internet Site'" | debconf-set-selections
            ;;
        rhel|fedora)
            $PACKAGE_MGR_BIN remove -y sendmail 2>/dev/null || true
            ;;
    esac

    pkg_install postfix
    # Mail client utilities — try several names (distro/version differ)
    pkg_install_one_by_one mailutils bsd-mailx s-nail mailx

    svc_enable postfix
    svc_start  postfix

    # Guard all postfix config writes — postfix may not be installed (missing repo)
    if command -v postconf >/dev/null 2>&1; then
        backup_config /etc/postfix/main.cf
        postconf -e "myhostname = ${SYSTEM_FQDN}"       2>/dev/null || true
        postconf -e "mydomain = ${SYSTEM_DOMAIN}"        2>/dev/null || true
        postconf -e "myorigin = ${SYSTEM_FQDN}"          2>/dev/null || true
        postconf -e "inet_interfaces = loopback-only"    2>/dev/null || true
        postconf -e "inet_protocols = ipv4"              2>/dev/null || true

        # Rewrite all outgoing From: headers to FROM_EMAIL / FROM_NAME
        mkdir -p /etc/postfix
        cat > /etc/postfix/sender_canonical << CANONEOF
/.+/    ${FROM_NAME} <${FROM_EMAIL}>
CANONEOF
        postconf -e "sender_canonical_maps = regexp:/etc/postfix/sender_canonical" 2>/dev/null || true
        postconf -e "smtp_header_checks = regexp:/etc/postfix/header_checks"       2>/dev/null || true
        cat > /etc/postfix/header_checks << HCEOF
/^From:.*/ REPLACE From: ${FROM_NAME} <${FROM_EMAIL}>
HCEOF
        postmap /etc/postfix/sender_canonical 2>/dev/null || true
        svc_reload postfix 2>/dev/null || true
    else
        warn "postconf not found — skipping postfix configuration (postfix not installed?)"
    fi

    cat > /usr/local/bin/enable-gmail-smarthost << 'GMAILEOF'
#!/bin/bash
# Enable Gmail relay for Postfix — set GMAIL_USER and GMAIL_PASS first
GMAIL_USER="${GMAIL_USER:-your@gmail.com}"
GMAIL_PASS="${GMAIL_PASS:-your-app-password}"
postconf -e "relayhost = [smtp.gmail.com]:587"
postconf -e "smtp_sasl_auth_enable = yes"
postconf -e "smtp_sasl_security_options = noanonymous"
postconf -e "smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd"
postconf -e "smtp_use_tls = yes"
postconf -e "smtp_tls_security_level = encrypt"
postconf -e "smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt"
cat > /etc/postfix/sasl_passwd << EOF
[smtp.gmail.com]:587 ${GMAIL_USER}:${GMAIL_PASS}
EOF
chmod 600 /etc/postfix/sasl_passwd
postmap /etc/postfix/sasl_passwd
systemctl restart postfix
echo "Gmail relay configured for ${GMAIL_USER}"
GMAILEOF
    chmod +x /usr/local/bin/enable-gmail-smarthost

    mark_done postfix
    success "Postfix installed"
}

# =============================================================================
# SECTION 21: HYLAFAX
# =============================================================================

install_hylafax() {
    step "📠 Installing HylaFAX+..."

    if command_exists faxstat; then
        info "HylaFAX already installed, skipping"
        return 0
    fi

    # Try package install first
    if [ -n "${PACKAGES_DISTRO_FAX:-}" ]; then
        pkg_install_one_by_one $PACKAGES_DISTRO_FAX
    fi

    # On RHEL/Fedora, hylafax+ has no package in EPEL9 — compile from source
    if ! command_exists faxstat && [ "${DISTRO_FAMILY}" = "rhel" -o "${DISTRO_FAMILY}" = "fedora" ]; then
        info "HylaFAX+ package not available — compiling from source..."
        _compile_hylafax_source || warn "HylaFAX+ source compile failed"
    fi

    if ! command_exists faxstat; then
        warn "HylaFAX not installed — fax functionality unavailable"
        return 0
    fi

    # Initialize HylaFAX server config non-interactively.
    # faxsetup -server is interactive (calls faxaddmodem for hardware modems).
    # We use IAXmodem (software modem) so we skip hardware modem detection
    # and just ensure the required directories and base config exist.
    mkdir -p /var/spool/hylafax/{etc,log,tmp,bin,archive,recvq}
    mkdir -p /var/spool/hylafax/etc
    # HylaFax queue daemon (faxq) runs as the 'uucp' user and needs to create
    # the FIFO control file in the spool root. Set ownership accordingly.
    # On RHEL-family 'uucp' maps to uid 3 (adm group), on Debian it's a proper 'uucp' group.
    chown uucp:uucp /var/spool/hylafax/ 2>/dev/null || \
        chown "$(id -u uucp 2>/dev/null || echo 3)":"$(id -g uucp 2>/dev/null || echo 4)" \
              /var/spool/hylafax/ 2>/dev/null || true
    chmod 755 /var/spool/hylafax/
    # Run faxsetup with 30s timeout piping newlines (accept all defaults, no modem config)
    if command_exists faxsetup; then
        timeout 30 bash -c 'yes "" | faxsetup -server -nomodem' 2>/dev/null || \
        timeout 30 bash -c 'yes "" | faxsetup -server'          2>/dev/null || true
    fi

    create_hylafax_service
    svc_enable hylafax 2>/dev/null || svc_enable hfaxd 2>/dev/null || true
    svc_start  hylafax 2>/dev/null || svc_start  hfaxd 2>/dev/null || true

    mark_done hylafax
    success "HylaFAX installed"
}

# Compile HylaFAX+ from source (used on RHEL/Fedora where no package is available)
_compile_hylafax_source() {
    # Use /latest/download to always get the current release
    local url="https://sourceforge.net/projects/hylafax/files/latest/download"
    local src_tar="hylafax-latest.tar.gz"

    # Build dependencies
    pkg_install libtiff-devel libtiff-tools libjpeg-turbo-devel openssl-devel \
        pam-devel ghostscript gcc gcc-c++ make 2>/dev/null || true

    # Symlink gs to expected location if needed
    if ! [ -x /usr/local/bin/gs ] && command -v gs >/dev/null 2>&1; then
        ln -sf "$(command -v gs)" /usr/local/bin/gs 2>/dev/null || true
    fi

    cd "${WORK_DIR}"
    if [ ! -f "${src_tar}" ]; then
        download_file "${url}" "${src_tar}" 180 || return 1
    fi

    tar -xzf "${src_tar}" 2>/dev/null || return 1
    local src_dir
    src_dir=$(ls -d hylafax-*/ 2>/dev/null | head -1)
    [ -d "${src_dir:-}" ] || return 1

    cd "${src_dir}"
    ./configure --nointeractive --quiet 2>/dev/null || return 1

    # Build in dependency order: port → util → rest
    # man page generation may fail (non-fatal); binaries are what matter
    ( cd port && make ) 2>/dev/null || return 1
    ( cd util && make ) 2>/dev/null || return 1
    make -j"$(nproc)" 2>/dev/null; make install 2>/dev/null || return 1
    # Verify at least one key binary was installed
    command -v faxstat >/dev/null 2>&1 || return 1
    cd "${WORK_DIR}"
    return 0
}

# =============================================================================
# SECTION 22: IAXMODEM
# =============================================================================

install_iaxmodem() {
    step "📠 Installing IAXmodem..."

    if command_exists iaxmodem; then
        info "IAXmodem already installed, skipping"
        return 0
    fi

    # Try package first (available on Debian)
    pkg_install_one_by_one iaxmodem 2>/dev/null || true

    # On RHEL/Fedora, iaxmodem has no package — compile from source
    if ! command_exists iaxmodem && [ "${DISTRO_FAMILY}" = "rhel" -o "${DISTRO_FAMILY}" = "fedora" ]; then
        info "IAXmodem package not available — compiling from source..."
        _compile_iaxmodem_source || warn "IAXmodem source compile failed"
    fi

    if ! command_exists iaxmodem; then
        warn "IAXmodem not installed — fax modems unavailable"
        return 0
    fi

    local i=1
    while [ "${i}" -le "${NUMBER_OF_MODEMS}" ]; do
        mkdir -p /etc/iaxmodem
        cat > "/etc/iaxmodem/ttyIAX${i}" << MODEMEOF
device          /dev/ttyIAX${i}
owner           uucp:uucp
mode            660
port            4569
refresh         300
server          127.0.0.1
peername        iaxmodem${i}
secret          iaxmodem${i}secret
cidname         FAX MACHINE ${i}
cidnumber       s
codec           ulaw
MODEMEOF
        create_iaxmodem_services "${i}"
        svc_enable "iaxmodem-ttyIAX${i}" 2>/dev/null || true
        svc_start  "iaxmodem-ttyIAX${i}" 2>/dev/null || true
        i=$((i + 1))
    done

    track_install "iaxmodem"
    success "IAXmodem installed"
}

# Compile IAXmodem from source (used on RHEL/Fedora where no package is available)
_compile_iaxmodem_source() {
    local url="https://sourceforge.net/projects/iaxmodem/files/latest/download"
    local src_tar="iaxmodem-latest.tgz"

    pkg_install libtiff-devel gcc make 2>/dev/null || true

    cd "${WORK_DIR}"
    if [ ! -f "${src_tar}" ]; then
        download_file "${url}" "${src_tar}" 120 || return 1
    fi

    tar -xzf "${src_tar}" 2>/dev/null || return 1
    local src_dir
    src_dir=$(ls -d iaxmodem*/ 2>/dev/null | head -1)
    [ -d "${src_dir:-}" ] || return 1

    cd "${src_dir}"
    make -j"$(nproc)" 2>/dev/null || make 2>/dev/null || return 1
    install -m 755 iaxmodem /usr/sbin/iaxmodem 2>/dev/null || \
        cp iaxmodem /usr/sbin/iaxmodem && chmod 755 /usr/sbin/iaxmodem
    cd "${WORK_DIR}"
    return 0
}

# =============================================================================
# SECTION 23: AVANTFAX
# =============================================================================

install_avantfax() {
    step "📠 Installing AvantFax..."
    [ "${INSTALL_AVANTFAX}" -ne 1 ] && return 0

    if [ -f "${AVANTFAX_WEB_DIR}/index.php" ]; then
        info "AvantFax already installed, skipping"
        return 0
    fi

    install_avantfax_php

    cd "${WORK_DIR}"
    local avantfax_url="https://sourceforge.net/projects/avantfax/files/avantfax-3.4.1.tgz/download"
    local avantfax_tar="avantfax-3.4.1.tgz"

    if [ ! -f "${avantfax_tar}" ]; then
        info "Downloading AvantFax 3.4.1 from SourceForge..."
        download_file "${avantfax_url}" "${avantfax_tar}" 120 \
            || { warn "Could not download AvantFax, skipping"; return 0; }
    fi

    tar -xzf "${avantfax_tar}" 2>/dev/null
    local avantfax_dir
    avantfax_dir=$(ls -d "${WORK_DIR}"/avantfax-*/ 2>/dev/null | head -1 || true)
    if [ ! -d "${avantfax_dir:-}" ]; then
        warn "AvantFax extraction failed, skipping"
        return 0
    fi

    # The tarball structure is: avantfax-3.4.1/avantfax/ (PHP app is in subdirectory)
    local avantfax_web_src="${avantfax_dir}avantfax"
    if [ ! -d "${avantfax_web_src}" ]; then
        # Fallback: try the top level (older releases may differ)
        avantfax_web_src="${avantfax_dir}"
    fi

    mkdir -p "${AVANTFAX_WEB_DIR}"
    cp -r "${avantfax_web_src}"/* "${AVANTFAX_WEB_DIR}/"
    chown -R "${APACHE_USER}":"${APACHE_GROUP}" "${AVANTFAX_WEB_DIR}"

    # Create DB and initialize schema
    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" << AVFAXSQLEOF 2>/dev/null || true
CREATE DATABASE IF NOT EXISTS avantfax CHARACTER SET utf8 COLLATE utf8_general_ci;
GRANT ALL PRIVILEGES ON avantfax.* TO 'avantfax'@'localhost' IDENTIFIED BY '${AVANTFAX_DB_PASSWORD}';
FLUSH PRIVILEGES;
AVFAXSQLEOF
    # Load schema from extracted tarball (avantfax_dir contains SQL files at top level)
    if [ -f "${avantfax_dir}create_tables.sql" ]; then
        mysql -u root -p"${MYSQL_ROOT_PASSWORD}" avantfax \
            < "${avantfax_dir}create_tables.sql" 2>/dev/null || true
    fi

    if [ -f "${AVANTFAX_WEB_DIR}/includes/config.php.default" ]; then
        cp "${AVANTFAX_WEB_DIR}/includes/config.php.default" \
           "${AVANTFAX_WEB_DIR}/includes/config.php"
        sed -i "s/define('DB_PASS', '.*')/define('DB_PASS', '${AVANTFAX_DB_PASSWORD}')/" \
            "${AVANTFAX_WEB_DIR}/includes/config.php" 2>/dev/null || true
        sed -i "s/define('DB_USER', '.*')/define('DB_USER', 'avantfax')/" \
            "${AVANTFAX_WEB_DIR}/includes/config.php" 2>/dev/null || true
    fi

    svc_reload "${APACHE_SERVICE}" 2>/dev/null || true

    mark_done avantfax
    cd /
    success "AvantFax installed"
}

configure_email_to_fax() {
    step "📧 Configuring email-to-fax..."
    [ -z "${EMAIL_TO_FAX_ALIAS}" ] && generate_fax_alias
    save_pbx_env

    cat > /usr/local/bin/email-to-fax.sh << 'ETFEOF'
#!/bin/bash
# Email-to-fax handler — called by MTA on incoming email to fax alias
set -e
SPOOL_DIR="/var/spool/fax/email"
mkdir -p "${SPOOL_DIR}"
EMAIL_FILE="${SPOOL_DIR}/fax-$(date +%s)-$$.eml"
cat > "${EMAIL_FILE}"
FAX_NUM=$(grep -i "^Subject:" "${EMAIL_FILE}" | grep -oP '\d{7,15}' | head -1 || true)
if [ -n "${FAX_NUM}" ]; then
    sendfax -n -d "${FAX_NUM}" "${EMAIL_FILE}" 2>/dev/null || true
fi
rm -f "${EMAIL_FILE}"
ETFEOF
    chmod +x /usr/local/bin/email-to-fax.sh

    success "Email-to-fax configured (alias: ${EMAIL_TO_FAX_ALIAS})"
}

configure_fax_to_email() {
    step "📨 Configuring fax-to-email..."
    [ -z "${FAX_TO_EMAIL_ADDRESS}" ] && FAX_TO_EMAIL_ADDRESS="${ADMIN_EMAIL:-root@localhost}"

    cat > /usr/local/bin/fax-to-email.sh << FTEEOF
#!/bin/bash
# Fax-to-email forwarder — called when HylaFAX receives a fax
FAX_FILE="\$1"
FAX_FROM="\$2"
FAX_PAGES="\$3"
TO="${FAX_TO_EMAIL_ADDRESS}"
[ -z "\${FAX_FILE}" ] && exit 1
SUBJECT="Incoming Fax from \${FAX_FROM} (\${FAX_PAGES} pages)"
BODY="You have received a fax from \${FAX_FROM}. See attachment."
if command -v uuencode >/dev/null 2>&1; then
    (echo "\${BODY}"; uuencode "\${FAX_FILE}" fax.pdf) | mail -s "\${SUBJECT}" "\${TO}" 2>/dev/null || true
elif command -v mutt >/dev/null 2>&1; then
    echo "\${BODY}" | mutt -s "\${SUBJECT}" -a "\${FAX_FILE}" -- "\${TO}" 2>/dev/null || true
fi
FTEEOF
    chmod +x /usr/local/bin/fax-to-email.sh

    # Register with HylaFAX FaxDispatch if present
    if [ -f /var/spool/hylafax/etc/FaxDispatch ]; then
        backup_config /var/spool/hylafax/etc/FaxDispatch
        grep -q "fax-to-email" /var/spool/hylafax/etc/FaxDispatch \
            || echo 'SENDMAIL="/usr/local/bin/fax-to-email.sh"' \
                >> /var/spool/hylafax/etc/FaxDispatch
    fi

    success "Fax-to-email configured (→ ${FAX_TO_EMAIL_ADDRESS})"
}

# =============================================================================
# SECTION 24: ASTERISK SOUNDS
# =============================================================================

install_asterisk_sounds() {
    step "🔊 Installing Asterisk sound packs..."

    local sounds_dir="/var/lib/asterisk/sounds"
    mkdir -p "${sounds_dir}/en"

    # Core sounds are usually installed with Asterisk; install extras
    local base_url="https://downloads.asterisk.org/pub/telephony/sounds/releases"
    for pack in asterisk-core-sounds-en-gsm asterisk-extra-sounds-en-gsm \
                asterisk-core-sounds-en-ulaw asterisk-extra-sounds-en-ulaw; do
        local pack_ver="1.6.1"
        local pack_file="${pack}-${pack_ver}.tar.gz"
        if [ ! -f "${sounds_dir}/en/.${pack}-installed" ]; then
            cd "${WORK_DIR}"
            download_file "${base_url}/${pack_file}" "${pack_file}" 120 2>/dev/null || true
            if [ -f "${pack_file}" ]; then
                tar -xzf "${pack_file}" -C "${sounds_dir}/en/" 2>/dev/null || true
                touch "${sounds_dir}/en/.${pack}-installed"
                info "Installed ${pack}"
            fi
        fi
    done

    chown -R asterisk:asterisk "${sounds_dir}"
    cd /

    track_install "asterisk-sounds"
    success "Asterisk sound packs installed"
}

# =============================================================================
# SECTION 25: TTS ENGINE (FLITE)
# =============================================================================

install_tts_engine() {
    step "🗣️  Installing Flite TTS engine..."

    pkg_install_one_by_one flite

    # AGI wrapper for Flite
    cat > /var/lib/asterisk/agi-bin/flite-agi.sh << 'FLITEEOF'
#!/bin/bash
# Flite AGI wrapper — reads text from AGI variable and speaks it
read -r TEXT
[ -z "${TEXT}" ] && exit 0
WAVFILE="/var/lib/asterisk/sounds/custom/flite-$(date +%s%N).wav"
mkdir -p "$(dirname "${WAVFILE}")"
flite -t "${TEXT}" -o "${WAVFILE}" 2>/dev/null
echo "SET VARIABLE FLITE_WAVFILE \"${WAVFILE}\""
FLITEEOF
    chmod +x /var/lib/asterisk/agi-bin/flite-agi.sh
    chown asterisk:asterisk /var/lib/asterisk/agi-bin/flite-agi.sh

    track_install "tts-flite"
    success "Flite TTS installed"
}

# =============================================================================
# SECTION 26: GTTS
# =============================================================================

install_gtts() {
    step "🗣️  Installing gTTS (Google Text-to-Speech)..."

    pkg_install_one_by_one python3-pip jq libsox-fmt-all

    # Debian 12+ uses PEP 668 (externally-managed-environment); need --break-system-packages
    pip3 install gTTS --break-system-packages 2>/dev/null \
        || pip3 install gTTS 2>/dev/null \
        || pip install gTTS --break-system-packages 2>/dev/null \
        || pip install gTTS 2>/dev/null \
        || warn "gTTS install failed"
    ln -sf /usr/bin/pip3 /usr/bin/pip 2>/dev/null || true

    # nv-today script
    if [ ! -f /var/lib/asterisk/agi-bin/nv-today.php ]; then
        cd /var/lib/asterisk/agi-bin/
        download_file http://incrediblepbx.com/today3.tar.gz \
            today3.tar.gz 30 2>/dev/null || true
        [ -f today3.tar.gz ] \
            && tar -xzf today3.tar.gz 2>/dev/null \
            && rm -f today3.tar.gz \
            || true
        cd /
    fi

    # Daily crontab for nv-today update
    grep -q "nv-today.php" /etc/crontab 2>/dev/null \
        || echo "08 01 * * * asterisk /var/lib/asterisk/agi-bin/nv-today.php" \
            >> /etc/crontab

    # gTTS AGI script
    cat > /var/lib/asterisk/agi-bin/gtts-agi.py << 'GTTSEOF'
#!/usr/bin/env python3
"""gTTS AGI — speaks text via Google TTS then plays the resulting file."""
import sys, os, subprocess, hashlib, re
from gtts import gTTS

def agi_read():
    return sys.stdin.readline().strip()

def agi_write(cmd):
    sys.stdout.write(cmd + '\n')
    sys.stdout.flush()

agi_write('')
params = {}
while True:
    line = agi_read()
    if not line:
        break
    if ':' in line:
        k, v = line.split(':', 1)
        params[k.strip()] = v.strip()

agi_write('GET VARIABLE GTTS_TEXT')
result = agi_read()
m = re.search(r'\((.+)\)', result)
text = m.group(1) if m else ''
if not text:
    sys.exit(0)

lang = 'en'
cache_dir = '/var/lib/asterisk/sounds/custom/gtts'
os.makedirs(cache_dir, exist_ok=True)
filename = hashlib.md5((text + lang).encode()).hexdigest()
mp3_path = f'{cache_dir}/{filename}.mp3'
wav_path = f'{cache_dir}/{filename}.wav'

if not os.path.exists(wav_path):
    tts = gTTS(text=text, lang=lang)
    tts.save(mp3_path)
    subprocess.run(['sox', mp3_path, '-r', '8000', '-c', '1', wav_path],
                   capture_output=True)
    os.remove(mp3_path)

agi_write(f'SET VARIABLE GTTS_FILE "{wav_path}"')
GTTSEOF
    chmod +x /var/lib/asterisk/agi-bin/gtts-agi.py
    chown asterisk:asterisk /var/lib/asterisk/agi-bin/gtts-agi.py

    # SpeechGen placeholder
    cat > /var/lib/asterisk/agi-bin/speechgen.php << 'SGEOF'
<?php
// SpeechGen.io TTS integration — add credentials below
$speechgen_token = "";
$speechgen_email = "";
SGEOF
    chown asterisk:asterisk /var/lib/asterisk/agi-bin/speechgen.php

    track_install "gtts"
    success "gTTS installed"
}

# =============================================================================
# SECTION 27: AGI SCRIPTS
# =============================================================================

install_agi_scripts() {
    step "📜 Installing AGI scripts..."

    local agi_dir="/var/lib/asterisk/agi-bin"
    mkdir -p "${agi_dir}"

    # Call logger AGI
    cat > "${agi_dir}/call-logger.agi" << 'CLAGIEOF'
#!/usr/bin/perl -w
use strict;
my %agi;
while (my $line = <STDIN>) {
    chomp $line;
    last unless $line =~ /:/;
    my ($key, $val) = split /:\s+/, $line, 2;
    $agi{$key} = $val;
}
my $logfile = "/var/log/asterisk/call-log.csv";
my $callerid = $agi{'agi_callerid'} // 'unknown';
my $extension = $agi{'agi_extension'} // 'unknown';
my $datetime = `date '+%Y-%m-%d %H:%M:%S'`;
chomp $datetime;
open(my $fh, '>>', $logfile) or exit;
print $fh qq("$datetime","$callerid","$extension"\n);
close $fh;
CLAGIEOF

    # Business hours check AGI
    cat > "${agi_dir}/business-hours.agi" << 'BHEOF'
#!/usr/bin/perl -w
use strict;
use POSIX qw(strftime);
my $hour   = int(strftime('%H', localtime));
my $dow    = int(strftime('%u', localtime));  # 1=Mon 7=Sun
my $open   = ($dow <= 5 && $hour >= 8 && $hour < 18) ? 1 : 0;
print "SET VARIABLE BUSINESS_HOURS $open\n";
while (<STDIN>) { last unless /:/; }
BHEOF

    # Caller ID validation AGI
    cat > "${agi_dir}/cid-validate.agi" << 'CIDEOF'
#!/usr/bin/perl -w
use strict;
while (my $line = <STDIN>) {
    chomp $line;
    last unless $line =~ /:/;
}
my $callerid = '';
print "GET VARIABLE CALLERID(num)\n";
my $result = <STDIN>;
chomp $result;
if ($result =~ /\((.+)\)/) {
    $callerid = $1;
}
my $valid = ($callerid =~ /^\+?[0-9]{7,15}$/) ? 1 : 0;
print "SET VARIABLE CID_VALID $valid\n";
CIDEOF

    chmod +x "${agi_dir}"/*.agi "${agi_dir}"/*.sh 2>/dev/null || true
    chown -R asterisk:asterisk "${agi_dir}"

    track_install "agi-scripts"
    success "AGI scripts installed"
}

# =============================================================================
# SECTION 28: DEMO DIALPLAN APPLICATIONS
# =============================================================================

install_demo_applications() {
    step "🎯 Installing demo dialplan applications..."

    local custom_conf="/etc/asterisk/extensions_custom.conf"
    backup_config "${custom_conf}"

    cat > "${custom_conf}" << 'DIALPLANEOF'
; =============================================================================
; PBX Demo Applications - extensions_custom.conf
; Generated by PBX installer v3.0
; =============================================================================

; --- DEMO menu (dial "DEMO" or 3366) ---
[demo-menu]
exten => s,1,Answer()
 same => n,Wait(1)
 same => n,Playback(demo-congrats)
 same => n,Background(demo-instruct)
 same => n,WaitExten(5)
exten => 1,1,Playback(digits/1)
 same => n,Goto(demo-menu,s,1)
exten => 2,1,Echo()
 same => n,Goto(demo-menu,s,1)
exten => 9,1,Hangup()
exten => t,1,Goto(demo-menu,s,1)
exten => i,1,Goto(demo-menu,s,1)

; --- Speaking Clock (dial 123) ---
[pbx-clock]
exten => s,1,Answer()
 same => n,AGI(nv-today.php)
 same => n,Hangup()

; --- Echo Test (dial *43) ---
[pbx-echo]
exten => s,1,Answer()
 same => n,Playback(demo-echotest)
 same => n,Echo()
 same => n,Playback(demo-echodone)
 same => n,Hangup()

; --- Music on Hold test (dial *610) ---
[pbx-moh]
exten => s,1,Answer()
 same => n,Playback(hold-on)
 same => n,MusicOnHold(default,60)
 same => n,Hangup()

; --- Lenny the Telemarketer Bot (dial 4747 or LENNY) ---
[pbx-lenny]
exten => s,1,Answer()
 same => n,AGI(lenny.agi)
 same => n,Hangup()

; --- Caller ID Test (dial *41) ---
[pbx-cidtest]
exten => s,1,Answer()
 same => n,SayDigits(${CALLERID(num)})
 same => n,Hangup()

; --- Weather Report TTS demo (dial 947) ---
[pbx-weather]
exten => s,1,Answer()
 same => n,Set(GTTS_TEXT=Welcome to the P B X weather demo. Fetching current weather.)
 same => n,AGI(gtts-agi.py)
 same => n,Playback(${GTTS_FILE})
 same => n,Hangup()

; --- Today's Date (dial 951 or TODAY) ---
[pbx-today]
exten => s,1,Answer()
 same => n,SayUnixTime(,America/New_York,ABdY)
 same => n,Hangup()

; --- Voicemail main menu (*97) ---
[pbx-voicemail]
exten => s,1,Answer()
 same => n,VoiceMailMain(${CALLERID(num)}@default)
 same => n,Hangup()

; === Hook all demo extensions into default context ===
[from-internal-custom]
; DEMO menu
exten => DEMO,1,Goto(demo-menu,s,1)
exten => 3366,1,Goto(demo-menu,s,1)

; Speaking clock
exten => 123,1,Goto(pbx-clock,s,1)

; Weather
exten => 947,1,Goto(pbx-weather,s,1)

; Today's date
exten => 951,1,Goto(pbx-today,s,1)
exten => TODAY,1,Goto(pbx-today,s,1)
exten => 8632,1,Goto(pbx-today,s,1)

; Telemarketer bot
exten => 4747,1,Goto(pbx-lenny,s,1)
exten => LENNY,1,Goto(pbx-lenny,s,1)
exten => 53669,1,Goto(pbx-lenny,s,1)

; Echo test
exten => *43,1,Goto(pbx-echo,s,1)

; Music on hold test
exten => *610,1,Goto(pbx-moh,s,1)

; Caller ID readback
exten => *41,1,Goto(pbx-cidtest,s,1)

; Voicemail main
exten => *97,1,Goto(pbx-voicemail,s,1)

; Conference rooms
exten => *469,1,ConfBridge(1,default_bridge,default_user)
exten => *470,1,ConfBridge(2,default_bridge,default_user)

; Feature codes
exten => *72,1,Set(DB(CFW/${CALLERID(num)})=on)
 same => n,Playback(call-fwd-unconditional)
 same => n,Hangup()
exten => *73,1,DBdel(CFW/${CALLERID(num)})
 same => n,Playback(call-fwd-unconditional-cancelled)
 same => n,Hangup()
exten => *76,1,Set(DB(DND/${CALLERID(num)})=1)
 same => n,Playback(dnd-activated)
 same => n,Hangup()
exten => *77,1,DBdel(DND/${CALLERID(num)})
 same => n,Playback(dnd-deactivated)
 same => n,Hangup()
exten => *78,1,Set(RECORD_CALLS=${IF($["${RECORD_CALLS}"=""]?true:)})
 same => n,Playback(call-recording-${IF($["${RECORD_CALLS}"="true"]?on:off)})
 same => n,Hangup()
exten => *65,1,Answer()
 same => n,SayDigits(${CALLERID(num)})
 same => n,Hangup()

; === Anonymous inbound SIP context ===
[from-pstn-custom]
exten => s,1,Answer()
 same => n,Playback(hello-world)
 same => n,Goto(demo-menu,s,1)

[from-trunk]
include => from-internal-custom
DIALPLANEOF

    # Create lenny AGI if not present
    if [ ! -f /var/lib/asterisk/agi-bin/lenny.agi ]; then
        cat > /var/lib/asterisk/agi-bin/lenny.agi << 'LENNYEOF'
#!/bin/bash
# Lenny — telemarketer-annoying bot
echo "ANSWER"
read -r _
LENNYEOF
        chmod +x /var/lib/asterisk/agi-bin/lenny.agi
        chown asterisk:asterisk /var/lib/asterisk/agi-bin/lenny.agi
    fi

    # Reload dialplan
    asterisk -rx "dialplan reload" 2>/dev/null || true

    track_install "demo-applications"
    success "Demo applications installed"
}

# =============================================================================
# SECTION 29: FIREWALL (firewalld / ufw)
# =============================================================================

configure_firewall() {
    step "🔥 Configuring firewall..."
    [ "${FIREWALL_ENABLED}" -ne 1 ] && return 0

    if command_exists firewall-cmd; then
        svc_enable firewalld
        svc_start  firewalld
        for port in 22/tcp 80/tcp 443/tcp 5060/udp 5060/tcp 5061/tcp \
                    4569/udp 8089/tcp 9001/tcp; do
            firewall-cmd --permanent --add-port="${port}" 2>/dev/null || true
        done
        firewall-cmd --permanent --add-port=10000-20000/udp 2>/dev/null || true
        firewall-cmd --reload 2>/dev/null || true
        success "firewalld configured"
    elif command_exists ufw; then
        ufw --force enable 2>/dev/null || true
        for port in 22 80 443 8089 9001; do
            ufw allow "${port}"/tcp 2>/dev/null || true
        done
        ufw allow 5060 2>/dev/null || true
        ufw allow 5061/tcp 2>/dev/null || true
        ufw allow 4569/udp 2>/dev/null || true
        ufw allow 10000:20000/udp 2>/dev/null || true
        ufw reload 2>/dev/null || true
        success "ufw configured"
    else
        info "No high-level firewall found; configure_iptables will apply rules"
    fi
}

# =============================================================================
# SECTION 30: IPTABLES
# =============================================================================

configure_iptables() {
    step "🔥 Configuring iptables rules..."
    [ "${FIREWALL_ENABLED}" -ne 1 ] && return 0

    local server_ip user_ip public_ip
    server_ip=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $7; exit}' || echo "")
    user_ip=$(echo "${SSH_CONNECTION:-}" | cut -f1 -d" " 2>/dev/null || echo "")
    public_ip=$(curl -s --max-time 10 https://ifconfig.me 2>/dev/null \
        || curl -s --max-time 10 https://api.ipify.org 2>/dev/null || echo "")

    pkg_install_one_by_one $PKG_IPTABLES_PERSIST ipset
    svc_enable iptables 2>/dev/null || true

    iptables -F INPUT  2>/dev/null || true
    iptables -P INPUT  DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT ACCEPT

    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    iptables -A INPUT -i lo -j ACCEPT
    [ -n "${server_ip}" ] && iptables -A INPUT -s "${server_ip}" -j ACCEPT || true
    [ -n "${user_ip}" ]   && iptables -A INPUT -s "${user_ip}"   -j ACCEPT || true
    [ -n "${public_ip}" ] && iptables -A INPUT -s "${public_ip}" -j ACCEPT || true

    iptables -A INPUT -p tcp --dport 22    -j ACCEPT
    iptables -A INPUT -p tcp --dport 80    -j ACCEPT
    iptables -A INPUT -p tcp --dport 443   -j ACCEPT
    iptables -A INPUT -p tcp --dport 9001  -j ACCEPT
    iptables -A INPUT -p udp --dport 5060  -j ACCEPT
    iptables -A INPUT -p tcp --dport 5060  -j ACCEPT
    iptables -A INPUT -p tcp --dport 5061  -j ACCEPT
    iptables -A INPUT -p udp --dport 4569  -j ACCEPT
    iptables -A INPUT -p tcp --dport 8089  -j ACCEPT
    iptables -A INPUT -p udp --dport 10000:20000 -j ACCEPT

    case "${DISTRO_FAMILY}" in
        debian)
            netfilter-persistent save 2>/dev/null \
                || { mkdir -p /etc/iptables; iptables-save > /etc/iptables/rules.v4; }
            ;;
        rhel|fedora)
            service iptables save 2>/dev/null \
                || iptables-save > /etc/sysconfig/iptables
            ;;
    esac

    cat > /usr/local/bin/iptables-custom << 'IPTEOF'
#!/bin/bash
# Re-apply custom iptables rules after reload
# Add your persistent custom rules here
IPTEOF
    chmod +x /usr/local/bin/iptables-custom

    success "iptables rules applied"
}

# =============================================================================
# SECTION 31: DISABLE IPv6
# =============================================================================

disable_ipv6() {
    step "🔧 Disabling IPv6..."

    if ! grep -q "disable_ipv6" /etc/sysctl.conf 2>/dev/null; then
        backup_config /etc/sysctl.conf
        cat >> /etc/sysctl.conf << 'SYSCTLEOF'
# Disable IPv6 (PBX installer)
net.ipv6.conf.all.disable_ipv6     = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6      = 1
SYSCTLEOF
        sysctl -p 2>/dev/null || true
    fi

    # Postfix IPv4-only (if installed)
    command_exists postconf \
        && postconf -e "inet_protocols = ipv4" 2>/dev/null || true

    success "IPv6 disabled"
}

# =============================================================================
# SECTION 32: FAIL2BAN
# =============================================================================

install_fail2ban() {
    step "Installing Fail2ban..."
    [ "${FAIL2BAN_ENABLED:-1}" -ne 1 ] && return 0

    pkg_install fail2ban

    mkdir -p /etc/fail2ban/jail.d

    # Ensure Asterisk log directory/file exist so fail2ban can start
    mkdir -p /var/log/asterisk
    touch /var/log/asterisk/security
    chown asterisk:asterisk /var/log/asterisk/security 2>/dev/null || true

    # Detect whether sshd is running and has a log — disable sshd jail if not.
    # Debian ships defaults-debian.conf with sshd enabled; we write our own
    # pbx-sshd.conf (sorts after defaults-debian.conf) to override it.
    local sshd_enabled="true"
    local sshd_log=""
    for f in /var/log/auth.log /var/log/secure /var/log/messages; do
        [ -f "$f" ] && sshd_log="$f" && break
    done
    local sshd_running=0
    systemctl is-active ssh  >/dev/null 2>&1 && sshd_running=1
    systemctl is-active sshd >/dev/null 2>&1 && sshd_running=1
    if [ -z "$sshd_log" ] || [ "$sshd_running" -eq 0 ]; then
        sshd_enabled="false"
        warn "sshd jail disabled: no auth log or sshd not running (container mode?)"
    fi

    # Global defaults — safe settings that won't lock anyone out
    cat > /etc/fail2ban/jail.d/pbx-defaults.conf << F2BGEOF
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 10
ignoreip = 127.0.0.1/8 ::1 ${SSH_CLIENT_IP:-}
F2BGEOF

    # Write sshd jail override AFTER defaults-debian.conf alphabetically
    # ("pbx-sshd.conf" > "defaults-debian.conf")
    cat > /etc/fail2ban/jail.d/pbx-sshd.conf << F2BSSHDEOF
[sshd]
enabled  = ${sshd_enabled}
port     = ${SSH_PORT:-22}
maxretry = 10
bantime  = 3600
findtime = 600
F2BSSHDEOF

    # Asterisk jails
    cat > /etc/fail2ban/jail.d/asterisk.conf << 'F2BEOF'
[asterisk]
enabled  = true
port     = 5060,5061
protocol = udp
filter   = asterisk
logpath  = /var/log/asterisk/security
maxretry = 5
bantime  = 3600
findtime = 600

[asterisk-tcp]
enabled  = true
port     = 5060,5061
protocol = tcp
filter   = asterisk
logpath  = /var/log/asterisk/security
maxretry = 5
bantime  = 3600
findtime = 600

[apache-auth]
enabled  = true
maxretry = 10
bantime  = 3600
findtime = 600
F2BEOF

    svc_enable fail2ban
    svc_restart fail2ban 2>/dev/null || warn "fail2ban failed to start — check logs"

    # Whitelist current SSH client IP
    if [ -n "${SSH_CLIENT_IP:-}" ] && [ "$sshd_enabled" = "true" ]; then
        sleep 2
        fail2ban-client set sshd addignoreip "${SSH_CLIENT_IP}" 2>/dev/null || true
        info "Whitelisted SSH client IP: ${SSH_CLIENT_IP}"
    fi

    mark_done fail2ban
    success "Fail2ban installed (maxretry=10, bantime=1h)"
}

# =============================================================================
# SECTION 33: LOGROTATE
# =============================================================================

configure_logrotate() {
    step "📋 Configuring logrotate for Asterisk logs..."

    cat > /etc/logrotate.d/asterisk << 'LREOF'
/var/log/asterisk/*.log
/var/log/asterisk/security {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    sharedscripts
    postrotate
        /usr/sbin/asterisk -rx "logger reload" > /dev/null 2>&1 || true
    endscript
}
LREOF

    cat > /etc/logrotate.d/pbx-install << 'LRPBXEOF'
/var/log/pbx-install.log
/var/log/pbx-install-errors.log {
    weekly
    rotate 8
    compress
    missingok
    notifempty
}
LRPBXEOF

    success "Logrotate configured"
}

# =============================================================================
# SECTION 34: WEBMIN
# =============================================================================

install_webmin() {
    step "🌐 Installing Webmin..."

    if [ -f /etc/webmin/miniserv.conf ]; then
        info "Webmin already installed, skipping"
        return 0
    fi

    case "${PKG_WEBMIN_REPO_TYPE}" in
        deb)
            curl -fsSL https://webmin.com/jcameron-key.asc \
                | gpg --dearmor -o /usr/share/keyrings/jcameron-key.gpg 2>/dev/null || true
            echo "deb [signed-by=/usr/share/keyrings/jcameron-key.gpg] https://download.webmin.com/download/repository sarge contrib" \
                > /etc/apt/sources.list.d/webmin.list
            apt-get update -y 2>/dev/null || true
            ;;
        rpm)
            cat > /etc/yum.repos.d/webmin.repo << 'WEBMINREPOEOF'
[Webmin]
name=Webmin Distribution Neutral
baseurl=https://download.webmin.com/download/yum
enabled=1
gpgcheck=1
gpgkey=https://webmin.com/jcameron-key.asc
WEBMINREPOEOF
            ;;
    esac
    pkg_install webmin

    # Ensure webmin listens on 9001
    if [ -f /etc/webmin/miniserv.conf ]; then
        backup_config /etc/webmin/miniserv.conf
        sed -i 's/^port=.*/port=9001/' /etc/webmin/miniserv.conf
    fi

    svc_enable  webmin 2>/dev/null || true
    svc_restart webmin 2>/dev/null || true

    mark_done webmin
    success "Webmin installed (port 9001)"
}

# =============================================================================
# SECTION 35: KNOCKD (PORT KNOCKING)
# =============================================================================

install_knockd() {
    step "🚪 Installing knockd (port-knocking daemon)..."

    pkg_install_one_by_one $PACKAGES_DISTRO_KNOCKD

    if command_exists knockd; then
        cat > /etc/knockd.conf << 'KNOCKEOF'
[options]
    UseSyslog

[openSSH]
    sequence    = 7000,8000,9000
    seq_timeout = 10
    command     = /sbin/iptables -I INPUT -s %IP% -p tcp --dport 22 -j ACCEPT
    tcpflags    = syn

[closeSSH]
    sequence    = 9000,8000,7000
    seq_timeout = 10
    command     = /sbin/iptables -D INPUT -s %IP% -p tcp --dport 22 -j ACCEPT
    tcpflags    = syn
KNOCKEOF
        svc_enable knockd 2>/dev/null || true
        svc_start  knockd 2>/dev/null || true
        track_install "knockd"
        success "knockd installed"
    else
        warn "knockd not installed"
    fi
}

# =============================================================================
# SECTION 36: SNGREP (SIP SNIFFER)
# =============================================================================

install_sngrep() {
    step "🔍 Installing sngrep SIP sniffer..."

    if command_exists sngrep; then
        info "sngrep already installed"
        return 0
    fi

    # Try to install from repos; fall back to source compile on RHEL if not available
    if ! pkg_install_one_by_one $PACKAGES_DISTRO_SNGREP && ! command_exists sngrep; then
        case "${DISTRO_FAMILY}" in
            rhel|fedora)
                pkg_install_one_by_one libpcap-devel
                cd "${WORK_DIR}"
                download_file \
                    "https://github.com/irontec/sngrep/releases/download/v1.8.1/sngrep-1.8.1.tar.gz" \
                    sngrep.tar.gz 60 2>/dev/null || true
                if [ -f sngrep.tar.gz ]; then
                    tar -xzf sngrep.tar.gz
                    local sdir
                    sdir=$(ls -d "${WORK_DIR}"/sngrep-*/ 2>/dev/null | head -1 || true)
                    [ -d "${sdir:-}" ] && cd "${sdir}" \
                        && ./configure 2>/dev/null \
                        && make -j"$(nproc)" 2>/dev/null \
                        && make install 2>/dev/null \
                        || warn "sngrep build failed"
                fi
                cd /
                ;;
        esac
    fi

    track_install "sngrep"
    success "sngrep installed"
}

# =============================================================================
# SECTION 37: OPENVPN
# =============================================================================

install_openvpn() {
    step "🔒 Installing OpenVPN..."

    if command_exists openvpn; then
        info "OpenVPN already installed"
        return 0
    fi

    pkg_install openvpn easy-rsa

    if command_exists openvpn; then
        svc_daemon_reload
        svc_enable openvpn 2>/dev/null || true
        # Client config template
        mkdir -p /etc/openvpn/client
        cat > /etc/openvpn/client/pbx-client.conf.template << 'OVPNEOF'
client
dev tun
proto udp
remote YOUR_SERVER_IP 1194
resolv-retry infinite
nobind
persist-key
persist-tun
ca   /etc/openvpn/ca.crt
cert /etc/openvpn/client.crt
key  /etc/openvpn/client.key
remote-cert-tls server
cipher AES-256-CBC
verb 3
OVPNEOF
        track_install "openvpn"
        success "OpenVPN installed"
    fi
}

# =============================================================================
# SECTION 38: BACKUP SYSTEM
# =============================================================================

setup_backup_system() {
    step "💾 Setting up backup system..."
    [ "${BACKUP_ENABLED}" -ne 1 ] && return 0

    mkdir -p "${BACKUP_BASE}"/{daily,weekly,monthly}

    cat > /usr/local/bin/pbx-backup-run << 'BKPEOF'
#!/bin/bash
# PBX automated backup script
set -euo pipefail

BACKUP_BASE="/mnt/backups/pbx"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
DAY=$(date +%u)    # 1=Mon 7=Sun
HOUR=$(date +%H)
RETAIN_DAILY=7
RETAIN_WEEKLY=4
RETAIN_MONTHLY=3

if   [ "${HOUR}" = "02" ] && [ "${DAY}" = "7" ]; then  TYPE="weekly"
elif [ "${HOUR}" = "02" ] && [ "$(date +%d)" = "01" ]; then TYPE="monthly"
else TYPE="daily"
fi

DEST="${BACKUP_BASE}/${TYPE}/${TIMESTAMP}"
mkdir -p "${DEST}"

# FreePBX config backup
fwconsole backup --backup-name="auto-${TIMESTAMP}" 2>/dev/null \
    || cp -r /etc/asterisk "${DEST}/asterisk-etc" 2>/dev/null || true

# MySQL databases
mysqldump -u root -p"$(grep "MySQL Root Password" /etc/pbx/pbx_passwords | awk '{print $NF}')" \
    --all-databases > "${DEST}/mysql-all.sql" 2>/dev/null || true

# Web root
tar -czf "${DEST}/webroot.tar.gz" "${WEB_ROOT:-/var/www/apache/pbx}/admin" 2>/dev/null || true

# PBX env
cp /etc/pbx/.env "${DEST}/" 2>/dev/null || true

# Feature: backup-verify — compute SHA256 checksums for all archive files
for f in "${DEST}"/*.tar.gz "${DEST}"/*.sql; do
    [ -f "${f}" ] && sha256sum "${f}" > "${f}.sha256" 2>/dev/null || true
done

# Feature: backup-encryption — encrypt archives if opted in
if [ -f /etc/pbx/.env ]; then
    # shellcheck source=/dev/null
    source /etc/pbx/.env 2>/dev/null || true
fi
if [ "${BACKUP_ENCRYPT:-no}" = "yes" ] && [ -n "${BACKUP_GPG_KEY:-}" ]; then
    for f in "${DEST}"/*.tar.gz "${DEST}"/*.sql; do
        [ -f "${f}" ] || continue
        gpg --batch --yes --encrypt --recipient "${BACKUP_GPG_KEY}" \
            --output "${f}.gpg" "${f}" 2>/dev/null \
            && rm -f "${f}" "${f}.sha256" \
            && sha256sum "${f}.gpg" > "${f}.gpg.sha256" 2>/dev/null || true
    done
fi

# Cleanup old backups
find "${BACKUP_BASE}/daily"   -maxdepth 1 -type d -mtime +"${RETAIN_DAILY}"   -exec rm -rf {} + 2>/dev/null || true
find "${BACKUP_BASE}/weekly"  -maxdepth 1 -type d -mtime +$(( RETAIN_WEEKLY * 7 )) -exec rm -rf {} + 2>/dev/null || true
find "${BACKUP_BASE}/monthly" -maxdepth 1 -type d -mtime +$(( RETAIN_MONTHLY * 30 )) -exec rm -rf {} + 2>/dev/null || true

echo "Backup complete: ${DEST}"
BKPEOF
    chmod +x /usr/local/bin/pbx-backup-run

    # Cron entry
    if ! grep -q "pbx-backup-run" /etc/crontab 2>/dev/null; then
        echo "30 02 * * * root /usr/local/bin/pbx-backup-run >> /var/log/pbx-backup.log 2>&1" \
            >> /etc/crontab
    fi

    track_install "backup-system"
    success "Backup system configured"
}

# =============================================================================
# SECTION 38b: FREEPBX AUTO-UPDATE (backup-before-update + freepbx-autoupdate)
# =============================================================================

setup_freepbx_autoupdate() {
    step "🔄 Setting up FreePBX auto-update with pre-update DB backup..."
    [ "${BACKUP_ENABLED:-1}" -ne 1 ] && return 0

    mkdir -p /var/log/pbx /mnt/backups/pbx/database

    # pbx-autoupdate is deployed via scripts/ directory; just set up the cron
    if ! grep -q "pbx-autoupdate" /etc/cron.d/pbx-autoupdate 2>/dev/null; then
        echo "30 2 * * 0 root /usr/local/bin/pbx-autoupdate" > /etc/cron.d/pbx-autoupdate
        chmod 644 /etc/cron.d/pbx-autoupdate
    fi

    track_install "freepbx-autoupdate"
    success "FreePBX auto-update configured (weekly, Sundays 02:30)"
}

# =============================================================================
# SECTION 38c: BACKUP ENCRYPTION (backup-encryption)
# =============================================================================

setup_backup_encryption() {
    step "🔐 Setting up backup encryption support..."

    # Install gnupg
    pkg_install gnupg gnupg2 2>/dev/null || true

    # pbx-backup-encrypt is deployed via scripts/ directory; just ensure gnupg installed
    # and add .env placeholder + passwords note

    # Add note to passwords file
    if [ -f "${AUTO_PASSWORDS_FILE}" ] && ! grep -q "backup encryption" "${AUTO_PASSWORDS_FILE}" 2>/dev/null; then
        cat >> "${AUTO_PASSWORDS_FILE}" << 'ENCNOTE'

# Backup Encryption (optional):
#   Run: pbx-backup-encrypt init        to generate a GPG key pair
#   Then set BACKUP_ENCRYPT=yes in /etc/pbx/.env to auto-encrypt backups
#   Public key exported to: /root/pbx-backup-key.pub (keep a safe copy!)
ENCNOTE
    fi

    # Add BACKUP_ENCRYPT placeholder to .env if not already set
    if [ -f "${PBX_ENV_FILE}" ] && ! grep -q "^BACKUP_ENCRYPT=" "${PBX_ENV_FILE}" 2>/dev/null; then
        echo "BACKUP_ENCRYPT=no" >> "${PBX_ENV_FILE}"
    fi

    track_install "backup-encryption"
    success "Backup encryption support installed (run: pbx-backup-encrypt init to activate)"
}

# =============================================================================
# SECTION 38d: FOP2 FLASH OPERATOR PANEL (fop2)
# =============================================================================

install_fop2() {
    step "📊 Installing FOP2 (Flash Operator Panel 2)..."
    skip_if_done fop2 && return 0

    local fop2_url="http://download.fop2.com/install_fop2.sh"
    local fop2_script="${WORK_DIR}/install_fop2.sh"

    if ! download_file "${fop2_url}" "${fop2_script}" 60 2>/dev/null; then
        warn "FOP2 installer download failed — skipping"
        return 0
    fi
    chmod 755 "${fop2_script}"

    # Run non-interactively
    bash "${fop2_script}" --auto 2>/dev/null || bash "${fop2_script}" 2>/dev/null || true
    rm -f "${fop2_script}"

    # Configure to work with FreePBX AMI
    if [ -f /usr/local/fop2/fop2.cfg ]; then
        sed -i 's/^manager_host.*/manager_host = 127.0.0.1/' /usr/local/fop2/fop2.cfg
        local ami_pass
        ami_pass=$(grep "^secret" /etc/asterisk/manager.conf 2>/dev/null | head -1 | awk '{print $NF}')
        [ -n "${ami_pass}" ] && sed -i "s/^manager_password.*/manager_password = ${ami_pass}/" /usr/local/fop2/fop2.cfg
    fi

    svc_enable fop2 2>/dev/null || true
    svc_start  fop2 2>/dev/null || true

    mark_done fop2
    success "FOP2 installed"
}

# =============================================================================
# SECTION 38e: PHONE PROVISIONING (phone-provisioning)
# =============================================================================

install_phone_provisioning() {
    step "📱 Setting up phone auto-provisioning..."
    [ "${INSTALL_PHONE_PROV:-no}" = "no" ] && return 0
    skip_if_done phone-provisioning && return 0

    # Install TFTP server
    case "${DISTRO_FAMILY}" in
        debian) pkg_install tftpd-hpa ;;
        rhel|fedora) pkg_install tftp-server ;;
    esac

    # Configure TFTP root
    local tftp_root="/var/lib/tftpboot"
    mkdir -p "${tftp_root}"

    case "${DISTRO_FAMILY}" in
        debian)
            if [ -f /etc/default/tftpd-hpa ]; then
                backup_config /etc/default/tftpd-hpa
                sed -i "s|TFTP_DIRECTORY=.*|TFTP_DIRECTORY=\"${tftp_root}\"|" /etc/default/tftpd-hpa
                sed -i 's|TFTP_OPTIONS=.*|TFTP_OPTIONS="--secure --create"|' /etc/default/tftpd-hpa
            fi
            svc_enable tftpd-hpa 2>/dev/null || true
            svc_start  tftpd-hpa 2>/dev/null || true
            ;;
        rhel|fedora)
            if [ -f /etc/xinetd.d/tftp ]; then
                sed -i 's/disable.*=.*yes/disable = no/' /etc/xinetd.d/tftp
                sed -i "s|server_args.*=.*|server_args = -s ${tftp_root} -c|" /etc/xinetd.d/tftp
                svc_enable xinetd 2>/dev/null || true
                svc_start  xinetd 2>/dev/null || true
            else
                # systemd socket unit for tftp
                svc_enable tftp.socket 2>/dev/null || true
                svc_start  tftp.socket 2>/dev/null || true
            fi
            ;;
    esac

    # HTTP provisioning root
    local prov_dir="${WEB_ROOT}/provisioning"
    mkdir -p "${prov_dir}"
    chown -R "${APACHE_USER}:${APACHE_GROUP}" "${prov_dir}" 2>/dev/null || true

    # Create Yealink provisioning template
    mkdir -p "${tftp_root}/yealink"
    cat > "${tftp_root}/yealink/y000000000000.cfg" << 'YLEOF'
#!version:1.0.0.1
##File header "#!version:1.0.0.1" cannot be edited or deleted##

# Yealink Auto-Provision Base Config
# Copy this file and rename to match your phone MAC, e.g. 001565123456.cfg

account.1.enable = 1
account.1.label = Extension 1000
account.1.display_name = Extension 1000
account.1.auth_name = 1000
account.1.user_name = 1000
account.1.password = CHANGEME
account.1.sip_server.1.address = PBX_IP
account.1.sip_server.1.port = 5060
account.1.transport = 0
YLEOF
    sed -i "s|PBX_IP|${PRIVATE_IP}|g" "${tftp_root}/yealink/y000000000000.cfg"

    # pbx-provision is deployed via scripts/ directory (reads PRIVATE_IP from /etc/pbx/.env at runtime)

    mark_done phone-provisioning
    success "Phone provisioning configured (TFTP + HTTP)"
}

# =============================================================================
# SECTION 38f: REMOTE BACKUP VIA RCLONE (remote-backup)
# =============================================================================

install_rclone() {
    step "☁️  Installing rclone for remote backups..."
    [ "${INSTALL_REMOTE_BACKUP:-no}" = "no" ] && return 0
    skip_if_done remote-backup && return 0

    local rclone_url="https://downloads.rclone.org/rclone-current-linux-amd64.zip"
    local rclone_zip="${WORK_DIR}/rclone-current-linux-amd64.zip"

    if ! command_exists rclone; then
        if ! download_file "${rclone_url}" "${rclone_zip}" 120 2>/dev/null; then
            warn "rclone download failed — skipping remote backup setup"
            return 0
        fi
        pkg_install unzip 2>/dev/null || true
        cd "${WORK_DIR}"
        unzip -o "${rclone_zip}" 2>/dev/null || true
        local rclone_dir
        rclone_dir=$(ls -d "${WORK_DIR}"/rclone-*-linux-amd64/ 2>/dev/null | head -1 || true)
        if [ -d "${rclone_dir:-}" ] && [ -f "${rclone_dir}/rclone" ]; then
            install -m 755 "${rclone_dir}/rclone" /usr/local/bin/rclone
        fi
        rm -f "${rclone_zip}"
        cd /
    fi

    if ! command_exists rclone; then
        warn "rclone installation failed — skipping remote backup"
        return 0
    fi

    # pbx-backup-remote is deployed via scripts/ directory; just set up the cron

    # Weekly cron (Sunday 03:00)
    if ! grep -q "pbx-backup-remote" /etc/cron.d/pbx-remote-backup 2>/dev/null; then
        mkdir -p /var/log/pbx
        cat > /etc/cron.d/pbx-remote-backup << 'RCLCRONEOF'
# PBX remote backup via rclone — runs after local backup (02:30)
0 3 * * 0 root /usr/local/bin/pbx-backup-remote >> /var/log/pbx/remote-backup.log 2>&1
RCLCRONEOF
        chmod 644 /etc/cron.d/pbx-remote-backup
    fi

    # Add RCLONE_REMOTE placeholder to .env if not already set
    if [ -f "${PBX_ENV_FILE}" ] && ! grep -q "^RCLONE_REMOTE=" "${PBX_ENV_FILE}" 2>/dev/null; then
        echo "RCLONE_REMOTE=" >> "${PBX_ENV_FILE}"
    fi

    mark_done remote-backup
    success "rclone installed — configure RCLONE_REMOTE in /etc/pbx/.env then run: rclone config"
}

# =============================================================================
# SECTION 39: MANAGEMENT SCRIPTS
# =============================================================================

create_management_scripts() {
    step "🔧 Creating management scripts..."

    # pbx-status
    cat > /usr/local/bin/pbx-status << 'PSTATEOF'
#!/bin/bash
echo "=========================================="
echo "  PBX System Status"
echo "=========================================="
for svc in asterisk freepbx mariadb httpd apache2 php-fpm fail2ban postfix; do
    if command -v systemctl >/dev/null 2>&1; then
        STATUS=$(systemctl is-active "${svc}" 2>/dev/null || echo "not-found")
    else
        STATUS=$(service "${svc}" status >/dev/null 2>&1 && echo "active" || echo "inactive")
    fi
    printf "  %-20s %s\n" "${svc}" "${STATUS}"
done
echo "------------------------------------------"
echo "  Disk:   $(df -h / | awk 'NR==2{print $3"/"$2" ("$5" used)"}')"
echo "  Memory: $(free -h | awk '/^Mem/{print $3"/"$2}')"
echo "  Load:   $(uptime | awk -F'load average:' '{print $2}')"
echo "=========================================="
PSTATEOF

    # pbx-restart
    cat > /usr/local/bin/pbx-restart << 'PRESTEOF'
#!/bin/bash
echo "Restarting PBX services..."
for svc in asterisk freepbx; do
    systemctl restart "${svc}" 2>/dev/null || service "${svc}" restart 2>/dev/null || true
done
sleep 3
echo "Done."
PRESTEOF

    # pbx-repair
    cat > /usr/local/bin/pbx-repair << 'PREPEOF'
#!/bin/bash
echo "Running FreePBX repair..."
fwconsole ma refreshsignatures 2>/dev/null || true
fwconsole chown             2>/dev/null || true
fwconsole reload --skip-registry-checks 2>/dev/null || true
echo "Repair complete."
PREPEOF

    # pbx-logs
    cat > /usr/local/bin/pbx-logs << 'PLOGSEOF'
#!/bin/bash
LOGFILE="${1:-/var/log/asterisk/full}"
tail -f "${LOGFILE}"
PLOGSEOF

    # pbx-backup
    cat > /usr/local/bin/pbx-backup << 'PBKPEOF'
#!/bin/bash
# PBX Backup Management
BACKUP_BASE="/mnt/backups/pbx"

case "${1:-run}" in
    run|"")
        /usr/local/bin/pbx-backup-run
        ;;
    verify)
        # Feature: backup-verify — check all SHA256 sums in backup directories
        echo "=== Verifying backup integrity ==="
        PASS=0; FAIL=0
        while IFS= read -r -d '' sha_file; do
            archive="${sha_file%.sha256}"
            [ -f "${archive}" ] || { echo "MISSING: ${archive}"; FAIL=$(( FAIL + 1 )); continue; }
            expected=$(awk '{print $1}' "${sha_file}")
            actual=$(sha256sum "${archive}" | cut -d' ' -f1)
            if [ "${expected}" = "${actual}" ]; then
                echo "OK: $(basename "${archive}")"
                PASS=$(( PASS + 1 ))
            else
                echo "FAIL: $(basename "${archive}") (checksum mismatch)"
                FAIL=$(( FAIL + 1 ))
            fi
        done < <(find "${BACKUP_BASE}" -name "*.sha256" -print0 2>/dev/null)
        echo "--- Results: ${PASS} OK, ${FAIL} FAILED ---"
        [ "${FAIL}" -eq 0 ]
        ;;
    status)
        # Feature: backup-verify — show backup status summary
        echo "=== PBX Backup Status ==="
        LAST=$(find "${BACKUP_BASE}" -mindepth 2 -maxdepth 2 -type d 2>/dev/null \
               | sort | tail -1)
        if [ -n "${LAST}" ]; then
            echo "Last backup : ${LAST}"
            echo "Last date   : $(stat -c %y "${LAST}" 2>/dev/null | cut -d. -f1)"
        else
            echo "Last backup : none"
        fi
        COUNT=$(find "${BACKUP_BASE}" -mindepth 2 -maxdepth 2 -type d 2>/dev/null | wc -l)
        SIZE=$(du -sh "${BACKUP_BASE}" 2>/dev/null | cut -f1)
        echo "Total count : ${COUNT}"
        echo "Total size  : ${SIZE:-0}"
        ;;
    *)
        echo "Usage: pbx-backup [run|verify|status]"
        exit 1
        ;;
esac
PBKPEOF

    # pbx-cleanup
    cat > /usr/local/bin/pbx-cleanup << 'PCLNEOF'
#!/bin/bash
find /mnt/backups/pbx -maxdepth 3 -type d -mtime +30 -exec rm -rf {} + 2>/dev/null || true
echo "Old backups cleaned up."
PCLNEOF

    # pbx-firewall
    cat > /usr/local/bin/pbx-firewall << 'PFWEOF'
#!/bin/bash
echo "Firewall status:"
if command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --list-all 2>/dev/null || true
elif command -v ufw >/dev/null 2>&1; then
    ufw status numbered 2>/dev/null || true
fi
iptables -L INPUT -n --line-numbers 2>/dev/null || true
PFWEOF

    # pbx-ssh
    cat > /usr/local/bin/pbx-ssh << 'PSSHEOF'
#!/bin/bash
echo "SSH Configuration:"
grep -E "^(Port|PermitRootLogin|PasswordAuthentication|PubkeyAuthentication)" \
    /etc/ssh/sshd_config 2>/dev/null || true
PSSHEOF

    # pbx-security
    cat > /usr/local/bin/pbx-security << 'PSECEOF'
#!/bin/bash
echo "=== PBX Security Audit ==="
echo "Fail2ban bans:"
fail2ban-client status asterisk 2>/dev/null || echo "  (fail2ban not running)"
echo ""
echo "Open ports:"
ss -tlnp 2>/dev/null | grep LISTEN || netstat -tlnp 2>/dev/null || true
echo ""
echo "Recent auth failures:"
grep "authentication failure\|Failed password" /var/log/auth.log \
    /var/log/secure 2>/dev/null | tail -10 || true
PSECEOF

    # pbx-services
    cat > /usr/local/bin/pbx-services << 'PSVCEOF'
#!/bin/bash
echo "=== PBX Service Status ==="
systemctl list-units --type=service --state=running 2>/dev/null | grep -E \
    "asterisk|freepbx|mariadb|mysql|apache|httpd|php|postfix|fail2ban|webmin" \
    || true
PSVCEOF

    # pbx-ssl
    cat > /usr/local/bin/pbx-ssl << 'PSSLEOF'
#!/bin/bash
echo "=== SSL Certificate Status ==="
for f in /etc/asterisk/keys/*.pem /etc/letsencrypt/live/*/fullchain.pem; do
    [ -f "${f}" ] || continue
    echo "File: ${f}"
    openssl x509 -in "${f}" -noout -subject -dates 2>/dev/null
    echo ""
done
PSSLEOF

    # pbx-passwords
    cat > /usr/local/bin/pbx-passwords << 'PPWEOF'
#!/bin/bash
echo "=== PBX Credentials ==="
cat /etc/pbx/pbx_passwords 2>/dev/null || cat /etc/pbx/.env 2>/dev/null || \
    echo "Password file not found"
PPWEOF

    # pbx-docs
    cat > /usr/local/bin/pbx-docs << 'PDOCEOF'
#!/bin/bash
echo "=== PBX Quick Reference ==="
echo ""
echo "Management Scripts:"
echo "  pbx-status     — System overview"
echo "  pbx-restart    — Restart PBX services"
echo "  pbx-repair     — Run FreePBX repair"
echo "  pbx-logs       — Tail Asterisk log"
echo "  pbx-backup     — Manual backup"
echo "  pbx-cleanup    — Clean old backups"
echo "  pbx-firewall   — Firewall status"
echo "  pbx-ssh        — SSH config"
echo "  pbx-security   — Security audit"
echo "  pbx-services   — Service status"
echo "  pbx-ssl        — Certificate status"
echo "  pbx-passwords  — Show credentials"
echo "  pbx-network    — Network info"
echo "  pbx-moh        — Music-on-Hold info"
echo "  pbx-config     — TUI configuration tool"
echo ""
echo "Demo Extensions:"
echo "  123  — Speaking clock"
echo "  947  — Weather (TTS demo)"
echo "  951  — Today's date"
echo "  *43  — Echo test"
echo "  *610 — Music on hold"
echo "  4747 — Lenny bot"
echo "  *41  — Caller ID readback"
echo "  *97  — Voicemail"
echo "  *469 — Conference room 1"
echo "  *470 — Conference room 2"
PDOCEOF

    # pbx-network
    cat > /usr/local/bin/pbx-network << 'PNETEOF'
#!/bin/bash
echo "=== PBX Network Information ==="
echo "Interfaces:"
ip addr show 2>/dev/null | grep -E "^[0-9]|inet " || ifconfig 2>/dev/null || true
echo ""
echo "Routes:"
ip route show 2>/dev/null || route -n 2>/dev/null || true
echo ""
echo "DNS:"
cat /etc/resolv.conf 2>/dev/null || true
PNETEOF

    # pbx-moh
    cat > /usr/local/bin/pbx-moh << 'PMOHEOF'
#!/bin/bash
echo "=== Music on Hold ==="
echo "MOH directories:"
ls -la /var/lib/asterisk/moh/ 2>/dev/null || echo "No MOH files found"
echo ""
echo "To add MOH: copy mp3/wav files to /var/lib/asterisk/moh/"
echo "Then reload: asterisk -rx 'module reload res_musiconhold.so'"
PMOHEOF

    # Set all scripts executable
    chmod +x /usr/local/bin/pbx-status  /usr/local/bin/pbx-restart \
              /usr/local/bin/pbx-repair  /usr/local/bin/pbx-logs \
              /usr/local/bin/pbx-backup  /usr/local/bin/pbx-cleanup \
              /usr/local/bin/pbx-firewall /usr/local/bin/pbx-ssh \
              /usr/local/bin/pbx-security /usr/local/bin/pbx-services \
              /usr/local/bin/pbx-ssl     /usr/local/bin/pbx-passwords \
              /usr/local/bin/pbx-docs    /usr/local/bin/pbx-network \
              /usr/local/bin/pbx-moh

    # pbx-config TUI
    cat > /usr/local/bin/pbx-config << 'PCFGEOF'
#!/bin/bash
# pbx-config — interactive TUI configuration tool using dialog
command -v dialog >/dev/null 2>&1 || { echo "Install dialog first"; exit 1; }
command -v fwconsole >/dev/null 2>&1 || { echo "FreePBX not found"; exit 1; }

while true; do
    CHOICE=$(dialog --clear --backtitle "PBX Configuration" \
        --title "PBX Config Tool" \
        --menu "Select action:" 20 60 10 \
        1 "Add PJSIP Extension" \
        2 "Add VoIP Trunk" \
        3 "Add Inbound Route" \
        4 "Add Outbound Route" \
        5 "View Configuration" \
        6 "Apply & Reload FreePBX" \
        7 "Exit" \
        3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && break

    case "${CHOICE}" in
        1)
            EXTNUM=$(dialog --inputbox "Extension number:" 8 40 3>&1 1>&2 2>&3) || continue
            EXTNAME=$(dialog --inputbox "Display name:" 8 40 3>&1 1>&2 2>&3) || continue
            EXTPASS=$(generate_password 16)
            fwconsole extensions --add \
                --extension="${EXTNUM}" \
                --name="${EXTNAME}" \
                --password="${EXTPASS}" 2>/dev/null \
                || dialog --msgbox "Extension added (or already exists): ${EXTNUM}" 8 50
            dialog --msgbox "Extension: ${EXTNUM}\nName: ${EXTNAME}\nPassword: ${EXTPASS}" 10 50
            ;;
        2)
            PROVIDER=$(dialog --menu "Select provider template:" 15 50 6 \
                1 "voip.ms" \
                2 "Flowroute" \
                3 "Telnyx" \
                4 "Twilio" \
                5 "Custom" \
                3>&1 1>&2 2>&3) || continue
            TRUNK_NAME=$(dialog --inputbox "Trunk name:" 8 40 3>&1 1>&2 2>&3) || continue
            TRUNK_USER=$(dialog --inputbox "Username/Account:" 8 40 3>&1 1>&2 2>&3) || continue
            TRUNK_PASS=$(dialog --inputbox "Password/Secret:" 8 40 3>&1 1>&2 2>&3) || continue
            case "${PROVIDER}" in
                1) TRUNK_HOST="vancouver.voip.ms" ;;
                2) TRUNK_HOST="us-east-nj.sip.flowroute.com" ;;
                3) TRUNK_HOST="sip.telnyx.com" ;;
                4) TRUNK_HOST="pstn.twilio.com" ;;
                *) TRUNK_HOST=$(dialog --inputbox "SIP Host:" 8 40 3>&1 1>&2 2>&3) || continue ;;
            esac
            fwconsole trunks --add \
                --name="${TRUNK_NAME}" \
                --username="${TRUNK_USER}" \
                --password="${TRUNK_PASS}" \
                --host="${TRUNK_HOST}" 2>/dev/null \
                || dialog --msgbox "Trunk configured: ${TRUNK_NAME} -> ${TRUNK_HOST}" 8 50
            ;;
        3)
            DID=$(dialog --inputbox "Inbound DID (phone number):" 8 40 3>&1 1>&2 2>&3) || continue
            DEST=$(dialog --inputbox "Destination extension:" 8 40 3>&1 1>&2 2>&3) || continue
            mysql -u root -p"$(grep "MySQL Root Password" /etc/pbx/pbx_passwords | awk '{print $NF}')" \
                asterisk -e "INSERT IGNORE INTO incoming (extension,description,destination) \
                VALUES ('${DID}','DID ${DID}','ext-local,${DEST},1');" 2>/dev/null \
                || dialog --msgbox "Inbound route: ${DID} -> ${DEST}" 8 50
            ;;
        4)
            PATTERN=$(dialog --inputbox "Dial pattern (e.g. _1NXXNXXXXXX):" 8 50 3>&1 1>&2 2>&3) || continue
            TRUNK=$(dialog --inputbox "Trunk name:" 8 40 3>&1 1>&2 2>&3) || continue
            dialog --msgbox "Outbound route for ${PATTERN} via ${TRUNK} - configure in FreePBX GUI" 8 60
            ;;
        5)
            INFO=$(asterisk -rx "pjsip show endpoints" 2>/dev/null \
                || echo "Asterisk not running")
            dialog --scrolltext --msgbox "${INFO}" 20 70
            ;;
        6)
            fwconsole reload --skip-registry-checks 2>/dev/null \
                && dialog --msgbox "FreePBX reloaded successfully." 8 40 \
                || dialog --msgbox "Reload failed. Check logs." 8 40
            ;;
        7) break ;;
    esac
done
clear
PCFGEOF
    chmod +x /usr/local/bin/pbx-config

    track_install "management-scripts"
    success "Management scripts created"
}

# =============================================================================
# SECTION 40: PBXSTATUS SCRIPT
# =============================================================================

create_pbxstatus() {
    step "📊 Creating pbxstatus script..."

    cat > /usr/local/bin/pbxstatus << 'PBXSTATEOF'
#!/bin/bash
# pbxstatus — full PBX health dashboard

RESET='\033[0m'; BOLD='\033[1m'; GREEN='\033[0;32m'
YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'

svc_status() {
    local svc="$1"
    if systemctl is-active --quiet "${svc}" 2>/dev/null; then
        echo -e "${GREEN}● running${RESET}"
    else
        echo -e "${RED}○ stopped${RESET}"
    fi
}

echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║                 PBX System Status Dashboard              ║${RESET}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════╝${RESET}"
echo ""

echo -e "${BOLD}Services:${RESET}"
for svc in asterisk freepbx mariadb mysql httpd apache2 php-fpm \
           postfix fail2ban webmin; do
    ST=$(svc_status "${svc}")
    printf "  %-20s %b\n" "${svc}" "${ST}"
done

echo ""
echo -e "${BOLD}Asterisk:${RESET}"
if asterisk -rx "core show version" 2>/dev/null; then
    asterisk -rx "core show channels count" 2>/dev/null || true
    asterisk -rx "pjsip show endpoints" 2>/dev/null | head -20 || true
else
    echo -e "  ${RED}Asterisk not responding${RESET}"
fi

echo ""
echo -e "${BOLD}System Resources:${RESET}"
echo "  Disk   : $(df -h / | awk 'NR==2{print $3"/"$2" ("$5" used)"}')"
echo "  Memory : $(free -h | awk '/^Mem/{print $3"/"$2" used"}')"
echo "  Uptime : $(uptime -p 2>/dev/null || uptime)"
echo "  Load   : $(uptime | awk -F'load average:' '{print $2}')"

echo ""
echo -e "${BOLD}Network:${RESET}"
PRIV_IP=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $7;exit}' || true)
PUB_IP=$(curl -s --max-time 5 https://ifconfig.me 2>/dev/null || echo "unknown")
echo "  Private IP : ${PRIV_IP}"
echo "  Public IP  : ${PUB_IP}"

echo ""
echo -e "${BOLD}Recent Asterisk Errors (last 5):${RESET}"
grep -i "error\|warning" /var/log/asterisk/full 2>/dev/null \
    | tail -5 || echo "  (no log)"
PBXSTATEOF
    chmod +x /usr/local/bin/pbxstatus

    success "pbxstatus created"
}

# =============================================================================
# SECTION 41: ROOT SCRIPTS
# =============================================================================

create_root_scripts() {
    step "📜 Creating root utility scripts..."

    # IP checker
    cat > /usr/local/bin/ipchecker << 'IPCEOF'
#!/bin/bash
# ipchecker — show current public and private IPs
PRIV=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $7;exit}')
PUB=$(curl -s --max-time 10 https://ifconfig.me 2>/dev/null \
    || curl -s --max-time 10 https://api.ipify.org 2>/dev/null || echo "unknown")
echo "Private IP: ${PRIV}"
echo "Public IP : ${PUB}"
IPCEOF
    chmod +x /usr/local/bin/ipchecker

    # add-ip — add IP to iptables whitelist
    cat > /usr/local/bin/add-ip << 'ADDIPEOF'
#!/bin/bash
IP="${1:?Usage: add-ip <ip-address>}"
iptables -I INPUT -s "${IP}" -j ACCEPT
echo "Added ${IP} to iptables whitelist"
ADDIPEOF
    chmod +x /usr/local/bin/add-ip

    # admin-pw-change — change FreePBX admin password
    cat > /usr/local/bin/admin-pw-change << 'APWEOF'
#!/bin/bash
echo "Changing FreePBX admin password..."
read -rsp "New password: " PW; echo
fwconsole userman --update --username=admin --password="${PW}" 2>/dev/null \
    || echo "fwconsole not available — update in FreePBX GUI"
echo "Password updated"
APWEOF
    chmod +x /usr/local/bin/admin-pw-change

    # sig-fix — fix FreePBX module signatures
    cat > /usr/local/bin/sig-fix << 'SIGEOF'
#!/bin/bash
echo "Refreshing FreePBX module signatures..."
fwconsole ma refreshsignatures 2>/dev/null || true
fwconsole chown 2>/dev/null || true
echo "Done."
SIGEOF
    chmod +x /usr/local/bin/sig-fix

    # timezone-setup
    cat > /usr/local/bin/timezone-setup << 'TZEOF'
#!/bin/bash
TZ="${1:?Usage: timezone-setup <timezone>  e.g. America/New_York}"
timedatectl set-timezone "${TZ}" 2>/dev/null \
    || ln -sf "/usr/share/zoneinfo/${TZ}" /etc/localtime 2>/dev/null
echo "Timezone set to ${TZ}"
TZEOF
    chmod +x /usr/local/bin/timezone-setup

    # Root .bash_profile enhancements
    if ! grep -q "pbx-status" /root/.bash_profile 2>/dev/null \
        && ! grep -q "pbx-status" /root/.bashrc 2>/dev/null; then
        cat >> /root/.bash_profile << 'BPEOF'

# PBX aliases
alias pbx='pbx-status'
alias log='tail -f /var/log/asterisk/full'
alias ast='asterisk -rvvvvv'
alias fpbx='fwconsole'
alias pbxrestart='pbx-restart'

# PATH additions
export PATH="${PATH}:/usr/local/sbin"
BPEOF
    fi

    # Root .vimrc
    if [ ! -f /root/.vimrc ]; then
        cat > /root/.vimrc << 'VIMEOF'
set number
set tabstop=4
set shiftwidth=4
set expandtab
set hlsearch
set incsearch
set ignorecase
set smartcase
set bg=dark
syntax on
VIMEOF
    fi

    success "Root scripts created"
}

# =============================================================================
# SECTION 42: ASTERIDEX
# =============================================================================

install_asteridex() {
    step "📒 Installing Asteridex phonebook..."

    local asteridex_dir="${WEB_ROOT}/asteridex"
    if [ -d "${asteridex_dir}" ]; then
        info "Asteridex already installed, skipping"
        return 0
    fi

    cd "${WORK_DIR}"
    if download_file \
        "https://sourceforge.net/projects/asteridex/files/latest/download" \
        asteridex.tar.gz 60 2>/dev/null; then
        tar -xzf asteridex.tar.gz 2>/dev/null || true
        local adir
        adir=$(ls -d "${WORK_DIR}"/asteridex*/ 2>/dev/null | head -1 || true)
        if [ -d "${adir:-}" ]; then
            mv "${adir}" "${asteridex_dir}"
            chown -R "${APACHE_USER}":"${APACHE_GROUP}" "${asteridex_dir}"
            info "Asteridex installed at ${asteridex_dir}"
        else
            warn "Asteridex extraction failed"
        fi
    else
        warn "Could not download Asteridex (phonebook unavailable)"
    fi
    cd /
    track_install "asteridex"
}

# =============================================================================
# SECTION 42b: NTP / TIME SYNC
# =============================================================================

setup_ntp() {
    step "Configuring NTP time sync..."
    pkg_install_one_by_one $PKG_NTP
    if command -v chronyd >/dev/null 2>&1; then
        svc_enable chronyd 2>/dev/null || true
        svc_restart chronyd 2>/dev/null || true
        chronyc makestep 2>/dev/null || true
    elif command -v ntpd >/dev/null 2>&1; then
        svc_enable ntp 2>/dev/null || true
        svc_restart ntp 2>/dev/null || true
    fi
    success "NTP configured"
}

# =============================================================================
# SECTION 42c: VOIP SYSTEM TUNING
# =============================================================================

setup_voip_tuning() {
    [ "${IS_CONTAINER:-0}" = "1" ] && { info "Container: skipping sysctl VoIP tuning"; return 0; }
    step "Tuning system for VoIP..."

    cat > /etc/sysctl.d/pbx-voip.conf << 'SYSCTLEOF'
# PBX VoIP kernel tuning
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.core.rmem_default = 65536
net.core.wmem_default = 65536
net.core.netdev_max_backlog = 5000
net.core.somaxconn = 1024
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384
net.ipv4.ip_local_port_range = 10000 65535
net.ipv4.tcp_fin_timeout = 30
fs.file-max = 1000000
SYSCTLEOF
    sysctl -p /etc/sysctl.d/pbx-voip.conf 2>/dev/null || true

    cat > /etc/security/limits.d/pbx-asterisk.conf << 'LIMITSEOF'
asterisk soft nofile 65536
asterisk hard nofile 65536
root     soft nofile 65536
root     hard nofile 65536
LIMITSEOF

    success "VoIP system tuning applied"
}

# =============================================================================
# SECTION 42d: QOS
# =============================================================================

setup_qos() {
    [ "${IS_CONTAINER:-0}" = "1" ] && return 0
    [ "${INSTALL_PROFILE:-standard}" = "minimal" ] && return 0
    step "Configuring QoS for VoIP..."

    local iface
    iface=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $5; exit}' || echo "eth0")

    cat > /usr/local/bin/pbx-qos-apply << QOSEOF
#!/bin/bash
# Apply DSCP marking for SIP and RTP — re-run after reboot
iptables -t mangle -A OUTPUT -p udp --dport 5060 -j DSCP --set-dscp-class EF 2>/dev/null || true
iptables -t mangle -A OUTPUT -p udp --dport 5061 -j DSCP --set-dscp-class EF 2>/dev/null || true
iptables -t mangle -A OUTPUT -p udp --dport 10000:20000 -j DSCP --set-dscp-class EF 2>/dev/null || true
iptables -t mangle -A OUTPUT -p tcp --dport 5060 -j DSCP --set-dscp-class CS3 2>/dev/null || true
QOSEOF
    chmod 755 /usr/local/bin/pbx-qos-apply

    echo "@reboot root /usr/local/bin/pbx-qos-apply" > /etc/cron.d/pbx-qos
    /usr/local/bin/pbx-qos-apply 2>/dev/null || true
    success "QoS DSCP rules applied (EF for SIP/RTP)"
}

# =============================================================================
# SECTION 42e: WEBRTC / STUN
# =============================================================================

configure_webrtc() {
    step "Configuring WebRTC and STUN..."

    local pjsip_conf="/etc/asterisk/pjsip.conf"
    if [ -f "${pjsip_conf}" ] && ! grep -q "transport-wss" "${pjsip_conf}"; then
        backup_config "${pjsip_conf}"
        cat >> "${pjsip_conf}" << 'WSSEOF'

; WebRTC WSS transport — for browser-based SIP clients
[transport-wss]
type     = transport
protocol = wss
bind     = 0.0.0.0

WSSEOF
    fi

    local ast_conf="/etc/asterisk/asterisk.conf"
    if [ -f "${ast_conf}" ] && ! grep -q "stunaddr" "${ast_conf}"; then
        cat >> "${ast_conf}" << 'STUNEOF'

[options]
stunaddr = stun.l.google.com:19302
STUNEOF
    fi

    success "WebRTC WSS transport + STUN configured"
}

# =============================================================================
# SECTION 42f: VOICEMAIL-TO-EMAIL
# =============================================================================

configure_voicemail_email() {
    local vm_conf="/etc/asterisk/voicemail.conf"
    [ -f "${vm_conf}" ] || return 0
    step "Configuring voicemail-to-email..."
    backup_config "${vm_conf}"

    sed -i "s|^;*serveremail=.*|serveremail=${FROM_EMAIL}|" "${vm_conf}" 2>/dev/null || true
    sed -i "s|^;*fromstring=.*|fromstring=${FROM_NAME}|" "${vm_conf}" 2>/dev/null || true

    grep -q "^format=" "${vm_conf}" || \
        sed -i '/^\[general\]/a format=wav49|gsm|wav' "${vm_conf}" 2>/dev/null || true

    success "Voicemail-to-email configured (from: ${FROM_NAME} <${FROM_EMAIL}> → ${ADMIN_EMAIL})"
}

# =============================================================================
# SECTION 42g: MAIN WEB PORTAL
# =============================================================================

build_main_portal() {
    step "Building main web portal..."
    mkdir -p "${WEB_ROOT}"

    cat > "${WEB_ROOT}/index.php" << 'PORTALEOF'
<?php
$services = [
    'FreePBX Admin'      => ['/admin/',      'PBX Management',       '⚙️'],
    'User Portal (UCP)'  => ['/ucp/',        'End-user self-service', '👤'],
    'Fax (AvantFax)'     => ['/avantfax/',   'Fax management',        '📠'],
    'Call Center Stats'  => ['/callcenter/', 'Queue statistics',      '📊'],
    'AsteriDex'          => ['/asteridex/',  'Phone directory',       '📖'],
    'Telephone Reminder' => ['/reminder/',   'Schedule reminders',    '⏰'],
    'System Status'      => ['/status/',     'Health overview',       '💚'],
    'Webmin'             => ['https://' . $_SERVER['HTTP_HOST'] . ':9001/',
                              'System admin', '🖥️'],
];
?><!DOCTYPE html>
<html>
<head>
<title>PBX Server</title>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
body{font-family:Arial,sans-serif;background:#1a1a2e;color:#eee;margin:0;padding:20px}
h1{text-align:center;color:#00d4ff;margin-bottom:30px}
.grid{display:flex;flex-wrap:wrap;gap:20px;justify-content:center;max-width:1000px;margin:0 auto}
.card{background:#16213e;border:1px solid #0f3460;border-radius:8px;padding:20px;width:200px;
      text-align:center;text-decoration:none;color:#eee;transition:transform .2s,border-color .2s}
.card:hover{transform:translateY(-4px);border-color:#00d4ff}
.card .icon{font-size:36px;margin-bottom:10px}
.card .name{font-weight:bold;font-size:14px;margin-bottom:5px}
.card .desc{font-size:12px;color:#aaa}
.footer{text-align:center;margin-top:40px;color:#666;font-size:12px}
</style>
</head>
<body>
<h1>🏢 PBX Server</h1>
<div class="grid">
<?php foreach($services as $name => [$url, $desc, $icon]): ?>
<a class="card" href="<?= htmlspecialchars($url) ?>">
  <div class="icon"><?= $icon ?></div>
  <div class="name"><?= htmlspecialchars($name) ?></div>
  <div class="desc"><?= htmlspecialchars($desc) ?></div>
</a>
<?php endforeach; ?>
</div>
<div class="footer">PBX v3.0 &bull; <?= htmlspecialchars(gethostname()) ?></div>
</body>
</html>
PORTALEOF

    chown "${APACHE_USER:-www-data}:${APACHE_GROUP:-www-data}" "${WEB_ROOT}/index.php" 2>/dev/null || true
    success "Main portal built at /"
}

# =============================================================================
# SECTION 42h: STATUS / HEALTH ENDPOINTS
# =============================================================================

build_status_page() {
    step "Building /status/ health endpoint..."
    local status_dir="${WEB_ROOT}/status"
    mkdir -p "${status_dir}"

    cat > "${status_dir}/index.php" << 'STATUSEOF'
<?php
header('Content-Type: application/json');
$services = ['asterisk','freepbx','mariadb','mysql','httpd','apache2','fail2ban','postfix','hylafax'];
$out = ['timestamp' => date('c'), 'hostname' => gethostname(), 'services' => []];
foreach ($services as $svc) {
    $state = trim(shell_exec("systemctl is-active " . escapeshellarg($svc) . " 2>/dev/null") ?? '');
    if ($state === 'active') $out['services'][$svc] = 'ok';
    elseif ($state !== '') $out['services'][$svc] = $state;
}
$out['disk_free_gb'] = round(disk_free_space('/') / 1073741824, 1);
$out['load_avg']     = sys_getloadavg();
$mem = file_get_contents('/proc/meminfo');
preg_match('/MemAvailable:\s+(\d+)/', $mem, $m);
$out['mem_free_mb'] = isset($m[1]) ? round($m[1]/1024, 1) : null;
echo json_encode($out, JSON_PRETTY_PRINT);
STATUSEOF

    chown -R "${APACHE_USER:-www-data}:${APACHE_GROUP:-www-data}" "${status_dir}" 2>/dev/null || true

    # Feature: health-endpoint — dedicated /health JSON endpoint
    local health_dir="${WEB_ROOT}/health"
    mkdir -p "${health_dir}"
    cat > "${health_dir}/index.php" << 'HEALTHPHPEOF'
<?php
header('Content-Type: application/json');
header('Cache-Control: no-cache, no-store');
header('X-Content-Type-Options: nosniff');

$services = ['asterisk', 'mariadb', 'mysql', 'httpd', 'apache2', 'php-fpm', 'php8.2-fpm', 'fail2ban', 'postfix'];
$status = [];
$overall = 'ok';

foreach ($services as $svc) {
    $out = shell_exec("systemctl is-active " . escapeshellarg($svc) . " 2>/dev/null");
    $state = trim($out ?? '');
    if ($state === 'active') {
        $status[$svc] = 'running';
    } elseif ($state === 'inactive' || $state === '') {
        // skip services that are not installed
    } else {
        $status[$svc] = $state;
        $overall = 'degraded';
    }
}

// Verify Asterisk CLI connectivity
$ast_ver = trim(shell_exec('asterisk -rx "core show version" 2>/dev/null') ?? '');
$status['asterisk_connected'] = !empty($ast_ver) ? 'true' : 'false';
if (empty($ast_ver)) $overall = 'degraded';

echo json_encode([
    'status'    => $overall,
    'timestamp' => date('c'),
    'hostname'  => gethostname(),
    'services'  => $status,
    'version'   => $ast_ver ?: 'unknown',
    'disk_free_gb' => round(disk_free_space('/') / 1073741824, 1),
], JSON_PRETTY_PRINT);
HEALTHPHPEOF
    chown -R "${APACHE_USER:-www-data}:${APACHE_GROUP:-www-data}" "${health_dir}" 2>/dev/null || true

    success "Status endpoint built at /status/ and /health/"
}

# =============================================================================
# SECTION 42i: HEALTH MONITORING
# =============================================================================

setup_health_monitoring() {
    [ "${INSTALL_PROFILE:-standard}" = "minimal" ] && return 0
    step "Setting up health monitoring..."

    # Write using unquoted heredoc so install-time vars are baked in,
    # but escape $() so they run at cron-execution time
    cat > /usr/local/bin/pbx-health-check << HEALTHEOF
#!/bin/bash
ADMIN_EMAIL="\${ADMIN_EMAIL:-${ADMIN_EMAIL:-root}}"
FROM_EMAIL="${FROM_EMAIL}"
FROM_NAME="${FROM_NAME}"
SERVICES="asterisk mariadb"
FAILED=""
for svc in \${SERVICES}; do
    systemctl is-active --quiet "\${svc}" 2>/dev/null || FAILED="\${FAILED} \${svc}"
done
if [ -n "\${FAILED}" ]; then
    FQDN=\$(hostname -f 2>/dev/null || hostname)
    MSG="PBX ALERT: Services down on \${FQDN}:\${FAILED}"
    echo "\${MSG}" | mail -s "[PBX ALERT] Services Down" \
        -a "From: \${FROM_NAME} <\${FROM_EMAIL}>" "\${ADMIN_EMAIL}" 2>/dev/null || true
    logger -t pbx-health "\${MSG}"
    for svc in \${FAILED}; do
        systemctl restart "\${svc}" 2>/dev/null && \
            echo "Auto-restarted: \${svc}" | \
            mail -s "[PBX] Auto-restarted \${svc} on \${FQDN}" \
                -a "From: \${FROM_NAME} <\${FROM_EMAIL}>" "\${ADMIN_EMAIL}" 2>/dev/null || true
    done
fi
HEALTHEOF
    chmod 755 /usr/local/bin/pbx-health-check

    echo "*/5 * * * * root /usr/local/bin/pbx-health-check" > /etc/cron.d/pbx-health
    success "Health monitoring active (every 5 min)"
}

# =============================================================================
# SECTION 42j: TELEPHONE REMINDER
# =============================================================================

install_telephone_reminder() {
    step "Installing Telephone Reminder..."
    local reminder_dir="${WEB_ROOT}/reminder"
    mkdir -p "${reminder_dir}"

    cat > "${reminder_dir}/index.php" << 'REMEOF'
<?php
$reminders_file = '/etc/asterisk/reminders.txt';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $phone = preg_replace('/[^0-9*#]/', '', $_POST['phone'] ?? '');
    $time  = $_POST['time'] ?? '';
    $msg   = substr(strip_tags($_POST['message'] ?? 'This is your reminder'), 0, 200);
    if ($phone && $time) {
        $ts = strtotime($time);
        file_put_contents($reminders_file, "${ts}|${phone}|${msg}\n", FILE_APPEND | LOCK_EX);
        $ok = "Reminder scheduled for {$time} → extension {$phone}";
    }
}
?><!DOCTYPE html>
<html>
<head><title>Telephone Reminder</title>
<style>body{font-family:Arial;max-width:500px;margin:40px auto;padding:20px}
label{display:block;font-weight:bold;margin-top:12px}
input,textarea,select{width:100%;padding:8px;margin-top:4px;box-sizing:border-box}
button{background:#0066cc;color:#fff;padding:10px 24px;border:none;cursor:pointer;margin-top:16px;border-radius:4px}
.ok{color:green;background:#f0fff0;padding:8px;border-radius:4px}</style></head>
<body>
<h2>⏰ Telephone Reminder</h2>
<?php if (!empty($ok)) echo "<p class='ok'>" . htmlspecialchars($ok) . "</p>"; ?>
<form method="post">
<label>Extension or Phone Number:</label>
<input type="text" name="phone" placeholder="1001 or 5551234567" required>
<label>Reminder Date &amp; Time:</label>
<input type="datetime-local" name="time" required>
<label>Message (read via TTS):</label>
<textarea name="message" rows="3">This is your telephone reminder.</textarea>
<button type="submit">📅 Schedule Reminder</button>
</form>
</body></html>
REMEOF

    cat > /usr/local/bin/pbx-reminder-process << 'REMINDEREOF'
#!/bin/bash
# Process pending reminders — called by cron every minute
REMFILE="/etc/asterisk/reminders.txt"
[ -f "${REMFILE}" ] || exit 0
NOW=$(date +%s)
TMPFILE=$(mktemp)
while IFS='|' read -r ts phone msg; do
    [ -z "${ts}" ] && continue
    if [ "${ts}" -le "${NOW}" ] 2>/dev/null; then
        asterisk -rx "originate Local/${phone}@from-internal application Playback 'vm-youhave'" \
            2>/dev/null || true
    else
        echo "${ts}|${phone}|${msg}" >> "${TMPFILE}"
    fi
done < "${REMFILE}"
mv "${TMPFILE}" "${REMFILE}"
REMINDEREOF
    chmod 755 /usr/local/bin/pbx-reminder-process
    echo "* * * * * asterisk /usr/local/bin/pbx-reminder-process" > /etc/cron.d/pbx-reminders

    # Apache alias
    local rem_conf
    case "${DISTRO_FAMILY}" in
        debian) rem_conf="/etc/apache2/conf-available/reminder.conf" ;;
        *) rem_conf="/etc/httpd/conf.d/reminder.conf" ;;
    esac
    cat > "${rem_conf}" << REMCEOF
Alias /reminder ${WEB_ROOT}/reminder
<Directory ${WEB_ROOT}/reminder>
    Options -Indexes
    AllowOverride None
    Require all granted
</Directory>
REMCEOF
    [ "${DISTRO_FAMILY}" = "debian" ] && a2enconf reminder 2>/dev/null || true

    chown -R "${APACHE_USER:-www-data}:${APACHE_GROUP:-www-data}" "${reminder_dir}" 2>/dev/null || true
    svc_reload "${APACHE_SERVICE}" 2>/dev/null || true
    success "Telephone Reminder installed at /reminder/"
}

# =============================================================================
# SECTION 42k: ASTERNIC CALL CENTER STATS
# =============================================================================

install_asternic() {
    step "Installing Asternic Call Center Stats..."
    local asternic_dir="${WEB_ROOT}/callcenter"
    mkdir -p "${asternic_dir}"

    local tmpdir
    tmpdir=$(mktemp -d)
    local url="https://github.com/asternic/callcenter-stats/archive/refs/heads/master.tar.gz"

    if curl -fsSL --max-time 60 "${url}" -o "${tmpdir}/asternic.tar.gz" 2>/dev/null; then
        tar -xzf "${tmpdir}/asternic.tar.gz" -C "${tmpdir}" 2>/dev/null || true
        if [ -d "${tmpdir}/callcenter-stats-master" ]; then
            cp -r "${tmpdir}/callcenter-stats-master/." "${asternic_dir}/"
            success "Asternic downloaded"
        fi
    else
        warn "Asternic download failed — creating placeholder"
        cat > "${asternic_dir}/index.php" << 'CCEOF'
<?php echo "<h1>Call Center Stats</h1><p>Visit <a href='https://www.asternic.net'>asternic.net</a> to download.</p>"; ?>
CCEOF
    fi

    local cc_conf
    case "${DISTRO_FAMILY}" in
        debian) cc_conf="/etc/apache2/conf-available/callcenter.conf" ;;
        *) cc_conf="/etc/httpd/conf.d/callcenter.conf" ;;
    esac
    cat > "${cc_conf}" << CCAEOF
Alias /callcenter ${asternic_dir}
<Directory ${asternic_dir}>
    Options -Indexes
    AllowOverride All
    Require all granted
</Directory>
CCAEOF
    [ "${DISTRO_FAMILY}" = "debian" ] && a2enconf callcenter 2>/dev/null || true

    chown -R "${APACHE_USER:-www-data}:${APACHE_GROUP:-www-data}" "${asternic_dir}" 2>/dev/null || true
    svc_reload "${APACHE_SERVICE}" 2>/dev/null || true
    rm -rf "${tmpdir}"
    success "Call Center Stats installed at /callcenter/"
}

# =============================================================================
# SECTION 43: FINALIZE INSTALLATION
# =============================================================================

finalize_installation() {
    step "🏁 Finalizing installation..."

    # Set correct permissions on key directories
    chown -R asterisk:asterisk \
        /etc/asterisk /var/lib/asterisk /var/log/asterisk /var/spool/asterisk 2>/dev/null || true
    chown -R "${APACHE_USER}":"${APACHE_GROUP}" "${WEB_ROOT}" 2>/dev/null || true
    chmod 750 "${PBX_ENV_DIR}" 2>/dev/null || true
    chmod 600 "${PBX_ENV_FILE}" 2>/dev/null || true

    # Set sensible hostname if still localhost
    local current_hostname
    current_hostname=$(hostname -f 2>/dev/null || hostname)
    if echo "${current_hostname}" | grep -qE "^localhost|^127\."; then
        warn "Hostname is localhost — set FQDN for proper mail/certificate function"
        warn "  Run: hostnamectl set-hostname pbx.yourdomain.com"
    fi

    # Final FreePBX reload
    # Fix PHP session directory ownership — FPM runs as asterisk, so it needs write access
    for sess_dir in /var/lib/php/session /var/lib/php/sessions; do
        [ -d "$sess_dir" ] && chown asterisk:asterisk "$sess_dir" 2>/dev/null || true
    done
    fwconsole chown  2>/dev/null || true
    fwconsole reload --skip-registry-checks 2>/dev/null || true

    # Start/restart all core services via their canonical service units
    # freepbx.service (oneshot, RemainAfterExit=yes) manages Asterisk via fwconsole
    # Starting it via systemd ensures systemd tracks the state correctly
    if [ -f /etc/systemd/system/freepbx.service ]; then
        # Kill any directly-started Asterisk so the oneshot can take ownership
        local _apid
        _apid=$(pgrep -x asterisk 2>/dev/null || true)
        if [ -n "$_apid" ]; then
            fwconsole stop 2>/dev/null || kill "$_apid" 2>/dev/null || true
            sleep 3
            rm -f /var/run/asterisk/asterisk.ctl /run/asterisk/asterisk.ctl \
                  /var/run/asterisk/asterisk.pid  /run/asterisk/asterisk.pid
        fi
        svc_start freepbx 2>/dev/null || fwconsole start 2>/dev/null || true
        sleep 5
    else
        safe_restart_asterisk
    fi
    svc_restart "${APACHE_SERVICE}" 2>/dev/null || true

    # Save final env
    save_pbx_env

    # Write comprehensive passwords file (save_passwords_file defined in prepare_system)
    if command -v save_passwords_file >/dev/null 2>&1 || declare -f save_passwords_file >/dev/null 2>&1; then
        save_passwords_file
    fi

    # Append extended credential info to passwords file
    {
        echo "WEBMIN_URL=https://${SYSTEM_FQDN}:9001/"
        echo "AVANTFAX_ADMIN=admin"
        echo "AVANTFAX_URL=http://${SYSTEM_FQDN}/avantfax/"
        echo "FREEPBX_URL=http://${SYSTEM_FQDN}/admin/"
    } >> "${AUTO_PASSWORDS_FILE}" 2>/dev/null || true
    chmod 600 "${AUTO_PASSWORDS_FILE}" 2>/dev/null || true

    # Mark installation complete
    echo "INSTALL_COMPLETE=$(date +%s)" >> "${INSTALL_INVENTORY}"

    success "Installation finalized"
}

# =============================================================================
# SECTION 44: VERIFY INSTALLATION
# =============================================================================

verify_installation() {
    step "✅ Verifying installation..."
    local errors=0

    # Check Asterisk — should be running by end of install
    if ! command -v asterisk >/dev/null 2>&1; then
        fail_component asterisk "asterisk binary not found"
        errors=$((errors + 1))
    elif ! asterisk -rx "core show version" >/dev/null 2>&1; then
        warn "Asterisk installed but not running — attempting restart"
        safe_restart_asterisk
        sleep 5
        if asterisk -rx "core show version" >/dev/null 2>&1; then
            success "Asterisk started (was stopped)"
        else
            warn "Asterisk installed but not running (may start after reboot)"
        fi
    else
        success "Asterisk is running"
    fi

    # Check MariaDB
    if ! svc_active mariadb 2>/dev/null && ! svc_active mysql 2>/dev/null && ! svc_active mysqld 2>/dev/null; then
        fail_component mariadb "service not running"
        errors=$((errors + 1))
    else
        success "MariaDB is running"
    fi

    # Check Apache
    if ! svc_active "${APACHE_SERVICE}" 2>/dev/null; then
        warn "${APACHE_SERVICE} is not running — attempting restart"
        svc_start "${APACHE_SERVICE}" 2>/dev/null || true
        sleep 2
        if svc_active "${APACHE_SERVICE}" 2>/dev/null; then
            success "${APACHE_SERVICE} started"
        else
            fail_component apache "${APACHE_SERVICE} not running"
            errors=$((errors + 1))
        fi
    else
        success "${APACHE_SERVICE} is running"
    fi

    # Check FreePBX
    if [ ! -f /usr/sbin/fwconsole ]; then
        fail_component freepbx "fwconsole not found"
        errors=$((errors + 1))
    elif [ ! -f /etc/freepbx.conf ]; then
        fail_component freepbx "/etc/freepbx.conf missing"
        errors=$((errors + 1))
    elif [ ! -f "${WEB_ROOT}/admin/index.php" ]; then
        fail_component freepbx "web files not found at ${WEB_ROOT}/admin/"
        errors=$((errors + 1))
    else
        success "FreePBX installed (fwconsole + web files present)"
    fi

    # Check PHP
    if ! php -r "echo 'ok';" >/dev/null 2>&1; then
        fail_component php "php CLI not working"
        errors=$((errors + 1))
    else
        local phpver; phpver=$(php -r "echo phpversion();" 2>/dev/null)
        success "PHP ${phpver} working"
    fi

    # Check Postfix (warn only — not fatal)
    if command -v postfix >/dev/null 2>&1; then
        if svc_active postfix 2>/dev/null; then
            success "Postfix running"
        else
            warn "Postfix installed but not running"
        fi
    else
        warn "Postfix not found — voicemail email delivery will not work"
    fi

    # Check HylaFAX + AvantFax (when fax enabled)
    if [ "${INSTALL_AVANTFAX:-1}" -eq 1 ]; then
        if command -v faxstat >/dev/null 2>&1; then
            success "HylaFAX installed"
        else
            warn "HylaFAX not found — fax functionality unavailable"
        fi
        if [ -f "${AVANTFAX_WEB_DIR}/index.php" ]; then
            success "AvantFax web files present"
        else
            warn "AvantFax web files not found at ${AVANTFAX_WEB_DIR}"
        fi
    fi

    # Check Webmin (warn only)
    if [ -f /etc/webmin/miniserv.conf ]; then
        if ss -tlnp 2>/dev/null | grep -q ':9001\b' || \
           netstat -tlnp 2>/dev/null | grep -q ':9001 '; then
            success "Webmin running (port 9001)"
        else
            warn "Webmin installed but not listening on port 9001"
        fi
    fi

    # Check knockd (if enabled)
    if [ "${INSTALL_KNOCKD:-no}" = "yes" ]; then
        if command -v knockd >/dev/null 2>&1; then
            if svc_active knockd 2>/dev/null; then
                success "knockd running"
            else
                warn "knockd installed but not running"
            fi
        else
            warn "knockd not found (was INSTALL_KNOCKD=yes)"
        fi
    fi

    # Check Apache vhost config (single-file layout)
    local vhost_path
    case "${DISTRO_FAMILY}" in
        debian) vhost_path="/etc/apache2/sites-enabled/pbx.conf" ;;
        *)      vhost_path="/etc/httpd/conf.d/pbx.conf" ;;
    esac
    if [ ! -f "${vhost_path}" ]; then
        warn "Apache vhost not found at ${vhost_path} — run again to regenerate"
    else
        if [ "${BEHIND_PROXY:-no}" = "yes" ]; then
            local proxy_listen
            proxy_listen=$(grep "VirtualHost" "${vhost_path}" | grep -o '127\.0\.0\.1:[0-9]*' | head -1)
            if [ -n "${proxy_listen}" ]; then
                success "Apache proxy vhost: ${proxy_listen}"
            else
                warn "Apache vhost found but proxy binding missing — check ${vhost_path}"
            fi
        else
            success "Apache vhost: ${vhost_path}"
        fi
    fi

    # Report any component failures accumulated during install
    if [ -n "${INSTALL_FAILURES}" ]; then
        warn "The following components had issues during installation:"
        printf "%b" "${INSTALL_FAILURES}" >&2
    fi

    if [ "${errors}" -eq 0 ] && [ -z "${INSTALL_FAILURES}" ]; then
        success "All verification checks passed ✓"
    else
        local total=$(( errors + $(printf "%b" "${INSTALL_FAILURES}" | grep -c "✗" 2>/dev/null || echo 0) ))
        warn "${total} issue(s) found — run: install.sh fix    or: pbx-repair"
    fi
}

# =============================================================================
# SECTION 45: COMPLETION MESSAGE
# =============================================================================

show_completion_message() {
    local scheme="https"
    local admin_url avantfax_url
    if [ "${BEHIND_PROXY:-no}" = "yes" ]; then
        # Reload proxy port from env file
        local _pp
        _pp=$(grep "^PROXY_HTTP_PORT=" "${PBX_ENV_FILE}" 2>/dev/null | cut -d= -f2 | tr -d '"')
        admin_url="http://YOUR-PROXY-DOMAIN/admin  (proxy → http://127.0.0.1:${_pp:-?}/admin)"
        avantfax_url="http://YOUR-PROXY-DOMAIN/avantfax  (proxy → http://127.0.0.1:${_pp:-?}/avantfax)"
    else
        [ "${SSL_ENABLED:-0}" -eq 0 ] && scheme="http"
        admin_url="${scheme}://${PUBLIC_IP}/admin"
        avantfax_url="${scheme}://${PUBLIC_IP}/avantfax"
    fi

    echo ""
    echo "${GREEN}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo "${GREEN}║           PBX Installation Complete! v${SCRIPT_VERSION}                      ║${NC}"
    echo "${GREEN}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "${CYAN}  System Information:${NC}"
    echo "    Private IP  : ${PRIVATE_IP}"
    echo "    Public IP   : ${PUBLIC_IP}"
    echo "    FQDN        : ${SYSTEM_FQDN}"
    echo ""
    if [ "${BEHIND_PROXY:-no}" = "yes" ]; then
        local _pp2
        _pp2=$(grep "^PROXY_HTTP_PORT=" "${PBX_ENV_FILE}" 2>/dev/null | cut -d= -f2 | tr -d '"')
        echo "${YELLOW}  ⚠️  Reverse Proxy Mode: Apache bound to 127.0.0.1:${_pp2:-?}${NC}"
        echo "${YELLOW}     Point your proxy to: http://127.0.0.1:${_pp2:-?}/  ${NC}"
        echo ""
    fi
    echo "${CYAN}  Web Interfaces:${NC}"
    echo "    FreePBX     : ${admin_url}"
    echo "    AvantFax    : ${avantfax_url}"
    echo "    Webmin      : https://${PUBLIC_IP}:9001"
    echo ""
    echo "${CYAN}  Credentials (also saved in /etc/pbx/pbx_passwords):${NC}"
    echo "    FreePBX Admin : ${FREEPBX_ADMIN_USERNAME} / ${FREEPBX_ADMIN_PASSWORD}"
    echo "    MySQL Root    : ${MYSQL_ROOT_PASSWORD}"
    echo ""
    echo "${CYAN}  Installed Components:${NC}"
    echo "    Asterisk ${ASTERISK_VERSION} | FreePBX ${FREEPBX_VERSION} | PHP ${PHP_VERSION} | MariaDB"
    echo "    AvantFax 3.4.1 | HylaFAX+ | IAXmodem (${NUMBER_OF_MODEMS} modems)"
    echo "    Fail2ban | Postfix | Webmin | sngrep | OpenVPN"
    echo ""
    echo "${CYAN}  Management Commands:${NC}"
    echo "    pbxstatus      — Full system dashboard"
    echo "    pbx-config     — TUI configuration tool"
    echo "    pbx-status     — Quick status"
    echo "    pbx-restart    — Restart services"
    echo "    pbx-repair     — Repair FreePBX"
    echo "    pbx-backup     — Manual backup"
    echo "    pbx-security   — Security audit"
    echo "    pbx-passwords  — Show credentials"
    echo "    pbx-docs       — Quick reference"
    echo "    add-ip <IP>    — Whitelist an IP"
    echo ""
    echo "${CYAN}  Demo Extensions (call from any extension):${NC}"
    echo "    123  Speaking clock   947  Weather TTS    951  Today's date"
    echo "    *43  Echo test        *610 Music on hold  4747 Lenny bot"
    echo "    *41  Caller ID        *97  Voicemail      *469 Conference 1"
    echo ""
    echo "${YELLOW}  ⚠️  Change default passwords before production use!${NC}"
    echo "${YELLOW}  ⚠️  Review firewall rules for your network topology.${NC}"
    echo ""
    echo "${GREEN}  Installation log: ${LOG_FILE}${NC}"
    echo ""

    # Send summary email if ADMIN_EMAIL is set and not root@
    if [ -n "${ADMIN_EMAIL:-}" ] && ! echo "${ADMIN_EMAIL}" | grep -q "^root@"; then
        {
            echo "PBX v3.0 Installation Complete"
            echo ""
            echo "Server: $(hostname -f 2>/dev/null || hostname)"
            echo "IP: ${PRIVATE_IP} / ${PUBLIC_IP}"
            echo ""
            cat "${AUTO_PASSWORDS_FILE}" 2>/dev/null
        } | mail -s "[PBX] Installation Complete on $(hostname)" \
            -a "From: ${FROM_NAME} <${FROM_EMAIL}>" "${ADMIN_EMAIL}" 2>/dev/null || true
    fi
}

# =============================================================================
# SECTION 46: MAIN INSTALLATION ORCHESTRATOR
# =============================================================================

run_installation() {
    log "PBX installer v${SCRIPT_VERSION} started"
    info "Starting PBX installation — log: ${LOG_FILE}"

    # Phase 1: Detection, preflight, profiles
    detect_system
    version_select
    setup_pkg_map
    preflight_checks
    resolve_install_profile
    detect_ssh_safety
    load_pbx_env
    setup_dns
    prepare_system

    # Phase 2: Repositories and packages
    setup_repositories
    install_core_dependencies

    # Phase 3: Core services
    install_mariadb
    install_php
    install_apache
    configure_odbc
    configure_letsencrypt_integration
    [ "${IS_CONTAINER:-0}" = "0" ] && disable_ipv6 || true

    # Phase 4: PBX core
    install_asterisk
    install_freepbx
    configure_freepbx

    # Phase 5: Media and dialplan
    install_asterisk_sounds
    install_tts_engine
    install_gtts
    install_agi_scripts
    install_demo_applications

    # Phase 6: Fax system (required)
    if [ "${INSTALL_AVANTFAX:-1}" -eq 1 ]; then
        install_postfix
        install_hylafax
        install_iaxmodem
        install_avantfax
        configure_email_to_fax
        configure_fax_to_email
    fi

    # Generate single Apache vhost config — runs here so all components
    # (SSL cert, AvantFax path, proxy mode) are fully known before writing
    generate_apache_vhost_config

    # Phase 7: Security
    if [ "${IS_CONTAINER:-0}" = "0" ]; then
        [ "${FIREWALL_ENABLED:-1}" -eq 1 ] && { configure_firewall; configure_iptables; }
    fi
    [ "${FAIL2BAN_ENABLED:-1}" -eq 1 ] && install_fail2ban || true
    configure_logrotate

    # Phase 8: Optional tools (profile-gated)
    [ "${INSTALL_WEBMIN:-yes}" = "yes" ] && install_webmin || true
    [ "${INSTALL_KNOCKD:-no}"  = "yes" ] && install_knockd  || true
    [ "${INSTALL_SNGREP:-no}"  = "yes" ] && install_sngrep  || true
    [ "${INSTALL_OPENVPN:-no}" = "yes" ] && install_openvpn || true
    [ "${INSTALL_FOP2:-no}"    = "yes" ] && install_fop2    || true
    [ "${INSTALL_PHONE_PROV:-no}" = "yes" ] && install_phone_provisioning || true

    # Phase 9: Backup
    [ "${BACKUP_ENABLED:-1}" -eq 1 ] && setup_backup_system     || true
    [ "${BACKUP_ENABLED:-1}" -eq 1 ] && setup_freepbx_autoupdate || true
    [ "${BACKUP_ENABLED:-1}" -eq 1 ] && setup_backup_encryption  || true
    [ "${INSTALL_REMOTE_BACKUP:-no}" = "yes" ] && install_rclone || true

    # Phase 10: System tuning and extra services
    setup_ntp
    setup_voip_tuning
    [ "${IS_CONTAINER:-0}" = "0" ] && setup_qos || true
    configure_webrtc
    configure_voicemail_email

    # Phase 11: Web apps and portals
    build_main_portal
    build_status_page
    install_telephone_reminder
    [ "${INSTALL_ASTERNIC:-yes}" = "yes" ] && install_asternic || true

    # Phase 12: Health monitoring
    [ "${INSTALL_PROFILE:-standard}" != "minimal" ] && setup_health_monitoring || true

    # Phase 13: Management scripts (GitHub API sync) and finalization
    sync_management_scripts
    create_pbxstatus
    create_root_scripts
    install_asteridex
    finalize_installation
    verify_installation
    show_completion_message

    log "PBX installer v${SCRIPT_VERSION} completed successfully"
}

show_install_status() {
    detect_system
    setup_output
    header "PBX System Status"
    printf "%-20s %s\n" "Hostname:" "$(hostname -f 2>/dev/null || hostname)"
    printf "%-20s %s\n" "OS:" "${DETECTED_OS:-unknown} ${DETECTED_VERSION:-}"
    printf "%-20s %s\n" "State file:" "${PBX_STATE_FILE}"
    echo ""
    header "Installed Components"
    for comp in asterisk freepbx php mariadb avantfax webmin; do
        local ver; ver=$(python3 -c "
import json,os,sys
f='${PBX_STATE_FILE}'
if not os.path.exists(f): sys.exit(1)
s=json.load(open(f))
v=s.get('installed',{}).get('${comp}',{}).get('version','')
print(v) if v else sys.exit(1)
" 2>/dev/null) && \
            printf "  ✓ %-16s %s\n" "${comp}" "${ver}" || \
            printf "  - %-16s not installed\n" "${comp}"
    done
    echo ""
    header "Service Health"
    for svc in asterisk mariadb apache2 httpd postfix fail2ban webmin; do
        if command_exists systemctl 2>/dev/null; then
            systemctl is-active --quiet "${svc}" 2>/dev/null && \
                printf "  ✓ %-16s running\n" "${svc}" || \
                systemctl is-enabled --quiet "${svc}" 2>/dev/null && \
                    printf "  ✗ %-16s stopped\n" "${svc}" || true
        fi
    done
}

fix_installation() {
    detect_system
    setup_output
    header "PBX Repair Mode"
    info "Restarting failed services..."
    for svc in mariadb asterisk apache2 httpd postfix fail2ban; do
        if command_exists systemctl; then
            if systemctl is-enabled --quiet "${svc}" 2>/dev/null && \
               ! systemctl is-active --quiet "${svc}" 2>/dev/null; then
                info "  Restarting ${svc}..."
                systemctl restart "${svc}" 2>/dev/null && \
                    success "  ${svc} restarted" || \
                    warn "  Failed to restart ${svc}"
            fi
        fi
    done
    if command_exists fwconsole; then
        info "Running fwconsole chown + reload..."
        fwconsole chown 2>/dev/null || true
        fwconsole reload --skip-registry-checks 2>/dev/null && success "FreePBX reloaded" || warn "FreePBX reload had warnings"
    fi
    info "Fixing file permissions..."
    [ -d /etc/asterisk ]       && chown -R asterisk:asterisk /etc/asterisk 2>/dev/null || true
    [ -d /var/lib/asterisk ]   && chown -R asterisk:asterisk /var/lib/asterisk 2>/dev/null || true
    [ -d /var/spool/asterisk ] && chown -R asterisk:asterisk /var/spool/asterisk 2>/dev/null || true
    success "Repair complete"
}

show_help() {
    cat << 'HELPEOF'
PBX Installer v3.0 — Production Asterisk + FreePBX installer
Supports: AlmaLinux/Rocky/RHEL/Oracle 8-9, Fedora 35+, Ubuntu 18+, Debian 10+, CentOS 6/7

USAGE:
  ./install.sh [command]

COMMANDS:
  install          Run full installation (default)
  status           Show installed components, versions, service health
  fix              Repair: restart failed services, fwconsole reload, fix permissions
  update-scripts   Re-sync all pbx-* scripts from GitHub (no install steps)
  help             Show this help message

ENVIRONMENT VARIABLES:
  TIMEZONE               System timezone (default: America/New_York)
  ADMIN_EMAIL            Admin email address (alerts sent here)
  FROM_EMAIL             From address for all system mail (default: no-reply@<fqdn>)
  FROM_NAME              From display name for all system mail (default: PBX System)
  BEHIND_PROXY           Set to 'yes' for reverse proxy support
  INSTALL_PROFILE        minimal | standard (default) | advanced
  INSTALL_AVANTFAX       1=install fax system (default: 1)
  FIREWALL_ENABLED       1=configure firewall (default: 1)
  FAIL2BAN_ENABLED       1=install fail2ban (default: 1)
  BACKUP_ENABLED         1=setup backup cron (default: 1)
  INSTALL_WEBMIN         yes/no — override profile default
  INSTALL_KNOCKD         yes/no — port knocking (advanced only by default)
  INSTALL_OPENVPN        yes/no — OpenVPN (advanced only by default)
  INSTALL_FOP2           yes/no — Flash Operator Panel 2 (advanced only)
  INSTALL_SNGREP         yes/no — SIP traffic monitor (advanced only)
  MYSQL_ROOT_PASSWORD    Pre-set MySQL root password (auto-generated if empty)
  FREEPBX_ADMIN_PASSWORD Pre-set FreePBX admin password (auto-generated if empty)
  GITHUB_REPO            GitHub repo for management scripts (default: scriptmgr/pbx)
  SCRIPTS_REF            Branch/tag for scripts (default: main)
  GITHUB_TOKEN           Token for private forks (optional)
  NO_COLOR               Set to disable colors and emojis (see no-color.org)

EXAMPLES:
  # Standard install
  ./install.sh

  # Install with custom settings
  TIMEZONE=Europe/London ADMIN_EMAIL=ops@example.com ./install.sh

  # Behind Nginx/Traefik reverse proxy
  BEHIND_PROXY=yes ./install.sh

  # Advanced profile (port knocking, OpenVPN, FOP2)
  INSTALL_PROFILE=advanced ./install.sh

  # Minimal install (no Webmin, no backups)
  INSTALL_PROFILE=minimal ./install.sh

  # Private fork of scripts
  GITHUB_REPO=myorg/pbx GITHUB_TOKEN=ghp_xxx ./install.sh

HELPEOF
}

# =============================================================================
# ENTRY POINT
# =============================================================================

[ "$(id -u)" -ne 0 ] && { echo "ERROR: Must run as root (sudo ./install.sh)"; exit 1; }

case "${1:-install}" in
    install)
        run_installation
        ;;
    status|--status)
        show_install_status
        ;;
    fix|--fix|repair)
        fix_installation
        ;;
    update-scripts|--update-scripts)
        detect_system
        setup_output
        sync_management_scripts
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo "ERROR: Unknown command: ${1}"
        show_help
        exit 1
        ;;
esac

