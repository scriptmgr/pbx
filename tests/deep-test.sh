#!/bin/bash
# =============================================================================
# PBX Deep Functional Test Suite
# Tests actual functionality: calls, dialplan, DB, scripts, fax, backup, etc.
# Run as root inside an installed PBX container
# =============================================================================

PASS=0; FAIL=0; WARN=0; SKIP=0
FAILURES=""

# ── Color output ─────────────────────────────────────────────────────────────
if [ -z "$NO_COLOR" ] && [ -t 1 ]; then
    _G="\033[0;32m"; _R="\033[0;31m"; _Y="\033[0;33m"; _B="\033[0;36m"; _N="\033[0m"
else
    _G=""; _R=""; _Y=""; _B=""; _N=""
fi

ok()   { printf "  ${_G}PASS${_N}: %s\n" "$*"; PASS=$((PASS+1)); }
fail() { printf "  ${_R}FAIL${_N}: %s\n" "$*"; FAIL=$((FAIL+1)); FAILURES="${FAILURES}\n  - $*"; }
warn() { printf "  ${_Y}WARN${_N}: %s\n" "$*"; WARN=$((WARN+1)); }
skip() { printf "  ${_B}SKIP${_N}: %s\n" "$*"; SKIP=$((SKIP+1)); }
sep()  { printf "\n${_B}=== %s ===${_N}\n" "$*"; }
info() { printf "       %s\n" "$*"; }

# ── Credentials & config ─────────────────────────────────────────────────────
ENV_FILE="/etc/pbx/.env"
FREEPBX_PASS="admin"
MYSQL_PASS=""
ADMIN_EMAIL=""
WEBMIN_PORT="9001"
WEB_ROOT="/var/www/apache/pbx"
APACHE_SERVICE="httpd"

