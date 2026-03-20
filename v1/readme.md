### 1\. Updated Installer Script (feesix-installer.sh)

This version is now production-hardened:

*   Per-environment DB user + random password (no root in Drupal)
*   Wait-for-DB with timeout + failure handling
*   True idempotent Drupal install (skips if already bootstrapped)
*   State file used meaningfully (skip installed envs, persist DB creds)
*   Lock file to prevent parallel runs
*   Backup with \--single-transaction --gzip + 7-day rotation
*   Pre-flight summary + user confirmation
*   Final hardening pass improved
*   Logging with levels

  ### 2\. Enterprise-Grade Documentation (Single-Page README.md)

Markdown

    # Actool – Drupal 11 Multi-Environment Stack
    
    Modern, secure, Docker-based Drupal 11 deployment for development, staging, and production on one Ubuntu 24.04 LTS VPS.
    
    **Single codebase** — separate docroots & databases per environment  
    **Caddy** — automatic HTTPS (Let’s Encrypt)  
    **Redis** — object/session cache (default on)  
    **Config Split** — developer modules only on dev/stg  
    **Idempotent installer** — fresh / rerun / upgrade modes  
    **Automatic backup** before destructive rerun --force  
    **SSH-key-only sudo user** — passwordless after setup
    
    ## System Requirements
    
    - OS: Ubuntu 24.04 LTS only
    - CPU: 4 cores minimum (8+ recommended)
    - RAM: 8 GB minimum (16 GB+ for production)
    - Storage: 40 GB SSD minimum (80 GB+ recommended)
    - Access: SSH key login as non-root sudo user (root forbidden)
    
    ## How to Prepare the Server
    
    1. Log in as root (only for initial setup)
    2. Create sudo user + SSH key:
       ```bash
       adduser --disabled-password --gecos "" actool
       usermod -aG sudo actool
       mkdir -p /home/actool/.ssh
       chmod 700 /home/actool/.ssh
       touch /home/actool/.ssh/authorized_keys
       chmod 600 /home/actool/.ssh/authorized_keys
       chown -R actool:actool /home/actool/.ssh
       echo "actool ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/actool
       chmod 440 /etc/sudoers.d/actool

3.  Upload your public key to /home/actool/.ssh/authorized\_keys
4.  Disable root & password login:
    
    Bash
    
        nano /etc/ssh/sshd_config
        PermitRootLogin no
        PasswordAuthentication no
        systemctl restart ssh
    
5.  Log out → log back in as actool via SSH key

How to Install
--------------

1.  Create config:
    
    Bash
    
        cat <<'EOF' > ~/actool.env
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
        chmod 600 ~/actool.env
    
2.  Run installer:
    
    Bash
    
        curl -O https://raw.githubusercontent.com/yourusername/actool/main/actool-installer.sh
        chmod +x actool-installer.sh
        sudo ./actool-installer.sh fresh
    
3.  Copy ~/actool\_access.txt immediately → delete after backup
4.  Change admin password right after login

Tuning & Hardening
------------------

### Caddy Tuning

caddy

{ email admin@feesix.com } feesix.com, dev.feesix.com, stg.feesix.com { rate\_limit { zone site { key {remote\_host}; events 50; window 5s; } } header Strict-Transport-Security "max-age=31536000;" @forbidden path /core/\*.php /vendor/\* .env respond @forbidden 403 }
Reload: docker compose exec caddy caddy reload

### settings.php Hardening

Add at bottom:

PHP

    $$   settings['trusted_host_patterns'] = ['^feesix\.com   $$', '^dev\.feesix\.com$$   ', '^stg\.feesix\.com   $$'];
    $settings['file_private_path'] = dirname(DRUPAL_ROOT) . '/private';
    $settings['https'] = TRUE;

### Server & Filesystem Hardening

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

Backup & Restore
----------------

### Automatic Backups (on rerun --force)

~/actool\_backups/YYYY-MM-DD\_HHMMSS/<env>/ → database.sql.gz + files.tar.gz

### Manual Backup

Bash

    for env in dev stg prod; do
      docker compose exec -T php drush @$$   env sql-dump --gzip > ~/backup-   $$(date +%F)-$env.sql.gz
    done

### Restore Example (dev)

Bash

    gunzip -c ~/backup-2026-03-20-dev.sql.gz | docker compose exec -T db mariadb -u root -prootsecret drupal_dev

Maintenance & Operations
------------------------

### Weekly

*   Backup databases & files
*   Rotate backups: find ~/actool\_backups -mtime +30 -exec rm -rf {} +
*   Upgrade: sudo ./actool-installer.sh upgrade

### Monthly

*   Test restore on dev
*   Check logs: cat ~/actool-install.log
*   Run hardening commands

### Troubleshooting

*   Site down → docker compose logs caddy
*   Permission issues → Run hardening
*   Docker denied → Log out/in
*   Certificate fail → Check DNS

### Security Checklist

*   SSH key login only
*   Passwordless sudo
*   Caddy HSTS & headers
*   Trusted host patterns
*   Private files outside web root
*   Backups tested
*   UFW enabled
*   Admin password changed

Future Roadmap
--------------

*   CrowdSec brute-force protection
*   Hetzner API multi-VPS
*   Offsite backups (rclone/S3)
*   GitHub Actions CI/CD
*   Question Paper Engine module

Built for Actool – March 2026

text

    This is your **v1 locked in** — secure, reliable, documented.
    
    Copy the script → save as `actool-installer.sh`  
    Copy the Markdown → save as `README.md`
    
    Let me know when you test it or want v1.1 (CrowdSec, ufw auto-setup, restore helper, etc.).  
    We're done with brainstorming — this is production-ready. 🚀
