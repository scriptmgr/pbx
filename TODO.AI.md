done: brand FreePBX UI from FROM_NAME and remove RSS feeds
done: remove DAHDI leftovers when no DAHDI hardware is present
done: fix Certman HTTP-01 challenge handling so ACME paths bypass HTTPS redirects
done: fix Debian 13 shared-runtime gaps (npm/pm2 reload path and php-pear for AvantFax)
done: fix AlmaLinux 10 HylaFAX source install fallback
done: re-run Debian 13 and AlmaLinux 10 comprehensive validation after installer fixes
done: clear the remaining FreePBX tampered-files warning cleanly (move portal to portal.php with DirectoryIndex; refresh module signatures in finalize)
pending: review installer IPv6 reporting behavior now that production currently has no IPv6 addresses or routes
done: make PHP 7.4 the default runtime and stop intentionally installing PHP 8+
done: fix UCP daemon ECONNREFUSED on ::1 (set ASTMANAGERHOST=127.0.0.1 in finalize)
done: seed UpdateManager notification_emails from ADMIN_EMAIL so security mails have a recipient
done: install ffmpeg-free / ffmpeg in PACKAGES_DISTRO_MEDIA_OPT for HTML5 m4a codec
done: add global Apache AllowOverride All on WEB_ROOT so .htaccess works regardless of which vhost serves the request (handles user-managed reverse proxies)
done: pbx-firewall + pbx-add-ip — auto-persist iptables rules after add/deny/reset; new pbx-firewall --save/--reload action
pending: validate install.sh changes (ASTMANAGERHOST, NOTIFICATION_EMAIL, ffmpeg, AllowOverride, portal.php, refreshsignatures) in pbx-alma9 and pbx-deb12 incus containers