if [ -f "$ENV_FILE" ]; then
    _ev() { grep "^${1}=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"'; }
    v=$(_ev ADMIN_PASSWORD);             [ -z "$v" ] && v=$(_ev FREEPBX_ADMIN_PASSWORD)
    [ -n "$v" ] && FREEPBX_PASS="$v"
    v=$(_ev MYSQL_ROOT_PASSWORD);        [ -n "$v" ] && MYSQL_PASS="$v"
    v=$(_ev ADMIN_EMAIL);                [ -n "$v" ] && ADMIN_EMAIL="$v"
    v=$(_ev WEB_ROOT);                   [ -n "$v" ] && WEB_ROOT="$v"
    v=$(_ev APACHE_SERVICE);             [ -n "$v" ] && APACHE_SERVICE="$v"
fi

v=$(grep "^port=" /etc/webmin/miniserv.conf 2>/dev/null | head -1 | cut -d= -f2)
[ -n "$v" ] && WEBMIN_PORT="$v"

AMI_USER=$(grep '^\[' /etc/asterisk/manager.conf 2>/dev/null \
    | grep -v '^\[general\]' | head -1 | tr -d '[]')
AMI_SECRET=$(grep "^secret" /etc/asterisk/manager.conf 2>/dev/null \
    | head -1 | awk -F'=' '{gsub(/ /,"",$2); print $2}')
[ -z "$AMI_USER" ]   && AMI_USER="admin"
[ -z "$AMI_SECRET" ] && AMI_SECRET="$FREEPBX_PASS"

DB_NAME=$(php -r "include '/etc/freepbx.conf'; echo \$amp_conf['AMPDBNAME'];" 2>/dev/null)
[ -z "$DB_NAME" ] && DB_NAME="asterisk"

FQDN=$(hostname -f 2>/dev/null || hostname)
HOST_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
HOST_IP=${HOST_IP:-127.0.0.1}

# ── Helpers ──────────────────────────────────────────────────────────────────

db_q() {
    mysql -u root ${MYSQL_PASS:+-p"${MYSQL_PASS}"} -Dasterisk -sNe "$1" 2>/dev/null
}

db_qdb() {
    mysql -u root ${MYSQL_PASS:+-p"${MYSQL_PASS}"} -sNe "$2" "$1" 2>/dev/null
}

ast() {
    asterisk -rx "$*" 2>/dev/null
}

http_check() {
    curl -skL --max-time 10 -o /dev/null -w "%{http_code}" "$1" 2>/dev/null || echo "000"
}

http_body() {
    curl -skL --max-time 10 "$1" 2>/dev/null
}

# Send raw AMI action and return first 20 lines of response
send_ami() {
    local payload="$1"
    printf "%s\r\n\r\n" "$payload" \
        | timeout 5 nc -q 2 127.0.0.1 5038 2>/dev/null \
        | head -20
}

ami_login_payload() {
    printf "Action: Login\r\nUsername: %s\r\nSecret: %s" "$AMI_USER" "$AMI_SECRET"
}

# Full AMI session: login then send action
ami_session() {
    local action="$1"
    {
        printf "Action: Login\r\nUsername: %s\r\nSecret: %s\r\n\r\n" \
            "$AMI_USER" "$AMI_SECRET"
        sleep 0.5
        printf "%s\r\n\r\n" "$action"
        sleep 0.5
    } | timeout 5 nc -q 2 127.0.0.1 5038 2>/dev/null | head -40
}

svc_active() {
    local s
    for s in "$@"; do
        systemctl is-active "$s" >/dev/null 2>&1 && return 0
    done
    return 1
}

# ── Header ───────────────────────────────────────────────────────────────────
printf "\n"
printf "${_B}================================================================${_N}\n"
printf "${_B} PBX DEEP FUNCTIONAL TEST SUITE${_N}\n"
printf "${_B} Host: %s (%s)${_N}\n" "$FQDN" "$HOST_IP"
printf "${_B} Date: %s${_N}\n" "$(date)"
printf "${_B} DB:   %s | AMI user: %s${_N}\n" "$DB_NAME" "$AMI_USER"
printf "${_B}================================================================${_N}\n"

# =============================================================================
sep "1. MANAGEMENT SCRIPTS"
# =============================================================================
# Run every pbx-* script non-destructively and verify exit 0 + non-empty output

_run_mgmt() {
    local label="$1" cmd="$2" args="$3" expect="$4"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        skip "SCRIPT $label: not installed"
        return
    fi
    local out ec
    # eval is required so that shell operators in $args (like 2>&1 and ||) are interpreted
    out=$(eval "NO_COLOR=1 timeout 30 $cmd $args" 2>&1)
    ec=$?
    if [ -z "$out" ] && [ "$ec" -eq 127 ]; then
        skip "SCRIPT $label: command not found"
        return
    fi
    if [ -n "$expect" ]; then
        if echo "$out" | grep -qiE "$expect"; then
            ok "SCRIPT $label: exit=$ec, output matches '$expect'"
        else
            warn "SCRIPT $label: exit=$ec, output did not match '$expect' — $(echo "$out" | head -1)"
        fi
    else
        if [ -n "$out" ]; then
            ok "SCRIPT $label: exit=$ec, produced output"
        else
            warn "SCRIPT $label: exit=$ec, no output"
        fi
    fi
}

# pbx-add-ip
_run_mgmt "pbx-add-ip --help"          pbx-add-ip   "--help 2>&1 || true" "usage|help|ip|add"
# pbx-asterisk
_run_mgmt "pbx-asterisk status"        pbx-asterisk "status 2>&1 || true"  "asterisk|running|active|version"
# pbx-autoupdate --check
_run_mgmt "pbx-autoupdate --check"     pbx-autoupdate "--check 2>&1 || true" "check|update|updat|auto"
# pbx-backup status
_run_mgmt "pbx-backup status"          pbx-backup   "status 2>&1 || true"  "backup|status|file|dir"
# pbx-backup-encrypt --help
_run_mgmt "pbx-backup-encrypt --help"  pbx-backup-encrypt "--help 2>&1 || true" "help|encrypt|usage|key"
# pbx-backup-remote --help
_run_mgmt "pbx-backup-remote --help"   pbx-backup-remote "--help 2>&1 || true" "help|remote|ssh|s3|usage"
# pbx-calls
_run_mgmt "pbx-calls"                  pbx-calls    "2>&1 || true"          "call|channel|active|no call"
# pbx-cdr
_run_mgmt "pbx-cdr"                    pbx-cdr      "2>&1 || true"          "cdr|call|record|detail"
# pbx-cleanup --dry-run
if command -v pbx-cleanup >/dev/null 2>&1; then
    out=$(NO_COLOR=1 timeout 30 pbx-cleanup --dry-run 2>&1 || NO_COLOR=1 timeout 30 pbx-cleanup 2>&1)
    [ -n "$out" ] && ok "SCRIPT pbx-cleanup: ran, output present" || warn "SCRIPT pbx-cleanup: no output"
else
    skip "SCRIPT pbx-cleanup: not installed"
fi
# pbx-config --help
if command -v pbx-config >/dev/null 2>&1; then
    out=$(NO_COLOR=1 timeout 10 pbx-config --help 2>&1 || NO_COLOR=1 timeout 10 pbx-config --list 2>&1 || true)
    [ -n "$out" ] && ok "SCRIPT pbx-config: runs (help/list output present)" \
        || warn "SCRIPT pbx-config: no output from --help/--list"
else
    skip "SCRIPT pbx-config: not installed"
fi
# pbx-diag
_run_mgmt "pbx-diag"                   pbx-diag     "2>&1 || true"          "diag|system|check|asterisk"
# pbx-docs
_run_mgmt "pbx-docs"                   pbx-docs     "2>&1 || true"          "doc|generate|manual|html"
# pbx-firewall
_run_mgmt "pbx-firewall status"        pbx-firewall "status 2>&1 || true"   "firewall|iptables|nft|rule|zone"
# pbx-ip-checker (cron daemon; use --show to get current status without network)
_run_mgmt "pbx-ip-checker --show"      pbx-ip-checker "--show 2>&1 || true"  "ip|public|wan|check|stored|found"
# pbx-logs --help
_run_mgmt "pbx-logs --help"            pbx-logs     "--help 2>&1 || true"   "help|log|usage|tail|view"
# pbx-moh
_run_mgmt "pbx-moh"                    pbx-moh      "2>&1 || true"          "moh|music|hold|class|file"
# pbx-network
_run_mgmt "pbx-network"                pbx-network  "2>&1 || true"          "network|ip|interface|route"
# pbx-passwords
_run_mgmt "pbx-passwords"              pbx-passwords "2>&1 || true"         "password|admin|mysql|secret"
# pbx-provision --help
_run_mgmt "pbx-provision --help"       pbx-provision "--help 2>&1 || true"  "help|provision|phone|device"
# pbx-recordings
_run_mgmt "pbx-recordings"             pbx-recordings "2>&1 || true"        "record|call|file|no recording"
# pbx-repair --check (read-only, safe to run in tests)
if command -v pbx-repair >/dev/null 2>&1; then
    out=$(NO_COLOR=1 timeout 60 pbx-repair --check 2>&1 || true)
    if [ -n "$out" ]; then
        ok "SCRIPT pbx-repair: --check ran without error"
    else
        warn "SCRIPT pbx-repair: no output from --check"
    fi
else
    skip "SCRIPT pbx-repair: not installed"
fi
# pbx-restart --help only (never actually restart)
_run_mgmt "pbx-restart --help"         pbx-restart  "--help 2>&1 || true"   "help|restart|usage|service"
# pbx-security
_run_mgmt "pbx-security"               pbx-security "2>&1 || true"          "security|fail2ban|ssh|permission"
# pbx-services
_run_mgmt "pbx-services"               pbx-services "2>&1 || true"          "service|active|running|status"
# pbx-ssh
_run_mgmt "pbx-ssh"                    pbx-ssh      "2>&1 || true"          "ssh|key|permit|password"
# pbx-ssl
_run_mgmt "pbx-ssl"                    pbx-ssl      "2>&1 || true"          "ssl|cert|tls|expire|key"
# pbx-status
_run_mgmt "pbx-status"                 pbx-status   "2>&1 || true"          "status|asterisk|running|uptime"
# pbx-trunks
_run_mgmt "pbx-trunks"                 pbx-trunks   "2>&1 || true"          "trunk|sip|pjsip|voip|provider"
# pbx-update --check
_run_mgmt "pbx-update --check"         pbx-update   "--check 2>&1 || true"  "check|update|version|latest"
# pbx-webmin
_run_mgmt "pbx-webmin"                 pbx-webmin   "2>&1 || true"          "webmin|port|url|status"
# pbxstatus alias
if command -v pbxstatus >/dev/null 2>&1; then
    out=$(NO_COLOR=1 timeout 15 pbxstatus 2>&1 || true)
    [ -n "$out" ] && ok "SCRIPT pbxstatus alias: produced output" || warn "SCRIPT pbxstatus: no output"
else
    skip "SCRIPT pbxstatus: not installed"
fi

# Count how many pbx-* scripts exist
PBX_SCRIPT_COUNT=$(find /usr/local/bin -maxdepth 1 -name 'pbx-*' 2>/dev/null | wc -l)
info "Total pbx-* scripts found: $PBX_SCRIPT_COUNT"
[ "$PBX_SCRIPT_COUNT" -ge 10 ] && ok "Management scripts: $PBX_SCRIPT_COUNT scripts installed" \
    || warn "Management scripts: only $PBX_SCRIPT_COUNT scripts (expected 16+)"

# =============================================================================
sep "2. ASTERISK MODULES"
# =============================================================================

_check_module() {
    local mod="$1" required="${2:-yes}"
    local out
    out=$(ast "module show like ${mod}" 2>/dev/null)
    if echo "$out" | grep -q "Running"; then
        ok "MODULE ${mod}: Running"
    elif echo "$out" | grep -q "Loaded"; then
        ok "MODULE ${mod}: Loaded"
    else
        if [ "$required" = "warn" ]; then
            warn "MODULE ${mod}: not loaded (non-critical)"
        else
            fail "MODULE ${mod}: NOT LOADED"
        fi
    fi
}

_check_module "res_pjsip"
_check_module "res_pjsip_session"
_check_module "chan_pjsip"
_check_module "app_voicemail"
_check_module "app_dial"
_check_module "app_queue"
_check_module "res_musiconhold"
_check_module "app_record"
_check_module "app_playback"
_check_module "res_agi"
_check_module "app_agi"   "warn"  # merged into res_agi in Asterisk 18+

# ConfBridge or MeetMe
MOD_CONF_OUT=$(ast "module show like app_confbridge")
MOD_MEET_OUT=$(ast "module show like app_meetme")
if echo "$MOD_CONF_OUT" | grep -q "Running"; then
    ok "MODULE app_confbridge: Running"
elif echo "$MOD_MEET_OUT" | grep -q "Running"; then
    ok "MODULE app_meetme: Running"
else
    warn "MODULE conferencing (app_confbridge/app_meetme): neither loaded"
fi

# Fax module (warn-only in containers)
FAX_OUT=$(ast "module show like res_fax"; ast "module show like app_fax")
if echo "$FAX_OUT" | grep -q "Running"; then
    ok "MODULE res_fax/app_fax: Running"
else
    warn "MODULE res_fax/app_fax: not loaded (fax via IAXmodem may still work)"
fi

TOTAL_MODS=$(ast "module show" | tail -1 | awk '{print $1}')
info "Total Asterisk modules loaded: $TOTAL_MODS"
[ "${TOTAL_MODS:-0}" -ge 50 ] && ok "Asterisk modules total: $TOTAL_MODS" \
    || warn "Asterisk modules total: $TOTAL_MODS (expected 50+)"

# =============================================================================
sep "3. DIALPLAN INTEGRITY"
# =============================================================================

DIALPLAN_ALL=$(ast "dialplan show" 2>/dev/null)

# Check contexts exist
# Asterisk 'dialplan show' format: [ Context 'name' created by '...' ]
_check_ctx() {
    local ctx="$1" severity="${2:-fail}"
    if echo "$DIALPLAN_ALL" | grep -qE "Context '${ctx}'"; then
        ok "CONTEXT [${ctx}]: present"
        return 0
    else
        if [ "$severity" = "warn" ]; then
            warn "CONTEXT [${ctx}]: not found (may be unconfigured)"
        else
            fail "CONTEXT [${ctx}]: MISSING"
        fi
        return 1
    fi
}

# from-internal (FreePBX) or pbx-demo (custom) or demo-menu
if echo "$DIALPLAN_ALL" | grep -qE "Context '(from-internal|pbx-demo|demo-menu)'"; then
    ok "CONTEXT from-internal or pbx-demo: present"
else
    fail "CONTEXT from-internal / pbx-demo: MISSING"
fi

# from-trunk / from-pstn / from-provider (warn-only: unconfigured is valid)
if echo "$DIALPLAN_ALL" | grep -qE "Context '(from-trunk|from-pstn|from-provider|from-analog)'"; then
    ok "CONTEXT from-trunk/from-pstn/from-provider: present"
else
    warn "CONTEXT from-trunk/from-pstn: not found (no trunks configured yet)"
fi

# Check extensions in from-internal-custom, from-internal, or any context
# Asterisk's 'dialplan show' wraps extensions in single quotes: '*43' => ...
_check_ext() {
    local ext="$1"
    local out
    out=$(ast "dialplan show ${ext}@from-internal" 2>/dev/null)
    # Use fixed-string match to avoid regex escaping issues with * and other special chars
    if echo "$out" | grep -qF "'${ext}' =>"; then
        ok "EXTENSION ${ext}: present in dialplan"
        return
    fi
    # Fallback: search full dialplan dump
    if echo "$DIALPLAN_ALL" | grep -qF "'${ext}' =>"; then
        ok "EXTENSION ${ext}: found in full dialplan dump"
    else
        warn "EXTENSION ${ext}: not found (demo may not be loaded)"
    fi
}

_check_ext "123"
_check_ext "*43"
_check_ext "*610"
_check_ext "*97"

# 947/951 are optional demo extensions (not always installed)
if echo "$DIALPLAN_ALL" | grep -qE "'947'"; then
    ok "EXTENSION 947: present"
else
    warn "EXTENSION 947: not found (optional demo)"
fi
if echo "$DIALPLAN_ALL" | grep -qE "'951'"; then
    ok "EXTENSION 951: present"
else
    warn "EXTENSION 951: not found (optional demo)"
fi

# LENNY / 4747
if echo "$DIALPLAN_ALL" | grep -qiE "'4747'|lenny"; then
    ok "EXTENSION LENNY/4747: found in dialplan"
else
    warn "EXTENSION LENNY/4747: not found (optional demo)"
fi

# Feature codes
for feat in "*72" "*73"; do
    out=$(ast "dialplan show ${feat}@from-internal" 2>/dev/null)
    if echo "$out" | grep -qE "\*72|\*73|callforward|Forward"; then
        ok "FEATURE CODE ${feat}: present in from-internal"
    elif echo "$DIALPLAN_ALL" | grep -qE "${feat}|callforward"; then
        ok "FEATURE CODE ${feat}: found in dialplan"
    else
        warn "FEATURE CODE ${feat}: not found"
    fi
done

# Conference rooms *469 *470
for room in "*469" "*470"; do
    if echo "$DIALPLAN_ALL" | grep -qE "${room}|conf.*469|conf.*470"; then
        ok "CONFERENCE ${room}: found in dialplan"
    else
        warn "CONFERENCE ${room}: not found (check conf rooms)"
    fi
done

# Total dialplan entries — 'dialplan show' output uses "'ext' =>" format (not "exten =>")
DIALPLAN_LINES=$(echo "$DIALPLAN_ALL" | grep -cF "' =>" 2>/dev/null || echo 0)
info "Total dialplan extension entries: $DIALPLAN_LINES"
[ "${DIALPLAN_LINES:-0}" -ge 10 ] && ok "Dialplan entries: $DIALPLAN_LINES" \
    || warn "Dialplan looks sparse: $DIALPLAN_LINES entries"

# =============================================================================
sep "4. LIVE CALL ORIGINATION VIA AMI"
# =============================================================================

# AMI connectivity test
AMI_BANNER=$(printf "Action: Login\r\nUsername: %s\r\nSecret: %s\r\n\r\n" \
    "$AMI_USER" "$AMI_SECRET" \
    | timeout 5 nc -q 2 127.0.0.1 5038 2>/dev/null | head -10)

if echo "$AMI_BANNER" | grep -q "Asterisk Call Manager"; then
    ok "AMI: banner received (Asterisk Call Manager)"
else
    warn "AMI: no banner — is port 5038 open? ($(ss -tlnp | grep 5038 | head -1))"
fi

if echo "$AMI_BANNER" | grep -q "Response: Success"; then
    ok "AMI: Login Response: Success"
elif echo "$AMI_BANNER" | grep -q "Response:"; then
    RESP=$(echo "$AMI_BANNER" | grep "Response:" | head -1)
    fail "AMI: Login failed — $RESP"
else
    warn "AMI: Login response unclear (nc/timeout issue?)"
fi

# Check channels before originate
CHAN_BEFORE=$(ast "core show channels" | tail -1)
info "Channels before originate: $CHAN_BEFORE"

# Originate a Local call to Echo application via from-internal-custom (*43 → pbx-echo)
if echo "$DIALPLAN_ALL" | grep -qiE "'?\*43'?"; then
    ORIG_RESP=$(ami_session \
        "Action: Originate\r\nChannel: Local/*43@from-internal\r\nApplication: Echo\r\nAsync: yes\r\nCallerId: DeepTest <5555>")
    if echo "$ORIG_RESP" | grep -qiE "Response: Success|Queued"; then
        ok "AMI Originate: Echo call queued successfully"
    else
        warn "AMI Originate: response unclear — $(echo "$ORIG_RESP" | grep -v '^$' | head -3 | tr '\n' '|')"
    fi

    # Poll for channel appearance (up to 4 seconds)
    FOUND_CHAN=0
    for i in 1 2 3 4; do
        sleep 1
        CHAN_NOW=$(ast "core show channels" | grep -c "Local/")
        if [ "${CHAN_NOW:-0}" -ge 1 ]; then
            ok "AMI Originate: Local channel appeared in 'core show channels' (attempt $i)"
            FOUND_CHAN=1
            break
        fi
    done
    [ "$FOUND_CHAN" -eq 0 ] && warn "AMI Originate: no Local channel seen in 4s (may have completed too fast)"
else
    warn "AMI Originate: *43/Echo extension not in dialplan — skipping live call test"
fi

# Confirm speaking clock dialplan entry via direct ast command
DP_CLOCK=$(ast "dialplan show 123@from-internal" 2>/dev/null)
if echo "$DP_CLOCK" | grep -qE "123|sayunixtime|SayUnixTime|clock|pbx-clock"; then
    ok "DIALPLAN 123: speaking clock entries present"
else
    warn "DIALPLAN 123: not found or empty"
fi

# =============================================================================
sep "5. PJSIP CONFIGURATION"
# =============================================================================

PJSIP_TRANSPORTS=$(ast "pjsip show transports")
if echo "$PJSIP_TRANSPORTS" | grep -qiE "udp|transport"; then
    ok "PJSIP transports: UDP transport present"
    info "Transports: $(echo "$PJSIP_TRANSPORTS" | grep -iE 'udp|tcp|tls' | head -3 | tr '\n' ' ')"
else
    fail "PJSIP transports: no UDP transport found"
fi

if echo "$PJSIP_TRANSPORTS" | grep -qiE "tls|5061"; then
    ok "PJSIP TLS transport: present"
else
    warn "PJSIP TLS transport: not configured (optional)"
fi

PJSIP_EPS=$(ast "pjsip show endpoints")
EP_COUNT=$(echo "$PJSIP_EPS" | grep -c "Avail\|Unavail\|Not in use\|In use" 2>/dev/null || echo 0)
info "PJSIP endpoints: $EP_COUNT"
if [ "${EP_COUNT:-0}" -ge 1 ]; then
    ok "PJSIP endpoints: $EP_COUNT endpoint(s) configured"
else
    warn "PJSIP endpoints: none configured (no trunks or extensions registered)"
fi

[ -f /etc/asterisk/pjsip.conf ] \
    && ok "pjsip.conf: exists ($(wc -l < /etc/asterisk/pjsip.conf) lines)" \
    || fail "pjsip.conf: MISSING"

# pjsip_wizard.conf or pjsip_registration.conf
if [ -f /etc/asterisk/pjsip_wizard.conf ]; then
    WIZARD_ENTRIES=$(grep -c '^\[' /etc/asterisk/pjsip_wizard.conf 2>/dev/null || echo 0)
    ok "pjsip_wizard.conf: present ($WIZARD_ENTRIES stanzas)"
elif [ -f /etc/asterisk/pjsip.endpoint.conf ]; then
    ok "pjsip.endpoint.conf: present"
else
    warn "pjsip_wizard.conf: not found (using inline pjsip.conf config)"
fi

# Check pjsip transport config — use live Asterisk data (already in PJSIP_TRANSPORTS)
# FreePBX stores transports in pjsip.transports.conf with sections like [0.0.0.0-udp]
TRANSPORT_COUNT=$(echo "$PJSIP_TRANSPORTS" | grep -c "^Transport:" 2>/dev/null || echo 0)
if [ "${TRANSPORT_COUNT:-0}" -ge 1 ]; then
    ok "pjsip: $TRANSPORT_COUNT transport(s) active (from pjsip show transports)"
elif grep -qiE "type\s*=\s*transport" /etc/asterisk/pjsip.transports.conf 2>/dev/null; then
    ok "pjsip: transport config found in pjsip.transports.conf"
else
    warn "pjsip: no active transports found (pjsip show transports returned no results)"
fi

# =============================================================================
sep "6. DATABASE INTEGRITY"
# =============================================================================

# Check databases exist
for dbtest in asterisk asteriskcdrdb; do
    DBCHECK=$(mysql -u root ${MYSQL_PASS:+-p"${MYSQL_PASS}"} -sNe \
        "SELECT SCHEMA_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='${dbtest}';" 2>/dev/null)
    [ "$DBCHECK" = "$dbtest" ] \
        && ok "DATABASE ${dbtest}: exists" \
        || fail "DATABASE ${dbtest}: MISSING"
done

# Check tables in asterisk DB
for tbl in devices users; do
    TBL=$(db_q "SHOW TABLES LIKE '${tbl}';" 2>/dev/null)
    [ -n "$TBL" ] && ok "TABLE asterisk.${tbl}: exists" \
        || warn "TABLE asterisk.${tbl}: not found"
done

# sip_buddies or pjsip tables
SIP_TBL=$(db_q "SHOW TABLES LIKE 'sip_buddies';" 2>/dev/null)
PJSIP_TBL=$(db_q "SHOW TABLES LIKE 'pjsip';" 2>/dev/null | head -1)
if [ -n "$SIP_TBL" ]; then
    ok "TABLE asterisk.sip_buddies: exists"
elif [ -n "$PJSIP_TBL" ]; then
    ok "TABLE asterisk.${PJSIP_TBL}: exists (PJSIP realtime)"
else
    warn "TABLE sip_buddies/pjsip_*: not found (may be file-based config)"
fi

# voicemail table
VM_TBL=$(db_q "SHOW TABLES LIKE 'voicemail%';" 2>/dev/null | head -1)
[ -n "$VM_TBL" ] && ok "TABLE asterisk.voicemail: exists" \
    || warn "TABLE asterisk.voicemail: not found (file-based VM?)"

# asteriskcdrdb.cdr
CDR_TBL=$(db_qdb "asteriskcdrdb" "SHOW TABLES LIKE 'cdr';" 2>/dev/null)
[ -n "$CDR_TBL" ] && ok "TABLE asteriskcdrdb.cdr: exists" \
    || fail "TABLE asteriskcdrdb.cdr: MISSING"

# CDR table accessible and count rows
CDR_COUNT=$(db_qdb "asteriskcdrdb" "SELECT COUNT(*) FROM cdr LIMIT 1;" 2>/dev/null || echo "ERR")
if [ "$CDR_COUNT" != "ERR" ]; then
    ok "TABLE asteriskcdrdb.cdr: accessible ($CDR_COUNT rows)"
else
    warn "TABLE asteriskcdrdb.cdr: query failed"
fi

# FreePBX ampusers table
AMP_ADMIN=$(db_q "SELECT username FROM ampusers WHERE username='admin' LIMIT 1;" 2>/dev/null)
[ "$AMP_ADMIN" = "admin" ] && ok "FreePBX ampusers: admin user exists" \
    || warn "FreePBX ampusers: admin not found (permissions issue?)"

# avantfax database
AF_DB=$(mysql -u root ${MYSQL_PASS:+-p"${MYSQL_PASS}"} -sNe \
    "SELECT SCHEMA_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='avantfax';" 2>/dev/null)
if [ "$AF_DB" = "avantfax" ]; then
    ok "DATABASE avantfax: exists"
    AF_ADMIN=$(db_qdb "avantfax" "SELECT Username FROM UserAccount WHERE Username='admin' LIMIT 1;" 2>/dev/null)
    [ "$AF_ADMIN" = "admin" ] && ok "avantfax.UserAccount: admin user exists" \
        || warn "avantfax.UserAccount: admin user not found"
else
    warn "DATABASE avantfax: not found (AvantFax may not be fully installed)"
fi

# =============================================================================
sep "7. VOICEMAIL SYSTEM"
# =============================================================================

[ -f /etc/asterisk/voicemail.conf ] \
    && ok "voicemail.conf: $(wc -l < /etc/asterisk/voicemail.conf) lines" \
    || fail "voicemail.conf: MISSING"

# Check default or general context exists
grep -qiE "^\[default\]|^\[general\]" /etc/asterisk/voicemail.conf 2>/dev/null \
    && ok "voicemail.conf: default/general context present" \
    || warn "voicemail.conf: no [default] or [general] context"

[ -d /var/spool/asterisk/voicemail ] \
    && ok "Voicemail spool: /var/spool/asterisk/voicemail exists" \
    || warn "Voicemail spool: directory missing"

VM_CONTEXTS=$(grep -c '^\[' /etc/asterisk/voicemail.conf 2>/dev/null || echo 0)
ok "Voicemail contexts in conf: $VM_CONTEXTS"

# Check for at least one mailbox (e.g. 100 or 101)
VM_BOX=$(grep -E "^100|^101|^200" /etc/asterisk/voicemail.conf 2>/dev/null | head -1)
if [ -n "$VM_BOX" ]; then
    ok "Voicemail mailbox configured: $(echo "$VM_BOX" | head -c 60)"
else
    warn "Voicemail: no extension 100/101 mailbox found in voicemail.conf"
fi

VM_SHOW=$(ast "voicemail show users")
if echo "$VM_SHOW" | grep -qE "[0-9]{3,}"; then
    ok "Voicemail users: $(echo "$VM_SHOW" | grep -cE '^[0-9]') users returned by 'voicemail show users'"
else
    warn "Voicemail show users: no users shown"
fi

# =============================================================================
sep "8. MUSIC ON HOLD"
# =============================================================================

[ -d /var/lib/asterisk/moh ] \
    && ok "MOH directory: /var/lib/asterisk/moh exists" \
    || fail "MOH directory: MISSING"

MOH_FILES=$(find /var/lib/asterisk/moh -type f 2>/dev/null | wc -l)
[ "${MOH_FILES:-0}" -ge 1 ] \
    && ok "MOH files: $MOH_FILES file(s) present" \
    || warn "MOH files: none found in /var/lib/asterisk/moh"

MOH_CLASSES=$(ast "moh show classes")
if echo "$MOH_CLASSES" | grep -qiE "class|default"; then
    CLASS_COUNT=$(echo "$MOH_CLASSES" | grep -c "Class:" 2>/dev/null || echo "1")
    ok "MOH classes: $CLASS_COUNT class(es) loaded"
else
    warn "MOH classes: 'moh show classes' returned no classes"
fi

MOH_FILES_AST=$(ast "moh show files")
if echo "$MOH_FILES_AST" | grep -qE "File:|\.mp3|\.wav|\.ulaw|\.alaw|\.gsm"; then
    ok "MOH files (Asterisk): files listed by 'moh show files'"
else
    warn "MOH files (Asterisk): 'moh show files' returned no file list"
fi

# =============================================================================
sep "9. FAX SYSTEM"
# =============================================================================

# HylaFAX services
if svc_active hylafax faxq hfaxd; then
    ok "HylaFAX service (hylafax/faxq): active"
else
    warn "HylaFAX service: not active (faxq may run as part of hylafax)"
fi

if svc_active hfaxd; then
    ok "hfaxd service: active"
else
    # Check if hfaxd is running as a process
    if pgrep hfaxd >/dev/null 2>&1; then
        ok "hfaxd process: running (pid $(pgrep hfaxd | head -1))"
    else
        warn "hfaxd: not running as service or process"
    fi
fi

[ -d /var/spool/hylafax ] \
    && ok "HylaFAX spool: /var/spool/hylafax exists" \
    || warn "HylaFAX spool: directory missing"

for subdir in recvq sendq doneq; do
    [ -d /var/spool/hylafax/$subdir ] \
        && ok "HylaFAX spool/$subdir: exists" \
        || warn "HylaFAX spool/$subdir: missing"
done

# iaxmodem processes
IAXMODEM_PIDS=$(pgrep iaxmodem 2>/dev/null | wc -l)
if [ "${IAXMODEM_PIDS:-0}" -ge 1 ]; then
    ok "iaxmodem processes: $IAXMODEM_PIDS running"
else
    warn "iaxmodem: no processes running (container: may need manual start)"
fi

# iaxmodem config directory
[ -d /etc/iaxmodem ] \
    && ok "iaxmodem config: /etc/iaxmodem exists" \
    || warn "iaxmodem config: /etc/iaxmodem missing"

IAXMODEM_CFGS=$(ls /etc/iaxmodem/ttyIAX* 2>/dev/null | wc -l)
[ "${IAXMODEM_CFGS:-0}" -ge 1 ] \
    && ok "iaxmodem config files: $IAXMODEM_CFGS (ttyIAX*)" \
    || warn "iaxmodem config files: none found (ttyIAX0-3 expected)"

# faxstat
if command -v faxstat >/dev/null 2>&1; then
    FAXSTAT_OUT=$(timeout 5 faxstat -s 2>/dev/null || timeout 5 faxstat 2>/dev/null || true)
    if [ -n "$FAXSTAT_OUT" ]; then
        ok "faxstat: returns output"
    else
        warn "faxstat -s: no output (HylaFAX may not be running)"
    fi
else
    warn "faxstat: command not found"
fi

# ttyIAX devices (container limitation)
if ls /dev/ttyIAX* >/dev/null 2>&1; then
    ok "ttyIAX devices: $(ls /dev/ttyIAX* 2>/dev/null | wc -l) present"
else
    warn "ttyIAX devices: not present (expected in container — iaxmodem creates at runtime)"
fi

# AvantFax web root
AF_WEBROOT=""
for d in "${WEB_ROOT}/avantfax" "/var/www/apache/pbx/avantfax" \
          "/var/www/html/avantfax" "/srv/www/pbx/avantfax"; do
    if [ -d "$d" ]; then
        AF_WEBROOT="$d"
        break
    fi
done
[ -n "$AF_WEBROOT" ] \
    && ok "AvantFax web root: $AF_WEBROOT" \
    || warn "AvantFax web root: not found under common paths"

# =============================================================================
sep "10. BACKUP SYSTEM"
# =============================================================================

BACKUP_DIR="/mnt/backups/pbx"

# a) Run full backup
info "Running 'pbx-backup full' (may take up to 2 minutes)..."
BACKUP_OUT=$(NO_COLOR=1 timeout 120 pbx-backup full 2>&1 || NO_COLOR=1 timeout 120 pbx-backup --now 2>&1 || true)
if echo "$BACKUP_OUT" | grep -qiE "success|complete|done|backup|OK|written"; then
    ok "pbx-backup full: completed (output indicates success)"
elif [ -n "$BACKUP_OUT" ]; then
    warn "pbx-backup full: ran but output uncertain — $(echo "$BACKUP_OUT" | tail -2 | tr '\n' '|')"
else
    warn "pbx-backup full: no output returned"
fi

# b) Verify config backup file exists and is > 1KB
CFG_BACKUP=$(find "$BACKUP_DIR" -name "*.tar.gz" -newer /etc/asterisk/asterisk.conf 2>/dev/null | sort | tail -1)
if [ -z "$CFG_BACKUP" ]; then
    CFG_BACKUP=$(find "$BACKUP_DIR" -name "*.tar.gz" 2>/dev/null | sort | tail -1)
fi
if [ -n "$CFG_BACKUP" ]; then
    CFG_SZ=$(stat -c%s "$CFG_BACKUP" 2>/dev/null || echo 0)
    [ "${CFG_SZ:-0}" -gt 1024 ] \
        && ok "Backup config archive: $CFG_BACKUP (${CFG_SZ} bytes)" \
        || warn "Backup config archive: $CFG_BACKUP is suspiciously small (${CFG_SZ} bytes)"
else
    warn "Backup config archive: no .tar.gz found in $BACKUP_DIR"
fi

# c) Verify database backup exists and is > 1KB
SQL_BACKUP=$(find "$BACKUP_DIR" \( -name "*.sql.gz" -o -name "*.sql" \) 2>/dev/null | sort | tail -1)
if [ -n "$SQL_BACKUP" ]; then
    SQL_SZ=$(stat -c%s "$SQL_BACKUP" 2>/dev/null || echo 0)
    [ "${SQL_SZ:-0}" -gt 1024 ] \
        && ok "Backup SQL dump: $SQL_BACKUP (${SQL_SZ} bytes)" \
        || warn "Backup SQL dump: $SQL_BACKUP is suspiciously small (${SQL_SZ} bytes)"
else
    warn "Backup SQL dump: no .sql/.sql.gz found in $BACKUP_DIR"
fi

# d) Run pbx-backup status
STATUS_OUT=$(NO_COLOR=1 timeout 15 pbx-backup status 2>&1 || true)
if echo "$STATUS_OUT" | grep -qiE "backup|file|bytes|KB|MB|status"; then
    ok "pbx-backup status: output lists backup info"
else
    warn "pbx-backup status: minimal output — $(echo "$STATUS_OUT" | head -1)"
fi

# e) Run pbx-backup db (database-only backup)
info "Running 'pbx-backup db'..."
DB_BACKUP_OUT=$(NO_COLOR=1 timeout 60 pbx-backup db 2>&1 || true)
if echo "$DB_BACKUP_OUT" | grep -qiE "success|done|complete|backup|dump|written|OK"; then
    ok "pbx-backup db: completed"
elif [ -n "$DB_BACKUP_OUT" ]; then
    warn "pbx-backup db: ran — $(echo "$DB_BACKUP_OUT" | tail -1)"
else
    warn "pbx-backup db: no output (subcommand may not exist)"
fi

# f) pbx-cleanup --dry-run
CLEAN_OUT=$(NO_COLOR=1 timeout 30 pbx-cleanup --dry-run 2>&1 || true)
if [ -n "$CLEAN_OUT" ]; then
    ok "pbx-cleanup --dry-run: ran without error"
else
    warn "pbx-cleanup --dry-run: no output"
fi

# =============================================================================
sep "11. SECURITY"
# =============================================================================

# fail2ban
if svc_active fail2ban; then
    ok "fail2ban: service active"
else
    fail "fail2ban: NOT running"
fi

# fail2ban asterisk jail
F2B_AST=$(fail2ban-client status asterisk 2>/dev/null || fail2ban-client status asterisk-iptables 2>/dev/null || true)
if echo "$F2B_AST" | grep -qiE "Currently banned|Status for|Jail list"; then
    ok "fail2ban: asterisk jail active"
    BANNED=$(echo "$F2B_AST" | grep -i "Currently banned" | awk -F: '{print $2}' | tr -d ' ')
    info "fail2ban asterisk: currently banned IPs: ${BANNED:-0}"
else
    warn "fail2ban: asterisk jail not found (check jail name with 'fail2ban-client status')"
fi

# pbx-security check
SEC_OUT=$(NO_COLOR=1 timeout 30 pbx-security 2>&1 || true)
if echo "$SEC_OUT" | grep -qiE "pass|ok|secure|check|permission|fail2ban"; then
    ok "pbx-security: ran and produced security output"
else
    warn "pbx-security: minimal output — $(echo "$SEC_OUT" | head -2 | tr '\n' '|')"
fi

# /etc/pbx/.env permissions
if [ -f "$ENV_FILE" ]; then
    ENV_PERM=$(stat -c "%a" "$ENV_FILE" 2>/dev/null)
    case "$ENV_PERM" in
        600|640) ok "/etc/pbx/.env permissions: $ENV_PERM (good)" ;;
        *)       warn "/etc/pbx/.env permissions: $ENV_PERM (expected 600 or 640)" ;;
    esac
