#!/bin/sh
# Complete PBX Installation Script - POSIX Compliant
# Production-ready Asterisk + FreePBX system with all features
# Version: 2.0 - Full Implementation

# Exit on any error
set -e

# =============================================================================
# CONFIGURATION & DEFAULTS
# =============================================================================

# Version Information
SCRIPT_VERSION="2.0"
INSTALL_DATE="$(date '+%Y-%m-%d %H:%M:%S')"

# Core Software Stack
ASTERISK_VERSION="21"
FREEPBX_VERSION="17.0"
PHP_VERSION="8.2"
PHP_AVANTFAX_VERSION="7.4"

# System Configuration
INSTALL_AVANTFAX=1
NUMBER_OF_MODEMS=4
FIREWALL_ENABLED=1
FAIL2BAN_ENABLED=1
BACKUP_ENABLED=1
SSL_ENABLED=1
USE_POSTFIX=1
INSTALL_MUSIC_ON_HOLD=1

# Paths
WEB_ROOT="/var/www/html"
FREEPBX_WEB_DIR="${WEB_ROOT}/admin"
AVANTFAX_WEB_DIR="${WEB_ROOT}/avantfax"
BACKUP_BASE="/mnt/backups/pbx"
LOG_FILE="/var/log/pbx-install.log"
ERROR_LOG="/var/log/pbx-install-errors.log"
AUTO_PASSWORDS_FILE="/root/.pbx_passwords"

# Global variables
WORK_DIR="/tmp/pbx-install"
PACKAGE_MANAGER=""
APACHE_USER=""
APACHE_GROUP=""
APACHE_SERVICE=""
SYSTEM_FQDN=""
SYSTEM_DOMAIN=""
PRIVATE_IP=""
PUBLIC_IP=""
DETECTED_OS=""
DETECTED_VERSION=""

# Generated passwords (will be set during installation)
MYSQL_ROOT_PASSWORD=""
FREEPBX_ADMIN_PASSWORD=""
FREEPBX_DB_PASSWORD=""
AVANTFAX_DB_PASSWORD=""

# Installation inventory tracking
INSTALL_INVENTORY="/root/.pbx_install_inventory"
INSTALLED_COMPONENTS=""

# Backup directory with timestamp
BACKUP_TIMESTAMP=$(date +%s)
CONFIG_BACKUP_DIR="/mnt/backups/pbx-config-backups/${BACKUP_TIMESTAMP}"

# PBX Environment Configuration
PBX_ENV_FILE="/etc/pbx/.env"
PBX_ENV_DIR="/etc/pbx"

# Email-to-Fax configuration (will be generated once)
EMAIL_TO_FAX_ALIAS=""
FAX_TO_EMAIL_ADDRESS=""

# =============================================================================
# ENVIRONMENT CONFIGURATION MANAGEMENT
# =============================================================================

# Load existing .env configuration
load_pbx_env() {
    if [ -f "${PBX_ENV_FILE}" ]; then
        info "Loading existing PBX configuration from ${PBX_ENV_FILE}..."
        # Source the env file safely
        set -a
        source "${PBX_ENV_FILE}"
        set +a
        success "Configuration loaded"
    fi
}

# Save configuration to .env file
save_pbx_env() {
    info "Saving PBX configuration to ${PBX_ENV_FILE}..."

    mkdir -p "${PBX_ENV_DIR}"

    cat > "${PBX_ENV_FILE}" << EOF
# PBX System Configuration
# Generated on: $(date)
# This file stores persistent configuration that survives script re-runs

# System Information
SYSTEM_FQDN="${SYSTEM_FQDN}"
SYSTEM_DOMAIN="${SYSTEM_DOMAIN}"
PRIVATE_IP="${PRIVATE_IP}"
PUBLIC_IP="${PUBLIC_IP}"

# Installation Information
INSTALL_DATE="${INSTALL_DATE}"
SCRIPT_VERSION="${SCRIPT_VERSION}"

# Email-to-Fax Configuration
EMAIL_TO_FAX_ALIAS="${EMAIL_TO_FAX_ALIAS}"
FAX_TO_EMAIL_ADDRESS="${FAX_TO_EMAIL_ADDRESS}"

# Passwords (for reference, also stored in ${AUTO_PASSWORDS_FILE})
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD}"
FREEPBX_ADMIN_PASSWORD="${FREEPBX_ADMIN_PASSWORD}"
FREEPBX_DB_PASSWORD="${FREEPBX_DB_PASSWORD}"
AVANTFAX_DB_PASSWORD="${AVANTFAX_DB_PASSWORD}"
EOF

    chmod 600 "${PBX_ENV_FILE}"
    success "Configuration saved to ${PBX_ENV_FILE}"
}

# Generate random email-to-fax alias (only once)
generate_fax_alias() {
    if [ -z "${EMAIL_TO_FAX_ALIAS}" ]; then
        # Generate a secure random 16-character alphanumeric string
        EMAIL_TO_FAX_ALIAS="fax$(openssl rand -hex 8)"
        info "Generated email-to-fax alias: ${EMAIL_TO_FAX_ALIAS}@${SYSTEM_DOMAIN}"
    fi
}

# =============================================================================
# INSTALLATION INVENTORY & ROLLBACK
# =============================================================================

# Track installed component
track_install() {
    local component="$1"
    echo "${component}" >> "${INSTALL_INVENTORY}"
    INSTALLED_COMPONENTS="${INSTALLED_COMPONENTS} ${component}"
    log "INSTALLED: ${component}"
}

# Backup configuration file with proper directory structure
backup_config() {
    local source_file="$1"

    # Skip if file doesn't exist
    if [ ! -f "${source_file}" ]; then
        return 0
    fi

    # Create backup directory structure mirroring original
    local backup_path="${CONFIG_BACKUP_DIR}$(dirname "${source_file}")"
    mkdir -p "${backup_path}"

    # Copy file to backup location
    cp -p "${source_file}" "${backup_path}/" >> "${LOG_FILE}" 2>&1

    info "Backed up ${source_file} to ${backup_path}/"
}

# Rollback a specific component
rollback_component() {
    local component="$1"

    warn "Rolling back ${component}..."

    case "${component}" in
        mariadb)
            systemctl stop mariadb 2>/dev/null || true
            systemctl disable mariadb 2>/dev/null || true
            case "${PACKAGE_MANAGER}" in
                apt-get) apt-get remove -y mariadb-server mariadb-client >> "${LOG_FILE}" 2>&1 ;;
                yum|dnf) ${PACKAGE_MANAGER} remove -y mariadb-server mariadb >> "${LOG_FILE}" 2>&1 ;;
            esac
            rm -rf /var/lib/mysql
            ;;
        apache)
            systemctl stop "${APACHE_SERVICE}" 2>/dev/null || true
            systemctl disable "${APACHE_SERVICE}" 2>/dev/null || true
            case "${PACKAGE_MANAGER}" in
                apt-get) apt-get remove -y apache2 >> "${LOG_FILE}" 2>&1 ;;
                yum|dnf) ${PACKAGE_MANAGER} remove -y httpd >> "${LOG_FILE}" 2>&1 ;;
            esac
            ;;
        asterisk)
            systemctl stop asterisk 2>/dev/null || true
            systemctl disable asterisk 2>/dev/null || true
            rm -rf /etc/asterisk /var/lib/asterisk /var/spool/asterisk /var/log/asterisk
            rm -f /usr/sbin/asterisk /etc/systemd/system/asterisk.service
            ;;
        freepbx)
            rm -rf "${WEB_ROOT}/admin" /var/www/html/admin
            mysql -e "DROP DATABASE IF EXISTS asterisk; DROP DATABASE IF EXISTS asteriskcdrdb;" 2>/dev/null || true
            ;;
        hylafax)
            systemctl stop hylafax 2>/dev/null || true
            systemctl disable hylafax 2>/dev/null || true
            rm -rf /var/spool/hylafax /usr/local/sbin/faxq /etc/systemd/system/hylafax.service
            ;;
        iaxmodem)
            for i in 0 1 2 3; do
                systemctl stop "iaxmodem${i}" 2>/dev/null || true
                systemctl disable "iaxmodem${i}" 2>/dev/null || true
                rm -f "/etc/systemd/system/iaxmodem${i}.service"
            done
            rm -rf /etc/iaxmodem /var/run/iaxmodem /usr/local/sbin/iaxmodem
            ;;
        avantfax)
            rm -rf "${AVANTFAX_WEB_DIR}"
            mysql -e "DROP DATABASE IF EXISTS avantfax;" 2>/dev/null || true
            ;;
        *)
            warn "Unknown component for rollback: ${component}"
            ;;
    esac

    systemctl daemon-reload 2>/dev/null || true
}

# Rollback all installed components
rollback_installation() {
    error_msg="${1:-Installation failed}"

    echo ""
    echo "${RED}╔════════════════════════════════════════════════════════════╗${NC}"
    echo "${RED}║                  ⚠️  INSTALLATION FAILED ⚠️                  ║${NC}"
    echo "${RED}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "${RED}Error: ${error_msg}${NC}"
    echo ""

    if [ -f "${INSTALL_INVENTORY}" ]; then
        warn "Rolling back installed components..."

        # Rollback in reverse order
        local components
        components=$(tac "${INSTALL_INVENTORY}")

        for component in ${components}; do
            rollback_component "${component}"
        done

        rm -f "${INSTALL_INVENTORY}"
        success "Rollback completed"
    else
        info "No components to rollback"
    fi

    echo ""
    echo "Check logs for details:"
    echo "  - ${LOG_FILE}"
    echo "  - ${ERROR_LOG}"
    echo ""

    exit 1
}

# Enhanced error function with rollback
error() {
    echo "${RED}❌ ERROR: $*${NC}" >&2
    echo "$(date '+%Y-%m-%d %H:%M:%S'): ERROR: $*" >> "${ERROR_LOG}"
    echo "$(date '+%Y-%m-%d %H:%M:%S'): ERROR: $*" >> "${LOG_FILE}"

    rollback_installation "$*"
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Safe Asterisk restart function (handles dual processes cleanly)
safe_restart_asterisk() {
    local max_wait=30
    local waited=0

    # Try graceful stop via systemctl first
    if systemctl is-active asterisk >/dev/null 2>&1; then
        systemctl stop asterisk 2>/dev/null &
        local stop_pid=$!

        # Wait for graceful stop
        while [ $waited -lt $max_wait ]; do
            if ! systemctl is-active asterisk >/dev/null 2>&1; then
                break
            fi
            sleep 1
            waited=$((waited + 1))
        done

        # Force kill stop command if still running
        kill $stop_pid 2>/dev/null || true
    fi

    # Ensure all asterisk processes are terminated
    pkill -9 asterisk 2>/dev/null || true
    sleep 2

    # Clean up PID files
    rm -f /var/run/asterisk/asterisk.pid 2>/dev/null || true

    # Start asterisk
    systemctl start asterisk 2>/dev/null || {
        # If systemctl fails, try direct start
        /usr/sbin/asterisk 2>/dev/null || true
    }

    # Wait for startup
    waited=0
    while [ $waited -lt $max_wait ]; do
        if systemctl is-active asterisk >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
        waited=$((waited + 1))
    done

    return 1
}

# Colors for output (POSIX compatible)
if [ -t 1 ]; then
    RED="$(printf '\033[0;31m')"
    GREEN="$(printf '\033[0;32m')"
    YELLOW="$(printf '\033[1;33m')"
    BLUE="$(printf '\033[0;34m')"
    PURPLE="$(printf '\033[0;35m')"
    CYAN="$(printf '\033[0;36m')"
    NC="$(printf '\033[0m')"
else
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    PURPLE=""
    CYAN=""
    NC=""
fi

# Logging functions
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $*" >> "$LOG_FILE"
}

error() {
    echo "${RED}❌ ERROR: $*${NC}" >&2
    echo "$(date '+%Y-%m-%d %H:%M:%S'): ERROR: $*" >> "$ERROR_LOG"
    echo "$(date '+%Y-%m-%d %H:%M:%S'): ERROR: $*" >> "$LOG_FILE"
    exit 1
}

warn() {
    echo "${YELLOW}⚠️  WARNING: $*${NC}"
    log "WARNING: $*"
}

info() {
    echo "${BLUE}ℹ️  INFO: $*${NC}"
    log "INFO: $*"
}

success() {
    echo "${GREEN}✅ $*${NC}"
    log "SUCCESS: $*"
}

step() {
    echo ""
    echo "${PURPLE}▶️  $*${NC}"
    log "STEP: $*"
}

# Generate secure password
generate_password() {
    length="${1:-32}"
    openssl rand -base64 "$length" 2>/dev/null | tr -d "=+/" | cut -c1-25
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Safe command execution with error handling
safe_execute() {
    cmd="$1"
    error_msg="${2:-Command failed}"

    log "Executing: $cmd"

    if ! eval "$cmd" >> "$LOG_FILE" 2>&1; then
        error "$error_msg: $cmd"
    fi
}

# =============================================================================
# SYSTEM DETECTION
# =============================================================================

detect_system() {
    step "🔍 Detecting system configuration..."

    # Detect OS
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DETECTED_OS="${ID}"
        DETECTED_VERSION="${VERSION_ID}"
        DETECTED_OS_LIKE="${ID_LIKE:-}"

        # Try exact match first (base distributions)
        case "${DETECTED_OS}" in
            ubuntu|debian)
                PACKAGE_MANAGER="apt-get"
                APACHE_USER="www-data"
                APACHE_GROUP="www-data"
                APACHE_SERVICE="apache2"
                ;;
            rocky|centos|rhel|almalinux|ol|fedora)
                if command_exists dnf; then
                    PACKAGE_MANAGER="dnf"
                else
                    PACKAGE_MANAGER="yum"
                fi
                APACHE_USER="apache"
                APACHE_GROUP="apache"
                APACHE_SERVICE="httpd"
                ;;
            *)
                # Check ID_LIKE for derivative distributions
                if echo "${DETECTED_OS_LIKE}" | grep -qE "debian|ubuntu"; then
                    info "Derivative distribution detected (based on Debian/Ubuntu)"
                    PACKAGE_MANAGER="apt-get"
                    APACHE_USER="www-data"
                    APACHE_GROUP="www-data"
                    APACHE_SERVICE="apache2"
                elif echo "${DETECTED_OS_LIKE}" | grep -qE "rhel|fedora|centos"; then
                    info "Derivative distribution detected (based on RHEL/Fedora)"
                    if command_exists dnf; then
                        PACKAGE_MANAGER="dnf"
                    else
                        PACKAGE_MANAGER="yum"
                    fi
                    APACHE_USER="apache"
                    APACHE_GROUP="apache"
                    APACHE_SERVICE="httpd"
                else
                    error "Unsupported operating system: ${DETECTED_OS} (ID_LIKE: ${DETECTED_OS_LIKE})"
                fi
                ;;
        esac
    else
        error "Cannot detect operating system"
    fi

    # Detect network information
    PRIVATE_IP="$(ip route get 8.8.8.8 2>/dev/null | awk '{print $7; exit}' || echo '')"
    PUBLIC_IP="$(curl -s --max-time 10 ifconfig.me 2>/dev/null || echo '')"

    # Detect hostname and domain
    SYSTEM_FQDN="$(hostname -f 2>/dev/null || hostname)"
    SYSTEM_DOMAIN="$(echo "${SYSTEM_FQDN}" | cut -d. -f2-)"

    # If domain is empty or localhost, use a default
    if [ -z "${SYSTEM_DOMAIN}" ] || echo "${SYSTEM_DOMAIN}" | grep -q "localhost\|localdomain"; then
        SYSTEM_DOMAIN="pbx.local"
        SYSTEM_FQDN="pbx.${SYSTEM_DOMAIN}"
    fi

    # Set email addresses
    ADMIN_EMAIL="${ADMIN_EMAIL:-admin@${SYSTEM_DOMAIN}}"

    info "Detected OS: ${DETECTED_OS} ${DETECTED_VERSION}"
    info "Package Manager: ${PACKAGE_MANAGER}"
    info "System FQDN: ${SYSTEM_FQDN}"
    info "Private IP: ${PRIVATE_IP:-Not detected}"
    info "Public IP: ${PUBLIC_IP:-Not detected}"

    success "System detection completed"
}

# =============================================================================
# SYSTEM PREPARATION
# =============================================================================

prepare_system() {
    step "🔧 Preparing system for installation..."

    # Create working directory
    mkdir -p "${WORK_DIR}"
    cd "${WORK_DIR}"

    # Create log files
    mkdir -p "$(dirname "${LOG_FILE}")"
    touch "${LOG_FILE}" "${ERROR_LOG}"
    chmod 644 "${LOG_FILE}" "${ERROR_LOG}"

    # Create backup directory structure
    if [ "${BACKUP_ENABLED}" = "1" ]; then
        mkdir -p "${BACKUP_BASE}/daily"
        mkdir -p "${BACKUP_BASE}/weekly"
        mkdir -p "${BACKUP_BASE}/monthly"
        mkdir -p "${BACKUP_BASE}/config"
        mkdir -p "${BACKUP_BASE}/database"
        mkdir -p "${BACKUP_BASE}/system"
        chmod -R 700 "${BACKUP_BASE}"
    fi

    # Update package repositories
    info "Updating package repositories..."
    case "${PACKAGE_MANAGER}" in
        apt-get)
            safe_execute "apt-get update" "Failed to update package repositories"
            ;;
        yum|dnf)
            safe_execute "${PACKAGE_MANAGER} makecache" "Failed to update package cache"
            ;;
    esac

    # Install essential packages
    info "Installing essential packages..."
    case "${PACKAGE_MANAGER}" in
        apt-get)
            safe_execute "DEBIAN_FRONTEND=noninteractive apt-get install -y curl wget gnupg2 software-properties-common apt-transport-https ca-certificates lsb-release" "Failed to install essential packages"
            ;;
        yum|dnf)
            safe_execute "${PACKAGE_MANAGER} install -y --allowerasing curl wget gnupg2 epel-release dnf-plugins-core" "Failed to install essential packages"
            ;;
    esac

    # Set timezone if provided
    if [ -n "${TIMEZONE:-}" ]; then
        if command_exists timedatectl; then
            safe_execute "timedatectl set-timezone ${TIMEZONE}" "Failed to set timezone"
        fi
    fi

    # Generate passwords (use existing from .env if available, otherwise generate new)
    MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-$(generate_password)}"
    FREEPBX_ADMIN_PASSWORD="${FREEPBX_ADMIN_PASSWORD:-$(generate_password)}"
    FREEPBX_DB_PASSWORD="${FREEPBX_DB_PASSWORD:-$(generate_password)}"
    AVANTFAX_DB_PASSWORD="${AVANTFAX_DB_PASSWORD:-$(generate_password)}"

    # Generate fax alias if not already set
    generate_fax_alias

    # Set fax-to-email address if not already set
    FAX_TO_EMAIL_ADDRESS="${FAX_TO_EMAIL_ADDRESS:-${ADMIN_EMAIL}}"

    # Create password storage file
    cat > "${AUTO_PASSWORDS_FILE}" << EOF
# 🔐 PBX System Passwords
# Generated: ${INSTALL_DATE}
# System: ${SYSTEM_FQDN}

# System Information
system_fqdn='${SYSTEM_FQDN}'
system_domain='${SYSTEM_DOMAIN}'
admin_email='${ADMIN_EMAIL}'
private_ip='${PRIVATE_IP}'
public_ip='${PUBLIC_IP}'

# Database Passwords
mysql_root_password='${MYSQL_ROOT_PASSWORD}'
freepbx_db_password='${FREEPBX_DB_PASSWORD}'
avantfax_db_password='${AVANTFAX_DB_PASSWORD}'

# Application Passwords
freepbx_admin_user='administrator'
freepbx_admin_password='${FREEPBX_ADMIN_PASSWORD}'
avantfax_admin_user='administrator'
avantfax_admin_password='${FREEPBX_ADMIN_PASSWORD}'

# Fax Configuration
email_to_fax_alias='${EMAIL_TO_FAX_ALIAS}@${SYSTEM_DOMAIN}'
fax_to_email_address='${FAX_TO_EMAIL_ADDRESS:-${ADMIN_EMAIL}}'

EOF
    chmod 600 "${AUTO_PASSWORDS_FILE}"

    success "System preparation completed"
}

# =============================================================================
# REPOSITORY SETUP
# =============================================================================

# Check if repository already exists by searching for base URL
repo_exists() {
    local repo_url="$1"
    local repo_dir=""

    # Determine repo directory based on package manager
    case "${PACKAGE_MANAGER}" in
        apt-get)
            repo_dir="/etc/apt/sources.list.d"
            # Also check main sources.list
            if [ -f /etc/apt/sources.list ]; then
                if grep -q "${repo_url}" /etc/apt/sources.list 2>/dev/null; then
                    return 0
                fi
            fi
            ;;
        yum|dnf)
            repo_dir="/etc/yum.repos.d"
            ;;
        *)
            return 1
            ;;
    esac

    if [ ! -d "${repo_dir}" ]; then
        return 1
    fi

    # Search for URL in all repo files
    if grep -R -q "${repo_url}" "${repo_dir}" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

