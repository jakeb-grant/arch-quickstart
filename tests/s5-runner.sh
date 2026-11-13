#!/usr/bin/env bash
# s5 harness — rootless scenario tests for hyprland-install (V3 surface:
# AUR per-package tolerance, install-time swap lifecycle, teardown ordering;
# D2: user installs, run through the real user-installs-setup; D3: the
# dotfiles apply and its temporary passwordless sudo).
#
# Runs INSIDE `unshare -rm` (root in a user namespace): tmpfs is mounted over
# /mnt and /root so the real installer functions run against a throwaway
# filesystem with stubbed commands — no sudo, no VM, nothing touched on the
# host.
#
# Usage:
#   bash tests/s5-runner.sh all               # run every scenario
#   unshare -rm bash tests/s5-runner.sh main <scenario>
#
# Scenarios:
#   aur-online-all-ok aur-online-one-fails aur-online-bootstrap-ok
#   aur-online-bootstrap-git-fails aur-online-bootstrap-mkpkg-fails
#   aur-offline-one-fails swap-swapon-ok swap-swapon-fails
#   teardown-active-swap ui-online-one-fails ui-offline-payload ui-none
#   dot-preloaded-ok dot-preloaded-fails dot-init-fails dot-ctrl-c
#   dot-exit-cleanup
#
# Gotcha (learned the hard way): `command -v` falls back to non-executable
# PATH entries, so host binaries (e.g. an installed yay) are hidden by giving
# the generated script a stubs-only PATH — NOT by masking the binary.
set -u

SCENARIOS=(
    aur-online-all-ok aur-online-one-fails aur-online-bootstrap-ok
    aur-online-bootstrap-git-fails aur-online-bootstrap-mkpkg-fails
    aur-offline-one-fails swap-swapon-ok swap-swapon-fails
    teardown-active-swap
    ui-online-one-fails ui-offline-payload ui-none
    dot-preloaded-ok dot-preloaded-fails dot-init-fails dot-ctrl-c
    dot-exit-cleanup
)

SELF="$(readlink -f "${BASH_SOURCE[0]}")"
INSTALLER="$(dirname "$SELF")/../archiso/airootfs/usr/local/bin/hyprland-install"
S_RUNNER="$(dirname "$SELF")/../archiso/airootfs/usr/local/bin/user-installs-setup"
export S_RUNNER
MODE="$1" SCEN="${2:-}"
STUBS=/root/stubs
CALLS=/root/calls.log
OUT=/root/out.log

# ----------------------------------------------------------------- all mode
if [[ "$MODE" == all ]]; then
    failed=0
    for s in "${SCENARIOS[@]}"; do
        unshare -rm bash "$SELF" main "$s" || failed=1
    done
    exit $failed
fi

# ---------------------------------------------------------------- exec mode
if [[ "$MODE" == exec ]]; then
    [[ -r "$INSTALLER" ]] || { echo "installer not readable: $INSTALLER"; exit 2; }
    export PATH="$STUBS:$PATH"
    # shellcheck disable=SC1090
    source <(head -n -1 "$INSTALLER")   # drop the trailing `main "$@"`
    # shellcheck disable=SC2034  # consumed by the sourced installer functions
    USERNAME=testuser
    # shellcheck disable=SC2034  # consumed by the sourced installer functions
    case "$SCEN" in
        aur-offline-*) OFFLINE_MODE=1 ;;
        aur-*)         OFFLINE_MODE=0 ;;
    esac
    case "$SCEN" in
        aur-*)      install_aur_packages ;;
        swap-*)     configure_swap ;;
        teardown-*) teardown_target ;;
        ui-*)       run_user_installs ;;
        dot-exit-*) touch "$INSTALL_SUDOERS"; exit 1 ;;
        # Checked here, before on_exit (which also removes it) can hide a
        # missing cleanup in the step itself
        dot-*)      setup_dotfiles
                    [[ -e "$INSTALL_SUDOERS" ]] && echo "SUDOERS LEFT AFTER STEP"
                    echo "INT trap after step: $(trap -p INT)" ;;
    esac
    exit 0
fi

# ---------------------------------------------------------------- main mode
# Refuse to run as real root (init userns): the tmpfs mounts below would
# shadow the host's actual /mnt and /root. Inside `unshare -rm` the uid_map
# range is 1, not the full 2^32-1 of the init namespace.
if [[ "$(awk '{print $3; exit}' /proc/self/uid_map)" == 4294967295 ]]; then
    echo "main mode must run inside 'unshare -rm' (would mount over the real /mnt and /root)"
    exit 2
fi
mount -t tmpfs none /mnt
mount -t tmpfs none /root
# User-install scenarios: the live ISO's hooks and payloads live here
if [[ "$SCEN" == ui-* || "$SCEN" == dot-* ]]; then
    mount -t tmpfs none /usr/local/share
    mount -t tmpfs none /opt