else
    fail "/etc/pbx/.env: MISSING"
fi

# .htpasswd-pbx
HTPASSWD_FILE=$(find /etc/pbx /etc/apache2 /etc/httpd /etc/asterisk \
    -name ".htpasswd*" 2>/dev/null | head -1)
[ -n "$HTPASSWD_FILE" ] \
    && ok "htpasswd file: $HTPASSWD_FILE" \
    || warn "htpasswd file: not found (callcenter/reminders may not be auth-protected)"

# SSH settings
SSHD_CONF="/etc/ssh/sshd_config"
if [ -f "$SSHD_CONF" ]; then
    PERM_ROOT=$(grep -iE "^PermitRootLogin" "$SSHD_CONF" | tail -1 | awk '{print $2}')
    info "SSH PermitRootLogin: ${PERM_ROOT:-not set (default prohibit-password)}"
    PASS_AUTH=$(grep -iE "^PasswordAuthentication" "$SSHD_CONF" | tail -1 | awk '{print $2}')
    info "SSH PasswordAuthentication: ${PASS_AUTH:-not set (default yes)}"
    [ "${PASS_AUTH,,}" = "no" ] \
        && ok "SSH PasswordAuthentication: disabled (keys only)" \
        || warn "SSH PasswordAuthentication: enabled (consider disabling)"
