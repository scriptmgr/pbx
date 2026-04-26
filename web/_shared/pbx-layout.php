<?php
/**
 * pbx-layout.php — shared HTML chrome (header + footer).
 *
 * Usage:
 *   $page_title = 'Telephone Reminder';
 *   require '/etc/pbx/web/pbx-layout.php';   // emits doctype + header
 *   ... page body ...
 *   require '/etc/pbx/web/pbx-layout-foot.php';
 *
 * If $page_user (array from pbx_current_user) is set, the header shows the
 * username + sign-out link.
 */

$pbx_brand_name = $pbx_brand_name ?? (getenv('FROM_NAME') ?: 'PBX System');
$pbx_brand_initials = strtoupper(substr(preg_replace('/[^A-Za-z]/', '', $pbx_brand_name) ?: 'P', 0, 2));
$page_title = $page_title ?? $pbx_brand_name;
?><!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title><?= htmlspecialchars($page_title) ?></title>
<link rel="stylesheet" href="/pbx-assets/pbx-style.css">
</head>
<body>
<header class="pbx-topbar">
    <div class="pbx-brand">
        <span class="pbx-logo"><?= htmlspecialchars($pbx_brand_initials) ?></span>
        <a href="/" style="color:inherit;"><?= htmlspecialchars($pbx_brand_name) ?></a>
    </div>
    <nav class="pbx-nav">
        <a href="/admin/">Admin</a>
        <a href="/ucp/">UCP</a>
        <?php if (!empty($page_user)): ?>
            <span class="pbx-user">
                Signed in as <strong><?= htmlspecialchars($page_user['name']) ?></strong>
                <?= $page_user['is_admin'] ? '(admin)' : '' ?>
                · <a href="<?= $page_user['is_admin'] ? '/admin/config.php?logout=true' : '/ucp/?quietmode=1&logout=true' ?>">Sign out</a>
            </span>
        <?php endif; ?>
    </nav>
</header>
<main class="pbx-shell">
