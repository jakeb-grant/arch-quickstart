# .zshrc for archiso live environment

# Basic zsh configuration
autoload -Uz compinit promptinit
compinit
promptinit

# Prompt
PS1='%B%F{red}[%F{yellow}%n%F{green}@%F{blue}%m%F{magenta} %~%F{red}]%f%b '

# Aliases
alias ls='ls --color=auto'
alias ll='ls -lah'
alias grep='grep --color=auto'

# History
HISTFILE=~/.zsh_history
HISTSIZE=1000
SAVEHIST=1000

# Auto-launch installer on tty1 (autologin terminal)
if [[ $(tty) == /dev/tty1 ]] && [[ -x /usr/local/bin/hyprland-install ]]; then
    /usr/local/bin/hyprland-install
fi
