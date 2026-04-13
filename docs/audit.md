# Auditoria inicial

Fecha: 2026-04-13

Configuraciones copiadas:

- `~/.config/hypr`: `hyprland.conf`, `hyprpaper.conf`, `hyprlock.conf`, `shaders/vibrancy.glsl`
- `~/.config/waybar`: `config`, `style.css`, scripts `power-menu.sh` y `system-update.sh`
- `~/.config/wofi`: `config`, `style.css`
- `~/.config/alacritty`: `alacritty.toml`
- `~/.config/dunst`: `dunstrc`
- `~/.config/btop`: `btop.conf`
- `~/.config/starship.toml`
- `~/.config/dolphinrc`
- `~/.zshrc`
- `~/.bashrc`
- `/etc/ly/config.ini`

No se copio:

- `~/.ssh`
- historiales de shell
- tokens, `.env`, credenciales y llaves
- caches, logs y temporales
- perfiles de navegador y estado de apps como Vivaldi/Ferdium
- `~/.config/go/telemetry/upload.token`
- `~/.config/pulse/cookie`
- carpetas personales completas como `Documents`, `Downloads` y `Pictures`
- imagenes personales de wallpaper
- backups locales como `hyprland.conf.save*`, `hyprland.conf.backup-*` y `alacritty/backups`
- `.local/bin/claude`, porque es un symlink absoluto hacia `~/.local/share/claude/versions/2.1.101` y no es portable

Notas:

- `~/.gitconfig` no existia al auditar, por eso el paquete `git/` queda preparado pero sin config real.
- La busqueda de patrones sensibles en los candidatos solo encontro un placeholder comentado de password en `hyprlock.conf`.
