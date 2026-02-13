#!/bin/bash
# =============================================================================
# Package Validation Script
# =============================================================================
# Validates that all packages in the package lists exist in official repos or AUR.
# Used by both online and offline ISO builds to catch invalid packages early.
#
# Usage:
#   validate-packages.sh [OPTIONS]
#
# Options:
#   --include-setup-packages    Also validate setup-packages.x86_64 (for offline build)
#   --base-path PATH            Base path to archiso directory (default: current dir)
#
# Requirements:
#   - pacman with synced databases (pacman -Sy)
#   - multilib repository enabled for lib32 packages
#   - curl and jq for AUR validation
# =============================================================================

set -e

# Defaults
INCLUDE_SETUP_PACKAGES=false
BASE_PATH="."

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --include-setup-packages)
            INCLUDE_SETUP_PACKAGES=true
            shift
            ;;
        --base-path)
            BASE_PATH="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# =============================================================================
# Ensure multilib is enabled and databases are synced
# =============================================================================
echo "Ensuring multilib repository is enabled..."
if ! grep -q '^\[multilib\]' /etc/pacman.conf; then
    echo -e '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist' >> /etc/pacman.conf
fi

echo "Syncing package databases..."
pacman -Sy

# =============================================================================
# Validate official packages
# =============================================================================
INVALID_PACKAGES=""
INVALID_AUR=""

echo ""
echo "Validating live ISO packages (packages.x86_64)..."
while IFS= read -r package; do
    [[ -z "$package" ]] || [[ "$package" =~ ^# ]] && continue
    if ! pacman -Si "$package" &>/dev/null; then
        echo "❌ Invalid: $package"
        INVALID_PACKAGES="$INVALID_PACKAGES $package"
    fi
done < "$BASE_PATH/archiso/packages.x86_64"

echo ""
echo "Validating target system packages (target-packages.x86_64)..."
while IFS= read -r package; do
    [[ -z "$package" ]] || [[ "$package" =~ ^# ]] && continue
    if ! pacman -Si "$package" &>/dev/null; then
        echo "❌ Invalid: $package"
        INVALID_PACKAGES="$INVALID_PACKAGES $package"
    fi
done < "$BASE_PATH/archiso/airootfs/root/target-packages.x86_64"

if [[ "$INCLUDE_SETUP_PACKAGES" == "true" ]]; then
    echo ""
    echo "Validating setup script packages (setup-packages.x86_64)..."
    while IFS= read -r package; do
        [[ -z "$package" ]] || [[ "$package" =~ ^# ]] && continue
        if ! pacman -Si "$package" &>/dev/null; then
            echo "❌ Invalid: $package"
            INVALID_PACKAGES="$INVALID_PACKAGES $package"
        fi
    done < "$BASE_PATH/archiso/airootfs/root/setup-packages.x86_64"
fi

if [[ -n "$INVALID_PACKAGES" ]]; then
    echo ""
    echo "ERROR: The following official packages were not found in repositories:"
    echo "$INVALID_PACKAGES"
else
    echo ""
    echo "✓ All official packages validated"
fi

# =============================================================================
# Validate AUR packages
# =============================================================================
echo ""
echo "Validating AUR packages (aur-packages.x86_64)..."

AUR_PACKAGES=""
while IFS= read -r package; do
    [[ -z "$package" ]] || [[ "$package" =~ ^# ]] && continue
    AUR_PACKAGES="$AUR_PACKAGES $package"
done < "$BASE_PATH/archiso/airootfs/root/aur-packages.x86_64"

# Also validate setup-aur-packages if it exists (legacy NVIDIA drivers, etc.)
SETUP_AUR_FILE="$BASE_PATH/archiso/airootfs/root/setup-aur-packages.x86_64"
if [[ -f "$SETUP_AUR_FILE" ]]; then
    echo "Validating setup-script AUR packages (setup-aur-packages.x86_64)..."
    while IFS= read -r package; do
        [[ -z "$package" ]] || [[ "$package" =~ ^# ]] && continue
        AUR_PACKAGES="$AUR_PACKAGES $package"
    done < "$SETUP_AUR_FILE"
fi

if [[ -n "$AUR_PACKAGES" ]]; then
    # Build query string for AUR RPC
    QUERY_ARGS=""
    for pkg in $AUR_PACKAGES; do
        QUERY_ARGS="${QUERY_ARGS}&arg[]=${pkg}"
    done
    QUERY_ARGS="${QUERY_ARGS:1}"  # Remove leading &

    # Query AUR API
    AUR_RESPONSE=$(curl -s "https://aur.archlinux.org/rpc/v5/info?${QUERY_ARGS}")

    if ! echo "$AUR_RESPONSE" | jq -e '.type == "multiinfo"' > /dev/null 2>&1; then
        echo "ERROR: Failed to query AUR API"
        echo "$AUR_RESPONSE"
        exit 1
    fi

    FOUND_PACKAGES=$(echo "$AUR_RESPONSE" | jq -r '.results[].Name')

    for pkg in $AUR_PACKAGES; do
        if ! echo "$FOUND_PACKAGES" | grep -qx "$pkg"; then
            echo "❌ Invalid AUR package: $pkg"
            INVALID_AUR="$INVALID_AUR $pkg"
        fi
    done

    if [[ -n "$INVALID_AUR" ]]; then
        echo ""
        echo "ERROR: The following AUR packages were not found:"
        echo "$INVALID_AUR"
    else
        echo "✓ All AUR packages validated"
    fi
else
    echo "No AUR packages to validate"
fi

# =============================================================================
# Final summary
# =============================================================================
if [[ -n "$INVALID_PACKAGES" ]] || [[ -n "$INVALID_AUR" ]]; then
    echo ""
    echo "=========================================="
    echo "Package validation FAILED"
    echo "=========================================="
    exit 1
fi

echo ""
echo "=========================================="
echo "All package validation complete!"
echo "=========================================="
