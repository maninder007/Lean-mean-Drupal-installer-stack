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

1. **Log in via SSH key** as your **non-root sudo user**  
   (root login forbidden – script will refuse to run)

2. **Create minimal config file** in your home directory:

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

3.   **Download & run installer:**
   curl -O https://raw.githubusercontent.com/yourusername/feezix/main/feesix-installer.sh
   chmod +x feesix-installer.sh
sudo ./feesix-installer.sh fresh

*   **Immediately copy** everything from ~/feesix\_access.txt to a secure place (password manager, encrypted drive). Delete or secure the file on the server after backup.
    
*   **Change admin password** right after first login.

## Installation Modes
fresh                # Full setup + install selected environments
rerun --force        # Backup → drop DB & docroot → reinstall selected envs (destructive!)
upgrade              # Safe update: composer + drush deploy on all active envs

Prerequisites
-------------

*   **OS**: Ubuntu 24.04 LTS only (script enforces this)
*   **Specs**: Minimum 4 CPU / 8 GB RAM (16 GB+ recommended for prod)
*   **Storage**: 40 GB SSD minimum (80 GB+ recommended)
*   **Access**: SSH key login as non-root sudo user
*   **Network**: DNS A records for feesix.com, dev.feesix.com, stg.feesix.com pointing to VPS IP

Backup & Restore
----------------

### Automatic Backups (on rerun --force)

Location: ~/feesix\_backups/YYYY-MM-DD\_HHMMSS/<env>/

Contents:

*   database.sql – full SQL dump
*   files.tar.gz – compressed sites/default/files

**Always move backups off-server** (SCP, rsync, S3, Hetzner Storage Box).

### Manual Backup (recommended weekly)

### Backup databases
for env in dev stg prod; do
  docker compose exec -T php drush @$$   env sql-dump > ~/backup-   $$(date +%F)-$env.sql
done

### Backup files directories
for env in dev stg prod; do
  docker compose exec -T php tar -czf /tmp/files-$env.tar.gz -C /var/www/html/$env/web/sites/default files
  docker cp feesix_php:/tmp/files-$$   env.tar.gz ~/backup-   $$(date +%F)-files-$env.tar.gz
  docker compose exec -T php rm /tmp/files-$env.tar.gz
done

### Restore Example (dev environment)
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

The installer already includes:

*   Strict-Transport-Security
*   Zstd + gzip compression
*   Automatic HTTPS

Extra hardening (edit Caddyfile):
{
  email admin@feesix.com
  servers {
    trusted_proxies static 127.0.0.1 ::1
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
Add these at the bottom of sites/default/settings.php:

// Trusted hosts – prevent host header attacks $settings\['trusted\_host\_patterns'\] = \[ '^feesix\\.com$', '^dev\\.feesix\\.com$', '^stg\\.feesix\\.com$', \];

// Disable dangerous features $settings\['allow\_insecure\_uploads'\] = FALSE; $settings\['file\_chmod\_directory'\] = 0755; $settings\['file\_chmod\_file'\] = 0644;

// Private & config paths outside web root $settings\['file\_private\_path'\] = dirname(DRUPAL\_ROOT) . '/private'; $settings\['config\_sync\_directory'\] = dirname(DRUPAL\_ROOT) . '/config/sync';

// Force HTTPS $settings\['https'\] = TRUE;

