#!/usr/bin/env bash

set -euo pipefail

readonly MENU_TITLE="Power Menu"
readonly NOTIFY_TITLE="Waybar power menu"
readonly UPDATE_SCRIPT="/home/jfranco/.config/waybar/scripts/update-system-with-backup.sh"

notify_user() {
  local message=$1

  if command -v notify-send >/dev/null 2>&1; then
    notify-send "$NOTIFY_TITLE" "$message"
  else
    printf '%s\n' "$message" >&2
  fi
}

require_command() {
  local cmd=$1

  if ! command -v "$cmd" >/dev/null 2>&1; then
    notify_user "Falta la dependencia requerida: $cmd"
    return 1
  fi
}

select_option() {
  local prompt=$1
  shift
  printf '%s\n' "$@" | wofi --dmenu --prompt "$prompt"
}

confirm_action() {
  local prompt=$1
  local choice

  choice=$(select_option "$prompt" "No" "Si") || return 1
  [[ "$choice" == "Si" ]]
}

require_command wofi || exit 1

choice=$(select_option "$MENU_TITLE" \
  "📦 Actualizar sistema" \
  "🔒 Bloquear" \
  "🚪 Cerrar sesión" \
  "🔄 Reiniciar" \
  "⏻ Apagar") || exit 0

case "$choice" in
  "📦 Actualizar sistema")
    if [[ ! -x "$UPDATE_SCRIPT" ]]; then
      notify_user "El script de actualizacion no existe o no es ejecutable."
      exit 1
    fi

    # Ejecutar en segundo plano sin terminal; toda la salida va al log.
    # setsid desacopla el proceso de la sesión de waybar.
    setsid bash "$UPDATE_SCRIPT" </dev/null &>/dev/null &
    disown
    ;;
  "🔒 Bloquear")
    require_command hyprlock || exit 1
    hyprlock
    ;;
  "🚪 Cerrar sesión")
    require_command hyprctl || exit 1
    hyprctl dispatch exit
    ;;
  "🔄 Reiniciar")
    if confirm_action "Confirmar reinicio"; then
      systemctl reboot
    fi
    ;;
  "⏻ Apagar")
    if confirm_action "Confirmar apagado"; then
      systemctl poweroff
    fi
    ;;
esac