fi
mkdir -p /mnt/home/testuser /mnt/swap /mnt/etc/sudoers.d "$STUBS"
touch "$CALLS"

mkstub() { local n="$1"; shift; printf '%s\n' "#!/bin/bash" "$@" > "$STUBS/$n"; chmod +x "$STUBS/$n"; }

# Pass-through wrappers: the generated install-aur.sh runs with PATH=$STUBS
# only, but still needs these coreutils
for c in rm mkdir cp chmod touch; do
    mkstub "$c" "exec /usr/bin/$c \"\$@\""
done

mkstub clear ':'
mkstub sleep ':'
mkstub fuser 'exit 0'
mkstub udevadm 'exit 0'
mkstub gpgconf 'exit 0'
mkstub cryptsetup 'exit 0'
mkstub chattr 'exit 0'
mkstub dd 'exit 0'
mkstub mkswap 'exit 0'
mkstub free 'echo "Mem: 4096 1024 3072"'
mkstub btrfs 'echo 12345'
mkstub swapon 'echo "swapon $*" >> /root/calls.log
[[ "${S_SWAPON_FAIL:-0}" == 1 ]] && exit 255
exit 0'
mkstub swapoff 'echo "swapoff $*" >> /root/calls.log
exit 0'
mkstub umount 'echo "umount $*" >> /root/calls.log
exit 0'
mkstub mountpoint '# report /mnt mounted until an umount has been logged
grep -q "^umount" /root/calls.log 2>/dev/null && exit 1
exit 0'
mkstub gum 'out=(); skip=0
for a in "$@"; do
  if (( skip )); then skip=0; continue; fi
  case "$a" in
    style|confirm|choose|input|spin) ;;
    --padding|--margin|--border|--align|--border-foreground|--foreground) skip=1 ;;
    --*) ;;
    *) out+=("$a") ;;
  esac
done
(( ${#out[@]} )) && printf "%s\n" "${out[@]}"
exit 0'
mkstub git 'if [[ "${S_GIT_FAIL:-0}" == 1 ]]; then echo "fatal: clone failed" >&2; exit 128; fi
mkdir -p yay-bin
exit 0'
mkstub makepkg 'if [[ "${S_MAKEPKG_FAIL:-0}" == 1 ]]; then exit 4; fi
cp /root/stubs/yay.real /root/stubs/yay
chmod +x /root/stubs/yay
exit 0'
# yay kept as yay.real; copied to yay by makepkg stub or scenario setup
printf '%s\n' '#!/bin/bash' 'pkg="${!#}"' \
    '[[ " ${S_YAY_FAIL_PKGS:-} " == *" $pkg "* ]] && exit 4' 'exit 0' \
    > "$STUBS/yay.real"
chmod +x "$STUBS/yay.real"
mkstub arch-chroot 'echo "arch-chroot $*" >> /root/calls.log
root="$1"; shift
case "$1" in
  pacman)
    pkg="${!#}"
    [[ " ${S_PACMAN_FAIL_PKGS:-} " == *" $pkg "* ]] && exit 1
    exit 0 ;;
  sudo)
    # user-installs-setup: the real runner, against the hooks in the target, as
    # uid 1000 (it refuses root) in a nested user namespace
    if [[ " $* " == *" /usr/local/bin/user-installs-setup "* ]]; then
      p=""
      for a in "$@"; do [[ "$a" == USER_INSTALLS_PAYLOADS=* ]] && p="${a#*=}"; done
      HOME="$root/home/testuser" USER_INSTALLS_DIR="$root/usr/local/share/user-installs" \
        USER_INSTALLS_PAYLOADS="${p:+$root$p}" \
        exec unshare -U --map-user=1000 --map-group=1000 /bin/bash "$S_RUNNER" "${!#}"
    fi
    # chezmoi: log its arguments and the temporary sudoers drop-in as it
    # stands while chezmoi runs
    if [[ " $* " == *" chezmoi "* ]]; then
      echo "chezmoi-args: $*" >> /root/calls.log
      f=$root/etc/sudoers.d/90-arch-quickstart-install
      [[ -e $f ]] && echo "sudoers-during: $(cat "$f")" >> /root/calls.log
      # chezmoi writes its config once init has rendered it
      if [[ "${S_CHEZMOI_CONFIG:-1}" == 1 ]]; then
        mkdir -p "$root/home/testuser/.config/chezmoi"
        touch "$root/home/testuser/.config/chezmoi/chezmoi.toml"
      fi
      # Ctrl-C at a prompt: the terminal signals the whole foreground
      # group, the installer (this stub parent) included
      if [[ "${S_CHEZMOI_SIGINT:-0}" == 1 ]]; then kill -INT "$PPID"; exit 130; fi
      exit "${S_CHEZMOI_RC:-0}"
    fi
    # stubs-only PATH so `command -v yay` sees exactly what the harness put
    # in /root/stubs (the host may have yay installed)
    script="${!#}"
    HOME="$root/home/testuser" PATH="/root/stubs" exec /bin/bash "$root$script" ;;
  *) exit 0 ;;
