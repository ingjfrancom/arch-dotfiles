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