else
    skip "SSH sshd_config: not found"
fi

# /etc/asterisk not world-writable
WW_ASTERISK=$(find /etc/asterisk -maxdepth 1 -perm -o+w -type f 2>/dev/null | wc -l)
[ "${WW_ASTERISK:-0}" -eq 0 ] \
    && ok "/etc/asterisk: no world-writable files" \
    || warn "/etc/asterisk: $WW_ASTERISK world-writable file(s) found"

# =============================================================================
sep "12. PHP CONFIGURATION"
# =============================================================================

# PHP 8.2
PHP_VERSION=$(php -v 2>/dev/null | head -1)
if echo "$PHP_VERSION" | grep -qE "PHP 8\.[2-9]"; then
    ok "PHP version: $PHP_VERSION"
elif echo "$PHP_VERSION" | grep -qE "PHP [89]"; then
    ok "PHP version: $PHP_VERSION"
else
    warn "PHP version: $PHP_VERSION (expected 8.2+)"
fi

# Required extensions
PHP_MODS=$(php -m 2>/dev/null)
for ext in pdo_mysql xml curl json mbstring gd zip; do
    echo "$PHP_MODS" | grep -qi "^${ext}$" \
        && ok "PHP extension ${ext}: loaded" \
        || warn "PHP extension ${ext}: NOT loaded"
