#!/bin/bash
# Regression tests for reverse proxy detection and explicit setting precedence.
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${TEST_DIR}/../install.sh"

PASS=0
FAIL=0

ok() {
    printf '  PASS: %s\n' "$*"
    PASS=$((PASS + 1))
}

fail() {
    printf '  FAIL: %s\n' "$*"
    FAIL=$((FAIL + 1))
}

# shellcheck disable=SC2329
ss() {
    printf '%s\n' 'LISTEN 0 511 *:443 *:* users:(("nginx",pid=123,fd=4))'
}

BEHIND_PROXY_AUTO_DETECTED="no"
resolve_behind_proxy auto no
if [ "${BEHIND_PROXY}" = "yes" ] && [ "${BEHIND_PROXY_AUTO_DETECTED}" = "yes" ]; then
    ok "active Nginx listener enables proxy mode"
else
    fail "active Nginx listener was not detected"
fi

BEHIND_PROXY_AUTO_DETECTED="yes"
resolve_behind_proxy no no
if [ "${BEHIND_PROXY}" = "no" ] && [ "${BEHIND_PROXY_AUTO_DETECTED}" = "no" ]; then
    ok "explicit no overrides detected proxy"
else
    fail "explicit no did not override detected proxy"
fi

BEHIND_PROXY_AUTO_DETECTED="yes"
resolve_behind_proxy yes no
if [ "${BEHIND_PROXY}" = "yes" ] && [ "${BEHIND_PROXY_AUTO_DETECTED}" = "no" ]; then
    ok "explicit yes overrides automatic mode"
else
    fail "explicit yes did not become a saved override"
fi

# shellcheck disable=SC2329
ss() {
    return 0
}

BEHIND_PROXY_AUTO_DETECTED="no"
resolve_behind_proxy auto no
if [ "${BEHIND_PROXY}" = "no" ] && [ "${BEHIND_PROXY_AUTO_DETECTED}" = "yes" ]; then
    ok "no proxy listener selects direct mode"
else
    fail "no proxy listener did not select direct mode"
fi

TEST_TEMP_ROOT="${TMPDIR:-/tmp}/github"
mkdir -p "${TEST_TEMP_ROOT}"
TEST_TEMP_DIR=$(mktemp -d "${TEST_TEMP_ROOT}/pbx-listeners-XXXXXX")
cleanup_test_temp() {
    if [[ -n "${TEST_TEMP_DIR:-}" && -d "${TEST_TEMP_DIR}" && ! -L "${TEST_TEMP_DIR}" \
        && "${TEST_TEMP_DIR}" == "${TEST_TEMP_ROOT}/pbx-listeners-"* ]]; then
        rm -rf -- "${TEST_TEMP_DIR}"
    fi
}
trap cleanup_test_temp EXIT

PORTS_FILE="${TEST_TEMP_DIR}/ports.conf"
printf 'Listen 127.0.0.1:63504\nListen 127.0.0.1:60001\nListen 127.0.0.1:8080\n' > "${PORTS_FILE}"
restore_apache_direct_listeners "${PORTS_FILE}" 1 63504
RESTORED_PORTS=$(awk '$1 == "Listen" { port = $2; sub(/^.*:/, "", port); print port }' "${PORTS_FILE}")
if [ "${RESTORED_PORTS}" = "60001
8080
80
443" ]; then
    ok "direct mode restores HTTP and HTTPS listeners and preserves other listeners"
else
    fail "direct mode did not restore HTTP and HTTPS listeners"
fi

RESTORED_CONFIG=$(cat "${PORTS_FILE}")
restore_apache_direct_listeners "${PORTS_FILE}" 1 63504
if [ "${RESTORED_CONFIG}" = "$(cat "${PORTS_FILE}")" ]; then
    ok "direct listener restoration is idempotent"
else
    fail "direct listener restoration added duplicate listeners"
fi

printf '\nSummary: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
