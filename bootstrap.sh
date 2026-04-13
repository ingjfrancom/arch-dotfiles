#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${REPO_URL:-git@github.com:ingjfrancom/arch-dotfiles.git}"
TARGET_DIR="${TARGET_DIR:-$HOME/arch-dotfiles}"

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

install_pacman_pkg() {
  local pkg="$1"
  if ! pacman -Q "$pkg" >/dev/null 2>&1; then
    sudo pacman -S --needed --noconfirm "$pkg"
  fi
}

install_yay() {
  if need_cmd yay; then
    return 0
  fi

  install_pacman_pkg git
  install_pacman_pkg base-devel

  local build_dir
  build_dir="$(mktemp -d)"
  git clone https://aur.archlinux.org/yay.git "$build_dir/yay"
  (cd "$build_dir/yay" && makepkg -si --noconfirm)
  rm -rf "$build_dir"
}

if ! need_cmd pacman; then
  echo "Este bootstrap esta pensado para Arch Linux y requiere pacman." >&2
  exit 1
fi

install_pacman_pkg git
install_pacman_pkg stow
install_pacman_pkg base-devel
install_yay

if [ ! -d "$TARGET_DIR/.git" ]; then
  git clone "$REPO_URL" "$TARGET_DIR"
else
  git -C "$TARGET_DIR" pull --ff-only
fi

echo "Repo listo en $TARGET_DIR"
echo "Restauracion completa: $TARGET_DIR/restore.sh"
