#!/bin/bash
# email-to-fax.sh — MTA pipe target: ship an inbound email out as a fax.
#
# Wired in /etc/aliases (or postfix virtual_aliases) — the MTA pipes the
# raw RFC822 message to stdin. Subject must contain the destination fax
# number (digits only, 7–15 chars).
set -e

SCRIPT_VERSION="${SCRIPT_VERSION:-3.0}"
case "${1:-}" in
    --version|-V) printf "%s v%s\n" "$(basename "$0")" "${SCRIPT_VERSION}"; exit 0 ;;
    --help|-h)
        printf "Usage: email-to-fax.sh   (MTA pipes message on stdin)\n\n"
        printf "The destination fax number is parsed from the Subject header.\n"
        exit 0 ;;
esac

SPOOL_DIR="${EMAIL_TO_FAX_SPOOL:-/var/spool/fax/email}"
mkdir -p "${SPOOL_DIR}"

EMAIL_FILE="${SPOOL_DIR}/fax-$(date +%s)-$$.eml"
cat > "${EMAIL_FILE}"

FAX_NUM=$(grep -i '^Subject:' "${EMAIL_FILE}" | grep -oE '[0-9]{7,15}' | head -1 || true)
if [ -n "${FAX_NUM}" ]; then
    sendfax -n -d "${FAX_NUM}" "${EMAIL_FILE}" 2>/dev/null || true
else
    logger -t email-to-fax "no fax number in Subject — dropping ${EMAIL_FILE}"
fi
rm -f "${EMAIL_FILE}"
