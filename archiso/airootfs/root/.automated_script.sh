#!/usr/bin/env bash
# Automated startup script for the live environment

# Generate locales
locale-gen

# Configure pacman
if [[ -e /run/archiso/bootmnt/arch/boot/x86_64/vmlinuz-linux ]]; then
    # Running from archiso
    printf "Configuring pacman...\n"
    pacman-key --init
    pacman-key --populate archlinux
fi

# Set console font if available
if [[ -r /usr/share/kbd/consolefonts/ter-116n.psf.gz ]]; then
    setfont ter-116n
fi
