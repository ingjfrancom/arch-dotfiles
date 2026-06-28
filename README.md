# Arch Dotfiles

Dotfiles reproducibles para Arch Linux usando Git, GNU Stow y scripts shell.

Repo remoto: `git@github.com:ingjfrancom/arch-dotfiles.git`

## Estructura

- `hypr/`: Hyprland, Hyprpaper, Hyprlock y shader local
- `waybar/`: barra, estilos y scripts
- `wofi/`: launcher
- `alacritty/`: terminal
- `dunst/`: notificaciones
- `zsh/` y `bash/`: shells
- `dolphin/`: `dolphinrc`
- `btop/`: monitor de sistema
- `starship/`: prompt
- `local-bin/`: carpeta preparada para scripts portables de `~/.local/bin`
- `ly/`: config de `/etc/ly/config.ini`
- `packages/`: listas exportadas de pacman y AUR
- `systemd/`: servicios habilitados del sistema y usuario
- `wallpapers/`: carpeta preparada, sin imagenes personales pesadas
- `docs/`: auditoria y notas

## Restauracion rapida

En una maquina nueva:

```sh
git clone git@github.com:ingjfrancom/arch-dotfiles.git ~/arch-dotfiles
cd ~/arch-dotfiles
./restore.sh
```

Tambien puedes usar el bootstrap desde cualquier ubicacion:

```sh
REPO_URL=git@github.com:ingjfrancom/arch-dotfiles.git ./bootstrap.sh
```

`restore.sh` instala paquetes, aplica dotfiles de usuario con Stow, restaura `/etc/ly/config.ini` por copia con backup, habilita servicios systemd y crea carpetas necesarias.

## Restauracion manual

```sh
cd ~/arch-dotfiles
./install-packages.sh
./restore.sh dotfiles
./restore.sh system-configs
./restore.sh services
```

Los dotfiles crean backups por archivo en `~/.dotfiles-backup-YYYYmmdd-HHMMSS` antes de reemplazar conflictos.

## Menu interactivo

```sh
cd ~/arch-dotfiles
./install-interactive.sh
```

Opciones disponibles:

- instalar paquetes
- aplicar dotfiles
- restaurar servicios
- restauracion completa

## Actualización del sistema desde Waybar

El menú de apagado de Waybar incluye dos scripts en `waybar/.config/waybar/scripts/`:

### `update-system-with-backup.sh` (entrada principal)

Ejecuta el flujo completo sin interacción:

1. Pide la contraseña de sudo **una sola vez** mediante un cuadro de diálogo (zenity).
2. Valida las credenciales y arranca un proceso en segundo plano que renueva el timestamp de sudo cada 270 s para que no expire en actualizaciones largas.
3. Hace `git pull --rebase` + `git add` + `git commit` + `git push` del repo de dotfiles como **respaldo previo** a la actualización. Si no hay cambios nuevos, omite el commit.
4. Detecta y bloquea el commit si hay archivos sensibles en staging (`.env`, claves privadas, tokens de GitHub/AWS).
5. Llama a `system-update.sh` pasando `SUDO_ASKPASS` y `_UPDATE_STANDALONE=false` para que no vuelva a pedir contraseña ni genere notificaciones de fallo duplicadas.
6. Al finalizar, elimina los archivos temporales de contraseña y revoca el timestamp de sudo.

### `system-update.sh` (también ejecutable de forma independiente)

Actualiza pacman, AUR (yay/paru con `--sudoflags="-A"`) y Flatpak sin interacción. Si se llama de forma directa y no encuentra `SUDO_ASKPASS`, muestra su propio diálogo zenity.

### Revertir una actualización fallida

```sh
cd ~/arch-dotfiles
git log --oneline          # buscar el commit "auto-backup before system update ..."
git checkout <hash> -- .   # restaurar ese estado de los dotfiles
```

### Logs

Cada ejecución guarda un log en `~/.cache/system-updates/`:

```
~/.cache/system-updates/backup-YYYYMMDD-HHMMSS.log   # respaldo + git
~/.cache/system-updates/update-YYYYMMDD-HHMMSS.log   # pacman/AUR/flatpak
```

### Dependencias

| Herramienta | Paquete         | Uso                              |
|-------------|-----------------|----------------------------------|
| `zenity`    | `zenity`        | Diálogo de contraseña            |
| `notify-send` | `libnotify`   | Notificaciones (dunst)           |
| `yay`/`paru`| AUR             | Helper AUR (opcional)            |
| `flatpak`   | `flatpak`       | Paquetes Flatpak (opcional)      |

## Exportaciones

- `packages/pkglist.txt`: paquetes oficiales y explicitos de pacman
- `packages/aurlist.txt`: paquetes detectados como externos/AUR
- `systemd/system-enabled.txt`: servicios systemd del sistema habilitados
- `systemd/user-enabled.txt`: servicios systemd de usuario habilitados

Para refrescar manualmente:

```sh
pacman -Qqen > packages/pkglist.txt
pacman -Qqm > packages/aurlist.txt
systemctl list-unit-files --state=enabled --no-pager > systemd/system-enabled.txt
systemctl --user list-unit-files --state=enabled --no-pager > systemd/user-enabled.txt
```

## Exclusiones

No se versiona:

- `~/.ssh`
- tokens, API keys, credenciales, `.env` y llaves privadas
- historiales sensibles
- caches, logs y temporales
- perfiles de navegador o estado de sesiones
- carpetas personales completas como `Documents`, `Downloads` y `Pictures`
- imagenes pesadas/personales de wallpaper

Consulta `docs/audit.md` para ver que se copio y que se omitio en esta maquina.
