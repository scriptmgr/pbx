# TODO

- `pbx-status-update` cron job (`/usr/local/bin/pbx-status-update`, invoked
  by `/etc/cron.d/pbx-status`) silently fails all Asterisk-derived
  health/status fields (`asterisk_version`, `asterisk_uptime`,
  `active_calls`, `registered_endpoints`, `total_endpoints` in `/health/`
  and `/status/` JSON) because cron's minimal default PATH
  (`/usr/bin:/bin`) doesn't include `/usr/sbin`, where `asterisk` lives.
  Confirmed via full beta test on both pbx-alma9 and pbx-deb12 — same
  bug on both distros, not a regression from any recent change. Fix:
  set `PATH=/usr/sbin:/usr/bin:/sbin:/bin` in `/etc/cron.d/pbx-status`,
  or use the full path `/usr/sbin/asterisk` in `pbx-status-update`.

- Fax status polling (`faxstat`) fails non-interactively on both alma9 and
  deb12 (`500 'PASS ': Syntax error, expecting password`), and modem
  status files show a persistent "Waiting for modem to come ready" state,
  despite `hosts.hfaxd` trusting localhost and iaxmodem/IAX peers being
  present and healthy. Confirmed cross-distro, pre-existing, not caught by
  any of the 5 test suites since none assert non-interactive faxstat
  output. Needs investigation — likely an interactive-vs-daemon auth or
  session context difference in the iaxmodem/hfaxd stack.

- No `creds.conf` backup-on-reinstall mechanism exists: `install.sh`
  appends/updates fields in place on `AUTO_PASSWORDS_FILE` re-runs rather
  than renaming the prior file to a timestamped backup. Confirmed by
  reading all `AUTO_PASSWORDS_FILE` usages in install.sh (lines
  1546-2281, 6765-7883) and by the absence of any `.bak`/timestamped
  variant in `/etc/pbx/` on either alma9 or deb12. Flagging in case this
  was assumed to exist — no action taken, not confirmed to be a bug
  (may be intentional).
