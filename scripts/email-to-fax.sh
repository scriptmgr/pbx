#!/usr/bin/env bash
# shellcheck shell=bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
##@Version           :  202605191156-git
# @@Author           :  Jason Hempstead
# @@Contact          :  git-admin@casjaysdev.pro
# @@License          :  MIT or LICENSE.md
# @@ReadME           :  email-to-fax.sh --help | README.md
# @@Copyright        :  Copyright: (c) 2026 Jason Hempstead, Casjays Developments
# @@Created          :  Tuesday, May 19, 2026 11:56 EDT
# @@File             :  email-to-fax.sh
# @@Description      :  MTA pipe target that ships an inbound email out as a fax.
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
set -e

case "${1:-}" in
    --version|-V) printf "%s v%s\n" "$(basename "$0")" "${VERSION}"; exit 0 ;;
    --help|-h)
        printf "Usage: email-to-fax.sh   (MTA pipes message on stdin)\n\n"
        printf "The destination fax number is parsed from the Subject header.\n"
        exit 0 ;;
esac

SPOOL_DIR="${EMAIL_TO_FAX_SPOOL:-/var/spool/fax/email}"
mkdir -p "${SPOOL_DIR}"

EMAIL_FILE="${SPOOL_DIR}/fax-$(date +%s)-$$.eml"
cat > "${EMAIL_FILE}"

FAX_NUM=$(grep -i -- '^Subject:' "${EMAIL_FILE}" | grep -oE '[0-9]{7,15}' | head -1 || true)
if [ -n "${FAX_NUM}" ]; then
    sendfax -n -d "${FAX_NUM}" "${EMAIL_FILE}" 2>/dev/null || true
else
    logger -t email-to-fax "no fax number in Subject — dropping ${EMAIL_FILE}"
fi
rm -f "${EMAIL_FILE}"
# ex: ts=2 sw=2 et filetype=sh
