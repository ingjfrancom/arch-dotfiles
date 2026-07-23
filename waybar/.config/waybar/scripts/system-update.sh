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

_log_slice_matches() {
  local log_mark="$1"
  local pattern="$2"

  tail -n "+$((log_mark + 1))" "$LOG_FILE" 2>/dev/null | grep -Eqi "$pattern"
}

_is_download_failure() {
  local log_mark="$1"

  _log_slice_matches "$log_mark" \
    'no se pudo obtener el archivo|no se pudieron descargar|failed retrieving file|failed to retrieve some files|Operation too slow|Connection timed out|Resolving timed out|Could not resolve host|Could not connect to|The requested URL returned error'
}

_is_dependency_failure() {
  local log_mark="$1"

  _log_slice_matches "$log_mark" \
    'no se pudieron satisfacer las dependencias|rompe la dependencia|could not satisfy dependencies|breaks dependency|conflicting dependencies'
}

_refresh_mirrors() {
  if ! command -v reflector >/dev/null 2>&1; then
    _log "ERROR: reflector no está instalado; no se puede reparar la lista de mirrors."
    return 1
  fi

  local mirror_tmp
  mirror_tmp=$(mktemp /tmp/mirrorlist.XXXXXX)

  _log "Regenerando mirrors HTTPS/IPv4 regionales (MX, US, CA)..."
  if ! reflector \
    --country MX,US,CA \
    --protocol https \
    --ipv4 \
    --completion-percent 100 \
    --age 24 \
    --sort country \
    --number 10 \
    --connection-timeout 10 \
    --download-timeout 30 \
    --save "$mirror_tmp" >> "$LOG_FILE" 2>&1; then
    _log "ERROR: reflector no pudo generar una lista regional."
    rm -f "$mirror_tmp"
    return 1
  fi

  if ! grep -q '^Server = https://' "$mirror_tmp"; then
    _log "ERROR: reflector generó una lista vacía o no válida."
    rm -f "$mirror_tmp"
    return 1
  fi

  if ! sudo -A install -o root -g root -m 0644 \
    "$mirror_tmp" /etc/pacman.d/mirrorlist >> "$LOG_FILE" 2>&1; then
    _log "ERROR: No se pudo instalar la nueva lista de mirrors."
    rm -f "$mirror_tmp"
    return 1
  fi

  rm -f "$mirror_tmp"
  _log "Lista regional instalada correctamente."
}

_fix_aur_dep_conflicts() {
  local helper="$1"
  local log_mark="$2"

  # Extraer paquetes AUR que causan el conflicto de dependencias.
  # pacman imprime: "necesaria para el paquete PKG" o "required by PKG"
  local -a broken=()
  mapfile -t broken < <(
    tail -n "+$((log_mark + 1))" "$LOG_FILE" \
      | grep -Eo 'required by [a-zA-Z0-9_@+.-]+|el paquete [a-zA-Z0-9_@+.-]+' \
      | grep -Eo '[a-zA-Z0-9_@+.-]+$' \
      | sort -u
  )

  if [[ ${#broken[@]} -eq 0 ]]; then
    _log "ERROR: Sin conflictos AUR identificables. Revisar el log manualmente."
    return 1
  fi

  _log "Conflicto detectado. Eliminando temporalmente: ${broken[*]}"
  # -Rdd: elimina sin verificar dependencias inversas (temporal)
  sudo -A pacman -Rdd "${broken[@]}" --noconfirm >> "$LOG_FILE" 2>&1 || {
    _log "ERROR: No se pudo eliminar ${broken[*]}."
    return 1
  }

  _log "Reintentando actualización..."
  if ! "$helper" -Syu --noconfirm --sudoflags="-A" >> "$LOG_FILE" 2>&1; then
    _log "ERROR: Segunda pasada falló. Reinstalando lo eliminado para no dejar el sistema roto..."
    "$helper" -S "${broken[@]}" --noconfirm --sudoflags="-A" >> "$LOG_FILE" 2>&1 || true
    return 1
  fi

  # Reconstruir los paquetes AUR contra las versiones nuevas de sus dependencias
  _log "Reconstruyendo paquetes AUR afectados: ${broken[*]}"
  "$helper" -S "${broken[@]}" --noconfirm --sudoflags="-A" >> "$LOG_FILE" 2>&1 \
    || _log "WARN: No se pudo reconstruir ${broken[*]} — instalar manualmente."
}

_update_packages() {
  local helper
  helper=$(_detect_aur_helper || true)

  if [[ -n "$helper" ]]; then
    _log "Actualizando sistema con $helper (pacman + AUR)..."

    # Anotar posición en el log para aislar el output de este comando
    local log_mark
    log_mark=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)

    if ! "$helper" -Syu --noconfirm --sudoflags="-A" >> "$LOG_FILE" 2>&1; then
      if _is_download_failure "$log_mark"; then
        _log "Fallo de descarga detectado. Se renovarán los mirrors y se reintentará una vez."
        _refresh_mirrors

        local retry_mark
        retry_mark=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)
        if ! "$helper" -Syu --noconfirm --sudoflags="-A" >> "$LOG_FILE" 2>&1; then
          if _is_download_failure "$retry_mark"; then
            _log "ERROR: La descarga volvió a fallar con mirrors nuevos. Revisar conexión o DNS."
            return 1
          fi
          if _is_dependency_failure "$retry_mark"; then
            _log "Conflicto de dependencias AUR detectado después del reintento."
            _fix_aur_dep_conflicts "$helper" "$retry_mark"
          else
            _log "ERROR: El reintento falló por una causa no reconocida. No se eliminarán paquetes."
            return 1
          fi
        fi
      elif _is_dependency_failure "$log_mark"; then
        _log "Conflicto de dependencias AUR detectado."
        _fix_aur_dep_conflicts "$helper" "$log_mark"
      else
        _log "ERROR: La actualización falló por una causa no reconocida. No se eliminarán paquetes."
        return 1
      fi
    fi

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
