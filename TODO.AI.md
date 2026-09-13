# TODO

- No `creds.conf` backup-on-reinstall mechanism exists: `install.sh`
  appends/updates fields in place on `AUTO_PASSWORDS_FILE` re-runs rather
  than renaming the prior file to a timestamped backup. Confirmed by
  reading all `AUTO_PASSWORDS_FILE` usages in install.sh (lines
  1546-2281, 6765-7883) and by the absence of any `.bak`/timestamped
  variant in `/etc/pbx/` on either alma9 or deb12. Flagging in case this
  was assumed to exist — no action taken, not confirmed to be a bug
  (may be intentional).

- `script-lint` pass on install.sh (pre-existing, not touched by this
  session's edits — 0 new issues introduced):
  - line 1039: function `state_set()` missing `__` prefix → rename to
    `__state_set()`
  - line 1048: function `state_get()` missing `__` prefix → rename to
    `__state_get()`
  - line 1050: `grep "^${1}="` missing `--` before pattern → `grep --
    "^${1}="`
  - line 3167: `grep "^PROXY_HTTP_PORT="` missing `--` before pattern →
    `grep -- "^PROXY_HTTP_PORT="`
  - line 8053: `grep "^port="` missing `--` before pattern → `grep --
    "^port="`
  - line 8155: `grep "^PROXY_HTTP_PORT="` missing `--` before pattern →
    `grep -- "^PROXY_HTTP_PORT="`
  - line 8178: `grep "^PROXY_HTTP_PORT="` missing `--` before pattern →
    `grep -- "^PROXY_HTTP_PORT="`
  - (script-lint reported 15 pre-existing findings total; only 7 were
    itemized in its summary — re-run script-lint on the whole file to
    get the remaining 8 before fixing this batch)
