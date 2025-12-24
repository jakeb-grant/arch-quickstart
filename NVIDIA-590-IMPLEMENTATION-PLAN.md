# NVIDIA Driver 590 Transition - Implementation Plan

## Overview

With NVIDIA driver version 590, Pascal (GTX 10xx) and older GPUs are no longer supported by the mainline driver. This plan implements support for both modern (Turing+) and legacy GPUs in the arch-quickstart ISO.

### Key Changes
- `nvidia` → `nvidia-open` (Arch repo transition)
- `nvidia-dkms` → `nvidia-open-dkms` (Arch repo transition)
- Pascal/Maxwell/older → requires `nvidia-580xx-dkms` from AUR

---

## File Changes Summary

| File | Action |
|------|--------|
| `archiso/airootfs/root/setup-aur-packages.x86_64` | **CREATE** - New file for setup-script AUR packages |
| `archiso/airootfs/root/setup-packages.x86_64` | **MODIFY** - Remove deprecated `nvidia-dkms` |
| `.github/workflows/build-iso.yml` | **MODIFY** - Build packages from new list |
| `archiso/airootfs/usr/local/bin/nvidia-setup` | **MODIFY** - New driver logic + AUR handling |

---

## Step 1: Create `setup-aur-packages.x86_64`

**File:** `archiso/airootfs/root/setup-aur-packages.x86_64`

```
# Setup script AUR packages
# These packages are built during ISO creation and included in the offline repo,
# but are NOT automatically installed. They are installed on-demand by setup
# scripts (nvidia-setup, etc.) based on hardware detection.
#
# This separation prevents conflicts (e.g., nvidia-580xx vs nvidia-open).

# =============================================================================
# GPU - NVIDIA Legacy (Pascal GTX 10xx, Maxwell GTX 9xx, and older)
# =============================================================================
# Required for GPUs no longer supported by driver 590+
nvidia-580xx-dkms
nvidia-580xx-utils
nvidia-580xx-settings
lib32-nvidia-580xx-utils
```

**Purpose:** These packages are:
- Built during ISO creation (by yay in the build workflow)
- Included in `/opt/offline-repo/`
- NOT installed by `install_aur_packages()`
- Installed on-demand by `nvidia-setup` when a legacy GPU is detected

---

## Step 2: Update `setup-packages.x86_64`

**File:** `archiso/airootfs/root/setup-packages.x86_64`

**Changes:**
```diff
 # =============================================================================
 # GPU - NVIDIA
 # =============================================================================
-# Proprietary driver (Pascal and older)
-nvidia-dkms
-# Open kernel modules (Turing and newer - required for Blackwell)
+# Open kernel modules (Turing and newer)
+# Note: Driver 590+ only supports Turing (GTX 16xx, RTX 20xx) and newer
+# Legacy GPUs (Pascal GTX 10xx, Maxwell GTX 9xx, older) require nvidia-580xx
+# from AUR - see setup-aur-packages.x86_64
 nvidia-open-dkms
 # Userspace utilities
 nvidia-utils
 lib32-nvidia-utils
```

**Rationale:**
- `nvidia-dkms` is deprecated/removed in Arch with driver 590
- Only `nvidia-open-dkms` remains for modern GPUs
- Legacy support moves to AUR packages

---

## Step 3: Update `.github/workflows/build-iso.yml`

**File:** `.github/workflows/build-iso.yml`

**Location:** Inside the "Build offline package repository" step (~line 218-243)

**Changes:**

### 3a. Add setup-aur-packages to the build process

After building regular AUR packages, add:

```bash
# Build setup-script AUR packages (not auto-installed, used by nvidia-setup etc.)
echo ""
echo "Building setup-script AUR packages..."
SETUP_AUR_FILE="/workspace/archiso/airootfs/root/setup-aur-packages.x86_64"
if [[ -f "$SETUP_AUR_FILE" ]]; then
    mapfile -t SETUP_AUR_PACKAGES < <(grep -v "^#" "$SETUP_AUR_FILE" | grep -v "^$")
    if [[ ${#SETUP_AUR_PACKAGES[@]} -gt 0 ]]; then
        echo "::group::Building setup AUR packages with yay"
        su -s /bin/bash builder -c "yay -S --noconfirm --needed ${SETUP_AUR_PACKAGES[*]}"
        echo "::endgroup::"

        # Copy built packages to offline repo
        cp /home/builder/.cache/yay/*/*.pkg.tar.zst /tmp/offline-repo/ 2>/dev/null || true
        cp -n /var/cache/pacman/pkg/*.pkg.tar.zst /tmp/offline-repo/ 2>/dev/null || true
    fi
fi
```

