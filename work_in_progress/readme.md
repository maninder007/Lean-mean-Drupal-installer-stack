### Enterprise-Grade Documentation (Single-Page README.md style)

Markdown

    # Feezix – Drupal 11 Multi-Environment Stack
    
    Modern, secure, Docker-based Drupal 11 deployment for dev/stg/prod on Ubuntu 24.04 LTS.
    
    ## Features
    
    - Single codebase, separate docroots & databases
    - Caddy auto-HTTPS (Let’s Encrypt)
    - Redis cache (default on)
    - Config Split for dev/stg modules
    - Idempotent installer: fresh / rerun / upgrade
    - Automatic backup before destructive rerun
    - SSH-key-only sudo user (passwordless after setup)
    
    ## Quick Start
    
    1. Log in as **non-root sudo user** via SSH key  
    2. Create config:
    
       ```bash
       cat <<'EOF' > ~/feesix-install.env
       BASE_DOMAIN=feesix.com
       INSTALL_DEV=true
       INSTALL_STG=true
       INSTALL_PROD=true
       DRUPAL_ADMIN_USER=admin
       DRUPAL_ADMIN_PASS=changeme123!
       DRUPAL_ADMIN_EMAIL=admin@feesix.com
       USE_LETSENCRYPT=true
       LETSENCRYPT_EMAIL=admin@feesix.com
       USE_REDIS=true
       EOF
       chmod 600 ~/feesix-install.env

3.  Run installer:
    
    Bash
    
        curl -O https://raw.githubusercontent.com/yourusername/feezix/main/feesix-installer.sh
        chmod +x feesix-installer.sh
        sudo ./feesix-installer.sh fresh
    
4.  Copy ~/feesix\_access.txt immediately → delete after backup
    
5.  Change admin password right after login
    

Modes
-----

*   fresh → full setup
*   rerun --force → backup + clean + reinstall
*   upgrade → safe composer + drush deploy

Backup & Restore
----------------

**Automatic** on rerun --force: ~/feesix\_backups/YYYY-MM-DD\_HHMMSS/<env>/ → database.sql.gz + files.tar.gz

**Manual weekly backup**:

Bash

    for env in dev stg prod; do
      docker compose exec -T php drush @$$   env sql-dump --gzip > ~/backup-   $$(date +%F)-$env.sql.gz
    done

**Restore dev example**:

Bash

    gunzip -c ~/backup-2026-03-20-dev.sql.gz | docker compose exec -T db mariadb -u root -prootsecret drupal_dev

**Test restores monthly**.

Tuning & Hardening
------------------

### Caddy (recommended)

caddy

`{ email admin@feesix.com } feesix.com, dev.feesix.com, stg.feesix.com { rate_limit { zone site { key {remote_host}; events 50; window 5s; } } header Strict-Transport-Security "max-age=31536000;" @forbidden path /core/*.php /vendor/* .env respond @forbidden 403 }`

Reload: docker compose exec caddy caddy reload

### settings.php (add at bottom)

PHP

    $$   settings['trusted_host_patterns'] = ['^feesix\.com   $$', '^dev\.feesix\.com$$   ', '^stg\.feesix\.com   $$'];
    $settings['file_private_path'] = dirname(DRUPAL_ROOT) . '/private';
    $settings['https'] = TRUE;

### Server Hardening

Bash

    sudo chown -R www-data:www-data /var/www/html
    sudo find /var/www/html -type d -exec chmod 755 {} +
    sudo find /var/www/html -type f -exec chmod 644 {} +
    sudo chmod -R go-rwx /var/www/html/*/web/sites/default/settings.php

### UFW Firewall

Bash

    sudo apt install ufw -y
    sudo ufw allow OpenSSH
    sudo ufw allow 80/tcp
    sudo ufw allow 443/tcp
    sudo ufw --force enable

Maintenance Jobs
----------------

**Weekly**:

*   Backup databases & files (see above)
*   Rotate backups: find ~/feesix\_backups -mtime +30 -exec rm -rf {} +
*   Upgrade: sudo ./feesix-installer.sh upgrade

**Monthly**:

*   Test restore on dev
*   Check logs: cat ~/feesix-install.log
*   Review security: run hardening commands

Troubleshooting
---------------

*   Site down → docker compose logs caddy
*   Permission issues → Run hardening
*   Docker denied → Log out/in
*   Certificate fail → Check DNS
*   Slow → Verify Redis (drush redis-check)

Future Roadmap
--------------

*   CrowdSec brute-force protection
*   Hetzner API multi-VPS
*   Offsite backups (rclone/S3)
*   GitHub Actions CI/CD
*   Question Paper Engine module

Built for Feezix – March 2026

text

    This is now **enterprise-grade ready** — secure, maintainable, documented.
    
    Let me know when you want:
    
    - Separate files (`docs/backup.md`, `docs/hardening.md`, etc.)
    - CrowdSec integration in installer
    - Restore helper script
    - Question Paper module starter
    
    We’re in great shape! 🚀
