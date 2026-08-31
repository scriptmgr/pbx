# Finish Commit 2: casjay-base compatibility + fail2ban visibility fix

## Context
This is a continuation of already-approved, already-in-progress work in this
session — not a new feature. Commit 1 (creds.conf rename) already landed and
pushed (`961530446f6a`). The remaining install.sh hunks (casjay-base
postfix/fail2ban satellite-relay and jail.local coexistence, plus a
silent-failure fix in fail2ban restart/verify status reporting) were already
written, reviewed, and are sitting unstaged in the working tree (popped from
stash). `.git/COMMIT_MESS` for this commit is already written and verified
against `git diff install.sh`. A `script-lint` agent (id a700ef2357efa1082)
is already running in the background to satisfy the lint gate.

No design decisions remain — this plan exists only to satisfy plan-mode's
requirement of an explicit plan file before continuing.

## Remaining steps
1. Wait for the in-flight `script-lint` agent to report back (PASS/FAIL on
   the install.sh hunks: casjay-base postfix detection, jail.local detection,
   jail.d backups, post-restart active check, verify_installation check).
2. If PASS: run `gitcommit --dir /root/Projects/github/scriptmgr/pbx all`
   for Commit 2, using the already-written `.git/COMMIT_MESS`.
3. If FAIL: fix the flagged issues in `install.sh`, re-run `bash -n
   install.sh`, re-run script-lint, then commit.
4. After push, check triggered CI run status if this repo has CI config
   (none confirmed yet this session).
5. Note to user (not yet actioned): AI.md's Testing Rules call for testing
   on both alma9 and deb12 — only alma9 (`pbx-alma9`) has been verified this
   session; deb12 (`pbx-deb12`) testing is still outstanding.

## Verification
- `bash -n install.sh` already passed (syntax OK).
- script-lint agent result pending.
- After commit: `git log -1 --stat` to confirm the commit contains exactly
  the install.sh hunks described in COMMIT_MESS, and `git status --porcelain`
  is clean.
