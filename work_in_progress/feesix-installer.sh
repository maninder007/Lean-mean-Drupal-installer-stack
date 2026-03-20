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

# Node.js LTS + Yarn 
