#!/bin/bash
# =============================================================================
# Package Validation Script
# =============================================================================
# Validates the package lists that feed the ISO builds:
#   1. Every official-repo package exists (pacman -Si)
#   2. Every AUR package exists (RPC v5, POSTed in chunks)
#   3. No AUR-listed package actually lives in the official repos (misplaced)
#   4. No duplicates within a list or across the target-system lists
#   5. Binaries referenced by exec-once in the shipped Hyprland config resolve
#      to a listed package (requires a synced pacman files database)
#   6. Literal package names installed by the setup scripts are present in the
#      lists that feed the offline repository
#
# Usage:
#   validate-packages.sh [OPTIONS]
#
# Options:
#   --include-setup-packages    Also validate setup-packages.x86_64 (for offline build)
#   --base-path PATH            Base path to repo root (default: current dir)
#   --skip-sync                 Don't touch pacman.conf or sync databases
#                               (for local runs without root; uses existing DBs)
#
# Requirements:
#   - pacman with synced databases (pacman -Sy; pacman -Fy for check 5)
#   - multilib repository enabled for lib32 packages
#   - curl and jq for AUR validation
# =============================================================================

set -euo pipefail

# Defaults
INCLUDE_SETUP_PACKAGES=false
BASE_PATH="."
SKIP_SYNC=false

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
        --skip-sync)
            SKIP_SYNC=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

FAILURES=0
fail() { echo "❌ $*"; FAILURES=$((FAILURES + 1)); }
note() { echo "⚠️  $*"; }

# Same parsing as the installer's read_package_list(): strip comments
# (including inline), CR, and surrounding whitespace; drop blank lines.
read_package_list() {
    local file="$1" line
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}"
        line="${line//$'\r'/}"
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        if [[ -n "$line" ]]; then
            printf '%s\n' "$line"
        fi
    done < "$file"
}

LIVE_LIST="$BASE_PATH/archiso/packages.x86_64"
TARGET_LIST="$BASE_PATH/archiso/airootfs/root/target-packages.x86_64"
SETUP_LIST="$BASE_PATH/archiso/airootfs/root/setup-packages.x86_64"
AUR_LIST="$BASE_PATH/archiso/airootfs/root/aur-packages.x86_64"
SETUP_AUR_LIST="$BASE_PATH/archiso/airootfs/root/setup-aur-packages.x86_64"
SETUP_SCRIPTS_DIR="$BASE_PATH/archiso/airootfs/usr/local/bin"
HYPR_CONF_DIR="$BASE_PATH/archiso/airootfs/etc/skel/.config/hypr"

# Packages a setup script installs deliberately without shipping them in the
# offline repo (the script gates them behind an online check). See BACKLOG H6.
OFFLINE_REPO_EXEMPT="rocm-opencl-runtime rocm-hip-runtime"

# =============================================================================
# Ensure multilib is enabled and databases are synced
# =============================================================================
if [[ "$SKIP_SYNC" == "false" ]]; then
    echo "Ensuring multilib repository is enabled..."
    if ! grep -q '^\[multilib\]' /etc/pacman.conf; then
        echo -e '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist' >> /etc/pacman.conf
    fi

    echo "Syncing package databases..."
    pacman -Sy
    echo "Syncing files databases (for file-reference checks)..."
    pacman -Fy
fi

# =============================================================================
# Load all lists once
# =============================================================================
mapfile -t LIVE_PKGS < <(read_package_list "$LIVE_LIST")
mapfile -t TARGET_PKGS < <(read_package_list "$TARGET_LIST")
mapfile -t AUR_PKGS < <(read_package_list "$AUR_LIST")
SETUP_PKGS=()
if [[ -f "$SETUP_LIST" ]]; then
    mapfile -t SETUP_PKGS < <(read_package_list "$SETUP_LIST")
fi
SETUP_AUR_PKGS=()
if [[ -f "$SETUP_AUR_LIST" ]]; then
    mapfile -t SETUP_AUR_PKGS < <(read_package_list "$SETUP_AUR_LIST")
