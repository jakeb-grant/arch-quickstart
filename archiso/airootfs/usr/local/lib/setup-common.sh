# shellcheck shell=bash
# ==============================================================================
# Shared helpers for the arch-quickstart setup scripts
# ==============================================================================
# Sourced by nvidia-setup, intel-setup, amd-setup, bluetooth-setup,
# printer-setup, firewall-setup and dotfiles-setup. Not used by
# hyprland-install, which has its own gum-styled logging.
#
# Environment variables honored by these helpers:
#   CHROOT_TARGET - Target mount point (e.g., "/mnt") for installer mode
#   CHROOT_USER   - Username to configure on the target system
#
# ==============================================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
header() { echo -e "\n${CYAN}=== $1 ===${NC}\n"; }

# =============================================================================
# Chroot-aware helpers
# =============================================================================

# Run a command - either directly with sudo, or via arch-chroot
run_cmd() {
    if [[ -n "$CHROOT_TARGET" ]]; then
        arch-chroot "$CHROOT_TARGET" "$@"
    else
        sudo "$@"
    fi
}

# Install packages
pkg_install() {
    run_cmd pacman -S --needed --noconfirm "$@"
}

# Enable a systemd service
svc_enable() {
    run_cmd systemctl enable "$@"
}

# Start a systemd service (only in non-chroot mode)
svc_start() {
    if [[ -z "$CHROOT_TARGET" ]]; then
        sudo systemctl start "$@"
    fi
}

# Get the correct file path (prefixed with CHROOT_TARGET if set)
target_path() {
    echo "${CHROOT_TARGET}$1"
}

is_offline_mode() {
    # Check if running in offline mode (local repo, no internet mirrors)
    local conf
    conf="$(target_path /etc/pacman.conf)"
    grep -q "Server = file:///opt/offline-repo" "$conf" 2>/dev/null
}

# Get the user's home directory path
get_user_home() {
    if [[ -n "$CHROOT_USER" ]]; then
        echo "${CHROOT_TARGET}/home/$CHROOT_USER"
    elif [[ -n "$SUDO_USER" ]]; then
        echo "/home/$SUDO_USER"
    else
        echo "$HOME"
    fi
}

# Get the username being configured
get_target_user() {
    if [[ -n "$CHROOT_USER" ]]; then
        echo "$CHROOT_USER"
    elif [[ -n "$SUDO_USER" ]]; then
        echo "$SUDO_USER"
    else
        whoami
    fi
}

# =============================================================================
# AUR helpers
# =============================================================================

# Check if an AUR helper is available
get_aur_helper() {
    if [[ -n "$CHROOT_TARGET" ]]; then
        if arch-chroot "$CHROOT_TARGET" which paru &>/dev/null 2>&1; then
            echo "paru"
        elif arch-chroot "$CHROOT_TARGET" which yay &>/dev/null 2>&1; then
            echo "yay"
        fi
    else
        if command -v paru &>/dev/null; then
            echo "paru"
        elif command -v yay &>/dev/null; then
            echo "yay"
        fi
    fi
}

# Install AUR packages (handles offline vs online mode)
# Usage: aur_install <package1> <package2> ...
aur_install() {
    local packages=("$@")

    if is_offline_mode; then
        # Offline mode: packages are pre-built in offline repo, use pacman
        info "Installing from offline repository..."
        pkg_install "${packages[@]}"
    else
        # Online mode: need AUR helper
        local aur_helper
        aur_helper=$(get_aur_helper)

        if [[ -z "$aur_helper" ]]; then
            echo ""
            error "No AUR helper found (paru or yay required)"
        fi

        info "Installing via $aur_helper..."
        if [[ -n "$CHROOT_TARGET" ]]; then
            # In chroot: need to run as non-root user
            if [[ -z "$CHROOT_USER" ]]; then
                error "CHROOT_USER not set - cannot install AUR packages in chroot"
            fi
            arch-chroot "$CHROOT_TARGET" sudo -u "$CHROOT_USER" $aur_helper -S --noconfirm --needed "${packages[@]}"
        else
            # Normal system: check if running as root
            if [[ $EUID -eq 0 ]]; then
                # Running as root (via sudo), get the original user
                if [[ -n "$SUDO_USER" ]]; then
                    sudo -u "$SUDO_USER" $aur_helper -S --noconfirm --needed "${packages[@]}"
                else
                    error "Cannot install AUR packages as root. Run the setup script with sudo as a normal user."
                fi
            else
                $aur_helper -S --noconfirm --needed "${packages[@]}"
            fi
        fi
    fi
}

