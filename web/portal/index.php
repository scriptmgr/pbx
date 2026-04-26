<?php
/**
 * Portal landing page (served as DirectoryIndex on /).
 *
 * Public — no auth. Each tile links to a sub-app whose own auth gate kicks
 * in on follow-through (FreePBX admin, UCP, FPM auth-shim, etc.).
 *
 * Edit web/portal/index.php upstream — install.sh deploys this file.
 */

// FROM_NAME from /etc/pbx/.env, exposed to PHP via Apache SetEnv on the vhost
// (see install_web_assets in install.sh). Falls back to a generic title.
$pbx_brand_name = getenv('PBX_BRAND_NAME') ?: (getenv('FROM_NAME') ?: 'PBX Server');

$tiles = [
    ['/admin/',      'FreePBX Admin',     'PBX management',         '⚙️'],
    ['/ucp/',        'User Portal',       'End-user self-service',  '👤'],
    ['/avantfax/',   'Fax (AvantFax)',    'Send & receive faxes',   '📠'],
    ['/callcenter/', 'Call Center Stats', 'Queue + agent reports',  '📊'],
    ['/asteridex/',  'AsteriDex',         'Phone directory',        '📖'],
    ['/reminder/',   'Telephone Reminder','Schedule a callback',    '⏰'],
    ['/status/',     'System Status',     'Live health JSON',       '💚'],
    ['https://' . htmlspecialchars($_SERVER['HTTP_HOST'] ?? 'localhost', ENT_QUOTES) . ':9001/',
                     'Webmin',            'OS administration',      '🖥️'],
];

$page_title = $pbx_brand_name;
require '/etc/pbx/web/_shared/pbx-layout.php';
?>

<section class="pbx-card" style="text-align:center;">
    <h1 style="font-size:26px;">🏢 <?= htmlspecialchars($pbx_brand_name) ?></h1>
    <p style="color:var(--pbx-muted);margin:0;">
        Choose a tool below. Sign in is handled by the destination service.
    </p>
</section>

<section class="pbx-grid">
    <?php foreach ($tiles as [$url, $name, $desc, $icon]): ?>
        <a class="pbx-tile" href="<?= htmlspecialchars($url) ?>">
            <div class="pbx-tile-icon"><?= $icon ?></div>
            <div class="pbx-tile-title"><?= htmlspecialchars($name) ?></div>
            <div class="pbx-tile-sub"><?= htmlspecialchars($desc) ?></div>
        </a>
    <?php endforeach; ?>
</section>

<?php require '/etc/pbx/web/_shared/pbx-layout-foot.php'; ?>