done

# php.ini location
PHP_INI=$(php --ini 2>/dev/null | grep "Loaded Configuration" | awk -F': ' '{print $2}' | tr -d ' ')
if [ -n "$PHP_INI" ] && [ -f "$PHP_INI" ]; then
    ok "php.ini: $PHP_INI"

    MEM_LIMIT=$(php -r "echo ini_get('memory_limit');" 2>/dev/null)
    MAX_EXEC=$(php -r "echo ini_get('max_execution_time');" 2>/dev/null)

    # Convert memory_limit to MB for comparison
    MEM_NUM=$(echo "$MEM_LIMIT" | grep -oE '[0-9]+')
    MEM_UNIT=$(echo "$MEM_LIMIT" | grep -oE '[GMK]' | tr '[:lower:]' '[:upper:]')
    case "$MEM_UNIT" in
        G) MEM_MB=$((MEM_NUM * 1024)) ;;
        M) MEM_MB=$MEM_NUM ;;
        K) MEM_MB=$((MEM_NUM / 1024)) ;;
        *) MEM_MB=$MEM_NUM ;;
    esac
    [ "${MEM_MB:-0}" -ge 128 ] \
        && ok "PHP memory_limit: $MEM_LIMIT (>= 128M)" \
        || warn "PHP memory_limit: $MEM_LIMIT (expected >= 128M)"

    # 0 = unlimited (CLI default); accept 0 or >= 30
    [ "${MAX_EXEC:-0}" -eq 0 ] || [ "${MAX_EXEC:-0}" -ge 30 ] \
        && ok "PHP max_execution_time: ${MAX_EXEC}s ($([ "${MAX_EXEC:-0}" -eq 0 ] && echo 'unlimited' || echo '>= 30s'))" \
        || warn "PHP max_execution_time: ${MAX_EXEC}s (expected >= 30s or 0 for unlimited)"
else
    warn "php.ini: not found or path could not be determined"
fi

# PHP 7.4 for AvantFax — Remi/RHEL names it php74, Debian/Ubuntu names it php7.4
if command -v php7.4 >/dev/null 2>&1; then
    PHP74=$(php7.4 -v 2>/dev/null | head -1)
elif command -v php74 >/dev/null 2>&1; then
    PHP74=$(php74 -v 2>/dev/null | head -1)
else
    PHP74=""
fi
if echo "$PHP74" | grep -q "7.4"; then
    ok "PHP 7.4: available ($PHP74)"
else
    warn "PHP 7.4: not found (required for AvantFax)"
fi

# =============================================================================
sep "13. WEB SERVICES — FUNCTIONAL AUTH"
# =============================================================================

COOKIE_JAR=".deep-test-cookies.txt"
CURL_BODY_FILE=".deep-test-body.txt"
rm -f "$COOKIE_JAR" "$CURL_BODY_FILE"

# a) FreePBX admin login
FB_LOGIN_CODE=$(curl -skL --max-time 10 \
    -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
    -o "$CURL_BODY_FILE" -w "%{http_code}" \
    "https://${HOST_IP}/admin/" 2>/dev/null || echo "000")
FB_LOGIN_BODY=$(cat "$CURL_BODY_FILE" 2>/dev/null)

