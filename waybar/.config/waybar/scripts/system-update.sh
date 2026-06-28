#!/usr/bin/env bash
#
# system-update.sh
#
# Actualiza el sistema completo (pacman, AUR, flatpak) sin interacción.
#
# Modos de uso:
#   Standalone:    ./system-update.sh
#   Desde wrapper: update-system-with-backup.sh exporta SUDO_ASKPASS y
#                  _UPDATE_STANDALONE=false, por lo que no pide contraseña
#                  de nuevo ni envía notificaciones de fallo propias.
#
# Contraseña:
#   Se solicita una sola vez via zenity. Se guarda en un script temporal
#   con permisos 700 apuntado por SUDO_ASKPASS. Se elimina al salir.
#   yay/paru reciben --sudoflags="-A" para que usen el mismo mecanismo.
#
# Logs:           ${XDG_CACHE_HOME:-~/.cache}/system-updates/update-YYYYMMDD-HHMMSS.log
# Notificaciones: notify-send (dunst)
#

set -Eeuo pipefail

readonly NOTIFY_TITLE="Actualización del sistema"
readonly LOG_DIR="${XDG_CACHE_HOME:-${HOME}/.cache}/system-updates"
readonly LOG_FILE="${LOG_DIR}/update-$(date '+%Y%m%d-%H%M%S').log"
readonly STANDALONE="${_UPDATE_STANDALONE:-true}"

_created_askpass=false
_askpass_file=""
_pass_file=""
_keepalive_pid=""

# ── Notificaciones ────────────────────────────────────────────────────────────

_notify() {
  command -v notify-send >/dev/null 2>&1 || return 0
  notify-send -u "$1" "$NOTIFY_TITLE" "$2"
}

# ── Log ───────────────────────────────────────────────────────────────────────

_log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"
}

# ── Cleanup ───────────────────────────────────────────────────────────────────

_cleanup() {
  local code=$?
  [[ -n "$_keepalive_pid" ]] && kill "$_keepalive_pid" 2>/dev/null || true
  if [[ "$_created_askpass" == true ]]; then
    rm -f "$_askpass_file" "$_pass_file"
    sudo -k 2>/dev/null || true
  fi
  if (( code != 0 )) && [[ "$STANDALONE" == true ]]; then
    _log "ERROR: Actualización terminó con código $code."
    _notify critical "Actualización fallida. Log: $LOG_FILE"
  fi
}

trap _cleanup EXIT

# ── Autenticación ─────────────────────────────────────────────────────────────

_setup_sudo() {
  if [[ -n "${SUDO_ASKPASS:-}" ]]; then
    _log "Usando SUDO_ASKPASS heredado."
    return
  fi

  command -v zenity >/dev/null 2>&1 || {
    _log "ERROR: zenity no instalado (sudo pacman -S zenity)."
    _notify critical "zenity no encontrado. Actualización cancelada."
    exit 1
  }

  local pass
  pass=$(zenity --password \
    --title="Actualización del sistema" \
    --text="Contraseña de sudo requerida para actualizar el sistema:" \
    2>/dev/null) || {
    _log "ERROR: Sin contraseña."
    _notify critical "Actualización cancelada: sin contraseña."
    exit 1
  }
  [[ -z "$pass" ]] && {
    _log "ERROR: Contraseña vacía."
    _notify critical "Actualización cancelada: contraseña vacía."
    exit 1
  }

  # Guardar contraseña en archivo temporal con permisos estrictos
  _pass_file=$(mktemp /tmp/.sp.XXXXXX)
  chmod 600 "$_pass_file"
  printf '%s' "$pass" > "$_pass_file"

  # Script askpass que lee la contraseña del archivo temporal
  _askpass_file=$(mktemp /tmp/.sa.XXXXXX)
  chmod 700 "$_askpass_file"
  printf '#!/bin/sh\nexec cat "%s"\n' "$_pass_file" > "$_askpass_file"
  export SUDO_ASKPASS="$_askpass_file"
  _created_askpass=true

  sudo -A -v >> "$LOG_FILE" 2>&1 || {
    _log "ERROR: Contraseña incorrecta."
    _notify critical "Contraseña incorrecta. Actualización cancelada."
    exit 1
  }
  _log "Credenciales de sudo validadas."
}

# Refresca el timestamp de sudo cada 270 s para evitar expiración durante updates largos
_start_sudo_keepalive() {
  ( while true; do sleep 270; sudo -A -v >> "$LOG_FILE" 2>&1 || true; done ) &
  _keepalive_pid=$!
}

# ── Detección de herramientas ─────────────────────────────────────────────────

_detect_aur_helper() {
  command -v yay  >/dev/null 2>&1 && { printf 'yay';  return; }
  command -v paru >/dev/null 2>&1 && { printf 'paru'; return; }
}

# ── Actualizaciones ───────────────────────────────────────────────────────────

_update_packages() {
  local helper
  helper=$(_detect_aur_helper || true)

  if [[ -n "$helper" ]]; then
    # El helper AUR gestiona pacman + AUR en conjunto: resuelve conflictos entre
    # paquetes oficiales y AUR (ej. ntfs-3g vs woeusb-ng) reconstruyendo los
    # paquetes AUR afectados antes de actualizar los oficiales.
    _log "Actualizando sistema con $helper (pacman + AUR)..."
    "$helper" -Syu --noconfirm --sudoflags="-A" >> "$LOG_FILE" 2>&1
    _log "$helper: OK."
  else
    _log "Actualizando paquetes oficiales (pacman)..."
    sudo -A pacman -Syu --noconfirm >> "$LOG_FILE" 2>&1
    _log "Pacman: OK."
  fi
}

_update_flatpak() {
  command -v flatpak >/dev/null 2>&1 || { _log "Flatpak no instalado. Saltando."; return 0; }

  _log "Actualizando Flatpak del sistema..."
  flatpak update -y >> "$LOG_FILE" 2>&1 \
    || _log "WARN: Flatpak sistema — sin actualizaciones o error menor."

  _log "Actualizando Flatpak del usuario..."
  flatpak update --user -y >> "$LOG_FILE" 2>&1 \
    || _log "WARN: Flatpak usuario — sin actualizaciones o error menor."
}

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
  mkdir -p "$LOG_DIR"
  _log "=== Inicio de actualización del sistema ==="

  command -v pacman >/dev/null 2>&1 || { _log "ERROR: pacman no encontrado."; exit 1; }
  command -v sudo   >/dev/null 2>&1 || { _log "ERROR: sudo no encontrado.";   exit 1; }

  _setup_sudo
  _start_sudo_keepalive

  _update_packages
  _update_flatpak

  _log "=== Actualización completada correctamente ==="
  _notify normal "Sistema actualizado correctamente."
}

main "$@"
