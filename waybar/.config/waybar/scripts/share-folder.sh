#!/usr/bin/env bash

set -Eeuo pipefail

readonly PORT="${SHARE_FOLDER_PORT:-8000}"
readonly SIGNAL="${SHARE_FOLDER_WAYBAR_SIGNAL:-9}"
readonly SERVICE_NAME="waybar-share-folder"
readonly SERVICE_UNIT="$SERVICE_NAME.service"

readonly PID_FILE="/tmp/waybar-share-folder-${UID}.pid"
readonly LOG_FILE="/tmp/waybar-share-folder-${UID}.log"

documents_dir() {
  if [[ -d "$HOME/Documentos" ]]; then
    printf '%s/Documentos\n' "$HOME"
  else
    printf '%s/Documents\n' "$HOME"
  fi
}

share_dir() {
  printf '%s/carpeta compartida\n' "$(documents_dir)"
}

notify_user() {
  local title=$1
  local message=$2

  if command -v notify-send >/dev/null 2>&1; then
    notify-send "$title" "$message"
  fi
}

refresh_waybar() {
  pkill -RTMIN+"$SIGNAL" waybar >/dev/null 2>&1 || true
}

is_running() {
  if command -v systemctl >/dev/null 2>&1; then
    systemctl --user is-active --quiet "$SERVICE_UNIT" >/dev/null 2>&1 && return 0
  fi

  [[ -f "$PID_FILE" ]] || return 1

  local pid
  pid=$(<"$PID_FILE")
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  kill -0 "$pid" >/dev/null 2>&1
}

cleanup_stale_pid() {
  if [[ -f "$PID_FILE" ]] && ! is_running; then
    rm -f "$PID_FILE"
  fi
}

local_ip() {
  local ip_addr

  ip_addr=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '
    {
      for (i = 1; i <= NF; i++) {
        if ($i == "src") {
          print $(i + 1)
          exit
        }
      }
    }
  ')

  if [[ -z "$ip_addr" ]]; then
    ip_addr=$(ip -o -4 addr show scope global 2>/dev/null | awk '
      {
        split($4, address, "/")
        print address[1]
        exit
      }
    ')
  fi

  printf '%s\n' "${ip_addr:-127.0.0.1}"
}

url() {
  printf 'http://%s:%s/\n' "$(local_ip)" "$PORT"
}

port_is_busy() {
  ss -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:)${PORT}$"
}

start_server() {
  cleanup_stale_pid

  if is_running; then
    printf 'Servidor activo: %s\n' "$(url)"
    return 0
  fi

  local dir
  dir=$(share_dir)
  mkdir -p "$dir"

  if port_is_busy; then
    printf 'El puerto %s ya esta en uso. Cambia SHARE_FOLDER_PORT o libera ese puerto.\n' "$PORT" >&2
    notify_user "Carpeta compartida" "No se pudo iniciar: el puerto $PORT ya esta en uso."
    exit 1
  fi

  if command -v systemd-run >/dev/null 2>&1 && command -v systemctl >/dev/null 2>&1; then
    systemd-run --user \
      --unit="$SERVICE_NAME" \
      --description="Waybar shared folder server" \
      --collect \
      --property=WorkingDirectory="$dir" \
      python3 -m http.server "$PORT" --bind 0.0.0.0 --directory "$dir" >>"$LOG_FILE" 2>&1
  else
    nohup python3 -m http.server "$PORT" --bind 0.0.0.0 --directory "$dir" >>"$LOG_FILE" 2>&1 &
    printf '%s\n' "$!" >"$PID_FILE"
  fi

  sleep 0.5

  if ! is_running; then
    rm -f "$PID_FILE"
    printf 'No se pudo iniciar el servidor. Revisa %s\n' "$LOG_FILE" >&2
    notify_user "Carpeta compartida" "No se pudo iniciar el servidor."
    exit 1
  fi

  printf 'Compartiendo: %s\n' "$dir"
  printf 'Desde otro dispositivo abre: %s\n' "$(url)"
  notify_user "Carpeta compartida activa" "Abre $(url) desde otro dispositivo."
  refresh_waybar
}

stop_server() {
  cleanup_stale_pid

  if ! is_running; then
    rm -f "$PID_FILE"
    printf 'El servidor ya estaba apagado.\n'
    refresh_waybar
    return 0
  fi

  if command -v systemctl >/dev/null 2>&1 && systemctl --user is-active --quiet "$SERVICE_UNIT" >/dev/null 2>&1; then
    systemctl --user stop "$SERVICE_UNIT" >/dev/null 2>&1 || true
  elif [[ -f "$PID_FILE" ]]; then
    local pid
    pid=$(<"$PID_FILE")
    kill "$pid" >/dev/null 2>&1 || true
  fi

  rm -f "$PID_FILE"

  printf 'Servidor apagado.\n'
  notify_user "Carpeta compartida" "Servidor apagado."
  refresh_waybar
}

toggle_server() {
  if is_running; then
    stop_server
  else
    start_server
  fi
}

json_escape() {
  local value=$1
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\n'/\\n}
  printf '%s' "$value"
}

status_json() {
  cleanup_stale_pid

  local dir tooltip text class_name alt
  dir=$(share_dir)

  if is_running; then
    text="󰒍"
    class_name="active"
    alt="active"
    tooltip="Servidor activo
Carpeta: $dir
URL: $(url)
Clic: apagar
Clic derecho: apagar"
  else
    text="󰉋"
    class_name="inactive"
    alt="inactive"
    tooltip="Servidor apagado
Carpeta: $dir
Clic: iniciar"
  fi

  printf '{"text":"%s","tooltip":"%s","class":"%s","alt":"%s"}\n' \
    "$(json_escape "$text")" \
    "$(json_escape "$tooltip")" \
    "$(json_escape "$class_name")" \
    "$(json_escape "$alt")"
}

usage() {
  cat <<EOF
Uso: ${0##*/} [start|stop|toggle|status|url]

Comparte la carpeta:
  $(share_dir)

URL actual:
  $(url)
EOF
}

main() {
  local action=${1:-toggle}

  case "$action" in
    start) start_server ;;
    stop) stop_server ;;
    toggle) toggle_server ;;
    status) status_json ;;
    url) url ;;
    *) usage ;;
  esac
}

main "$@"
