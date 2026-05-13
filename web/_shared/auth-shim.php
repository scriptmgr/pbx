<?php
/**
 * auth-shim.php — PHP-FPM auto_prepend_file gate for path-based auth.
 *
 * Wired in via php_admin_value[auto_prepend_file] in the primary FPM pool.
 * Runs on every PHP request the pool handles. To stay cheap (and to avoid
 * accidentally double-auth-ing the FreePBX admin / UCP itself, which manage
 * their own sessions), it only acts on URI prefixes listed in PBX_GATED_PATHS.
 *
 * Edit /etc/pbx/web/auth-shim.php to add more gated prefixes.
 */

$uri = $_SERVER['REQUEST_URI'] ?? '';
// Strip query string for matching.
$path = ($q = strpos($uri, '?')) === false ? $uri : substr($uri, 0, $q);

$PBX_GATED_PATHS = [
    '/callcenter/' => false,   // any UCP user or admin
    '/reminder/'   => false,   // any UCP user or admin
];

foreach ($PBX_GATED_PATHS as $prefix => $admin_required) {
    if (strncmp($path, $prefix, strlen($prefix)) === 0) {
        require_once '/etc/pbx/web/_shared/pbx-auth.php';
        pbx_require_login((bool)$admin_required);
        break;
    }
}

// After UCP login, ucp.js calls location.reload() which re-requests
// /ucp/?next=<encoded-path>. If the user is now authenticated, redirect
// them to the original target rather than leaving them on the UCP dashboard.
if (strncmp($path, '/ucp', 4) === 0 && isset($_GET['next'])) {
    $next = $_GET['next'];
    if (preg_match('#^/[A-Za-z0-9_\-./?&=%]*$#', $next)) {
        require_once '/etc/pbx/web/_shared/pbx-auth.php';
        if (pbx_current_user() !== null) {
            header('Location: ' . $next, true, 302);
            exit;
        }
    }
}