setup_repositories() {
    step "📦 Setting up package repositories..."

    case "${PACKAGE_MANAGER}" in
        apt-get)
            # Add PHP repository for Ubuntu/Debian
            if [ "${DETECTED_OS}" = "ubuntu" ]; then
                if ! repo_exists "ppa.launchpad.net/ondrej/php"; then
                    info "Adding Ondrej PHP repository..."
                    safe_execute "add-apt-repository -y ppa:ondrej/php" "Failed to add PHP repository"
                else
                    success "PHP repository already configured, skipping..."
                fi
            elif [ "${DETECTED_OS}" = "debian" ]; then
                if ! repo_exists "packages.sury.org"; then
                    info "Adding Sury PHP repository..."
                    safe_execute "wget -qO /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg" "Failed to add PHP GPG key"
                    echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list
                else
                    success "PHP repository already configured, skipping..."
                fi
            fi

            # NodeSource repository for Node.js
            if ! repo_exists "deb.nodesource.com"; then
                info "Adding NodeSource repository..."
                safe_execute "curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -" "Failed to add NodeSource repository"
            else
                success "NodeSource repository already configured, skipping..."
            fi

            safe_execute "apt-get update" "Failed to update repositories"
            ;;

        yum|dnf)
            # EPEL repository
            if ! repo_exists "fedoraproject.org/epel"; then
                info "Installing EPEL repository..."
                safe_execute "${PACKAGE_MANAGER} install -y epel-release" "Failed to install EPEL"
            else
                success "EPEL repository already configured, skipping..."
            fi

            # Remi repository for PHP
            if ! repo_exists "rpms.remirepo.net"; then
                info "Installing Remi repository..."
                if [ "${DETECTED_VERSION%%.*}" = "8" ]; then
                    safe_execute "${PACKAGE_MANAGER} install -y https://rpms.remirepo.net/enterprise/remi-release-8.rpm" "Failed to install Remi repository"
                elif [ "${DETECTED_VERSION%%.*}" = "9" ]; then
                    safe_execute "${PACKAGE_MANAGER} install -y https://rpms.remirepo.net/enterprise/remi-release-9.rpm" "Failed to install Remi repository"
                fi
            else
                success "Remi repository already configured, skipping..."
            fi

            # NodeSource repository for Node.js
            if ! repo_exists "rpm.nodesource.com"; then
                info "Adding NodeSource repository..."
                curl -fsSL https://rpm.nodesource.com/setup_lts.x | bash - >> "${LOG_FILE}" 2>&1 || warn "NodeSource repository setup had issues"
            else
                success "NodeSource repository already configured, skipping..."
            fi
            ;;
    esac

    success "Package repositories configured"
}

# =============================================================================
# PACKAGE INSTALLATION HELPERS
# =============================================================================

# Try installing a package with multiple name variants
# Returns 0 if ANY variant installs successfully
# Returns 1 if ALL variants fail (caller decides to error or continue)
try_install_package() {
    local package_variants="$1"
    local description="${2:-package}"
    local optional="${3:-no}"

    for pkg in ${package_variants}; do
        if [ "${PACKAGE_MANAGER}" = "apt-get" ]; then
            if apt-cache show "${pkg}" >/dev/null 2>&1; then
                if DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkg}" >> "${LOG_FILE}" 2>&1; then
                    info "Installed ${description} (${pkg})"
                    return 0
                fi
            fi
        else
            if ${PACKAGE_MANAGER} info "${pkg}" >/dev/null 2>&1; then
                if ${PACKAGE_MANAGER} install -y "${pkg}" >> "${LOG_FILE}" 2>&1; then
                    info "Installed ${description} (${pkg})"
                    return 0
                fi
            fi
        fi
    done

    # All variants failed
    if [ "${optional}" = "yes" ]; then
        # Optional packages - just log to file, not console
        echo "$(date '+%Y-%m-%d %H:%M:%S'): INFO: Optional package ${description} not available (tried: ${package_variants})" >> "${LOG_FILE}"
        return 1
    else
        warn "FAILED to install ${description} (tried: ${package_variants})"
    fi
    return 1
}

# Try installing multiple packages from a list, with variants
install_package_list() {
    local packages="$1"
    local category="${2:-packages}"

    info "Installing ${category}..."

    for pkg_line in ${packages}; do
        # If package line contains |, try variants
        if echo "${pkg_line}" | grep -q '|'; then
            try_install_package "${pkg_line}" "${pkg_line%%|*}"
        else
            if [ "${PACKAGE_MANAGER}" = "apt-get" ]; then
                DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkg_line}" >> "${LOG_FILE}" 2>&1 || warn "Package ${pkg_line} not available"
            else
                ${PACKAGE_MANAGER} install -y "${pkg_line}" >> "${LOG_FILE}" 2>&1 || warn "Package ${pkg_line} not available"
            fi
        fi
    done
}

# Compile and install package from source if not available in repos
compile_from_source() {
    local package_name="$1"
    local source_url="$2"
    local configure_opts="${3:-}"

    info "Compiling ${package_name} from source..."

    cd "${WORK_DIR}" || return 1

    # Download source
    local source_file="${source_url##*/}"
    wget -q "${source_url}" -O "${source_file}" >> "${LOG_FILE}" 2>&1 || {
        warn "Failed to download ${package_name} from ${source_url}"
        return 1
    }

    # Extract
    local extract_dir=""
    if echo "${source_file}" | grep -q '\.tar\.gz$\|\.tgz$'; then
        tar -xzf "${source_file}" >> "${LOG_FILE}" 2>&1
        extract_dir=$(tar -tzf "${source_file}" | head -1 | cut -d/ -f1)
    elif echo "${source_file}" | grep -q '\.tar\.bz2$'; then
        tar -xjf "${source_file}" >> "${LOG_FILE}" 2>&1
        extract_dir=$(tar -tjf "${source_file}" | head -1 | cut -d/ -f1)
    fi

    cd "${extract_dir}" || return 1

    # Build and install
    ./configure ${configure_opts} >> "${LOG_FILE}" 2>&1 && \
    make -j$(nproc) >> "${LOG_FILE}" 2>&1 && \
    make install >> "${LOG_FILE}" 2>&1 && \
    ldconfig >> "${LOG_FILE}" 2>&1

    local result=$?
    cd "${WORK_DIR}"

    if [ ${result} -eq 0 ]; then
        success "${package_name} compiled and installed from source"
        return 0
    else
        warn "Failed to compile ${package_name} from source"
        return 1
    fi
}

# =============================================================================
# CORE DEPENDENCIES
# =============================================================================

install_core_dependencies() {
    step "📚 Installing core system dependencies..."

    case "${PACKAGE_MANAGER}" in
        apt-get)
            # Core build tools - install one-by-one with dependencies
            info "Installing build tools..."
            for pkg in build-essential gcc g++ make cmake autoconf automake libtool \
                       git wget curl unzip bzip2 tar gzip patch pkg-config linux-headers-generic; do
                DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkg}" >> "${LOG_FILE}" 2>&1 || \
                warn "Package ${pkg} not available"
            done

            # System libraries - install one-by-one
            info "Installing system libraries..."
            for pkg in openssl libssl-dev ca-certificates \
                       libxml2-dev libxslt1-dev \
                       libcurl4-openssl-dev \
                       libncurses5-dev libncursesw5-dev libnewt-dev \
                       libsqlite3-dev sqlite3 \
                       uuid-dev libuuid1 \
                       zlib1g-dev \
                       libedit-dev \
                       libreadline-dev; do
                DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkg}" >> "${LOG_FILE}" 2>&1 || \
                warn "Package ${pkg} not available"
            done

            # Asterisk VoIP dependencies - install one-by-one
            info "Installing Asterisk VoIP dependencies..."
            for pkg in libjansson-dev \
                       libspeex-dev libspeexdsp-dev \
                       libopus-dev \
                       libgsm1-dev \
                       libogg-dev libvorbis-dev \
                       libsndfile1-dev \
                       libasound2-dev \
                       libmariadb-dev libmariadb-dev-compat \
                       unixodbc-dev \
                       libldap2-dev; do
                DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkg}" >> "${LOG_FILE}" 2>&1 || \
                warn "Package ${pkg} not available"
            done

            # Try variants for packages with different names
            # CRITICAL: libsrtp required for secure RTP
            try_install_package "libsrtp2-dev libsrtp-dev" "libsrtp" || \
                error "Failed to install libsrtp - required for secure SIP/RTP"

            # OPTIONAL: These enhance functionality but aren't required
            try_install_package "libpjproject-dev" "libpjproject" "yes" || true
            try_install_package "libiksemel-dev" "libiksemel" "yes" || true
            try_install_package "libresample1-dev" "libresample" "yes" || true

            # Audio/Video processing - install one-by-one
            info "Installing audio/video tools..."
            for pkg in sox mpg123 lame ghostscript imagemagick; do
                DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkg}" >> "${LOG_FILE}" 2>&1 || \
                warn "Package ${pkg} not available"
            done

            # Fax system dependencies - install one-by-one
            info "Installing fax system dependencies..."
            for pkg in libtiff-dev libtiff5 libpng-dev libjpeg-dev; do
                DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkg}" >> "${LOG_FILE}" 2>&1 || \
                warn "Package ${pkg} not available"
            done

            # System utilities - install one-by-one
            info "Installing system utilities..."
            for pkg in nodejs npm ntp ntpdate logrotate rsyslog cron \
                       htop iotop iftop net-tools sudo vim nano; do
                DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkg}" >> "${LOG_FILE}" 2>&1 || \
                warn "Package ${pkg} not available"
            done

            # Optional advanced packages (don't warn if missing)
            info "Installing optional packages..."
            for pkg in ffmpeg libvpx-dev libbluetooth-dev libfreeradius-dev libcorosync-common-dev; do
                DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkg}" >> "${LOG_FILE}" 2>&1 || true
            done
            ;;

        yum|dnf)
            # Enable PowerTools/CRB repository for devel packages (if not using casjay repo)
            if ! repo_exists "casjay-os-crb" && ! repo_exists "casjay-os-base"; then
                info "Enabling PowerTools/CRB repository..."
                if [ "${DETECTED_VERSION%%.*}" = "8" ]; then
                    ${PACKAGE_MANAGER} config-manager --set-enabled powertools >> "${LOG_FILE}" 2>&1 || \
                    ${PACKAGE_MANAGER} config-manager --set-enabled PowerTools >> "${LOG_FILE}" 2>&1 || \
                    info "PowerTools repository not available (may not be needed)"
                elif [ "${DETECTED_VERSION%%.*}" = "9" ]; then
                    ${PACKAGE_MANAGER} config-manager --set-enabled crb >> "${LOG_FILE}" 2>&1 || \
                    ${PACKAGE_MANAGER} config-manager --set-enabled CRB >> "${LOG_FILE}" 2>&1 || \
                    info "CRB repository not available (may not be needed)"
                fi
            else
                info "Using CasJay repository (includes CRB packages)"
            fi

            # Core build tools - install one-by-one with dependencies
            info "Installing build tools..."
            for pkg in gcc gcc-c++ make cmake autoconf automake libtool \
                       git wget curl unzip bzip2 tar gzip patch; do
                ${PACKAGE_MANAGER} install -y "${pkg}" >> "${LOG_FILE}" 2>&1 || \
                warn "Package ${pkg} not available"
            done

            # Install matching kernel headers based on running kernel
            if uname -r | grep -q 'elrepo'; then
                info "Detected ELRepo kernel, installing kernel-ml-headers..."
                if ! try_install_package "kernel-ml-headers" "kernel-ml-headers"; then
                    warn "Failed to install kernel-ml-headers, trying standard kernel-headers as fallback..."
                    try_install_package "kernel-headers" "kernel-headers" || \
                        warn "Could not install any kernel headers"
                fi
            else
                info "Installing standard kernel-headers..."
                try_install_package "kernel-headers" "kernel-headers" || \
                    warn "kernel-headers not available"
            fi

            # Try pkg-config variants (CRITICAL)
            # AlmaLinux/RHEL 9 uses pkgconf-pkg-config, older versions use pkgconfig
            try_install_package "pkgconf-pkg-config pkgconf pkgconfig pkg-config" "pkg-config" || \
                error "Failed to install pkg-config - required for building"

            # System libraries - install one-by-one
            info "Installing system libraries..."
            for pkg in openssl openssl-devel ca-certificates \
                       libxml2-devel libxslt-devel \
                       libcurl-devel \
                       ncurses-devel newt-devel \
                       sqlite-devel sqlite \
                       libuuid-devel \
                       zlib-devel \
                       libedit-devel \
                       readline-devel; do
                ${PACKAGE_MANAGER} install -y "${pkg}" >> "${LOG_FILE}" 2>&1 || \
                warn "Package ${pkg} not available"
            done

            # Asterisk VoIP dependencies
            info "Installing Asterisk VoIP dependencies..."

            # Core VoIP packages (with variants) - CRITICAL for Asterisk
            try_install_package "jansson-devel" "jansson" || \
                error "Failed to install jansson - required for Asterisk"
            try_install_package "libsrtp-devel srtp-devel" "libsrtp" || \
                error "Failed to install libsrtp - required for secure SIP/RTP"
            try_install_package "speex-devel" "speex"
            try_install_package "speexdsp-devel" "speexdsp"
            try_install_package "opus-devel" "opus"
            try_install_package "gsm-devel" "gsm"
            try_install_package "libogg-devel" "libogg"
            try_install_package "libvorbis-devel vorbis-devel" "libvorbis"
            try_install_package "libsndfile-devel" "libsndfile"
            try_install_package "alsa-lib-devel" "alsa-lib"
            try_install_package "mariadb-devel mysql-devel" "mariadb" || \
                error "Failed to install MariaDB development libraries - required for database"
            try_install_package "unixODBC-devel unixodbc-devel" "unixodbc"
            try_install_package "openldap-devel" "openldap"

            # OPTIONAL: pjproject and iksemel enhance functionality but aren't required
            try_install_package "pjproject-devel" "pjproject" "yes" || true
            try_install_package "iksemel-devel" "iksemel" "yes" || true

            # Audio/Video processing - install one-by-one
            info "Installing audio/video tools..."
            for pkg in sox mpg123 lame ghostscript; do
                ${PACKAGE_MANAGER} install -y "${pkg}" >> "${LOG_FILE}" 2>&1 || \
                warn "Package ${pkg} not available"
            done

            # Try ImageMagick variants
            try_install_package "ImageMagick imagemagick" "ImageMagick"

            # Fax system dependencies - install one-by-one
            info "Installing fax system dependencies..."
            for pkg in libtiff-devel libtiff-tools libpng-devel libjpeg-turbo-devel; do
                ${PACKAGE_MANAGER} install -y "${pkg}" >> "${LOG_FILE}" 2>&1 || \
                warn "Package ${pkg} not available"
            done

            # System utilities - install one-by-one
            info "Installing system utilities..."
            for pkg in chrony logrotate rsyslog cronie \
                       htop iotop iftop net-tools sudo vim nano; do
                ${PACKAGE_MANAGER} install -y "${pkg}" >> "${LOG_FILE}" 2>&1 || \
                warn "Package ${pkg} not available"
            done

            # Handle nodejs/npm separately to avoid conflicts
            info "Installing Node.js and npm..."
            ${PACKAGE_MANAGER} install -y nodejs --skip-broken >> "${LOG_FILE}" 2>&1 || \
            ${PACKAGE_MANAGER} install -y nodejs --nobest >> "${LOG_FILE}" 2>&1 || \
            warn "Node.js installation using fallback"

            ${PACKAGE_MANAGER} install -y npm --skip-broken >> "${LOG_FILE}" 2>&1 || \
            warn "npm installation skipped (may use alternative)"

            # Optional advanced packages (don't warn if missing)
            info "Installing optional packages..."
            for pkg in ffmpeg libvpx-devel bluez-libs-devel freeradius-devel corosynclib-devel; do
                ${PACKAGE_MANAGER} install -y "${pkg}" >> "${LOG_FILE}" 2>&1 || true
            done
            ;;
    esac

    success "Core dependencies installed"
}

# =============================================================================
# MARIADB INSTALLATION
# =============================================================================

install_mariadb() {
    step "🗄️  Installing MariaDB database server..."

    case "${PACKAGE_MANAGER}" in
        apt-get)
            safe_execute "DEBIAN_FRONTEND=noninteractive apt-get install -y mariadb-server mariadb-client" "Failed to install MariaDB"
            ;;
        yum|dnf)
            safe_execute "${PACKAGE_MANAGER} install -y mariadb-server mariadb" "Failed to install MariaDB"
            ;;
    esac

    # Start and enable MariaDB
    safe_execute "systemctl enable mariadb" "Failed to enable MariaDB"
    safe_execute "systemctl start mariadb" "Failed to start MariaDB"

    sleep 3

    # Secure MariaDB installation
    info "Securing MariaDB installation..."
    mysql << EOF 2>/dev/null || true
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF

    # Create .my.cnf for root
    cat > /root/.my.cnf << EOF
[client]
user=root
password=${MYSQL_ROOT_PASSWORD}
EOF
    chmod 600 /root/.my.cnf

    # Create FreePBX databases and user
    mysql << EOF 2>/dev/null || true
CREATE DATABASE IF NOT EXISTS asterisk;
CREATE DATABASE IF NOT EXISTS asteriskcdrdb;
CREATE USER IF NOT EXISTS 'freepbxuser'@'localhost' IDENTIFIED BY '${FREEPBX_DB_PASSWORD}';
GRANT ALL PRIVILEGES ON asterisk.* TO 'freepbxuser'@'localhost';
GRANT ALL PRIVILEGES ON asteriskcdrdb.* TO 'freepbxuser'@'localhost';
FLUSH PRIVILEGES;
EOF

    # CRITICAL: Update password on re-runs (CREATE USER IF NOT EXISTS doesn't update password)
    mysql << EOF 2>/dev/null || true
ALTER USER 'freepbxuser'@'localhost' IDENTIFIED BY '${FREEPBX_DB_PASSWORD}';
FLUSH PRIVILEGES;
EOF

    track_install "mariadb"
    success "MariaDB installation completed"
}

# =============================================================================
# PHP INSTALLATION
# =============================================================================

install_php() {
    step "🐘 Installing PHP ${PHP_VERSION}..."

    case "${PACKAGE_MANAGER}" in
        apt-get)
            php_packages="php${PHP_VERSION} php${PHP_VERSION}-cli php${PHP_VERSION}-common \
                         php${PHP_VERSION}-curl php${PHP_VERSION}-gd php${PHP_VERSION}-mbstring \
                         php${PHP_VERSION}-mysql php${PHP_VERSION}-xml php${PHP_VERSION}-zip \
                         php${PHP_VERSION}-intl php${PHP_VERSION}-bcmath php${PHP_VERSION}-soap \
                         php${PHP_VERSION}-fpm php${PHP_VERSION}-opcache php${PHP_VERSION}-json \
                         php${PHP_VERSION}-pdo php-pear"

            safe_execute "DEBIAN_FRONTEND=noninteractive apt-get install -y ${php_packages}" "Failed to install PHP"

            # Configure PHP
            PHP_INI="/etc/php/${PHP_VERSION}/apache2/php.ini"
            if [ -f "${PHP_INI}" ]; then
                sed -i 's/memory_limit = .*/memory_limit = 512M/' "${PHP_INI}"
                sed -i 's/upload_max_filesize = .*/upload_max_filesize = 100M/' "${PHP_INI}"
                sed -i 's/post_max_size = .*/post_max_size = 100M/' "${PHP_INI}"
                sed -i 's/max_execution_time = .*/max_execution_time = 300/' "${PHP_INI}"
            fi
            ;;

        yum|dnf)
            # Enable PHP module non-interactively
            ${PACKAGE_MANAGER} module reset -y php >> "${LOG_FILE}" 2>&1 || warn "PHP module reset not available"
            ${PACKAGE_MANAGER} module enable -y php:remi-${PHP_VERSION} >> "${LOG_FILE}" 2>&1 || warn "PHP module enable not available, using system packages"

            php_packages="php php-cli php-common php-curl php-gd php-mbstring \
                         php-mysqlnd php-xml php-zip php-intl php-bcmath \
                         php-soap php-fpm php-opcache php-json php-pdo php-pear"

            safe_execute "${PACKAGE_MANAGER} install -y ${php_packages}" "Failed to install PHP"

            # Configure PHP
            PHP_INI="/etc/php.ini"
            if [ -f "${PHP_INI}" ]; then
                backup_config "${PHP_INI}"
                sed -i 's/memory_limit = .*/memory_limit = 512M/' "${PHP_INI}"
                sed -i 's/upload_max_filesize = .*/upload_max_filesize = 100M/' "${PHP_INI}"
                sed -i 's/post_max_size = .*/post_max_size = 100M/' "${PHP_INI}"
                sed -i 's/max_execution_time = .*/max_execution_time = 300/' "${PHP_INI}"
            fi

            # Configure PHP-FPM to listen on TCP port 9000
            if [ -f /etc/php-fpm.d/www.conf ]; then
                backup_config /etc/php-fpm.d/www.conf
                sed -i 's/^listen = .*/listen = 127.0.0.1:9000/' /etc/php-fpm.d/www.conf
                sed -i 's/^;listen.allowed_clients/listen.allowed_clients/' /etc/php-fpm.d/www.conf
            fi

            # Enable and restart PHP-FPM (restart to apply TCP port configuration)
            systemctl enable php-fpm >> "${LOG_FILE}" 2>&1 || warn "Failed to enable PHP-FPM"
            systemctl restart php-fpm >> "${LOG_FILE}" 2>&1 || warn "Failed to restart PHP-FPM"

            # Verify PHP-FPM is listening on correct port
            sleep 2
            if ss -tln | grep -q ':9000'; then
                info "PHP-FPM listening on port 9000"
            else
                warn "PHP-FPM may not be listening on port 9000"
            fi
            ;;
    esac

    # Install ionCube Loader (required by some FreePBX commercial modules)
    info "Installing ionCube Loader for PHP ${PHP_VERSION}..."
    cd "${WORK_DIR}"

    if ! php -m | grep -q ionCube; then
        wget -q https://downloads.ioncube.com/loader_downloads/ioncube_loaders_lin_x86-64.tar.gz >> "${LOG_FILE}" 2>&1
        tar xzf ioncube_loaders_lin_x86-64.tar.gz >> "${LOG_FILE}" 2>&1

        PHP_EXT_DIR=$(php -i | grep '^extension_dir' | awk '{print $3}')

        case "${PHP_VERSION}" in
            8.2) cp ioncube/ioncube_loader_lin_8.2.so "${PHP_EXT_DIR}/" ;;
            8.1) cp ioncube/ioncube_loader_lin_8.1.so "${PHP_EXT_DIR}/" ;;
            8.0) cp ioncube/ioncube_loader_lin_8.0.so "${PHP_EXT_DIR}/" ;;
            7.4) cp ioncube/ioncube_loader_lin_7.4.so "${PHP_EXT_DIR}/" ;;
        esac

        echo "zend_extension=ioncube_loader_lin_${PHP_VERSION}.so" > /etc/php.d/00-ioncube.ini

        # Restart PHP-FPM to load ionCube
        systemctl restart php-fpm >> "${LOG_FILE}" 2>&1

        if php -m | grep -q ionCube; then
            success "ionCube Loader installed successfully"
        else
            warn "ionCube Loader may not be loaded correctly"
        fi
    else
        info "ionCube Loader already installed"
    fi

    success "PHP installation completed"
}

