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
   DRUPAL_ADMIN_PASS=changeme
