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
alias install='archinstall'

# History
HISTFILE=~/.zsh_history
HISTSIZE=1000
SAVEHIST=1000

# Display welcome message
if [[ -r /etc/motd ]]; then
    cat /etc/motd
fi
