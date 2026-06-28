#!/usr/bin/env bash
#
# update-system-with-backup.sh
#
# Respalda los dotfiles en GitHub y luego actualiza el sistema completo.
# Diseñado para ejecutarse desde el menú de Waybar sin abrir una terminal.
#
# Flujo:
#   1. Solicita contraseña de sudo una sola vez (ventana zenity).
#   2. Valida las credenciales de sudo.
#   3. Sincroniza el repo local con el remoto (git pull --rebase).
#   4. Hace git add + commit + push como respaldo del estado PREVIO
#      a la actualización, para poder revertir si algo falla.
#   5. Llama a system-update.sh pasando SUDO_ASKPASS para no volver
#      a pedir contraseña ni mostrar otro diálogo.
#
# Para revertir una actualización fallida:
#   cd ~/arch-dotfiles && git log --oneline   # ver commits de respaldo
#   git checkout <hash> -- .                  # restaurar un estado anterior
#
# Logs:           ${XDG_CACHE_HOME:-~/.cache}/system-updates/backup-YYYYMMDD-HHMMSS.log
# Notificaciones: notify-send (dunst)
#

set -Eeuo pipefail

readonly NOTIFY_TITLE="Actualización con respaldo"
readonly DOTFILES_REPO="${HOME}/arch-dotfiles"
readonly REMOTE_NAME="origin"
readonly MAIN_BRANCH="main"
readonly SYSTEM_UPDATE_SCRIPT="${HOME}/.config/waybar/scripts/system-update.sh"
readonly LOG_DIR="${XDG_CACHE_HOME:-${HOME}/.cache}/system-updates"
readonly LOG_FILE="${LOG_DIR}/backup-$(date '+%Y%m%d-%H%M%S').log"

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
  rm -f "$_askpass_file" "$_pass_file"
  sudo -k 2>/dev/null || true
  if (( code != 0 )); then
    _log "ERROR: Proceso terminó con código $code."
    _notify critical "Fallo en respaldo/actualización. Log: $LOG_FILE"
  fi
}

trap _cleanup EXIT

# ── Autenticación ─────────────────────────────────────────────────────────────

_setup_sudo() {
  command -v zenity >/dev/null 2>&1 || {
    _notify critical "zenity no encontrado (sudo pacman -S zenity). Cancelado."
    exit 1
  }

  local pass
  pass=$(zenity --password \
    --title="Actualización con respaldo" \
    --text="Contraseña de sudo — usada para el respaldo y la actualización completa:" \
    2>/dev/null) || {
    _notify critical "Actualización cancelada: sin contraseña."
    exit 1
  }
  [[ -z "$pass" ]] && {
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

  sudo -A -v >> "$LOG_FILE" 2>&1 || {
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

# ── Respaldo de dotfiles ──────────────────────────────────────────────────────

_scan_staged_for_secrets() {
  local f
  local -a staged=()
  mapfile -t staged < <(git -C "$DOTFILES_REPO" diff --cached --name-only --diff-filter=ACMR)

  for f in "${staged[@]}"; do
    case "$(basename "$f")" in
      .env|*.env|*.pem|*.key|id_rsa|id_dsa|id_ecdsa|id_ed25519)
        _log "ERROR: Archivo sensible detectado en staging: $f"
        return 1
        ;;
    esac
    if git -C "$DOTFILES_REPO" show ":$f" 2>/dev/null | grep -Eq \
      '-----BEGIN (OPENSSH|RSA|DSA|EC|PRIVATE) PRIVATE KEY-----|ghp_[A-Za-z0-9_]{36,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}'; then
      _log "ERROR: Contenido sensible detectado en: $f"
      return 1
    fi
  done
}

_backup_dotfiles() {
  if [[ ! -d "$DOTFILES_REPO" ]] || \
     ! git -C "$DOTFILES_REPO" rev-parse --is-inside-work-tree >> "$LOG_FILE" 2>&1; then
    _log "WARN: Sin repositorio válido en $DOTFILES_REPO. Continuando sin respaldo."
    _notify low "Sin repo de dotfiles. Actualizando sin respaldo previo."
    return 0
  fi

  _log "=== Respaldo de dotfiles ==="

  # Sincronizar con el remoto antes de commitear para evitar conflictos
  _log "Sincronizando con $REMOTE_NAME/$MAIN_BRANCH..."
  git -C "$DOTFILES_REPO" pull --rebase "$REMOTE_NAME" "$MAIN_BRANCH" >> "$LOG_FILE" 2>&1 \
    || _log "WARN: pull rebase falló (posible falta de conexión). Continuando."

  git -C "$DOTFILES_REPO" add . >> "$LOG_FILE" 2>&1

  # Abortar si hay archivos sensibles preparados para commit
  if ! _scan_staged_for_secrets; then
    git -C "$DOTFILES_REPO" restore --staged . >> "$LOG_FILE" 2>&1 || true
    _notify critical "Archivo sensible detectado en dotfiles. Respaldo cancelado."
    return 1
  fi

  if git -C "$DOTFILES_REPO" diff --cached --quiet; then
    _log "Sin cambios nuevos en dotfiles. No se crea commit."
  else
    local msg="auto-backup before system update $(date '+%Y-%m-%d %H:%M:%S')"
    _log "Commit: $msg"
    git -C "$DOTFILES_REPO" commit -m "$msg" >> "$LOG_FILE" 2>&1
  fi

  _log "Push a $REMOTE_NAME/$MAIN_BRANCH..."
  git -C "$DOTFILES_REPO" push "$REMOTE_NAME" "$MAIN_BRANCH" >> "$LOG_FILE" 2>&1
  _log "Respaldo completado y enviado a GitHub."
  _notify normal "Dotfiles respaldados en GitHub."
}

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
  mkdir -p "$LOG_DIR"
  _log "=== Inicio: respaldo + actualización del sistema ==="

  _setup_sudo
  _start_sudo_keepalive
  _backup_dotfiles

  [[ ! -x "$SYSTEM_UPDATE_SCRIPT" ]] && {
    _log "ERROR: Script no encontrado o sin permiso de ejecución: $SYSTEM_UPDATE_SCRIPT"
    exit 1
  }

  _log "Iniciando actualización del sistema..."
  # Pasar SUDO_ASKPASS al script hijo para que no pida contraseña de nuevo.
  # _UPDATE_STANDALONE=false suprime las notificaciones de fallo del hijo;
  # las maneja este script a través del trap EXIT.
  export _UPDATE_STANDALONE=false
  "$SYSTEM_UPDATE_SCRIPT"
}

main "$@"