esac'

printf 'pkg1\npkg2\n' > /root/aur-packages.x86_64

# User installs a and b, on the live ISO and copied to the target (as
# configure_system does). Each logs what it saw; one in S_UI_FAIL fails
mkhook() {
    local d
    for d in /usr/local/share/user-installs/$1 /mnt/usr/local/share/user-installs/$1; do
        mkdir -p "$d"
        printf '%s\n' 'echo "'"$1"' ran PAYLOAD=$PAYLOAD pwd=$PWD" >> "$HOME/hooks.log"' \
            '[[ -z "$PAYLOAD" ]] || ls "$PAYLOAD" >> "$HOME/hooks.log"' \
            '[[ " ${S_UI_FAIL:-} " != *" '"$1"' "* ]]' > "$d/install"
    done
}
if [[ "$SCEN" == ui-* && "$SCEN" != ui-none ]]; then
    mkhook a
    mkhook b
fi

# Scenario knobs
case "$SCEN" in
    aur-online-all-ok)                cp "$STUBS/yay.real" "$STUBS/yay"; chmod +x "$STUBS/yay" ;;
    aur-online-one-fails)             cp "$STUBS/yay.real" "$STUBS/yay"; chmod +x "$STUBS/yay"
                                      export S_YAY_FAIL_PKGS="pkg2" ;;
    aur-online-bootstrap-ok)          : ;;  # no yay stub; git+makepkg succeed
    aur-online-bootstrap-git-fails)   export S_GIT_FAIL=1 ;;
    aur-online-bootstrap-mkpkg-fails) export S_MAKEPKG_FAIL=1 ;;
    aur-offline-one-fails)            export S_PACMAN_FAIL_PKGS="pkg2" ;;
    swap-swapon-ok)                   : ;;
    swap-swapon-fails)                export S_SWAPON_FAIL=1 ;;
    teardown-active-swap)             : ;;
    ui-online-one-fails)              export S_UI_FAIL="b" ;;
    ui-offline-payload)               mkdir -p /opt/user-installs/a; touch /opt/user-installs/a/blob ;;
    ui-none)                          : ;;
    dot-preloaded-ok)                 mkdir -p /opt/dotfiles/.git ;;
    dot-preloaded-fails)              mkdir -p /opt/dotfiles/.git; export S_CHEZMOI_RC=1 ;;
    dot-init-fails)                   mkdir -p /opt/dotfiles/.git; export S_CHEZMOI_RC=1 S_CHEZMOI_CONFIG=0 ;;
    dot-ctrl-c)                       mkdir -p /opt/dotfiles/.git; export S_CHEZMOI_SIGINT=1 S_CHEZMOI_CONFIG=0 ;;
    dot-exit-cleanup)                 : ;;
    *) echo "unknown scenario: $SCEN"; exit 2 ;;
esac

rc=0
bash "$SELF" exec "$SCEN" > "$OUT" 2>&1 < /dev/null || rc=$?

# Assertions
pass=1
fail() { echo "  ASSERT FAIL: $1"; pass=0; }
want()    { grep -qF -- "$1" "$OUT" || fail "output missing: $1"; }
want_not() { grep -qF -- "$1" "$OUT" && fail "output must not contain: $1"; return 0; }
want_rc0() { [[ $rc -eq 0 ]] || fail "exit code $rc, expected 0"; }
marker=/mnt/home/testuser/.aur-failed

