# Hyprland Arch Linux ISO

A custom Arch Linux ISO with a TUI installer for a clean Hyprland desktop environment.

## Related Repositories

- **[jakeb-grant/dotfiles](https://github.com/jakeb-grant/dotfiles)** - Personal dotfiles managed with chezmoi. The installer can optionally apply these during installation.

## What's Included

**Desktop Environment:**
- Hyprland (Wayland compositor)
- SDDM (display manager)
- Waybar (status bar)
- Walker (application launcher with Elephant indexer)
- Ghostty (terminal)

**Applications:**
- Firefox, Nautilus, Zed editor
- PipeWire audio stack
- iwd + impala (WiFi management)

**Fonts:** JetBrains Mono Nerd, Noto fonts

## Installation Flow

### 1. Boot the ISO

Boot from USB and the installer launches automatically.

#### Booting with Ventoy

If using Ventoy, boot the ISO in **GRUB2 mode**:
1. Select the ISO in Ventoy
2. Press Enter, then select "Boot in grub2 mode"

(Normal mode may not work due to ISO boot configuration)

### 2. The Installer

The TUI installer launches automatically and guides you through:

#### Disk Selection
- Lists all available disks (NVMe, SATA, etc.)
- Requires double confirmation before wiping

#### System Configuration
- **Machine type**: Select `laptop` or `desktop`
- **Username**: Pre-filled with default (configurable)
- **Password**: Enter and confirm
- **Disk encryption**: Optional LUKS encryption (can use same password)
- **Timezone**: Defaults to `America/Denver`
- **Git config**: Pre-filled, editable

#### Network
- Auto-detects ethernet connection
- If no connection, offers WiFi setup with network selection

#### What Gets Created

**Partitions (GPT):**
| Partition | Size | Format | Mount |
|-----------|------|--------|-------|
| EFI | 512MB | FAT32 | `/boot` |
| Root | Remaining | BTRFS | `/` |

**BTRFS Subvolumes:**
| Subvolume | Mount Point | Purpose |
|-----------|-------------|---------|
| `@` | `/` | Root filesystem |
| `@home` | `/home` | User data |
| `@snapshots` | `/.snapshots` | Snapshot storage |
| `@var_log` | `/var/log` | Log files |
| `@swap` | `/swap` | Swap file (nodatacow) |

Mount options: `noatime,compress=zstd,space_cache=v2`

**Swap File:**
- Automatically sized based on RAM (supports hibernation)
- RAM ≤ 2GB: 2x RAM
- RAM 2-16GB: Equal to RAM
- RAM > 16GB: Capped at 16GB

#### Packages Installed
~70 packages including the full Hyprland desktop, plus AUR packages via yay:
- `walker-bin` - Application launcher
- `elephant` + providers - Application indexer for Walker

#### System Configuration Applied
- Locale: `en_US.UTF-8`
- Keymap: `us`
- Shell: `bash`
- Multilib repository: Enabled (for 32-bit support)
- Git configured with name/email
- GRUB bootloader (UEFI)
- Services enabled: iwd, systemd-resolved, SDDM

### 3. First Boot

After reboot:
1. SDDM login screen appears
2. Log in with your username/password
3. Hyprland starts automatically

### 4. Post-Install Setup

The installer automatically configures:
- **Bluetooth** (bluez + blueman)
- **Printing** (CUPS + drivers)
- **Firewall** (UFW with user-selected rules)
- **GPU drivers** (based on detected hardware)

These scripts can also be run manually for reconfiguration:

#### GPU Drivers

```bash
nvidia-setup    # NVIDIA GPUs (dedicated or hybrid)
intel-setup     # Intel GPUs (standalone only)
amd-setup       # AMD GPUs (standalone only)
```

**Which script to use:**
| Your Hardware | Script |
|---------------|--------|
| Intel iGPU + NVIDIA dGPU | `nvidia-setup` |
| AMD APU + NVIDIA dGPU | `nvidia-setup` |
| Standalone NVIDIA | `nvidia-setup` |
| Standalone AMD (RX series, APU) | `amd-setup` |
| Standalone Intel | `intel-setup` |

##### nvidia-setup Features
- Auto-detects GPU generation (selects correct driver package)
- Detects hybrid graphics (Intel/AMD + NVIDIA)
- Configures early KMS modules in mkinitcpio
- For hybrid: installs `prime-run` wrapper for GPU offloading
- Adds Hyprland environment variables
- Auto-enables multilib if needed

**After nvidia-setup on hybrid graphics:**
```bash
# Apps run on iGPU by default (power saving)
# Use prime-run to run on NVIDIA dGPU:
prime-run steam
prime-run glxinfo | grep "OpenGL renderer"
```

##### amd-setup / intel-setup Features
- Installs Mesa, Vulkan, and VA-API drivers
- Detects if NVIDIA is present and warns about hybrid
- Adds Hyprland environment variables
- Auto-enables multilib if needed

##### AMD ROCm (GPU Compute)

ROCm is **not installed by default** due to its large size (~500MB+). If you need GPU compute capabilities (OpenCL, machine learning with PyTorch/TensorFlow, Blender GPU rendering), run `amd-setup` manually after installation:

```bash
amd-setup  # Will prompt to install ROCm packages
```

This requires network access as ROCm packages are not included in the offline ISO.

#### System Features

```bash
bluetooth-setup   # Bluetooth + Blueman GUI
printer-setup     # CUPS + drivers
firewall-setup    # UFW with interactive rules
dotfiles-setup    # Clone your dotfiles repo
```

## Default Keybinds (Hyprland)

| Keybind | Action |
|---------|--------|
| `SUPER + Return` | Open terminal (Ghostty) |
| `SUPER + D` | Application launcher (Walker) |
| `SUPER + E` | File manager (Nautilus) |
| `SUPER + Q` | Close window |
| `SUPER + F` | Toggle fullscreen |
| `SUPER + V` | Toggle floating |
| `SUPER + M` | Exit Hyprland |
| `SUPER + 1-9` | Switch workspace |
| `SUPER + SHIFT + 1-9` | Move window to workspace |
| `SUPER + H/J/K/L` | Move focus (vim keys) |
| `SUPER + Arrow Keys` | Move focus |
| `SUPER + Mouse Drag` | Move/resize window |
| `Print` | Screenshot region to clipboard |
| `SHIFT + Print` | Screenshot full screen |
| `XF86Audio*` | Volume controls |
| `XF86MonBrightness*` | Brightness controls |

## Walker (Application Launcher)

Walker uses Elephant as its backend indexer. The following providers are installed:

| Provider | Function |
|----------|----------|
| `desktopapplications` | Launch installed applications |
| `windows` | Switch between open windows |
| `clipboard` | Clipboard history |
| `calc` | Calculator |
| `runner` | Run shell commands |
| `files` | File search |
| `archlinuxpkgs` | Search Arch packages |

## ISO Variants

Two ISO variants are built automatically:

| Variant | Size | Internet Required | Use Case |
|---------|------|-------------------|----------|
| **Online** | ~1.2 GB | Yes (during install) | Fast build, always latest packages |
| **Offline** | ~5-6 GB | No | Air-gapped installs, unreliable network |

### Online ISO
- Smaller download
- Packages downloaded during installation
- Always gets latest package versions
- Requires stable internet connection

### Offline ISO
- All packages pre-built and embedded
- No network required for full installation (including GPU drivers)
- Includes all GPU drivers (NVIDIA, Intel, AMD) - correct ones installed based on detected hardware
- Includes printer drivers, firewall, and Bluetooth packages
- Includes pre-loaded dotfiles (optional)
- Network only needed for: custom dotfiles from a different repo, or AMD ROCm compute packages

## Building the ISO

### GitHub Actions (Automatic)

Push to `main` or `claude/*` branches to trigger a build. Both online and offline ISOs are built in parallel. Download from workflow artifacts.

**Manual trigger with options:**
1. Go to Actions → "Build Arch Linux ISO"
2. Click "Run workflow"
3. Optionally specify:
   - Custom ISO name
   - Dotfiles repo URL (for offline ISO)

**Note:** For security, builds only run on pushes and same-repo PRs. Fork PRs are blocked.

### Local Build

```bash
# Install dependencies
sudo pacman -S archiso

# Build (creates online variant)
cd archiso
sudo mkarchiso -v -w /tmp/archiso-work -o /tmp/archiso-out .
```

For offline builds with pre-loaded packages, use the GitHub Actions workflow.

## Configuration Files

### `install.conf` - Installation Defaults

```bash
DEFAULT_USERNAME="jacob"
DEFAULT_HOSTNAME_OPTIONS=("laptop" "desktop")
GIT_USER_NAME="jacob"
GIT_USER_EMAIL="86214494+jakeb-grant@users.noreply.github.com"
DEFAULT_TIMEZONE="America/Denver"
DEFAULT_LOCALE="en_US.UTF-8"
DEFAULT_KEYMAP="us"
```

### `dotfiles.conf` - Offline Dotfiles

```bash
# Dotfiles repository to include in offline ISO builds
DOTFILES_REPO=https://github.com/jakeb-grant/dotfiles
```

When set, the offline ISO will include pre-cloned dotfiles at `/opt/dotfiles`. The installer detects these and offers to apply them automatically—no network required.

Leave empty to skip pre-loading dotfiles. Users can still enter a repo URL during installation if network is available.

### `archiso/airootfs/root/target-packages.x86_64` - Installed System Packages

Packages installed on the target system (the full Hyprland desktop). This is the **single source of truth** for target packages—the installer reads from this location.

### `archiso/airootfs/root/aur-packages.x86_64` - AUR Packages

AUR packages installed via yay on the target system. Comments (lines starting with `#`) and blank lines are ignored.

### `archiso/airootfs/root/setup-packages.x86_64` - Setup Script Packages

Packages included in the offline repository but **not auto-installed**. These are installed on-demand by the setup scripts:

| Category | Packages | Used By |
|----------|----------|---------|
| NVIDIA | `nvidia-dkms`, `nvidia-open-dkms`, `nvidia-utils`, etc. | `nvidia-setup` |
| Intel | `mesa`, `vulkan-intel`, `intel-media-driver`, etc. | `intel-setup` |
| AMD | `vulkan-radeon`, `libva-mesa-driver`, etc. | `amd-setup` |
| Firewall | `ufw` | `firewall-setup` |
| Printing | `cups`, `ghostscript`, `gutenprint`, etc. | `printer-setup` |

This architecture allows the offline ISO to support any hardware configuration without installing unnecessary drivers. The correct packages are installed based on detected hardware during the setup phase.

### `archiso/packages.x86_64` - Live ISO Packages

Packages included in the live environment (for installation/rescue).

## Directory Structure

```
archiso/
├── profiledef.sh              # ISO profile configuration
├── packages.x86_64            # Live ISO packages
├── pacman.conf                # Pacman config (multilib enabled)
├── dotfiles.conf              # Dotfiles repo for offline ISO
├── airootfs/
│   ├── etc/
│   │   ├── pacman.conf        # Target system pacman config
│   │   ├── pacman.d/
│   │   │   ├── mirrorlist
│   │   │   └── offline-pacman.conf  # Offline mode pacman config
│   │   └── skel/.config/hypr/
│   │       └── hyprland.conf  # Default Hyprland config
│   ├── opt/
│   │   ├── offline-repo/      # Pre-built packages (offline ISO only)
│   │   └── dotfiles/          # Pre-cloned dotfiles (offline ISO only)
│   ├── root/
│   │   ├── install.conf       # Installer defaults
│   │   ├── target-packages.x86_64  # Target system packages (always installed)
│   │   ├── aur-packages.x86_64     # AUR packages (always installed)
│   │   └── setup-packages.x86_64   # Setup script packages (on-demand)
│   └── usr/local/bin/
│       ├── hyprland-install   # Main TUI installer
│       ├── nvidia-setup       # NVIDIA driver setup (hybrid support)
│       ├── intel-setup        # Intel driver setup
│       ├── amd-setup          # AMD driver setup
│       ├── bluetooth-setup    # Bluetooth setup
│       ├── printer-setup      # CUPS setup
│       ├── firewall-setup     # UFW setup
│       └── dotfiles-setup     # Dotfiles deployment
├── grub/                      # GRUB (UEFI) config
├── syslinux/                  # Syslinux (BIOS) config
└── efiboot/                   # systemd-boot entries
```

## Creating Releases

Tag a commit to create a GitHub release with the ISO:

```bash
git tag v1.0.0
git push origin v1.0.0
```
