# ==============================
# ⚡ HISTORIAL INTELIGENTE
# ==============================
HISTSIZE=10000
SAVEHIST=10000
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_FIND_NO_DUPS
setopt SHARE_HISTORY
setopt INC_APPEND_HISTORY

# ==============================
# 🔥 AUTOCOMPLETADO PRO
# ==============================
autoload -Uz compinit
compinit

zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'

# ==============================
# 🧠 KEYBINDINGS (tipo VSCode)
# ==============================
bindkey -e
bindkey '^[[1;5C' forward-word   # Ctrl + →
bindkey '^[[1;5D' backward-word  # Ctrl + ←
bindkey '^H' backward-kill-word  # Ctrl + Backspace

# ==============================
# 🎨 PLUGINS
# ==============================

# Autosuggestions (gris)
source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh

# Syntax highlighting (colores)
source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# ==============================
# 💻 ALIASES PRO
# ==============================
alias ls="eza --icons --group-directories-first"
alias ll="eza -la --icons"
alias cat="bat"
alias grep="grep --color=auto"
alias cls="clear"

# ==============================
# ⚡ FZF (busqueda brutal)
# ==============================
[ -f /usr/share/fzf/key-bindings.zsh ] && source /usr/share/fzf/key-bindings.zsh
[ -f /usr/share/fzf/completion.zsh ] && source /usr/share/fzf/completion.zsh

# ==============================
# 🧾 BANNER
# ==============================
#fastfetch



# Sin banner (más limpio)
# fastfetch  ← comenta esto

# Prompt
eval "$(starship init zsh)"
export ZSH_CURSOR_STYLE=beam
#setopt smoothscroll
export PATH="$HOME/.npm-global/bin:$PATH"
export PATH="$HOME/.local/bin:$PATH"


# Added by Antigravity CLI installer
export PATH="/home/jfranco/.local/bin:$PATH"