### 3b. Add setup-aur-packages to validation

In the validation section (~line 259-277), add:

```bash
# Validate setup-aur-packages
if [[ -f /workspace/archiso/airootfs/root/setup-aur-packages.x86_64 ]]; then
    while IFS= read -r pkg || [[ -n "$pkg" ]]; do
      [[ -z "$pkg" ]] || [[ "$pkg" =~ ^# ]] && continue
      echo "$REPO_PACKAGES" | grep -qx "$pkg" || MISSING="$MISSING $pkg"
    done < /workspace/archiso/airootfs/root/setup-aur-packages.x86_64
fi
```

---

## Step 4: Update `nvidia-setup` Script

**File:** `archiso/airootfs/usr/local/bin/nvidia-setup`

### 4a. Add new helper function for AUR package detection

After `is_offline_mode()` function (~line 62), add:

```bash
# Check if an AUR helper is available
get_aur_helper() {
    if [[ -n "$CHROOT_TARGET" ]]; then
        if run_cmd which paru &>/dev/null; then
            echo "paru"
        elif run_cmd which yay &>/dev/null; then
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
            error "No AUR helper found (paru or yay required for legacy NVIDIA drivers)"
        fi

        info "Installing via $aur_helper..."
        if [[ -n "$CHROOT_TARGET" ]]; then
            # In chroot: need to run as non-root user
            if [[ -z "$CHROOT_USER" ]]; then
                error "CHROOT_USER not set - cannot install AUR packages in chroot"
            fi
            arch-chroot "$CHROOT_TARGET" sudo -u "$CHROOT_USER" $aur_helper -S --noconfirm --needed "${packages[@]}"
        else
            # Normal system: run as current user (should not be root)
            if [[ $EUID -eq 0 ]]; then
                error "Cannot install AUR packages as root. Run nvidia-setup as a normal user with sudo."
            fi
            $aur_helper -S --noconfirm --needed "${packages[@]}"
        fi
    fi
}
```

### 4b. Update GPU generation constants and detection

Replace the driver selection section (~lines 138-188) with:

