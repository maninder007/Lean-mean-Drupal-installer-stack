#!/usr/bin/env bash
# =============================================================================
# Feezix Drupal 11 Multi-Environment Installer – Ubuntu 24.04 Edition (2026)
# =============================================================================
# Security & Usage Rules:
#   • Must be run by a NON-ROOT sudo user logged in via SSH KEY ONLY
#   • Automatically grants NOPASSWD sudo to this user (idempotent)
#   • Installs all required server software first
#   • Modes: fresh | rerun [--force] | upgrade
#   • Automatic backup before destructive rerun --force
#   • Logs to ~/feesix-install.log
# =============================================================================

set -euo pipefail

# Redirect all output to log + console
exec > >(tee -a "$HOME/feesix-install.log") 2>&1

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting Feezix installer..."

MODE="${1:-fresh}"
[[ "${2:-}" == "--force" ]] && FORCE=true || FORCE=false

# ─── 0. Security & User Validation ───────────────────────────────────────────
if [[ "$(id -u)" == "0" ]]; then
  echo "ERROR: Do NOT run this script as root."
  echo "You are overqualified for this job."
  echo "Log in as your regular sudo user via SSH key and run with sudo."
  exit 1
fi

if [[ -z "${SUDO_USER:-}" ]]; then
  echo "ERROR: You must run this script with sudo."
  echo "Example: sudo ./feesix-installer.sh fresh"
  exit 1
fi

# Detect password login (insecure)
if who | grep -q "$(whoami).*(:0|pts/0)"; then
  echo "CRITICAL: You appear to be logged in via password or console."
  echo "This is NOT secure. Re-login via SSH with key only."
  echo "Aborting installation."
  exit 1
fi

# Grant NOPASSWD sudo to this user (idempotent)
SUDO_LINE="$SUDO_USER ALL=(ALL) NOPASSWD:ALL"
if ! sudo grep -qxF "$SUDO_LINE" "/etc/sudoers.d/$SUDO_USER" 2>/dev/null; then
  echo "$SUDO_LINE" | sudo tee "/etc/sudoers.d/$SUDO_USER" >/dev/null
  sudo chmod 440 "/etc/sudoers.d/$SUDO_USER"
  echo "→ Granted passwordless sudo to $SUDO_USER (no more prompts)"
fi

# Enforce Ubuntu 24.04 only
if ! lsb_release -cs | grep -q "noble"; then
  echo "ERROR: This script is designed for Ubuntu 24.04 (noble) only."
  echo "Detected: $(lsb_release -ds)"
  exit 1
fi

# ─── 1. Install required server software (idempotent) ────────────────────────
echo "Installing required server software (Ubuntu 24.04)..."

sudo apt-get update -qq
sudo apt-get upgrade -y -qq
sudo apt-get install -y -qq \
  apt-transport-https ca-certificates curl gnupg lsb-release \
  git unzip zip build-essential software-properties-common \
  acl sudo vim htop

# Docker + compose plugin
if ! command -v docker &>/dev/null; then
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu noble stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  sudo apt-get update -qq
  sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
fi
sudo usermod -aG docker "$SUDO_USER" 2>/dev/null || true

# PHP 8.4 from Ondřej Surý PPA
if ! php -v | grep -q "PHP 8.4"; then
  sudo add-apt-repository ppa:ondrej/php -y
  sudo apt-get update -qq
  sudo apt-get install -y -qq \
    php8.4 php8.4-cli php8.4-fpm php8.4-mysql php8.4-xml php8.4-mbstring \
    php8.4-curl php8.4-zip php8.4-gd php8.4-intl php8.4-bcmath php8.4-opcache \
    php8.4-apcu php8.4-redis php8.4-imagick php8.4-dev
fi

# PECL yaml extension
if ! php -m | grep -q yaml; then
  sudo apt-get install -y -qq libyaml-dev
  printf "\n" | sudo pecl install yaml
  echo "extension=yaml.so" | sudo tee /etc/php/8.4/mods-available/yaml.ini
  sudo phpenmod yaml
  sudo systemctl restart php8.4-fpm || true
fi

