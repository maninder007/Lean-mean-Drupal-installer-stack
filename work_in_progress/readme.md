### 1\. Main README.md (the landing page)

Markdown

    # Feezix – Drupal 11 Multi-Environment Stack
    
    Modern, secure, Docker-based Drupal 11 deployment for **development**, **staging**, and **production** on a single VPS (with easy future multi-VPS extension).
    
    **Single codebase** — separate docroots and databases per environment  
    **Caddy** — automatic HTTPS via Let's Encrypt  
    **Redis** — object/session cache (default enabled)  
    **Config Split** — developer modules only on dev/stg  
    **Idempotent installer** — fresh / rerun / upgrade modes
    
    Built for Ubuntu 24.04 LTS
    
    ## Features at a glance
    
    - Automatic HTTPS for feesix.com + dev.feesix.com + stg.feesix.com
    - Separate databases: drupal_dev, drupal_stg, drupal_prod
    - Backup before any destructive action (rerun --force)
    - SSH-key-only sudo user workflow (passwordless after setup)
    - Full server bootstrap (Docker, PHP 8.4, Composer, Node/Yarn, yaml, etc.)
    - Hardened permissions & production-ready defaults
    
    ## Quick Start (Recommended)
    
    1. Log in via **SSH key** as your **sudo user** (not root)
    2. Create minimal config file:
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

3.  Download & run installer:
    
    Bash
    
        curl -O https://raw.githubusercontent.com/yourusername/feezix/main/feesix-installer.sh
        chmod +x feesix-installer.sh
        sudo ./feesix-installer.sh fresh
    
4.  **Immediately copy** everything from ~/feesix\_access.txt to a secure place Then delete or secure the file on the server.
5.  Change admin password **immediately** after login.

Modes
-----

Bash

    fresh                # Full setup + install selected environments
    rerun --force        # Backup → drop DB & docroot → reinstall selected envs
    upgrade              # Safe update: composer + drush deploy on all active envs

Table of Contents
-----------------

*   Prerequisites
*   Installation
*   Backup & Restore
*   Hardening Guide
    *   Nginx Hardening (optional – if you ever replace Caddy)
    *   settings.php Hardening
    *   Caddy Hardening
    *   Server & Filesystem Hardening
*   Troubleshooting
*   Security Checklist
*   Future Extensions

See also:

*   feesix-installer.sh – main installer
*   feesix-upgrade.sh – upgrade-only variant (optional)
*   feesix-backup.sh – manual backup script (optional)

Built for Feezix – March 2026

text

    ### 2. docs/backup-restore.md
    
    ```markdown
    # Backup & Restore Guide
    
    ## Automatic Backups
    
    Whenever you run `rerun --force`, the installer **automatically** creates a timestamped backup:
    
    Location: `~/feesix_backups/YYYY-MM-DD_HHMMSS/<env>/`
    
    Contents:
    - `database.sql` – full DB dump (drush sql-dump)
    - `files.tar.gz` – compressed `sites/default/files` directory
    
    Example:

~/feesix\_backups/2026-03-20\_143022/dev/database.sql ~/feesix\_backups/2026-03-20\_143022/dev/files.tar.gz

text

    **Important**: These backups are **local only**. Move them off-server (SCP, rsync to S3, Hetzner Storage Box, etc.) immediately.
    
    ## Manual Backup (Recommended for production)
    
    Run these commands as your sudo user:
    
    ```bash
    # Backup all databases
    for env in dev stg prod; do
      docker compose exec -T php drush @$$   env sql-dump > ~/backup-   $$(date +%F)-$env.sql
    done
    
    # Backup all files directories
    for env in dev stg prod; do
      docker compose exec -T php tar -czf /tmp/files-$env.tar.gz -C /var/www/html/$env/web/sites/default files
      docker cp feesix_php:/tmp/files-$$   env.tar.gz ~/backup-   $$(date +%F)-files-$env.tar.gz
      docker compose exec -T php rm /tmp/files-$env.tar.gz
    done

Restore Procedure
-----------------

1.  Stop containers (optional):
    
    Bash
    
        docker compose down
    