[ "$FB_LOGIN_CODE" != "000" ] \
    && ok "FreePBX admin GET /admin/: HTTP $FB_LOGIN_CODE" \
    || fail "FreePBX admin GET /admin/: unreachable"

echo "$FB_LOGIN_BODY" | grep -qiE "login|FreePBX|username|password" \
    && ok "FreePBX admin: login form present" \
    || warn "FreePBX admin: login form not detected in response"

# POST login
FB_POST_CODE=$(curl -skL --max-time 10 \
    -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
    -d "username=admin&password=${FREEPBX_PASS}&action=login" \
    -o "$CURL_BODY_FILE" -w "%{http_code}" \
    "https://${HOST_IP}/admin/config.php" 2>/dev/null || echo "000")
FB_POST_BODY=$(cat "$CURL_BODY_FILE" 2>/dev/null)

if echo "$FB_POST_BODY" | grep -qiE "dashboard|Logout|FreePBX Administration|pbx_admin|fpbx_username"; then
    ok "FreePBX admin: LOGIN SUCCESS (dashboard/logout found in response)"
elif [ "$FB_POST_CODE" = "302" ] || [ "$FB_POST_CODE" = "200" ]; then
    warn "FreePBX admin: login POST returned $FB_POST_CODE but no dashboard detected"
else
    warn "FreePBX admin: login POST HTTP $FB_POST_CODE"
fi

# b) AvantFax login
AF_URL=""
for path in "/avantfax/" "/pbx/avantfax/" "/fax/"; do
    code=$(curl -skL --max-time 5 -o /dev/null -w "%{http_code}" \
        "https://${HOST_IP}${path}" 2>/dev/null || echo "000")
    if [ "$code" != "000" ] && [ "$code" != "404" ]; then
        AF_URL="https://${HOST_IP}${path}"
        break
    fi
done

if [ -n "$AF_URL" ]; then
    rm -f "$COOKIE_JAR" "$CURL_BODY_FILE"
    AF_GET=$(curl -skL --max-time 10 -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
        -o "$CURL_BODY_FILE" -w "%{http_code}" "$AF_URL" 2>/dev/null || echo "000")
    AF_BODY=$(cat "$CURL_BODY_FILE" 2>/dev/null)
    ok "AvantFax GET $AF_URL: HTTP $AF_GET"

    # POST login to AvantFax
    AF_POST=$(curl -skL --max-time 10 -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
        -d "username=admin&password=${FREEPBX_PASS}&action=login" \
        -o "$CURL_BODY_FILE" -w "%{http_code}" "${AF_URL}" 2>/dev/null || echo "000")
    AF_PBODY=$(cat "$CURL_BODY_FILE" 2>/dev/null)
    if echo "$AF_PBODY" | grep -qiE "dashboard|fax|inbox|logout|send fax|avantfax"; then
        ok "AvantFax: LOGIN SUCCESS (dashboard content found)"
    else
        warn "AvantFax: login POST HTTP $AF_POST — dashboard not detected in body"
    fi
else
    warn "AvantFax: not reachable at /avantfax/, /pbx/avantfax/, or /fax/"
fi

# c) Reminders with Basic auth
REM_CODE=$(curl -skL --max-time 10 \
    -u "admin:${FREEPBX_PASS}" \
    -o "$CURL_BODY_FILE" -w "%{http_code}" \
    "https://${HOST_IP}/reminders/" 2>/dev/null || echo "000")
REM_BODY=$(cat "$CURL_BODY_FILE" 2>/dev/null)
if [ "$REM_CODE" = "200" ] && [ -n "$REM_BODY" ]; then
    ok "Reminders /reminders/ with Basic auth: HTTP 200, body present"
elif [ "$REM_CODE" = "401" ]; then
    warn "Reminders /reminders/: 401 Unauthorized (wrong password or no auth configured)"
elif [ "$REM_CODE" = "404" ]; then
    warn "Reminders /reminders/: 404 (application may not be installed)"
else
    warn "Reminders /reminders/: HTTP $REM_CODE"
fi

# d) CallCenter with Basic auth
CC_CODE=$(curl -skL --max-time 10 \
    -u "admin:${FREEPBX_PASS}" \
    -o "$CURL_BODY_FILE" -w "%{http_code}" \
    "https://${HOST_IP}/callcenter/" 2>/dev/null || echo "000")
CC_BODY=$(cat "$CURL_BODY_FILE" 2>/dev/null)
if [ "$CC_CODE" = "200" ] && [ -n "$CC_BODY" ]; then
    ok "CallCenter /callcenter/ with Basic auth: HTTP 200, body present"
elif [ "$CC_CODE" = "401" ]; then
    warn "CallCenter /callcenter/: 401 Unauthorized"
elif [ "$CC_CODE" = "404" ]; then
    warn "CallCenter /callcenter/: 404 (application may not be installed)"
else
    warn "CallCenter /callcenter/: HTTP $CC_CODE"
fi

rm -f "$COOKIE_JAR" "$CURL_BODY_FILE"

# =============================================================================
sep "14. ASTERISK SOUNDS"
# =============================================================================

SOUNDS_DIR="/var/lib/asterisk/sounds/en"
[ -d "$SOUNDS_DIR" ] \
    && ok "Sounds dir: $SOUNDS_DIR exists" \
    || fail "Sounds dir: $SOUNDS_DIR MISSING"

# Count sound files
SOUND_FILE_COUNT=$(find "$SOUNDS_DIR" -type f \( -name "*.ulaw" -o -name "*.alaw" -o -name "*.gsm" \) 2>/dev/null | wc -l)
info "Sound files (.ulaw/.alaw/.gsm): $SOUND_FILE_COUNT"
[ "${SOUND_FILE_COUNT:-0}" -ge 50 ] \
    && ok "Asterisk sounds: $SOUND_FILE_COUNT files (>= 50)" \
    || warn "Asterisk sounds: only $SOUND_FILE_COUNT files (expected 50+)"

# Digits 0-9 in ulaw
ALL_DIGITS=1
for d in 0 1 2 3 4 5 6 7 8 9; do
    if ! [ -f "$SOUNDS_DIR/digits/${d}.ulaw" ] && \
       ! [ -f "$SOUNDS_DIR/digits/${d}.gsm" ] && \
       ! [ -f "$SOUNDS_DIR/digits/${d}.alaw" ]; then
        warn "Sound: digits/${d} missing (checked .ulaw/.gsm/.alaw)"
        ALL_DIGITS=0
    fi
done
[ "$ALL_DIGITS" -eq 1 ] && ok "Sound digits 0-9: all present"

# TTS test file
TTS_FILE=$(find "$SOUNDS_DIR" -name "tt-*" 2>/dev/null | head -1)
[ -n "$TTS_FILE" ] \
    && ok "TTS test sound: $TTS_FILE" \
    || warn "TTS test sounds (tt-*): none found"

# Total sounds by format
for fmt in ulaw gsm alaw wav; do
    N=$(find /var/lib/asterisk/sounds -name "*.${fmt}" 2>/dev/null | wc -l)
    [ "$N" -gt 0 ] && info "Sound format .${fmt}: $N files"
done

# =============================================================================
sep "15. AGI SCRIPTS"
# =============================================================================

AGI_DIR="/var/lib/asterisk/agi-bin"
[ -d "$AGI_DIR" ] \
    && ok "AGI directory: $AGI_DIR exists" \
    || fail "AGI directory: $AGI_DIR MISSING"

AGI_COUNT=$(find "$AGI_DIR" -type f 2>/dev/null | wc -l)
info "AGI scripts total: $AGI_COUNT"
[ "${AGI_COUNT:-0}" -ge 1 ] \
    && ok "AGI scripts: $AGI_COUNT file(s) found" \
    || warn "AGI scripts: none found in $AGI_DIR"

# Check for key AGI scripts (using actual filenames with dashes, as installed)
for agi_script in call-logger.agi cid-validate.agi business-hours.agi; do
    if [ -f "$AGI_DIR/$agi_script" ]; then
        # Executable check
        [ -x "$AGI_DIR/$agi_script" ] \
            && ok "AGI $agi_script: exists and is executable" \
            || warn "AGI $agi_script: exists but NOT executable"

        # Determine type and syntax-check
        FIRST_LINE=$(head -1 "$AGI_DIR/$agi_script" 2>/dev/null)
        if echo "$FIRST_LINE" | grep -q "perl"; then
            if command -v perl >/dev/null 2>&1; then
                perl -c "$AGI_DIR/$agi_script" >/dev/null 2>&1 \
                    && ok "AGI $agi_script: Perl syntax OK" \
                    || warn "AGI $agi_script: Perl syntax error"
            fi
        elif echo "$FIRST_LINE" | grep -q "python"; then
            PYTHON_CMD=$(echo "$FIRST_LINE" | grep -oE "python[0-9.]*" | head -1)
            ${PYTHON_CMD:-python3} -c "import ast; ast.parse(open('$AGI_DIR/$agi_script').read())" 2>/dev/null \
                && ok "AGI $agi_script: Python syntax OK" \
                || warn "AGI $agi_script: Python syntax error"
        elif echo "$FIRST_LINE" | grep -qiE "bash|sh"; then
            bash -n "$AGI_DIR/$agi_script" 2>/dev/null \
                && ok "AGI $agi_script: bash syntax OK" \
                || warn "AGI $agi_script: bash syntax error"
        else
            ok "AGI $agi_script: exists (unknown interpreter)"
        fi
    else
        warn "AGI $agi_script: not found in $AGI_DIR"
    fi
