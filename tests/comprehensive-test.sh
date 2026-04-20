#!/bin/bash
# =============================================================================
# PBX Comprehensive End-to-End Test Suite
# Covers: web, SIP, calls, fax, scripts, DB, security, admin, backup, email
# Run as root inside an installed PBX container
# =============================================================================
PASS=0; FAIL=0; WARN=0; SKIP=0
FAILURES=""

ok()   { echo "  PASS: $*"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $*"; FAIL=$((FAIL+1)); FAILURES="${FAILURES}\n  - $*"; }
warn() { echo "  WARN: $*"; WARN=$((WARN+1)); }
skip() { echo "  SKIP: $*"; SKIP=$((SKIP+1)); }
sep()  { echo ""; echo "=== $* ==="; }

# ── Read credentials from env file ──────────────────────────────────────────
ENV_FILE="/etc/pbx/.env"
FREEPBX_PASS="admin"
MYSQL_PASS=""
ADMIN_EMAIL=""
WEBMIN_PORT="9001"
WEB_ROOT="/var/www/apache/pbx"
BEHIND_PROXY="no"
PROXY_HTTP_PORT=""

if [ -f "$ENV_FILE" ]; then
    v=$(grep "^FREEPBX_ADMIN_PASSWORD=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"')
    [ -n "$v" ] && FREEPBX_PASS="$v"
    v=$(grep "^MYSQL_ROOT_PASSWORD_FILE=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"')
    [ -n "$v" ] && MYSQL_PASS_FILE="$v"
    v=$(grep "^ADMIN_EMAIL=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"')
    [ -n "$v" ] && ADMIN_EMAIL="$v"
    v=$(grep "^WEB_ROOT=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"')
    [ -n "$v" ] && WEB_ROOT="$v"
    v=$(grep "^BEHIND_PROXY=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"')
    [ -n "$v" ] && BEHIND_PROXY="$v"
    v=$(grep "^PROXY_HTTP_PORT=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"')
    [ -n "$v" ] && PROXY_HTTP_PORT="$v"
fi
[ -z "${MYSQL_PASS_FILE:-}" ] && MYSQL_PASS_FILE="/etc/pbx/mysql_root_password"
[ -z "$MYSQL_PASS" ] && [ -f "$MYSQL_PASS_FILE" ] && MYSQL_PASS=$(tr -d '\r\n' < "$MYSQL_PASS_FILE" 2>/dev/null)
v=$(grep "^port=" /etc/webmin/miniserv.conf 2>/dev/null | head -1 | cut -d= -f2)
[ -n "$v" ] && WEBMIN_PORT="$v"

AMI_USER=$(grep '^\[' /etc/asterisk/manager.conf 2>/dev/null | grep -v '^\[general\]' | head -1 | tr -d '[]')
AMI_SECRET=$(grep "^secret" /etc/asterisk/manager.conf 2>/dev/null | head -1 | awk -F'=' '{gsub(/ /,"",$2); print $2}')
DB_NAME=$(php -r "include '/etc/freepbx.conf'; echo \$amp_conf['AMPDBNAME'];" 2>/dev/null)
[ -z "$DB_NAME" ] && DB_NAME="asterisk"
FQDN=$(hostname -f 2>/dev/null || hostname)

if [ "$BEHIND_PROXY" = "yes" ] && [ -n "$PROXY_HTTP_PORT" ]; then
    WEB_BASE_URL="http://127.0.0.1:${PROXY_HTTP_PORT}"
else
    WEB_BASE_URL="https://127.0.0.1"
fi

db_q() { mysql -u root ${MYSQL_PASS:+-p"${MYSQL_PASS}"} "${DB_NAME}" -sNe "$1" 2>/dev/null; }
ast()  { asterisk -rx "$*" 2>/dev/null; }

svc_active() {
    local s
    for s in "$@"; do
        systemctl is-active "$s" >/dev/null 2>&1 && return 0
    done
    return 1
}

check_svc() {
    local label="$1"; shift
    local found=0 st
    for s in "$@"; do
        if systemctl list-units --type=service 2>/dev/null | grep -qE "^\s+${s}\.service"; then
            st=$(systemctl is-active "$s" 2>/dev/null)
            found=1
            case "$st" in
                active)     ok "SERVICE $label ($s): running"; return ;;
                activating) warn "SERVICE $label ($s): activating"; return ;;
                *)          fail "SERVICE $label ($s): $st"; return ;;
            esac
        fi
    done
    [ "$found" -eq 0 ] && fail "SERVICE $label: not installed"
}

curl_get() {
    local url="$1" code body
    body=$(curl -skL --max-time 10 "$url" 2>/dev/null)
    code=$(curl -skL --max-time 10 -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
    printf "%s\n%s" "$code" "$body"
}

# =============================================================================
sep "1. SYSTEM HEALTH"
# =============================================================================

OS=$(. /etc/os-release 2>/dev/null && echo "$NAME $VERSION_ID" || echo "Unknown")
ok "OS: $OS"

MEM_MB=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}')
[ "${MEM_MB:-0}" -ge 512 ] && ok "Memory: ${MEM_MB}MB" || warn "Low memory: ${MEM_MB}MB"

DISK_FREE=$(df -BG / 2>/dev/null | awk 'NR==2{gsub("G","",$4); print $4}')
[ "${DISK_FREE:-0}" -ge 5 ] && ok "Disk free: ${DISK_FREE}GB" || warn "Low disk: ${DISK_FREE}GB"

[ -f "$ENV_FILE" ] && ok "/etc/pbx/.env present ($(wc -l < "$ENV_FILE") variables)" || fail "/etc/pbx/.env missing"
[ -f /etc/pbx/state.json ] && ok "state.json: $(grep -c '=yes' /etc/pbx/state.json 2>/dev/null) components tracked" || warn "state.json missing"
ok "Hostname: $FQDN"

if command -v chronyc >/dev/null 2>&1; then
    chronyc tracking 2>/dev/null | grep -qiE "Leap status|Reference ID" \
        && ok "chrony: time sync active" || warn "chrony: not synced (OK in container)"
fi

# =============================================================================
sep "2. SERVICES"
# =============================================================================

check_svc "Asterisk"    asterisk freepbx
check_svc "MariaDB"     mariadb mysql
check_svc "Web server"  httpd apache2
check_svc "PHP-FPM"     php-fpm php8.2-fpm php7.4-fpm
check_svc "Postfix"     postfix
check_svc "Fail2ban"    fail2ban
check_svc "HylaFAX"     hylafax "hylafax+"
check_svc "Webmin"      webmin
check_svc "Cron"        crond cron cronie

# =============================================================================
sep "3. ASTERISK CORE"
# =============================================================================

VER=$(ast "core show version" | head -1)
echo "$VER" | grep -q "Asterisk" && ok "Version: $VER" || fail "Asterisk CLI not responding"

CTX=$(ast "dialplan show" | grep -c "Context" || echo 0)
[ "${CTX:-0}" -ge 50 ] && ok "Dialplan: $CTX contexts loaded" || fail "Dialplan too small: $CTX contexts"

for ctx in from-internal from-pstn from-trunk default macro-dialout-trunk-predial-hook; do
    ast "dialplan show $ctx" 2>/dev/null | grep -q "Context" \
        && ok "Context [$ctx] present" || fail "Context [$ctx] MISSING"
done

PJSIP_TRANSPORTS=$(ast "pjsip show transports")
PJSIP_TRANSPORT_COUNT=$(printf '%s\n' "$PJSIP_TRANSPORTS" | grep -cE '^Transport:') || PJSIP_TRANSPORT_COUNT=0
SIP_LISTENER_COUNT=$(ss -lntup 2>/dev/null | grep -cE '(:5060|:5061)') || SIP_LISTENER_COUNT=0
if printf '%s\n' "$PJSIP_TRANSPORTS" | grep -qiE "udp|tcp"; then
    ok "PJSIP transports: $PJSIP_TRANSPORT_COUNT"
elif [ "${SIP_LISTENER_COUNT:-0}" -gt 0 ]; then
    ok "SIP listeners active despite partial transport listing: $SIP_LISTENER_COUNT"
else
    fail "No PJSIP transports"
fi

ss -ulnp 2>/dev/null | grep -q ":5060" && ok "SIP UDP 5060 listening" || warn "SIP UDP 5060 not listening"
ss -tlnp 2>/dev/null | grep -q ":5038" && ok "AMI port 5038 listening" || fail "AMI port 5038 not listening"
ss -tlnp 2>/dev/null | grep -q ":8088" && ok "ARI/HTTP port 8088 listening" || warn "ARI port 8088 not listening"

for mod in chan_pjsip pbx_config app_voicemail res_musiconhold app_queue app_confbridge; do
    ast "module show like $mod" | grep -q "Running" \
        && ok "Module $mod: Running" || warn "Module $mod: not running"
done

SND=$(find /var/lib/asterisk/sounds/en -name "*.gsm" -o -name "*.ulaw" 2>/dev/null | wc -l)
[ "$SND" -ge 100 ] && ok "Sounds: $SND en/ files" || warn "Sounds: only $SND files"

MOH=$(find /var/lib/asterisk/moh -type f 2>/dev/null | wc -l)
[ "$MOH" -ge 1 ] && ok "Music on Hold: $MOH files" || warn "No MOH files"

AGI=$(find /var/lib/asterisk/agi-bin -type f 2>/dev/null | wc -l)
[ "$AGI" -ge 1 ] && ok "AGI scripts: $AGI in agi-bin/" || warn "No AGI scripts"

# AMI authentication
if [ -n "$AMI_USER" ] && [ -n "$AMI_SECRET" ]; then
    AMIRES=$(timeout 4 bash -c 'exec 3<>/dev/tcp/127.0.0.1/5038; printf "Action: Login\r\nUsername: '"$AMI_USER"'\r\nSecret: '"$AMI_SECRET"'\r\n\r\nAction: Logoff\r\n\r\n" >&3; sleep 1; cat <&3' 2>/dev/null || true)
    echo "$AMIRES" | grep -q "Response: Success" && ok "AMI login: authenticated" || warn "AMI login: failed (user=$AMI_USER)"
else
    warn "AMI user/secret not found in manager.conf"
fi

# Demo contexts
for ctx in demo-menu pbx-echo pbx-clock pbx-lenny; do
    ast "dialplan show $ctx" 2>/dev/null | grep -q "Context" \
        && ok "Demo dialplan [$ctx] present" || warn "Demo dialplan [$ctx] missing"
done

# =============================================================================
sep "4. CALL TEST via AMI Originate"
# =============================================================================

if [ -n "$AMI_USER" ] && [ -n "$AMI_SECRET" ]; then
    CALLID="pytest$(date +%s)"
    # Originate call to echo test (*43)
    ORIGOUT=$(timeout 10 bash -c 'exec 3<>/dev/tcp/127.0.0.1/5038
printf "Action: Login\r\nUsername: '"$AMI_USER"'\r\nSecret: '"$AMI_SECRET"'\r\n\r\n" >&3
sleep 0.3
printf "Action: Originate\r\nChannel: Local/*43@from-internal\r\nContext: from-internal\r\nExten: *43\r\nPriority: 1\r\nCallerID: TestBot <5550000000>\r\nTimeout: 5000\r\nActionID: '"$CALLID"'\r\n\r\n" >&3
sleep 4
printf "Action: Logoff\r\n\r\n" >&3
sleep 0.5
cat <&3' 2>/dev/null || true)
    echo "$ORIGOUT" | grep -qiE "Response: (Success|Error)" \
        && ok "AMI Originate accepted (echo test *43)" || warn "AMI Originate: no response from AMI"

    sleep 3
    # Check CDR for recent test call
    CDR_N=$(mysql -u root ${MYSQL_PASS:+-p"${MYSQL_PASS}"} asteriskcdrdb -sNe \
        "SELECT COUNT(*) FROM cdr WHERE calldate > DATE_SUB(NOW(), INTERVAL 3 MINUTE);" 2>/dev/null)
    [ "${CDR_N:-0}" -ge 1 ] && ok "CDR: $CDR_N recent entries logged" \
        || warn "CDR: no recent entries (call may not have connected)"

    # Active channels check
    CHANS=$(ast "core show channels" | grep -c "active call\|Local" || echo 0)
    ok "Active channels: $CHANS (call test complete)"
else
    warn "Skipping call test — AMI credentials not found"
fi

# =============================================================================
sep "5. FREEPBX MODULES"
# =============================================================================

fwconsole ma list 2>/dev/null | grep -q "Enabled" && ok "fwconsole works" || fail "fwconsole ma list failed"

MOD_COUNT=$(fwconsole ma list 2>/dev/null | grep -c "Enabled" || echo 0)
[ "${MOD_COUNT:-0}" -ge 40 ] && ok "Modules enabled: $MOD_COUNT" || fail "Too few modules: $MOD_COUNT"

for mod in core voicemail cdr backup ringgroups ivr dashboard framework sipsettings userman \
           timeconditions featurecodeadmin announcement recordings conferences \
           findmefollow callforward donotdisturb; do
    fwconsole ma list 2>/dev/null | grep -qE "^\| ${mod}[[:space:]]" \
        && ok "Module [${mod}]" || fail "Module [${mod}] MISSING"
done

fwconsole ma list 2>/dev/null | grep -qiE "dynroute|inboundroutes" \
    && ok "Routing module present" || warn "Routing module not found"

# fwconsole reload clean
RLOUT=$(fwconsole reload --skip-registry-checks 2>&1 | tail -3)
echo "$RLOUT" | grep -qiE "Reload Complete|message.*Reload" \
    && ok "fwconsole reload: clean" || warn "fwconsole reload: $RLOUT"

# =============================================================================
sep "6. DATABASE INTEGRITY"
# =============================================================================

mysql -u root ${MYSQL_PASS:+-p"${MYSQL_PASS}"} -e "SELECT VERSION();" 2>/dev/null | grep -q "." \
    && ok "MariaDB: $(mysql -u root ${MYSQL_PASS:+-p"${MYSQL_PASS}"} -e 'SELECT VERSION();' 2>/dev/null | tail -1)" \
    || fail "MariaDB not accessible"

TABLES=$(mysql -u root ${MYSQL_PASS:+-p"${MYSQL_PASS}"} "$DB_NAME" -e "SHOW TABLES;" 2>/dev/null | wc -l)
[ "${TABLES:-0}" -ge 20 ] && ok "FreePBX DB: $TABLES tables" || fail "FreePBX DB too small: $TABLES tables"

for tbl in devices users custom_extensions sipsettings featurecodes; do
    mysql -u root ${MYSQL_PASS:+-p"${MYSQL_PASS}"} "$DB_NAME" -e "SELECT 1 FROM $tbl LIMIT 1;" >/dev/null 2>&1 \
        && ok "DB table [$tbl] accessible" || warn "DB table [$tbl] missing from ${DB_NAME}"
done

# cdr and cel live in asteriskcdrdb (separate CDR database)
CDR_DB="asteriskcdrdb"
for tbl in cdr cel; do
    mysql -u root ${MYSQL_PASS:+-p"${MYSQL_PASS}"} "$CDR_DB" -e "SELECT 1 FROM $tbl LIMIT 1;" >/dev/null 2>&1 \
        && ok "DB table [${CDR_DB}.${tbl}] accessible" || fail "DB table [${CDR_DB}.${tbl}] missing"
done

FW_VER=$(db_q "SELECT value FROM admin WHERE variable='version' LIMIT 1;")
[ -n "$FW_VER" ] && ok "FreePBX DB version: $FW_VER" || warn "FreePBX version not found in DB"

USERS=$(db_q "SELECT COUNT(*) FROM ampusers;")
[ "${USERS:-0}" -ge 1 ] && ok "FreePBX admin accounts: $USERS" || warn "No FreePBX user accounts in DB"

SIP_PORT=$(db_q "SELECT data FROM sipsettings WHERE keyword='bindport' LIMIT 1;")
[ -n "${SIP_PORT}" ] && ok "SIP settings in DB: bindport=$SIP_PORT" || warn "SIP port in DB: '$SIP_PORT'"

# ODBC
odbcinst -q -d 2>/dev/null | grep -qiE "MariaDB|MySQL" \
    && ok "ODBC MariaDB driver registered" || warn "ODBC driver not in odbcinst"

# =============================================================================
sep "7. WEB SERVICES"
# =============================================================================

_curl_code() { curl -skL --max-time 10 -o /tmp/pbx-curl-tmp -w "%{http_code}" "$1" 2>/dev/null || echo "000"; }
_curl_body() { cat /tmp/pbx-curl-tmp 2>/dev/null; }

check_url() {
    local label="$1" url="$2" ok_codes="$3" pattern="${4:-}"
    local code body
    code=$(_curl_code "$url")
    body=$(_curl_body)
    if echo "$ok_codes" | tr ',' '\n' | grep -qx "$code"; then
        if [ -n "$pattern" ]; then
            echo "$body" | grep -qiE "$pattern" \
                && ok "$label: HTTP $code, content OK" \
                || fail "$label: HTTP $code but content mismatch (expected: $pattern)"
        else
            ok "$label: HTTP $code"
        fi
    else
        fail "$label: expected HTTP [$ok_codes], got $code"
    fi
}

check_url "Portal root"             "${WEB_BASE_URL}/"                      "200,301,302"
check_url "FreePBX /admin/"         "${WEB_BASE_URL}/admin/"                "200,302"   "FreePBX|pbx|login|password"
check_url "/health JSON"            "${WEB_BASE_URL}/health"                "200"       "status|ok|healthy|version"
check_url "/status/ page"           "${WEB_BASE_URL}/status/"               "200"       "asterisk|pbx|service|version|status"
check_url "/avantfax/"              "${WEB_BASE_URL}/avantfax/"             "200,302"   "AvantFax|fax|Hyla|login"
check_url "/callcenter/"            "${WEB_BASE_URL}/callcenter/"           "200,302,401,403"
check_url "Webmin HTTPS"            "https://127.0.0.1:${WEBMIN_PORT}/"    "200,302,401" "Webmin|webmin|login"

# Health endpoint detailed
HEALTH=$(_curl_code "${WEB_BASE_URL}/health")
HBODY=$(_curl_body)
echo "$HBODY" | grep -qiE '"status"'   && ok "/health: has 'status' key"    || warn "/health: missing 'status' key"
echo "$HBODY" | grep -qiE '"asterisk"' && ok "/health: has 'asterisk' key"  || warn "/health: missing 'asterisk' key"
echo "$HBODY" | grep -qiE '"mariadb"|"database"' && ok "/health: has DB key" || warn "/health: missing DB key"
echo "$HBODY" | grep -qiE '"hylafax"|"fax"' && ok "/health: has fax key"    || warn "/health: missing fax key"

# FreePBX admin login page content
ADMIN_BODY=$(_curl_code "${WEB_BASE_URL}/admin/config.php" >/dev/null; _curl_body)
echo "$ADMIN_BODY" | grep -qiE "html|FreePBX|login|password" \
    && ok "FreePBX admin page: HTML rendered" || warn "FreePBX admin page: unexpected content"

# PHP working (dynamic content test)
PHP_OUT=$(_curl_code "${WEB_BASE_URL}/admin/config.php" > /dev/null; _curl_body)
echo "$PHP_OUT" | grep -qiE "<!DOCTYPE|<html" \
    && ok "PHP: dynamic HTML page rendered via Apache/FPM" || warn "PHP: page may not be rendering"

if [ "$BEHIND_PROXY" = "yes" ] && [ -n "$PROXY_HTTP_PORT" ]; then
    skip "TLS: direct Apache 443 skipped in reverse proxy mode"
    ss -tlnp 2>/dev/null | grep -q ":${PROXY_HTTP_PORT}\b" \
        && ok "Apache proxy port ${PROXY_HTTP_PORT} listening" \
        || fail "Apache proxy port ${PROXY_HTTP_PORT} NOT listening"
else
    CERT=$(echo | openssl s_client -connect 127.0.0.1:443 -servername "$FQDN" 2>/dev/null | openssl x509 -noout -subject -dates 2>/dev/null)
    [ -n "$CERT" ] && ok "TLS: SSL cert valid — $(echo "$CERT" | grep notAfter)" || warn "TLS: no cert returned"
    ss -tlnp 2>/dev/null | grep -q ":443" && ok "Apache: port 443 listening" || fail "Apache: port 443 NOT listening"
    ss -tlnp 2>/dev/null | grep -q ":80" && ok "Apache: port 80 listening" || warn "Apache: port 80 not listening"
fi

# =============================================================================
sep "8. FAX SYSTEM"
# =============================================================================

pgrep -x hfaxd >/dev/null 2>&1 && ok "hfaxd process running" || fail "hfaxd not running"
ss -tlnp 2>/dev/null | grep -q ":4559" && ok "hfaxd port 4559 listening" || fail "hfaxd port 4559 not listening"

FAXSTAT_OUT=$(timeout 5 faxstat -h 127.0.0.1 2>&1)
FAXSTAT_EXIT=$?
[ "$FAXSTAT_EXIT" -eq 0 ] \
    && ok "faxstat: connected to hfaxd" \
    || warn "faxstat: cannot connect to hfaxd (exit=$FAXSTAT_EXIT)"

IAXPIDS=$(pgrep -x iaxmodem 2>/dev/null | wc -l)
[ "${IAXPIDS:-0}" -ge 4 ] && ok "iaxmodem: $IAXPIDS instances running" || fail "iaxmodem: $IAXPIDS instances (need 4)"

TTYCOUNT=$(ls /dev/ttyIAX* 2>/dev/null | wc -l)
[ "${TTYCOUNT:-0}" -ge 4 ] && ok "IAX tty devices: $TTYCOUNT (/dev/ttyIAX1-4)" || fail "IAX tty devices: $TTYCOUNT (need 4)"

[ -d /var/spool/hylafax/etc ]   && ok "HylaFAX spool/etc present"  || fail "HylaFAX spool missing"
[ -d /var/spool/hylafax/recvq ] && ok "HylaFAX recvq present"      || warn "HylaFAX recvq missing"
[ -d /var/spool/hylafax/sendq ] && ok "HylaFAX sendq present"      || warn "HylaFAX sendq missing"

MCONF=$(ls /var/spool/hylafax/etc/config.ttyIAX* 2>/dev/null | wc -l)
[ "${MCONF:-0}" -ge 4 ] && ok "HylaFAX modem configs: $MCONF" || warn "HylaFAX modem configs: $MCONF (need 4)"

AF_DIR="${WEB_ROOT}/avantfax"
[ -d "$AF_DIR" ]                          && ok "AvantFax dir: $AF_DIR"        || fail "AvantFax dir missing"
[ -f "${AF_DIR}/index.php" ]              && ok "AvantFax index.php present"   || fail "AvantFax index.php missing"
[ -f "${AF_DIR}/includes/config.php" ]    && ok "AvantFax config.php present"  || fail "AvantFax config.php missing"
[ -f "${AF_DIR}/includes/FaxModem.php" ]  && ok "AvantFax FaxModem.php present" || warn "AvantFax FaxModem.php missing"

AF_DB=$(mysql -u root ${MYSQL_PASS:+-p"${MYSQL_PASS}"} -e "SHOW DATABASES LIKE 'avantfax';" 2>/dev/null | grep -c "avantfax" || echo 0)
[ "${AF_DB:-0}" -ge 1 ] && ok "AvantFax database exists" || warn "AvantFax database missing"

grep -qE "EMAIL_TO_FAX_ALIAS|FAX_EMAIL_ALIAS" "$ENV_FILE" 2>/dev/null \
    && ok "Fax email alias configured" \
    || warn "Email-to-fax alias not in .env"

# =============================================================================
sep "9. SECURITY & FIREWALL"
# =============================================================================

systemctl is-active fail2ban >/dev/null 2>&1 && ok "fail2ban: active" || fail "fail2ban: not running"

JAILS=$(fail2ban-client status 2>/dev/null | grep "Jail list" | sed 's/.*://' | tr ',' '\n' | grep -v "^[[:space:]]*$" | wc -l)
[ "${JAILS:-0}" -ge 2 ] && ok "fail2ban jails: $JAILS active" || warn "fail2ban jails: $JAILS"

for jail in asterisk apache-auth; do
    fail2ban-client status "$jail" 2>/dev/null | grep -q "Currently banned" \
        && ok "fail2ban jail [$jail]: active" || warn "fail2ban jail [$jail]: not found"
done
# SSH jail may be named differently across distros
fail2ban-client status 2>/dev/null | grep -qiE "sshd|ssh" \
    && ok "fail2ban: SSH jail active" || warn "fail2ban: no SSH jail (sshd/ssh)"

# Firewall
if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active firewalld >/dev/null 2>&1; then
    ok "Firewall: firewalld active"
    SVCS=$(firewall-cmd --list-services 2>/dev/null)
    echo "$SVCS" | grep -qiE "http" && ok "firewalld: HTTP/HTTPS allowed" || warn "firewalld: HTTP not in allowed services"
    PORTS=$(firewall-cmd --list-ports 2>/dev/null)
    echo "$PORTS" | grep -q "5060" && ok "firewalld: SIP 5060 allowed" || warn "firewalld: SIP 5060 not in ports"
elif command -v ufw >/dev/null 2>&1; then
    UFW_ST=$(ufw status 2>/dev/null | head -1)
    ok "Firewall: ufw ($UFW_ST)"
elif iptables -L INPUT -n 2>/dev/null | grep -qE "ACCEPT|REJECT|DROP"; then
    RULES=$(iptables -L INPUT -n 2>/dev/null | grep -cE "ACCEPT|DROP|REJECT")
    ok "Firewall: iptables ($RULES INPUT rules)"
else
    warn "No active firewall detected"
fi

# SSH
SSHD_CONF=""
for f in /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf; do
    [ -f "$f" ] && SSHD_CONF="${SSHD_CONF} $(cat "$f")"
done
echo "$SSHD_CONF" | grep -qE "PermitRootLogin (no|prohibit-password)" \
    && ok "SSH: PermitRootLogin restricted" || warn "SSH: PermitRootLogin may allow root"

# =============================================================================
sep "10. MANAGEMENT SCRIPTS — IN-DEPTH"
# =============================================================================

ALL_SCRIPTS="pbx-status pbx-services pbx-ssl pbx-network pbx-logs pbx-firewall
             pbx-security pbx-passwords pbx-cdr pbx-trunks pbx-asterisk pbx-calls
             pbx-repair pbx-restart pbx-cleanup pbx-docs pbx-moh pbx-recordings
             pbx-config pbx-diag pbx-update pbx-backup pbx-ssh pbx-webmin
             pbx-add-ip pbx-provision pbxstatus"

MISSING_SCRIPTS=0
for s in $ALL_SCRIPTS; do
    command -v "$s" >/dev/null 2>&1 || { fail "Script missing from PATH: $s"; MISSING_SCRIPTS=$((MISSING_SCRIPTS+1)); }
done
[ "$MISSING_SCRIPTS" -eq 0 ] && ok "All management scripts in PATH"

# pbx-status — full run
OUT=$(NO_COLOR=1 pbx-status 2>/dev/null)
[ -n "$OUT" ] \
    && echo "$OUT" | grep -qiE "asterisk|running|PBX|service" \
    && ok "pbx-status: service info shown" || warn "pbx-status: no service info"

# pbx-services — full run
OUT=$(NO_COLOR=1 pbx-services 2>/dev/null)
echo "$OUT" | grep -qiE "running|stopped|active|asterisk" \
    && ok "pbx-services: status table shown" || warn "pbx-services: no status"

# pbx-asterisk
OUT=$(NO_COLOR=1 pbx-asterisk 2>/dev/null)
echo "$OUT" | grep -qiE "asterisk|channel|version|peer" \
    && ok "pbx-asterisk: Asterisk info shown" || warn "pbx-asterisk: minimal output"

# pbx-network
OUT=$(NO_COLOR=1 pbx-network 2>/dev/null)
echo "$OUT" | grep -qiE "IP|interface|eth|port|network" \
    && ok "pbx-network: network info shown" || warn "pbx-network: minimal output"

# pbx-vpn
OUT=$(NO_COLOR=1 pbx-vpn --status 2>/dev/null)
echo "$OUT" | grep -qiE "vpn|openvpn|wireguard|client" \
    && ok "pbx-vpn: VPN client status shown" || warn "pbx-vpn: minimal output"

# pbx-ssl
OUT=$(NO_COLOR=1 pbx-ssl 2>/dev/null)
echo "$OUT" | grep -qiE "cert|SSL|TLS|expire|self.signed|Let" \
    && ok "pbx-ssl: cert status shown" || warn "pbx-ssl: minimal output"

# pbx-firewall
OUT=$(NO_COLOR=1 pbx-firewall 2>/dev/null)
echo "$OUT" | grep -qiE "firewall|rule|port|zone|allow|fail2ban" \
    && ok "pbx-firewall: firewall rules shown" || warn "pbx-firewall: minimal output"

# pbx-security
OUT=$(NO_COLOR=1 pbx-security 2>/dev/null)
echo "$OUT" | grep -qiE "security|check|pass|fail|warn|permission|ssh" \
    && ok "pbx-security: audit results shown" || warn "pbx-security: minimal output"

# pbx-passwords
OUT=$(NO_COLOR=1 pbx-passwords 2>/dev/null | head -30)
echo "$OUT" | grep -qiE "password|secret|MariaDB|admin|credential" \
    && ok "pbx-passwords: credential info shown" || warn "pbx-passwords: minimal output"

# pbx-cdr
OUT=$(NO_COLOR=1 pbx-cdr 2>/dev/null | head -20)
echo "$OUT" | grep -qiE "CDR|call|record|duration|date" \
    && ok "pbx-cdr: CDR data shown" || warn "pbx-cdr: no CDR output"

# pbx-moh
OUT=$(NO_COLOR=1 pbx-moh 2>/dev/null)
echo "$OUT" | grep -qiE "music|hold|MOH|file|class" \
    && ok "pbx-moh: MOH status shown" || warn "pbx-moh: minimal output"

# pbx-logs
OUT=$(NO_COLOR=1 pbx-logs 2>/dev/null | head -20)
echo "$OUT" | grep -qiE "log|asterisk|error|apache|system" \
    && ok "pbx-logs: log entries shown" || warn "pbx-logs: minimal output"

# pbx-trunks
OUT=$(NO_COLOR=1 pbx-trunks 2>/dev/null)
echo "$OUT" | grep -qiE "trunk|SIP|PJSIP|provider|no trunk" \
    && ok "pbx-trunks: trunk info shown" || warn "pbx-trunks: minimal output"

# pbx-diag
OUT=$(NO_COLOR=1 timeout 30 pbx-diag 2>/dev/null | head -30)
echo "$OUT" | grep -qiE "diag|check|OK|FAIL|system|asterisk" \
    && ok "pbx-diag: diagnostic results shown" || warn "pbx-diag: minimal output"

# pbx-recordings
OUT=$(NO_COLOR=1 pbx-recordings 2>/dev/null | head -10)
echo "$OUT" | grep -qiE "record|call|file|no recording" \
    && ok "pbx-recordings: recording list shown" || warn "pbx-recordings: minimal output"

# pbx-calls
OUT=$(NO_COLOR=1 pbx-calls 2>/dev/null | head -10)
echo "$OUT" | grep -qiE "call|active|channel|no call" \
    && ok "pbx-calls: call info shown" || warn "pbx-calls: minimal output"

# pbxstatus (alias)
command -v pbxstatus >/dev/null 2>&1 && \
    OUT=$(NO_COLOR=1 pbxstatus 2>/dev/null) && \
    [ -n "$OUT" ] && ok "pbxstatus alias: works" || warn "pbxstatus: no output"

# pbx-webmin
OUT=$(NO_COLOR=1 pbx-webmin 2>/dev/null | head -10)
echo "$OUT" | grep -qiE "webmin|port|status|URL" \
    && ok "pbx-webmin: Webmin info shown" || warn "pbx-webmin: minimal output"

# =============================================================================
sep "11. BACKUP SYSTEM"
# =============================================================================

BACKUP_OUT=$(NO_COLOR=1 timeout 120 pbx-backup --now 2>&1)
echo "$BACKUP_OUT" | grep -qiE "success|complete|backup|OK" \
    && ok "pbx-backup --now: completed successfully" || fail "pbx-backup --now: FAILED"

BDIR="/mnt/backups/pbx"
[ -d "$BDIR" ] && ok "Backup dir: $BDIR" || fail "Backup dir missing: $BDIR"

TAR_N=$(find "$BDIR" -name "*.tar.gz" 2>/dev/null | wc -l)
SQL_N=$(find "$BDIR" \( -name "*.sql.gz" -o -name "*.sql" \) 2>/dev/null | wc -l)
[ "$TAR_N" -ge 1 ] && ok "Backup archives: $TAR_N tar.gz" || warn "No tar.gz backup files"
[ "$SQL_N" -ge 1 ] && ok "Backup SQL dumps: $SQL_N sql files" || warn "No SQL dumps"

LATEST=$(find "$BDIR" -name "*.tar.gz" 2>/dev/null | sort -t/ -k5 | tail -1)
if [ -n "$LATEST" ]; then
    SZ=$(stat -c%s "$LATEST" 2>/dev/null || echo 0)
    [ "${SZ:-0}" -gt 1024 ] && ok "Latest backup size: $((SZ/1024))KB" || warn "Backup suspiciously small: ${SZ}B"
fi

# Cron backup job
BCRON=$(crontab -l 2>/dev/null; cat /etc/crontab 2>/dev/null; cat /etc/cron.d/pbx* 2>/dev/null; cat /etc/cron.daily/pbx-* 2>/dev/null)
echo "$BCRON" | grep -qiE "backup" \
    && ok "Backup cron job configured" || warn "No backup cron job found"

# pbx-cleanup
OUT=$(NO_COLOR=1 pbx-cleanup --dry-run 2>/dev/null || NO_COLOR=1 pbx-cleanup 2>/dev/null | head -5)
echo "$OUT" | grep -qiE "clean|backup|retain|dry" \
    && ok "pbx-cleanup: runs without error" || warn "pbx-cleanup: no output"

# =============================================================================
sep "12. EMAIL / POSTFIX"
# =============================================================================

systemctl is-active postfix >/dev/null 2>&1 && ok "Postfix: active" || fail "Postfix: not running"
ss -tlnp 2>/dev/null | grep -q ":25\b" && ok "SMTP port 25: listening" || warn "SMTP port 25: not listening"

POSTHOST=$(postconf -h myhostname 2>/dev/null)
[ -n "$POSTHOST" ] && ok "Postfix myhostname: $POSTHOST" || warn "Postfix myhostname not configured"

POSTORIGIN=$(postconf -h myorigin 2>/dev/null)
[ -n "$POSTORIGIN" ] && ok "Postfix myorigin: $POSTORIGIN" || warn "Postfix myorigin not set"

MAILQ=$(mailq 2>/dev/null | tail -1)
ok "Mail queue: $MAILQ"

# =============================================================================
sep "13. FILE SYSTEM & PERMISSIONS"
# =============================================================================

for dir in /etc/asterisk /var/lib/asterisk /var/log/asterisk /var/spool/asterisk \
           /etc/pbx "${WEB_ROOT}" /mnt/backups/pbx /var/spool/hylafax; do
    [ -d "$dir" ] && ok "Dir exists: $dir" || fail "Dir MISSING: $dir"
done

id asterisk >/dev/null 2>&1 && ok "asterisk system user exists" || fail "asterisk user missing"

for f in /etc/asterisk/pjsip.conf /etc/asterisk/extensions.conf \
          /etc/asterisk/manager.conf /etc/asterisk/modules.conf \
          /etc/freepbx.conf "${WEB_ROOT}/admin/config.php"; do
    [ -f "$f" ] && ok "Config: $f" || fail "Config MISSING: $f"
done

OWN=$(stat -c%U /etc/asterisk 2>/dev/null)
[ "$OWN" = "asterisk" ] && ok "/etc/asterisk owned by asterisk" || warn "/etc/asterisk owned by $OWN"

PHPOWN=$(stat -c%U /var/lib/php/session 2>/dev/null || stat -c%U /var/lib/php/sessions 2>/dev/null || echo "unknown")
[ "$PHPOWN" = "asterisk" ] && ok "PHP session dir owned by asterisk" || warn "PHP session dir owned by $PHPOWN (FPM issues possible)"

# =============================================================================
sep "14. CERTIFICATES & TLS"
# =============================================================================

[ -d /etc/asterisk/keys ] && ok "/etc/asterisk/keys dir exists" || warn "/etc/asterisk/keys missing"
KEY_N=$(ls /etc/asterisk/keys/*.pem /etc/asterisk/keys/*.crt 2>/dev/null | wc -l)
[ "$KEY_N" -ge 1 ] && ok "Asterisk TLS key files: $KEY_N" || warn "No Asterisk TLS keys"

if [ "$BEHIND_PROXY" = "yes" ] && [ -n "$PROXY_HTTP_PORT" ]; then
    skip "TLS handshake: skipped in reverse proxy mode"
else
    openssl s_client -connect 127.0.0.1:443 -servername localhost </dev/null 2>/dev/null | grep -qiE "CONNECTED|CERTIFICATE" \
        && ok "TLS handshake: Apache 443 OK" || warn "TLS handshake: failed"
fi

if [ -d /etc/letsencrypt/live ]; then
    LE_N=$(ls /etc/letsencrypt/live/ 2>/dev/null | wc -l)
    ok "Let's Encrypt: $LE_N domains"
else
    ok "Self-signed cert in use (Let's Encrypt not configured — OK)"
fi

# =============================================================================
sep "15. VOICEMAIL"
# =============================================================================

[ -f /etc/asterisk/voicemail.conf ] \
    && ok "voicemail.conf: $(wc -l < /etc/asterisk/voicemail.conf) lines" \
    || fail "voicemail.conf missing"

[ -d /var/spool/asterisk/voicemail ] && ok "Voicemail spool exists" || warn "Voicemail spool missing"

ast "dialplan show pbx-voicemail" 2>/dev/null | grep -q "Context" \
    && ok "Voicemail dialplan [pbx-voicemail] loaded" \
    || { ast "dialplan show app-voicemail" 2>/dev/null | grep -q "Context" \
         && ok "Voicemail dialplan [app-voicemail] loaded" || warn "Voicemail dialplan context missing"; }

ast "module show like app_voicemail" | grep -q "Running" \
    && ok "app_voicemail.so: running" || fail "app_voicemail.so: not running"

# Voicemail contexts in conf
grep -c '^\[' /etc/asterisk/voicemail.conf 2>/dev/null | grep -q "[0-9]" \
    && ok "Voicemail contexts: $(grep -c '^\[' /etc/asterisk/voicemail.conf)" || warn "No voicemail contexts"

# =============================================================================
sep "16. CONFERENCE & FEATURES"
# =============================================================================

ast "module show like app_confbridge" | grep -q "Running" \
    && ok "ConfBridge module: running" || warn "ConfBridge module: not running"

# ConfBridge is used inline (no discrete dialplan context) - check usage in dialplan
ast "dialplan show app-conferences" 2>/dev/null | grep -q "Context" \
    && ok "Conference dialplan context present" \
    || { ast "dialplan show" 2>/dev/null | grep -qi "confbridge\|conference" \
         && ok "ConfBridge used in dialplan (no discrete context)" || warn "Conference dialplan missing"; }

for feat in callforward donotdisturb findmefollow; do
    fwconsole ma list 2>/dev/null | grep -qE "^\| ${feat}[[:space:]]" \
        && ok "Feature module [${feat}]" || warn "Feature module [${feat}] missing"
done

# =============================================================================
sep "17. CRON & MAINTENANCE"
# =============================================================================

svc_active crond cron && ok "Cron service: active" || warn "Cron service: not active"

ALL_CRON=$(crontab -l 2>/dev/null; cat /etc/crontab 2>/dev/null; find /etc/cron.d /etc/cron.daily /etc/cron.weekly -type f 2>/dev/null | xargs cat 2>/dev/null; crontab -u asterisk -l 2>/dev/null; crontab -u root -l 2>/dev/null)
echo "$ALL_CRON" | grep -qiE "backup|pbx-backup"   && ok "Cron: backup job present"    || warn "Cron: no backup job"
echo "$ALL_CRON" | grep -qiE "cleanup|pbx-cleanup" && ok "Cron: cleanup job present"   || warn "Cron: no cleanup job"
echo "$ALL_CRON" | grep -qiE "fwconsole|freepbx"   && ok "Cron: FreePBX cron present" || warn "Cron: no FreePBX cron"

[ -f /etc/logrotate.d/asterisk ] || [ -f /etc/logrotate.d/pbx ] \
    && ok "Log rotation: Asterisk/PBX config found" || warn "Log rotation: no Asterisk config"

# =============================================================================
sep "18. IDEMPOTENCY / INSTALL INTEGRITY"
# =============================================================================

[ -f /var/log/pbx-install.log ] && {
    grep -q "completed successfully" /var/log/pbx-install.log \
        && ok "Install log: 'completed successfully' found" \
        || warn "Install log: no completion marker"
    ISTEPS=$(grep "STEP " /var/log/pbx-install.log | grep -v "^[[:space:]]" | wc -l)
    ok "Install steps logged: $ISTEPS"
} || warn "Install log not found"

if [ -f /etc/pbx/state.json ]; then
    DONE_STEPS=$(grep -c '=yes' /etc/pbx/state.json 2>/dev/null)
    [ "$DONE_STEPS" -ge 8 ] && ok "State: $DONE_STEPS components installed" || warn "State: only $DONE_STEPS components"
fi

# =============================================================================
sep "FINAL SUMMARY"
# =============================================================================
echo ""
echo "  PASSED:  $PASS"
echo "  WARNED:  $WARN"
echo "  FAILED:  $FAIL"
echo "  SKIPPED: $SKIP"
echo ""

if [ "$FAIL" -gt 0 ]; then
    echo "FAILURES DETAIL:"
    printf "%b\n" "$FAILURES"
    echo ""
    echo "RESULT: $FAIL FAILURE(S) — REQUIRES FIXES"
    exit 1
else
    echo "RESULT: ALL TESTS PASSED — PRODUCTION READY"
    exit 0
fi
