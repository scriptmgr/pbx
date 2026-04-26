<?php
/**
 * Telephone Reminder — schedule a callback for any extension.
 *
 * Auth: any logged-in FreePBX user (UCP user OR admin). Enforced via the
 * FPM auth-shim (path-prefix /reminder/) AND defensively at the top of
 * this file in case the shim is disabled.
 *
 * Edit web/reminder/index.php upstream — install.sh deploys this file.
 */

require_once '/etc/pbx/web/_shared/pbx-auth.php';
$page_user = pbx_require_login(false);

$reminders_file = '/etc/asterisk/reminders.txt';
$ok  = '';
$err = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $phone = preg_replace('/[^0-9*#]/', '', $_POST['phone'] ?? '');
    $time  = $_POST['time']    ?? '';
    $msg   = substr(strip_tags($_POST['message'] ?? 'This is your reminder'), 0, 200);

    if ($phone === '' || $time === '') {
        $err = 'Extension/phone and date/time are required.';
    } else {
        $ts = strtotime($time);
        if ($ts === false) {
            $err = 'Could not parse the date/time.';
        } elseif ($ts < time() - 60) {
            $err = 'Reminder time is in the past.';
        } elseif (!is_writable($reminders_file)) {
            $err = "Reminder file is not writable. Check ownership of {$reminders_file}.";
        } else {
            $line = sprintf("%d|%s|%s\n", $ts, $phone, $msg);
            file_put_contents($reminders_file, $line, FILE_APPEND | LOCK_EX);
            $ok = sprintf(
                'Reminder scheduled for %s → extension %s',
                date('Y-m-d H:i', $ts),
                htmlspecialchars($phone)
            );
        }
    }
}

// Show the user's pending reminders (filtered to lines they can see — admins
// see everything; UCP users see only reminders matching their primary extension).
$pending = [];
if (is_readable($reminders_file)) {
    $own_ext = '';
    if (!$page_user['is_admin']) {
        $um = $GLOBALS['__pbx_freepbx']->Userman ?? null;
        if ($um) {
            $u = $um->getUserByID($page_user['id']);
            $own_ext = (string)($u['default_extension'] ?? '');
        }
    }
    foreach (file($reminders_file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $row) {
        [$ts, $ph, $m] = array_pad(explode('|', $row, 3), 3, '');
        if (!ctype_digit($ts) || (int)$ts < time()) continue;
        if (!$page_user['is_admin'] && $own_ext !== '' && $ph !== $own_ext) continue;
        $pending[] = ['ts' => (int)$ts, 'phone' => $ph, 'msg' => $m];
    }
    usort($pending, fn($a, $b) => $a['ts'] <=> $b['ts']);
}

$page_title = 'Telephone Reminder';
require '/etc/pbx/web/_shared/pbx-layout.php';
?>

<section class="pbx-card">
    <h1>⏰ Schedule a Telephone Reminder</h1>
    <p style="color:var(--pbx-muted);margin:0 0 14px;">
        At the scheduled time the system will originate a call to the chosen
        extension and play your message.
    </p>

    <?php if ($ok): ?>
        <div class="pbx-msg ok"><?= $ok ?></div>
    <?php endif; ?>
    <?php if ($err): ?>
        <div class="pbx-msg err"><?= htmlspecialchars($err) ?></div>
    <?php endif; ?>

    <form method="post" autocomplete="off">
        <label for="r-phone">Extension or Phone Number</label>
        <input id="r-phone" type="tel" name="phone"
               placeholder="1001 or 5551234567"
               pattern="[0-9*#]+" required>

        <label for="r-time">Reminder Date &amp; Time</label>
        <input id="r-time" type="datetime-local" name="time"
               min="<?= date('Y-m-d\TH:i') ?>" required>

        <label for="r-msg">Message (read via TTS)</label>
        <textarea id="r-msg" name="message" rows="3"
                  maxlength="200">This is your telephone reminder.</textarea>

        <div style="margin-top:18px;">
            <button class="pbx-btn" type="submit">📅 Schedule Reminder</button>
        </div>
    </form>
</section>

<?php if ($pending): ?>
<section class="pbx-card">
    <h2>Upcoming reminders<?= $page_user['is_admin'] ? '' : ' for your extension' ?></h2>
    <table style="width:100%; border-collapse:collapse; font-size:14px;">
        <thead>
            <tr style="text-align:left; color:var(--pbx-muted); font-size:12px;">
                <th style="padding:8px 4px; border-bottom:1px solid var(--pbx-border);">When</th>
                <th style="padding:8px 4px; border-bottom:1px solid var(--pbx-border);">Extension</th>
                <th style="padding:8px 4px; border-bottom:1px solid var(--pbx-border);">Message</th>
            </tr>
        </thead>
        <tbody>
        <?php foreach ($pending as $r): ?>
            <tr>
                <td style="padding:8px 4px; border-bottom:1px solid var(--pbx-border);">
                    <?= date('Y-m-d H:i', $r['ts']) ?>
                </td>
                <td style="padding:8px 4px; border-bottom:1px solid var(--pbx-border);">
                    <?= htmlspecialchars($r['phone']) ?>
                </td>
                <td style="padding:8px 4px; border-bottom:1px solid var(--pbx-border); color:var(--pbx-muted);">
                    <?= htmlspecialchars($r['msg']) ?>
                </td>
            </tr>
        <?php endforeach; ?>
        </tbody>
    </table>
</section>
<?php endif; ?>

<?php require '/etc/pbx/web/_shared/pbx-layout-foot.php'; ?>
