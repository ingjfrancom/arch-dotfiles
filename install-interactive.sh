#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

while true; do
  cat <<'MENU'

Arch dotfiles
1. Instalar paquetes
2. Aplicar dotfiles
3. Restaurar servicios
4. Restauracion completa
5. Salir
MENU

  read -r -p "Elige una opcion: " choice
  case "$choice" in
    1) "$ROOT_DIR/restore.sh" packages ;;
    2) "$ROOT_DIR/restore.sh" dotfiles ;;
    3) "$ROOT_DIR/restore.sh" services ;;
    4) "$ROOT_DIR/restore.sh" all ;;
    5) exit 0 ;;
    *) echo "Opcion invalida." ;;
  esac
done