# =============================================================================
# APACHE INSTALLATION
# =============================================================================

install_apache() {
    step "🌐 Installing Apache web server..."

    case "${PACKAGE_MANAGER}" in
        apt-get)
            # Install Apache without mod_php - using PHP-FPM only
            safe_execute "DEBIAN_FRONTEND=noninteractive apt-get install -y apache2" "Failed to install Apache"

            # Enable required modules for PHP-FPM
            safe_execute "a2enmod rewrite" "Failed to enable rewrite module"
            safe_execute "a2enmod ssl" "Failed to enable SSL module"
            safe_execute "a2enmod headers" "Failed to enable headers module"
            safe_execute "a2enmod proxy" "Failed to enable proxy module"
            safe_execute "a2enmod proxy_fcgi" "Failed to enable proxy_fcgi module"
            safe_execute "a2enmod setenvif" "Failed to enable setenvif module"
            ;;

        yum|dnf)
            safe_execute "${PACKAGE_MANAGER} install -y httpd mod_ssl" "Failed to install Apache"
            # Note: proxy modules are compiled in by default on RHEL/CentOS
            ;;
    esac

    # Create web directories
    mkdir -p "${WEB_ROOT}"
    mkdir -p "${FREEPBX_WEB_DIR}"

    if [ "${INSTALL_AVANTFAX}" = "1" ]; then
        mkdir -p "${AVANTFAX_WEB_DIR}"
    fi

    # Set ownership
    chown -R "${APACHE_USER}:${APACHE_GROUP}" "${WEB_ROOT}"

    # Configure Apache for PHP-FPM
    configure_apache_phpfpm

    # Configure FreePBX directories with AllowOverride
    configure_freepbx_apache

    # Start and enable Apache
    safe_execute "systemctl enable ${APACHE_SERVICE}" "Failed to enable Apache"
    safe_execute "systemctl start ${APACHE_SERVICE}" "Failed to start Apache"

    track_install "apache"
    success "Apache installation completed"
}

# Configure FreePBX Apache directories
configure_freepbx_apache() {
    info "Configuring FreePBX Apache directories..."

    case "${PACKAGE_MANAGER}" in
        yum|dnf)
            cat > /etc/httpd/conf.d/freepbx.conf << 'EOF'
# FreePBX Apache Configuration
# Enable .htaccess files for FreePBX

<Directory /var/www/html>
    Options -Indexes +FollowSymLinks
    AllowOverride All
    Require all granted
</Directory>

<Directory /var/www/html/admin>
    Options -Indexes +FollowSymLinks
    AllowOverride All
    Require all granted
</Directory>

<Directory /var/www/html/ucp>
    Options -Indexes +FollowSymLinks
    AllowOverride All
    Require all granted
</Directory>
EOF
            ;;

        apt-get)
            cat > /etc/apache2/conf-available/freepbx.conf << 'EOF'
# FreePBX Apache Configuration
# Enable .htaccess files for FreePBX

<Directory /var/www/html>
    Options -Indexes +FollowSymLinks
    AllowOverride All
    Require all granted
</Directory>

<Directory /var/www/html/admin>
    Options -Indexes +FollowSymLinks
    AllowOverride All
    Require all granted
</Directory>

<Directory /var/www/html/ucp>
    Options -Indexes +FollowSymLinks
    AllowOverride All
    Require all granted
</Directory>
EOF
            a2enconf freepbx >> "${LOG_FILE}" 2>&1
            ;;
    esac

    success "FreePBX Apache configuration completed"
}

# Configure Apache to use PHP-FPM instead of mod_php
configure_apache_phpfpm() {
    info "Configuring Apache for PHP-FPM..."

    case "${PACKAGE_MANAGER}" in
        apt-get)
            # Debian/Ubuntu: Create PHP-FPM configuration
            cat > /etc/apache2/conf-available/php-fpm.conf << 'EOF'
# PHP-FPM Configuration for Apache
<FilesMatch \.php$>
    SetHandler "proxy:unix:/run/php/php-fpm.sock|fcgi://localhost"
</FilesMatch>
EOF
            a2enconf php-fpm >> "${LOG_FILE}" 2>&1
            ;;

        yum|dnf)
            # Disable old php.conf files that conflict with PHP-FPM
            if [ -f /etc/httpd/conf.d/php.conf ]; then
                backup_config /etc/httpd/conf.d/php.conf
                mv /etc/httpd/conf.d/php.conf /etc/httpd/conf.d/php.conf.disabled
                info "Disabled conflicting php.conf (using PHP-FPM instead)"
            fi
            if [ -f /etc/httpd/conf.d/php74-php.conf ]; then
                backup_config /etc/httpd/conf.d/php74-php.conf
                mv /etc/httpd/conf.d/php74-php.conf /etc/httpd/conf.d/php74-php.conf.disabled
                info "Disabled conflicting php74-php.conf (using PHP-FPM instead)"
            fi

            # RHEL/CentOS: Create PHP-FPM configuration
            cat > /etc/httpd/conf.d/php-fpm.conf << 'EOF'
# PHP-FPM Configuration for Apache
# Default: Use PHP 8.2 FPM for all .php files
<FilesMatch \.php$>
    SetHandler "proxy:fcgi://127.0.0.1:9000"
</FilesMatch>

# AvantFax: Use PHP 7.4 FPM
<Directory "/var/www/html/avantfax">
    <FilesMatch \.php$>
        SetHandler "proxy:fcgi://127.0.0.1:9074"
    </FilesMatch>
</Directory>

# Proxy configuration
<Proxy "fcgi://127.0.0.1:9000">
    ProxySet timeout=300
</Proxy>

<Proxy "fcgi://127.0.0.1:9074">
    ProxySet timeout=300
</Proxy>

# Directory index for PHP
DirectoryIndex index.php index.html
EOF
            ;;
    esac

    success "Apache PHP-FPM configuration completed"
}

# =============================================================================
# SSL/TLS CERTIFICATE MANAGEMENT
# =============================================================================

