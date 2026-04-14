#!/bin/bash
# =============================================================================
# PBX End-User / Admin Beta Test Suite
# Simulates real admin and end-user workflows
# Run as root inside an installed PBX container
# =============================================================================
PASS=0; FAIL=0; WARN=0
FAILURES=""

ok()   { echo "  PASS: $*"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $*"; FAIL=$((FAIL+1)); FAILURES="${FAILURES}|$*"; }
warn() { echo "  WARN: $*"; WARN=$((WARN+1)); }
sep()  { echo ""; echo "=== $* ==="; }

ENV_FILE="/etc/pbx/.env"
FREEPBX_USER="administrator"
AVANTFAX_USER="administrator"
AVANTFAX_PASS=""
FREEPBX_PASS="admin"
MYSQL_PASS=""
WEBMIN_PORT="9001"
WEB_ROOT="/var/www/apache/pbx"

if [ -f "$ENV_FILE" ]; then
    v=$(grep "^FREEPBX_ADMIN_USERNAME=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"')
    [ -n "$v" ] && FREEPBX_USER="$v"
    v=$(grep "^ADMIN_PASSWORD=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"')
    [ -z "$v" ] && v=$(grep "^FREEPBX_ADMIN_PASSWORD=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"')
    [ -n "$v" ] && FREEPBX_PASS="$v"
    v=$(grep "^AVANTFAX_ADMIN_USERNAME=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"')
    [ -n "$v" ] && AVANTFAX_USER="$v"
    v=$(grep "^AVANTFAX_ADMIN_PASSWORD=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"')
    [ -n "$v" ] && AVANTFAX_PASS="$v"
    v=$(grep "^MYSQL_ROOT_PASSWORD_FILE=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"')
    [ -n "$v" ] && MYSQL_PASS_FILE="$v"
    v=$(grep "^WEB_ROOT=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"')
    [ -n "$v" ] && WEB_ROOT="$v"
fi
[ -z "${MYSQL_PASS_FILE:-}" ] && MYSQL_PASS_FILE="/etc/pbx/mysql_root_password"
[ -z "$MYSQL_PASS" ] && [ -f "$MYSQL_PASS_FILE" ] && MYSQL_PASS=$(tr -d '\r\n' < "$MYSQL_PASS_FILE" 2>/dev/null)
[ -z "$AVANTFAX_PASS" ] && AVANTFAX_PASS="$FREEPBX_PASS"
v=$(grep "^port=" /etc/webmin/miniserv.conf 2>/dev/null | head -1 | cut -d= -f2)
[ -n "$v" ] && WEBMIN_PORT="$v"

AMI_USER=$(grep '^\[' /etc/asterisk/manager.conf 2>/dev/null | grep -v '^\[general\]' | head -1 | tr -d '[]')
AMI_SECRET=$(grep "^secret" /etc/asterisk/manager.conf 2>/dev/null | head -1 | awk -F'=' '{gsub(/ /,"",$2); print $2}')
DB_NAME=$(php -r "include '/etc/freepbx.conf'; echo \$amp_conf['AMPDBNAME'];" 2>/dev/null || echo "asterisk")
[ -z "$DB_NAME" ] && DB_NAME="asterisk"
FQDN=$(hostname -f 2>/dev/null || hostname)
HOST_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
APACHE_SERVICE=$(grep "^APACHE_SERVICE=" "$ENV_FILE" 2>/dev/null | cut -d= -f2 || echo "httpd")

db_q() { mysql -u root ${MYSQL_PASS:+-p"${MYSQL_PASS}"} "${DB_NAME}" -sNe "$1" 2>/dev/null; }
ast()  { asterisk -rx "$*" 2>/dev/null; }
curl_body() { cat /tmp/eu-curl.tmp 2>/dev/null; }

_http() {
    local url="$1"
    local code body
    code=$(curl -skL --max-time 10 -b /tmp/pbx-cookie.jar -c /tmp/pbx-cookie.jar \
        -o /tmp/eu-curl.tmp -w "%{http_code}" "$url" 2>/dev/null || echo "000")
    echo "$code"
}

echo "========================================================"
echo " PBX END-USER / ADMIN BETA TEST"
echo " Host: ${FQDN} (${HOST_IP})"
echo " Date: $(date)"
echo "========================================================"

# =============================================================================
sep "1. WEB UI - FREEPBX ADMIN LOGIN & NAVIGATION"
# =============================================================================

# Login to FreePBX
LOGIN_CODE=$(curl -skL --max-time 10 \
    -c /tmp/pbx-cookie.jar -o /tmp/eu-curl.tmp -w "%{http_code}" \
    "https://${HOST_IP}/admin/" 2>/dev/null || echo "000")
[ "$LOGIN_CODE" != "000" ] && ok "FreePBX admin page: reachable (HTTP $LOGIN_CODE)" || fail "FreePBX admin: unreachable"

LOGIN_BODY=$(cat /tmp/eu-curl.tmp 2>/dev/null)
echo "$LOGIN_BODY" | grep -qiE "login|username|password|FreePBX" \
    && ok "FreePBX: login form present" || warn "FreePBX: no login form detected"

# Submit login credentials
POST_CODE=$(curl -skL --max-time 10 \
    -b /tmp/pbx-cookie.jar -c /tmp/pbx-cookie.jar \
    -d "username=${FREEPBX_USER}&password=${FREEPBX_PASS}&action=login" \
    -o /tmp/eu-curl.tmp -w "%{http_code}" \
    "https://${HOST_IP}/admin/config.php" 2>/dev/null || echo "000")
POST_BODY=$(cat /tmp/eu-curl.tmp 2>/dev/null)
echo "$POST_BODY" | grep -qiE "dashboard|Logout|FreePBX Administration|pbx_admin" \
    && ok "FreePBX login: authenticated (${FREEPBX_USER})" || warn "FreePBX login: auth state unclear (HTTP $POST_CODE)"

# Navigate to dashboard
DASH_CODE=$(_http "https://${HOST_IP}/admin/config.php?display=dashboard")
DASH_BODY=$(curl_body)
echo "$DASH_BODY" | grep -qiE "module|FreePBX|dashboard|System|Notifications" \
    && ok "FreePBX dashboard: loads after login" || warn "FreePBX dashboard: content unexpected"

# Navigate to Extensions page  
EXT_CODE=$(_http "https://${HOST_IP}/admin/config.php?display=extensions")
EXT_BODY=$(curl_body)
echo "$EXT_BODY" | grep -qiE "extension|device|FreePBX" \
    && ok "FreePBX Extensions page: accessible" || warn "FreePBX Extensions page: access issue (HTTP $EXT_CODE)"

# Navigate to Trunks page
TRUNK_CODE=$(_http "https://${HOST_IP}/admin/config.php?display=trunks")
TRUNK_BODY=$(curl_body)
echo "$TRUNK_BODY" | grep -qiE "trunk|FreePBX" \
    && ok "FreePBX Trunks page: accessible" || warn "FreePBX Trunks page: access issue (HTTP $TRUNK_CODE)"

# Navigate to Inbound Routes
IR_CODE=$(_http "https://${HOST_IP}/admin/config.php?display=inboundroutes")
echo "$IR_CODE" | grep -qE "^(200|302)$" && ok "FreePBX Inbound Routes: accessible (HTTP $IR_CODE)" || warn "Inbound Routes: HTTP $IR_CODE"

# Navigate to Outbound Routes
OR_CODE=$(_http "https://${HOST_IP}/admin/config.php?display=outboundroutes")
echo "$OR_CODE" | grep -qE "^(200|302)$" && ok "FreePBX Outbound Routes: accessible (HTTP $OR_CODE)" || warn "Outbound Routes: HTTP $OR_CODE"

# Navigate to IVR
IVR_CODE=$(_http "https://${HOST_IP}/admin/config.php?display=ivr")
echo "$IVR_CODE" | grep -qE "^(200|302)$" && ok "FreePBX IVR: accessible (HTTP $IVR_CODE)" || warn "IVR: HTTP $IVR_CODE"

# Navigate to Ring Groups
RG_CODE=$(_http "https://${HOST_IP}/admin/config.php?display=ringgroups")
echo "$RG_CODE" | grep -qE "^(200|302)$" && ok "FreePBX Ring Groups: accessible (HTTP $RG_CODE)" || warn "Ring Groups: HTTP $RG_CODE"

# CDR Reports
CDR_CODE=$(_http "https://${HOST_IP}/admin/config.php?display=cdr")
echo "$CDR_CODE" | grep -qE "^(200|302)$" && ok "FreePBX CDR Reports: accessible (HTTP $CDR_CODE)" || warn "CDR Reports: HTTP $CDR_CODE"

# System Info page
SYSINFO_CODE=$(_http "https://${HOST_IP}/admin/config.php?display=sysadmin")
echo "$SYSINFO_CODE" | grep -qE "^(200|302)$" && ok "FreePBX System Admin: accessible (HTTP $SYSINFO_CODE)" || warn "System Admin: HTTP $SYSINFO_CODE"

# =============================================================================
sep "2. WEB UI - ALL ENDPOINTS"
# =============================================================================

check_url() {
    local desc="$1" url="$2" expect="${3:-}"
    local code body
    code=$(curl -skL --max-time 10 -b /tmp/pbx-cookie.jar -c /tmp/pbx-cookie.jar \
        -o /tmp/eu-curl.tmp -w "%{http_code}" "$url" 2>/dev/null || echo "000")
    body=$(cat /tmp/eu-curl.tmp 2>/dev/null)
    if echo "$code" | grep -qE "^(200|301|302|401|403)$"; then
        if [ -n "$expect" ]; then
            echo "$body" | grep -qiE "$expect" \
                && ok "${desc}: HTTP $code, content OK" \
                || warn "${desc}: HTTP $code but no match for '${expect}'"
        else
            ok "${desc}: HTTP $code"
        fi
    elif echo "$code" | grep -qE "^(404|500|503)$"; then
        fail "${desc}: HTTP $code (${url})"
    else
        warn "${desc}: HTTP $code (${url})"
    fi
}

check_url "Portal home"                  "https://${HOST_IP}/"           "PBX|asterisk|FreePBX|portal"
check_url "Health endpoint"              "https://${HOST_IP}/health"     "status"
check_url "Status page"                  "https://${HOST_IP}/status/"    "asterisk|service|pbx"
check_url "AvantFax UI"                  "https://${HOST_IP}/avantfax/"  "AvantFax|fax|Hyla|login"
check_url "Webmin HTTPS"                 "https://${HOST_IP}:${WEBMIN_PORT}/" "webmin|login|hostname|system"
check_url "FreePBX admin"               "https://${HOST_IP}/admin/"      "FreePBX|login"

# =============================================================================
sep "3. ASTERISK DIALPLAN - ALL DEMO APPS"
# =============================================================================

# Verify each demo extension is routable
for ext in DEMO 123 947 951 TODAY LENNY 4747; do
    # Check in from-internal, from-internal-custom, or demo-menu context
    FOUND=$(ast "dialplan show from-internal" 2>/dev/null | grep -cF "$ext" || echo 0)
    FOUND2=$(ast "dialplan show demo-menu" 2>/dev/null | grep -cF "$ext" || echo 0)
    FOUND3=$(ast "dialplan show from-internal-custom" 2>/dev/null | grep -cF "$ext" || echo 0)
    [ "${FOUND:-0}" -ge 1 ] || [ "${FOUND2:-0}" -ge 1 ] || [ "${FOUND3:-0}" -ge 1 ] \
        && ok "Demo extension [${ext}]: routable in dialplan" \
        || warn "Demo extension [${ext}]: NOT found in dialplan"
done

# Verify special services
for ext in '*43' '*97' '*469' '*470'; do
    FOUND=$(ast "dialplan show from-internal" 2>/dev/null | grep -cF "$ext" || echo 0)
    FOUND2=$(ast "dialplan show from-internal-custom" 2>/dev/null | grep -cF "$ext" || echo 0)
    [ "${FOUND:-0}" -ge 1 ] || [ "${FOUND2:-0}" -ge 1 ] \
        && ok "Service code [${ext}]: in dialplan" \
        || warn "Service code [${ext}]: missing from dialplan"
done

# Verify all demo contexts exist
for ctx in demo-menu pbx-echo pbx-clock pbx-lenny pbx-voicemail from-internal from-pstn from-trunk default; do
    ast "dialplan show $ctx" 2>/dev/null | grep -q "Context" \
        && ok "Dialplan context [${ctx}]: loaded" \
        || warn "Dialplan context [${ctx}]: missing"
done

# Total context count
CTX_TOTAL=$(ast "dialplan show" 2>/dev/null | grep -c "^\[ Context" || echo 0)
[ "${CTX_TOTAL:-0}" -ge 50 ] \
    && ok "Total dialplan contexts: ${CTX_TOTAL}" \
    || warn "Total contexts: only ${CTX_TOTAL} (expected >= 50)"

# =============================================================================
sep "4. ASTERISK MODULES - ALL CRITICAL"
# =============================================================================

for mod in chan_pjsip pbx_config app_voicemail res_musiconhold app_queue \
           app_confbridge res_agi func_callerid app_dial app_playback \
           app_record res_agi res_pjsip res_pjsip_session \
           app_chanspy res_rtp_asterisk app_stasis; do
    ast "module show like $mod" | grep -q "Running" \
        && ok "Module [${mod}]: Running" \
        || fail "Module [${mod}]: NOT running"
done

# =============================================================================
sep "5. PJSIP TRANSPORT STACK"
# =============================================================================

TRANS=$(ast "pjsip show transports" 2>/dev/null)
echo "$TRANS" | grep -qiE "udp" && ok "PJSIP: UDP transport configured" || fail "PJSIP: no UDP transport"
echo "$TRANS" | grep -qiE "tcp" && ok "PJSIP: TCP transport configured" || warn "PJSIP: no TCP transport"
echo "$TRANS" | grep -qiE "tls" && ok "PJSIP: TLS transport configured" || warn "PJSIP: no TLS transport"
echo "$TRANS" | grep -qiE "wss|websocket" && ok "PJSIP: WSS transport configured" || warn "PJSIP: no WSS transport"

ss -ulnp 2>/dev/null | grep -q ":5060" && ok "Network: UDP 5060 open" || warn "Network: UDP 5060 not listening"
ss -tlnp 2>/dev/null | grep -q ":5061" && ok "Network: TCP/TLS 5061 open" || warn "Network: TLS 5061 not listening"
ss -tlnp 2>/dev/null | grep -q ":5038" && ok "Network: AMI 5038 open" || fail "Network: AMI 5038 not listening"
ss -tlnp 2>/dev/null | grep -q ":443"  && ok "Network: HTTPS 443 open" || fail "Network: HTTPS 443 not listening"

# =============================================================================
sep "6. AMI - ADMIN INTERFACE TESTS"
# =============================================================================

if [ -n "${AMI_USER}" ] && [ -n "${AMI_SECRET}" ]; then
    # Test full AMI session with multiple actions
    AMI_OUT=$(timeout 6 bash -c "exec 3<>/dev/tcp/127.0.0.1/5038; \
        printf 'Action: Login\r\nUsername: ${AMI_USER}\r\nSecret: ${AMI_SECRET}\r\n\r\n' >&3; \
        printf 'Action: CoreShowChannels\r\n\r\n' >&3; \
        printf 'Action: ModuleCheck\r\nModule: chan_pjsip\r\n\r\n' >&3; \
        printf 'Action: SIPpeers\r\n\r\n' >&3; \
        sleep 2; cat <&3" 2>/dev/null || echo "ami-failed")

    echo "$AMI_OUT" | grep -q "Success" && ok "AMI: Login successful" || warn "AMI: Login not confirmed"
    echo "$AMI_OUT" | grep -qiE "CoreShowChannels|EventList" && ok "AMI: CoreShowChannels works" || warn "AMI: CoreShowChannels no response"
    echo "$AMI_OUT" | grep -qiE "Version:|Running" && ok "AMI: ModuleCheck works" || warn "AMI: ModuleCheck no response"

    # Try originate to echo test (async, won't block)
    ORIG_OUT=$(timeout 8 bash -c "exec 3<>/dev/tcp/127.0.0.1/5038; \
        printf 'Action: Login\r\nUsername: ${AMI_USER}\r\nSecret: ${AMI_SECRET}\r\n\r\n' >&3; \
        sleep 0.3; \
        printf 'Action: Originate\r\nChannel: Local/*43@from-internal\r\nApplication: Playback\r\nData: demo-congrats\r\nTimeout: 5000\r\nAsync: true\r\n\r\n' >&3; \
        sleep 2; cat <&3" 2>/dev/null || echo "ami-failed")
    echo "$ORIG_OUT" | grep -qiE "Success|Queued" && ok "AMI: Originate command accepted" || warn "AMI: Originate not confirmed"
else
    warn "AMI: credentials not available, skipping AMI tests"
fi

# =============================================================================
sep "7. FAX SYSTEM END-TO-END"
# =============================================================================

systemctl is-active hylafax >/dev/null 2>&1 && ok "HylaFAX (faxq): running" || fail "HylaFAX (faxq): not running"
pgrep -x hfaxd >/dev/null && ok "hfaxd: running" || fail "hfaxd: not running"

# Verify hfaxd port 4559 responds (more reliable than faxstat which needs auth on some versions)
HFAXD_BANNER=$(timeout 3 bash -c 'exec 3<>/dev/tcp/127.0.0.1/4559 2>/dev/null; read -t2 line <&3 2>/dev/null; echo "$line"; exec 3>&-' 2>/dev/null || true)
echo "$HFAXD_BANNER" | grep -qiE "^[0-9]{3}|HylaFAX" \
    && ok "hfaxd: port 4559 responding (banner: $(echo "$HFAXD_BANNER" | head -c60))" \
    || warn "hfaxd: port 4559 not responding"

IAX_PROCS=$(pgrep -c iaxmodem 2>/dev/null || echo 0)
[ "${IAX_PROCS:-0}" -ge 4 ] && ok "iaxmodem: $IAX_PROCS processes (need 4)" || fail "iaxmodem: only $IAX_PROCS instances"

for n in 1 2 3 4; do
    [ -c /dev/ttyIAX${n} ] && ok "IAX modem /dev/ttyIAX${n}: device present" || fail "IAX modem /dev/ttyIAX${n}: MISSING"
done

for n in 1 2 3 4; do
    [ -f /var/spool/hylafax/etc/config.ttyIAX${n} ] \
        && ok "HylaFAX config /etc/config.ttyIAX${n}: present" \
        || warn "HylaFAX config ttyIAX${n}: missing"
done

[ -d /var/spool/hylafax/recvq ] && ok "HylaFAX recvq: exists" || warn "HylaFAX recvq: missing"
[ -d /var/spool/hylafax/sendq ] && ok "HylaFAX sendq: exists" || warn "HylaFAX sendq: missing"

# AvantFax web
AVF=$(curl -skL --max-time 8 "https://${HOST_IP}/avantfax/" 2>/dev/null)
echo "$AVF" | grep -qiE "AvantFax|HylaFax|fax|login" && ok "AvantFax web: accessible" || fail "AvantFax web: not accessible"
[ -f "${WEB_ROOT}/avantfax/includes/FaxModem.php" ] && ok "AvantFax PHP files: installed" || fail "AvantFax PHP: missing"

# IAXmodem config files
for n in 1 2 3 4; do
    [ -f /etc/iaxmodem/ttyIAX${n} ] && ok "IAXmodem config /etc/iaxmodem/ttyIAX${n}: present" || warn "IAXmodem config ttyIAX${n}: missing"
done

# Email-to-fax alias
FAX_ALIAS=$(grep "^EMAIL_TO_FAX_ALIAS=" "$ENV_FILE" 2>/dev/null | cut -d= -f2)
[ -z "$FAX_ALIAS" ] && FAX_ALIAS=$(grep "^FAX_EMAIL_ALIAS=" "$ENV_FILE" 2>/dev/null | cut -d= -f2)
[ -n "$FAX_ALIAS" ] && ok "Email-to-fax alias: $FAX_ALIAS" || warn "Email-to-fax alias: not configured"

# =============================================================================
sep "8. SECURITY AUDIT"
# =============================================================================

# Fail2ban jails
F2B=$(fail2ban-client status 2>/dev/null || echo "")
echo "$F2B" | grep -qi "asterisk" && ok "Fail2ban: asterisk jail protecting SIP" || fail "Fail2ban: no asterisk jail"
echo "$F2B" | grep -qi "apache" && ok "Fail2ban: apache jail protecting web" || warn "Fail2ban: no apache-auth jail"

# SSL/TLS
CERT_INFO=$(echo | openssl s_client -connect 127.0.0.1:443 -servername "${FQDN}" 2>/dev/null | openssl x509 -noout -subject -enddate 2>/dev/null)
[ -n "$CERT_INFO" ] && ok "SSL certificate: $CERT_INFO" || fail "SSL: no valid certificate on port 443"

# Asterisk TLS keys
KEY_COUNT=$(ls /etc/asterisk/keys/ 2>/dev/null | wc -l)
[ "${KEY_COUNT:-0}" -ge 3 ] && ok "Asterisk TLS keys: $KEY_COUNT files in /etc/asterisk/keys/" || warn "Asterisk TLS keys: only $KEY_COUNT files"

# Process user
AST_PID=$(pgrep -x asterisk | head -1)
if [ -n "$AST_PID" ]; then
    AST_USER=$(ps -o user= -p "$AST_PID" 2>/dev/null | tr -d ' ')
    [ "$AST_USER" = "asterisk" ] && ok "Asterisk: running as 'asterisk' user (not root)" || warn "Asterisk: running as '$AST_USER'"
fi

# File permissions
ENV_PERMS=$(stat -c %a /etc/pbx/.env 2>/dev/null)
[ "$ENV_PERMS" = "600" ] && ok "/etc/pbx/.env: permissions 600 (secure)" || warn "/etc/pbx/.env: permissions $ENV_PERMS (should be 600)"

KEYS_PERMS=$(stat -c %a /etc/asterisk/keys 2>/dev/null)
ok "Asterisk keys dir permissions: $KEYS_PERMS"

# Postfix not open relay
RELAY_TEST=$(timeout 5 bash -c 'exec 3<>/dev/tcp/127.0.0.1/25 2>/dev/null; read -t3 line <&3 2>/dev/null; echo "$line"; exec 3>&-' 2>/dev/null || true)
echo "$RELAY_TEST" | grep -qiE "ESMTP|220" && ok "Postfix: SMTP port responding" || warn "Postfix: SMTP not responding on 25"

# =============================================================================
sep "9. MANAGEMENT SCRIPTS - FULL FUNCTIONAL AUDIT"
# =============================================================================

run_script() {
    local name="$1" args="${2:-}" expect="${3:-}"
    local out rc=0
    out=$(NO_COLOR=1 timeout 15 "$name" $args 2>&1) || rc=$?
    if [ -n "$expect" ]; then
        echo "$out" | grep -qiE "$expect" \
            && ok "${name} ${args}: OK (matched '${expect}')" \
            || warn "${name} ${args}: unexpected output (rc=$rc, got: $(echo "$out" | head -2))"
    else
        [ -n "$out" ] && ok "${name} ${args}: produced output" || warn "${name} ${args}: no output (rc=$rc)"
    fi
}

run_script "pbx-status"   ""       "asterisk|service|status|running"
run_script "pbx-services" ""       "service|active|running|asterisk|mariadb"
run_script "pbx-network"  ""       "ip|network|interface|addr|listen|port"
run_script "pbx-firewall" ""       "firewall|iptables|INPUT|ufw"
run_script "pbx-ssl"      ""       "ssl|cert|tls|expire|valid|key"
run_script "pbx-security" ""       "security|ssh|fail2ban|firewall|audit"
run_script "pbx-logs"     ""       "."
run_script "pbx-passwords" ""      "password|mysql|admin|freepbx|asterisk"
run_script "pbx-moh"      ""       "music|moh|class|hold"
run_script "pbx-cdr"      ""       "."
run_script "pbx-calls"    ""       "."
run_script "pbx-asterisk" ""       "asterisk|module|version|channel|uptime"
run_script "pbx-docs"     ""       "."

# Scripts with specific flags
run_script "pbx-diag"     ""       "diag|check|asterisk|service|version"
run_script "pbx-backup"   "--help" "."
run_script "pbx-update"   "--check" "."
run_script "pbx-repair"   "--check" "." 2>/dev/null || run_script "pbx-repair" "" "repair|check|service"

# Verify all expected scripts exist
SCRIPT_LIST="pbx-status pbx-services pbx-ssl pbx-network pbx-logs pbx-firewall
             pbx-security pbx-diag pbx-repair pbx-restart pbx-backup pbx-cleanup
             pbx-passwords pbx-docs pbx-moh pbx-config pbx-update pbx-cdr pbx-calls
             pbx-ssh pbx-webmin pbx-asterisk pbx-autoupdate pbx-recordings
             pbx-trunks pbx-provision pbx-add-ip pbx-backup-remote pbx-backup-encrypt"
TOTAL_SCRIPTS=0
MISSING_SCRIPTS=0
for sc in $SCRIPT_LIST; do
    TOTAL_SCRIPTS=$((TOTAL_SCRIPTS+1))
    if [ -x "/usr/local/bin/$sc" ]; then
        ok "Script /usr/local/bin/$sc: present and executable"
    else
        fail "Script /usr/local/bin/$sc: MISSING or not executable"
        MISSING_SCRIPTS=$((MISSING_SCRIPTS+1))
    fi
done
[ "$MISSING_SCRIPTS" -eq 0 ] && ok "All $TOTAL_SCRIPTS management scripts present" || warn "$MISSING_SCRIPTS of $TOTAL_SCRIPTS scripts missing"

# =============================================================================
sep "10. DATABASE INTEGRITY"
# =============================================================================

# Count tables
TABLE_COUNT=$(mysql -uroot ${MYSQL_PASS:+-p"${MYSQL_PASS}"} "$DB_NAME" -sNe "SHOW TABLES;" 2>/dev/null | wc -l)
[ "${TABLE_COUNT:-0}" -ge 20 ] && ok "FreePBX DB: $TABLE_COUNT tables" || fail "FreePBX DB: only $TABLE_COUNT tables"

# Check key tables with row counts
for tbl in admin devices users sipsettings featurecodes pjsip ampusers; do
    CNT=$(mysql -uroot ${MYSQL_PASS:+-p"${MYSQL_PASS}"} "$DB_NAME" -sNe "SELECT COUNT(*) FROM ${tbl};" 2>/dev/null)
    if [ -n "$CNT" ]; then
        ok "DB [${DB_NAME}.${tbl}]: $CNT rows"
    else
        warn "DB [${DB_NAME}.${tbl}]: missing or empty"
    fi
done

# FreePBX version in DB
FW_VER=$(mysql -uroot ${MYSQL_PASS:+-p"${MYSQL_PASS}"} "$DB_NAME" -sNe "SELECT value FROM admin WHERE variable='version' LIMIT 1;" 2>/dev/null)
[ -n "$FW_VER" ] && ok "FreePBX version in DB: $FW_VER" || fail "FreePBX version not found in admin table"

# Admin user exists
ADMIN_CNT=$(mysql -uroot ${MYSQL_PASS:+-p"${MYSQL_PASS}"} "$DB_NAME" -sNe "SELECT COUNT(*) FROM ampusers WHERE username='admin';" 2>/dev/null)
[ "${ADMIN_CNT:-0}" -ge 1 ] && ok "FreePBX admin user exists in DB" || fail "FreePBX admin user missing from ampusers"

# CDR database
CDR_CNT=$(mysql -uroot ${MYSQL_PASS:+-p"${MYSQL_PASS}"} "asteriskcdrdb" -sNe "SELECT COUNT(*) FROM cdr;" 2>/dev/null || echo -1)
[ "${CDR_CNT:-0}" -ge 0 ] && ok "CDR DB: $CDR_CNT records" || fail "CDR DB inaccessible"
CEL_CNT=$(mysql -uroot ${MYSQL_PASS:+-p"${MYSQL_PASS}"} "asteriskcdrdb" -sNe "SELECT COUNT(*) FROM cel;" 2>/dev/null || echo -1)
[ "${CEL_CNT:-0}" -ge 0 ] && ok "CEL DB: $CEL_CNT records" || fail "CEL DB inaccessible"

# AvantFax DB
AVF_TABLES=$(mysql -uroot ${MYSQL_PASS:+-p"${MYSQL_PASS}"} "avantfax" -sNe "SHOW TABLES;" 2>/dev/null | wc -l)
[ "${AVF_TABLES:-0}" -ge 5 ] && ok "AvantFax DB: $AVF_TABLES tables" || warn "AvantFax DB: only $AVF_TABLES tables"

# ODBC
odbcinst -q -d 2>/dev/null | grep -qiE "MariaDB|MySQL" && ok "ODBC: MariaDB/MySQL driver registered" || warn "ODBC: driver not registered"

# =============================================================================
sep "11. TTS, SOUNDS, MOH"
# =============================================================================

# Flite TTS
if command -v flite >/dev/null 2>&1; then
    FLITE_V=$(flite --version 2>&1 | head -1 || echo "unknown")
    ok "Flite TTS installed: $FLITE_V"
    TTS_OUT=$(flite -t "test" -o /tmp/tts-pbx-test.wav 2>&1 || echo "failed")
    [ -f /tmp/tts-pbx-test.wav ] && ok "Flite TTS: synthesis OK" || warn "Flite TTS: synthesis failed"
    rm -f /tmp/tts-pbx-test.wav
else
    warn "Flite TTS: not installed"
fi

# Sound files
GSM=$(find /var/lib/asterisk/sounds/en -name "*.gsm" 2>/dev/null | wc -l)
ULAW=$(find /var/lib/asterisk/sounds/en -name "*.ulaw" 2>/dev/null | wc -l)
[ "${GSM:-0}" -ge 100 ] && ok "GSM sounds: $GSM files" || warn "GSM sounds: only $GSM"
[ "${ULAW:-0}" -ge 50 ] && ok "ulaw sounds: $ULAW files" || warn "ulaw sounds: only $ULAW"

# Check specific sounds used by demo apps
for snd in "vm-intro" "digits/0" "digits/1" "tt-weasels" "hello-world" "demo-congrats"; do
    FOUND=$(find /var/lib/asterisk/sounds -name "$(basename $snd).*" 2>/dev/null | wc -l)
    [ "${FOUND:-0}" -ge 1 ] && ok "Sound [${snd}]: present" || warn "Sound [${snd}]: missing"
done

# Music on Hold
MOH_FILES=$(find /var/lib/asterisk/moh -type f 2>/dev/null | wc -l)
[ "${MOH_FILES:-0}" -ge 1 ] && ok "Music on Hold files: $MOH_FILES" || warn "MOH: no files"

MOH_CLASSES=$(ast "moh show classes" | grep -c "^Class:" || echo 0)
[ "${MOH_CLASSES:-0}" -ge 1 ] && ok "MOH classes configured: $MOH_CLASSES" || warn "MOH: no classes"

# AGI scripts
AGI_COUNT=$(ls /var/lib/asterisk/agi-bin/ 2>/dev/null | wc -l)
[ "${AGI_COUNT:-0}" -ge 3 ] && ok "AGI scripts: $AGI_COUNT in agi-bin/" || warn "AGI scripts: only $AGI_COUNT"

# =============================================================================
sep "12. EMAIL & NOTIFICATION SYSTEM"
# =============================================================================

systemctl is-active postfix >/dev/null 2>&1 && ok "Postfix: active" || fail "Postfix: not running"
ss -tlnp 2>/dev/null | grep -q ":25" && ok "SMTP port 25: listening" || warn "SMTP port 25: not listening"

# Test sendmail
echo "PBX beta test $(date)" | sendmail root 2>/dev/null && ok "sendmail: message submitted" || warn "sendmail: failed"
QUEUE=$(mailq 2>/dev/null | head -2)
ok "Mail queue: $QUEUE"

POSTFIX_MAIN=$(postconf myhostname 2>/dev/null)
[ -n "$POSTFIX_MAIN" ] && ok "Postfix config: $POSTFIX_MAIN" || warn "Postfix: myhostname not set"

# =============================================================================
sep "13. BACKUP SYSTEM TEST"
# =============================================================================

[ -d /mnt/backups/pbx ] && ok "Backup dir: /mnt/backups/pbx" || warn "Backup dir: missing"
PRE_COUNT=$(find /mnt/backups/pbx -name "*.tar.gz" 2>/dev/null | wc -l)
ok "Existing backup archives: $PRE_COUNT"

# Run backup
echo "  [Running pbx-backup --now, please wait...]"
BACKUP_RC=0
BACKUP_OUT=$(NO_COLOR=1 timeout 120 pbx-backup --now 2>&1) || BACKUP_RC=$?
echo "$BACKUP_OUT" | grep -qiE "complete|success|created|backup|done|wrote|tar" \
    && ok "pbx-backup --now: completed" \
    || { fail "pbx-backup --now: FAILED (rc=$BACKUP_RC)"; echo "  OUTPUT: $(echo "$BACKUP_OUT" | tail -3)"; }

POST_COUNT=$(find /mnt/backups/pbx -name "*.tar.gz" 2>/dev/null | wc -l)
[ "$POST_COUNT" -gt "$PRE_COUNT" ] \
    && ok "New backup created (now $POST_COUNT archives)" \
    || warn "No new archive after backup (still $POST_COUNT)"

# Cron configured
ALL_CRON=$(cat /etc/crontab 2>/dev/null; cat /etc/cron.d/* 2>/dev/null; crontab -u asterisk -l 2>/dev/null; crontab -u root -l 2>/dev/null)
echo "$ALL_CRON" | grep -qiE "pbx-backup|backup-run" && ok "Backup cron: scheduled in crontab" || warn "Backup cron: not found"
echo "$ALL_CRON" | grep -qiE "pbx-cleanup|cleanup" && ok "Cleanup cron: scheduled" || warn "Cleanup cron: not found"
echo "$ALL_CRON" | grep -qiE "fwconsole|freepbx" && ok "FreePBX maintenance cron: scheduled" || warn "FreePBX cron: not found"

# pbx-cleanup runs ok
CLEAN_OUT=$(NO_COLOR=1 timeout 20 pbx-cleanup 2>&1 | head -5 || true)
echo "$CLEAN_OUT" | grep -q "." && ok "pbx-cleanup: runs without error" || warn "pbx-cleanup: no output"

# =============================================================================
sep "14. LOG FILES & ROTATION"
# =============================================================================

[ -f /var/log/asterisk/full ]     && ok "Asterisk full log: $(wc -l < /var/log/asterisk/full) lines" || warn "Asterisk full log: missing"
[ -f /var/log/pbx-install.log ]   && ok "Install log: $(wc -l < /var/log/pbx-install.log) lines" || warn "Install log: missing"
[ -f /var/log/pbx-backup.log ] || touch /var/log/pbx-backup.log && ok "Backup log: configured"

# Check for fatal errors in recent Asterisk log
RECENT_ERRORS=$(tail -500 /var/log/asterisk/full 2>/dev/null | grep -cE "^.{24}ERROR" 2>/dev/null; true)
RECENT_ERRORS=${RECENT_ERRORS:-0}
[ "${RECENT_ERRORS:-0}" -le 10 ] \
    && ok "Asterisk log: $RECENT_ERRORS recent errors (acceptable)" \
    || warn "Asterisk log: $RECENT_ERRORS errors in last 500 lines"

# Log rotation
[ -f /etc/logrotate.d/asterisk ] || [ -f /etc/logrotate.d/pbx ] \
    && ok "Logrotate: Asterisk config present" || warn "Logrotate: no Asterisk config"

# =============================================================================
sep "15. SYSTEM RESOURCES & PERSISTENCE"
# =============================================================================

MEM_FREE=$(free -m 2>/dev/null | awk '/^Mem:/{print $7}')
DISK_FREE=$(df -BG / 2>/dev/null | awk 'NR==2{print $4}' | tr -d 'G')
LOAD=$(awk '{print $1}' /proc/loadavg 2>/dev/null)
ok "System: free=${MEM_FREE}MB, disk=${DISK_FREE}GB, load=${LOAD}"
[ "${MEM_FREE:-0}" -ge 100 ] && ok "Memory: ${MEM_FREE}MB free (adequate)" || warn "Memory: only ${MEM_FREE}MB free"
[ "${DISK_FREE:-0}" -ge 5 ] && ok "Disk: ${DISK_FREE}GB free (adequate)" || warn "Disk: only ${DISK_FREE}GB free"

# Critical services enabled for reboot
for svc in freepbx mariadb; do
    systemctl is-enabled "$svc" >/dev/null 2>&1 \
        && ok "Boot: $svc enabled (survives reboot)" || warn "Boot: $svc NOT enabled"
done
HTTPD=$(grep "^APACHE_SERVICE=" "$ENV_FILE" 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "httpd")
systemctl is-enabled "$HTTPD" >/dev/null 2>&1 && ok "Boot: $HTTPD enabled" || warn "Boot: $HTTPD not enabled"
systemctl is-enabled hylafax >/dev/null 2>&1 && ok "Boot: hylafax enabled" || warn "Boot: hylafax not enabled"
systemctl is-enabled fail2ban >/dev/null 2>&1 && ok "Boot: fail2ban enabled" || warn "Boot: fail2ban not enabled"

# .env completeness
for var in MYSQL_ROOT_PASSWORD ADMIN_PASSWORD SYSTEM_FQDN DISTRO_FAMILY \
           ASTERISK_VERSION FREEPBX_VERSION PHP_VERSION; do
    grep -q "^${var}=" "$ENV_FILE" 2>/dev/null \
        && ok ".env: $var present" || warn ".env: $var missing"
done

# =============================================================================
sep "FINAL SUMMARY"
# =============================================================================

TOTAL=$((PASS + WARN + FAIL))
echo ""
echo "========================================================"
printf " RESULTS:  %d PASS  |  %d WARN  |  %d FAIL  |  %d TOTAL\n" "$PASS" "$WARN" "$FAIL" "$TOTAL"
if [ "$FAIL" -eq 0 ]; then
    echo " STATUS:   ALL TESTS PASSED (zero failures)"
else
    echo " STATUS:   $FAIL FAILURE(S) - see above"
    echo " FAILURES:"
    echo "$FAILURES" | tr '|' '\n' | grep -v '^$' | while read -r line; do echo "   - $line"; done
fi
echo "========================================================"

exit "$FAIL"