# =============================================================================
# GPU detection
# =============================================================================

# Populate DETECTED_NVIDIA / DETECTED_INTEL / DETECTED_AMD from lspci.
# Callers skip this when the installer pre-detected GPUs via environment.
# shellcheck disable=SC2034  # globals consumed by the sourcing scripts
detect_gpus() {
    local all_gpus
    all_gpus=$(lspci | grep -iE 'vga|3d|display' || true)
    DETECTED_NVIDIA=$(echo "$all_gpus" | grep -i 'nvidia' | head -1 || true)
    DETECTED_INTEL=$(echo "$all_gpus" | grep -iE 'intel.*(graphics|hd|uhd|iris|xe|arc)' | head -1 || true)
    # Word boundaries required: bare 'ati' matches "VGA compATIble controller"
    DETECTED_AMD=$(echo "$all_gpus" | grep -iE '\b(amd|radeon|ati)\b' | head -1 || true)
}

# Heuristic: AMD APUs are branded "Radeon Graphics" (no RX/Pro model number)
# or show their die codename; discrete cards carry RX/Pro model numbers.
# Usage: amd_is_apu "$DETECTED_AMD"
amd_is_apu() {
    echo "$1" | grep -qiE 'Radeon Graphics$|Ryzen.*Radeon|Renoir|Cezanne|Barcelo|Phoenix|Rembrandt|Lucienne|Mendocino'
}

# =============================================================================
# Package repository preparation
# =============================================================================

# Offline mode: the local repo is complete and static, so skip the sync.
# Online mode: make sure multilib is enabled (for lib32-* packages), then
# sync and upgrade so the new driver matches the running kernel.
ensure_multilib_and_sync() {
    if is_offline_mode; then
        info "Offline mode detected - using local package repository"
        info "Skipping database sync (packages already available locally)"
        return 0
    fi

    local pacman_conf
    pacman_conf="$(target_path /etc/pacman.conf)"
    if ! grep -q "^\[multilib\]" "$pacman_conf"; then
        warn "Multilib repository is not enabled!"
        info "Enabling multilib repository for 32-bit support..."

        # Enable multilib by uncommenting the section
        sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' "$pacman_conf"

        # Verify it was enabled
        if ! grep -q "^\[multilib\]" "$pacman_conf"; then
            warn "Could not auto-enable multilib. Adding it manually..."
            echo -e "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist" >> "$pacman_conf"
        fi

        info "Multilib repository enabled"
    fi

    info "Updating package database..."
    run_cmd pacman -Syu --noconfirm
}

# =============================================================================
# Hyprland configuration
# =============================================================================

# Append a block of settings (from stdin) to the user's hyprland.conf, once.
# Usage: append_hyprland_env "<marker string>" <<'EOF' ... EOF
# Skips with a warning if the marker is already in the file; if the file
# doesn't exist, prints the block for the user to add manually.
append_hyprland_env() {
    local marker="$1" conf
    conf="$(get_user_home)/.config/hypr/hyprland.conf"

    if [[ ! -f "$conf" ]]; then
        warn "Hyprland config not found at $conf"
        echo ""
        warn "Add these lines manually to your hyprland.conf:"
        echo ""
        sed 's/^/  /'
        return 0
    fi

    if grep -q "$marker" "$conf"; then
        warn "$marker already present in hyprland.conf"
        warn "Skipping to avoid duplicates. Please verify configuration manually."
        return 0
    fi

    info "Adding $marker to hyprland.conf..."
    cat >> "$conf"
    info "Environment variables added to hyprland.conf"
}