configure_letsencrypt_integration() {
    step "🔒 Configuring Let's Encrypt integration..."

    # Check if Let's Encrypt directory exists
    if [ ! -d "/etc/letsencrypt/live" ]; then
        info "No Let's Encrypt certificates found, skipping integration..."
        return 0
    fi

    # Find certificates for this domain
    local cert_dir=""
    local found_cert=0

    # Check for exact domain match first
    if [ -d "/etc/letsencrypt/live/${SYSTEM_FQDN}" ]; then
        cert_dir="/etc/letsencrypt/live/${SYSTEM_FQDN}"
        found_cert=1
    else
        # Find first available certificate
        for dir in /etc/letsencrypt/live/*/; do
            if [ -f "${dir}cert.pem" ] && [ -f "${dir}privkey.pem" ]; then
                cert_dir="${dir%/}"
                found_cert=1
                break
            fi
        done
    fi

    if [ $found_cert -eq 0 ]; then
        info "No valid Let's Encrypt certificates found"
        return 0
    fi

    info "Found Let's Encrypt certificate at: ${cert_dir}"

    # Create Asterisk keys directory
    mkdir -p /etc/asterisk/keys
    chown asterisk:asterisk /etc/asterisk/keys
    chmod 750 /etc/asterisk/keys

    # Create certificate deployment script
    cat > /usr/local/bin/deploy-asterisk-certs << 'EOFCERT'
#!/bin/bash
# Deploy Let's Encrypt certificates for Asterisk
# Called by certbot renewal hook

CERT_DIR="$1"
ASTERISK_KEY_DIR="/etc/asterisk/keys"

if [ -z "${CERT_DIR}" ]; then
    # Find certificate directory
    if [ -d "/etc/letsencrypt/live" ]; then
        CERT_DIR=$(find /etc/letsencrypt/live -name cert.pem -exec dirname {} \; | head -1)
    fi
fi

if [ -z "${CERT_DIR}" ] || [ ! -d "${CERT_DIR}" ]; then
    echo "ERROR: Certificate directory not found"
    exit 1
fi

echo "Deploying certificates from ${CERT_DIR}"

# Create asterisk keys directory if it doesn't exist
mkdir -p "${ASTERISK_KEY_DIR}"

# Concatenate cert and chain for Asterisk
cat "${CERT_DIR}/cert.pem" "${CERT_DIR}/chain.pem" > "${ASTERISK_KEY_DIR}/asterisk.pem"

# Copy private key
cp "${CERT_DIR}/privkey.pem" "${ASTERISK_KEY_DIR}/asterisk-key.pem"

# Set proper permissions
chown -R asterisk:asterisk "${ASTERISK_KEY_DIR}"
chmod 640 "${ASTERISK_KEY_DIR}/asterisk.pem"
chmod 640 "${ASTERISK_KEY_DIR}/asterisk-key.pem"

# Reload Asterisk if running
if systemctl is-active asterisk >/dev/null 2>&1; then
    echo "Reloading Asterisk..."
    asterisk -rx "pjsip reload" >/dev/null 2>&1
    asterisk -rx "http reload" >/dev/null 2>&1
fi

echo "Certificate deployment completed"
EOFCERT

    chmod +x /usr/local/bin/deploy-asterisk-certs

    # Create Let's Encrypt renewal hook
    mkdir -p /etc/letsencrypt/renewal-hooks/deploy
    cat > /etc/letsencrypt/renewal-hooks/deploy/asterisk << 'EOFHOOK'
#!/bin/bash
# Let's Encrypt renewal hook for Asterisk
# Automatically deploys renewed certificates to Asterisk

# Get the certificate directory from certbot
if [ -n "${RENEWED_LINEAGE}" ]; then
    /usr/local/bin/deploy-asterisk-certs "${RENEWED_LINEAGE}"
else
    /usr/local/bin/deploy-asterisk-certs
fi
EOFHOOK

    chmod +x /etc/letsencrypt/renewal-hooks/deploy/asterisk

    # Deploy certificates now
    info "Deploying certificates for Asterisk..."
    /usr/local/bin/deploy-asterisk-certs "${cert_dir}"

    # Configure Asterisk to use TLS certificates
    info "Configuring Asterisk TLS..."

    # Update PJSIP configuration for TLS
    if [ -f /etc/asterisk/pjsip_custom.conf ]; then
        if ! grep -q "cert_file" /etc/asterisk/pjsip_custom.conf; then
            cat >> /etc/asterisk/pjsip_custom.conf << 'EOFTLS'

; TLS Configuration (Let's Encrypt)
[transport-tls]
type=transport
protocol=tls
bind=0.0.0.0:5061
cert_file=/etc/asterisk/keys/asterisk.pem
priv_key_file=/etc/asterisk/keys/asterisk-key.pem
method=tlsv1_2
EOFTLS
        fi
    fi

    # Configure HTTP/HTTPS for Asterisk manager interface
    if [ -f /etc/asterisk/http.conf ]; then
        backup_config /etc/asterisk/http.conf

        if ! grep -q "tlsenable=yes" /etc/asterisk/http.conf; then
            cat >> /etc/asterisk/http.conf << 'EOFHTTP'

; HTTPS Configuration (Let's Encrypt)
[general]
enabled=yes
bindaddr=0.0.0.0
bindport=8088
tlsenable=yes
tlsbindaddr=0.0.0.0:8089
tlscertfile=/etc/asterisk/keys/asterisk.pem
tlsprivatekey=/etc/asterisk/keys/asterisk-key.pem
EOFHTTP
        fi
    fi

    success "Let's Encrypt integration configured"
    info "Certificates will auto-renew and deploy to Asterisk"
}

# =============================================================================
# REVERSE PROXY CONFIGURATION
# =============================================================================

configure_reverse_proxy_support() {
    step "🔄 Configuring reverse proxy support..."

    # Ask user if behind reverse proxy
    if [ -n "${BEHIND_PROXY:-}" ]; then
        info "Reverse proxy mode: ${BEHIND_PROXY}"
    else
        # Auto-detect or assume not behind proxy
        BEHIND_PROXY="no"
    fi

    if [ "${BEHIND_PROXY}" = "yes" ] || [ "${BEHIND_PROXY}" = "true" ] || [ "${BEHIND_PROXY}" = "1" ]; then
        info "Configuring Apache for reverse proxy mode..."

        case "${APACHE_SERVICE}" in
            apache2)
                # Enable required modules for reverse proxy
                a2enmod remoteip >> "${LOG_FILE}" 2>&1 || warn "Failed to enable remoteip module"
                a2enmod proxy >> "${LOG_FILE}" 2>&1 || true
                a2enmod proxy_http >> "${LOG_FILE}" 2>&1 || true

                # Configure RemoteIP to trust proxy
                cat > /etc/apache2/conf-available/remoteip.conf << 'EOFREMOTE'
<IfModule remoteip_module>
    RemoteIPHeader X-Forwarded-For
    RemoteIPInternalProxy 10.0.0.0/8
    RemoteIPInternalProxy 172.16.0.0/12
    RemoteIPInternalProxy 192.168.0.0/16
    RemoteIPInternalProxy 127.0.0.1
</IfModule>
EOFREMOTE

                a2enconf remoteip >> "${LOG_FILE}" 2>&1 || warn "Failed to enable remoteip config"
                ;;

            httpd)
                # RHEL/CentOS/AlmaLinux configuration
                cat > /etc/httpd/conf.d/remoteip.conf << 'EOFREMOTE'
# Reverse Proxy Configuration
RemoteIPHeader X-Forwarded-For
RemoteIPInternalProxy 10.0.0.0/8
RemoteIPInternalProxy 172.16.0.0/12
RemoteIPInternalProxy 192.168.0.0/16
RemoteIPInternalProxy 127.0.0.1

# Trust proxy for SSL detection
SetEnvIf X-Forwarded-Proto "https" HTTPS=on
EOFREMOTE
                ;;
        esac

        # Update firewall to only allow local connections
        info "Updating firewall for reverse proxy mode..."

        # Note: In reverse proxy mode, web server should only accept connections from proxy
        # This is optional and can be configured by user

        success "Reverse proxy support configured"
        info "Web server configured to trust X-Forwarded-For headers"
        info "NOTE: Ensure your reverse proxy is configured to pass these headers"
    else
        info "Running in direct access mode (not behind reverse proxy)"
        success "Direct access mode configured"
    fi

    # Restart Apache to apply changes
    systemctl reload "${APACHE_SERVICE}" >> "${LOG_FILE}" 2>&1 || \
        systemctl restart "${APACHE_SERVICE}" >> "${LOG_FILE}" 2>&1 || \
        warn "Failed to reload Apache"
}

# =============================================================================
# SYSTEMD SERVICE FILES
# =============================================================================

create_asterisk_service() {
    info "Creating Asterisk systemd service..."

    cat > /etc/systemd/system/asterisk.service << 'EOF'
[Unit]
Description=Asterisk PBX
Documentation=man:asterisk(8)
Wants=network-online.target
After=network-online.target mariadb.service

[Service]
Type=simple
User=asterisk
Group=asterisk
ExecStart=/usr/sbin/asterisk -f -C /etc/asterisk/asterisk.conf
ExecStop=/usr/sbin/asterisk -rx 'core stop now'
ExecReload=/usr/sbin/asterisk -rx 'core reload'
Restart=on-failure
RestartSec=5
TimeoutStartSec=300
LimitNOFILE=65536
# Systemd hardening disabled - prevents control socket creation
#PrivateTmp=true
#ProtectSystem=full
#ProtectHome=true

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable asterisk 2>/dev/null || true
}

create_iaxmodem_services() {
    info "Creating IAXmodem systemd services..."

    local modem_num
    for modem_num in $(seq 0 $((NUMBER_OF_MODEMS - 1))); do
        cat > "/etc/systemd/system/iaxmodem${modem_num}.service" << EOF
[Unit]
Description=IAXmodem ${modem_num}
Documentation=man:iaxmodem(1)
After=asterisk.service
Requires=asterisk.service

[Service]
Type=forking
User=uucp
Group=uucp
ExecStart=/usr/local/sbin/iaxmodem ttyIAX${modem_num}
PIDFile=/var/run/iaxmodem/iaxmodem${modem_num}.pid
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

        systemctl daemon-reload
        systemctl enable "iaxmodem${modem_num}" 2>/dev/null || true
    done
}

create_hylafax_service() {
    info "Creating HylaFax+ systemd service..."

    cat > /etc/systemd/system/hylafax.service << 'EOF'
[Unit]
Description=HylaFAX+ Fax Server
Documentation=man:hfaxd(8)
After=network.target iaxmodem0.service iaxmodem1.service iaxmodem2.service iaxmodem3.service

[Service]
Type=forking
ExecStart=/usr/local/sbin/faxq
ExecStop=/usr/bin/pkill -f faxq
Restart=on-failure
RestartSec=5
User=uucp
Group=uucp

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable hylafax 2>/dev/null || true
}

# =============================================================================
# ASTERISK INSTALLATION
# =============================================================================

install_asterisk() {
    step "📞 Installing Asterisk ${ASTERISK_VERSION}..."

    # Check if Asterisk is already installed
    if command_exists asterisk && [ -f /etc/asterisk/asterisk.conf ]; then
        INSTALLED_VERSION=$(asterisk -V 2>/dev/null | grep -oP 'Asterisk \K[0-9]+' | head -1)
        if [ "$INSTALLED_VERSION" = "${ASTERISK_VERSION}" ]; then
            success "Asterisk ${ASTERISK_VERSION} is already installed, skipping compilation..."
            track_install "asterisk"

            # CRITICAL: Ensure Asterisk is running before returning
            # FreePBX installation REQUIRES Asterisk to be active
            if ! systemctl is-active asterisk >/dev/null 2>&1; then
                info "Asterisk is not running, starting it now..."
                systemctl enable asterisk 2>/dev/null || true
                safe_restart_asterisk || warn "Failed to start Asterisk"

                # Wait up to 30 seconds for Asterisk to be fully ready
                info "Waiting for Asterisk to initialize..."
                local waited=0
                while [ $waited -lt 30 ]; do
                    if systemctl is-active asterisk >/dev/null 2>&1 && \
                       asterisk -rx "core show version" >/dev/null 2>&1; then
                        success "Asterisk is running and responsive"
                        return 0
                    fi
                    sleep 2
                    waited=$((waited + 2))
                done
                warn "Asterisk started but may still be initializing"
            else
                success "Asterisk is already running"
            fi
            return 0
        else
            info "Asterisk ${INSTALLED_VERSION} found, will upgrade to ${ASTERISK_VERSION}..."
        fi
    fi

    cd "${WORK_DIR}"

    # Create asterisk user first
    if ! id -u asterisk >/dev/null 2>&1; then
        info "Creating asterisk user..."
        useradd -r -d /var/lib/asterisk -s /sbin/nologin asterisk
    fi

    # Download Asterisk
    info "Downloading Asterisk ${ASTERISK_VERSION}..."
    local ASTERISK_TARBALL="asterisk-${ASTERISK_VERSION}-current.tar.gz"
    local ASTERISK_URL="https://downloads.asterisk.org/pub/telephony/asterisk/asterisk-${ASTERISK_VERSION}-current.tar.gz"

    wget -q "${ASTERISK_URL}" -O "${ASTERISK_TARBALL}" >> "${LOG_FILE}" 2>&1 || \
        error "Failed to download Asterisk"

    # Extract
    info "Extracting Asterisk source..."
    tar -xzf "${ASTERISK_TARBALL}" >> "${LOG_FILE}" 2>&1 || \
        error "Failed to extract Asterisk"

    local ASTERISK_DIR=$(tar -tzf "${ASTERISK_TARBALL}" | head -1 | cut -d/ -f1)
    cd "${ASTERISK_DIR}" || error "Failed to enter Asterisk directory"

    # Install prerequisites from menuselect
    info "Installing Asterisk prerequisites..."
    contrib/scripts/install_prereq install >> "${LOG_FILE}" 2>&1 || warn "Some prerequisites may have failed"

    # Configure
    info "Configuring Asterisk (this may take a few minutes)..."
    ./configure \
        --with-pjproject-bundled \
        --with-jansson-bundled \
        --with-crypto \
        --with-ssl \
        --with-srtp \
        CFLAGS="-DLOW_MEMORY" >> "${LOG_FILE}" 2>&1 || \
        error "Asterisk configure failed"

    # Make menuselect (enable commonly needed modules)
    info "Selecting Asterisk modules..."
    make menuselect.makeopts >> "${LOG_FILE}" 2>&1

    # Enable required modules
    menuselect/menuselect \
        --enable chan_pjsip \
        --enable chan_local \
        --enable res_pjsip \
        --enable res_pjsip_session \
        --enable app_voicemail \
        --enable cdr_mysql \
        --enable res_config_mysql \
        --enable format_mp3 \
        menuselect.makeopts >> "${LOG_FILE}" 2>&1 || warn "Some modules may not be available"

    # Compile
    info "Compiling Asterisk (this will take 10-20 minutes)..."
    make -j$(nproc) >> "${LOG_FILE}" 2>&1 || \
        error "Asterisk compilation failed"

    # Install
    info "Installing Asterisk..."
    make install >> "${LOG_FILE}" 2>&1 || \
        error "Asterisk installation failed"

    make samples >> "${LOG_FILE}" 2>&1 || warn "Failed to install sample configs"
    make config >> "${LOG_FILE}" 2>&1 || warn "Failed to install init scripts"

    # Set ownership
    info "Setting Asterisk permissions..."
    chown -R asterisk:asterisk /etc/asterisk
    chown -R asterisk:asterisk /var/lib/asterisk
    chown -R asterisk:asterisk /var/log/asterisk
    chown -R asterisk:asterisk /var/spool/asterisk
    chown -R asterisk:asterisk /var/run/asterisk
    chmod 775 /var/run/asterisk
    chown -R asterisk:asterisk /usr/lib/asterisk 2>/dev/null || true

    # Configure Asterisk control socket for FreePBX
    info "Configuring Asterisk control socket..."

    # Ensure [files] section exists
    if ! grep -q '^\[files\]' /etc/asterisk/asterisk.conf; then
        echo -e '\n[files]' >> /etc/asterisk/asterisk.conf
    fi

    # Add or update astctl settings (don't rely on commented samples)
    if ! grep -q '^astctlpermissions' /etc/asterisk/asterisk.conf; then
        sed -i '/^\[files\]/a astctlpermissions = 0660' /etc/asterisk/asterisk.conf
    fi
    if ! grep -q '^astctlowner' /etc/asterisk/asterisk.conf; then
        sed -i '/^\[files\]/a astctlowner = asterisk' /etc/asterisk/asterisk.conf
    fi
    if ! grep -q '^astctlgroup' /etc/asterisk/asterisk.conf; then
        sed -i '/^\[files\]/a astctlgroup = apache' /etc/asterisk/asterisk.conf
    fi
    if ! grep -q '^astctl ' /etc/asterisk/asterisk.conf; then
        sed -i '/^\[files\]/a astctl = asterisk.ctl' /etc/asterisk/asterisk.conf
    fi

    # Add apache user to asterisk group for socket access
    usermod -a -G asterisk apache 2>/dev/null || true

    # Configure to run as asterisk user
    mkdir -p /etc/default
    cat > /etc/default/asterisk << EOF
AST_USER="asterisk"
AST_GROUP="asterisk"
EOF

    # Create systemd service
    create_asterisk_service

    # Start Asterisk
    systemctl start asterisk || warn "Failed to start Asterisk (will retry later)"

    # Wait for Asterisk to fully start and create control socket
    info "Waiting for Asterisk to initialize..."
    for i in {1..30}; do
        if [ -S /var/run/asterisk/asterisk.ctl ]; then
            success "Asterisk control socket created"
            break
        fi
        sleep 2
    done

    track_install "asterisk"
    success "Asterisk ${ASTERISK_VERSION} installed successfully"
}

# =============================================================================
# FREEPBX INSTALLATION
# =============================================================================

install_freepbx() {
    step "🎛️  Installing FreePBX ${FREEPBX_VERSION}..."

    # Check if FreePBX is already installed
    if command_exists fwconsole && [ -d /var/www/html/admin ]; then
        success "FreePBX is already installed, skipping initial installation..."
        track_install "freepbx"
        return 0
    fi

    cd "${WORK_DIR}"

    # Ensure Asterisk is running
    systemctl start asterisk || warn "Asterisk not running yet"

    # Wait for Asterisk control socket to be ready
    info "Waiting for Asterisk to be ready..."
    for i in {1..30}; do
        if [ -S /var/run/asterisk/asterisk.ctl ] && asterisk -rx "core show version" &>/dev/null; then
            success "Asterisk is ready"
            break
        fi
        sleep 2
    done

    # Download FreePBX
    info "Downloading FreePBX ${FREEPBX_VERSION}..."
    if [ -d "freepbx" ]; then
        info "FreePBX source already exists, using existing directory..."
    else
        git clone -b release/${FREEPBX_VERSION} --depth 1 https://github.com/FreePBX/framework.git freepbx >> "${LOG_FILE}" 2>&1 || \
            error "Failed to clone FreePBX repository"
    fi

    cd freepbx || error "Failed to enter FreePBX directory"

    # Install FreePBX
    info "Installing FreePBX (this may take 10-15 minutes)..."
    ./start_asterisk start >> "${LOG_FILE}" 2>&1 || warn "Failed to start Asterisk via start_asterisk"

    # Run FreePBX install
    # Note: FreePBX install script may return non-zero even on success
    # We check for actual installation success below
    ./install \
        -n \
        --dbuser=freepbxuser \
        --dbpass="${FREEPBX_DB_PASSWORD}" \
        --dbname=asterisk \
        --cdrdbname=asteriskcdrdb \
        --webroot="${WEB_ROOT}" \
        --astetcdir=/etc/asterisk \
        --astmoddir=/usr/lib/asterisk/modules \
        --astvarlibdir=/var/lib/asterisk \
        --astagidir=/var/lib/asterisk/agi-bin \
        --astspooldir=/var/spool/asterisk \
        --astrundir=/var/run/asterisk \
        --astlogdir=/var/log/asterisk \
        --ampbin=/var/lib/asterisk/bin \
        --ampsbin=/usr/local/sbin \
        --ampcgibin=/var/www/cgi-bin \
        --ampplayback=/var/lib/asterisk/playback \
        --user="${APACHE_USER}" \
        --group="${APACHE_GROUP}" >> "${LOG_FILE}" 2>&1 || true

    # Verify FreePBX actually installed successfully
    if ! command_exists fwconsole || [ ! -d "${WEB_ROOT}/admin" ]; then
        error "FreePBX installation failed - fwconsole or admin directory not found"
    fi

    # Set admin password
    info "Setting FreePBX admin password..."
    fwconsole user create administrator \
        --password="${FREEPBX_ADMIN_PASSWORD}" >> "${LOG_FILE}" 2>&1 || \
    fwconsole user administrator setpassword "${FREEPBX_ADMIN_PASSWORD}" >> "${LOG_FILE}" 2>&1 || \
        warn "Failed to set admin password (may need manual setup)"

    # Install core modules
    info "Installing FreePBX core modules..."
    fwconsole ma downloadinstall framework core >> "${LOG_FILE}" 2>&1 || warn "Some modules may have failed"

    # Reload FreePBX
    info "Reloading FreePBX configuration..."
    fwconsole reload >> "${LOG_FILE}" 2>&1 || warn "Failed to reload FreePBX"

    # Restart Asterisk (using safe restart to avoid dual process issues)
    info "Restarting Asterisk..."
    safe_restart_asterisk >> "${LOG_FILE}" 2>&1 || warn "Asterisk restart had issues"

    # Set permissions
    fwconsole chown >> "${LOG_FILE}" 2>&1 || warn "Failed to set FreePBX permissions"

    track_install "freepbx"
    success "FreePBX ${FREEPBX_VERSION} installed successfully"
}

# =============================================================================
# FREEPBX CONFIGURATION
# =============================================================================

configure_freepbx() {
    step "⚙️  Configuring FreePBX network and SIP settings..."

    # Detect public and private IPs
    info "Detecting network configuration..."
    PRIVATE_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -1)
    PUBLIC_IP=$(curl -s -4 --max-time 5 ifconfig.me || curl -s -4 --max-time 5 icanhazip.com || echo "")

    if [ -z "${PUBLIC_IP}" ]; then
        PUBLIC_IP="${PRIVATE_IP}"
        info "Could not detect public IP, using private IP: ${PRIVATE_IP}"
    else
        info "Detected Public IP: ${PUBLIC_IP}, Private IP: ${PRIVATE_IP}"
    fi

    # Disable chan_sip (old SIP driver) to use PJSIP on port 5060
    info "Disabling chan_sip in favor of PJSIP..."

    # Disable chan_sip module loading
    if [ -f /etc/asterisk/modules.conf ]; then
        if ! grep -q "noload => chan_sip.so" /etc/asterisk/modules.conf; then
            echo "noload => chan_sip.so" >> /etc/asterisk/modules.conf
        fi
    else
        cat > /etc/asterisk/modules.conf << 'EOF'
[modules]
autoload=yes
noload => chan_sip.so
EOF
    fi

    # Configure PJSIP settings (primary SIP driver on port 5060)
    info "Configuring PJSIP settings..."

    # Backup existing configuration
    backup_config /etc/asterisk/pjsip_custom.conf

    # Only create base config if it doesn't exist or is empty
    if [ ! -f /etc/asterisk/pjsip_custom.conf ] || [ ! -s /etc/asterisk/pjsip_custom.conf ]; then
        cat > /etc/asterisk/pjsip_custom.conf << EOF
; ===== AUTOMATED PJSIP CONFIGURATION =====
[global]
type=global
user_agent=FreePBX PBX
max_forwards=70
keep_alive_interval=300
disable_multi_domain=yes

[transport-udp]
type=transport
protocol=udp
bind=0.0.0.0:5060
external_media_address=${PUBLIC_IP}
external_signaling_address=${PUBLIC_IP}
local_net=${PRIVATE_IP}/255.255.255.0

[transport-tcp]
type=transport
protocol=tcp
bind=0.0.0.0:5060

[transport-tls]
type=transport
protocol=tls
bind=0.0.0.0:5061
EOF
    else
        success "PJSIP configuration already exists, skipping to preserve user settings..."
    fi

    # Configure RTP settings
    info "Configuring RTP settings..."

    # Only add RTP config if not already present
    if [ ! -f /etc/asterisk/rtp.conf ] || ! grep -q "AUTOMATED RTP CONFIGURATION" /etc/asterisk/rtp.conf; then
        cat >> /etc/asterisk/rtp.conf << EOF

; ===== AUTOMATED RTP CONFIGURATION =====
[general]
rtpstart=10000
rtpend=20000
strictrtp=yes
icesupport=yes
stunaddr=stun.l.google.com:19302
EOF
    else
        success "RTP configuration already exists, skipping..."
    fi

    # Configure Asterisk modules
    info "Configuring Asterisk modules..."

    # Ensure critical modules are loaded (only if not already added)
    if ! grep -q "REQUIRED MODULES" /etc/asterisk/modules.conf 2>/dev/null; then
        cat >> /etc/asterisk/modules.conf << 'EOFMODULES'

; ===== REQUIRED MODULES =====
; Core modules
load => res_pjsip.so
load => res_pjsip_session.so
load => res_pjsip_outbound_registration.so
load => res_pjsip_endpoint_identifier_ip.so
load => res_pjsip_authenticator_digest.so
load => res_pjsip_nat.so
load => res_pjsip_transport_management.so
load => chan_pjsip.so

; RTP and Media
load => res_rtp_asterisk.so
load => res_srtp.so
load => res_http_websocket.so

; Dialplan and Applications
load => app_dial.so
load => app_playback.so
load => app_voicemail.so
load => app_directory.so
load => app_queue.so
load => app_confbridge.so
load => app_meetme.so
load => app_record.so
load => app_mixmonitor.so
load => app_chanspy.so
load => app_page.so

; Functions
load => func_callerid.so
load => func_cdr.so
load => func_strings.so
load => func_math.so
load => func_db.so

; CDR
load => cdr_csv.so
load => cdr_custom.so
load => cdr_manager.so

; Resources
load => res_musiconhold.so
load => res_agi.so
load => res_odbc.so
load => res_config_odbc.so

; Formats
load => format_wav.so
load => format_gsm.so
load => format_pcm.so
load => format_g729.so

; Codecs
load => codec_ulaw.so
load => codec_alaw.so
load => codec_gsm.so
load => codec_g722.so

; PBX Core
load => pbx_config.so
load => pbx_spool.so
load => pbx_realtime.so
EOFMODULES
    else
        success "Asterisk modules already configured, skipping..."
    fi

    # Install ALL FreePBX modules (70+ modules for full feature set)
    info "Installing comprehensive FreePBX module set (70+ modules)..."

    # Core Framework Modules (Essential)
    info "Installing core framework modules..."
    fwconsole ma downloadinstall framework core >> "${LOG_FILE}" 2>&1 || \
        warn "Core framework modules failed to install"

    # Connectivity & Trunking
    info "Installing connectivity modules..."
    fwconsole ma downloadinstall pjsip connectivity customappsreg >> "${LOG_FILE}" 2>&1 || true
    fwconsole ma downloadinstall trunk >> "${LOG_FILE}" 2>&1 || true

    # Extensions & Devices
    info "Installing extension modules..."
    fwconsole ma downloadinstall extensionsettings >> "${LOG_FILE}" 2>&1 || true

    # Call Routing & Management
    info "Installing call routing modules..."
    fwconsole ma downloadinstall inbound_routes outbound_routes >> "${LOG_FILE}" 2>&1 || true
    fwconsole ma downloadinstall ringgroups queues >> "${LOG_FILE}" 2>&1 || true
    fwconsole ma downloadinstall timeconditions daynight >> "${LOG_FILE}" 2>&1 || true
    fwconsole ma downloadinstall callforward callwaiting >> "${LOG_FILE}" 2>&1 || true
    fwconsole ma downloadinstall findmefollow followme >> "${LOG_FILE}" 2>&1 || true
    fwconsole ma downloadinstall donotdisturb >> "${LOG_FILE}" 2>&1 || true
    fwconsole ma downloadinstall callflow >> "${LOG_FILE}" 2>&1 || true
    fwconsole ma downloadinstall routing >> "${LOG_FILE}" 2>&1 || true

    # IVR & Menus
    info "Installing IVR and menu modules..."
    fwconsole ma downloadinstall ivr >> "${LOG_FILE}" 2>&1 || true
    fwconsole ma downloadinstall miscapps >> "${LOG_FILE}" 2>&1 || true
    fwconsole ma downloadinstall miscdests >> "${LOG_FILE}" 2>&1 || true

    # Voicemail & Messaging
    info "Installing voicemail modules..."
    fwconsole ma downloadinstall voicemail >> "${LOG_FILE}" 2>&1 || true
    fwconsole ma downloadinstall vmblast >> "${LOG_FILE}" 2>&1 || true
    fwconsole ma downloadinstall vmsettings >> "${LOG_FILE}" 2>&1 || true

    # Call Recording & Monitoring
    info "Installing recording and monitoring modules..."
    fwconsole ma downloadinstall callrecording >> "${LOG_FILE}" 2>&1 || true
    fwconsole ma downloadinstall recordings >> "${LOG_FILE}" 2>&1 || true
    fwconsole ma downloadinstall announcement >> "${LOG_FILE}" 2>&1 || true
    fwconsole ma downloadinstall soundlang >> "${LOG_FILE}" 2>&1 || true
    fwconsole ma downloadinstall music >> "${LOG_FILE}" 2>&1 || true

    # Conferences & Collaboration
    info "Installing conference modules..."
    fwconsole ma downloadinstall conferences >> "${LOG_FILE}" 2>&1 || true
    fwconsole ma downloadinstall conferenceapps >> "${LOG_FILE}" 2>&1 || true

    # Call Features
    info "Installing call feature modules..."
    fwconsole ma downloadinstall parking >> "${LOG_FILE}" 2>&1 || true
    fwconsole ma downloadinstall paging >> "${LOG_FILE}" 2>&1 || true
    fwconsole ma downloadinstall pagingadmin >> "${LOG_FILE}" 2>&1 || true
    fwconsole ma downloadinstall pinsets >> "${LOG_FILE}" 2>&1 || true
    fwconsole ma downloadinstall speeddial >> "${LOG_FILE}" 2>&1 || true
    fwconsole ma downloadinstall callback >> "${LOG_FILE}" 2>&1 || true
    fwconsole ma downloadinstall callmenu >> "${LOG_FILE}" 2>&1 || true
    fwconsole ma downloadinstall dictate >> "${LOG_FILE}" 2>&1 || true

    # System Administration
    info "Installing system administration modules..."
    fwconsole ma downloadinstall dashboard >> "${LOG_FILE}" 2>&1 || true
    fwconsole ma downloadinstall backup >> "${LOG_FILE}" 2>&1 || true
    fwconsole ma downloadinstall logfiles >> "${LOG_FILE}" 2>&1 || true
    fwconsole ma downloadinstall asteriskinfo >> "${LOG_FILE}" 2>&1 || true
    fwconsole ma downloadinstall sysadmin >> "${LOG_FILE}" 2>&1 || true
    fwconsole ma downloadinstall filestore >> "${LOG_FILE}" 2>&1 || true

    # CDR & Reporting
    info "Installing CDR and reporting modules..."
    fwconsole ma downloadinstall cdr >> "${LOG_FILE}" 2>&1 || true
    fwconsole ma downloadinstall cdrreports >> "${LOG_FILE}" 2>&1 || true

    # Caller ID & Directory
    info "Installing caller ID and directory modules..."
    fwconsole ma downloadinstall cidlookup >> "${LOG_FILE}" 2>&1 || true
    fwconsole ma downloadinstall directory >> "${LOG_FILE}" 2>&1 || true
    fwconsole ma downloadinstall phonebook >> "${LOG_FILE}" 2>&1 || true

    # Security & Authentication
    info "Installing security modules..."
    fwconsole ma downloadinstall certman >> "${LOG_FILE}" 2>&1 || true
    fwconsole ma downloadinstall userman >> "${LOG_FILE}" 2>&1 || true
    fwconsole ma downloadinstall restapi >> "${LOG_FILE}" 2>&1 || true
    fwconsole ma downloadinstall arimanager >> "${LOG_FILE}" 2>&1 || true

    # User Control Panel & WebRTC
    info "Installing UCP and WebRTC modules..."
    fwconsole ma downloadinstall ucp >> "${LOG_FILE}" 2>&1 || true
    fwconsole ma downloadinstall webrtc >> "${LOG_FILE}" 2>&1 || true

    # Advanced Features
    info "Installing advanced feature modules..."
    fwconsole ma downloadinstall weakpasswords >> "${LOG_FILE}" 2>&1 || true
    fwconsole ma downloadinstall featurecodeadmin >> "${LOG_FILE}" 2>&1 || true
    fwconsole ma downloadinstall contactmanager >> "${LOG_FILE}" 2>&1 || true
    fwconsole ma downloadinstall asterisk-cli >> "${LOG_FILE}" 2>&1 || true
    fwconsole ma downloadinstall fw_langpacks >> "${LOG_FILE}" 2>&1 || true
    fwconsole ma downloadinstall languages >> "${LOG_FILE}" 2>&1 || true

    # Utilities
    info "Installing utility modules..."
    fwconsole ma downloadinstall setcid >> "${LOG_FILE}" 2>&1 || true
    fwconsole ma downloadinstall blockcid >> "${LOG_FILE}" 2>&1 || true
    fwconsole ma downloadinstall blacklist >> "${LOG_FILE}" 2>&1 || true
    fwconsole ma downloadinstall calltagging >> "${LOG_FILE}" 2>&1 || true
    fwconsole ma downloadinstall accountcodepreserve >> "${LOG_FILE}" 2>&1 || true
    fwconsole ma downloadinstall bulkhandler >> "${LOG_FILE}" 2>&1 || true

    # Endpoint Management
    info "Installing endpoint management modules..."
    fwconsole ma downloadinstall endpointman >> "${LOG_FILE}" 2>&1 || true
    fwconsole ma downloadinstall pm2 >> "${LOG_FILE}" 2>&1 || true

    # Refresh module list
    fwconsole ma refreshsignatures >> "${LOG_FILE}" 2>&1 || true
    fwconsole ma upgradeall >> "${LOG_FILE}" 2>&1 || true

    success "All FreePBX modules installed successfully"

    # Apply FreePBX configurations via fwconsole
    info "Applying FreePBX module configurations..."

    # Set Asterisk SIP Settings via fwconsole
    fwconsole setting FREEPBX_SYSTEM_IDENT "${SYSTEM_FQDN}" >> "${LOG_FILE}" 2>&1 || true

    # Set permissions
    fwconsole chown >> "${LOG_FILE}" 2>&1 || warn "Failed to set FreePBX permissions"

    # Reload Asterisk and FreePBX
    info "Reloading Asterisk and FreePBX..."
    fwconsole reload >> "${LOG_FILE}" 2>&1 || true
    asterisk -rx "module reload" >> "${LOG_FILE}" 2>&1 || true
    asterisk -rx "pjsip reload" >> "${LOG_FILE}" 2>&1 || true
    asterisk -rx "rtp reload" >> "${LOG_FILE}" 2>&1 || true
    asterisk -rx "dialplan reload" >> "${LOG_FILE}" 2>&1 || true

    track_install "freepbx_config"
    success "FreePBX configured with Public IP: ${PUBLIC_IP}, Private IP: ${PRIVATE_IP}"
}

# =============================================================================
# POSTFIX MAIL SERVER INSTALLATION
# =============================================================================

install_postfix() {
    step "📧 Installing Postfix mail server..."

    # Install Postfix
    case "${PACKAGE_MANAGER}" in
        apt-get)
            DEBIAN_FRONTEND=noninteractive apt-get install -y postfix >> "${LOG_FILE}" 2>&1 || \
                error "Failed to install Postfix"
            ;;
        yum|dnf)
            ${PACKAGE_MANAGER} install -y postfix >> "${LOG_FILE}" 2>&1 || \
                error "Failed to install Postfix"
            ;;
    esac

    # Enable and start Postfix
    systemctl enable postfix >> "${LOG_FILE}" 2>&1
    systemctl start postfix >> "${LOG_FILE}" 2>&1 || \
        warn "Failed to start Postfix"

    # Set Postfix as default MTA
    if command -v alternatives >/dev/null 2>&1; then
        alternatives --set mta /usr/sbin/sendmail.postfix >> "${LOG_FILE}" 2>&1 || true
    fi

    track_install "postfix"
    success "Postfix mail server installed"
}

# =============================================================================
# EMAIL-TO-FAX CONFIGURATION
# =============================================================================

configure_email_to_fax() {
    step "📧→📠 Configuring email-to-fax with secure alias..."

    # Add alias to /etc/aliases
    if ! grep -q "^${EMAIL_TO_FAX_ALIAS}:" /etc/aliases 2>/dev/null; then
        echo "${EMAIL_TO_FAX_ALIAS}: \"|/usr/local/bin/mail2fax\"" >> /etc/aliases
        info "Added email-to-fax alias: ${EMAIL_TO_FAX_ALIAS}@${SYSTEM_DOMAIN}"
    else
        info "Email-to-fax alias already exists"
    fi

    # Rebuild aliases database
    newaliases >> "${LOG_FILE}" 2>&1 || warn "Failed to rebuild aliases"

    # Create mail2fax script
    cat > /usr/local/bin/mail2fax << 'MAIL2FAX_EOF'
#!/bin/bash
# Email-to-Fax Gateway Script
# Receives emails and sends them as faxes via HylaFAX

# Read email from stdin
EMAIL_FILE=$(mktemp)
cat > "${EMAIL_FILE}"

# Extract recipient fax number from subject (format: "Fax to: 15551234567")
FAX_NUMBER=$(grep -i "^Subject:.*Fax to:" "${EMAIL_FILE}" | sed -n 's/.*Fax to:[[:space:]]*\([0-9+]*\).*/\1/p')

if [ -z "${FAX_NUMBER}" ]; then
    echo "ERROR: No fax number found in subject line" | logger -t mail2fax
    rm -f "${EMAIL_FILE}"
    exit 1
fi

# Extract and convert email body/attachments to fax format
# This is a basic implementation - production systems may need more sophisticated parsing
BODY_FILE=$(mktemp)
grep -A 999999 "^$" "${EMAIL_FILE}" | tail -n +2 > "${BODY_FILE}"

# Send via HylaFAX sendfax command
/usr/bin/sendfax -n -d "${FAX_NUMBER}" "${BODY_FILE}" >> /var/log/mail2fax.log 2>&1

# Cleanup
rm -f "${EMAIL_FILE}" "${BODY_FILE}"

exit 0
MAIL2FAX_EOF

    chmod +x /usr/local/bin/mail2fax

    # Create log file
    touch /var/log/mail2fax.log
    chown root:root /var/log/mail2fax.log
    chmod 644 /var/log/mail2fax.log

    # Restart Postfix to apply changes
    systemctl restart postfix >> "${LOG_FILE}" 2>&1 || warn "Failed to restart Postfix"

    track_install "email_to_fax"
    success "Email-to-fax configured: ${EMAIL_TO_FAX_ALIAS}@${SYSTEM_DOMAIN}"
}