fi

# Everything that ends up in the offline repo / on the target system
TARGET_SYSTEM_PKGS=$(printf '%s\n' "${TARGET_PKGS[@]}" "${SETUP_PKGS[@]}" \
    "${AUR_PKGS[@]}" "${SETUP_AUR_PKGS[@]}")

in_target_system_lists() {
    grep -qx "$1" <<< "$TARGET_SYSTEM_PKGS"
}

# =============================================================================
# Check 1: official packages exist in the repos
# =============================================================================
validate_official_list() {
    local label="$1"; shift
    echo ""
    echo "Validating $label..."
    local package
    for package in "$@"; do
        if ! pacman -Si "$package" &>/dev/null; then
            fail "Not in official repos: $package ($label)"
        fi
    done
}

validate_official_list "live ISO packages (packages.x86_64)" "${LIVE_PKGS[@]}"
validate_official_list "target system packages (target-packages.x86_64)" "${TARGET_PKGS[@]}"
if [[ "$INCLUDE_SETUP_PACKAGES" == "true" ]]; then
    validate_official_list "setup script packages (setup-packages.x86_64)" "${SETUP_PKGS[@]}"
fi

# =============================================================================
# Check 2: AUR packages exist (chunked POST to RPC v5 - no URL-length limit,
# names URL-encoded by curl)
# =============================================================================
ALL_AUR_PKGS=("${AUR_PKGS[@]}" "${SETUP_AUR_PKGS[@]}")

