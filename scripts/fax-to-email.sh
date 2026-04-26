#!/bin/bash
# fax-to-email.sh — HylaFAX FaxDispatch hook: email an inbound fax.
#
# HylaFAX calls: fax-to-email.sh <fax-file> <fax-from> <fax-pages>
# Recipient + From identity are read from /etc/pbx/.env at runtime so
# changing FAX_TO_EMAIL_ADDRESS doesn't require a re-install.
set -eu

SCRIPT_VERSION="${SCRIPT_VERSION:-3.0}"
case "${1:-}" in
    --version|-V) printf "%s v%s\n" "$(basename "$0")" "${SCRIPT_VERSION}"; exit 0 ;;
    --help|-h)
        printf "Usage: fax-to-email.sh <fax-file> <fax-from> <fax-pages>\n\n"
        printf "Email an inbound HylaFAX-received fax. Configured via /etc/pbx/.env:\n"
        printf "  FAX_TO_EMAIL_ADDRESS  recipient (default: ADMIN_EMAIL)\n"
        printf "  FAX_FROM_EMAIL        envelope From (default: FROM_EMAIL)\n"
        printf "  FAX_FROM_NAME         display From (default: FROM_NAME)\n"
        exit 0 ;;
esac

[ -f /etc/pbx/.env ] && . /etc/pbx/.env 2>/dev/null || true

FAX_FILE="${1:-}"
FAX_FROM="${2:-unknown}"
FAX_PAGES="${3:-?}"
[ -z "${FAX_FILE}" ] && exit 1

TO="${FAX_TO_EMAIL_ADDRESS:-${ADMIN_EMAIL:-root@localhost}}"
MAIL_FROM="${FAX_FROM_EMAIL:-${FROM_EMAIL:-no-reply@localhost}}"
MAIL_FROM_NAME="${FAX_FROM_NAME:-${FROM_NAME:-PBX Fax System}}"

SUBJECT="Incoming Fax from ${FAX_FROM} (${FAX_PAGES} pages)"
BODY="You have received a fax from ${FAX_FROM}. See attachment."

if command -v uuencode >/dev/null 2>&1; then
    ( echo "${BODY}"; uuencode "${FAX_FILE}" fax.pdf ) \
        | mail -s "${SUBJECT}" -a "From: ${MAIL_FROM_NAME} <${MAIL_FROM}>" "${TO}" 2>/dev/null || true
elif command -v mutt >/dev/null 2>&1; then
    echo "${BODY}" | mutt -s "${SUBJECT}" \
        -e "my_hdr From: ${MAIL_FROM_NAME} <${MAIL_FROM}>" \
        -a "${FAX_FILE}" -- "${TO}" 2>/dev/null || true
else
    logger -t fax-to-email "no MUA available (need uuencode or mutt) — fax not delivered to ${TO}"
fi
