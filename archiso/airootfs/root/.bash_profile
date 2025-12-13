# .bash_profile - executed for login shells

[[ -f ~/.bashrc ]] && . ~/.bashrc

# Auto-launch installer on tty1 (autologin terminal)
if [[ $(tty) == /dev/tty1 ]] && [[ -x /usr/local/bin/hyprland-install ]]; then
    /usr/local/bin/hyprland-install
fi