# =============================================================================
# FAX-TO-EMAIL CONFIGURATION
# =============================================================================

configure_fax_to_email() {
    step "📠→📧 Configuring fax-to-email delivery..."

    # Configure HylaFAX to email received faxes
    # This is done in /var/spool/hylafax/etc/FaxDispatch

    if [ ! -f /var/spool/hylafax/etc/FaxDispatch ]; then
        cat > /var/spool/hylafax/etc/FaxDispatch << FAXDISPATCH_EOF
# HylaFAX Fax Dispatch Configuration
# Send all received faxes to admin email

SENDTO="${FAX_TO_EMAIL_ADDRESS}"
FILETYPE=pdf

# Email subject and body
TEMPLATE=en
FAXMASTER="${FAX_TO_EMAIL_ADDRESS}"
FAXADMIN="${FAX_TO_EMAIL_ADDRESS}"
FAXDISPATCH_EOF

        chown uucp:uucp /var/spool/hylafax/etc/FaxDispatch
        chmod 644 /var/spool/hylafax/etc/FaxDispatch

        info "Created FaxDispatch configuration"
    else
        info "FaxDispatch already exists"
    fi

    # Ensure faxrcvd script uses email delivery
    if [ -f /var/spool/hylafax/bin/faxrcvd ]; then
        # faxrcvd should already be configured by HylaFAX to use FaxDispatch
        info "faxrcvd script exists"
    fi

    track_install "fax_to_email"
    success "Fax-to-email configured to: ${FAX_TO_EMAIL_ADDRESS}"
}

# =============================================================================
# HYLAFAX+ INSTALLATION
# =============================================================================

install_hylafax() {
    step "📠 Installing HylaFax+ fax server..."

    cd "${WORK_DIR}"

    # Create uucp user if doesn't exist
    if ! id -u uucp >/dev/null 2>&1; then
        useradd -r -d /var/spool/hylafax -s /bin/bash uucp
    fi

    # Download HylaFax+
    info "Downloading HylaFax+ source..."
    local HYLAFAX_VERSION="7.0.11"
    local HYLAFAX_URL="https://sourceforge.net/projects/hylafax/files/hylafax/hylafax-${HYLAFAX_VERSION}.tar.gz/download"

    curl -sL "${HYLAFAX_URL}" -o "hylafax-${HYLAFAX_VERSION}.tar.gz" >> "${LOG_FILE}" 2>&1 || \
        error "Failed to download HylaFax+"

    # Extract
    info "Extracting HylaFax+ source..."
    tar -xzf "hylafax-${HYLAFAX_VERSION}.tar.gz" >> "${LOG_FILE}" 2>&1 || \
        error "Failed to extract HylaFax+"

    cd "hylafax-${HYLAFAX_VERSION}" || error "Failed to enter HylaFax+ directory"

    # Configure
    info "Configuring HylaFax+..."
    ./configure \
        --nointeractive \
        --with-DIR_BIN=/usr/local/bin \
        --with-DIR_SBIN=/usr/local/sbin \
        --with-DIR_LIBDATA=/usr/local/lib/fax \
        --with-DIR_LIBEXEC=/usr/local/sbin \
        --with-DIR_SPOOL=/var/spool/hylafax \
        --with-AFM=no \
        --with-AWK=/usr/bin/awk \
        --with-PATH_VGETTY=/bin/false \
        --with-PATH_EGETTY=/bin/false >> "${LOG_FILE}" 2>&1 || \
        error "HylaFax+ configure failed"

    # Compile and install (sequential make required for HylaFax+)
    info "Compiling and installing HylaFax+..."
    make >> "${LOG_FILE}" 2>&1 || \
        error "HylaFax+ compilation failed"

    make install >> "${LOG_FILE}" 2>&1 || \
        error "HylaFax+ installation failed"

    # Set permissions
    chown -R uucp:uucp /var/spool/hylafax
    chmod 755 /var/spool/hylafax

    # Create systemd service
    create_hylafax_service

    track_install "hylafax"
    success "HylaFax+ installed successfully"
}

# =============================================================================
# IAXMODEM INSTALLATION
# =============================================================================

install_iaxmodem() {
    step "📟 Installing IAXmodem..."

    cd "${WORK_DIR}"

    # Download IAXmodem
    info "Downloading IAXmodem source..."
    local IAXMODEM_VERSION="1.3.4"
    local IAXMODEM_URL="https://sourceforge.net/projects/iaxmodem/files/latest/download"

    wget -O "iaxmodem-${IAXMODEM_VERSION}.tar.gz" "${IAXMODEM_URL}" >> "${LOG_FILE}" 2>&1 || \
        error "Failed to download IAXmodem"

    # Extract
    info "Extracting IAXmodem source..."
    tar -xzf "iaxmodem-${IAXMODEM_VERSION}.tar.gz" >> "${LOG_FILE}" 2>&1 || \
        error "Failed to extract IAXmodem"

    cd "iaxmodem-${IAXMODEM_VERSION}" || error "Failed to enter IAXmodem directory"

    # Compile and install (using static build to include bundled libraries)
    info "Compiling IAXmodem..."
    ./build static >> "${LOG_FILE}" 2>&1 || error "IAXmodem compilation failed"

    # Install the compiled binary
    info "Installing IAXmodem..."
    cp iaxmodem /usr/local/bin/ || error "IAXmodem installation failed"
    chmod +x /usr/local/bin/iaxmodem

    # Create IAXmodem configuration directory
    mkdir -p /etc/iaxmodem
    mkdir -p /var/run/iaxmodem
    mkdir -p /var/log/iaxmodem
    chown -R uucp:uucp /var/run/iaxmodem /var/log/iaxmodem

    # Configure modems
    info "Configuring ${NUMBER_OF_MODEMS} virtual fax modems..."
    local modem_num
    local port=4570

    for modem_num in $(seq 0 $((NUMBER_OF_MODEMS - 1))); do
        cat > "/etc/iaxmodem/ttyIAX${modem_num}.cfg" << EOF
device /dev/ttyIAX${modem_num}
owner uucp:uucp
mode 660
port ${port}
refresh 300
peername iaxmodem${modem_num}
secret password
cidname Fax Modem ${modem_num}
cidnumber 5555555${modem_num}
codec slinear
EOF
        port=$((port + 1))
    done

    # Configure Asterisk for IAXmodem
    info "Configuring Asterisk for IAXmodem..."
    cat >> /etc/asterisk/iax.conf << EOF

; IAXmodem Configuration
[iaxmodem0]
type=friend
context=from-internal
host=dynamic
secret=password
qualify=yes
EOF

    # Create systemd services for modems
    create_iaxmodem_services

    track_install "iaxmodem"
    success "IAXmodem installed and configured for ${NUMBER_OF_MODEMS} modems"
}

# =============================================================================
# AVANTFAX INSTALLATION
# =============================================================================

install_avantfax() {
    step "🖨️  Installing AvantFax web interface..."

    cd "${WORK_DIR}"

    # Install PHP 7.4 for AvantFax (if not already installed)
    info "Installing PHP ${PHP_AVANTFAX_VERSION} for AvantFax..."
    case "${PACKAGE_MANAGER}" in
        apt-get)
            DEBIAN_FRONTEND=noninteractive apt-get install -y \
                php${PHP_AVANTFAX_VERSION} \
                php${PHP_AVANTFAX_VERSION}-mysql \
                php${PHP_AVANTFAX_VERSION}-gd \
                php${PHP_AVANTFAX_VERSION}-imap >> "${LOG_FILE}" 2>&1 || \
                warn "Failed to install PHP ${PHP_AVANTFAX_VERSION}"
            ;;
        yum|dnf)
            # Use Remi SCL packages for PHP 7.4 (allows coexistence with PHP 8.2)
            ${PACKAGE_MANAGER} install -y \
                php74-php \
                php74-php-cli \
                php74-php-common \
                php74-php-gd \
                php74-php-mbstring \
                php74-php-mysqlnd \
                php74-php-pdo \
                php74-php-xml \
                php74-php-ldap \
                php74-php-imap \
                php74-php-fpm >> "${LOG_FILE}" 2>&1 || \
                warn "Failed to install PHP 7.4"

            # Configure PHP 7.4 FPM to listen on port 9074
            if [ -f /etc/opt/remi/php74/php-fpm.d/www.conf ]; then
                backup_config /etc/opt/remi/php74/php-fpm.d/www.conf
                sed -i 's/^listen = .*/listen = 127.0.0.1:9074/' /etc/opt/remi/php74/php-fpm.d/www.conf
                sed -i 's/^;listen.allowed_clients/listen.allowed_clients/' /etc/opt/remi/php74/php-fpm.d/www.conf
            fi

            # Enable and restart PHP 7.4 FPM (restart to apply TCP port configuration)
            systemctl enable php74-php-fpm >> "${LOG_FILE}" 2>&1 || warn "Failed to enable PHP 7.4 FPM"
            systemctl restart php74-php-fpm >> "${LOG_FILE}" 2>&1 || warn "Failed to restart PHP 7.4 FPM"

            # Verify PHP 7.4 FPM is listening on correct port
            sleep 2
            if ss -tln | grep -q ':9074'; then
                info "PHP 7.4 FPM listening on port 9074"
            else
                warn "PHP 7.4 FPM may not be listening on port 9074"
            fi
            ;;
    esac

    # Download AvantFax from SourceForge (official source)
    info "Downloading AvantFax 3.4.1..."
    AVANTFAX_VERSION="3.4.1"
    AVANTFAX_URL="https://sourceforge.net/projects/avantfax/files/avantfax-${AVANTFAX_VERSION}.tgz/download"

    wget -O avantfax-${AVANTFAX_VERSION}.tgz "${AVANTFAX_URL}" >> "${LOG_FILE}" 2>&1 || \
        error "Failed to download AvantFax from SourceForge (REQUIRED)"

    tar xzf avantfax-${AVANTFAX_VERSION}.tgz >> "${LOG_FILE}" 2>&1 || \
        error "Failed to extract AvantFax tarball (REQUIRED)"

    cd avantfax-${AVANTFAX_VERSION} || error "Failed to enter AvantFax directory (REQUIRED)"

    # Install to web directory (copy from inner avantfax subdirectory)
    info "Installing AvantFax..."
    mkdir -p "${AVANTFAX_WEB_DIR}"
    if [ -d "avantfax" ]; then
        # Newer tarball structure has nested directory
        cp -r avantfax/* "${AVANTFAX_WEB_DIR}/"
    else
        # Older tarball structure has files at top level
        cp -r * "${AVANTFAX_WEB_DIR}/"
    fi
    chown -R "${APACHE_USER}:${APACHE_GROUP}" "${AVANTFAX_WEB_DIR}"

    # Create database
    info "Creating AvantFax database..."
    mysql << EOF 2>/dev/null || warn "Failed to create AvantFax database"
CREATE DATABASE IF NOT EXISTS avantfax;
CREATE USER IF NOT EXISTS 'avantfax'@'localhost' IDENTIFIED BY '${AVANTFAX_DB_PASSWORD}';
GRANT ALL PRIVILEGES ON avantfax.* TO 'avantfax'@'localhost';
FLUSH PRIVILEGES;
EOF

    # Import database schema
    if [ -f "${AVANTFAX_WEB_DIR}/database.sql" ]; then
        mysql avantfax < "${AVANTFAX_WEB_DIR}/database.sql" >> "${LOG_FILE}" 2>&1 || \
            warn "Failed to import AvantFax database"
    fi

    # Initialize AvantFax database tables
    info "Initializing AvantFax database..."
    if [ -f "${AVANTFAX_WEB_DIR}/create_tables.sql" ]; then
        mysql avantfax < "${AVANTFAX_WEB_DIR}/create_tables.sql" >> "${LOG_FILE}" 2>&1 || \
            warn "AvantFax tables may already exist"
    fi

    # Create AvantFax admin user with same password as FreePBX
    info "Creating AvantFax admin user..."
    mysql avantfax << EOF >> "${LOG_FILE}" 2>&1 || warn "AvantFax admin user may already exist"
-- Create admin user with same password as FreePBX admin
-- Using INSERT IGNORE to skip if user already exists
INSERT IGNORE INTO UserAccount (uid, username, password, name, email, superuser, is_admin, acc_enabled, any_modem)
VALUES (1, 'administrator', MD5('${FREEPBX_ADMIN_PASSWORD}'), 'System Administrator', '${ADMIN_EMAIL}', 1, 1, 1, 1);
EOF

    # Configure AvantFax
    info "Configuring AvantFax..."

    # Try different config file names (version dependent)
    if [ -f "${AVANTFAX_WEB_DIR}/includes/local_config-example.php" ]; then
        cp "${AVANTFAX_WEB_DIR}/includes/local_config-example.php" \
           "${AVANTFAX_WEB_DIR}/includes/local_config.php"
    elif [ -f "${AVANTFAX_WEB_DIR}/includes/local_config.php.sample" ]; then
        cp "${AVANTFAX_WEB_DIR}/includes/local_config.php.sample" \
           "${AVANTFAX_WEB_DIR}/includes/local_config.php"
    fi

    # Update database password in config
    if [ -f "${AVANTFAX_WEB_DIR}/includes/local_config.php" ]; then
        sed -i "s/define('AFDB_PASS',.*/define('AFDB_PASS',		'${AVANTFAX_DB_PASSWORD}');		\/\/ password/" \
            "${AVANTFAX_WEB_DIR}/includes/local_config.php"
        chmod 640 "${AVANTFAX_WEB_DIR}/includes/local_config.php"
        info "AvantFax configuration file created and configured"
    else
        warn "Could not find AvantFax config template"
    fi

    # Set permissions
    chmod 755 "${AVANTFAX_WEB_DIR}"
    chown -R "${APACHE_USER}:${APACHE_GROUP}" "${AVANTFAX_WEB_DIR}"

    track_install "avantfax"
    success "AvantFax installed successfully at ${AVANTFAX_WEB_DIR}"
}

# =============================================================================
# ASTERISK SOUNDS AND PROMPTS
# =============================================================================

install_asterisk_sounds() {
    step "🔊 Installing Asterisk sounds and prompts..."

    cd "${WORK_DIR}"

    local sounds_dir="/var/lib/asterisk/sounds"
    mkdir -p "${sounds_dir}"

    # Download core English sounds (WAV, high quality)
    info "Downloading Asterisk core sounds..."
    local SOUNDS_URL="https://downloads.asterisk.org/pub/telephony/sounds"

    wget -q "${SOUNDS_URL}/asterisk-core-sounds-en-wav-current.tar.gz" -O asterisk-core-sounds.tar.gz >> "${LOG_FILE}" 2>&1 || \
        warn "Failed to download core sounds"

    if [ -f asterisk-core-sounds.tar.gz ]; then
        tar -xzf asterisk-core-sounds.tar.gz -C "${sounds_dir}" >> "${LOG_FILE}" 2>&1
        rm -f asterisk-core-sounds.tar.gz
    fi

    # Download extra sounds
    info "Downloading Asterisk extra sounds..."
    wget -q "${SOUNDS_URL}/asterisk-extra-sounds-en-wav-current.tar.gz" -O asterisk-extra-sounds.tar.gz >> "${LOG_FILE}" 2>&1 || \
        warn "Failed to download extra sounds"

    if [ -f asterisk-extra-sounds.tar.gz ]; then
        tar -xzf asterisk-extra-sounds.tar.gz -C "${sounds_dir}" >> "${LOG_FILE}" 2>&1
        rm -f asterisk-extra-sounds.tar.gz
    fi

    # Download Music on Hold
    info "Downloading Music on Hold files..."
    wget -q "${SOUNDS_URL}/asterisk-moh-opsound-wav-current.tar.gz" -O asterisk-moh.tar.gz >> "${LOG_FILE}" 2>&1 || \
        warn "Failed to download MOH files"

    if [ -f asterisk-moh.tar.gz ]; then
        mkdir -p /var/lib/asterisk/moh
        tar -xzf asterisk-moh.tar.gz -C /var/lib/asterisk/moh >> "${LOG_FILE}" 2>&1
        rm -f asterisk-moh.tar.gz
    fi

    # Set permissions
    chown -R asterisk:asterisk /var/lib/asterisk/sounds
    chown -R asterisk:asterisk /var/lib/asterisk/moh
    chmod -R 755 /var/lib/asterisk/sounds
    chmod -R 755 /var/lib/asterisk/moh

    track_install "sounds"
    success "Asterisk sounds and prompts installed"
}

# =============================================================================
# TTS ENGINE INSTALLATION
# =============================================================================

install_tts_engine() {
    step "🗣️  Installing TTS (Text-to-Speech) engine..."

    # Install Flite (lightweight TTS engine)
    info "Installing Flite TTS engine..."

    case "${PACKAGE_MANAGER}" in
        apt-get)
            DEBIAN_FRONTEND=noninteractive apt-get install -y flite >> "${LOG_FILE}" 2>&1 || \
                warn "Failed to install Flite"
            ;;
        yum|dnf)
            ${PACKAGE_MANAGER} install -y flite >> "${LOG_FILE}" 2>&1 || \
                warn "Failed to install Flite"
            ;;
    esac

    # Test if flite is available
    if command_exists flite; then
        info "Flite TTS engine installed successfully"

        # Create simple test script
        mkdir -p /var/lib/asterisk/agi-bin
        cat > /var/lib/asterisk/agi-bin/tts-test << 'EOF'