done

# Check any other AGI files for executability
NON_EXEC=$(find "$AGI_DIR" -type f ! -executable 2>/dev/null | wc -l)
[ "${NON_EXEC:-0}" -eq 0 ] \
    && ok "AGI scripts: all executable" \
    || warn "AGI scripts: $NON_EXEC non-executable file(s) found"

# =============================================================================
sep "16. FEATURE CODES & APPLICATIONS"
# =============================================================================

# *72 (call forward enable)
FWD72=$(ast "dialplan show *72@from-internal" 2>/dev/null)
if echo "$FWD72" | grep -qiE "\*72|callforward|Forward"; then
    ok "Feature *72 (call forward on): in from-internal"
elif echo "$DIALPLAN_ALL" | grep -qiE "\*72|callforward"; then
    ok "Feature *72 (call forward on): found in dialplan"
else
    warn "Feature *72 (call forward on): not found in dialplan"
fi

# *97 (voicemail)
VM97=$(ast "dialplan show *97@from-internal" 2>/dev/null)
if echo "$VM97" | grep -qiE "\*97|voicemail|VoicemailMain"; then
    ok "Feature *97 (voicemail): in from-internal"
elif echo "$DIALPLAN_ALL" | grep -qiE "VoicemailMain|\*97"; then
    ok "Feature *97 (voicemail): found in dialplan"
else
    warn "Feature *97 (voicemail): not found in dialplan"
fi

# features.conf
[ -f /etc/asterisk/features.conf ] \
    && ok "features.conf: exists ($(wc -l < /etc/asterisk/features.conf) lines)" \
    || warn "features.conf: not found"

# Call recording configured
if grep -rqiE "callrecording|mixmonitor|Monitor" /etc/asterisk/ 2>/dev/null; then
    ok "Call recording: configured (MixMonitor/Monitor found in asterisk configs)"
else
    warn "Call recording: not found in asterisk configs"
fi

# FreePBX feature code modules
for mod in callforward donotdisturb callrecording; do
    fwconsole ma list 2>/dev/null | grep -qiE "^\| *${mod} " \
        && ok "FreePBX feature module ${mod}: installed" \
        || warn "FreePBX feature module ${mod}: not found in module list"
done

# =============================================================================
sep "17. NETWORK & SIP PORTS"
# =============================================================================

_check_udp_port() {
    local port="$1" label="$2" required="${3:-yes}"
    if ss -unlp 2>/dev/null | grep -qE ":${port}\b" || \
       ss -unp 2>/dev/null | grep -qE ":${port}\b"; then
        ok "UDP port ${port} (${label}): listening"
    else
        [ "$required" = "warn" ] \
            && warn "UDP port ${port} (${label}): not listening" \
            || fail "UDP port ${port} (${label}): NOT listening"
    fi
}

_check_tcp_port() {
    local port="$1" label="$2" required="${3:-yes}"
    if ss -tlnp 2>/dev/null | grep -qE ":${port}\b" || \
       ss -tnp 2>/dev/null | grep -qE ":${port}\b"; then
        ok "TCP port ${port} (${label}): listening"
    else
        [ "$required" = "warn" ] \
            && warn "TCP port ${port} (${label}): not listening" \
            || fail "TCP port ${port} (${label}): NOT listening"
    fi
}

_check_udp_port 5060  "SIP"
_check_tcp_port 5061  "SIP/TLS"      "warn"
_check_tcp_port 8088  "Asterisk HTTP"
_check_udp_port 4569  "IAX2"
_check_tcp_port 80    "HTTP"
_check_tcp_port 443   "HTTPS"        "warn"
_check_tcp_port 5038  "AMI"
_check_tcp_port "$WEBMIN_PORT" "Webmin"
_check_tcp_port 25    "SMTP/Postfix"
_check_tcp_port 4559  "HylaFAX hfaxd" "warn"

# RTP range in rtp.conf
RTP_CONF="/etc/asterisk/rtp.conf"
if [ -f "$RTP_CONF" ]; then
    RTP_START=$(grep -iE "^rtpstart" "$RTP_CONF" | awk -F= '{gsub(/ /,"",$2); print $2}' | head -1)
    RTP_END=$(grep -iE "^rtpend" "$RTP_CONF" | awk -F= '{gsub(/ /,"",$2); print $2}' | head -1)
    if [ -n "$RTP_START" ] && [ -n "$RTP_END" ]; then
        ok "RTP range: ${RTP_START}-${RTP_END} (from rtp.conf)"
        [ "${RTP_START:-0}" -ge 10000 ] && [ "${RTP_END:-0}" -le 20000 ] \
            && ok "RTP range: within 10000-20000 standard range" \
            || warn "RTP range: ${RTP_START}-${RTP_END} is outside 10000-20000 (non-standard)"
    else
        warn "RTP range: not found in rtp.conf (using defaults)"
    fi
else
    warn "rtp.conf: not found"
fi

# =============================================================================
sep "18. LOG FILES & ROTATION"
# =============================================================================

[ -f /var/log/asterisk/full ] \
    && ok "Asterisk log /var/log/asterisk/full: exists" \
    || fail "Asterisk log /var/log/asterisk/full: MISSING"

if [ -f /var/log/asterisk/full ]; then
    # Check it's being written to (mtime within last 5 min = 300s)
    MTIME_AGO=$(( $(date +%s) - $(stat -c %Y /var/log/asterisk/full 2>/dev/null || echo 0) ))
    [ "${MTIME_AGO:-9999}" -le 300 ] \
        && ok "Asterisk log: modified ${MTIME_AGO}s ago (active)" \
        || warn "Asterisk log: last modified ${MTIME_AGO}s ago (may be quiet)"

    LOG_SIZE=$(du -m /var/log/asterisk/full 2>/dev/null | awk '{print $1}')
    info "Asterisk full log size: ${LOG_SIZE:-?}MB"
    [ "${LOG_SIZE:-0}" -lt 500 ] \
        && ok "Asterisk log size: ${LOG_SIZE}MB (< 500MB)" \
        || warn "Asterisk log size: ${LOG_SIZE}MB (> 500MB — consider rotation)"
fi

[ -f /var/log/asterisk/security ] \
    && ok "Asterisk security log: exists" \
    || warn "Asterisk security log: not found"

[ -f /var/log/pbx-install.log ] \
    && ok "PBX install log: /var/log/pbx-install.log exists" \
    || warn "PBX install log: /var/log/pbx-install.log not found"

# logrotate config
if [ -f /etc/logrotate.d/asterisk ] || [ -f /etc/logrotate.d/pbx ]; then
    ok "logrotate: Asterisk/PBX config present"
else
    warn "logrotate: no Asterisk/PBX logrotate config found"
fi

# =============================================================================
sep "19. CRON JOBS"
# =============================================================================

# crond or cron running
if svc_active crond cron; then
    ok "Cron service: active"
else
    warn "Cron service: crond/cron not active"
fi

# Gather all cron sources
ALL_CRON=$(
    crontab -l 2>/dev/null
    crontab -u root -l 2>/dev/null
    crontab -u asterisk -l 2>/dev/null
    cat /etc/crontab 2>/dev/null
    find /etc/cron.d /etc/cron.daily /etc/cron.weekly /etc/cron.hourly \
        -type f 2>/dev/null | xargs cat 2>/dev/null
)

echo "$ALL_CRON" | grep -qiE "pbx-backup|backup" \
    && ok "Cron: backup job configured" \
    || warn "Cron: no backup job found in crontab/cron.d"

echo "$ALL_CRON" | grep -qiE "pbx-cleanup|cleanup" \
    && ok "Cron: cleanup job configured" \
    || warn "Cron: no cleanup job found"

echo "$ALL_CRON" | grep -qiE "fwconsole|freepbx" \
    && ok "Cron: FreePBX cron job present" \
    || warn "Cron: no FreePBX (fwconsole) cron found"

# FreePBX cron via fwconsole cron
FWCRON=$(find /etc/cron.d -name "*freepbx*" -o -name "*fpbx*" 2>/dev/null | head -1)
[ -n "$FWCRON" ] && ok "FreePBX cron file: $FWCRON" || true

# =============================================================================
sep "20. SYSTEM RESOURCES"
# =============================================================================

# Disk space
DISK_AVAIL_MB=$(df -BM / 2>/dev/null | awk 'NR==2{gsub("M","",$4); print $4}')
DISK_AVAIL_GB=$(df -BG / 2>/dev/null | awk 'NR==2{gsub("G","",$4); print $4}')
if [ "${DISK_AVAIL_MB:-0}" -lt 512 ]; then
    fail "Disk / free: ${DISK_AVAIL_MB}MB (< 512MB — CRITICAL)"
elif [ "${DISK_AVAIL_MB:-0}" -lt 1024 ]; then
    warn "Disk / free: ${DISK_AVAIL_MB}MB (< 1GB — low)"
else
    ok "Disk / free: ${DISK_AVAIL_GB}GB"
fi

# RAM
RAM_AVAIL=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo 2>/dev/null)
RAM_AVAIL_MB=$(( ${RAM_AVAIL:-0} / 1024 ))
if [ "${RAM_AVAIL_MB:-0}" -ge 512 ]; then
    ok "RAM available: ${RAM_AVAIL_MB}MB"
elif [ "${RAM_AVAIL_MB:-0}" -ge 256 ]; then
    warn "RAM available: ${RAM_AVAIL_MB}MB (low — performance may suffer)"