```bash
# ==============================================================================
# Driver Selection
# ==============================================================================
header "Selecting Driver Package"

# GPU Generation Detection
#
# NVIDIA Driver 590+ Support Matrix:
#   - Turing and newer (GTX 16xx, RTX 20xx+): nvidia-open-dkms (official repo)
#   - Pascal and older (GTX 10xx, 9xx, etc.): nvidia-580xx-dkms (AUR - legacy)
#
# The open kernel modules are now the default for supported GPUs.

NVIDIA_DRIVER_PACKAGE=""
NVIDIA_UTILS_PACKAGE=""
LEGACY_GPU=false

# Check for Turing and newer (supported by driver 590+)
if echo "$DETECTED_NVIDIA" | grep -qiE 'RTX.*(50[0-9][0-9]|5090|5080|5070|5060|5050)'; then
    # Blackwell (50xx)
    NVIDIA_DRIVER_PACKAGE="nvidia-open-dkms"
    NVIDIA_UTILS_PACKAGE="nvidia-utils"
    info "Detected Blackwell (50xx) GPU - nvidia-open-dkms"
elif echo "$DETECTED_NVIDIA" | grep -qiE 'RTX.*(40[0-9][0-9]|4090|4080|4070|4060|4050)'; then
    # Ada Lovelace (40xx)
    NVIDIA_DRIVER_PACKAGE="nvidia-open-dkms"
    NVIDIA_UTILS_PACKAGE="nvidia-utils"
    info "Detected Ada Lovelace (40xx) GPU - nvidia-open-dkms"
elif echo "$DETECTED_NVIDIA" | grep -qiE 'RTX.*(30[0-9][0-9]|3090|3080|3070|3060|3050)'; then
    # Ampere (30xx)
    NVIDIA_DRIVER_PACKAGE="nvidia-open-dkms"
    NVIDIA_UTILS_PACKAGE="nvidia-utils"
    info "Detected Ampere (30xx) GPU - nvidia-open-dkms"
elif echo "$DETECTED_NVIDIA" | grep -qiE 'RTX.*(20[0-9][0-9]|2080|2070|2060)|GTX.*(16[0-9][0-9]|1660|1650|1630)'; then
    # Turing (20xx and GTX 16xx)
    NVIDIA_DRIVER_PACKAGE="nvidia-open-dkms"
    NVIDIA_UTILS_PACKAGE="nvidia-utils"
    info "Detected Turing (20xx/16xx) GPU - nvidia-open-dkms"
elif echo "$DETECTED_NVIDIA" | grep -qiE 'GTX.*(10[0-9][0-9]|1080|1070|1060|1050|1030)|GT.?10[0-9][0-9]'; then
    # Pascal (10xx) - LEGACY
    NVIDIA_DRIVER_PACKAGE="nvidia-580xx-dkms"
    NVIDIA_UTILS_PACKAGE="nvidia-580xx-utils"
    LEGACY_GPU=true
    warn "Detected Pascal (10xx) GPU - LEGACY driver required"
elif echo "$DETECTED_NVIDIA" | grep -qiE 'GTX.*(9[0-9][0-9]|980|970|960|950)|GT.?9[0-9][0-9]'; then
    # Maxwell (9xx) - LEGACY
    NVIDIA_DRIVER_PACKAGE="nvidia-580xx-dkms"
    NVIDIA_UTILS_PACKAGE="nvidia-580xx-utils"
    LEGACY_GPU=true
    warn "Detected Maxwell (9xx) GPU - LEGACY driver required"
elif echo "$DETECTED_NVIDIA" | grep -qiE 'RTX'; then
    # Unknown RTX - assume modern
    NVIDIA_DRIVER_PACKAGE="nvidia-open-dkms"
    NVIDIA_UTILS_PACKAGE="nvidia-utils"
    info "Detected RTX GPU - nvidia-open-dkms"
else
    # Older/unrecognized - LEGACY
    NVIDIA_DRIVER_PACKAGE="nvidia-580xx-dkms"
    NVIDIA_UTILS_PACKAGE="nvidia-580xx-utils"
    LEGACY_GPU=true
    warn "Detected older/unrecognized GPU - LEGACY driver required"
fi

# Display legacy GPU warning
if [[ "$LEGACY_GPU" == "true" ]]; then
    echo ""
    warn "════════════════════════════════════════════════════════════════"
    warn "  LEGACY GPU DETECTED"
    warn "════════════════════════════════════════════════════════════════"
    echo ""
    echo "  NVIDIA driver 590+ no longer supports your GPU."
    echo "  The legacy nvidia-580xx driver from AUR will be installed."
    echo ""
    echo "  GPU: $(echo "$DETECTED_NVIDIA" | sed 's/.*: //')"
    echo "  Driver: $NVIDIA_DRIVER_PACKAGE (AUR)"
    echo ""

    # Check requirements for online mode
    if ! is_offline_mode; then
        AUR_HELPER=$(get_aur_helper)
        if [[ -z "$AUR_HELPER" ]]; then
            echo ""
            error "No AUR helper found!"
            echo ""
            echo "  Legacy NVIDIA drivers require an AUR helper (paru or yay)."
            echo ""
            echo "  Install one first:"
            echo "    paru:  sudo pacman -S paru"
            echo "    yay:   sudo pacman -S yay"
            echo ""
            echo "  Then run nvidia-setup again."
            exit 1
        fi
        info "AUR helper found: $AUR_HELPER"
    fi
    warn "════════════════════════════════════════════════════════════════"
    echo ""
fi
```

### 4c. Update package installation section

Replace the package installation section (~lines 293-309) with:

```bash
# Build package lists based on GPU type
if [[ "$LEGACY_GPU" == "true" ]]; then
    # Legacy GPU: AUR packages
    DRIVER_PACKAGES=(
        "${NVIDIA_DRIVER_PACKAGE}"      # nvidia-580xx-dkms
        "${NVIDIA_UTILS_PACKAGE}"       # nvidia-580xx-utils
        "lib32-${NVIDIA_UTILS_PACKAGE}" # lib32-nvidia-580xx-utils
        "nvidia-580xx-settings"         # GUI configuration tool
    )

    OFFICIAL_PACKAGES=(
        "${KERNEL_HEADERS}"
        "egl-wayland"
        "qt5-wayland"
        "qt6-wayland"
    )

    # Install official packages first
    info "Installing official packages..."
    echo "  Packages: ${OFFICIAL_PACKAGES[*]}"
    pkg_install "${OFFICIAL_PACKAGES[@]}"

    # Install AUR packages (handles offline vs online)
    info "Installing legacy NVIDIA driver packages..."
    echo "  Packages: ${DRIVER_PACKAGES[*]}"
    aur_install "${DRIVER_PACKAGES[@]}"
else
    # Modern GPU: all official packages
    PACKAGES_TO_INSTALL=(
        "${KERNEL_HEADERS}"
        "${NVIDIA_DRIVER_PACKAGE}"      # nvidia-open-dkms
        "nvidia-utils"
        "lib32-nvidia-utils"
        "egl-wayland"
        "libva-nvidia-driver"           # VA-API (not available for legacy)
        "nvidia-settings"
        "qt5-wayland"
        "qt6-wayland"
    )

    info "Installing NVIDIA packages..."
    echo "  Packages: ${PACKAGES_TO_INSTALL[*]}"
    pkg_install "${PACKAGES_TO_INSTALL[@]}"
fi
```

