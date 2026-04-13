#!/usr/bin/env bash

set -Eeuo pipefail

readonly NOTIFY_TITLE="Actualizacion con respaldo"
readonly DOTFILES_REPO="${HOME}/arch-dotfiles"
readonly REMOTE_NAME="origin"
readonly MAIN_BRANCH="main"
readonly SYSTEM_UPDATE_SCRIPT="${HOME}/.config/waybar/scripts/system-update.sh"

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

ask_yes_no() {
  local prompt=$1
  local answer

  printf '%s [s/N]: ' "$prompt"
  read -r answer
  [[ "$answer" =~ ^([sS]|[sS][iI])$ ]]
}

confirm_update_without_backup() {
  local reason=$1

  printf '\nERROR: %s\n' "$reason" >&2
  notify_user "$reason"

  if ask_yes_no "Continuar de todos modos con la actualizacion"; then
    printf 'Continuando sin respaldo previo.\n'
    return 0
  fi

  printf 'Actualizacion cancelada. No se actualizo el sistema.\n'
  notify_user "Actualizacion cancelada antes de actualizar el sistema."
  pause_before_exit
  exit 1
}

verify_dotfiles_repo() {
  print_section "Verificando repositorio de dotfiles"
  printf 'Repositorio esperado: %s\n' "$DOTFILES_REPO"

  if [[ ! -d "$DOTFILES_REPO" ]]; then
    return 1
  fi

  if ! git -C "$DOTFILES_REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    return 1
  fi

  printf 'Repositorio git valido.\n'
}

scan_staged_for_suspicious_content() {
  local file
  local base
  local -a staged_files=()

  mapfile -t staged_files < <(git diff --cached --name-only --diff-filter=ACMR)

  for file in "${staged_files[@]}"; do
    base=$(basename "$file")

    # Evita subir por accidente archivos tipicos de secretos nuevos.
    case "$base" in
      .env|*.env|*.pem|*.key|id_rsa|id_dsa|id_ecdsa|id_ed25519)
        printf 'Archivo sospechoso preparado para commit: %s\n' "$file" >&2
        return 1
        ;;
    esac

    if git show ":$file" 2>/dev/null | grep -Eq -- '-----BEGIN (OPENSSH|RSA|DSA|EC|PRIVATE) PRIVATE KEY-----|ghp_[A-Za-z0-9_]{36,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}'; then
      printf 'Contenido sensible potencial detectado en: %s\n' "$file" >&2
      return 1
    fi
  done
}

backup_dotfiles() {
  local commit_message

  print_section "Respaldando dotfiles en GitHub"
  cd "$DOTFILES_REPO"

  printf 'Preparando cambios con git add .\n'
  if ! git add .; then
    return 1
  fi

  if ! scan_staged_for_suspicious_content; then
    printf 'Se cancela el respaldo para evitar subir algo potencialmente sensible.\n' >&2
    return 1
  fi

  if git diff --cached --quiet; then
    printf 'No hay cambios nuevos para commitear.\n'
  else
    commit_message="auto-backup before system update $(date '+%Y-%m-%d %H:%M:%S')"
    printf 'Creando commit: %s\n' "$commit_message"

    if ! git commit -m "$commit_message"; then
      return 1
    fi
  fi

  printf 'Enviando respaldo a %s/%s.\n' "$REMOTE_NAME" "$MAIN_BRANCH"
  if ! git push "$REMOTE_NAME" "$MAIN_BRANCH"; then
    return 1
  fi

  printf 'Respaldo terminado correctamente.\n'
  notify_user "Respaldo de dotfiles completado."
}

run_system_update() {
  print_section "Iniciando actualizacion del sistema"

  if [[ ! -x "$SYSTEM_UPDATE_SCRIPT" ]]; then
    printf 'No se encontro el script de actualizacion o no es ejecutable: %s\n' "$SYSTEM_UPDATE_SCRIPT" >&2
    pause_before_exit
    exit 1
  fi

  exec "$SYSTEM_UPDATE_SCRIPT"
}

main() {
  clear
  printf 'Actualizacion del sistema con respaldo previo\n'
  printf 'Fecha: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"

  if ! verify_dotfiles_repo; then
    confirm_update_without_backup "No existe ${DOTFILES_REPO} o no es un repositorio git valido."
    run_system_update
  fi

  if ! backup_dotfiles; then
    confirm_update_without_backup "Fallo el respaldo de dotfiles antes de actualizar."
  fi

  run_system_update
}

main "$@"