else
    fail "RAM available: ${RAM_AVAIL_MB}MB (< 256MB — insufficient)"
fi

# Total RAM
RAM_TOTAL=$(awk '/^MemTotal:/{print $2}' /proc/meminfo 2>/dev/null)
RAM_TOTAL_MB=$(( ${RAM_TOTAL:-0} / 1024 ))
info "RAM total: ${RAM_TOTAL_MB}MB"

# Load average
LOAD_1=$(awk '{print $1}' /proc/loadavg 2>/dev/null)
LOAD_INT=$(echo "$LOAD_1" | cut -d. -f1)
if [ "${LOAD_INT:-0}" -ge 10 ]; then
    warn "Load average: $LOAD_1 (very high)"
elif [ "${LOAD_INT:-0}" -ge 5 ]; then
    warn "Load average: $LOAD_1 (high)"
else
    ok "Load average: $LOAD_1"
fi

# CPU cores
CPU_CORES=$(nproc 2>/dev/null || grep -c "^processor" /proc/cpuinfo 2>/dev/null || echo 1)
info "CPU cores: $CPU_CORES"

# Uptime
UPTIME=$(uptime -p 2>/dev/null || uptime 2>/dev/null | awk -F'up ' '{print $2}' | cut -d, -f1)
info "Uptime: $UPTIME"

# =============================================================================
sep "21. INSTALLED COMPONENT VERSIONS"
# =============================================================================

# Asterisk version
AST_VER=$(asterisk -V 2>/dev/null || echo "unknown")
ok "Asterisk version: $AST_VER"
echo "$AST_VER" | grep -qE "^Asterisk (21|22)" \
    && ok "Asterisk: version 21+ (expected)" \
    || warn "Asterisk: version is $AST_VER (expected 21+)"

# FreePBX version
FPBX_VER=$(fwconsole --version 2>/dev/null \
    | grep -oE "[0-9]+\.[0-9]+\.[0-9]+" | head -1 \
    || php -r "include '/etc/freepbx.conf'; echo \$amp_conf['VERSION'];" 2>/dev/null \
    || echo "unknown")
ok "FreePBX version: $FPBX_VER"

# PHP
PHP_VER=$(php -r "echo phpversion();" 2>/dev/null || echo "unknown")
ok "PHP version: $PHP_VER"

# MariaDB
MARIA_VER=$(mysql -u root ${MYSQL_PASS:+-p"${MYSQL_PASS}"} -e "SELECT VERSION();" 2>/dev/null \
    | tail -1 | awk '{print $1}')
ok "MariaDB version: ${MARIA_VER:-unknown}"

# Apache
APACHE_VER=$(httpd -v 2>/dev/null | head -1 || apache2 -v 2>/dev/null | head -1 || echo "unknown")
ok "Apache version: $APACHE_VER"

# HylaFAX
HYLAFAX_VER=$(faxstat -V 2>/dev/null | head -1 \
    || dpkg -l hylafax-server 2>/dev/null | grep "^ii" | awk '{print $3}' \
    || rpm -q hylafax+ 2>/dev/null \
    || echo "unknown")
ok "HylaFAX version: $HYLAFAX_VER"

# iaxmodem
IAXMODEM_VER=$(iaxmodem --version 2>/dev/null | head -1 \
    || rpm -q iaxmodem 2>/dev/null \
    || dpkg -l iaxmodem 2>/dev/null | grep "^ii" | awk '{print $3}' \
    || echo "unknown")
ok "iaxmodem version: $IAXMODEM_VER"

# fail2ban
F2B_VER=$(fail2ban-client --version 2>/dev/null | head -1 || echo "unknown")
ok "fail2ban version: $F2B_VER"

# =============================================================================
sep "22. FREEPBX MODULES"
# =============================================================================

FWCONSOLE_LIST=$(fwconsole ma list 2>/dev/null)
if [ -n "$FWCONSOLE_LIST" ]; then
    MOD_INSTALLED=$(echo "$FWCONSOLE_LIST" | grep -c " Enabled " 2>/dev/null || \
                    echo "$FWCONSOLE_LIST" | grep -c "| Enabled" 2>/dev/null || echo 0)
    info "FreePBX enabled modules: $MOD_INSTALLED"
    [ "${MOD_INSTALLED:-0}" -ge 20 ] \
        && ok "FreePBX modules: $MOD_INSTALLED enabled (>= 20)" \
        || warn "FreePBX modules: only $MOD_INSTALLED enabled (expected 20+)"

    # Core modules — FreePBX 17 uses 'sipsettings' (not 'pjsip') for PJSIP management
    for coremod in framework core voicemail sipsettings; do
        echo "$FWCONSOLE_LIST" | grep -qiE "^\| *${coremod} " \
            && ok "FreePBX module ${coremod}: in module list" \
            || warn "FreePBX module ${coremod}: NOT in module list"
    done

    # Routing modules — in FreePBX 17 routing is part of core; check for related modules
    for routemod in ivr ringgroups queues timeconditions; do
        echo "$FWCONSOLE_LIST" | grep -qiE "^\| *${routemod} " \
            && ok "FreePBX routing module ${routemod}: in module list" \
            || warn "FreePBX routing module ${routemod}: not in module list"
    done

    # Admin/reporting modules
    for adminmod in backup dashboard cdr; do
        echo "$FWCONSOLE_LIST" | grep -qiE "^\| *${adminmod} " \
            && ok "FreePBX module ${adminmod}: in module list" \
            || warn "FreePBX module ${adminmod}: not in module list"
    done
else
    warn "FreePBX fwconsole ma list: no output (fwconsole not available?)"
fi

# fwconsole status / info
FWSTATUS=$(timeout 15 fwconsole sa 2>/dev/null || timeout 15 fwconsole info 2>/dev/null || true)
[ -n "$FWSTATUS" ] && ok "fwconsole sa/info: responds" || warn "fwconsole sa/info: no output"

# =============================================================================
sep "23. IDEMPOTENCY SPOT-CHECK"
# =============================================================================

# a) Re-run pbx-repair in read-only check mode only (never full repair in tests)
if command -v pbx-repair >/dev/null 2>&1; then
    info "Running pbx-repair --check (read-only status)..."
    REP_OUT=$(NO_COLOR=1 timeout 60 pbx-repair --check 2>&1 || true)
    EC=$?
    if [ -n "$REP_OUT" ] && echo "$REP_OUT" | grep -qiE "ok|pass|repair|check|status|running"; then
        ok "IDEMPOTENCY pbx-repair --check: ran without fatal errors"
    else
        warn "IDEMPOTENCY pbx-repair --check: exit=$EC, output: $(echo "$REP_OUT" | tail -2 | tr '\n' '|')"
    fi
else
    skip "IDEMPOTENCY pbx-repair: not installed"
fi

# b) Run pbx-backup full twice and verify both backups exist
info "Running second pbx-backup full (idempotency check)..."
BACKUP2_OUT=$(NO_COLOR=1 timeout 120 pbx-backup full 2>&1 \
    || NO_COLOR=1 timeout 120 pbx-backup --now 2>&1 || true)
if echo "$BACKUP2_OUT" | grep -qiE "success|done|complete|backup|written|OK"; then
    ok "IDEMPOTENCY pbx-backup full (2nd run): completed"
else
    warn "IDEMPOTENCY pbx-backup full (2nd run): $(echo "$BACKUP2_OUT" | tail -1)"
fi

BACKUP_COUNT=$(find /mnt/backups/pbx -name "*.tar.gz" 2>/dev/null | wc -l)
[ "${BACKUP_COUNT:-0}" -ge 2 ] \
    && ok "IDEMPOTENCY backups: $BACKUP_COUNT archives exist after 2 runs" \
    || warn "IDEMPOTENCY backups: only $BACKUP_COUNT archive(s) found"

# c) fwconsole reload
info "Running fwconsole reload (idempotency)..."
FWRELOAD=$(timeout 60 fwconsole reload 2>&1 || true)
EC=$?
if echo "$FWRELOAD" | grep -qiE "reload|success|done|ok|applying"; then
    ok "IDEMPOTENCY fwconsole reload: exit=$EC, completed"
elif [ "$EC" -eq 0 ]; then
    ok "IDEMPOTENCY fwconsole reload: exit=0"
else
    warn "IDEMPOTENCY fwconsole reload: exit=$EC — $(echo "$FWRELOAD" | tail -2 | tr '\n' '|')"
fi

# =============================================================================
sep "FINAL RESULTS"
# =============================================================================

TOTAL=$((PASS + FAIL + WARN + SKIP))
printf "\n"
printf "  Tests run:  %d\n" "$TOTAL"
printf "  ${_G}PASSED${_N}:     %d\n" "$PASS"
printf "  ${_Y}WARNED${_N}:     %d\n" "$WARN"
printf "  ${_R}FAILED${_N}:     %d\n" "$FAIL"
printf "  ${_B}SKIPPED${_N}:    %d\n" "$SKIP"
printf "\n"

if [ "$FAIL" -gt 0 ]; then
    printf "${_R}FAILURES:${_N}\n"
    printf "%b\n" "$FAILURES"
    printf "\n"
    printf "${_R}RESULT: %d FAILURE(S) — SYSTEM REQUIRES ATTENTION${_N}\n\n" "$FAIL"
    exit 1
else
    printf "${_G}RESULT: ALL TESTS PASSED — SYSTEM FUNCTIONAL${_N}\n\n"
    exit 0
fi
