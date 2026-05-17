done: brand FreePBX UI from FROM_NAME and remove RSS feeds
done: remove DAHDI leftovers when no DAHDI hardware is present
done: fix Certman HTTP-01 challenge handling so ACME paths bypass HTTPS redirects
done: fix Debian 13 shared-runtime gaps (npm/pm2 reload path and php-pear for AvantFax)
done: fix AlmaLinux 10 HylaFAX source install fallback
done: re-run Debian 13 and AlmaLinux 10 comprehensive validation after installer fixes
done: clear the remaining FreePBX tampered-files warning cleanly (move portal to portal.php with DirectoryIndex; refresh module signatures in finalize)
done: IPv6 handling is now dynamic — configure_ipv6() detects actual IPv6 availability at runtime; IPv4-only hosts stay at inet_protocols=ipv4 with no sysctl changes; dual-stack hosts get inet_protocols=all; reporting already conditional on non-empty PRIMARY_IP6/PUBLIC_IP6
note: gen3 distros (Debian 12+, AlmaLinux/Rocky/Ubuntu 22.04+) intentionally use PHP 8.2 + FreePBX 17.0; PHP 7.4 is retained as secondary runtime for AvantFax only (commit 0b3cc929c5db)
done: fix UCP daemon ECONNREFUSED on ::1 (set ASTMANAGERHOST=127.0.0.1 in finalize)
done: seed UpdateManager notification_emails from ADMIN_EMAIL so security mails have a recipient
done: install ffmpeg-free / ffmpeg in PACKAGES_DISTRO_MEDIA_OPT for HTML5 m4a codec
done: add global Apache AllowOverride All on WEB_ROOT so .htaccess works regardless of which vhost serves the request (handles user-managed reverse proxies)
done: pbx-firewall + pbx-add-ip — auto-persist iptables rules after add/deny/reset; new pbx-firewall --save/--reload action
done: validate install.sh changes (ASTMANAGERHOST, NOTIFICATION_EMAIL, ffmpeg, AllowOverride, portal.php, refreshsignatures) — validated on AlmaLinux 9, Debian 12, and Ubuntu 24.04; all verification checks passed on all three