echo ""
echo "Validating AUR packages (aur-packages.x86_64, setup-aur-packages.x86_64)..."
if [[ ${#ALL_AUR_PKGS[@]} -gt 0 ]]; then
    CHUNK_SIZE=100
    FOUND_AUR=""
    for ((i = 0; i < ${#ALL_AUR_PKGS[@]}; i += CHUNK_SIZE)); do
        CURL_ARGS=()
        for pkg in "${ALL_AUR_PKGS[@]:i:CHUNK_SIZE}"; do
            CURL_ARGS+=(--data-urlencode "arg[]=$pkg")
        done
        RESPONSE=$(curl -sf --retry 3 --retry-delay 2 "${CURL_ARGS[@]}" "https://aur.archlinux.org/rpc/v5/info") || {
            echo "ERROR: AUR RPC request failed"
            exit 1
        }
        if ! jq -e '.type == "multiinfo"' <<< "$RESPONSE" > /dev/null; then
            echo "ERROR: Unexpected AUR RPC response:"
            echo "$RESPONSE"
            exit 1
        fi
        FOUND_AUR+=$(jq -r '.results[].Name' <<< "$RESPONSE")$'\n'
    done

    for pkg in "${ALL_AUR_PKGS[@]}"; do
        if ! grep -qx "$pkg" <<< "$FOUND_AUR"; then
            fail "Not in the AUR: $pkg"
        fi
        # A package that moved into the official repos must move lists too,
        # or the AUR build step will fail once the AUR entry is dropped
        if pacman -Si "$pkg" &>/dev/null; then
            fail "AUR-listed package is in the official repos: $pkg (move it to target-packages/setup-packages)"
        fi
    done
else
    echo "No AUR packages to validate"
fi

# =============================================================================
# Check 3: duplicates - within any list, and across the target-system lists
# (live ISO vs target overlap is legitimate: they are different systems)
# =============================================================================
echo ""
echo "Checking for duplicate entries..."
check_dupes_within() {
    local label="$1"; shift
    local dupes
    dupes=$(printf '%s\n' "$@" | sort | uniq -d)
    if [[ -n "$dupes" ]]; then
        fail "Duplicate entries in $label: $(tr '\n' ' ' <<< "$dupes")"
    fi
}
[[ ${#LIVE_PKGS[@]} -gt 0 ]] && check_dupes_within "packages.x86_64" "${LIVE_PKGS[@]}"
check_dupes_within "the target-system lists (target/setup/aur/setup-aur)" \
    "${TARGET_PKGS[@]}" "${SETUP_PKGS[@]}" "${AUR_PKGS[@]}" "${SETUP_AUR_PKGS[@]}"

# =============================================================================
# Check 4: exec-once binaries in the shipped Hyprland config resolve to a
# listed package (catches autostarting a program nothing installs)
# =============================================================================
echo ""
echo "Checking exec-once references in shipped Hyprland config..."
if [[ -z "$(pacman -Fq /usr/bin/bash 2>/dev/null)" ]]; then
    note "pacman files database not synced (pacman -Fy) - skipping exec-once checks"
else
    while IFS= read -r cmd; do
        # First word of the command line; env-var assignments have no path
        cmd="${cmd%% *}"
        [[ "$cmd" == *=* || -z "$cmd" ]] && continue
        if [[ "$cmd" == /* ]]; then
            path="$cmd"
        else
            path="/usr/bin/$cmd"
        fi
        # pacman -Fq prints "repo/package" for each owner, or nothing
        owner=$(pacman -Fq "$path" 2>/dev/null | head -1)
        owner="${owner##*/}"
        if [[ -z "$owner" ]]; then
            note "exec-once target '$cmd' not found in any official package (AUR- or dotfiles-provided?)"
        elif ! in_target_system_lists "$owner"; then
            fail "exec-once runs '$cmd' but its package '$owner' is in no package list"
        fi
    done < <(sed -n 's/^[[:space:]]*exec-once[[:space:]]*=[[:space:]]*//p' "$HYPR_CONF_DIR"/*.conf)
fi

# =============================================================================
# Check 5: literal package names in the setup scripts are available offline
# (in some list that feeds the offline repo), unless explicitly exempt
# =============================================================================
echo ""
echo "Checking packages referenced by setup scripts..."
SETUP_SCRIPTS=(nvidia-setup intel-setup amd-setup bluetooth-setup printer-setup firewall-setup dotfiles-setup)
for script in "${SETUP_SCRIPTS[@]}"; do
    [[ -f "$SETUP_SCRIPTS_DIR/$script" ]] || continue
    # Extract literal tokens from PACKAGES-style array definitions and from
    # direct pkg_install/aur_install arguments; skip anything with a variable
    while IFS= read -r pkg; do
        [[ "$pkg" == *'$'* || -z "$pkg" ]] && continue
        if grep -qw "$pkg" <<< "$OFFLINE_REPO_EXEMPT"; then
            continue
        fi
        if ! in_target_system_lists "$pkg"; then
            fail "$script installs '$pkg' but it is in no package list (offline install would fail)"
        fi
    done < <(awk '
        /^[[:space:]]*[A-Z_]*PACKAGES[A-Z_]*\+?=\(/ { in_array = 1 }
        in_array {
            line = $0
            sub(/#.*/, "", line)
            n = split(line, tokens)
            for (t = 1; t <= n; t++) {
                tok = tokens[t]
                gsub(/["()]/, "", tok)
                sub(/^[A-Z_]+\+?=/, "", tok)
                if (tok ~ /^[a-z0-9][a-z0-9._+-]*$/) print tok
            }
            if (line ~ /\)/) in_array = 0
            next
        }
        /^[[:space:]]*(pkg_install|aur_install)[[:space:]]/ {
            for (t = 2; t <= NF; t++) {
                tok = $t
                gsub(/"/, "", tok)
                if (tok ~ /^[a-z0-9][a-z0-9._+-]*$/) print tok
            }
        }
    ' "$SETUP_SCRIPTS_DIR/$script" | sort -u)
done

# =============================================================================
# Final summary
# =============================================================================
echo ""
if [[ "$FAILURES" -gt 0 ]]; then
    echo "=========================================="
    echo "Package validation FAILED ($FAILURES problem(s))"
    echo "=========================================="
    exit 1
fi

echo "=========================================="
echo "All package validation complete!"
echo "=========================================="
