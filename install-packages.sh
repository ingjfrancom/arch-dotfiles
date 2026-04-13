#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PKGLIST="$ROOT_DIR/packages/pkglist.txt"
AURLIST="$ROOT_DIR/packages/aurlist.txt"

read_packages() {
  local file="$1"
  [ -f "$file" ] || return 0
  sed 's/#.*$//' "$file" | awk 'NF {print $1}' | sort -u
}

install_pacman_packages() {
  mapfile -t packages < <(read_packages "$PKGLIST")
  [ "${#packages[@]}" -gt 0 ] || return 0

  local missing=()
  for pkg in "${packages[@]}"; do
    if ! pacman -Q "$pkg" >/dev/null 2>&1; then
      missing+=("$pkg")
    fi
  done

  if [ "${#missing[@]}" -gt 0 ]; then
    sudo pacman -S --needed --noconfirm "${missing[@]}"
  else
    echo "Paquetes oficiales ya instalados."
  fi
}

install_aur_packages() {
  mapfile -t packages < <(read_packages "$AURLIST")
  [ "${#packages[@]}" -gt 0 ] || return 0

  if ! command -v yay >/dev/null 2>&1; then
    echo "yay no esta instalado. Ejecuta ./bootstrap.sh primero." >&2
    exit 1
  fi

  local missing=()
  for pkg in "${packages[@]}"; do
    if ! pacman -Q "$pkg" >/dev/null 2>&1; then
      missing+=("$pkg")
    fi
  done

  if [ "${#missing[@]}" -gt 0 ]; then
    yay -S --needed --noconfirm "${missing[@]}"
  else
    echo "Paquetes AUR ya instalados."
  fi
}

install_pacman_packages
install_aur_packages