# Composer (with SHA check)
if ! command -v composer &>/dev/null; then
  echo "Installing Composer with verification..."
  curl -sS https://getcomposer.org/installer -o composer-setup.php
  HASH=$(curl -sS https://composer.github.io/installer.sig)
  php -r "if (hash_file('sha384', 'composer-setup.php') === '$HASH') { echo 'Installer verified'; } else { echo 'Installer corrupt'; unlink('composer-setup.php'); } echo PHP_EOL;"
  sudo php composer-setup.php --install-dir=/usr/local/bin --filename=composer
  rm composer-setup.php
fi
sudo composer self-update --2 --quiet

# Node.js LTS + Yarn 4.x
if ! command -v node &>/dev/null || ! node -v | grep -q "v20"; then
  curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
  sudo apt-get install -y -qq nodejs
  sudo corepack enable
  sudo corepack prepare yarn@stable --activate
fi

# ─── 2. Load user config ─────────────────────────────────────────────────────
ENV_FILE="$HOME/feesix-install.env"
[[ -f "$ENV_FILE" ]] || { echo "Missing $ENV_FILE – create it first"; exit 1; }
source "$ENV_FILE"

# ─── 3. Backup function (used before destructive rerun) ──────────────────────
backup_env() {
  local e="$1" db="drupal_$e" dir="/var/www/html/$e"
  local backup_dir="$HOME/feesix_backups/$(date +%Y-%m-%d_%H%M%S)/$e"
  mkdir -p "$backup_dir"
  echo "Backing up $e → $backup_dir"

  # DB dump
  docker compose exec -T php drush @$e sql-dump --result-file=/tmp/backup.sql >/dev/null 2>&1 || true
  docker cp feesix_php:/tmp/backup.sql "$backup_dir/database.sql" 2>/dev/null || true
  docker compose exec -T php rm -f /tmp/backup.sql 2>/dev/null || true

  # Files
  if docker compose exec -T php test -d "$dir/web/sites/default/files"; then
    docker compose exec -T php tar -czf /tmp/files.tar.gz -C "$dir/web/sites/default" files
    docker cp feesix_php:/tmp/files.tar.gz "$backup_dir/files.tar.gz"
    docker compose exec -T php rm -f /tmp/files.tar.gz
  fi
}

# ─── 4. Docker + Caddy Setup ────────────────────────────────────────────────
setup_docker() {
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

# ─── 5. Manage Environment ──────────────────────────────────────────────────
manage_env() {
  local e="$1" db="drupal_$e" dir="/var/www/html/$e"

  if [[ "$MODE" == "rerun" && "$FORCE" == true ]]; then
    backup_env "$e"
    echo "Force rerun: dropping DB $db and docroot $e"
    docker compose exec -T db mariadb -u root -prootsecret -e "DROP DATABASE IF EXISTS $db; CREATE DATABASE $db;"
    rm -rf "./docroot/$e" || true
  fi

  docker compose exec -T php mkdir -p "$dir"

  docker compose exec -T php bash -c "
    cd $dir &&
    [ ! -f composer.json ] && composer create-project drupal/recommended-project:$DRUPAL_VERSION . --no-interaction
    composer require drush/drush:^13 drupal/config_split --no-update
    composer install --no-dev --optimize-autoloader
    vendor/bin/drush site:install standard -y \
      --db-url=mysql://root:rootsecret@db/$db \
      --site-name='$DRUPAL_SITE_PREFIX – ${e^}' \
      --account-name='$DRUPAL_ADMIN_USER' \
      --account-pass='$DRUPAL_ADMIN_PASS' \
      --account-mail='$DRUPAL_ADMIN_EMAIL' \
      --locale=en
    vendor/bin/drush en config_split -y
    vendor/bin/drush cr
  "
}

# ─── Final Hardening Pass ────────────────────────────────────────────────────
harden_docroot() {
  echo "Applying final security hardening..."
  sudo chown -R www-data:www-data /var/www/html
  sudo find /var/www/html -type d -exec chmod 755 {} +
  sudo find /var/www/html -type f -exec chmod 644 {} +
}

# ─── Main ────────────────────────────────────────────────────────────────────
main() {
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

  echo "Feezix stack ready!"
  echo "Sites:"
  echo "  • https://$BASE_DOMAIN           (production)"
  echo "  • https://dev.$BASE_DOMAIN       (development)"
  echo "  • https://stg.$BASE_DOMAIN       (staging)"
  echo "Credentials & keys: ~/feesix_access.txt"
  [[ "$MODE" == "rerun" && "$FORCE" == true ]] && echo "Backups saved in ~/feesix_backups/"
}

main "$@"
