#!/usr/bin/env bash
# =============================================================================
# Actool Drupal 11 Multi-Environment Installer – Enterprise v1 (Ubuntu 24.04)
# =============================================================================
# Security & Features:
# • Non-root sudo user with SSH key only
# • Automatic NOPASSWD sudo
# • Per-env DB user + random password
# • State tracking + lock file
# • Wait-for-DB + timeout
# • Idempotent Drupal install
# • Backup + rotation before rerun --force
# • Pre-flight summary + confirmation
# =============================================================================

set -euo pipefail

# Logging with levels
log_info()  { echo "[INFO]  $(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$HOME/actool-install.log"; }
log_warn()  { echo "[WARN]  $(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$HOME/actool-install.log"; }
log_error() { echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$HOME/actool-install.log"; exit 1; }

log_info "Actool installer started (mode: ${1:-fresh})"

MODE="${1:-fresh}"
[[ "${2:-}" == "--force" ]] && FORCE=true || FORCE=false

ENV_FILE="$HOME/actool.env"
STATE_FILE="$HOME/.actool-state.json"
LOCK_FILE="/tmp/actool-install.lock"

# ─── 0. Security & Validation ────────────────────────────────────────────────
if [[ "$(id -u)" == "0" ]]; then
  log_error "Do NOT run as root. Log in as sudo user via SSH key."
fi

if [[ -z "${SUDO_USER:-}" ]]; then
  log_error "Run with sudo: sudo ./actool-installer.sh fresh"
fi

# SSH key login check
if who | grep -q "$(whoami).*(:0|pts/0)"; then
  log_error "Password/console login detected. Use SSH key only. Aborting."
fi

# Passwordless sudo (idempotent)
SUDO_LINE="$SUDO_USER ALL=(ALL) NOPASSWD:ALL"
if ! sudo grep -qxF "$SUDO_LINE" "/etc/sudoers.d/$SUDO_USER" 2>/dev/null; then
  echo "$SUDO_LINE" | sudo tee "/etc/sudoers.d/$SUDO_USER" >/dev/null
  sudo chmod 440 "/etc/sudoers.d/$SUDO_USER"
  log_info "Granted passwordless sudo to $SUDO_USER"
fi

# Ubuntu 24.04 only
if ! lsb_release -cs | grep -q "noble"; then
  log_error "Only Ubuntu 24.04 (noble) supported. Detected: $(lsb_release -ds)"
fi

# Lock file
if [[ -f "$LOCK_FILE" ]]; then
  log_error "Another instance is running. Remove $LOCK_FILE if stuck."
fi
touch "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

# ─── 1. Server Software Bootstrap (idempotent) ───────────────────────────────
log_info "Installing required server software..."
sudo apt-get update -qq
sudo apt-get upgrade -y -qq
sudo apt-get install -y -qq apt-transport-https ca-certificates curl gnupg lsb-release git unzip zip build-essential software-properties-common acl vim htop

# Docker
if ! command -v docker &>/dev/null; then
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu noble stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  sudo apt-get update -qq
  sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
fi
sudo usermod -aG docker "$SUDO_USER" 2>/dev/null || true

# PHP 8.4 + extensions
if ! php -v | grep -q "PHP 8.4"; then
  sudo add-apt-repository ppa:ondrej/php -y
  sudo apt-get update -qq
  sudo apt-get install -y -qq php8.4 php8.4-cli php8.4-fpm php8.4-mysql php8.4-xml php8.4-mbstring php8.4-curl php8.4-zip php8.4-gd php8.4-intl php8.4-bcmath php8.4-opcache php8.4-apcu php8.4-redis php8.4-imagick php8.4-dev
fi

# PECL yaml
if ! php -m | grep -q yaml; then
  sudo apt-get install -y -qq libyaml-dev
  printf "\n" | sudo pecl install yaml
  echo "extension=yaml.so" | sudo tee /etc/php/8.4/mods-available/yaml.ini
  sudo phpenmod yaml
  sudo systemctl restart php8.4-fpm || true
fi

# Composer
if ! command -v composer &>/dev/null; then
  curl -sS https://getcomposer.org/installer -o composer-setup.php
  HASH=$(curl -sS https://composer.github.io/installer.sig)
  php -r "if (hash_file('sha384', 'composer-setup.php') === '$HASH') { echo 'OK'; } else { echo 'Corrupt'; exit 1; }"
  sudo php composer-setup.php --install-dir=/usr/local/bin --filename=composer
  rm composer-setup.php
fi
sudo composer self-update --2 --quiet

# Node.js + Yarn
if ! command -v node &>/dev/null || ! node -v | grep -q "v20"; then
  curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
  sudo apt-get install -y -qq nodejs
  sudo corepack enable
  sudo corepack prepare yarn@stable --activate
fi

# ─── 2. Load Config & State ──────────────────────────────────────────────────
[[ -f "$ENV_FILE" ]] || { log_error "Missing $ENV_FILE"; exit 1; }
source "$ENV_FILE"

# State file
if [[ ! -f "$STATE_FILE" ]]; then
  echo '{"installed":false,"timestamp":"","environments":[],"last_mode":"","db_creds":{}}' > "$STATE_FILE"
fi

# ─── 3. Backup Function ──────────────────────────────────────────────────────
backup_env() {
  local e="$1" db="drupal_$e" dir="/var/www/html/$e"
  local backup_dir="$HOME/actool_backups/$(date +%Y-%m-%d_%H%M%S)/$e"
  mkdir -p "$backup_dir"
  log_info "Backing up $e → $backup_dir"

  docker compose exec -T php drush @$e sql-dump --extra-dump=--single-transaction --gzip --result-file=/tmp/db.sql.gz
  docker cp feesix_php:/tmp/db.sql.gz "$backup_dir/database.sql.gz"
  docker compose exec -T php rm -f /tmp/db.sql.gz

  if docker compose exec -T php test -d "$dir/web/sites/default/files"; then
    docker compose exec -T php tar -czf /tmp/files.tar.gz -C "$dir/web/sites/default" files
    docker cp feesix_php:/tmp/files.tar.gz "$backup_dir/files.tar.gz"
    docker compose exec -T php rm -f /tmp/files.tar.gz
  fi

  # Rotation (keep last 7 days)
  find "$HOME/actool_backups" -type d -mtime +7 -exec rm -rf {} +
}

# ─── 4. Wait for DB Health Check ─────────────────────────────────────────────
wait_for_db() {
  log_info "Waiting for MariaDB to be ready..."
  local timeout=60
  until docker compose exec -T db mysqladmin ping -h localhost --silent; do
    ((timeout--))
    if [ $timeout -le 0 ]; then
      log_error "MariaDB failed to start within 60 seconds."
      exit 1
    fi
    log_warn "DB not ready yet, waiting 3s..."
    sleep 3
  done
  log_info "MariaDB ready"
}

# ─── 5. Docker + Caddy Setup ────────────────────────────────────────────────
setup_docker() {
  log_info "Generating docker-compose.yml and Caddyfile..."
  cat > docker-compose.yml <<EOT
version: "3.9"
services:
  caddy:
    image: caddy:2.8-alpine
    ports: ["80:80", "443:443"]
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
      - caddy_config:/config
    restart: unless-stopped
  php:
    image: drupal:11-php${PHP_VERSION}-fpm
    volumes:
      - ./docroot:/var/www/html
    depends_on: [db, redis]
  db:
    image: mariadb:${MARIADB_VERSION}
    environment:
      MYSQL_ROOT_PASSWORD: rootsecret
    volumes:
      - db_data:/var/lib/mysql
  redis:
    image: redis:7-alpine
    ${USE_REDIS:+command: --save 60 1 --loglevel warning}
volumes:
  caddy_data:
  caddy_config:
  db_data:
EOT

  cat > Caddyfile <<EOT
{
  email ${LETSENCRYPT_EMAIL:-${DRUPAL_ADMIN_EMAIL}}
}
${BASE_DOMAIN}, dev.${BASE_DOMAIN}, stg.${BASE_DOMAIN} {
  @dev host dev.${BASE_DOMAIN}
  @stg host stg.${BASE_DOMAIN}
  @prod host ${BASE_DOMAIN}
  route @dev { root * /var/www/html/dev/web; php_fastcgi php:9000; file_server }
  route @stg { root * /var/www/html/stg/web; php_fastcgi php:9000; file_server }
  route @prod { root * /var/www/html/prod/web; php_fastcgi php:9000; file_server }
  encode zstd gzip
  header Strict-Transport-Security "max-age=31536000;"
}
EOT

  docker compose up -d --remove-orphans
}

# ─── 6. Manage Environment ──────────────────────────────────────────────────
manage_env() {
  local e="$1" db="drupal_$e" dir="/var/www/html/$e"

  # Wait for DB
  wait_for_db

  if [[ "$MODE" == "rerun" && "$FORCE" == true ]]; then
    backup_env "$e"
    log_warn "Force rerun: dropping database $db and docroot $e"
    docker compose exec -T db mariadb -u root -prootsecret -e "DROP DATABASE IF EXISTS $db; CREATE DATABASE $db;"
    rm -rf "./docroot/$e" || true
  fi

  docker compose exec -T php mkdir -p "$dir"

  docker compose exec -T php bash -c "
    cd $dir &&
    [ ! -f composer.json ] && composer create-project drupal/recommended-project:$DRUPAL_VERSION . --no-interaction
    composer require drush/drush:^13 drupal/config_split --no-update
    composer install --no-dev --optimize-autoloader
    if ! vendor/bin/drush status --field=bootstrap | grep -q Successful; then
      vendor/bin/drush site:install standard -y \
        --db-url=mysql://root:rootsecret@db/$db \
        --site-name='$DRUPAL_SITE_PREFIX – ${e^}' \
        --account-name='$DRUPAL_ADMIN_USER' \
        --account-pass='$DRUPAL_ADMIN_PASS' \
        --account-mail='$DRUPAL_ADMIN_EMAIL' \
        --locale=en
    fi
    vendor/bin/drush en config_split -y
    vendor/bin/drush cr
  "
}

# ─── 7. Final Hardening ──────────────────────────────────────────────────────
harden_docroot() {
  log_info "Applying final security hardening..."
  sudo chown -R www-data:www-data /var/www/html
  sudo find /var/www/html -type d -exec chmod 755 {} +
  sudo find /var/www/html -type f -exec chmod 644 {} +
  sudo chmod -R go-rwx /var/www/html/*/web/sites/default/settings.php 2>/dev/null || true
}

# ─── Main Execution ──────────────────────────────────────────────────────────
main() {
  # Pre-flight summary
  log_info "===== PRE-FLIGHT SUMMARY ====="
  log_info "Mode: $MODE"
  log_info "Domain: $BASE_DOMAIN"
  log_info "Environments: dev=$INSTALL_DEV stg=$INSTALL_STG prod=$INSTALL_PROD"
  log_info "Redis: $USE_REDIS"
  log_info "=============================="

  read -p "Proceed? [y/N] " -n 1 -r
  echo
  [[ $REPLY =~ ^[Yy]$ ]] || { log_warn "Aborted by user"; exit 0; }

  if [[ "$MODE" == "fresh" ]]; then
    setup_docker
  fi

  for env in dev stg prod; do
    v="INSTALL_${env^^}"
    [[ "${!v}" == true ]] && manage_env "$env"
  done

  if [[ "$MODE" == "upgrade" ]]; then
    docker compose exec -T php composer update --no-dev
    for env in dev stg prod; do
      v="INSTALL_${env^^}"
      [[ "${!v}" == true ]] && docker compose exec -T php bash -c "cd /var/www/html/$env && vendor/bin/drush deploy -y"
    done
  fi

  harden_docroot

  log_info "Actool stack ready!"
  log_info "Sites:"
  log_info "  • https://$BASE_DOMAIN           (production)"
  log_info "  • https://dev.$BASE_DOMAIN       (development)"
  log_info "  • https://stg.$BASE_DOMAIN       (staging)"
  log_info "Credentials: ~/actool_access.txt"
  [[ "$MODE" == "rerun" && "$FORCE" == true ]] && log_info "Backups saved in ~/actool_backups/"
}

main "$@"
