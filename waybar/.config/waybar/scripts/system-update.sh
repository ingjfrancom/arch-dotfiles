#!/usr/bin/env bash

set -Eeuo pipefail

readonly NOTIFY_TITLE="Actualizacion del sistema"

notify_user() {
  local message=$1

  if command -v notify-send >/dev/null 2>&1; then
    notify-send "$NOTIFY_TITLE" "$message"
  fi
}

pause_before_exit() {
  printf '\nPresiona Enter para cerrar...'
  read -r _
}

print_section() {
  local title=$1
  printf '\n== %s ==\n' "$title"
}

print_list() {
  local title=$1
  shift

  print_section "$title"

  if (($# == 0)); then
    printf 'Nada pendiente.\n'
    return
  fi

  printf '%s\n' "$@"
}

detect_aur_helper() {
  if command -v yay >/dev/null 2>&1; then
    printf 'yay\n'
    return
  fi

  if command -v paru >/dev/null 2>&1; then
    printf 'paru\n'
  fi
}

main() {
  local helper=""
  local -a repo_updates=()
  local -a aur_updates=()
  local -a flatpak_system_updates=()
  local -a flatpak_user_updates=()
  local total_updates=0

  if ! command -v pacman >/dev/null 2>&1; then
    printf 'No se encontro pacman. Este script esta pensado para Arch Linux o derivados.\n' >&2
    pause_before_exit
    exit 1
  fi

  if ! command -v sudo >/dev/null 2>&1; then
    printf 'No se encontro sudo. No puedo actualizar los paquetes del sistema sin ese comando.\n' >&2
    pause_before_exit
    exit 1
  fi

  helper=$(detect_aur_helper || true)

  clear
  printf 'Actualizacion completa del sistema\n'
  printf 'Fecha: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"

  if [[ -n "$helper" ]]; then
    printf 'Helper AUR detectado: %s\n' "$helper"
  else
    printf 'Helper AUR detectado: ninguno\n'
  fi

  if command -v flatpak >/dev/null 2>&1; then
    printf 'Flatpak: disponible\n'
  else
    printf 'Flatpak: no instalado\n'
  fi

  print_section "Sincronizando bases de paquetes"
  printf 'Se solicitara tu contrasena para actualizar la base de datos de pacman.\n'
  sudo pacman -Sy

  mapfile -t repo_updates < <(pacman -Qu 2>/dev/null || true)

  if [[ -n "$helper" ]]; then
    mapfile -t aur_updates < <("$helper" -Qua 2>/dev/null || true)
  fi

  if command -v flatpak >/dev/null 2>&1; then
    mapfile -t flatpak_system_updates < <(flatpak remote-ls --updates --columns=name,version,origin 2>/dev/null || true)
    mapfile -t flatpak_user_updates < <(flatpak remote-ls --user --updates --columns=name,version,origin 2>/dev/null || true)
  fi

  print_list "Actualizaciones de repos oficiales" "${repo_updates[@]}"

  if [[ -n "$helper" ]]; then
    print_list "Actualizaciones AUR ($helper)" "${aur_updates[@]}"
  fi

  if command -v flatpak >/dev/null 2>&1; then
    print_list "Actualizaciones Flatpak del sistema" "${flatpak_system_updates[@]}"
    print_list "Actualizaciones Flatpak del usuario" "${flatpak_user_updates[@]}"
  fi

  total_updates=$((${#repo_updates[@]} + ${#aur_updates[@]} + ${#flatpak_system_updates[@]} + ${#flatpak_user_updates[@]}))

  print_section "Resumen"
  printf 'Total detectado: %d actualizaciones pendientes.\n' "$total_updates"

  if ((total_updates == 0)); then
    printf 'El sistema ya esta al dia.\n'
    notify_user "No se encontraron actualizaciones pendientes."
    pause_before_exit
    exit 0
  fi

  printf '\nContinuar con la actualizacion completa? [s/N]: '
  read -r confirm

  if [[ ! "$confirm" =~ ^([sS]|[sS][iI])$ ]]; then
    printf 'Actualizacion cancelada.\n'
    notify_user "Actualizacion cancelada por el usuario."
    pause_before_exit
    exit 0
  fi

  print_section "Actualizando paquetes del sistema"
  if [[ -n "$helper" ]]; then
    "$helper" -Syu
  else
    sudo pacman -Syu
  fi

  if command -v flatpak >/dev/null 2>&1; then
    if ((${#flatpak_system_updates[@]} > 0)); then
      print_section "Actualizando Flatpak del sistema"
      flatpak update -y
    fi

    if ((${#flatpak_user_updates[@]} > 0)); then
      print_section "Actualizando Flatpak del usuario"
      flatpak update --user -y
    fi
  fi

  print_section "Finalizado"
  printf 'La actualizacion termino sin errores.\n'
  notify_user "Actualizacion completada correctamente."
  pause_before_exit
}

main "$@"
