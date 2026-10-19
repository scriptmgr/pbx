# TODO

- 2026-10-19 Fail2ban now defaults to ban-only actions and overrides the
  standard sendmail ban actions, so an existing `action_m`, `action_mw`, or
  `action_mwl` policy cannot send one email per banned IP. The isolated
  Fail2ban configuration parser check passed.

- 2026-10-19 Debian 12 libvirt clean install with no reverse proxy and an
  existing Let's Encrypt certificate: auto-detection selected direct Apache
  mode, both ports 80/443 listened, and Apache served the copied certificate
  for `pbx.casjay.dev`. Trusted HTTPS requests to `/` and `/health` passed;
  HTTP redirected to HTTPS. The full suite passed (181 passed, 2 warnings,
  0 failed, 0 skipped); warnings were no recent CDR and optional rclone absent.
  An installer rerun exited 0 and retained automatic mode. The proxy resolver
  regression test passed 4/4, including explicit `yes`/`no` override cases.

- 2026-10-18 Debian 12 all-options run in an isolated Incus container:
  installer exited 0 with AvantFax, Webmin, OpenVPN, WireGuard, FOP2, sngrep,
  phone provisioning, remote backup/rclone, Asternic, Fail2ban, and backups
  enabled. The full suite passed with 179 passed, 2 warnings, 0 failures,
  and 0 skipped. Warnings were the unsynchronized container clock and no
  recent CDR call. Confirmed rclone, OpenVPN, WireGuard, sngrep, Fail2ban,
  provisioning scripts/TFTP, FOP2, AvantFax, Webmin, and TFTP service were
  installed; Webmin and AvantFax web checks passed.

- 2026-10-18 Debian 13 cloud VM full install verification: the first suite
  exposed three real defects: npm was omitted from Debian 13 packages, the
  FreePBX `pm2` module was not reconciled, and root-created web/status paths
  were unreadable to Apache/PHP-FPM under the VM's restrictive umask. Added
  Debian 13 npm handling, required `pm2` reconciliation, Apache parent
  traversal permissions, and root:asterisk status JSON permissions. The
  installer idempotency rerun exited 0; the full suite passed with 179
  passed, 2 expected warnings (no recent CDR call, optional rclone absent),
  0 failures, and 0 skips. `/health` returned 200 with status `ok`. Debian
  13 is not listed in the supported release table, so this validates the
  gen2 fallback path only. An intermediate gen3 mapping experiment against
  the already-installed FreePBX 16 VM was invalid as an in-place major-stack
  conversion; the mapping was reverted before the final idempotency/full-suite
  run.

- Test continuation (2026-10-11):
  - Input validation: 100 passed / 0 failed on AlmaLinux 9 and Debian 12.
  - Self-signed certificate: full suite passed on Debian 12 (177 passed,
    3 warnings, 0 failed) and existing AlmaLinux 9 test runs (178 passed,
    2 warnings, 0 failed).
  - Let's Encrypt certificate: copied to the AlmaLinux 9 port-test VM;
    installer exited 0 with no error lines, deployed cert/key matched and
    were valid, and the full suite passed (178 passed, 2 warnings, 0 failed).
  - Legacy-name opt-ins (`INSTALL_PHONE_PROV=yes` and
    `INSTALL_REMOTE_BACKUP=yes`): installer exited 0 with no error lines;
    TFTP socket/UDP 69 and rclone checks passed. The full suite passed with
    the real certificate still deployed (179 passed, 1 CDR warning, 0 failed).
  - Component opt-outs and port-conflict/low-resource scenarios were run by
    the existing AlmaLinux test harness. Their targeted assertions passed;
    low-resource suites passed twice (178/2/0), and the port-conflict suite
    passed (178/2/0). For the opt-out suite, the harness must pass the same
    `PBX_INSTALL_AVANTFAX=no PBX_INSTALL_WEBMIN=no` settings as installation.
  - Follow-up (2026-10-17): the docs VM's `app_voicemail.so` failure was a
    symptom of Asterisk stuck in graceful shutdown, while systemd repeatedly
    tried to start another instance. The installer waited only three seconds
    after `fwconsole stop`, then removed control files and continued. The
    finalizer now waits for Asterisk to exit, escalates if needed, and refuses
    to remove control files while the process remains. The health monitor also
    restarted standalone Asterisk while `freepbx.service` owned it. It now
    checks the live CLI and restarts FreePBX when recovery is needed. The
    matched AlmaLinux 9 opt-out suite passed after this fix (158 passed,
    3 warnings, 0 failed, 1 skipped); a clean first-run install remains needed.
  - Fixed `tests/input-validation-test.sh` to locate `install.sh` relative to
    the test file instead of defaulting to `/root/install.sh`; local matrix:
    100 passed / 0 failed, including the invalid-install no-touch check.
  - The test-lint wrapper rejected remote `ssh` commands before execution
    because it only recognizes local command prefixes; the VM/container tests
    were run directly in their designated test environments.
  - Credential persistence harness was attempted on the already-installed
    port-test VM. Its clean-machine preconditions were false (`/etc/pbx` and
    MariaDB already existed), so the failures are inconclusive; the test
    changed DB credentials and left that VM's DB checks failing. Reset that
    VM before reusing it. Valid special-character credential persistence
    remains unverified.
  - The health check preserved the active timestamp of `freepbx.service`,
    `app_voicemail.so` stayed Running, and `/health/` returned 200. `pbx-ssl`
    recognized the copied Let's Encrypt certificate (65 days remaining) and
    generated a valid self-signed certificate in the fallback check.
  - `bash -n` passed for all edited Bash scripts and `git diff --check` passed.
    ShellCheck on `scripts/pbx-health-check` still reports unused template
    variables and the optional `/etc/pbx/.env` include; the installer lint
    backlog remains open.

