# Custom Arch Linux ISO Builder

This repository contains the configuration for building a custom Arch Linux ISO using [archiso](https://wiki.archlinux.org/title/Archiso).

## Features

- Automated ISO builds via GitHub Actions
- Both BIOS and UEFI boot support
- Pre-configured with essential system tools
- NetworkManager for easy network configuration
- SSH server enabled for remote access
- archinstall for guided installation

## Building the ISO

### Automatic (GitHub Actions)

1. Push changes to the `main` branch or `claude/*` branches
2. The workflow triggers automatically when files in `archiso/` change
3. Download the built ISO from the workflow artifacts

You can also manually trigger a build:
1. Go to **Actions** → **Build Arch Linux ISO**
2. Click **Run workflow**
3. Optionally specify a custom ISO name

### Manual (Local Build)

```bash
# Install dependencies (on Arch Linux)
sudo pacman -S archiso

# Build the ISO
cd archiso
sudo mkarchiso -v -w /tmp/archiso-work -o /tmp/archiso-out .

# The ISO will be in /tmp/archiso-out/
```

## Directory Structure

```
archiso/
├── profiledef.sh         # Main profile configuration
├── packages.x86_64       # Packages to install in the ISO
├── pacman.conf           # Pacman configuration for build
├── airootfs/             # Root filesystem customizations
│   ├── etc/              # System configuration files
│   │   ├── hostname
│   │   ├── locale.conf
│   │   ├── mkinitcpio.conf
│   │   └── systemd/      # Systemd services and presets
│   ├── root/             # Root user home directory
│   └── usr/local/bin/    # Custom scripts
├── efiboot/              # EFI boot configuration
├── grub/                 # GRUB bootloader config
└── syslinux/             # Syslinux (BIOS) bootloader config
```

## Customization

### Adding Packages

Edit `archiso/packages.x86_64` to add or remove packages:

```
# Add your packages, one per line
firefox
code
```

### Adding Custom Files

Place files in `archiso/airootfs/` mirroring the target path:
- `airootfs/etc/myconfig.conf` → `/etc/myconfig.conf`
- `airootfs/usr/local/bin/myscript` → `/usr/local/bin/myscript`

### Enabling Services

Edit `archiso/airootfs/etc/systemd/system-preset/00-archiso.preset`:

```
enable myservice.service
```

### Modifying Boot Options

- **GRUB (UEFI)**: Edit `archiso/grub/grub.cfg`
- **Syslinux (BIOS)**: Edit `archiso/syslinux/syslinux.cfg`
- **systemd-boot**: Edit files in `archiso/efiboot/loader/`

## Boot Options

The ISO provides several boot options:

| Option | Description |
|--------|-------------|
| Default | Normal boot with persistent storage |
| copytoram | Copy ISO to RAM (removes USB drive dependency) |
| Accessibility | Boot with speech synthesis enabled |

## Live Environment

After booting:
- **Root password**: None (empty, auto-login enabled)
- **Installation**: Run `archinstall` for guided setup
- **Network**: NetworkManager is pre-enabled
- **SSH**: Available for remote access

## Creating Releases

Tag a commit to create a GitHub release with the ISO:

```bash
git tag v1.0.0
git push origin v1.0.0
```

## Requirements

### GitHub Actions
- Runs on `ubuntu-latest` with Arch Linux container
- No additional secrets required

### Local Build
- Arch Linux system
- `archiso` package installed
- Root privileges for mkarchiso

## License

This configuration is based on the official Arch Linux [releng profile](https://gitlab.archlinux.org/archlinux/archiso/-/tree/master/configs/releng).