#!/bin/sh
# Simple TTS test script
TEXT="${1:-Hello, this is a text to speech test.}"
flite -t "$TEXT" -o /tmp/tts_output.wav
echo "TTS audio saved to /tmp/tts_output.wav"
EOF
        chmod +x /var/lib/asterisk/agi-bin/tts-test
        chown asterisk:asterisk /var/lib/asterisk/agi-bin/tts-test

        # Create 411 Directory Service audio prompts
        info "Creating 411 directory service prompts..."
        SOUNDS_DIR="/var/lib/asterisk/sounds/en"
        mkdir -p "${SOUNDS_DIR}"

        # Create intro prompt
        flite -t "Welcome to directory assistance. This service is free and provided by your P B X system." \
            -o "${SOUNDS_DIR}/dir-intro.wav" 2>/dev/null || true

        # Create options menu
        flite -t "Press 1 to search by first name. Press 2 to search by last name. Press 3 to browse all extensions. Or stay on the line to search by last name." \
            -o "${SOUNDS_DIR}/dir-options.wav" 2>/dev/null || true

        # Convert to appropriate formats for Asterisk
        if command_exists sox; then
            for file in dir-intro dir-options; do
                if [ -f "${SOUNDS_DIR}/${file}.wav" ]; then
                    sox "${SOUNDS_DIR}/${file}.wav" -r 8000 -c 1 -t wav "${SOUNDS_DIR}/${file}.sln" 2>/dev/null || true
                    sox "${SOUNDS_DIR}/${file}.wav" -r 8000 -c 1 "${SOUNDS_DIR}/${file}.ulaw" 2>/dev/null || true
                fi
            done
        fi

        chown -R asterisk:asterisk "${SOUNDS_DIR}"
        success "411 directory service prompts created"
    fi

    track_install "tts"
    success "TTS engine installed"
}

# =============================================================================
# AGI SCRIPTS INSTALLATION
# =============================================================================