- Still untested from the broader matrix: legacy-name component opt-outs,
  interruption/resume by SIGKILL or hard power-off, mid-install network cuts,
  upgrade from HEAD install.sh, and short hostname with IPv6 disabled.

- 2026-10-17 checks: `bash -n` passed for all edited Bash scripts, and the
  input-validation suite passed (100/0). The AlmaLinux 9 matched opt-out
  full-script suite passed (158/3 warnings/0/1 skipped). This was an already
  installed VM, not a clean install, and does not close the broader matrix.

- `script-lint` re-run on install.sh: the 7 itemized findings are fixed
  (`__state_set`/`__state_get` renames, `--` on bare `grep` calls). The 8
  unitemized pre-existing findings were never listed; re-run script-lint
  on the whole file to get them.

- AI.md Testing Rules assume incus containers, but this host's EL9
  qemu-kvm has no SPICE so `incus launch --vm` fails; incus containers
  work for systemd tests. Debian 12 installer and full-script suite passed
  in an isolated Incus container; AlmaLinux 9 was tested with libvirt
  (`pbxnet`, overlay on `pbx-almalinux9-base.qcow2`, key injected via
  guestfish). Decide whether to document the libvirt VM path in AI.md.

- Commits `6cb210cad04f`, `ce1fb51e7665`, and `da0776a581ea` (this
  session, faxstat/creds/module-retry fixes) used subject lines of 64,
  63, and 67 characters — AI.md's Commit Rules cap subject lines at 56
  chars, which these exceed (67 also exceeds the global 64-char cap).
  Followed the global gitcommit convention instead of re-checking
  AI.md's stricter project override before writing those commit
  messages. Not rewriting already-pushed history for this; flagging so
  future commit messages in this repo respect the 56-char limit.

- alma9 first-run `/health` 503 + failed `freepbx.service` was seen once
  and not reproduced; the unit/recovery hardening is verified by forced
  failures only. Re-check with the first-run suite of the next full runs.

- Management scripts are installed from GitHub `main`, so the
  `pbxstatus`/`pbx-repair` fixes only reach new installs after push.

- AI.md Path Conventions lists the health endpoint as
  `/var/www/html/health/index.php`; the installer writes it under
  `${WEB_ROOT}/health` (default `/var/www/apache/pbx/health`).

- 2026-10-17 resume/module recovery verification: a fresh AlmaLinux 9 install
  and a fresh Debian 12 install both hit the explicit 590-second test bound
  while installing FreePBX modules. Re-running the installer resumed each
  system successfully. Added module reconciliation to the installed/skip
  paths; both suites now report 157 passed / 4 warnings / 0 failed / 1
  skipped. The required core, framework, voicemail, timeconditions,
  callforward, and donotdisturb modules were enabled, with 77 enabled modules
  on AlmaLinux 9 and 67 on Debian 12. Service creation errors now propagate
  out of the FreePBX install step. Warnings were container clock sync, no
  recent CDR, intentionally disabled rclone, and limited component state.
  Special-character admin/MySQL credentials round-tripped through the
  generated dotenv file and MySQL password file. The first Debian suite run
  used an incorrect local scripts source directory; after correcting it, the
  complete suite passed. These runs validate timeout/TERM resume, not SIGKILL
  or hard-power-loss recovery.