2.  Restore database (example: restore dev):
    
    Bash
    
        cat ~/backup-2026-03-20-dev.sql | docker compose exec -T db mariadb -u root -prootsecret drupal_dev
    
3.  Restore files:
    
    Bash
    
        docker compose cp ~/backup-2026-03-20-files-dev.tar.gz feesix_php:/tmp/
        docker compose exec -T php tar -xzf /tmp/backup-2026-03-20-files-dev.tar.gz -C /var/www/html/dev/web/sites/default/
        docker compose exec -T php rm /tmp/backup-2026-03-20-files-dev.tar.gz
    
4.  Restart & clear cache:
    
    Bash
    
        docker compose up -d
        docker compose exec -T php bash -c "cd /var/www/html/dev && vendor/bin/drush cr"
    

**Tip**: Test restore procedure on a dev/staging environment **monthly**.

text

    ### 3. docs/hardening.md
    
    ```markdown
    # Hardening Guide
    
    ## Caddy Hardening (default & recommended)
    
    Caddy is already very secure out of the box. The installer includes:
    
    - Strict-Transport-Security header
    - Zstd + gzip compression
    - Automatic HTTPS via Let’s Encrypt
    
    Additional manual hardening (edit Caddyfile):
    
    ```caddy
    {
      email admin@feesix.com
      servers {
        trusted_proxies static 127.0.0.1 ::1  # only if behind CDN/load balancer
      }
    }
    
    feesix.com, dev.feesix.com, stg.feesix.com {
      # ... existing routes ...
      header {
        -Server
        X-Content-Type-Options nosniff
        X-Frame-Options DENY
        Referrer-Policy strict-origin-when-cross-origin
      }
      @forbidden {
        path /core/*.php /vendor/* /config/* .env
      }
      respond @forbidden 403
    }

Reload: docker compose exec caddy caddy reload

settings.php Hardening
----------------------

The installer uses safe defaults. Add these at the bottom of settings.php:

PHP

    // Trusted hosts (prevent host header attacks)
    $settings['trusted_host_patterns'] = [
      '^feesix\.com$',
      '^dev\.feesix\.com$',
      '^stg\.feesix\.com$',
    ];
    
    // Disable dangerous features
    $settings['allow_insecure_uploads'] = FALSE;
    $settings['file_chmod_directory'] = 0755;
    $settings['file_chmod_file'] = 0644;
    
    // Move private files & config outside web root
    $settings['file_private_path'] = dirname(DRUPAL_ROOT) . '/private';
    $settings['config_sync_directory'] = dirname(DRUPAL_ROOT) . '/config/sync';
    
    // Force HTTPS in Drupal
    $settings['https'] = TRUE;

Server & Filesystem Hardening
-----------------------------

Run after installation:

Bash

    # Safe permissions on docroot
    sudo chown -R www-data:www-data /var/www/html
    sudo find /var/www/html -type d -exec chmod 755 {} +
    sudo find /var/www/html -type f -exec chmod 644 {} +
    
    # Restrict access to sensitive files
    sudo chmod -R go-rwx /var/www/html/*/web/sites/default/settings.php
    sudo chmod -R go-rwx /var/www/html/*/web/sites/default/services.yml

Optional: UFW Firewall (strongly recommended)
---------------------------------------------

Bash

    sudo apt install ufw -y
    sudo ufw allow OpenSSH
    sudo ufw allow 80/tcp
    sudo ufw allow 443/tcp
    sudo ufw --force enable
    sudo ufw status

Final Security Checklist
------------------------

*   Passwordless sudo only for trusted user
*   SSH key login only (password auth disabled)
*   Caddy HSTS & security headers
*   Trusted host patterns set
*   Private files & config outside web root
*   Regular backups tested
*   UFW or CSF firewall enabled
*   Admin password changed after install

You now have a hardened, production-ready base.

text

    This structure gives you a clean, modular, GitHub-friendly documentation set.  
    You can add more pages later (e.g. `troubleshooting.md`, `ci-cd.md`, `question-engine.md`).
    
    Let me know if you want me to generate any additional file (e.g. `troubleshooting.md`, `restore.md`) or refine any of these.  
    You're now ready to push this to GitHub — it looks professional and secure. 🚀
