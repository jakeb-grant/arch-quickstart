# Offline Installation Support Plan

## Overview

This plan outlines how to add offline installation support to the arch-quickstart ISO by pre-building all packages (official + AUR) and including them as a local repository on the ISO.

## Research Summary

Based on the [ArchWiki Archiso documentation](https://wiki.archlinux.org/title/Archiso):

1. **Custom Local Repository**: archiso supports adding custom local repositories via `pacman.conf`
2. **AUR Packages**: Must be built with `makepkg` and added to the local repo with `repo-add`
3. **Repository Location**: Must be accessible during build (e.g., `/tmp` or within airootfs)
4. **Configuration**: Add repo to `pacman.conf` with `SigLevel = Optional TrustAll`

## Current State

| Component | Count | Location |
|-----------|-------|----------|
| Live ISO packages | ~91 | `archiso/packages.x86_64` |
| Target system packages | ~121 | `archiso/airootfs/root/target-packages.x86_64` |
| AUR packages | ~13 | `archiso/airootfs/root/aur-packages.x86_64` |

**Current installer behavior:**
- Uses `pacstrap` to download packages from online mirrors during installation
- Installs `yay-bin` via `makepkg`, then uses `yay` to install AUR packages

## Proposed Architecture

```
archiso/
├── airootfs/
│   ├── opt/
│   │   └── offline-repo/           # NEW: Local package repository
│   │       ├── offline.db.tar.zst  # Repository database
│   │       ├── offline.files.tar.zst
│   │       └── *.pkg.tar.zst       # All packages (official + AUR)
│   ├── etc/
│   │   └── pacman.d/
│   │       └── offline-pacman.conf # NEW: Offline pacman config
│   └── root/
│       └── ...
└── pacman.conf                     # Modified for build process
```

## Implementation Steps

### Phase 1: Build System Changes (GitHub Actions)

#### Step 1.1: Create AUR Build Environment
Add a new build stage that creates a non-root user for building AUR packages:

```yaml
- name: Create build user for AUR packages
  run: |
    useradd -m builder
    echo "builder ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
    mkdir -p /tmp/aur-build
    chown builder:builder /tmp/aur-build
```

#### Step 1.2: Download Official Packages
Download all packages from `target-packages.x86_64` with dependencies:

```yaml
- name: Download official packages
  run: |
    mkdir -p /tmp/offline-repo

    # Create temporary blank database to download packages with deps
    mkdir -p /tmp/blankdb/local

    # Read packages and download with dependencies
    packages=$(grep -v '^#' archiso/airootfs/root/target-packages.x86_64 | grep -v '^$' | tr '\n' ' ')

    pacman -Syw --cachedir /tmp/offline-repo --dbpath /tmp/blankdb $packages
```

#### Step 1.3: Build AUR Packages
Clone and build each AUR package:

```yaml
- name: Build AUR packages
  run: |
    cd /tmp/aur-build

    # Read AUR packages
    while IFS= read -r package; do
      [[ -z "$package" || "$package" =~ ^# ]] && continue

      echo "Building $package..."
      sudo -u builder git clone "https://aur.archlinux.org/${package}.git"
      cd "$package"
      sudo -u builder makepkg -s --noconfirm --skippgpcheck
      cp *.pkg.tar.zst /tmp/offline-repo/
      cd ..
    done < archiso/airootfs/root/aur-packages.x86_64
```

#### Step 1.4: Create Repository Database
Generate the repo database with all packages:

```yaml
- name: Create offline repository database
  run: |
    cd /tmp/offline-repo
    repo-add offline.db.tar.zst *.pkg.tar.zst
```

#### Step 1.5: Copy Repository to airootfs
Include the repository in the ISO:

```yaml
- name: Include offline repository in ISO
  run: |
    mkdir -p archiso/airootfs/opt/offline-repo
    cp /tmp/offline-repo/*.pkg.tar.zst archiso/airootfs/opt/offline-repo/
    cp /tmp/offline-repo/offline.db* archiso/airootfs/opt/offline-repo/
    cp /tmp/offline-repo/offline.files* archiso/airootfs/opt/offline-repo/
```

### Phase 2: Configuration Files

#### Step 2.1: Create Offline pacman.conf
Create `archiso/airootfs/etc/pacman.d/offline-pacman.conf`:

```ini
[options]
HoldPkg     = pacman glibc
Architecture = auto
CheckSpace
SigLevel    = Required DatabaseOptional
LocalFileSigLevel = Optional TrustAll

# Offline repository (priority - first)
[offline]
SigLevel = Optional TrustAll
Server = file:///opt/offline-repo

# Online repositories (fallback)
[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist

[multilib]
Include = /etc/pacman.d/mirrorlist
```

#### Step 2.2: Modify Build pacman.conf
Update `archiso/pacman.conf` to include the offline repo during build:

```ini
# Add before [core]:
[offline]
SigLevel = Optional TrustAll
Server = file:///tmp/offline-repo
```

### Phase 3: Installer Modifications

#### Step 3.1: Add Offline Detection
Modify `hyprland-install` to detect offline mode:

```bash
# Near the top of the script
detect_offline_mode() {
    if [[ -d /opt/offline-repo ]] && [[ -f /opt/offline-repo/offline.db.tar.zst ]]; then
        OFFLINE_MODE=1
        info "Offline repository detected - enabling offline installation mode"
    else
        OFFLINE_MODE=0
    fi
}
```

#### Step 3.2: Modify Package Installation
Update the `install_base()` function:

```bash
install_base() {
    # ... existing code ...

    if [[ "$OFFLINE_MODE" -eq 1 ]]; then
        # Copy offline pacman.conf to target
        mkdir -p /mnt/etc/pacman.d
        cp /etc/pacman.d/offline-pacman.conf /mnt/etc/pacman.conf

        # Copy offline repo to target (for pacstrap to use)
        mkdir -p /mnt/opt/offline-repo
        cp -r /opt/offline-repo/* /mnt/opt/offline-repo/

        # Use pacstrap with local config
        pacstrap -C /etc/pacman.d/offline-pacman.conf -K /mnt "${packages[@]}"
    else
        # Online installation (current behavior)
        pacstrap -K /mnt "${packages[@]}"
    fi
}
```

#### Step 3.3: Modify AUR Installation
Update `install_aur_packages()` for offline mode:

```bash
install_aur_packages() {
    # ... existing code ...

    if [[ "$OFFLINE_MODE" -eq 1 ]]; then
        # AUR packages already in offline repo, install directly
        info "Installing pre-built AUR packages from offline repository..."

        for pkg in "${aur_packages[@]}"; do
            arch-chroot /mnt pacman -S --noconfirm "$pkg"
        done
    else
        # Online installation (current behavior - build with yay)
        # ... existing yay installation code ...
    fi
}
```

#### Step 3.4: Post-Installation Cleanup
Remove offline repo after installation (optional, saves disk space):

```bash
finish() {
    # ... existing code ...

    if [[ "$OFFLINE_MODE" -eq 1 ]]; then
        # Optionally remove offline repo to save space
        # Or keep it for future package installations

        # Restore normal pacman.conf for online updates
        cat > /mnt/etc/pacman.conf << 'EOF'
[options]
HoldPkg     = pacman glibc
Architecture = auto
CheckSpace
ParallelDownloads = 5
SigLevel    = Required DatabaseOptional
LocalFileSigLevel = Optional

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist

[multilib]
Include = /etc/pacman.d/mirrorlist
EOF
    fi
}
```

### Phase 4: Build Workflow Updates

#### Complete Updated Workflow Section

```yaml
- name: Build offline repository
  run: |
    # Create build user
    useradd -m builder
    echo "builder ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

    # Install build dependencies
    pacman -S --noconfirm --needed git base-devel

    # Create directories
    mkdir -p /tmp/offline-repo
    mkdir -p /tmp/aur-build
    mkdir -p /tmp/blankdb/local
    chown builder:builder /tmp/aur-build

    # Download official packages with dependencies
    echo "Downloading official packages..."
    packages=$(grep -v '^#' archiso/airootfs/root/target-packages.x86_64 | grep -v '^$' | tr '\n' ' ')
    pacman -Syw --cachedir /tmp/offline-repo --dbpath /tmp/blankdb $packages

    # Build AUR packages
    echo "Building AUR packages..."
    cd /tmp/aur-build
    while IFS= read -r package; do
      [[ -z "$package" || "$package" =~ ^# ]] && continue
      echo "::group::Building $package"
      sudo -u builder git clone "https://aur.archlinux.org/${package}.git"
      cd "$package"
      sudo -u builder makepkg -s --noconfirm --skippgpcheck
      cp *.pkg.tar.zst /tmp/offline-repo/
      cd ..
      echo "::endgroup::"
    done < $GITHUB_WORKSPACE/archiso/airootfs/root/aur-packages.x86_64

    # Create repository database
    echo "Creating repository database..."
    cd /tmp/offline-repo
    repo-add offline.db.tar.zst *.pkg.tar.zst

    # Copy to airootfs
    echo "Copying repository to ISO..."
    mkdir -p $GITHUB_WORKSPACE/archiso/airootfs/opt/offline-repo
    cp /tmp/offline-repo/* $GITHUB_WORKSPACE/archiso/airootfs/opt/offline-repo/

    # Show repository size
    du -sh $GITHUB_WORKSPACE/archiso/airootfs/opt/offline-repo/
```

## Considerations

### ISO Size Impact
- Current ISO: ~1-1.5 GB
- With offline packages: ~4-6 GB (estimated)
- Consider offering both online and offline ISO variants

### Build Time Impact
- Current build: ~10-15 minutes
- With AUR building: ~30-60 minutes (depending on packages)

### Package Freshness
- Offline packages become outdated as soon as they're built
- Users should run `pacman -Syu` after installation when online
- Consider adding a warning message in the installer

### AUR Package Dependencies
- Some AUR packages may have dependencies on other AUR packages
- Build order matters (e.g., `elephant` before `elephant-*` providers)
- May need to handle build failures gracefully

### Fallback Behavior
- If offline repo is incomplete/corrupted, fall back to online
- Provide clear error messages for offline-specific issues

## Alternative: Hybrid Approach

Instead of a fully offline ISO, consider a "mostly offline" approach:

1. Include all official packages in the offline repo
2. Still require internet for AUR packages (they change frequently)
3. Reduces ISO size while still speeding up installation significantly

## Files to Create/Modify

| File | Action | Description |
|------|--------|-------------|
| `.github/workflows/build-iso.yml` | Modify | Add offline repo build steps |
| `archiso/airootfs/etc/pacman.d/offline-pacman.conf` | Create | Offline pacman configuration |
| `archiso/airootfs/usr/local/bin/hyprland-install` | Modify | Add offline mode detection and handling |
| `archiso/pacman.conf` | Modify | Add offline repo for build process |

## Testing Plan

1. Build ISO locally with offline repo
2. Test in QEMU with network disabled
3. Verify all packages install correctly
4. Test fallback to online when offline repo missing
5. Verify post-install system can update normally

## Success Criteria

- [ ] ISO builds successfully with embedded packages
- [ ] Installation completes without network access
- [ ] All packages from both lists are installed
- [ ] System boots and functions correctly after install
- [ ] Online updates work post-installation