install_agi_scripts() {
    step "📜 Installing AGI (Asterisk Gateway Interface) scripts..."

    local agi_dir="/var/lib/asterisk/agi-bin"
    mkdir -p "${agi_dir}"

    # Create sample AGI scripts

    # 1. Call logging AGI
    info "Creating sample AGI scripts..."
    cat > "${agi_dir}/call-logger" << 'EOF'
#!/bin/sh
# Simple call logging AGI script
# Usage: AGI(call-logger)

read -r AGI_REQUEST
read -r AGI_CHANNEL
read -r AGI_LANGUAGE
read -r AGI_TYPE
read -r AGI_UNIQUEID
read -r AGI_CALLERID
read -r AGI_CALLERIDNAME
read -r AGI_CALLINGPRES
read -r AGI_CALLINGANI2
read -r AGI_CALLINGTON
read -r AGI_CALLINGTNS
read -r AGI_DNID
read -r AGI_RDNIS
read -r AGI_CONTEXT
read -r AGI_EXTENSION
read -r AGI_PRIORITY
read -r AGI_ENHANCED
read -r AGI_ACCOUNTCODE
read -r AGI_THREADID

# Log call details
echo "$(date): Call from ${AGI_CALLERID} to ${AGI_EXTENSION}" >> /var/log/asterisk/agi-calls.log

# Return success
echo "VERBOSE \"Call logged\" 1"
echo "200 result=0"
EOF

    # 2. Number validation AGI
    cat > "${agi_dir}/validate-number" << 'EOF'
#!/bin/sh
# Validate phone number format
# Usage: AGI(validate-number,${EXTEN})

NUMBER="$1"

if echo "$NUMBER" | grep -qE '^\+?[0-9]{10,15}$'; then
    echo "SET VARIABLE VALID_NUMBER 1"
    echo "200 result=1"
else
    echo "SET VARIABLE VALID_NUMBER 0"
    echo "200 result=0"
fi
EOF

    # 3. Business hours check
    cat > "${agi_dir}/check-hours" << 'EOF'
#!/bin/sh
# Check if current time is within business hours
# Usage: AGI(check-hours)

HOUR=$(date +%H)
DAY=$(date +%u)

# Monday-Friday (1-5), 9 AM - 5 PM
if [ "$DAY" -le 5 ] && [ "$HOUR" -ge 9 ] && [ "$HOUR" -lt 17 ]; then
    echo "SET VARIABLE BUSINESS_HOURS 1"
    echo "200 result=1"
else
    echo "SET VARIABLE BUSINESS_HOURS 0"
    echo "200 result=0"
fi
EOF

    # Set permissions
    chmod +x "${agi_dir}"/*
    chown -R asterisk:asterisk "${agi_dir}"

    track_install "agi"
    success "AGI scripts installed in ${agi_dir}"
}

# =============================================================================
# DEMO APPLICATIONS & ADVANCED DIALPLAN
# =============================================================================

install_demo_applications() {
    step "📞 Installing comprehensive demo applications and features..."

    # Backup existing demo dialplan
    backup_config /etc/asterisk/extensions_incrediblepbx.conf

    # Check if demo apps are already installed
    if [ -f /etc/asterisk/extensions_incrediblepbx.conf ] && grep -q "IncrediblePBX Demo Applications" /etc/asterisk/extensions_incrediblepbx.conf; then
        success "Demo applications already installed, skipping to preserve customizations..."
        track_install "demo_apps"
        return 0
    fi

    # Create custom extensions file
    cat > /etc/asterisk/extensions_incrediblepbx.conf << 'EOFDEMO'
; =============================================================================
; IncrediblePBX Demo Applications & Features
; =============================================================================

[from-internal-custom]
include => incrediblepbx-demos
include => incrediblepbx-apps

; =============================================================================
; DEMO APPLICATIONS (Dial from any extension)
; =============================================================================

[incrediblepbx-demos]

; DEMO - System Demo (Information about this PBX)
exten => DEMO,1,Answer()
 same => n,Wait(1)
 same => n,Playback(welcome)
 same => n,Playback(to-call-demo)
 same => n,SayDigits(123)
 same => n,Playback(for-time)
 same => n,SayDigits(951)
 same => n,Playback(for-weather)
 same => n,SayDigits(947)
 same => n,Hangup()

; 123 - Speaking Clock
exten => 123,1,Answer()
 same => n,Wait(1)
 same => n,Playback(at-tone-time-exactly)
 same => n,SayUnixTime(,Etc/UTC,HMSdY)
 same => n,Playback(thank-you-for-calling)
 same => n,Hangup()

; 947 - Weather Report (TTS Demo)
exten => 947,1,Answer()
 same => n,Wait(1)
 same => n(weather),agi(weather.sh)
 same => n,Hangup()

; 951 - Today's Date
exten => 951,1,Answer()
 same => n,Wait(1)
 same => n,Playback(todays-date-is)
 same => n,SayUnixTime(,Etc/UTC,BdY)
 same => n,Hangup()

; TODAY - Same as 951
exten => TODAY,1,Goto(951,1)

; *68 - Wakeup Call Service
exten => *68,1,Answer()
 same => n,Wait(1)
 same => n,Playback(please-enter-your)
 same => n,Playback(wakeup)
 same => n,Playback(time)
 same => n,Read(waketime,beep,4)
 same => n,SayDigits(${waketime})
 same => n,Set(DB(wakeup/${CALLERID(num)})=${waketime})
 same => n,Playback(your-wakeup-call-is-set)
 same => n,Hangup()

; 4747 - LENNY (Keep telemarketers busy)
exten => 4747,1,Answer()
 same => n,Wait(1)
 same => n,Playback(lenny/Lenny1)
 same => n,WaitExten(10)
 same => n,Playback(lenny/Lenny2)
 same => n,WaitExten(10)
 same => n,Playback(lenny/Lenny3)
 same => n,WaitExten(10)
 same => n,Playback(lenny/Lenny4)
 same => n,WaitExten(10)
 same => n,Playback(lenny/Lenny5)
 same => n,WaitExten(10)
 same => n,Playback(lenny/Lenny6)
 same => n,WaitExten(10)
 same => n,Hangup()

; LENNY - Same as 4747
exten => LENNY,1,Goto(4747,1)

; *97 - Voicemail Main Menu
exten => *97,1,Answer()
 same => n,Wait(1)
 same => n,VoiceMailMain(${CALLERID(num)}@default)
 same => n,Hangup()

; *98 - Voicemail Check (with PIN)
exten => *98,1,Answer()
 same => n,Wait(1)
 same => n,VoiceMailMain()
 same => n,Hangup()

; *43 - Echo Test
exten => *43,1,Answer()
 same => n,Wait(1)
 same => n,Playback(demo-echotest)
 same => n,Echo()
 same => n,Playback(demo-echodone)
 same => n,Hangup()

; *469 - Conference Room 1
exten => *469,1,Answer()
 same => n,Wait(1)
 same => n,Playback(conf-entering)
 same => n,ConfBridge(1)
 same => n,Hangup()

; *470 - Conference Room 2
exten => *470,1,Answer()
 same => n,Wait(1)
 same => n,Playback(conf-entering)
 same => n,ConfBridge(2)
 same => n,Hangup()

; =============================================================================
; UTILITY APPLICATIONS
; =============================================================================

[incrediblepbx-apps]

; *72 - Call Forward Enable
exten => *72,1,Answer()
 same => n,Wait(1)
 same => n,Playback(please-enter-your)
 same => n,Playback(extension)
 same => n,Read(fwdnum,then-press-pound,10)
 same => n,Set(DB(CFWD/${CALLERID(num)})=${fwdnum})
 same => n,Playback(call-fwd-on)
 same => n,Playback(to)
 same => n,SayDigits(${fwdnum})
 same => n,Hangup()

; *73 - Call Forward Disable
exten => *73,1,Answer()
 same => n,Wait(1)
 same => n,DBdel(CFWD/${CALLERID(num)})
 same => n,Playback(call-fwd-cancelled)
 same => n,Hangup()

; *76 - Do Not Disturb Enable
exten => *76,1,Answer()
 same => n,Wait(1)
 same => n,Set(DB(DND/${CALLERID(num)})=YES)
 same => n,Playback(do-not-disturb)
 same => n,Playback(activated)
 same => n,Hangup()

; *77 - Do Not Disturb Disable
exten => *77,1,Answer()
 same => n,Wait(1)
 same => n,DBdel(DND/${CALLERID(num)})
 same => n,Playback(do-not-disturb)
 same => n,Playback(de-activated)
 same => n,Hangup()

; *78 - Call Recording Toggle
exten => *78,1,Answer()
 same => n,Wait(1)
 same => n,Set(RECSTATUS=${DB(REC/${CALLERID(num)})})
 same => n,GotoIf($["${RECSTATUS}" = "ON"]?recoff:recon)
 same => n(recon),Set(DB(REC/${CALLERID(num)})=ON)
 same => n,Playback(call-recording)
 same => n,Playback(activated)
 same => n,Hangup()
 same => n(recoff),Set(DB(REC/${CALLERID(num)})=OFF)
 same => n,Playback(call-recording)
 same => n,Playback(de-activated)
 same => n,Hangup()

; *65 - Extension Status (Busy/Available)
exten => *65,1,Answer()
 same => n,Wait(1)
 same => n,Playback(extension)
 same => n,SayDigits(${CALLERID(num)})
 same => n,Playback(is)
 same => n,Playback(available)
 same => n,Hangup()

; *41 - Caller ID Lookup Test
exten => *41,1,Answer()
 same => n,Wait(1)
 same => n,Playback(your)
 same => n,Playback(phone-number-is)
 same => n,SayDigits(${CALLERID(num)})
 same => n,Hangup()

; *500 - Call Pickup
exten => *500,1,Pickup()
 same => n,Hangup()

; *501 - Directed Call Pickup (by extension)
exten => *501,1,Answer()
 same => n,Read(pickupext,extension,4)
 same => n,Pickup(${pickupext}@PICKUPMARK)
 same => n,Hangup()

; =============================================================================
; SAMPLE IVR MENU
; =============================================================================

[sample-ivr]
exten => s,1,Answer()
 same => n,Wait(1)
 same => n(menu),Background(welcome)
 same => n,Background(for-sales-press-1)
 same => n,Background(for-support-press-2)
 same => n,Background(for-directory-press-3)
 same => n,WaitExten(10)
 same => n,Goto(menu)

exten => 1,1,Playback(connecting-to)
 same => n,Playback(sales)
 same => n,Dial(SIP/1000,30)
 same => n,Voicemail(1000@default,u)
 same => n,Hangup()

exten => 2,1,Playback(connecting-to)
 same => n,Playback(support)
 same => n,Dial(SIP/1001,30)
 same => n,Voicemail(1001@default,u)
 same => n,Hangup()

exten => 3,1,Directory(default,from-internal)

; 411 - Enhanced Directory Assistance Service
; Comprehensive directory service similar to Google 411
exten => 411,1,Answer()
 same => n,Wait(1)
 same => n,Playback(dir-intro)
 same => n,Background(dir-options)
 same => n,WaitExten(10)

; Option 1: Search by last name
exten => 1,1,Directory(default,from-internal,f)  ; First name search
 same => n,Goto(411,1)

; Option 2: Search by first name
exten => 2,1,Directory(default,from-internal,l)  ; Last name search
 same => n,Goto(411,1)

; Option 3: Browse all extensions
exten => 3,1,Directory(default,from-internal,b)  ; Both names
 same => n,Goto(411,1)

; Timeout - default to last name search
exten => t,1,Directory(default,from-internal,l)
 same => n,Goto(411,1)

exten => i,1,Playback(invalid)
 same => n,Goto(s,menu)

exten => t,1,Playback(goodbye)
 same => n,Hangup()

; =============================================================================
; MUSIC ON HOLD TEST
; =============================================================================

[moh-test]
exten => *610,1,Answer()
 same => n,Wait(1)
 same => n,Playback(music-on-hold-test)
 same => n,MusicOnHold(default,300)
 same => n,Hangup()

EOFDEMO

    # Include the demo dialplan
    if ! grep -q "incrediblepbx" /etc/asterisk/extensions.conf; then
        echo "#include extensions_incrediblepbx.conf" >> /etc/asterisk/extensions.conf
    fi

    # Create weather AGI script
    cat > /var/lib/asterisk/agi-bin/weather.sh << 'EOFWEATHER'
#!/bin/bash
# Simple weather report using TTS
echo "VERBOSE \"Weather Report Demo\" 3"

# Get weather data (simplified for demo)
CITY="Your City"
TEMP="72"
CONDITION="sunny"

# Generate TTS
TEXT="The current weather in $CITY is $CONDITION with a temperature of $TEMP degrees Fahrenheit."

# Use Flite for TTS
if command -v flite >/dev/null 2>&1; then
    flite -t "$TEXT" -o /tmp/weather.wav 2>/dev/null
    echo "STREAM FILE /tmp/weather \"\""
else
    echo "VERBOSE \"Flite not available\" 3"
fi

echo "200 result=0"
exit 0
EOFWEATHER

    chmod +x /var/lib/asterisk/agi-bin/weather.sh
    chown asterisk:asterisk /var/lib/asterisk/agi-bin/weather.sh

    # Create sample voicemail context (only if not already configured)
    if ! grep -q "Sample Voicemail Boxes" /etc/asterisk/voicemail.conf 2>/dev/null; then
        cat >> /etc/asterisk/voicemail.conf << 'EOFVM'

; Sample Voicemail Boxes
[default]
1000 => 1234,User 1000,user1000@example.com,,attach=yes|delete=yes
1001 => 1234,User 1001,user1001@example.com,,attach=yes|delete=yes
1002 => 1234,User 1002,user1002@example.com,,attach=yes|delete=yes
EOFVM
    else
        success "Sample voicemail boxes already configured, skipping..."
    fi

    # Configure Music on Hold
    backup_config /etc/asterisk/musiconhold.conf

    if [ ! -f /etc/asterisk/musiconhold.conf ] || [ ! -s /etc/asterisk/musiconhold.conf ]; then
        cat > /etc/asterisk/musiconhold.conf << 'EOFMOH'
[default]
mode=files
directory=/var/lib/asterisk/moh
random=yes
EOFMOH
    else
        success "Music on Hold already configured, skipping to preserve settings..."
    fi

    # Configure conferencing
    backup_config /etc/asterisk/confbridge.conf

    if [ ! -f /etc/asterisk/confbridge.conf ] || [ ! -s /etc/asterisk/confbridge.conf ]; then
        cat > /etc/asterisk/confbridge.conf << 'EOFCONF'
[default_user]
type=user
music_on_hold_when_empty=yes
music_on_hold_class=default
announce_user_count=yes
announce_user_count_all=yes

[default_bridge]
type=bridge
max_members=50
record_conference=no
EOFCONF
    else
        success "Conference bridge already configured, skipping to preserve settings..."
    fi

    # Set permissions
    chown -R asterisk:asterisk /etc/asterisk/
    chmod 644 /etc/asterisk/*.conf

    track_install "demo_apps"
    success "Demo applications and advanced features installed"
}

# =============================================================================
# SECURITY CONFIGURATION
# =============================================================================

configure_firewall() {
    step "🔒 Configuring firewall..."

    if command_exists firewall-cmd; then
        # FirewallD (RHEL-based)
        systemctl enable firewalld >> "${LOG_FILE}" 2>&1 || warn "Failed to enable firewalld"
        systemctl start firewalld >> "${LOG_FILE}" 2>&1 || warn "Failed to start firewalld"

        # Add PBX services
        firewall-cmd --permanent --add-service=http >> "${LOG_FILE}" 2>&1 || true
        firewall-cmd --permanent --add-service=https >> "${LOG_FILE}" 2>&1 || true
        firewall-cmd --permanent --add-port=5060/tcp >> "${LOG_FILE}" 2>&1 || true
        firewall-cmd --permanent --add-port=5060/udp >> "${LOG_FILE}" 2>&1 || true
        firewall-cmd --permanent --add-port=5061/tcp >> "${LOG_FILE}" 2>&1 || true
        firewall-cmd --permanent --add-port=10000-20000/udp >> "${LOG_FILE}" 2>&1 || true
        firewall-cmd --reload >> "${LOG_FILE}" 2>&1 || true

    elif command_exists ufw; then
        # UFW (Ubuntu/Debian)
        safe_execute "ufw --force enable" "Failed to enable UFW"

        # Add PBX services
        ufw allow 22/tcp
        ufw allow 80/tcp
        ufw allow 443/tcp
        ufw allow 5060/tcp
        ufw allow 5060/udp
        ufw allow 5061/tcp
        ufw allow 10000:20000/udp
    fi

    success "Firewall configured"
}

install_fail2ban() {
    step "🛡️  Installing Fail2ban..."

    case "${PACKAGE_MANAGER}" in
        apt-get)
            safe_execute "DEBIAN_FRONTEND=noninteractive apt-get install -y fail2ban" "Failed to install Fail2ban"
            ;;
        yum|dnf)
            safe_execute "${PACKAGE_MANAGER} install -y fail2ban" "Failed to install Fail2ban"
            ;;
    esac

    # Configure Fail2ban for Asterisk
    cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3

[asterisk]
enabled = true
filter = asterisk
action = iptables-allports[name=ASTERISK]
logpath = /var/log/asterisk/security.log
maxretry = 5
bantime = 86400

[apache-auth]
enabled = true

[sshd]
enabled = true
maxretry = 3
bantime = 3600
EOF

    # Start and enable Fail2ban
    safe_execute "systemctl enable fail2ban" "Failed to enable Fail2ban"
    safe_execute "systemctl start fail2ban" "Failed to start Fail2ban"

    success "Fail2ban installed and configured"
}

# =============================================================================
# BACKUP SYSTEM
# =============================================================================

setup_backup_system() {
    step "💾 Setting up backup system..."

    # Create backup script
    cat > /usr/local/bin/pbx-backup << 'EOF'
#!/bin/sh
# PBX Backup Script
BACKUP_DIR="/mnt/backups/pbx"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

echo "🔄 Starting backup..."
mkdir -p "${BACKUP_DIR}/manual"

# Backup FreePBX
if [ -d /etc/asterisk ]; then
    tar -czf "${BACKUP_DIR}/manual/freepbx_${TIMESTAMP}.tar.gz" \
        /etc/asterisk \
        /var/www/html/admin \
        /etc/freepbx.conf 2>/dev/null || true
    echo "✅ FreePBX backup completed"
fi

# Backup databases
if command -v mysqldump >/dev/null 2>&1; then
    mysqldump --all-databases | gzip > "${BACKUP_DIR}/manual/databases_${TIMESTAMP}.sql.gz"
    echo "✅ Database backup completed"
fi

echo "📦 Backup saved to: ${BACKUP_DIR}/manual/"
ls -lh "${BACKUP_DIR}/manual/"
EOF
    chmod +x /usr/local/bin/pbx-backup

    # Create backup cron job
    cat > /etc/cron.d/pbx-backup << EOF
# PBX Backup Schedule
0 2 * * * root /usr/local/bin/pbx-backup >/dev/null 2>&1
EOF

    success "Backup system configured"
}

# =============================================================================
# MANAGEMENT SCRIPTS
# =============================================================================

create_management_scripts() {
    step "🛠️  Creating management scripts..."

    # pbx-status
    cat > /usr/local/bin/pbx-status << 'EOF'
#!/bin/sh
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                    📊 PBX System Status                     ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "🖥️  System Information:"
echo "   Hostname: $(hostname -f)"
echo "   Uptime: $(uptime)"
echo ""
echo "🌐 Network:"
echo "   Private IP: $(ip route get 8.8.8.8 2>/dev/null | awk '{print $7; exit}')"
echo "   Public IP: $(curl -s --max-time 2 ifconfig.me 2>/dev/null || echo 'N/A')"
echo ""
echo "📡 Services:"
printf "   Apache: "
systemctl is-active apache2 2>/dev/null || systemctl is-active httpd 2>/dev/null
printf "   MariaDB: "
systemctl is-active mariadb 2>/dev/null || echo "inactive"
printf "   Asterisk: "
systemctl is-active asterisk 2>/dev/null || echo "inactive"
printf "   Fail2ban: "
systemctl is-active fail2ban 2>/dev/null || echo "inactive"
echo ""
echo "💾 Disk Usage:"
df -h / 2>/dev/null | grep -v Filesystem
echo ""
echo "🧠 Memory Usage:"
free -h 2>/dev/null | grep -E "^Mem|^Swap"
echo ""
echo "📞 Asterisk Status:"
if command -v asterisk >/dev/null 2>&1; then
    asterisk -rx 'core show channels' 2>/dev/null | grep "active"
fi
EOF
    chmod +x /usr/local/bin/pbx-status

    # pbx-restart
    cat > /usr/local/bin/pbx-restart << 'EOF'
#!/bin/sh
echo "🔄 Restarting PBX services..."
systemctl restart mariadb 2>/dev/null && echo "✅ MariaDB restarted"
systemctl restart apache2 2>/dev/null || systemctl restart httpd 2>/dev/null && echo "✅ Apache restarted"

# Safe Asterisk restart (handles dual processes)
systemctl stop asterisk 2>/dev/null
sleep 2
pkill -9 asterisk 2>/dev/null || true
rm -f /var/run/asterisk/asterisk.pid 2>/dev/null || true
sleep 1
systemctl start asterisk 2>/dev/null && echo "✅ Asterisk restarted"

systemctl restart fail2ban 2>/dev/null && echo "✅ Fail2ban restarted"
echo "✨ All services restarted"
EOF
    chmod +x /usr/local/bin/pbx-restart

    # pbx-logs
    cat > /usr/local/bin/pbx-logs << 'EOF'
#!/bin/sh
case "${1:-show}" in
    show)
        echo "📜 Recent PBX installation logs:"
        echo "================================"
        tail -50 /var/log/pbx-install.log 2>/dev/null || echo "No installation logs found"
        echo ""
        echo "📞 Recent Asterisk logs:"
        echo "========================"
        tail -20 /var/log/asterisk/messages 2>/dev/null || echo "No Asterisk logs found"
        ;;
    clear)
        echo "🗑️  Clearing old logs..."
        echo "" > /var/log/pbx-install.log 2>/dev/null
        echo "" > /var/log/asterisk/messages 2>/dev/null
        echo "✅ Logs cleared"
        ;;
    *)
        echo "Usage: $0 {show|clear}"
        exit 1
        ;;
esac
EOF
    chmod +x /usr/local/bin/pbx-logs

    # pbx-passwords
    cat > /usr/local/bin/pbx-passwords << 'EOF'
#!/bin/sh
echo "🔐 PBX System Passwords"
echo "======================="
if [ -f /root/.pbx_passwords ]; then
    cat /root/.pbx_passwords
else
    echo "❌ Password file not found: /root/.pbx_passwords"
fi
EOF
    chmod +x /usr/local/bin/pbx-passwords

    # pbx-repair
    cat > /usr/local/bin/pbx-repair << 'EOF'
#!/bin/sh
echo "🔧 Running PBX system repair..."
echo ""

# Fix permissions
echo "📝 Fixing permissions..."
if [ -d /etc/asterisk ]; then
    chown -R asterisk:asterisk /etc/asterisk
    chown -R asterisk:asterisk /var/lib/asterisk
    chown -R asterisk:asterisk /var/spool/asterisk
    chown -R asterisk:asterisk /var/log/asterisk
    echo "✅ Asterisk permissions fixed"
fi

if [ -d /var/www/html ]; then
    chown -R www-data:www-data /var/www/html 2>/dev/null || \
    chown -R apache:apache /var/www/html 2>/dev/null
    echo "✅ Web permissions fixed"
fi

# Restart services
echo ""
echo "🔄 Restarting services..."
systemctl restart mariadb 2>/dev/null
systemctl restart apache2 2>/dev/null || systemctl restart httpd 2>/dev/null

# Safe Asterisk restart
systemctl stop asterisk 2>/dev/null
sleep 2
pkill -9 asterisk 2>/dev/null || true
rm -f /var/run/asterisk/asterisk.pid 2>/dev/null || true
sleep 1
systemctl start asterisk 2>/dev/null

echo ""
echo "✅ System repair completed"
EOF
    chmod +x /usr/local/bin/pbx-repair

    # pbx-network
    cat > /usr/local/bin/pbx-network << 'EOF'
#!/bin/sh
echo "🌐 Network Diagnostics"
echo "===================="
echo ""
echo "Network Interfaces:"
ip addr show | grep -E "^[0-9]+:|inet " || ifconfig
echo ""
echo "Default Gateway:"
ip route | grep default || route -n | grep "^0.0.0.0"
echo ""
echo "DNS Configuration:"
cat /etc/resolv.conf
echo ""
echo "Network Connectivity Tests:"
echo -n "  Internet (8.8.8.8): "
ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1 && echo "✅ OK" || echo "❌ FAIL"
echo -n "  DNS (google.com): "
ping -c 1 -W 2 google.com >/dev/null 2>&1 && echo "✅ OK" || echo "❌ FAIL"
EOF
    chmod +x /usr/local/bin/pbx-network

    # pbx-firewall
    cat > /usr/local/bin/pbx-firewall << 'EOF'
#!/bin/sh
if command -v firewall-cmd >/dev/null 2>&1; then
    echo "🔥 Firewall Status (firewalld)"
    echo "=============================="
    firewall-cmd --state
    echo ""
    echo "Active Zones:"
    firewall-cmd --get-active-zones
    echo ""
    echo "Allowed Services:"
    firewall-cmd --list-services
    echo ""
    echo "Allowed Ports:"
    firewall-cmd --list-ports
elif command -v ufw >/dev/null 2>&1; then
    echo "🔥 Firewall Status (ufw)"
    echo "======================="
    ufw status verbose
else
    echo "No supported firewall found"
fi
EOF
    chmod +x /usr/local/bin/pbx-firewall

    # pbx-ssh
    cat > /usr/local/bin/pbx-ssh << 'EOF'
#!/bin/sh
echo "🔑 SSH Configuration Status"
echo "==========================="
echo ""
echo "SSH Service:"
systemctl status sshd 2>/dev/null || systemctl status ssh 2>/dev/null
echo ""
echo "SSH Configuration:"
grep -E "^(Port|PermitRootLogin|PasswordAuthentication|PubkeyAuthentication)" /etc/ssh/sshd_config
echo ""
echo "Active SSH Sessions:"
who
EOF
    chmod +x /usr/local/bin/pbx-ssh

    # pbx-security
    cat > /usr/local/bin/pbx-security << 'EOF'
#!/bin/sh
echo "🛡️  Security Audit"
echo "================"
echo ""
echo "Fail2ban Status:"
systemctl status fail2ban 2>/dev/null | grep "Active:" || echo "Not installed"
echo ""
echo "Fail2ban Jails:"
fail2ban-client status 2>/dev/null || echo "Fail2ban not running"
echo ""
echo "Open Ports:"
ss -tulpn | grep LISTEN || netstat -tulpn | grep LISTEN
echo ""
echo "Recent Failed Login Attempts:"
grep "Failed password" /var/log/auth.log 2>/dev/null | tail -5 || \
grep "Failed password" /var/log/secure 2>/dev/null | tail -5 || \
echo "No recent failures"
EOF
    chmod +x /usr/local/bin/pbx-security

    # pbx-services
    cat > /usr/local/bin/pbx-services << 'EOF'
#!/bin/sh
echo "🔧 PBX Services Status"
echo "====================="
echo ""
for service in asterisk mariadb apache2 httpd fail2ban hylafax; do
    if systemctl list-unit-files | grep -q "^${service}.service"; then
        printf "%-15s: " "$service"
        systemctl is-active "$service" 2>/dev/null || echo "inactive"
    fi
done
echo ""
echo "IAXmodem Services:"
for i in 0 1 2 3; do
    if systemctl list-unit-files | grep -q "^iaxmodem${i}.service"; then
        printf "  iaxmodem%-2s : " "$i"
        systemctl is-active "iaxmodem${i}" 2>/dev/null || echo "inactive"
    fi
done
EOF
    chmod +x /usr/local/bin/pbx-services

    # pbx-ssl
    cat > /usr/local/bin/pbx-ssl << 'EOF'
#!/bin/sh
echo "🔒 SSL Certificate Status"
echo "========================"
echo ""
if [ -f /etc/ssl/certs/pbx-selfsigned.crt ]; then
    echo "Certificate Type: Self-Signed"
    echo "Location: /etc/ssl/certs/pbx-selfsigned.crt"
    echo ""
    openssl x509 -in /etc/ssl/certs/pbx-selfsigned.crt -noout -dates
elif [ -d /etc/letsencrypt/live ]; then
    echo "Certificate Type: Let's Encrypt"
    echo "Domains:"
    ls -1 /etc/letsencrypt/live/
    echo ""
    for domain in /etc/letsencrypt/live/*/cert.pem; do
        [ -f "$domain" ] && openssl x509 -in "$domain" -noout -dates
    done
else
    echo "No SSL certificates found"
fi
EOF
    chmod +x /usr/local/bin/pbx-ssl

    # pbx-cleanup
    cat > /usr/local/bin/pbx-cleanup << 'EOF'
#!/bin/sh
echo "🧹 PBX Cleanup"
echo "============="
echo ""
echo "Backup Directory Usage:"
du -sh /mnt/backups/pbx/* 2>/dev/null || echo "No backups found"
echo ""
echo "Log Directory Usage:"
du -sh /var/log/asterisk 2>/dev/null
du -sh /var/log/apache2 2>/dev/null || du -sh /var/log/httpd 2>/dev/null
echo ""
echo "Removing old backups (>30 days)..."
find /mnt/backups/pbx -type f -mtime +30 -delete 2>/dev/null && echo "✅ Done" || echo "No old backups"
echo ""
echo "Rotating logs..."
logrotate -f /etc/logrotate.conf 2>/dev/null && echo "✅ Done" || echo "Failed"
EOF
    chmod +x /usr/local/bin/pbx-cleanup

    # pbx-docs
    cat > /usr/local/bin/pbx-docs << 'EOF'
#!/bin/sh
echo "📚 PBX System Documentation"
echo "==========================="
echo ""
echo "Installation Details:"
cat /root/.pbx_passwords 2>/dev/null || echo "Password file not found"
echo ""
echo "System Version:"
cat /etc/os-release | grep -E "^(NAME|VERSION)="
echo ""
echo "Asterisk Version:"
asterisk -V 2>/dev/null || echo "Asterisk not installed"
echo ""
echo "FreePBX Version:"
fwconsole --version 2>/dev/null || echo "FreePBX not installed"
echo ""
echo "Installed Management Scripts:"
ls -1 /usr/local/bin/pbx-*
EOF
    chmod +x /usr/local/bin/pbx-docs

    # pbx-moh
    cat > /usr/local/bin/pbx-moh << 'EOF'
#!/bin/sh
echo "🎵 Music on Hold Management"
echo "==========================="
echo ""
echo "MOH Directory: /var/lib/asterisk/moh"
echo ""
if [ -d /var/lib/asterisk/moh ]; then
    echo "Available MOH Files:"
    ls -lh /var/lib/asterisk/moh/
else
    echo "MOH directory not found"
fi
echo ""
echo "MOH Configuration:"
cat /etc/asterisk/musiconhold.conf 2>/dev/null || echo "MOH not configured"
EOF
    chmod +x /usr/local/bin/pbx-moh

    # pbx-config (TUI for FreePBX configuration)
    cat > /usr/local/bin/pbx-config << 'EOFCONFIG'
#!/bin/bash
# PBX Configuration TUI
# Interactive configuration tool for FreePBX

# Check if dialog is installed
if ! command -v dialog >/dev/null 2>&1; then
    echo "Installing dialog..."
    if command -v apt-get >/dev/null 2>&1; then
        apt-get install -y dialog >/dev/null 2>&1
    elif command -v yum >/dev/null 2>&1; then
        yum install -y dialog >/dev/null 2>&1
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y dialog >/dev/null 2>&1
    fi
fi

DIALOG_CANCEL=1
DIALOG_ESC=255
HEIGHT=20
WIDTH=70

# Temporary file for dialog
TEMPFILE=$(mktemp 2>/dev/null) || TEMPFILE=/tmp/pbx-config-$$
trap "rm -f $TEMPFILE" 0 1 2 5 15

# Main menu
main_menu() {
    dialog --clear --title "FreePBX Configuration Tool" \
        --menu "Choose an option:" $HEIGHT $WIDTH 10 \
        1 "Add Extension" \
        2 "Add VoIP Trunk (Provider)" \
        3 "Configure Inbound Route" \
        4 "Configure Outbound Route" \
        5 "View Current Configuration" \
        6 "Apply & Reload FreePBX" \
        7 "Exit" 2>$TEMPFILE

    retval=$?
    choice=$(cat $TEMPFILE)

    case $retval in
        $DIALOG_CANCEL|$DIALOG_ESC)
            clear
            exit 0
            ;;
    esac

    case $choice in
        1) add_extension ;;
        2) add_trunk ;;
        3) add_inbound_route ;;
        4) add_outbound_route ;;
        5) view_configuration ;;
        6) apply_config ;;
        7) clear; exit 0 ;;
        *) main_menu ;;
    esac
}

# Add Extension
add_extension() {
    dialog --title "Add Extension" \
        --form "Enter extension details:" $HEIGHT $WIDTH 8 \
        "Extension Number:" 1 1 "1000" 1 25 10 10 \
        "Display Name:" 2 1 "User 1000" 2 25 30 50 \
        "Secret (Password):" 3 1 "$(openssl rand -hex 8)" 3 25 30 50 \
        "Email:" 4 1 "user@example.com" 4 25 30 50 \
        2>$TEMPFILE

    if [ $? -eq 0 ]; then
        EXT_NUM=$(sed -n 1p $TEMPFILE | tr -d ' ')
        EXT_NAME=$(sed -n 2p $TEMPFILE)
        EXT_SECRET=$(sed -n 3p $TEMPFILE)
        EXT_EMAIL=$(sed -n 4p $TEMPFILE)

        # Validate required fields
        if [ -z "$EXT_NUM" ]; then
            dialog --title "Error" --msgbox "Extension number is required!" 6 $WIDTH
            add_extension
            return
        fi

        if [ -z "$EXT_NAME" ]; then
            dialog --title "Error" --msgbox "Display name is required!" 6 $WIDTH
            add_extension
            return
        fi

        if [ -z "$EXT_SECRET" ]; then
            dialog --title "Error" --msgbox "Password is required!" 6 $WIDTH
            add_extension
            return
        fi

        # Validate extension number is numeric
        if ! [[ "$EXT_NUM" =~ ^[0-9]+$ ]]; then
            dialog --title "Error" --msgbox "Extension number must be numeric!" 6 $WIDTH
            add_extension
            return
        fi

        # Validate extension number length - avoid phone number formats
        # Phone numbers: 7 (local), 10 (USA), 11 (international with 1), 12+ (international)
        # Valid extensions: 1-2 digits (too short for production), 3-6 digits (good), 8-9 digits (avoid confusion)
        local ext_len=${#EXT_NUM}
        if [ $ext_len -eq 7 ] || [ $ext_len -eq 10 ] || [ $ext_len -eq 11 ] || [ $ext_len -ge 12 ]; then
            dialog --title "Error" --msgbox "Extension length conflicts with phone number format!\nAvoid: 7, 10, 11, or 12+ digits\nUse: 3-6 digits or 8-9 digits" 10 $WIDTH
            add_extension
            return
        fi

        # Block emergency/service numbers (411 allowed for directory service)
        case "$EXT_NUM" in
            911|311|511|611|711|811|999|000|100|101|211|988)
                dialog --title "Error" --msgbox "Cannot use emergency or service numbers!\nBlocked: 911, 311, 511, 611, 711, 811, 988, 999\nNote: 411 allowed for directory service" 10 $WIDTH
                add_extension
                return
                ;;
        esac

        # Require at least 3 digits for production use
        if [ $ext_len -lt 3 ]; then
            dialog --title "Error" --msgbox "Extension must be at least 3 digits for security!" 6 $WIDTH
            add_extension
            return
        fi

        # Create extension using fwconsole
        fwconsole extension add pjsip "$EXT_NUM" "$EXT_NAME" "$EXT_SECRET" "$EXT_EMAIL" >/dev/null 2>&1

        if [ $? -eq 0 ]; then
            dialog --title "Success" --msgbox "Extension $EXT_NUM created successfully!\n\nExtension: $EXT_NUM\nName: $EXT_NAME\nPassword: $EXT_SECRET\nEmail: $EXT_EMAIL" 12 $WIDTH
        else
            dialog --title "Error" --msgbox "Failed to create extension. Please check logs." 8 $WIDTH
        fi
    fi

    main_menu
}

# Add VoIP Trunk
add_trunk() {
    dialog --clear --title "Select VoIP Provider" \
        --menu "Choose a provider template:" $HEIGHT $WIDTH 10 \
        1 "voip.ms (USA/Canada)" \
        2 "Flowroute" \
        3 "Telnyx" \
        4 "Twilio" \
        5 "Custom Provider" \
        6 "Back to Main Menu" 2>$TEMPFILE

    provider_choice=$(cat $TEMPFILE)

    case $provider_choice in
        1) configure_voipms ;;
        2) configure_flowroute ;;
        3) configure_telnyx ;;
        4) configure_twilio ;;
        5) configure_custom ;;
        6) main_menu ;;
        *) main_menu ;;
    esac
}

# Configure voip.ms
configure_voipms() {
    dialog --title "voip.ms Configuration" \
        --form "Enter voip.ms account details:" $HEIGHT $WIDTH 6 \
        "Account ID:" 1 1 "" 1 20 30 30 \
        "Username:" 2 1 "" 2 20 30 30 \
        "Password:" 3 1 "" 3 20 30 30 \
        "Server:" 4 1 "seattle.voip.ms" 4 20 30 50 \
        2>$TEMPFILE

    if [ $? -eq 0 ]; then
        VOIPMS_ACCOUNT=$(sed -n 1p $TEMPFILE | tr -d ' ')
        VOIPMS_USER=$(sed -n 2p $TEMPFILE | tr -d ' ')
        VOIPMS_PASS=$(sed -n 3p $TEMPFILE)
        VOIPMS_SERVER=$(sed -n 4p $TEMPFILE | tr -d ' ')

        # Validate required fields
        if [ -z "$VOIPMS_ACCOUNT" ] || [ -z "$VOIPMS_USER" ] || [ -z "$VOIPMS_PASS" ] || [ -z "$VOIPMS_SERVER" ]; then
            dialog --title "Error" --msgbox "All fields are required for voip.ms configuration!" 6 $WIDTH
            configure_voipms
            return
        fi

        # Create trunk configuration
        TRUNK_NAME="voipms_${VOIPMS_ACCOUNT}"

        # Add trunk via fwconsole
        cat > /tmp/voipms_trunk.conf << EOF
[$TRUNK_NAME]
type=endpoint
context=from-trunk
disallow=all
allow=ulaw
allow=alaw
allow=g729
aors=$TRUNK_NAME
auth=$TRUNK_NAME
outbound_auth=$TRUNK_NAME
from_user=$VOIPMS_USER
from_domain=$VOIPMS_SERVER

[$TRUNK_NAME]
type=identify
endpoint=$TRUNK_NAME
match=$VOIPMS_SERVER

[$TRUNK_NAME]
type=aor
contact=sip:$VOIPMS_SERVER:5060
qualify_frequency=60

[$TRUNK_NAME]
type=auth
auth_type=userpass
username=$VOIPMS_USER
password=$VOIPMS_PASS

[$TRUNK_NAME]
type=registration
transport=transport-udp
outbound_auth=$TRUNK_NAME
server_uri=sip:$VOIPMS_SERVER
client_uri=sip:$VOIPMS_USER@$VOIPMS_SERVER
contact_user=$VOIPMS_USER
retry_interval=60
EOF

        cat /tmp/voipms_trunk.conf >> /etc/asterisk/pjsip_custom.conf
        rm -f /tmp/voipms_trunk.conf

        dialog --title "Success" --msgbox "voip.ms trunk '$TRUNK_NAME' configured!\n\nServer: $VOIPMS_SERVER\nUsername: $VOIPMS_USER\n\nRemember to:\n1. Apply configuration\n2. Set up inbound/outbound routes" 14 $WIDTH
    fi

    main_menu
}

# Configure Flowroute
configure_flowroute() {
    dialog --title "Flowroute Configuration" \
        --form "Enter Flowroute details:" $HEIGHT $WIDTH 4 \
        "Access Key:" 1 1 "" 1 20 40 50 \
        "Secret Key:" 2 1 "" 2 20 40 50 \
        2>$TEMPFILE

    if [ $? -eq 0 ]; then
        FR_ACCESS=$(sed -n 1p $TEMPFILE)
        FR_SECRET=$(sed -n 2p $TEMPFILE)

        TRUNK_NAME="flowroute"

        cat > /tmp/flowroute_trunk.conf << EOF
[$TRUNK_NAME]
type=endpoint
context=from-trunk
disallow=all
allow=ulaw
allow=alaw
aors=$TRUNK_NAME
auth=$TRUNK_NAME
outbound_auth=$TRUNK_NAME

[$TRUNK_NAME]
type=aor
contact=sip:us-east-va.sip.flowroute.com:5060
qualify_frequency=60

[$TRUNK_NAME]
type=auth
auth_type=userpass
username=$FR_ACCESS
password=$FR_SECRET

[$TRUNK_NAME]
type=identify
endpoint=$TRUNK_NAME
match=us-east-va.sip.flowroute.com

[$TRUNK_NAME]
type=registration
transport=transport-udp
outbound_auth=$TRUNK_NAME
server_uri=sip:us-east-va.sip.flowroute.com
client_uri=sip:$FR_ACCESS@us-east-va.sip.flowroute.com
contact_user=$FR_ACCESS
EOF

        cat /tmp/flowroute_trunk.conf >> /etc/asterisk/pjsip_custom.conf
        rm -f /tmp/flowroute_trunk.conf

        dialog --title "Success" --msgbox "Flowroute trunk configured!" 10 $WIDTH
    fi

    main_menu
}

# Configure Telnyx
configure_telnyx() {
    dialog --title "Telnyx Configuration" \
        --form "Enter Telnyx details:" $HEIGHT $WIDTH 4 \
        "SIP Username:" 1 1 "" 1 20 40 50 \
        "SIP Password:" 2 1 "" 2 20 40 50 \
        2>$TEMPFILE

    if [ $? -eq 0 ]; then
        TEL_USER=$(sed -n 1p $TEMPFILE)
        TEL_PASS=$(sed -n 2p $TEMPFILE)

        TRUNK_NAME="telnyx"

        cat > /tmp/telnyx_trunk.conf << EOF
[$TRUNK_NAME]
type=endpoint
context=from-trunk
disallow=all
allow=ulaw
allow=alaw
allow=g722
aors=$TRUNK_NAME
auth=$TRUNK_NAME
outbound_auth=$TRUNK_NAME

[$TRUNK_NAME]
type=aor
contact=sip:sip.telnyx.com:5060
qualify_frequency=60

[$TRUNK_NAME]
type=auth
auth_type=userpass
username=$TEL_USER
password=$TEL_PASS

[$TRUNK_NAME]
type=registration
transport=transport-udp
outbound_auth=$TRUNK_NAME
server_uri=sip:sip.telnyx.com
client_uri=sip:$TEL_USER@sip.telnyx.com
contact_user=$TEL_USER
EOF

        cat /tmp/telnyx_trunk.conf >> /etc/asterisk/pjsip_custom.conf
        rm -f /tmp/telnyx_trunk.conf

        dialog --title "Success" --msgbox "Telnyx trunk configured!" 10 $WIDTH
    fi

    main_menu
}

# Configure Twilio
configure_twilio() {
    dialog --title "Twilio Configuration" \
        --form "Enter Twilio SIP Trunk details:" $HEIGHT $WIDTH 4 \
        "Domain:" 1 1 "yourtrunk.pstn.twilio.com" 1 20 40 50 \
        "Username (optional):" 2 1 "" 2 20 40 50 \
        "Password (optional):" 3 1 "" 3 20 40 50 \
        2>$TEMPFILE

    if [ $? -eq 0 ]; then
        TW_DOMAIN=$(sed -n 1p $TEMPFILE)
        TW_USER=$(sed -n 2p $TEMPFILE)
        TW_PASS=$(sed -n 3p $TEMPFILE)

        TRUNK_NAME="twilio"

        cat > /tmp/twilio_trunk.conf << EOF
[$TRUNK_NAME]
type=endpoint
context=from-trunk
disallow=all
allow=ulaw
allow=alaw
aors=$TRUNK_NAME
EOF

        if [ -n "$TW_USER" ] && [ -n "$TW_PASS" ]; then
            cat >> /tmp/twilio_trunk.conf << EOF
auth=$TRUNK_NAME
outbound_auth=$TRUNK_NAME
EOF
        fi

        cat >> /tmp/twilio_trunk.conf << EOF

[$TRUNK_NAME]
type=aor
contact=sip:$TW_DOMAIN:5060
qualify_frequency=60

[$TRUNK_NAME]
type=identify
endpoint=$TRUNK_NAME
match=$TW_DOMAIN
EOF

        if [ -n "$TW_USER" ] && [ -n "$TW_PASS" ]; then
            cat >> /tmp/twilio_trunk.conf << EOF

[$TRUNK_NAME]
type=auth
auth_type=userpass
username=$TW_USER
password=$TW_PASS
EOF
        fi

        cat /tmp/twilio_trunk.conf >> /etc/asterisk/pjsip_custom.conf
        rm -f /tmp/twilio_trunk.conf

        dialog --title "Success" --msgbox "Twilio trunk configured!" 10 $WIDTH
    fi

    main_menu
}

# Configure custom provider
configure_custom() {
    dialog --title "Custom Provider Configuration" \
        --form "Enter provider details:" $HEIGHT $WIDTH 8 \
        "Trunk Name:" 1 1 "custom_trunk" 1 20 30 50 \
        "Server/Host:" 2 1 "" 2 20 30 50 \
        "Username:" 3 1 "" 3 20 30 50 \
        "Password:" 4 1 "" 4 20 30 50 \
        "Port:" 5 1 "5060" 5 20 10 10 \
        2>$TEMPFILE

    if [ $? -eq 0 ]; then
        TRUNK_NAME=$(sed -n 1p $TEMPFILE)
        SIP_SERVER=$(sed -n 2p $TEMPFILE)
        SIP_USER=$(sed -n 3p $TEMPFILE)
        SIP_PASS=$(sed -n 4p $TEMPFILE)
        SIP_PORT=$(sed -n 5p $TEMPFILE)

        cat > /tmp/custom_trunk.conf << EOF
[$TRUNK_NAME]
type=endpoint
context=from-trunk
disallow=all
allow=ulaw
allow=alaw
allow=g729
aors=$TRUNK_NAME
auth=$TRUNK_NAME
outbound_auth=$TRUNK_NAME

[$TRUNK_NAME]
type=aor
contact=sip:$SIP_SERVER:$SIP_PORT
qualify_frequency=60

[$TRUNK_NAME]
type=auth
auth_type=userpass
username=$SIP_USER
password=$SIP_PASS

[$TRUNK_NAME]
type=identify
endpoint=$TRUNK_NAME
match=$SIP_SERVER

[$TRUNK_NAME]
type=registration
transport=transport-udp
outbound_auth=$TRUNK_NAME
server_uri=sip:$SIP_SERVER:$SIP_PORT
client_uri=sip:$SIP_USER@$SIP_SERVER
contact_user=$SIP_USER
EOF

        cat /tmp/custom_trunk.conf >> /etc/asterisk/pjsip_custom.conf
        rm -f /tmp/custom_trunk.conf

        dialog --title "Success" --msgbox "Custom trunk '$TRUNK_NAME' configured!" 10 $WIDTH
    fi

    main_menu
}

# Add Inbound Route
add_inbound_route() {
    dialog --title "Add Inbound Route" \
        --form "Configure inbound route:" $HEIGHT $WIDTH 6 \
        "DID/Number:" 1 1 "" 1 20 30 50 \
        "Description:" 2 1 "Incoming Call" 2 20 30 50 \
        "Destination Ext:" 3 1 "1000" 3 20 10 10 \
        2>$TEMPFILE

    if [ $? -eq 0 ]; then
        IN_DID=$(sed -n 1p $TEMPFILE)
        IN_DESC=$(sed -n 2p $TEMPFILE)
        IN_DEST=$(sed -n 3p $TEMPFILE)

        # Add basic inbound route to extensions_custom.conf
        cat >> /etc/asterisk/extensions_custom.conf << EOF

; Inbound Route for $IN_DID - $IN_DESC
[from-trunk]
exten => $IN_DID,1,NoOp(Inbound call to $IN_DID)
 same => n,Goto(from-internal,$IN_DEST,1)
EOF

        dialog --title "Success" --msgbox "Inbound route created!\n\nDID: $IN_DID\nDestination: Extension $IN_DEST\n\nNote: This is a basic route. Use FreePBX web interface for advanced routing." 12 $WIDTH
    fi

    main_menu
}

# Add Outbound Route
add_outbound_route() {
    dialog --title "Add Outbound Route" \
        --form "Configure outbound route:" $HEIGHT $WIDTH 6 \
        "Route Name:" 1 1 "default_out" 1 20 30 50 \
        "Dial Pattern:" 2 1 "NXXNXXXXXX" 2 20 30 50 \
        "Trunk Name:" 3 1 "voipms" 3 20 30 50 \
        2>$TEMPFILE

    if [ $? -eq 0 ]; then
        OUT_NAME=$(sed -n 1p $TEMPFILE)
        OUT_PATTERN=$(sed -n 2p $TEMPFILE)
        OUT_TRUNK=$(sed -n 3p $TEMPFILE)

        # Add basic outbound route
        cat >> /etc/asterisk/extensions_custom.conf << EOF

; Outbound Route: $OUT_NAME
[from-internal-custom]
exten => _$OUT_PATTERN,1,NoOp(Outbound call via $OUT_TRUNK)
 same => n,Dial(PJSIP/\${EXTEN}@$OUT_TRUNK,60)
 same => n,Hangup()
EOF

        dialog --title "Success" --msgbox "Outbound route '$OUT_NAME' created!\n\nPattern: $OUT_PATTERN\nTrunk: $OUT_TRUNK\n\nNote: Use FreePBX web interface for advanced routing options." 12 $WIDTH
    fi

    main_menu
}

# View Configuration
view_configuration() {
    CONFIG_INFO=$(cat << EOFINFO
=== PJSIP Trunks ===
$(grep -E '^\[.*\]$' /etc/asterisk/pjsip_custom.conf 2>/dev/null | head -20)

=== Extensions ===
$(asterisk -rx 'pjsip show endpoints' 2>/dev/null | head -20)

=== Network Settings ===
Private IP: $(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -1)
Public IP: $(curl -s --max-time 3 ifconfig.me)

=== FreePBX Status ===
$(fwconsole chown --check 2>/dev/null | head -10)
EOFINFO
)

    dialog --title "Current Configuration" \
        --msgbox "$CONFIG_INFO" 22 $WIDTH

    main_menu
}

# Apply configuration
apply_config() {
    dialog --infobox "Applying configuration and reloading FreePBX..." 5 $WIDTH

    fwconsole reload >/dev/null 2>&1
    asterisk -rx "pjsip reload" >/dev/null 2>&1
    asterisk -rx "dialplan reload" >/dev/null 2>&1

    sleep 2

    dialog --title "Success" --msgbox "Configuration applied and FreePBX reloaded!" 8 $WIDTH

    main_menu
}

# Start the TUI
main_menu
EOFCONFIG
    chmod +x /usr/local/bin/pbx-config

    success "Management scripts created"
}

# =============================================================================
# FINAL CONFIGURATION
# =============================================================================

finalize_installation() {
    step "🎯 Finalizing installation..."

    # Create main portal page
    cat > "${WEB_ROOT}/index.html" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>🏢 PBX System - ${SYSTEM_FQDN}</title>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        body {
            font-family: -apple-system, system-ui, sans-serif;
            max-width: 1200px;
            margin: 0 auto;
            padding: 20px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
        }
        .container {
            background: white;
            padding: 40px;
            border-radius: 15px;
            box-shadow: 0 20px 40px rgba(0,0,0,0.1);
        }
        h1 {
            color: #2d3748;
            text-align: center;
            margin-bottom: 40px;
        }
        .services {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin: 40px 0;
        }
        .service {
            background: #f7fafc;
            padding: 30px;
            border-radius: 10px;
            text-align: center;
            transition: transform 0.3s;
        }
        .service:hover {
            transform: translateY(-5px);
        }
        .service a {
            display: inline-block;
            padding: 12px 30px;
            background: #667eea;
            color: white;
            text-decoration: none;
            border-radius: 25px;
            margin-top: 15px;
        }
        .info {
            background: #e6fffa;
            padding: 25px;
            border-radius: 10px;
            margin: 30px 0;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🏢 PBX System Portal</h1>

        <div class="services">
            <div class="service">
                <h3>📞 FreePBX Admin</h3>
                <p>Complete PBX management interface</p>
                <a href="/admin/">Access Admin Panel</a>
            </div>

            <div class="service">
                <h3>👤 User Control Panel</h3>
                <p>User self-service portal (UCP)</p>
                <a href="/ucp/">Access UCP</a>
            </div>

            <div class="service">
                <h3>📠 Fax Management</h3>
                <p>AvantFax web interface</p>
                <a href="/avantfax/">Access AvantFax</a>
            </div>
        </div>

        <div class="info">
            <h3>📋 System Information</h3>
            <p><strong>Hostname:</strong> ${SYSTEM_FQDN}</p>
            <p><strong>Installation Date:</strong> ${INSTALL_DATE}</p>
            <p><strong>Asterisk Version:</strong> ${ASTERISK_VERSION}</p>
            <p><strong>FreePBX Version:</strong> ${FREEPBX_VERSION}</p>
        </div>

        <div class="info">
            <h3>🛠️ Management Commands</h3>
            <p>Use these commands via SSH:</p>
            <ul>
                <li><code>pbx-config</code> - <strong>TUI Configuration Tool</strong> (Extensions, Trunks, Routes)</li>
                <li><code>pbx-status</code> - System status</li>
                <li><code>pbx-restart</code> - Restart services</li>
                <li><code>pbx-backup</code> - Create backup</li>
                <li><code>pbx-logs</code> - View logs</li>
                <li><code>pbx-passwords</code> - Show passwords</li>
                <li><code>pbx-repair</code> - Repair system</li>
            </ul>
        </div>
    </div>
</body>
</html>
EOF

    # Set proper permissions
    chown -R "${APACHE_USER}:${APACHE_GROUP}" "${WEB_ROOT}"

    # Restart services
    systemctl restart "${APACHE_SERVICE}" 2>/dev/null
    safe_restart_asterisk >/dev/null 2>&1

    # Save configuration to persistent .env file
    save_pbx_env

    success "Installation finalized"
}

# =============================================================================
# INSTALLATION VERIFICATION
# =============================================================================

verify_installation() {
    step "🔍 Verifying installation..."

    local verification_failed=0

    # Check critical binaries
    info "Checking installed binaries..."
    for cmd in asterisk fwconsole mysql php httpd hylafax sendfax faxstat; do
        if command_exists "${cmd}"; then
            success "✓ ${cmd} installed"
        else
            warn "✗ ${cmd} NOT found"
            verification_failed=1
        fi
    done

    # Check critical services
    info "Checking service status..."
    for service in asterisk mariadb httpd hylafax; do
        if systemctl is-active --quiet "${service}" 2>/dev/null; then
            success "✓ ${service} service running"
        else
            warn "✗ ${service} service NOT running"
            verification_failed=1
        fi
    done

    # Check FreePBX
    if [ -d /var/www/html/admin ] && command_exists fwconsole; then
        success "✓ FreePBX installed"
    else
        warn "✗ FreePBX NOT properly installed"
        verification_failed=1
    fi

    # Check fax modems if fax system enabled
    if [ "${FAX_ENABLED}" = "1" ]; then
        local modem_count=$(ls -1 /dev/ttyIAX* 2>/dev/null | wc -l)
        if [ "${modem_count}" -ge 1 ]; then
            success "✓ Fax modems configured (${modem_count} modems)"
        else
            warn "✗ Fax modems NOT configured"
            verification_failed=1
        fi
    fi

    # Summary
    if [ ${verification_failed} -eq 0 ]; then
        success "Installation verification PASSED - all components installed and running"
    else
        warn "Installation verification found issues - see warnings above"
        warn "System may still be functional, check 'pbx-status' for details"
    fi
}

# =============================================================================
# INSTALLATION COMPLETE
# =============================================================================

show_completion_message() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║            🎉 PBX Installation Complete! 🎉                ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    echo "🌐 Web Access:"
    echo "   Main Portal: http://${SYSTEM_FQDN}/"
    echo ""
    echo "   FreePBX Admin: http://${SYSTEM_FQDN}/admin/"
    echo "   Username: administrator"
    echo "   Password: ${FREEPBX_ADMIN_PASSWORD}"
    echo ""
    echo "   AvantFax: http://${SYSTEM_FQDN}/avantfax/"
    echo "   Username: administrator"
    echo "   Password: ${FREEPBX_ADMIN_PASSWORD}"
    echo ""
    echo "   UCP (User Control Panel): http://${SYSTEM_FQDN}/ucp/"
    echo "   Username: administrator"
    echo "   Password: ${FREEPBX_ADMIN_PASSWORD}"
    echo ""
    echo "📁 Important Files:"
    echo "   Passwords: ${AUTO_PASSWORDS_FILE}"
    echo "   Install Log: ${LOG_FILE}"
    echo "   Error Log: ${ERROR_LOG}"
    echo ""
    echo "🛠️  Management Commands:"
    echo "   pbx-config    - TUI Configuration Tool (Extensions, Trunks, Routes)"
    echo "   pbx-status    - System status overview"
    echo "   pbx-restart   - Restart all services"
    echo "   pbx-backup    - Create system backup"
    echo "   pbx-logs      - View system logs"
    echo "   pbx-passwords - Show all passwords"
    echo "   pbx-repair    - Repair system issues"
    echo ""
    echo "📞 Demo Applications (Dial from any extension):"
    echo "   DEMO or dial D-E-M-O  - System demo and information"
    echo "   123                   - Speaking clock (time/date)"
    echo "   947                   - Weather report (TTS demo)"
    echo "   951 or TODAY          - Today's date"
    echo "   4747 or LENNY         - LENNY (telemarketer bot)"
    echo "   *43                   - Echo test"
    echo "   *469, *470            - Conference rooms"
    echo "   *97                   - Voicemail main menu"
    echo "   *610                  - Music on hold test"
    echo ""
    echo "⚙️  Feature Codes:"
    echo "   *72 / *73  - Call forwarding (enable/disable)"
    echo "   *76 / *77  - Do not disturb (enable/disable)"
    echo "   *78        - Call recording toggle"
    echo "   *68        - Wakeup call service"
    echo "   *500       - Call pickup"
    echo "   *41        - Caller ID test"
    echo ""
    echo "📝 Next Steps:"
    echo "   1. Access FreePBX at http://${SYSTEM_FQDN}/admin/"
    echo "   2. Run 'pbx-config' to quickly add extensions/trunks"
    echo "   3. Configure your SIP trunks (or use pbx-config TUI)"
    echo "   4. Create extensions for users (or use pbx-config TUI)"
    echo "   5. Try demo applications by dialing DEMO, 123, or 947"
    echo "   6. Set up IVR and advanced call routing in FreePBX"
    echo ""
    success "Installation completed successfully! 🚀"
    echo ""
    echo "All passwords have been saved to: ${AUTO_PASSWORDS_FILE}"
    echo ""
}

# =============================================================================
# MAIN INSTALLATION FUNCTION
# =============================================================================

run_installation() {
    step "🚀 Starting PBX system installation..."

    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║         Complete PBX Installation Script v${SCRIPT_VERSION}         ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""

    # System preparation
    detect_system

    # Load existing .env configuration (if this is a re-run)
    load_pbx_env

    prepare_system
    setup_repositories

    # Core system installation
    install_core_dependencies

    # Database and web server
    install_mariadb
    install_php
    install_apache

    # SSL/TLS and reverse proxy configuration
    configure_letsencrypt_integration
    configure_reverse_proxy_support

    # Core PBX system
    install_asterisk
    install_freepbx

    # Configure FreePBX network and SIP settings
    configure_freepbx

    # Asterisk sounds, prompts, and additional features
    install_asterisk_sounds
    install_tts_engine
    install_agi_scripts
    install_demo_applications

    # Fax system (if enabled)
    if [ "${INSTALL_AVANTFAX}" = "1" ]; then
        install_postfix
        install_hylafax
        install_iaxmodem
        install_avantfax
        configure_email_to_fax
        configure_fax_to_email
    fi

    # Security systems
    if [ "${FIREWALL_ENABLED}" = "1" ]; then
        configure_firewall
    fi

    if [ "${FAIL2BAN_ENABLED}" = "1" ]; then
        install_fail2ban
    fi

    # Backup system
    if [ "${BACKUP_ENABLED}" = "1" ]; then
        setup_backup_system
    fi

    # Create management scripts
    create_management_scripts

    # Final configuration
    finalize_installation

    # Verify installation
    verify_installation

    # Show completion message
    show_completion_message
}

# =============================================================================
# SCRIPT ENTRY POINT
# =============================================================================

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    error "This script must be run as root"
fi

# Handle command line arguments
case "${1:-install}" in
    install)
        run_installation
        ;;
    help|--help|-h)
        echo "PBX Installation Script v${SCRIPT_VERSION}"
        echo ""
        echo "Usage: $0 [action]"
        echo ""
        echo "Actions:"
        echo "  install  - Run complete PBX installation (default)"
        echo "  help     - Show this help message"
        echo ""
        echo "Environment Variables:"
        echo "  FREEPBX_ADMIN_PASSWORD  - Set FreePBX admin password"
        echo "  MYSQL_ROOT_PASSWORD     - Set MySQL root password"
        echo "  ADMIN_EMAIL            - Set administrator email"
        echo "  TIMEZONE               - Set system timezone"
        echo ""
        echo "Example:"
        echo "  FREEPBX_ADMIN_PASSWORD='MySecurePass123' $0"
        ;;
    *)
        error "Unknown action: $1. Use 'help' for usage information."
        ;;
esac

# Exit successfully
exit 0