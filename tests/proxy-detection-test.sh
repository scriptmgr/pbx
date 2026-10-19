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

printf '\nSummary: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
