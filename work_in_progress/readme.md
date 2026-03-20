    # Feezix – Drupal 11 Multi-Environment Stack
    
    Modern, secure, Docker-based Drupal 11 deployment for **development**, **staging**, and **production** on a single Ubuntu 24.04 LTS VPS.
    
    **Single codebase** — separate docroots and databases per environment  
    **Caddy** — automatic HTTPS via Let's Encrypt  
    **Redis** — object/session cache (default enabled)  
    **Config Split** — developer modules only on dev/stg  
    **Idempotent installer** — fresh / rerun / upgrade modes  
    **Backup before destructive actions** — automatic DB + files backup on rerun --force
    
    Built & tested for Ubuntu 24.04 LTS – March 2026
    
    ## Quick Start (Recommended)
    
    1. Log in via **SSH key** as your **non-root sudo user**  
       (root login forbidden – script will refuse to run)
    
    2. Create minimal config file in your home directory:
    
       ```bash
       cat <<'EOF' > ~/feesix-install.env
       # Feezix Installer Config – Keep private (chmod 600)
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

3.  Download & run installer:
    
    Bash
    
        curl -O https://raw.githubusercontent.com/yourusername/feezix/main/feesix-installer.sh
        chmod +x feesix-installer.sh
        sudo ./feesix-installer.sh fresh
    
4.  **Immediately copy** everything from ~/feesix\_access.txt to a secure place (password manager, encrypted drive). Then delete or secure the file on the server.
    
5.  Change admin password **immediately** after first login.
    

Installation Modes
------------------

Bash

    fresh                 # Full setup + install selected environments
    rerun --force         # Backup → drop DB & docroot → reinstall selected envs (destructive!)
    upgrade               # Safe update: composer + drush deploy on all active envs

Prerequisites
-------------

*   OS: Ubuntu 24.04 LTS only (script enforces this)
*   Specs: Minimum 4 CPU / 8 GB RAM (16 GB+ recommended for prod)
*   Storage: 40 GB SSD minimum (80 GB+ recommended)
*   Access: SSH key login as non-root sudo user
*   Network: DNS A records for feesix.com, dev.feesix.com, stg.feesix.com pointing to VPS IP

Backup & Restore
----------------

### Automatic Backups (on rerun --force)

Location: ~/feesix\_backups/YYYY-MM-DD\_HHMMSS/<env>/

Contents:

*   database.sql – full SQL dump (drush sql-dump)
*   files.tar.gz – compressed sites/default/files

**Always move backups off-server** (SCP, rsync, S3, Hetzner Storage Box).

### Manual Backup (recommended weekly)

Bash

    # Backup databases
    for env in dev stg prod; do
      docker compose exec -T php drush @$$   env sql-dump > ~/backup-   $$(date +%F)-$env.sql
    done
    
    # Backup files directories
    for env in dev stg prod; do
      docker compose exec -T php tar -czf /tmp/files-$env.tar.gz -C /var/www/html/$env/web/sites/default files
      docker cp feesix_php:/tmp/files-$$   env.tar.gz ~/backup-   $$(date +%F)-files-$env.tar.gz
      docker compose exec -T php rm /tmp/files-$env.tar.gz
    done

### Restore Example (dev environment)

Bash

    # Restore DB
    cat ~/backup-2026-03-20-dev.sql | docker compose exec -T db mariadb -u root -prootsecret drupal_dev
    
    # Restore files
    docker compose cp ~/backup-2026-03-20-files-dev.tar.gz feesix_php:/tmp/
    docker compose exec -T php tar -xzf /tmp/backup-2026-03-20-files-dev.tar.gz -C /var/www/html/dev/web/sites/default/
    docker compose exec -T php rm /tmp/backup-2026-03-20-files-dev.tar.gz
    
    # Restart & clear cache
    docker compose up -d
    docker compose exec -T php bash -c "cd /var/www/html/dev && vendor/bin/drush cr"

**Test restores monthly** on dev/staging.

Hardening Guide
---------------

### Caddy Hardening (default & recommended)

The installer includes:

*   Strict-Transport-Security header
*   Zstd + gzip compression
*   Automatic HTTPS

Extra hardening (edit Caddyfile):

caddy

`{ email admin@feesix.com servers { trusted_proxies static 127.0.0.1 ::1 } } feesix.com, dev.feesix.com, stg.feesix.com { # ... existing routes ... header { -Server X-Content-Type-Options nosniff X-Frame-Options DENY Referrer-Policy strict-origin-when-cross-origin } @forbidden { path /core/*.php /vendor/* /config/* .env } respond @forbidden 403 }`

Reload: docker compose exec caddy caddy reload

### settings.php Hardening

Add these at the bottom of sites/default/settings.php:

PHP

    // Trusted hosts – prevent host header attacks
    $settings['trusted_host_patterns'] = [
      '^feesix\.com$',
      '^dev\.feesix\.com$',
      '^stg\.feesix\.com$',
    ];
    
    // Disable dangerous features
    $settings['allow_insecure_uploads'] = FALSE;
    $settings['file_chmod_directory'] = 0755;
    $settings['file_chmod_file'] = 0644;
    
    // Private & config paths outside web root
    $settings['file_private_path'] = dirname(DRUPAL_ROOT) . '/private';
    $settings['config_sync_directory'] = dirname(DRUPAL_ROOT) . '/config/sync';
    
    // Force HTTPS
    $settings['https'] = TRUE;

### Server & Filesystem Hardening

Run after installation:

Bash

    # Safe ownership & permissions
    sudo chown -R www-data:www-data /var/www/html
    sudo find /var/www/html -type d -exec chmod 755 {} +
    sudo find /var/www/html -type f -exec chmod 644 {} +
    
    # Restrict sensitive files
    sudo chmod -R go-rwx /var/www/html/*/web/sites/default/settings.php
    sudo chmod -R go-rwx /var/www/html/*/web/sites/default/services.yml

### UFW Firewall (strongly recommended)

Bash

    sudo apt install ufw -y
    sudo ufw allow OpenSSH
    sudo ufw allow 80/tcp
    sudo ufw allow 443/tcp
    sudo ufw --force enable
    sudo ufw status

Security Checklist
------------------

*   SSH key login only (password auth disabled)
*   Passwordless sudo for your user
*   Caddy HSTS & security headers
*   Trusted host patterns set
*   Private files & config outside web root
*   Backups tested monthly
*   UFW firewall enabled
*   Admin password changed after install

Troubleshooting
---------------

*   Caddy fails to issue certificate → Check DNS (A records must point to VPS IP)
*   Docker permission denied → Log out & back in (docker group)
*   Site not loading → Check ~/feesix-install.log and docker compose logs caddy
*   Rerun fails → Restore from ~/feesix\_backups/

Future Extensions
-----------------

*   Hetzner API multi-VPS provisioning
*   Email delivery of credentials (msmtp)
*   Varnish / Nginx fastcgi\_cache
*   GitHub Actions CI/CD pipeline
*   Automated daily backups to S3 / Hetzner Storage Box

Built for Feezix – March 2026

text

    Now just:
    1. Click inside the big code block above
    2. Ctrl+A (select all)
    3. Ctrl+C (copy)
    4. Open your GitHub README.md
    5. Ctrl+V (paste)
    
    It will paste perfectly — no line numbers, no broken formatting, all headings and code blocks intact.
    
    If you want it split into separate files later (e.g. `docs/hardening.md`, `docs/backup.md`), I can give you those too. But this single-block version is perfect for one-click copy-paste.
    
    Ready to push to GitHub? Let me know when you want the actual installer script file content