case "$SCEN" in
    aur-online-all-ok)
        want_rc0
        want "AUR packages installed!"
        want_not "failed to build/install"
        want_not "ERROR: Command failed"
        [[ -e $marker ]] && fail ".aur-failed left behind" ;;
    aur-online-one-fails)
        want_rc0
        want "1 AUR packages failed to build/install"
        want "  - pkg2"
        want "install manually with: yay -S pkg2"
        want "AUR packages installed!"
        want_not "ERROR: Command failed"
        [[ -e $marker ]] && fail ".aur-failed left behind" ;;
    aur-online-bootstrap-ok)
        want_rc0
        want "AUR packages installed!"
        want_not "skipped"
        want_not "failed to build/install"
        want_not "ERROR: Command failed"
        [[ -e $marker ]] && fail ".aur-failed left behind" ;;
    aur-online-bootstrap-git-fails|aur-online-bootstrap-mkpkg-fails)
        want_rc0
        want "all AUR packages were skipped"
        want "install yay and run: yay -S pkg1 pkg2"
        want_not "ERROR: Command failed"
        [[ -e $marker ]] && fail ".aur-failed left behind" ;;
    aur-offline-one-fails)
        want_rc0
        want "Failed to install pkg2"
        want "install manually with: yay -S pkg2"
        want "AUR packages installed!"
        want_not "ERROR: Command failed" ;;
    swap-swapon-ok)
        want_rc0
        want "Swap file configured"
        want_not "Could not activate swap"
        grep -q '^swapon /mnt/swap/swapfile' "$CALLS" || fail "swapon never called"
        grep -qF '/swap/swapfile none swap' /mnt/etc/fstab || fail "fstab entry missing" ;;
    swap-swapon-fails)
        want_rc0
        want "Could not activate swap"
        want "Swap file configured"
        want_not "ERROR: Command failed"
        grep -qF '/swap/swapfile none swap' /mnt/etc/fstab || fail "fstab entry missing" ;;
    teardown-active-swap)
        want_rc0
        so=$(grep -n '^swapoff' "$CALLS" | head -1 | cut -d: -f1)
        um=$(grep -n '^umount' "$CALLS" | head -1 | cut -d: -f1)
        [[ -n $so ]] || fail "swapoff never called in teardown"
        [[ -n $um ]] || fail "umount never called in teardown"
        [[ -n $so && -n $um && $so -lt $um ]] || fail "swapoff ($so) not before umount ($um)" ;;
    ui-online-one-fails)
        log=/mnt/home/testuser/hooks.log
        want_rc0
        want "1 user install(s) failed: b"
        want "After rebooting, run: user-installs-setup b"
        want_not "User installs done!"
        want_not "ERROR: Command failed"
        grep -qx "a ran PAYLOAD= pwd=/mnt/home/testuser" "$log" || fail "a did not run in ~ without a payload"
        grep -q "^b ran" "$log" || fail "b never ran" ;;
    ui-offline-payload)
        log=/mnt/home/testuser/hooks.log
        want_rc0
        want "User installs done!"
        want_not "failed"
        grep -qx "a ran PAYLOAD=/mnt/var/tmp/user-installs-payloads/a pwd=/mnt/home/testuser" "$log" \
            || fail "a did not get its staged payload"
        grep -qx "blob" "$log" || fail "a's payload was empty"
        grep -qx "b ran PAYLOAD= pwd=/mnt/home/testuser" "$log" || fail "b (no payload) got one"
        grep -q "chown -R testuser: /var/tmp/user-installs-payloads" "$CALLS" || fail "payload not chowned in the chroot"
        [[ -e /mnt/var/tmp/user-installs-payloads ]] && fail "staged payloads left in the target" ;;
    dot-preloaded-ok)
        want_rc0
        want "Dotfiles applied successfully!"
        grep -q -- "chezmoi-args: .*sudo -u testuser -H env ARCH_QUICKSTART_INSTALL=1 chezmoi init --apply --keep-going$" "$CALLS" \
            || fail "chezmoi not run as the user with -H, ARCH_QUICKSTART_INSTALL and --keep-going"
        grep -qx "sudoers-during: testuser ALL=(ALL:ALL) NOPASSWD: ALL" "$CALLS" || fail "no temporary sudoers while chezmoi ran"
        want_not "SUDOERS LEFT AFTER STEP" ;;
    dot-preloaded-fails)
        want_rc0
        want "Some dotfiles did not apply (see above). After rebooting, run: chezmoi apply"
        want_not "Dotfiles applied successfully!"
        want_not "ERROR: Command failed"
        want_not "SUDOERS LEFT AFTER STEP" ;;
    dot-init-fails)
        want_rc0
        want "After rebooting, run: chezmoi init --apply"
        want_not "SUDOERS LEFT AFTER STEP" ;;
    dot-ctrl-c)
        want_rc0
        want "After rebooting, run: chezmoi init --apply"
        want "INT trap after step: trap -- 'exit 130' SIGINT"
        want_not "SUDOERS LEFT AFTER STEP"
        want_not "ERROR: Command failed" ;;
    dot-exit-cleanup)
        [[ $rc -eq 1 ]] || fail "exit code $rc, expected 1"
        [[ -e /mnt/etc/sudoers.d/90-arch-quickstart-install ]] && fail "on_exit left the temporary sudoers behind" ;;
    ui-none)
        want_rc0
        want "No user installs"
        grep -q user-installs-setup "$CALLS" && fail "runner called with no user installs" ;;
esac

if (( pass )); then echo "PASS $SCEN"; else echo "FAIL $SCEN"; sed 's/^/    | /' "$OUT"; exit 1; fi
