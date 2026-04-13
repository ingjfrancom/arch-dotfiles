#!/usr/bin/env bash

set -euo pipefail

readonly MENU_TITLE="Power Menu"
readonly NOTIFY_TITLE="Waybar power menu"
readonly UPDATE_SCRIPT="/home/jfranco/.config/waybar/scripts/system-update.sh"

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

launch_terminal() {
  local script_path=$1

  if command -v kitty >/dev/null 2>&1; then
    kitty --hold bash -lc "$script_path" &
    return 0
  fi

  if command -v alacritty >/dev/null 2>&1; then
    alacritty -e bash -lc "$script_path" &
    return 0
  fi

  if command -v konsole >/dev/null 2>&1; then
    konsole --hold -e bash -lc "$script_path" &
    return 0
  fi

  if command -v xterm >/dev/null 2>&1; then
    xterm -hold -e bash -lc "$script_path" &
    return 0
  fi

  return 1
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
    require_command bash || exit 1

    if [[ ! -x "$UPDATE_SCRIPT" ]]; then
      notify_user "El script de actualizacion no existe o no es ejecutable."
      exit 1
    fi

    if ! launch_terminal "$UPDATE_SCRIPT"; then
      notify_user "No se encontro una terminal compatible para ejecutar la actualizacion."
      exit 1
    fi
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
