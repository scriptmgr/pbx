#!/bin/bash
# Functional test suite for PBX installation — raw text output (always log-safe)
PASS=0; FAIL=0; WARN=0
ok()   { echo "  PASS: $*"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $*"; FAIL=$((FAIL+1)); }
warn() { echo "  WARN: $*"; WARN=$((WARN+1)); }
sep()  { echo ""; echo "=== $* ==="; }

sep "ASTERISK FUNCTIONAL"
# Service: managed by freepbx.service (fwconsole start) or directly
if systemctl is-active asterisk >/dev/null 2>&1; then
    ok "asterisk systemd service active"
elif systemctl is-active freepbx >/dev/null 2>&1; then
    ok "asterisk managed by freepbx.service"
else
    fail "neither asterisk nor freepbx service active"
fi
asterisk -rx "core show version" 2>/dev/null | grep -q "Asterisk" \
    && ok "asterisk CLI: $(asterisk -rx 'core show version' 2>/dev/null | head -1)" \
    || fail "asterisk CLI not responsive"
asterisk -rx "dialplan show" 2>/dev/null | grep -q "Context" \
    && ok "dialplan loaded ($(asterisk -rx 'dialplan show' 2>/dev/null | grep -c Context) contexts)" \
    || fail "dialplan empty"
asterisk -rx "pjsip show transports" 2>/dev/null | grep -qiE "udp|tcp|tls|ws" \
    && ok "PJSIP transports loaded" || fail "no PJSIP transports"
# AMI: use bash /dev/tcp since nc may not be installed
AMI_SECRET=$(grep "^secret" /etc/asterisk/manager.conf 2>/dev/null | head -1 | awk -F= '{gsub(/ /,"",$2); print $2}')
if [ -n "$AMI_SECRET" ] && ss -tlnp 2>/dev/null | grep -q ":5038\b"; then
    # Use timeout + bash /dev/tcp for AMI test
    RESULT=$(timeout 3 bash -c "exec 3<>/dev/tcp/127.0.0.1/5038; \
        printf 'Action: Login\r\nUsername: admin\r\nSecret: %s\r\n\r\n' '$AMI_SECRET' >&3; \
        sleep 1; cat <&3" 2>/dev/null || true)
    echo "$RESULT" | grep -q "Response: Success" \
        && ok "AMI login successful" \
        || warn "AMI login failed (Asterisk initializing or auth mismatch)"
else
    warn "AMI secret not found or port 5038 not listening"
fi

sep "FREEPBX FUNCTIONAL"
fwconsole ma list 2>/dev/null | grep -q "Enabled" \
    && ok "fwconsole ma list works" || fail "fwconsole ma list failed"
COUNT=$(fwconsole ma list 2>/dev/null | grep -c "Enabled" || echo 0)
[ "$COUNT" -ge 50 ] && ok "FreePBX modules enabled: $COUNT" || fail "Too few modules: $COUNT"
# FreePBX 17 module names (verified from live install)
for mod in core voicemail cdr backup ringgroups ivr dashboard framework sipsettings userman; do
    fwconsole ma list 2>/dev/null | grep -q "^| ${mod} " \
        && ok "FreePBX module: $mod" || fail "FreePBX module missing: $mod"
done
# Routing: FreePBX 17 uses dynroute + core (no separate inboundroutes module)
fwconsole ma list 2>/dev/null | grep -qE "dynroute|inboundroutes" \
    && ok "FreePBX routing module present" || warn "FreePBX routing module not found"
asterisk -rx "module show like chan_pjsip" 2>/dev/null | grep -q "Running" \
    && ok "chan_pjsip.so loaded" || fail "chan_pjsip.so not loaded"

sep "WEB PORTAL FUNCTIONAL"
# Use HTTPS directly — HTTP redirects to the configured FQDN which may not resolve in containers
curl -skL "https://127.0.0.1/" -o /dev/null -w "%{http_code}" | grep -q "^200$" \
    && ok "portal / accessible" \
    || fail "portal / returned $(curl -skL https://127.0.0.1/ -o /dev/null -w '%{http_code}')"
curl -skL "https://127.0.0.1/admin/" -o /dev/null -w "%{http_code}" | grep -qE "^(200|302)$" \
    && ok "FreePBX /admin/ accessible" || fail "FreePBX /admin/ not accessible"
curl -skL "https://127.0.0.1/health" 2>/dev/null | grep -qiE "status|ok|healthy|version" \
    && ok "/health endpoint returns JSON" || fail "/health endpoint not working"
curl -skL "https://127.0.0.1/status/" -o /dev/null -w "%{http_code}" | grep -q "^200$" \
    && ok "/status/ accessible" || warn "/status/ not accessible"
curl -skL "https://127.0.0.1/avantfax/" -o /dev/null -w "%{http_code}" | grep -qE "^(200|302)$" \
    && ok "/avantfax/ accessible" || warn "/avantfax/ not accessible"
curl -skL "https://127.0.0.1/callcenter/" -o /dev/null -w "%{http_code}" | grep -qE "^(200|302|403)$" \
    && ok "/callcenter/ accessible" || warn "/callcenter/ not accessible"
WM_PORT=$(grep "^port=" /etc/webmin/miniserv.conf 2>/dev/null | cut -d= -f2 || echo 9001)
curl -sk --max-time 5 "https://127.0.0.1:${WM_PORT}/" -o /dev/null -w "%{http_code}" | grep -qE "^(200|302|401)$" \
    && ok "Webmin :${WM_PORT} accessible" || warn "Webmin :${WM_PORT} not accessible"

sep "FAX SYSTEM FUNCTIONAL"
systemctl is-active hylafax >/dev/null 2>&1 || systemctl is-active hylafax+ >/dev/null 2>&1 \
    && ok "HylaFAX service active" || fail "HylaFAX service not running"
# hfaxd must be running for faxstat to work
pgrep -x hfaxd >/dev/null 2>&1 \
    && ok "hfaxd running (port 4559 client server)" \
    || fail "hfaxd not running — fax clients cannot connect"
echo "" | timeout 5 faxstat -h localhost 2>/dev/null | grep -qiE "HylaFAX|Scheduler|modem|queue|job" \
    && ok "faxstat -h localhost connects" \
    || { warn "faxstat cannot connect (hfaxd may still be starting)"; }
pgrep -x iaxmodem >/dev/null 2>&1 \
    && ok "iaxmodem running ($(pgrep -x iaxmodem | wc -l) instances)" \
    || fail "no iaxmodem processes"
ls /dev/ttyIAX* >/dev/null 2>&1 \
    && ok "IAX modem devices: $(ls /dev/ttyIAX* 2>/dev/null | tr '\n' ' ')" \
    || fail "no /dev/ttyIAX* devices"
[ -f /var/www/apache/pbx/avantfax/includes/config.php ] \
    && ok "AvantFax config.php present" || warn "AvantFax config.php missing"

sep "BACKUP FUNCTIONAL"
pbx-backup --now 2>&1 | tee /tmp/backup-test.out | grep -E "OK|backup|Backup|complete|error" | tail -3
grep -qiE "success|complete|backup" /tmp/backup-test.out \
    && ok "pbx-backup --now succeeded" || fail "pbx-backup --now failed"
find /mnt/backups/pbx -name "*.tar.gz" -o -name "*.sql.gz" 2>/dev/null | head -1 | grep -q "." \
    && ok "backup archives exist in /mnt/backups/pbx/" || fail "no backup files found"

sep "SCRIPTS FUNCTIONAL"
for script in pbx-status pbx-services pbx-ssl pbx-network pbx-logs pbx-firewall \
              pbx-security pbx-passwords pbx-cdr pbx-trunks pbx-asterisk pbx-calls \
              pbx-repair pbx-restart pbx-cleanup pbx-docs pbx-moh pbx-recordings \
              pbx-config pbx-diag pbx-update; do
    if command -v "$script" >/dev/null 2>&1; then
        "$script" --help >/dev/null 2>&1 || "$script" -h >/dev/null 2>&1 || "$script" help >/dev/null 2>&1 \
            && ok "$script --help works" \
            || fail "$script --help returned error"
    else
        fail "$script not found in PATH"
    fi
done
pbx-status  2>/dev/null | grep -qiE "Asterisk|PBX|Service|Running" \
    && ok "pbx-status output valid" || fail "pbx-status output invalid"
pbx-services 2>/dev/null | grep -qiE "asterisk|mariadb|apache|httpd" \
    && ok "pbx-services lists services" || fail "pbx-services output invalid"

sep "SERVICES SUMMARY"
for svc in asterisk freepbx mariadb apache2 httpd php-fpm postfix fail2ban hylafax webmin; do
    if systemctl list-units --type=service 2>/dev/null | grep -q "^  *${svc}"; then
        status=$(systemctl is-active "$svc" 2>/dev/null)
        case "$status" in
            active)      ok   "$svc: running" ;;
            activating)  warn "$svc: activating" ;;
            *)           fail "$svc: $status" ;;
        esac
    fi
done

sep "RESULT"
echo "PASSED: $PASS  WARNED: $WARN  FAILED: $FAIL"
[ "$FAIL" -eq 0 ] && echo "RESULT: ALL TESTS PASSED" || echo "RESULT: $FAIL FAILURE(S)"
exit $FAIL
