# TODO

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

- Commits `6cb210cad04f`, `ce1fb51e7665`, and `da0776a581ea` (this
  session, faxstat/creds/module-retry fixes) used subject lines of 64,
  63, and 67 characters — AI.md's Commit Rules cap subject lines at 56
  chars, which these exceed (67 also exceeds the global 64-char cap).
  Followed the global gitcommit convention instead of re-checking
  AI.md's stricter project override before writing those commit
  messages. Not rewriting already-pushed history for this; flagging so
  future commit messages in this repo respect the 56-char limit.
