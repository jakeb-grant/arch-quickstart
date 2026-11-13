# Hyprland Arch Linux ISO

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A custom Arch Linux ISO with a TUI installer for a clean Hyprland desktop environment. Boot from USB, answer a few prompts, and walk away with a fully configured Hyprland desktop — GPU drivers, Bluetooth, printing, firewall, and your dotfiles all handled, online or completely air-gapped.

## Related Repositories

- **[jakeb-grant/dotfiles](https://github.com/jakeb-grant/dotfiles)** - Personal dotfiles managed with chezmoi. The installer can optionally apply these during installation.
- **[jakeb-grant/strand](https://github.com/jakeb-grant/strand)** - The Wayland shell those dotfiles use (bar, launcher, notifications, lock screen, polkit prompt). It is not a pacman package; the installer installs it as a [user install](#archisoairootfsusrlocalshareuser-installs---user-installs).
- See the section of the README on configuration files for additional detail. Your dotfiles repo must be managed with chezmoi, and everything it needs must be installed by one of three lists: `archiso/airootfs/root/target-packages.x86_64` (packages in the official repos), `archiso/airootfs/root/aur-packages.x86_64` (AUR packages), or a user install in `archiso/airootfs/usr/local/share/user-installs/` (tools installed some other way, such as by their own install script).

## Installation Flow

### 1. Boot the ISO

Boot from USB and the installer launches automatically.

#### Booting with Ventoy

If using Ventoy, boot the ISO in **GRUB2 mode**:
1. Select the ISO in Ventoy
2. Press Enter, then select "Boot in grub2 mode"

(Normal mode may not work due to ISO boot configuration)

### 2. The Installer

The TUI installer launches automatically. It is drawn for the Linux console it runs on (16 colours, an 80x25 screen, a 256-glyph font). Every screen after the welcome opens with a small `◆ arch quickstart` masthead showing the chapter as `n of 10 · name` (the network check, before the chapters, shows `hyprland on arch` instead). The line of water under it rolls as a wave through the finished chapters.

The welcome screen shows the route in two acts:
- **You answer:** disk · you · machine · review. Nothing is written to any disk in this part. Ctrl-C stops cleanly anywhere in it, and so does Esc at a menu or text prompt (at a yes/no question, Esc means no).
- **Then it runs:** prepare · base · system · apps · extras · dotfiles. Normally nothing asks for input until the dotfiles chapter, where the screen flashes to call you back.

Before the chapters it checks the network (and, on the offline ISO, the offline repository).

#### Network
- Auto-detects ethernet connection
- If no connection, offers WiFi setup with network selection
- The offline ISO needs no network; only a remote dotfiles repo would

#### Disk Selection
- Lists all available disks (NVMe, SATA, eMMC, etc.), excluding the USB stick the installer booted from
- Shows the chosen disk's current partitions and asks "Erase /dev/…?" as a first check. Nothing is erased there: the erase waits until you type the disk's name on the [review screen](#review)

#### System Configuration
- **Hostname**: Text input, pre-filled with default (configurable)
- **Username**: Pre-filled with default (configurable)
- **Password**: Enter and confirm (a typo asks again, up to three times)
- **Disk encryption**: Optional LUKS encryption (can use same password)
- **Timezone**: Defaults to `America/Denver`
- **Git config**: Pre-filled, editable

#### Graphics and Firewall
- Detects the GPUs and recommends a driver setup (`nvidia-setup`, `intel-setup`, `amd-setup`, or none)
- Firewall: everything closed, with SSH, HTTP/HTTPS and KDE Connect as optional openings (`x` toggles)

#### Review
Every answer on one card (disk and what it becomes, machine, locale, git, graphics, firewall), with a plain "Nothing has been written yet":
- **Install on /dev/X**, **Change the disk**, **Change you**, **Change machine**, or **Quit, nothing written**. A changed chapter starts from your earlier answers, so Enter keeps each one (the passwords are typed again).
- Install shows the disk as it is now and asks you to **type its name** (`nvme0n1`, or `/dev/nvme0n1`). This proves you read which disk. It is the only gate: nothing touches the disk before it, and normally nothing asks for input after it until dotfiles. A wrong name asks again; the third wrong name stops with nothing written.

#### While It Runs
- The long steps (pacstrap, the setup scripts, the AUR builds, the user installs, chezmoi) print straight to the screen, between two labelled rules. The closing rule gives the outcome and the time taken, e.g. `── ■ 1,284 packages ──── 3m 41s ──`.
- Once GRUB is verified, a checkpoint card says the machine can boot on its own. From then on a step that fails prints a warning and the installer carries on, rather than stopping a bootable install.
- The console has no scrollback, so every warning that comes with a fix is also kept for the finish screen.

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
About 110 packages from the official repos and 15 from the AUR (built with yay) provide a base Hyprland desktop. Without dotfiles the system boots to Hyprland with a terminal (Kitty), yazi and Hyprland's example keybinds. The desktop shell and theming come from your dotfiles (see `dotfiles.conf`), so customize the package lists to preload whatever your dotfiles need. The author's dotfiles use Strand as their shell, which the installer adds as a user install.

The online ISO builds the AUR packages as your user, and makepkg and yay call `sudo`; the builds can outlast sudo's password timeout, so they get the same temporary passwordless rule as the dotfiles step (below), removed as soon as they finish. If that rule cannot be set up, the installer says so, and the builds may ask for your password. A package that fails to build never stops the installation, and neither does Ctrl-C during the builds: the installer prints the `yay` command to finish the job after rebooting.

#### User Installs
After the AUR packages, the installer runs the [user installs](#archisoairootfsusrlocalshareuser-installs---user-installs): tools installed for your user by a script, outside pacman. Two ship with this repo:
- `strand` - the Strand shell, from its edge channel (on the offline ISO, the edge build bundled when the ISO was built)
- `rust` - rustup's stable toolchain as the default (needs the network)

A failed user install never stops the installation; it prints the command to retry it after rebooting.

#### Dotfiles
Last, the installer applies your dotfiles with `chezmoi init --apply`, as your user, in the new system:
- It stays attached to the terminal, so chezmoi's prompts (`promptChoiceOnce` and the like) are asked as usual.
- The dotfiles' scripts can use `sudo` without a password while chezmoi runs (the online AUR builds get the same rule while they run). The rule allowing it (`/etc/sudoers.d/90-arch-quickstart-install`) is removed as soon as chezmoi finishes, and again by the installer's exit handler if the installer stops early. Only a power cut during the step can leave it behind.
- It runs with `--keep-going`, so one failing script does not stop the others. A failed `run_once_`/`run_onchange_` script is not recorded, and `chezmoi apply` after rebooting runs it again.
- `ARCH_QUICKSTART_INSTALL=1` is set, so templates and scripts can tell they are running from the installer, in a chroot where nothing of the new system is booted yet.
- Ctrl-C stops chezmoi, not the installation.

#### System Configuration Applied
- Locale: `en_US.UTF-8`
- Keymap: `us`
- Shell: `bash`
- Multilib repository: Enabled (for 32-bit support)
- Git configured with name/email
- GRUB bootloader (UEFI), plus a fallback copy at `EFI/BOOT/BOOTX64.EFI` so the disk boots even if the firmware's boot entry is lost (CMOS reset, board swap)
- Services enabled: iwd, systemd-resolved, greetd

#### The Finish Screen
A receipt on one screen: the machine and user, the disk, the desktop (package count, dotfiles applied or not), how long the install took, and (when there is room) the time per chapter. Below it are the things left to do after rebooting, each with the exact command where there is one (`yay -S hyprshot`, `chezmoi apply`, ...), or "Nothing left to do. Clean run." Then it asks whether to reboot. The same receipt is saved as plain text to `~/install-report.txt` and `/var/log/arch-quickstart-install.txt`.

#### If Something Fails
Before the checkpoint, a failure stops the installer. It prints what failed (for an unexpected error, the exact command and line) and, if the disk was already touched, unmounts the target and closes the LUKS container. For an unexpected error, or any other stop once the disk was touched (except Ctrl-C, which only cleans up), it then shows a card: where it stopped, what that usually means, the state of the disk, and what to do next. A check that stops it before the disk is touched (no disk found, the disk's name mistyped three times) says why in one line, with nothing written. Re-running `hyprland-install` is safe and starts over.

### 3. First Boot

After reboot:
1. greetd/tuigreet login screen appears
2. Log in with your username/password
3. Hyprland starts automatically

Anything the finish screen listed as left to do is in `~/install-report.txt`.

### 4. Post-Install Setup

The installer automatically configures:
- **Bluetooth** (bluez + bluetui)
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
- Writes Hyprland environment variables to `~/.config/hypr/gpu-env.lua`, which the fallback config loads (dotfiles that manage `hyprland.lua` set their own, or add `pcall(require, "gpu-env")`)
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
- Writes Hyprland environment variables to `~/.config/hypr/gpu-env.lua`, which the fallback config loads (dotfiles that manage `hyprland.lua` set their own, or add `pcall(require, "gpu-env")`)
- Auto-enables multilib if needed

##### AMD ROCm (GPU Compute)

ROCm is **not installed by default** due to its large size (~500MB+). If you need GPU compute capabilities (OpenCL, machine learning with PyTorch/TensorFlow, Blender GPU rendering), run `amd-setup` manually after installation:

```bash
amd-setup  # Will prompt to install ROCm packages
```

This requires network access as ROCm packages are not included in the offline ISO.

#### System Features

```bash
bluetooth-setup      # Bluetooth + Bluetui TUI
printer-setup        # CUPS + drivers
firewall-setup       # UFW with interactive rules
dotfiles-setup       # Clone your dotfiles repo
user-installs-setup  # Run the user installs again (all, or the ones named); also updates them
```

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
- Includes what the user installs need offline (Strand's edge build, fetched when the ISO is built)
- Network only needed for: custom dotfiles from a different repo, AMD ROCm compute packages, or user installs without an offline payload (`rust`)

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

## Testing

An ISO build takes about an hour, so most checks run without one:

```bash
bash tests/s5-runner.sh all     # installer scenarios, no VM and no root
bash tests/glyph-lint.sh        # every character the installer prints draws on tty1
python3 tests/tty-render.py capture.ans screen.png   # see a screen as tty1 shows it
```

- `tests/s5-runner.sh` runs the real installer functions against stubbed commands, as root inside a user namespace (`unshare -rm`) with throwaway `/mnt` and `/root`, so nothing on the host is touched. It covers pacstrap, the AUR, user-install and dotfiles steps, swap, teardown, the review gate, the finish receipt and the failure card.
- `tests/glyph-lint.sh` (also run in CI) fails on any character outside the glyphs the live ISO's console font draws as intended, and on gum options or defaults that would draw ones it lacks. A missing glyph shows up as a small square, so it is easy to miss by eye.
- `tests/tty-render.py` draws captured terminal output (ANSI escapes included) pixel for pixel through that font, at 80x25 by default. It also reports missing glyphs and lines over 79 columns. It needs `ter-116n.psf.gz`, which is not in the repo. The script's header shows how to fetch it from the `terminus-font` package without installing it.

## Configuration Files

### `install.conf` - Installation Defaults

```bash
DEFAULT_USERNAME="jacob"
DEFAULT_HOSTNAME="archlinux"
GIT_USER_NAME="jacob"
GIT_USER_EMAIL="86214494+jakeb-grant@users.noreply.github.com"
DEFAULT_TIMEZONE="America/Denver"
DEFAULT_LOCALE="en_US.UTF-8"
DEFAULT_KEYMAP="us"
DEFAULT_FONT=""          # console font; empty keeps the kernel default
DEFAULT_SHELL="/bin/bash"
```

These are only pre-filled defaults for the installer prompts—every one can be changed at install time. **Forking this repo?** Swap in your own values here (the username/name/email above are the author's) and point `dotfiles.conf` below at your own dotfiles repo.

### `archiso/airootfs/etc/dotfiles.conf` - Dotfiles Repository

```bash
# Dotfiles repository for ISO builds and dotfiles-setup
DOTFILES_REPO=https://github.com/jakeb-grant/dotfiles
```

The single source of truth for your dotfiles repo:

- **Offline ISO builds**: the repo is pre-cloned to `/opt/dotfiles` on the ISO. The installer detects it and offers to apply it automatically—no network required.
- **Installer prompt**: the remote-repo prompt comes pre-filled with this value (editable).
- **Installed system**: the file lands at `/etc/dotfiles.conf`, where `dotfiles-setup` uses it as the default repo when run without an argument.

Leave empty to skip pre-loading dotfiles. Users can still enter a repo URL during installation if network is available.

### `archiso/airootfs/root/target-packages.x86_64` - Installed System Packages

Packages installed on the target system (the full Hyprland desktop). This is the **single source of truth** for target packages—the installer reads from this location.

### `archiso/airootfs/root/aur-packages.x86_64` - AUR Packages

AUR packages installed via yay on the target system. Comments (lines starting with `#`) and blank lines are ignored.

### `archiso/airootfs/root/setup-packages.x86_64` - Setup Script Packages

Packages included in the offline repository but **not auto-installed**. These are installed on-demand by the setup scripts:

| Category | Packages | Used By |
|----------|----------|---------|
| NVIDIA | `nvidia-open-dkms`, `nvidia-utils`, `egl-wayland`, etc. | `nvidia-setup` |
| Intel | `mesa`, `vulkan-intel`, `intel-media-driver`, etc. | `intel-setup` |
| AMD | `vulkan-radeon`, `vulkan-tools`, etc. | `amd-setup` |
| Firewall | `ufw` | `firewall-setup` |
| Printing | `cups`, `ghostscript`, `gutenprint`, etc. | `printer-setup` |

This architecture allows the offline ISO to support any hardware configuration without installing unnecessary drivers. The correct packages are installed based on detected hardware during the setup phase.

### `archiso/airootfs/usr/local/share/user-installs/` - User Installs

Tools installed for one user by a script, outside pacman and the AUR (a shell's own installer, a release binary, a toolchain). Each is a directory:

```
user-installs/<name>/
  install   run as the user, in ~; installs or updates the tool
  fetch     optional; run in CI for the offline ISO, bundles what install needs
```

`install` runs as the new user (never root) and must be safe to run again, since running it again is how a user retries or updates. `PAYLOAD` holds the path to the bundled payload on the offline ISO and is empty otherwise; install from it when it is set, else from the network. A non-zero exit is reported, never fatal.

`fetch` runs as `fetch DIR` while the offline ISO is built (curl, jq and `GITHUB_TOKEN` available) and downloads everything `install` needs into `DIR`, which lands at `/opt/user-installs/<name>/` on the ISO. A failing `fetch` fails the build. Without a `fetch`, `install` needs the network on the offline ISO too.

The installer copies the directory to the installed system, where `user-installs-setup [name...]` runs them again. See [`user-installs/README.md`](archiso/airootfs/usr/local/share/user-installs/README.md) and the `strand` user install for an example.

### `archiso/packages.x86_64` - Live ISO Packages

Packages included in the live environment (for installation/rescue).

## Directory Structure

```
archiso/
├── profiledef.sh              # ISO profile configuration
├── packages.x86_64            # Live ISO packages
├── pacman.conf                # Pacman config (multilib enabled)
├── airootfs/
│   ├── etc/
│   │   ├── dotfiles.conf      # Dotfiles repo (offline builds + dotfiles-setup default)
│   │   ├── pacman.conf        # Target system pacman config
│   │   ├── pacman.d/
│   │   │   ├── mirrorlist
│   │   │   └── offline-pacman.conf  # Offline mode pacman config
│   │   └── skel/.config/hypr/
│   │       └── hyprland.lua   # Fallback Hyprland config (used without dotfiles)
│   ├── opt/
│   │   ├── offline-repo/      # Pre-built packages (offline ISO only)
│   │   ├── dotfiles/          # Pre-cloned dotfiles (offline ISO only)
│   │   └── user-installs/     # User-install payloads, e.g. Strand (offline ISO only)
│   ├── root/
│   │   ├── install.conf       # Installer defaults
│   │   ├── target-packages.x86_64  # Target system packages (always installed)
│   │   ├── aur-packages.x86_64     # AUR packages (always installed)
│   │   ├── setup-packages.x86_64   # Setup script packages (on-demand)
│   │   └── setup-aur-packages.x86_64  # Setup AUR packages (on-demand)
│   ├── usr/local/bin/
│   │   ├── hyprland-install   # Main TUI installer
│   │   ├── nvidia-setup       # NVIDIA driver setup (hybrid support)
│   │   ├── intel-setup        # Intel driver setup
│   │   ├── amd-setup          # AMD driver setup
│   │   ├── bluetooth-setup    # Bluetooth setup
│   │   ├── printer-setup      # CUPS setup
│   │   ├── firewall-setup     # UFW setup
│   │   ├── dotfiles-setup     # Dotfiles deployment
│   │   └── user-installs-setup  # Runs the user installs
│   ├── usr/local/lib/
│   │   └── setup-common.sh    # Shared helpers for the setup scripts
│   └── usr/local/share/user-installs/
│       ├── README.md          # How to add a user install
│       ├── strand/            # Strand shell (install + fetch)
│       └── rust/              # rustup stable toolchain (install)
├── grub/                      # GRUB (UEFI) config
├── syslinux/                  # Syslinux (BIOS) config
└── efiboot/                   # systemd-boot entries
tests/
├── s5-runner.sh               # Installer scenarios, rootless (see Testing)
├── glyph-lint.sh              # Every printed character draws on tty1
└── tty-render.py              # Draws captured output through the console font
```

## Creating Releases

Tag a commit to create a GitHub release with the ISO:

```bash
git tag v1.0.0
git push origin v1.0.0
```
