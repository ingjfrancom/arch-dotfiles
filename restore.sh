#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="${BACKUP_DIR:-$HOME/.dotfiles-backup-$(date +%Y%m%d-%H%M%S)}"

STOW_PACKAGES=(
  hypr
  waybar
  wofi
  alacritty
  dunst
  zsh
  bash
  dolphin
  btop
  starship
  local-bin
)

ensure_dirs() {
  mkdir -p "$HOME/.config" "$HOME/.local/bin" "$HOME/Pictures/wallpaper"
}

install_packages() {
  "$ROOT_DIR/install-packages.sh"
}

backup_path() {
  local target="$1"
  local rel="${target#$HOME/}"
  mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
  mv "$target" "$BACKUP_DIR/$rel"
  echo "Backup: $target -> $BACKUP_DIR/$rel"
}

backup_conflicts_for_package() {
  local package="$1"
  local package_dir="$ROOT_DIR/$package"
  [ -d "$package_dir" ] || return 0

  while IFS= read -r -d '' source_path; do
    local rel="${source_path#$package_dir/}"
    local target="$HOME/$rel"
    local repo_real
    local target_real

    repo_real="$(realpath -m "$source_path")"
    target_real="$(realpath -m "$target")"

    if [ -e "$target" ] || [ -L "$target" ]; then
      if [ "$repo_real" != "$target_real" ]; then
        backup_path "$target"
      fi
    fi
  done < <(find "$package_dir" \( -type f -o -type l \) -print0)
}

apply_dotfiles() {
  if ! command -v stow >/dev/null 2>&1; then
    echo "GNU Stow no esta instalado. Ejecuta ./bootstrap.sh primero." >&2
    exit 1
  fi

  ensure_dirs
  mkdir -p "$BACKUP_DIR"

  for package in "${STOW_PACKAGES[@]}"; do
    backup_conflicts_for_package "$package"
    stow --dir="$ROOT_DIR" --target="$HOME" --restow "$package"
  done

  echo "Dotfiles aplicados con Stow."
  echo "Backups en $BACKUP_DIR"
}

restore_services() {
  local system_file="$ROOT_DIR/systemd/system-enabled.txt"
  local user_file="$ROOT_DIR/systemd/user-enabled.txt"

  if [ -f "$system_file" ]; then
    awk 'NR > 1 && $1 !~ /^(UNIT|[0-9]+)$/ && $2 == "enabled" {print $1}' "$system_file" |
      while read -r unit; do
        sudo systemctl enable "$unit" || true
      done
  fi

  if [ -f "$user_file" ]; then
    awk 'NR > 1 && $1 !~ /^(UNIT|[0-9]+)$/ && $2 == "enabled" {print $1}' "$user_file" |
      while read -r unit; do
        systemctl --user enable "$unit" || true
      done
  fi
}

restore_system_configs() {
  if [ -f "$ROOT_DIR/ly/etc/ly/config.ini" ]; then
    sudo mkdir -p /etc/ly
    if [ -e /etc/ly/config.ini ] && [ ! -L /etc/ly/config.ini ]; then
      sudo cp -a /etc/ly/config.ini "/etc/ly/config.ini.backup.$(date +%Y%m%d-%H%M%S)"
    fi
    sudo install -m 0644 "$ROOT_DIR/ly/etc/ly/config.ini" /etc/ly/config.ini
  fi
}

full_restore() {
  install_packages
  apply_dotfiles
  restore_system_configs
  restore_services
}

case "${1:-all}" in
  packages)
    install_packages
    ;;
  dotfiles)
    apply_dotfiles
    ;;
  services)
    restore_services
    ;;
  system-configs)
    restore_system_configs
    ;;
  all)
    full_restore
    ;;
  *)
    echo "Uso: $0 [all|packages|dotfiles|services|system-configs]" >&2
    exit 1
    ;;
esac
