#!/bin/bash
# =============================================================================
# install.sh input validation test
# Runs `install.sh validate` (and one real `install` abort) against a matrix of
# good and bad settings. The install-abort case is safe to run as root because
# invalid inputs must be rejected before the installer touches the system.
# =============================================================================
TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "${TEST_DIR}/.." && pwd)"
INSTALL="${INSTALL:-${PROJECT_DIR}/install.sh}"
PASS=0; FAIL=0
ok()   { echo "  PASS: $*"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $*"; FAIL=$((FAIL+1)); }

# expect NAME EXPECTED_RC VAR=value ...
expect() {
    local name="$1" want="$2" out rc
    shift 2
    out=$(env -i PATH="$PATH" "$@" bash "$INSTALL" validate 2>&1); rc=$?
    if [ "$rc" -eq "$want" ]; then ok "$name (rc=$rc)"; else fail "$name: wanted rc=$want, got rc=$rc"; fi
    LAST_OUT="$out"
}

L33=$(printf 'a%.0s' $(seq 1 33)); L32=$(printf 'a%.0s' $(seq 1 32))
P129=$(printf 'a%.0s' $(seq 1 129)); P128=$(printf 'a%.0s' $(seq 1 128))

echo "=== valid settings are accepted ==="
expect "defaults (nothing set)" 0
expect "automatic proxy detection" 0 BEHIND_PROXY=auto
expect "typical custom set" 0 ADMIN_EMAIL=ops@example.com TIMEZONE=Europe/London ADMIN_USERNAME=admin.user-1 \
    ADMIN_PASSWORD='Str0ng+Pass_word@1' MYSQL_ROOT_PASSWORD='Db:Pass,w0rd/x^y~z' PROXY_HTTP_PORT=8190
expect "email with plus tag" 0 ADMIN_EMAIL=first.last+pbx@sub.example.co.uk
expect "UTC timezone" 0 TIMEZONE=UTC
expect "half-hour timezone" 0 TIMEZONE=Asia/Kolkata
expect "port 1" 0 PROXY_HTTP_PORT=1
expect "port 65535" 0 PROXY_HTTP_PORT=65535
expect "16 modems" 0 NUMBER_OF_MODEMS=16
expect "32-char username" 0 ADMIN_USERNAME="$L32"
expect "8-char password" 0 ADMIN_PASSWORD=abcd1234
expect "128-char password" 0 ADMIN_PASSWORD="$P128"
expect "yes/no spellings" 0 BEHIND_PROXY=YES PBX_INSTALL_FOP2=No INSTALL_WEBMIN=false PBX_INSTALL_SNGREP=0 FAIL2BAN_ENABLED=on
expect "owner/repo" 0 GITHUB_REPO=scriptmgr/pbx SCRIPTS_REF=release/1.2

echo "=== bad email ==="
for v in notanemail 'a@b' "o'brien@example.org" 'a b@example.com' 'x@y.z' '$(id)@example.com' 'a@example.com;rm' '"q"@example.com' 'a@exa mple.com'; do
    expect "ADMIN_EMAIL=$v" 64 "ADMIN_EMAIL=$v"
done
expect "FAX_TO_EMAIL_ADDRESS=nope" 64 FAX_TO_EMAIL_ADDRESS=nope
expect "FROM_EMAIL=nope" 64 FROM_EMAIL=nope

echo "=== bad timezone ==="
for v in Not/AZone '../etc/passwd' 'UTC;x' "America/New_York'" 'America/New York' '/etc/passwd'; do
    expect "TIMEZONE=$v" 64 "TIMEZONE=$v"
done

echo "=== bad usernames ==="
for v in 'bad user' 'a;b' '1abc' "o'admin" "$L33" '$(id)' 'a`id`' 'a|b' 'a"b'; do
    expect "ADMIN_USERNAME=$v" 64 "ADMIN_USERNAME=$v"
done
expect "AVANTFAX_ADMIN_USERNAME=bad name" 64 "AVANTFAX_ADMIN_USERNAME=bad name"
expect "FREEPBX_ADMIN_USERNAME=a;b" 64 "FREEPBX_ADMIN_USERNAME=a;b"

echo "=== bad passwords ==="
for v in short 'has space pass' "pa'ss1234word" 'pa"ss1234word' 'pass$1234word' 'pass`1234`x' 'pass\1234word' 'pass|1234word' \
         'pass;1234word' 'pass&1234word' 'pass<1234word' "$P129"; do
    expect "ADMIN_PASSWORD=${v:0:20}" 64 "ADMIN_PASSWORD=$v"
done
expect "MYSQL_ROOT_PASSWORD with quote" 64 "MYSQL_ROOT_PASSWORD=ab'cdefgh"
expect "AVANTFAX_ADMIN_PASSWORD short" 64 AVANTFAX_ADMIN_PASSWORD=abc

echo "=== bad ports / numbers / switches ==="
for v in abc 0 65536 99999 -1 '80 ' '8080;ls' 080808; do
    expect "PROXY_HTTP_PORT=$v" 64 "PROXY_HTTP_PORT=$v"
done
expect "WEBMIN_PORT=abc" 64 WEBMIN_PORT=abc
for v in 8088 8089 5060 3306 22 025; do expect "PROXY_HTTP_PORT=$v (used by the PBX)" 64 "PROXY_HTTP_PORT=$v"; done
expect "WEBMIN_PORT=8088 (used by Asterisk)" 64 WEBMIN_PORT=8088
expect "PROXY_HTTP_PORT equals WEBMIN_PORT" 64 PROXY_HTTP_PORT=9100 WEBMIN_PORT=9100
expect "free proxy port 8190" 0 PROXY_HTTP_PORT=8190
expect "default webmin port 9001" 0 WEBMIN_PORT=9001
for v in 0 17 x -1; do expect "NUMBER_OF_MODEMS=$v" 64 "NUMBER_OF_MODEMS=$v"; done
for v in maybe 2 'yes;' perhaps; do expect "BEHIND_PROXY=$v" 64 "BEHIND_PROXY=$v"; done
expect "PBX_INSTALL_WEBMIN=maybe" 64 PBX_INSTALL_WEBMIN=maybe
expect "legacy INSTALL_WEBMIN=maybe" 64 INSTALL_WEBMIN=maybe

echo "=== bad names and repos ==="
expect "FROM_NAME with quote" 64 "FROM_NAME=O'Brien PBX"
expect "FAX_FROM_NAME with backtick" 64 'FAX_FROM_NAME=a`b'
expect "FAX_NUMBER=abc" 64 FAX_NUMBER=abc
expect "GITHUB_REPO=noslash" 64 GITHUB_REPO=noslash
expect "GITHUB_REPO=a/b;c" 64 'GITHUB_REPO=a/b;c'
expect "SCRIPTS_REF with space" 64 'SCRIPTS_REF=main now'

echo "=== messages ==="
expect "two bad settings" 64 ADMIN_EMAIL=x TIMEZONE=y
grep -q "2 invalid setting" <<< "$LAST_OUT" && ok "error count reported (2)" || fail "error count missing: $LAST_OUT"
grep -q "ADMIN_EMAIL" <<< "$LAST_OUT" && grep -q "TIMEZONE" <<< "$LAST_OUT" && ok "each bad setting named" || fail "bad settings not named"
expect "secret not echoed" 64 "ADMIN_PASSWORD=pa'ss1234word"
grep -q "pa'ss1234word" <<< "$LAST_OUT" && fail "password value was echoed" || ok "password value not echoed"
grep -q "nothing was installed" <<< "$LAST_OUT" && ok "tells the user nothing changed" || fail "no 'nothing installed' notice"

echo "=== a real install aborts before touching the system ==="
had_etc=0; [ -e /etc/pbx ] && had_etc=1
log_before=$(stat -c '%Y-%s' /var/log/pbx-install.log 2>/dev/null || echo none)
START=$(date +%s)
out=$(env -i PATH="$PATH" ADMIN_EMAIL="o'brien@example.org" timeout 60 bash "$INSTALL" 2>&1); rc=$?
ELAPSED=$(( $(date +%s) - START ))
[ "$rc" -eq 64 ] && ok "install exits 64 on bad input" || fail "install rc=$rc (wanted 64)"
[ "$ELAPSED" -le 10 ] && ok "install aborts in ${ELAPSED}s" || fail "install took ${ELAPSED}s to abort"
[ "$had_etc" -eq 0 ] && [ -e /etc/pbx ] && fail "/etc/pbx was created" || ok "/etc/pbx not created by the aborted install"
[ "$(stat -c '%Y-%s' /var/log/pbx-install.log 2>/dev/null || echo none)" = "$log_before" ] \
    && ok "install log untouched by the aborted install" || fail "install log changed during the aborted install"

echo
echo "=== SUMMARY ==="
echo "  PASSED: $PASS"
echo "  FAILED: $FAIL"
[ "$FAIL" -eq 0 ]