### 4d. Update installation summary

Update the summary section (~lines 221-248) to reflect the new packages:

```bash
# ==============================================================================
# Summary and Confirmation
# ==============================================================================
header "Installation Summary"

echo "Hardware detected:"
echo "  - NVIDIA GPU: $(echo "$DETECTED_NVIDIA" | sed 's/.*: //')"
if [[ -n "$HYBRID_TYPE" ]]; then
    if [[ "$HYBRID_TYPE" == "intel" ]]; then
        echo "  - Intel iGPU: $(echo "$DETECTED_INTEL" | sed 's/.*: //')"
    else
        echo "  - AMD iGPU: $(echo "$DETECTED_AMD" | sed 's/.*: //')"
    fi
    echo "  - Setup type: Hybrid (PRIME offloading)"
else
    echo "  - Setup type: Dedicated NVIDIA"
fi
echo ""

if [[ "$LEGACY_GPU" == "true" ]]; then
    echo "Driver information:"
    echo "  - Status: LEGACY GPU (not supported by driver 590+)"
    echo "  - Driver: $NVIDIA_DRIVER_PACKAGE (AUR)"
    echo "  - Utils: $NVIDIA_UTILS_PACKAGE, lib32-$NVIDIA_UTILS_PACKAGE"
    if is_offline_mode; then
        echo "  - Source: Offline repository (pre-built)"
    else
        echo "  - Source: AUR via $(get_aur_helper)"
    fi
else
    echo "Packages to install:"
    echo "  - Driver: $NVIDIA_DRIVER_PACKAGE"
    echo "  - Headers: $KERNEL_HEADERS"
    echo "  - Utils: nvidia-utils, lib32-nvidia-utils"
    echo "  - Wayland: egl-wayland, libva-nvidia-driver"
fi
echo ""

echo "System modifications:"
echo "  - /etc/modprobe.d/nvidia.conf (DRM modeset)"
echo "  - /etc/mkinitcpio.conf (early KMS modules)"
echo "  - ~/.config/hypr/hyprland.conf (environment variables)"
if [[ -n "$HYBRID_TYPE" ]]; then
    echo "  - /usr/local/bin/prime-run (PRIME wrapper script)"
fi
```

---

## Step 5: Validation Script Update (Optional)

**File:** `.github/scripts/validate-packages.sh`

Add validation for the new `setup-aur-packages.x86_64` file to ensure packages exist in AUR.

---

## Implementation Order

1. **Create `setup-aur-packages.x86_64`** - New file with legacy nvidia packages
2. **Update `setup-packages.x86_64`** - Remove deprecated `nvidia-dkms`
3. **Update `build-iso.yml`** - Build and validate new package list
4. **Update `nvidia-setup`** - New driver logic and AUR handling
5. **Test offline mode** - Verify legacy drivers install from offline repo
6. **Test online mode** - Verify legacy drivers install via AUR helper

---

## Testing Matrix

| Scenario | GPU | Mode | Expected Behavior |
|----------|-----|------|-------------------|
| Install | Turing+ (RTX 30xx) | Offline | `pacman -S nvidia-open-dkms` |
| Install | Turing+ (RTX 30xx) | Online | `pacman -S nvidia-open-dkms` |
| Install | Pascal (GTX 1080) | Offline | `pacman -S nvidia-580xx-dkms` (from offline repo) |
| Install | Pascal (GTX 1080) | Online | `yay -S nvidia-580xx-dkms` |
| Post-install | Turing+ | - | `pacman -S nvidia-open-dkms` |
| Post-install | Pascal | - | `yay -S nvidia-580xx-dkms` (requires AUR helper) |

---

## Rollback Plan

If issues arise:
1. Revert `setup-packages.x86_64` to include `nvidia-dkms`
2. Remove `setup-aur-packages.x86_64`
3. Revert `nvidia-setup` to previous version
4. Revert `build-iso.yml` changes

---

## Notes

- **libva-nvidia-driver** is NOT available for nvidia-580xx (legacy VA-API support limited)
- **nvidia-settings** vs **nvidia-580xx-settings** - different packages for each driver branch
- Legacy driver users may experience reduced feature support compared to modern drivers
- The nvidia-580xx packages in AUR are community-maintained
