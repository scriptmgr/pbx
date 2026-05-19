#!/usr/bin/env bash
# shellcheck shell=bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
##@Version           :  202605191156-git
# @@Author           :  Jason Hempstead
# @@Contact          :  git-admin@casjaysdev.pro
# @@License          :  MIT or LICENSE.md
# @@ReadME           :  fax-to-email.sh --help | README.md
# @@Copyright        :  Copyright: (c) 2026 Jason Hempstead, Casjays Developments
# @@Created          :  Tuesday, May 19, 2026 11:56 EDT
# @@File             :  fax-to-email.sh
# @@Description      :  HylaFAX FaxDispatch hook that emails an inbound fax to the configured recipient.
# @@Changelog        :  Add compliant script header; fix convention violations
# @@TODO             :
# @@Other            :
# @@Resource         :
# @@Terminal App     :  no
# @@sudo/root        :  no
# @@Template         :  shell/bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
# shellcheck disable=SC1001,SC1003,SC2001,SC2003,SC2016,SC2031,SC2090,SC2115,SC2120,SC2155,SC2199,SC2229,SC2317,SC2329
# - - - - - - - - - - - - - - - - - - - - - - - - -
VERSION="202605191156-git"
APPNAME="${0##*/}"
RUN_USER="${USER}"
SET_UID="${UID}"
SCRIPT_SRC_DIR="${BASH_SOURCE%/*}"
# - - - - - - - - - - - - - - - - - - - - - - - - -
set -eu

case "${1:-}" in
    --version|-V) printf "%s v%s\n" "$(basename "$0")" "${VERSION}"; exit 0 ;;
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
# ex: ts=2 sw=2 et filetype=sh
