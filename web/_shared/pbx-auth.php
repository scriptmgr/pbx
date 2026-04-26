<?php
/**
 * pbx-auth.php — central auth gate for custom PBX web pages.
 *
 * Lives at /etc/pbx/web/pbx-auth.php (NOT under WEB_ROOT — never web-served).
 * Bootstraps FreePBX, then exposes:
 *
 *   pbx_require_login(bool $admin_required = false)
 *     - If a FreePBX admin (ampusers row, AMP_user session) is logged in: pass.
 *     - If a UCP user is logged in (Userman session): pass — unless $admin_required.
 *     - Otherwise redirect to FreePBX's existing login page (/admin/config.php
 *       for admin-required pages, /ucp/ for end-user pages), with ?next=
 *       set so the user lands back here after auth.
 *
 *   pbx_current_user(): array{id:int, name:string, is_admin:bool}|null
 *     - Returns the logged-in identity, or null if anonymous.
 *
 * Designed to fail closed: any error during bootstrap → 503 with no body.
 */

if (defined('PBX_AUTH_LOADED')) { return; }
define('PBX_AUTH_LOADED', true);

// Bootstrap FreePBX BEFORE session_start() — $_SESSION['AMP_user'] is a
// serialized `ampuser` instance, and PHP needs the class loaded at unserialize
// time or it becomes an incomplete object (Whoops will then yell).
if (!isset($GLOBALS['__pbx_freepbx'])) {
    if (!is_file('/etc/freepbx.conf')) {
        http_response_code(503);
        exit;
    }
    try {
        $bootstrap_settings = ['skip_astman' => true];
        require_once '/etc/freepbx.conf';
        $GLOBALS['__pbx_freepbx'] = \FreePBX::create();
        $ampuser_class = $GLOBALS['__pbx_freepbx']->Config->get('AMPWEBROOT')
            . '/admin/libraries/ampuser.class.php';
        if (is_file($ampuser_class)) {
            require_once $ampuser_class;
        }
    } catch (Throwable $e) {
        http_response_code(503);
        exit;
    }
}

if (session_status() !== PHP_SESSION_ACTIVE) {
    @session_start();
}

/**
 * Build the canonical "current user" record by inspecting the active sessions.
 * FreePBX admin sets $_SESSION['AMP_user']; UCP sets $_SESSION['ucp']['user']
 * (modern UCP) or $_SESSION['UCP/User']/$_SESSION['username'] on older builds.
 */
function pbx_current_user(): ?array {
    // FreePBX admin (ampusers row).
    if (!empty($_SESSION['AMP_user']) && is_object($_SESSION['AMP_user'])
            && !empty($_SESSION['AMP_user']->id)) {
        return [
            'id'       => (int)$_SESSION['AMP_user']->id,
            'name'     => (string)($_SESSION['AMP_user']->username ?? 'admin'),
            'is_admin' => true,
        ];
    }

    // UCP / Userman session — try the well-known shapes.
    $candidates = [
        $_SESSION['ucp']['user']   ?? null,
        $_SESSION['UCP/User']      ?? null,
        $_SESSION['username']      ?? null,
    ];
    foreach ($candidates as $c) {
        if (is_array($c) && !empty($c['id'])) {
            return [
                'id'       => (int)$c['id'],
                'name'     => (string)($c['username'] ?? $c['name'] ?? 'user'),
                'is_admin' => false,
            ];
        }
        if (is_string($c) && $c !== '') {
            $userman = $GLOBALS['__pbx_freepbx']->Userman ?? null;
            if ($userman) {
                $u = $userman->getUserByUsername($c);
                if (!empty($u['id'])) {
                    return [
                        'id'       => (int)$u['id'],
                        'name'     => (string)$u['username'],
                        'is_admin' => false,
                    ];
                }
            }
        }
    }
    return null;
}

function pbx_require_login(bool $admin_required = false): array {
    $user = pbx_current_user();
    if ($user !== null && (!$admin_required || $user['is_admin'])) {
        return $user;
    }

    $next = $_SERVER['REQUEST_URI'] ?? '/';
    // Don't echo the user's URL into a header without a sanity guard.
    if (!preg_match('#^/[A-Za-z0-9_\-./?&=%]*$#', $next)) { $next = '/'; }

    $login = $admin_required ? '/admin/config.php' : '/ucp/';
    header('Location: ' . $login . '?next=' . rawurlencode($next), true, 302);
    exit;
}

/**
 * Convenience: require admin specifically (helper alias).
 */
function pbx_require_admin(): array {
    return pbx_require_login(true);
}
