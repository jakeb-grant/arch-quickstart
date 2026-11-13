#!/usr/bin/env bash
# s5 harness — rootless scenario tests for hyprland-install (V3 surface:
# AUR per-package tolerance, install-time swap lifecycle, teardown ordering;
# D2: user installs, run through the real user-installs-setup; D3: the
# dotfiles apply and its temporary passwordless sudo; F1-F3: Ctrl-C and the
# temporary sudo in the AUR step, and nothing after GRUB aborting the install).
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
#   aur-online-all-ok aur-online-sync-fails aur-online-one-fails
#   aur-online-bootstrap-ok
#   aur-online-bootstrap-git-fails aur-online-bootstrap-mkpkg-fails
#   aur-offline-one-fails aur-online-ctrl-c aur-online-bootstrap-ctrl-c
#   aur-offline-ctrl-c swap-swapon-ok swap-swapon-fails
#   teardown-active-swap ui-online-one-fails ui-offline-payload ui-none
#   dot-preloaded-ok dot-preloaded-fails dot-init-fails dot-ctrl-c
#   dot-remote-fails dot-exit-cleanup ext-all-ok ext-one-fails ext-ctrl-c
#   ext-offline
#   cfg-post-grub-fails cfg-post-grub-write-fails cfg-pre-grub-fails
#   cfg-minimal spine fin-clean fin-notes fin-many
#   review-install review-wrong-name review-quit review-change review-typo
#   review-esc review-change-you review-change-disk review-keep-disk
#   ask-password-retry
#   ask-password-fails err-card err-heredoc err-cancel base-online
#   base-count-fails
#
# Gotcha (learned the hard way): `command -v` falls back to non-executable
# PATH entries, so host binaries (e.g. an installed yay) are hidden by giving
# the generated script a stubs-only PATH — NOT by masking the binary.
set -u

SCENARIOS=(
    aur-online-all-ok aur-online-sync-fails aur-online-one-fails aur-online-bootstrap-ok
    aur-online-bootstrap-git-fails aur-online-bootstrap-mkpkg-fails
    aur-offline-one-fails aur-online-ctrl-c aur-online-bootstrap-ctrl-c
    aur-offline-ctrl-c
    swap-swapon-ok swap-swapon-fails
    teardown-active-swap
    ui-online-one-fails ui-offline-payload ui-none
    dot-preloaded-ok dot-preloaded-fails dot-init-fails dot-ctrl-c
    dot-remote-fails dot-exit-cleanup
    ext-all-ok ext-one-fails ext-ctrl-c ext-offline
    cfg-post-grub-fails cfg-post-grub-write-fails cfg-pre-grub-fails
    cfg-minimal
    spine
    fin-clean fin-notes fin-many
    review-install review-wrong-name review-quit review-change review-typo
    review-esc review-change-you review-change-disk review-keep-disk
    ask-password-retry ask-password-fails
    err-card err-heredoc err-cancel
    base-online base-count-fails
)

SELF="$(readlink -f "${BASH_SOURCE[0]}")"
INSTALLER="$(dirname "$SELF")/../archiso/airootfs/usr/local/bin/hyprland-install"
S_RUNNER="$(dirname "$SELF")/../archiso/airootfs/usr/local/bin/user-installs-setup"
AUR_LIST="$(dirname "$SELF")/../archiso/airootfs/root/aur-packages.x86_64"
export S_RUNNER
MODE="$1" SCEN="${2:-}"
STUBS=/root/stubs
CALLS=/root/calls.log
OUT=/root/out.log
NOTES_OUT=/root/notes.log

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
        aur-offline-*|ext-offline) OFFLINE_MODE=1 ;;
        aur-*|base-*)  OFFLINE_MODE=0 ;;
    esac
    # shellcheck disable=SC2034  # consumed by the sourced installer functions
    case "$SCEN" in
        ext-*) FIREWALL_RULES=$'SSH (port 22)\nKDE Connect / GSConnect (ports 1714-1764)'
               GPU_SETUP=nvidia DETECTED_NVIDIA=1 DETECTED_INTEL=0 DETECTED_AMD=0 ;;
        cfg-*) TIMEZONE=UTC HOSTNAME=testhost PASSWORD=pw ENCRYPT_DISK=no
               ROOT_PART=/dev/vda2 RESUME_OFFSET=12345 OFFLINE_MODE=1 ;;&
        # install_base fell back to the minimal list: no greetd to set up
        cfg-minimal) MINIMAL_SYSTEM=1 GREETER_OK=0 ;;
        # the receipt's facts: chapter times for the questions (1-4, which
        # are not install time and must not show) and from prepare (5) to
        # apps (9); dotfiles' is taken by step. The 21m 47s since the disk
        # was touched is set as finish starts (below), so a slow host can't
        # shift it
        fin-*) HOSTNAME=testhost DISK=/dev/vda ENCRYPT_DISK=yes PKG_COUNT=1284
               OFFLINE_MODE=1
               STEP_SECS=([1]=30 [2]=95 [3]=40 [4]=62 [5]=21 [6]=401 [7]=125 [8]=754 [9]=48) ;;
        # the answers the review card shows (configure_user/_extras' globals)
        review-*) HOSTNAME=testhost TIMEZONE=UTC ENCRYPT_DISK=yes DISK=/dev/vda
                  GIT_USER_NAME="Test User" GIT_USER_EMAIL=test@example.com
                  GPU_SETUP=nvidia GPU_PICK="nvidia-setup (hybrid graphics - detected)"
                  FIREWALL_RULES="SSH (port 22)" ;;&
        # answers off the defaults, all kept by Enter: a timezone of their
        # own, a separate passphrase, a GPU line the list offers, and an
        # opening with a comma in it
        review-change-you)
                  ENCRYPT_PASSWORD=other GPU_PICK="nvidia-setup (NVIDIA)"
                  FIREWALL_RULES=$'SSH (port 22)\nHTTP/HTTPS (ports 80, 443)' ;;
    esac
    case "$SCEN" in
        aur-*)      install_aur_packages ;;
        base-*)     step base
                    install_base
                    echo "PKG_COUNT=$PKG_COUNT" ;;
        swap-*)     configure_swap ;;
        teardown-*) teardown_target ;;
        ui-*)       run_user_installs ;;
        dot-exit-*) touch "$INSTALL_SUDOERS"; exit 1 ;;
        dot-*)      setup_dotfiles ;;
        ext-*)      install_extras
                    echo "CHROOT_TARGET after step: ${CHROOT_TARGET:-}" ;;
        cfg-*)      step system
                    configure_system
                    echo "BOOTABLE=$BOOTABLE GREETER_OK=$GREETER_OK" ;;
        fin-*)
            # The end of the dotfiles chapter, then the finish receipt with
            # the stub's yes. CLEAR marks where the receipt's screen starts
            clear() { echo "CLEAR"; }
            # shellcheck disable=SC2034  # read by the sourced step and finish
            STEP_N=10
            case "$SCEN" in
                fin-clean) step_skip ;;
                fin-notes) note "hyprshot didn't build" "yay -S hyprshot" ;;
                fin-many)
                    # shellcheck disable=SC2034  # read by the sourced finish
                    DOTFILES_APPLIED=1
                    note "the AUR step stopped early" \
                        "yay -S --needed $(grep -v '^[[:space:]]*#' "$AUR_LIST" | xargs)"
                    note "2 user installs failed" "user-installs-setup strand rust"
                    note "some dotfiles did not apply" "chezmoi apply"
                    note "the temporary sudo rule is still there" \
                        "sudo rm /etc/sudoers.d/90-arch-quickstart-install"
                    # shellcheck disable=SC2034  # read by the sourced finish
                    GREETER_OK=0
                    note "greetd is not enabled" "sudo systemctl enable greetd"
                    note "hibernation is not enabled (no swapfile offset)"
                    note "could not write /etc/iwd/main.conf"
                    note "check swap is on (it failed in the installer)" "swapon --show" ;;
            esac
            # main's own lines from the dotfiles chapter's work on, so a step
            # dropped from main fails here; setup_dotfiles is left to the
            # dot-* scenarios
            setup_dotfiles() { :; }
            # finish, with the clock set as it starts: it reads SECONDS
            # twice (report, card), so the check still allows a second
            eval "$(declare -f finish | sed '1s/^finish /s5_finish /')"
            # shellcheck disable=SC2034  # read by the sourced finish
            finish() { INSTALL_T0=$(( SECONDS - 1307 )); s5_finish; }
            tail=$(sed -n "s/^ *step dotfiles; *//p; s/^ *\(step 'done';.*\)/\1/p" "$INSTALLER")
            [[ $tail == *restore_pacman_conf*finish* ]] || echo "MAIN TAIL NOT FOUND: $tail"
            eval "$tail" ;;
        review-*)
            # The gate alone: the card, the menu, the typed name. Nothing
            # may reach the disk: partition_disk is never called from here,
            # and DISK_TOUCHED is printed however review_plan ends (the
            # trap hands the exit code on to on_exit untouched)
            partition_disk() { echo "PARTITION CALLED"; }
            # shellcheck disable=SC2154  # s5_rc is set by the trap itself
            trap 's5_rc=$?; echo "TOUCHED=$DISK_TOUCHED"; set +e; trap - ERR
                  (exit $s5_rc); on_exit' EXIT
            step review
            review_plan
            echo "REVIEW RETURNED" ;;
        ask-*)
            # configure_user's typed-twice password, with the stub's yes at
            # every confirm (encrypt, with the same password)
            configure_user
            [[ $PASSWORD == pw && $ENCRYPT_PASSWORD == pw ]] && echo "PASSWORD SET" ;;
        err-card)
            # A command fails once the disk is touched: the ERR line, then
            # cleanup, then the failure card, then the pause
            step base
            # shellcheck disable=SC2034  # read by the sourced on_exit
            DISK=/dev/vda DISK_TOUCHED=1 HOSTNAME=testhost
            grep -q never-there /dev/null ;;
        err-heredoc)
            # A heredoc fails once the target boots: BASH_COMMAND carries
            # the body, which must not break the card's rows (bash's own
            # message, which names this long path, is kept out)
            step system
            # shellcheck disable=SC2034  # read by the sourced on_exit
            DISK=/dev/vda DISK_TOUCHED=1 HOSTNAME=testhost BOOTABLE=1
            cat 2> /dev/null > /nonexistent/hosts << EOF
127.0.0.1   localhost
EOF
            ;;
        err-cancel)
            # Ctrl-C once the disk is touched: cleanup, but no card, no pause
            step base
            # shellcheck disable=SC2034  # read by the sourced on_exit
            DISK=/dev/vda DISK_TOUCHED=1
            exit 130 ;;
        spine)
            # The welcome, then the masthead through the chapters: clear
            # always before the disk is touched, then only on a new chapter.
            # A 63-character hostname must be cut to keep the boot note in
            # 79 columns.
            clear() { echo "CLEAR"; }
            echo "STEP_COUNT=${#STEPS[@]}"
            welcome
            header
            step disk;    header; header
            step prepare; header; DISK_TOUCHED=1; header
            # shellcheck disable=SC2034  # read by the sourced masthead
            HOSTNAME=$(printf 'h%.0s' {1..63}) BOOTABLE=1
            step apps;    header; header
            step 'done';  header
            # a per-package rule with the longest kind and count: the name
            # gives way, the line stays in 79 columns (checked below)
            pkg_rule "user install" 10 10 "$(printf 'n%.0s' {1..70})"
            # shellcheck disable=SC2034  # read by the sourced on_exit
            DISK_TOUCHED=0 ;;
    esac
    # Checked here, before on_exit (which also removes it) can hide a
    # missing cleanup in the step itself
    [[ -e "$INSTALL_SUDOERS" ]] && echo "SUDOERS LEFT AFTER STEP"
    # The notes the step carried to the finish receipt, one "WHAT|FIX" a
    # line, kept out of the output (a fix may pass 79 columns)
    for i in "${!NOTES[@]}"; do
        printf '%s|%s\n' "${NOTES[i]}" "${NOTE_FIXES[i]}"
    done > "$NOTES_OUT"
    echo "INT trap after step: $(trap -p INT)"
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
if [[ "$SCEN" == ui-* || "$SCEN" == dot-* || "$SCEN" == cfg-* ]]; then
    mount -t tmpfs none /usr/local/share
    mount -t tmpfs none /opt
fi
# Setup scripts (install_extras), and what configure_system copies from the
# live system into the target
if [[ "$SCEN" == ext-* || "$SCEN" == cfg-* ]]; then
    mount -t tmpfs none /usr/local/bin
    mount -t tmpfs none /usr/local/lib
fi
# Teardown and the failure card read the LUKS mapping's state: hide the
# host's own, so no scenario depends on (or touches) it
if [[ -d /dev/mapper ]]; then
    mount -t tmpfs none /dev/mapper
fi
if [[ "$SCEN" == cfg-* ]]; then
    mount -t tmpfs none /etc/skel
    mkdir -p /etc/skel/.config/hypr /mnt/etc/pacman.d /mnt/etc/pam.d /mnt/etc/default \
        /mnt/boot/EFI/GRUB /mnt/boot/EFI/BOOT /mnt/boot/grub /mnt/usr/local/bin
    touch /etc/skel/.config/hypr/hyprland.lua
    echo 'HOOKS=(base udev)' > /mnt/etc/mkinitcpio.conf
    echo 'GRUB_CMDLINE_LINUX=""' > /mnt/etc/default/grub
    # What grub-install / grub-mkconfig would have written
    for f in EFI/GRUB/grubx64.efi EFI/BOOT/BOOTX64.EFI grub/grub.cfg; do echo x > "/mnt/boot/$f"; done
    for s in bluetooth-setup firewall-setup; do
        printf '#!/bin/bash\n' > "/usr/local/bin/$s"; chmod +x "/usr/local/bin/$s"
    done
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
mkstub genfstab 'echo "# fstab"'
mkstub blkid 'echo 0000-test-uuid'
mkstub swapon 'echo "swapon $*" >> /root/calls.log
[[ "${S_SWAPON_FAIL:-0}" == 1 ]] && exit 255
exit 0'
mkstub swapoff 'echo "swapoff $*" >> /root/calls.log
exit 0'
mkstub umount 'echo "umount $*" >> /root/calls.log
exit 0'
mkstub reboot 'echo "reboot" >> /root/calls.log
exit 0'
mkstub mountpoint '# report /mnt mounted until an umount has been logged
grep -q "^umount" /root/calls.log 2>/dev/null && exit 1
exit 0'
mkstub gum '# S_GUM_CHOOSE / S_GUM_INPUT: what the user picks at each gum choose /
# types at each gum input, a |-separated sequence, one value a call (a value
# can be empty: "a||b"). ESC, or a call past the end, is Esc: exit 1. KEEP
# is Enter on what was pre-filled: an input its --value, a choose its
# --selected=, one a line ("\," is a comma). S_GUM_CONFIRM: the answer at
# each gum confirm, no, yes or DEF (Enter: its --default, true unless
# --default=false); past the end (and unset), yes
knob="S_GUM_${1^^}"
if [[ "$1" == confirm && -n "${S_GUM_CONFIRM:-}" ]]; then
  IFS="|" read -ra vals <<< "$S_GUM_CONFIRM"
  n=$(cat /root/gum-confirm.n 2>/dev/null || echo 0)
  echo $(( n + 1 )) > /root/gum-confirm.n
  [[ "${vals[n]:-yes}" == no ]] && exit 1
  [[ "${vals[n]:-yes}" == DEF && " $* " == *" --default=false "* ]] && exit 1
fi
if [[ ( "$1" == choose || "$1" == input ) && -n "${!knob:-}" ]]; then
  IFS="|" read -ra vals <<< "${!knob}"
  n=$(cat "/root/gum-$1.n" 2>/dev/null || echo 0)
  echo $(( n + 1 )) > "/root/gum-$1.n"
  (( n < ${#vals[@]} )) && [[ "${vals[n]}" != ESC ]] || exit 1
  if [[ "${vals[n]}" == KEEP ]]; then
    v=(); prev=""
    for a in "$@"; do
      [[ "$prev" == --value ]] && v+=("$a")
      [[ "$a" == --value=* ]] && v+=("${a#--value=}")
      [[ "$a" == --selected=* ]] && { a=${a#--selected=}; v+=("${a//\\,/,}"); }
      prev=$a
    done
    (( ${#v[@]} )) || v=("")
    printf "%s\n" "${v[@]}"; exit 0
  fi
  printf "%s\n" "${vals[n]}"; exit 0
fi
out=(); skip=0
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
# Disk tools: the review card and the erase screen read the disk; wipefs and
# parted must never run in a review scenario
mkstub lsblk 'if [[ " $* " == *" -dno "* ]]; then echo "  20G QEMU HARDDISK"; exit 0; fi
if [[ " $* " == *" -dpno "* ]]; then
  printf "%s\n" "/dev/vda  20G QEMU HARDDISK" "/dev/vdb  10G QEMU HARDDISK"; exit 0
fi
printf "%s\n" "NAME    SIZE FSTYPE LABEL" "vda      20G" "|-vda1  512M vfat   SYSTEM" "\`-vda2 19.5G ntfs   Windows"'
mkstub wipefs 'echo "wipefs $*" >> /root/calls.log'
mkstub lspci 'exit 0'    # no GPU detected, whatever the host has
mkstub parted 'echo "parted $*" >> /root/calls.log'
mkstub git 'if [[ "${S_GIT_FAIL:-0}" == 1 ]]; then echo "fatal: clone failed" >&2; exit 128; fi
mkdir -p yay-bin
exit 0'
mkstub makepkg 'if [[ "${S_MAKEPKG_FAIL:-0}" == 1 ]]; then exit 4; fi
cp /root/stubs/yay.real /root/stubs/yay
chmod +x /root/stubs/yay
mkdir -p /mnt/usr/bin
touch /mnt/usr/bin/yay
chmod +x /mnt/usr/bin/yay
exit 0'
# yay kept as yay.real; copied to yay by makepkg stub or scenario setup.
# have_yay: yay already installed, on the stubs PATH and in the target
# (where the installer looks for it after a failed AUR step)
have_yay() {
    cp "$STUBS/yay.real" "$STUBS/yay"; chmod +x "$STUBS/yay"
    mkdir -p /mnt/usr/bin; touch /mnt/usr/bin/yay; chmod +x /mnt/usr/bin/yay
}
printf '%s\n' '#!/bin/bash' 'pkg="${!#}"' \
    '[[ " ${S_YAY_FAIL_PKGS:-} " == *" $pkg "* ]] && exit 4' 'exit 0' \
    > "$STUBS/yay.real"
chmod +x "$STUBS/yay.real"
mkstub arch-chroot 'echo "arch-chroot $*" >> /root/calls.log
root="$1"; shift
# S_CHROOT_FAIL: a command line (e.g. "systemctl enable greetd") that fails
[[ -n "${S_CHROOT_FAIL:-}" && " $* " == *" $S_CHROOT_FAIL "* ]] && exit 1
case "$1" in
  chpasswd) cat > /dev/null; exit 0 ;;
  pacman)
    pkg="${!#}"
    [[ " ${S_PACMAN_FAIL_PKGS:-} " == *" $pkg "* ]] && exit 1
    # Ctrl-C while this package installs: the terminal signals the whole
    # foreground group, the installer (this stub parent) included
    if [[ " ${S_PACMAN_SIGINT_PKGS:-} " == *" $pkg "* ]]; then kill -INT "$PPID"; exit 130; fi
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
    # The AUR script: log the temporary sudoers drop-in as it stands while
    # the builds run; S_AUR_SIGINT is Ctrl-C part way through them
    f=$root/etc/sudoers.d/90-arch-quickstart-install
    [[ -e $f ]] && echo "sudoers-during-script: $(cat "$f")" >> /root/calls.log
    if [[ "${S_AUR_SIGINT:-0}" == 1 ]]; then kill -INT "$PPID"; exit 130; fi
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

# The chroot-aware setup scripts install_extras runs. Each logs its name,
# arguments and CHROOT_TARGET, and whether the temporary sudo rule is there
# while it runs; one in S_SETUP_FAIL fails, one in S_SETUP_SIGINT gets
# Ctrl-C (which reaches the installer too)
if [[ "$SCEN" == ext-* ]]; then
    for s in bluetooth-setup printer-setup firewall-setup nvidia-setup intel-setup amd-setup; do
        printf '%s\n' '#!/bin/bash' 'n=$(basename "$0")' \
            'echo "setup $n $* CHROOT_TARGET=$CHROOT_TARGET" >> /root/calls.log' \
            '[[ -f /mnt/etc/sudoers.d/90-arch-quickstart-install ]] && echo "sudoers during $n" >> /root/calls.log' \
            '[[ " ${S_SETUP_SIGINT:-} " == *" $n "* ]] && { kill -INT "$PPID"; exit 130; }' \
            '[[ " ${S_SETUP_FAIL:-} " != *" $n "* ]]' > "/usr/local/bin/$s"
        chmod +x "/usr/local/bin/$s"
    done
fi

# Scenario knobs
case "$SCEN" in
    aur-online-all-ok)                have_yay ;;
    aur-online-sync-fails)            have_yay; export S_CHROOT_FAIL="pacman -Syu --noconfirm" ;;
    aur-online-one-fails)             have_yay; export S_YAY_FAIL_PKGS="pkg2" ;;
    aur-online-bootstrap-ok)          : ;;  # no yay stub; git+makepkg succeed
    aur-online-bootstrap-git-fails)   export S_GIT_FAIL=1 ;;
    aur-online-bootstrap-mkpkg-fails) export S_MAKEPKG_FAIL=1 ;;
    aur-offline-one-fails)            export S_PACMAN_FAIL_PKGS="pkg2" ;;
    aur-online-ctrl-c)                have_yay; export S_AUR_SIGINT=1
                                      # the shipped list: its advice must fold
                                      cp "$AUR_LIST" /root/aur-packages.x86_64 ;;
    aur-online-bootstrap-ctrl-c)      export S_AUR_SIGINT=1 ;;  # no yay yet
    aur-offline-ctrl-c)               export S_PACMAN_SIGINT_PKGS="pkg1" ;;
    ext-all-ok)                       : ;;
    ext-one-fails)                    export S_SETUP_FAIL="printer-setup nvidia-setup" ;;
    ext-ctrl-c)                       export S_SETUP_SIGINT="bluetooth-setup" ;;
    ext-offline)                      : ;;
    cfg-post-grub-fails)              export S_CHROOT_FAIL="systemctl enable greetd" ;;
    cfg-post-grub-write-fails)        touch /mnt/etc/greetd ;;  # a file: no config.toml in it
    cfg-pre-grub-fails)               export S_CHROOT_FAIL="mkinitcpio -P" ;;
    cfg-minimal)                      : ;;
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
    dot-remote-fails)                 # the clone fails: no chezmoi config, no source .git
                                      mkstub curl 'exit 0'
                                      export S_CHEZMOI_RC=1 S_CHEZMOI_CONFIG=0 \
                                          S_GUM_INPUT=https://github.com/jakeb-grant/dotfiles.git ;;
    dot-exit-cleanup)                 : ;;
    spine)                            : ;;
    fin-*)                            mkdir -p /mnt/etc /mnt/var/log
                                      mkstub curl 'exit 0'
                                      echo '[offline]' > /mnt/etc/pacman.conf ;;&
    fin-notes)                        export S_CHROOT_FAIL="pacman -Sy --noconfirm" ;;
    fin-*)                            : ;;
    review-install)                   export S_GUM_CHOOSE="Install on /dev/vda" S_GUM_INPUT=vda ;;
    review-wrong-name)                export S_GUM_CHOOSE="Install on /dev/vda" \
                                          S_GUM_INPUT="vdb|sda|/dev/vda1" ;;
    review-quit)                      export S_GUM_CHOOSE="Quit, nothing written" ;;
    review-change)                    # back to machine, a new GPU and rule, then install
                                      export S_GUM_CHOOSE="Change machine|amd-setup (AMD)|HTTP/HTTPS (ports 80, 443)|Install on /dev/vda" \
                                          S_GUM_INPUT=/dev/vda ;;
    review-typo)                      export S_GUM_CHOOSE="Install on /dev/vda" S_GUM_INPUT="vdb|vda" ;;
    review-esc)                       export S_GUM_CHOOSE="Install on /dev/vda" S_GUM_INPUT=ESC ;;
    review-change-you)                # back to you, then machine, Enter on every
                                      # answer (pre-filled, or the confirm's
                                      # default), then install
                                      export S_GUM_CHOOSE="Change you|Change machine|KEEP|KEEP|Install on /dev/vda" \
                                          S_GUM_CONFIRM="DEF|DEF|DEF" \
                                          S_GUM_INPUT="KEEP|KEEP|pw|pw|pe|pe|KEEP|KEEP|vda" ;;
    review-keep-disk)                 # back to the disk, Enter on the cursor, yes at "Erase?"
                                      export S_GUM_CHOOSE="Change the disk|KEEP|Install on /dev/vda" \
                                          S_GUM_INPUT=vda ;;
    review-change-disk)               # back to the disk, pick another, Cancel at "Erase?"
                                      export S_GUM_CHOOSE="Change the disk|/dev/vdb  10G QEMU HARDDISK|Install on /dev/vda" \
                                          S_GUM_CONFIRM=no S_GUM_INPUT=vda ;;
    ask-password-retry)               # empty, then a mismatch, then a match
                                      export S_GUM_INPUT="testhost|testuser||pw|nope|pw|pw|Test User|test@example.com" ;;
    ask-password-fails)               export S_GUM_INPUT="testhost|testuser|a|b|c|d|e|f" ;;
    err-card|err-heredoc|err-cancel)  : ;;
    base-*)                           # pacstrap "installs" coreutils; the
                                      # count after it is pacman's, or fails
                                      printf '%s\n' base linux grub > /root/target-packages.x86_64
                                      mkstub pacman-key 'exit 0'
                                      mkstub pacstrap 'echo "pacstrap $*" >> /root/calls.log
mkdir -p /mnt/usr/bin; touch /mnt/usr/bin/ln; chmod +x /mnt/usr/bin/ln'
                                      mkstub pacman 'echo "pacman $*" >> /root/calls.log
if [[ "$1" == -r ]]; then
  [[ "${S_COUNT_FAIL:-0}" == 1 ]] && exit 1
  for i in $(seq 1284); do echo "p$i"; done
fi
exit 0' ;;&
    base-count-fails)                 export S_COUNT_FAIL=1 ;;
    base-*)                           : ;;
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
want_line() { grep -qxF -- "$1" "$OUT" || fail "no output line exactly: $1"; }
# want_note "WHAT|FIX": the step carried this note to the finish receipt
want_note() { grep -qxF -- "$1" "$NOTES_OUT" || fail "no note: $1"; }
no_notes() { [[ -s $NOTES_OUT ]] && fail "unexpected note(s): $(tr '\n' ' ' < "$NOTES_OUT")"; return 0; }
# cmd_after HEADING: the command print_cmd folded under the line HEADING,
# unfolded back to one line
cmd_after() {
    awk -v h="$1" 'f && /^  / { l = $0; sub(/^ +/, "", l); c = sub(/ \\$/, "", l)
                               printf "%s%s", l, (c ? " " : "\n"); if (!c) exit; next }
                   $0 == h { f = 1 }' "$OUT"
}
marker=/mnt/home/testuser/.aur-failed

case "$SCEN" in
    aur-online-all-ok)
        want_rc0
        want "── AUR builds ──"
        want "── AUR 2/2 · pkg2 ──"
        want "── ■ 2 of 2 built ──"
        want "■ AUR packages installed"
        want_not "failed to build/install"
        no_notes
        want_not "ERROR: Command failed"
        [[ -e $marker ]] && fail ".aur-failed left behind"
        # the builds start from fresh sync databases, refreshed before yay
        want "databases up to date"
        first_yay=$(grep -n "yay\|install-aur" "$CALLS" | head -n 1 | cut -d: -f1)
        sync=$(grep -n "^arch-chroot /mnt pacman -Syu --noconfirm$" "$CALLS" | head -n 1 | cut -d: -f1)
        [[ -n $sync && -n $first_yay && $sync -lt $first_yay ]] \
            || fail "pacman -Syu did not run in the target before the AUR builds"
        true ;;
    aur-online-sync-fails)
        # a refresh that fails warns; the builds still run, nothing aborts
        want_rc0
        want "── ! not refreshed"
        want "Could not refresh the package databases - some AUR builds may fail"
        want "── ■ 2 of 2 built ──"
        want_not "ERROR: Command failed" ;;
    aur-online-one-fails)
        want_rc0
        want "1 AUR package failed to build/install"
        want "── ! 1 of 2 built ──"
        want "  - pkg2"
        want_line "   ! After rebooting, install manually with:"
        want_line "     yay -S pkg2"
        # U17: no success line after a failure; the rule says "1 of 2"
        want_not "AUR packages installed"
        want_note "pkg2 didn't build|yay -S pkg2"
        want_not "ERROR: Command failed"
        [[ -e $marker ]] && fail ".aur-failed left behind" ;;
    aur-online-bootstrap-ok)
        want_rc0
        want "■ AUR packages installed"
        want_not "skipped"
        want_not "failed to build/install"
        want_not "ERROR: Command failed"
        [[ -e $marker ]] && fail ".aur-failed left behind" ;;
    aur-online-bootstrap-git-fails|aur-online-bootstrap-mkpkg-fails)
        want_rc0
        want "all AUR packages were skipped"
        want_line "   ! After rebooting, install yay and run:"
        want_line "     yay -S pkg1 pkg2"
        want_note "no AUR apps: install yay, then run|yay -S pkg1 pkg2"
        want_not "ERROR: Command failed"
        [[ -e $marker ]] && fail ".aur-failed left behind" ;;
    aur-offline-one-fails)
        want_rc0
        want "Failed to install pkg2"
        want "── AUR 1/2 · pkg1 ──"
        want "── ! 1 of 2 installed ──"
        want_line "   ! After rebooting, install manually with:"
        want_line "     yay -S pkg2"
        want_not "AUR packages installed"
        want_note "pkg2 didn't install|yay -S pkg2"
        want_not "ERROR: Command failed" ;;
    aur-online-ctrl-c)
        # F1: Ctrl-C ends the AUR builds, never the (bootable) install
        want_rc0
        want "The AUR step stopped before it finished"
        want "── ! stopped early ──"
        want_line "   ! After rebooting, run:"
        # the shipped list, folded within 79 columns (checked for every
        # scenario below), unfolds back to the whole command
        expect="yay -S --needed $(grep -v '^[[:space:]]*#' "$AUR_LIST" | xargs)"
        [[ "$(cmd_after "   ! After rebooting, run:")" == "$expect" ]] \
            || fail "advice is not: $expect"
        (( $(grep -c ' \\$' "$OUT") >= 1 )) || fail "the shipped list's advice did not fold"
        want_note "the AUR step stopped early|$expect"
        want_not "all AUR packages were skipped"
        want_not "ERROR: Command failed"
        [[ -e $marker ]] && fail ".aur-failed left behind"
        [[ -e /mnt/home/testuser/install-aur.sh ]] && fail "install-aur.sh left behind" ;;
    aur-online-bootstrap-ctrl-c)
        # Ctrl-C before yay is installed: advise the bootstrap, not a yay
        # command that cannot run
        want_rc0
        want "all AUR packages were skipped"
        want_line "   ! After rebooting, install yay and run:"
        want_line "     yay -S pkg1 pkg2"
        want_note "no AUR apps: install yay, then run|yay -S pkg1 pkg2"
        want_not "The AUR step stopped before it finished"
        want_not "ERROR: Command failed"
        [[ -e $marker ]] && fail ".aur-failed left behind" ;;
    aur-offline-ctrl-c)
        # F1: Ctrl-C skips the package installing; the rest still install
        want_rc0
        want "Failed to install pkg1"
        want_line "   ! After rebooting, install manually with:"
        want_line "     yay -S pkg1"
        want_not "ERROR: Command failed"
        grep -q "pacman -S --noconfirm pkg2$" "$CALLS" || fail "pkg2 not installed after Ctrl-C on pkg1" ;;
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
        want_note "check swap is on (it failed in the installer)|swapon --show"
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
        want "1 user install failed: b"
        want "── ! 1 of 2 installed ──"
        want_line "   ! After rebooting, run:"
        [[ "$(cmd_after "   ! After rebooting, run:")" == "user-installs-setup b" ]] \
            || fail "advice is not: user-installs-setup b"
        want_not "User installs done"
        want_note "b didn't install|user-installs-setup b"
        want_not "ERROR: Command failed"
        grep -qx "a ran PAYLOAD= pwd=/mnt/home/testuser" "$log" || fail "a did not run in ~ without a payload"
        grep -q "^b ran" "$log" || fail "b never ran" ;;
    ui-offline-payload)
        log=/mnt/home/testuser/hooks.log
        want_rc0
        want "User installs done"
        want "── user installs ──"
        want "── user install 1/2 · a ──"
        want "── ■ 2 of 2 installed ──"
        want_not "failed"
        grep -qx "a ran PAYLOAD=/mnt/var/tmp/user-installs-payloads/a pwd=/mnt/home/testuser" "$log" \
            || fail "a did not get its staged payload"
        grep -qx "blob" "$log" || fail "a's payload was empty"
        grep -qx "b ran PAYLOAD= pwd=/mnt/home/testuser" "$log" || fail "b (no payload) got one"
        grep -q "chown -R testuser: /var/tmp/user-installs-payloads" "$CALLS" || fail "payload not chowned in the chroot"
        [[ -e /mnt/var/tmp/user-installs-payloads ]] && fail "staged payloads left in the target" ;;
    dot-preloaded-ok)
        want_rc0
        want "■ Dotfiles applied"
        no_notes
        want "Welcome back. This one needs you."
        want "── chezmoi ──"
        want "── ■ chezmoi finished ──"
        grep -q -- "chezmoi-args: .*sudo -u testuser -H env ARCH_QUICKSTART_INSTALL=1 chezmoi init --apply --keep-going$" "$CALLS" \
            || fail "chezmoi not run as the user with -H, ARCH_QUICKSTART_INSTALL and --keep-going"
        grep -qx "sudoers-during: testuser ALL=(ALL:ALL) NOPASSWD: ALL" "$CALLS" || fail "no temporary sudoers while chezmoi ran"
        want_not "SUDOERS LEFT AFTER STEP" ;;
    dot-preloaded-fails)
        want_rc0
        want "Some dotfiles did not apply. After rebooting, run: chezmoi apply"
        want "── ! chezmoi exited with 1 ──"
        want_not "Dotfiles applied"
        # the retry survives the next clear: carried to the finish receipt
        want_note "some dotfiles did not apply|chezmoi apply"
        want_not "ERROR: Command failed"
        want_not "SUDOERS LEFT AFTER STEP" ;;
    dot-init-fails)
        want_rc0
        want "After rebooting, run: chezmoi init --apply"
        want_note "the dotfiles did not apply|chezmoi init --apply"
        want_not "SUDOERS LEFT AFTER STEP" ;;
    dot-ctrl-c)
        want_rc0
        want "After rebooting, run: chezmoi init --apply"
        want "INT trap after step: trap -- 'exit 130' SIGINT"
        want_not "SUDOERS LEFT AFTER STEP"
        want_not "ERROR: Command failed" ;;
    dot-remote-fails)
        # the retry names the repo, on its own line (a long URL stays
        # within 79 columns, checked for every scenario below)
        want_rc0
        want_line "   ! After rebooting, run:"
        [[ "$(cmd_after "   ! After rebooting, run:")" == "dotfiles-setup $S_GUM_INPUT" ]] \
            || fail "advice is not: dotfiles-setup $S_GUM_INPUT"
        want_note "the dotfiles are not set up|dotfiles-setup $S_GUM_INPUT"
        want_not "Dotfiles applied"
        want_not "SUDOERS LEFT AFTER STEP" ;;
    dot-exit-cleanup)
        [[ $rc -eq 1 ]] || fail "exit code $rc, expected 1"
        [[ -e /mnt/etc/sudoers.d/90-arch-quickstart-install ]] && fail "on_exit left the temporary sudoers behind" ;;
    ui-none)
        want_rc0
        want "No user installs"
        grep -q user-installs-setup "$CALLS" && fail "runner called with no user installs" ;;
    ext-all-ok)
        want_rc0
        want "Bluetooth configured"
        want "Printing configured"
        want "Firewall configured"
        want "GPU drivers configured"
        want "Additional components installed"
        want "── ■ 4 of 4 set up ──"
        want "CHROOT_TARGET after step: "
        want_not "CHROOT_TARGET after step: /mnt"
        grep -qx "setup firewall-setup --ssh --kdeconnect CHROOT_TARGET=/mnt" "$CALLS" \
            || fail "firewall-setup not run with the chosen rules in chroot mode"
        grep -qx "setup nvidia-setup  CHROOT_TARGET=/mnt" "$CALLS" || fail "nvidia-setup not run"
        # online, nvidia-setup's legacy path builds from the AUR as the
        # user: the temporary sudo rule is there for it, and only for it
        grep -qx "sudoers during nvidia-setup" "$CALLS" \
            || fail "no temporary sudo rule while nvidia-setup ran online"
        grep -E "^sudoers during (bluetooth|printer|firewall)-setup" "$CALLS" \
            && fail "the temporary sudo rule was there for a script that needs none"
        true ;;
    ext-offline)
        # offline the driver comes from the ISO's repo, as root: no sudo rule
        want_rc0
        want "GPU drivers configured"
        grep -q "^sudoers during" "$CALLS" && fail "a temporary sudo rule was granted offline"
        true ;;
    ext-one-fails)
        # F2: a failing setup script warns; the rest still run
        want_rc0
        want "printer-setup failed"
        want "nvidia-setup failed"
        want "2 setup scripts failed."
        want "── ! 2 of 4 set up ──"
        want_line "   ! After rebooting, run:"
        want_line "     printer-setup"
        want_line "     nvidia-setup"
        want_note "2 setup scripts failed|printer-setup; nvidia-setup"
        want "Bluetooth configured"
        want "Firewall configured"
        want_not "Printing configured"
        want_not "GPU drivers configured"
        want_not "Additional components installed"
        want_not "ERROR: Command failed" ;;
    ext-ctrl-c)
        # Ctrl-C stops the setup script running, not the installer
        want_rc0
        want "bluetooth-setup failed"
        want_line "     bluetooth-setup"
        want "Printing configured"
        want "GPU drivers configured"
        want_not "ERROR: Command failed" ;;
    cfg-post-grub-fails)
        # F2: after GRUB, a failing command warns and the step carries on
        want_rc0
        want "Could not enable greetd"
        want_note "greetd is not enabled|sudo systemctl enable greetd"
        want_not "Could not enable iwd"
        want_not "Could not write"
        # the step still reaches its checkpoint, which only GRUB earns
        want "testhost can boot on its own now."
        want_line "BOOTABLE=1 GREETER_OK=0"
        want_not "ERROR: Command failed"
        grep -q "grub-mkconfig" "$CALLS" || fail "grub-mkconfig never ran"
        [[ -s /mnt/etc/greetd/config.toml ]] || fail "greetd config not written after the failure"
        [[ -x /mnt/usr/local/bin/firewall-setup ]] || fail "setup scripts not copied after the failure" ;;
    cfg-post-grub-write-fails)
        # F2: a config file that cannot be written after GRUB warns too
        want_rc0
        want "Could not write /etc/greetd/config.toml"
        want "testhost can boot on its own now."
        want_line "BOOTABLE=1 GREETER_OK=0"
        want_not "ERROR: Command failed"
        [[ -s /mnt/etc/iwd/main.conf ]] || fail "iwd config not written after the failure"
        [[ -x /mnt/usr/local/bin/firewall-setup ]] || fail "setup scripts not copied after the failure" ;;
    cfg-minimal)
        # the minimal system has no greetd: none set up, none noted
        want_rc0
        want "testhost can boot on its own now."
        want_line "BOOTABLE=1 GREETER_OK=0"
        want_not "greetd"
        no_notes
        grep -q "systemctl enable greetd" "$CALLS" && fail "enabled greetd on the minimal system"
        grep -q "systemctl enable iwd" "$CALLS" || fail "iwd not enabled"
        [[ -e /mnt/etc/greetd ]] && fail "greetd config written on the minimal system"
        [[ -s /mnt/etc/iwd/main.conf ]] || fail "iwd config not written" ;;
    cfg-pre-grub-fails)
        # ...but before GRUB a failure still aborts: the disk would not boot
        [[ $rc -ne 0 ]] || fail "exit code 0, expected a failure"
        want "ERROR: Command failed"
        want_not "can boot on its own"
        grep -q "grub-install" "$CALLS" && fail "grub-install ran after a failed mkinitcpio"
        # the card's guess goes by what failed: here, the initramfs
        want "× stopped at 7 of 10 · system"
        want "the boot loader or initramfs could not be set up" ;;
    fin-clean|fin-notes|fin-many)
        rep=/mnt/home/testuser/install-report.txt
        want_rc0
        want "testhost is ready. Welcome home, testuser."
        want "/dev/vda · btrfs · encrypted"
        want "saved to ~/install-report.txt"
        want_not "ERROR: Command failed"
        want_not "MAIN TAIL NOT FOUND"
        # the receipt fits 80x25: 22 rows before the 3 of gum confirm
        r=$(awk '$0 == "CLEAR" { n = 0; next } $0 == "Reboot now?" { print n; exit } { n++ }' "$OUT")
        [[ -n $r && $r -le 22 ]] || fail "the receipt takes ${r:-?} rows before the prompt, more than 22"
        # the reboot path is unchanged: swap off, unmount, reboot
        so=$(grep -n '^swapoff' "$CALLS" | head -1 | cut -d: -f1)
        um=$(grep -nx 'umount -R /mnt' "$CALLS" | head -1 | cut -d: -f1)
        [[ -n $so && -n $um && $so -lt $um ]] || fail "swapoff (${so:-none}) not before umount -R /mnt (${um:-none})"
        grep -qx reboot "$CALLS" || fail "reboot never called"
        # the offline repo is gone from the target's pacman.conf
        grep -qx '\[core\]' /mnt/etc/pacman.conf || fail "pacman.conf not restored"
        grep -q offline /mnt/etc/pacman.conf && fail "pacman.conf still lists the offline repo"
        # U18: the report on the target, plain, the user's copy chowned
        [[ -s /mnt/var/log/arch-quickstart-install.txt ]] || fail "no install log on the target"
        [[ -s $rep ]] || fail "no install report in the user's home"
        grep -q $'\e' "$rep" && fail "colour escapes in the report"
        grep -q "chown testuser: /home/testuser/install-report.txt" "$CALLS" \
            || fail "report not chowned in the chroot" ;;&
    fin-clean)
        # two spaces between chapters would pass 79 here: one each
        want "prepare 0:21 base 6:41 system 2:05 apps 12:34 extras 0:48 dotfiles skipped"
        grep -qE "built in  21m 4[78]s" "$OUT" || fail "output missing: built in  21m 47s"
        want "Hyprland · 1,284 packages · no dotfiles"
        want "■ Nothing left to do. Clean run."
        want "SUPER+Enter terminal"
        want "System configured for online updates"
        want "After the reboot, log in as testuser. Hyprland starts on its own."
        grep -qx "Nothing left to do. Clean run." "$rep" || fail "report not clean"
        # the times start at prepare: the questions are not install time
        grep -q "^chapters  prepare 0:21  base 6:41" "$rep" || fail "report's chapter times do not start at prepare"
        grep -qx "After the reboot, log in as testuser. Hyprland starts on its own." "$rep" \
            || fail "report misses the login line" ;;
    fin-notes)
        # the restore's own failure, noted at its site, and a carried note
        want "Could not sync package databases"
        want "Two things to finish after you reboot:"
        want "! hyprshot didn't build"
        want "yay -S hyprshot"
        want "! the package databases are not synced"
        want "sudo pacman -Syu"
        want_not "Nothing left to do"
        want_not "SUPER+Enter"
        want_not "System configured for online updates"
        grep -qx "  yay -S hyprshot" "$rep" || fail "report misses a note's command" ;;
    fin-many)
        # eight notes: the padding and the times give way, long commands are
        # cut to a row and the rest summed up; the report keeps them whole
        want "Eight things to finish after you reboot:"
        want "dotfiles applied"
        want_not "prepare 0:21"
        want "! the AUR step stopped early"
        want "more in ~/install-report.txt"
        # greetd is not set up: log in, but no claim that Hyprland starts
        want "After the reboot, log in as testuser."
        want_not "starts on its own"
        grep -qx "After the reboot, log in as testuser." "$rep" || fail "report claims a greeter"
        expect="yay -S --needed $(grep -v '^[[:space:]]*#' "$AUR_LIST" | xargs)"
        grep -qxF "  $expect" "$rep" || fail "report cut the AUR command"
        grep -qxF "! check swap is on (it failed in the installer)" "$rep" || fail "report misses the last note" ;;
    review-*|ask-*)
        want_not "PARTITION CALLED"
        grep -qE '^(wipefs|parted)' "$CALLS" && fail "a disk tool ran before the gate"
        want_not "ERROR: Command failed"
        # a typo is never a failure card
        want_not "× stopped at" ;;&
    review-*)
        want_line "TOUCHED=0"
        want "4 of 10 · review"
        want "Nothing has been written yet. Here's the plan."
        want "/dev/vda  20G  QEMU HARDDISK"
        want "EFI 512M · btrfs (5 subvolumes) · 4G swapfile · encrypted"
        want "testhost · user testuser · UTC"
        want "Test User <test@example.com>"
        want "then, on its own: prepare · base · system · apps · extras"
        want "it asks again at: dotfiles" ;;&
    review-install|review-typo|review-change|review-change-you|review-change-disk|review-keep-disk)
        # the right name: the gate opens, review_plan returns, nothing written
        want_rc0
        want "Everything on /dev/vda will be erased. There is no undo."
        want_line "vda      20G"
        want "Type the disk's name to erase it."
        want "past the point of no return · writing to /dev/vda"
        want "REVIEW RETURNED"
        # exactly one gate, in main: the review is the step right before
        # partition_disk, which nothing else calls
        calls=$(grep -E '^[^#]*\<partition_disk\>' "$INSTALLER" | grep -v 'partition_disk()')
        [[ $(wc -l <<< "$calls") -eq 1 && $calls == *"step prepare;"* ]] \
            || fail "partition_disk is called other than once, from step prepare: $calls"
        prev=$(awk '/^main\(\)/ { m = 1 } m && /^ *step / { if (/partition_disk/) { print p; exit } p = $0 }' "$INSTALLER")
        [[ $prev =~ ^\ *step\ review\;\ +review_plan$ ]] \
            || fail "the step before partition_disk is not the review: $prev" ;;&
    review-install)
        want "graphics   nvidia (hybrid) · firewall deny all + SSH"
        want_not "Those didn't match" ;;
    review-typo)
        # U20: a wrong name asks again, then the right one opens the gate
        [[ $(grep -c "Those didn't match. Try again (Esc cancels)." "$OUT") -eq 1 ]] \
            || fail "expected one re-ask" ;;
    review-change)
        # back through machine, then the card again with the new answers
        [[ $(grep -c "Nothing has been written yet" "$OUT") -eq 2 ]] || fail "the card did not come back"
        # the review masthead: both cards, then the erase screen
        [[ $(grep -c "4 of 10 · review" "$OUT") -eq 3 ]] || fail "the review masthead did not come back"
        want "3 of 10 · machine"
        want "graphics   amd · firewall deny all + HTTP/HTTPS" ;;
    review-change-you)
        # back through you and machine: the card each time, every answer
        # kept by Enter, not reset to the defaults (the hostname and
        # username pre-filled, encryption and its own passphrase, the
        # timezone, the git ones, the GPU and both openings)
        want "2 of 10 · you"
        want "3 of 10 · machine"
        [[ $(grep -c "Nothing has been written yet" "$OUT") -eq 3 ]] || fail "the card did not come back"
        [[ $(grep -c "testhost · user testuser · UTC" "$OUT") -eq 3 ]] \
            || fail "the hostname, username or timezone was not kept from the review"
        want "Keep timezone (UTC)?"
        [[ $(grep -c "· encrypted" "$OUT") -eq 3 ]] || fail "encryption was not kept"
        want "Confirm encryption passphrase:"
        [[ $(grep -c "Test User <test@example.com>" "$OUT") -eq 3 ]] \
            || fail "the git answers were not kept"
        [[ $(grep -c "graphics   nvidia · firewall deny all + SSH + HTTP/HTTPS" "$OUT") -eq 3 ]] \
            || fail "the GPU or the firewall openings were not kept" ;;
    review-keep-disk)
        # the chooser starts on the disk picked before, so Enter keeps it
        want "1 of 10 · disk"
        want_not "No disk selected."
        [[ $(grep -c "Nothing has been written yet" "$OUT") -eq 2 ]] || fail "the card did not come back" ;;
    review-change-disk)
        # Cancel at the soft "Erase?" goes back to the review, old disk kept
        want "1 of 10 · disk"
        want "Everything on /dev/vdb will be erased."
        want_not "Installation cancelled by user."
        # the card's disk row would read so had vdb been kept (the lsblk
        # stub sizes every disk 20G)
        want_not "/dev/vdb  20G"
        [[ $(grep -c "Nothing has been written yet" "$OUT") -eq 2 ]] || fail "the card did not come back" ;;
    review-wrong-name)
        # three wrong names: a die before the disk, with the pause
        [[ $rc -eq 1 ]] || fail "exit code $rc, expected 1"
        [[ $(grep -c "Those didn't match. Try again (Esc cancels)." "$OUT") -eq 2 ]] \
            || fail "expected two re-asks before the die"
        want "× ERROR: That isn't the disk's name. Nothing was written."
        want "Press Enter to exit..."
        want_not "past the point of no return"
        want_not "REVIEW RETURNED" ;;
    review-quit)
        want_rc0
        want "No problem, nothing was written."
        want_not "Everything on /dev/vda will be erased"
        want_not "REVIEW RETURNED" ;;
    review-esc)
        # Esc at the typed name: a clean cancel, no pause
        [[ $rc -eq 130 ]] || fail "exit code $rc, expected 130"
        want "Stopped. Nothing was written to any disk."
        want_not "Press Enter to exit..."
        want_not "past the point of no return"
        want_not "REVIEW RETURNED" ;;
    ask-password-retry)
        # U20: empty, then a mismatch, each re-asked; the third try holds
        want_rc0
        want "That was empty. Try again (Esc cancels)."
        [[ $(grep -c "Those didn't match. Try again (Esc cancels)." "$OUT") -eq 1 ]] \
            || fail "expected one mismatch re-ask"
        want_line "PASSWORD SET"
        # the summary and its confirm moved to the review card
        want_not "Configuration summary"
        want_not "Proceed with these settings?" ;;
    ask-password-fails)
        # three mismatches: the old die, before any disk is touched
        [[ $rc -eq 1 ]] || fail "exit code $rc, expected 1"
        [[ $(grep -c "Those didn't match. Try again (Esc cancels)." "$OUT") -eq 2 ]] \
            || fail "expected two re-asks before the die"
        want "× ERROR: Passwords do not match."
        want_not "PASSWORD SET" ;;
    err-card)
        # U21: the ERROR line first and verbatim, then cleanup, the card,
        # and the pause; the exit code is the failure's
        [[ $rc -eq 1 ]] || fail "exit code $rc, expected 1"
        want "ERROR: Command failed at line"
        want "× stopped at 6 of 10 · base system"
        want "grep -q never-there /dev/null"
        want "a download failed: check the network"
        want "/dev/vda may be partly written, now unmounted"
        e=$(grep -n "ERROR: Command failed" "$OUT" | head -1 | cut -d: -f1)
        c=$(grep -n "Cleaning up" "$OUT" | head -1 | cut -d: -f1)
        k=$(grep -n "× stopped at" "$OUT" | head -1 | cut -d: -f1)
        p=$(grep -n "Press Enter to exit" "$OUT" | head -1 | cut -d: -f1)
        [[ -n $e && -n $c && -n $k && -n $p ]] && (( e < c && c < k && k < p )) \
            || fail "order is not ERROR ($e), cleanup ($c), card ($k), pause ($p)"
        # the line the ERR line names is the failing command's own
        n=$(sed -n 's/.*ERROR: Command failed at line \([0-9]*\): grep -q never-there.*/\1/p' "$OUT")
        [[ $(sed -n "${n:-0}p" "$SELF") == *"grep -q never-there /dev/null"* ]] \
            || fail "the ERR line's number ($n) is not the failing line" ;;
    err-heredoc)
        # the card keeps the command's first line: every card line is a
        # box line, and the body is printed once (by the verbatim ERROR)
        [[ $rc -eq 1 ]] || fail "exit code $rc, expected 1"
        want "ERROR: Command failed at line"
        want "× stopped at 7 of 10 · system"
        want "failed   line "
        want "> /nonexistent/hosts <<EOF"
        want "a late setup step: the lines above say what"
        want "testhost already boots on its own"
        card=$(awk '/^   ┌/ { b = 1 } b { print } b && /^   └/ { exit }' "$OUT")
        [[ $(wc -l <<< "$card") -eq 7 ]] || fail "the card is not 7 lines: $card"
        grep -qv '^   [┌│└]' <<< "$card" && fail "a card line is not a box line: $card"
        [[ $(grep -c "127.0.0.1   localhost" "$OUT") -eq 1 ]] || fail "the heredoc body leaked into the card" ;;
    err-cancel)
        # Ctrl-C after the disk was touched: cleanup, then out, no card
        [[ $rc -eq 130 ]] || fail "exit code $rc, expected 130"
        want "Cleaning up"
        want_not "× stopped at"
        want_not "Press Enter to exit..." ;;
    base-online|base-count-fails)
        # The pacstrap frame: what is about to happen, the step-away line,
        # pacman's own output between the rules, the real total after it
        want_rc0
        want "6 of 10 · base system"
        want "Downloading and installing 3 packages plus dependencies."
        want "── pacstrap"
        want "pacman's (n/N) counter below is the real progress bar."
        want "Nothing to answer until dotfiles."
        want "■ Base system installed"
        want_not "ERROR: Command failed"
        grep -qx "pacman -Sy" "$CALLS" || fail "databases not synced before pacstrap"
        grep -qx "pacstrap -K /mnt base linux grub" "$CALLS" || fail "pacstrap not given the list"
        [[ $(grep -n -m1 '^pacman -Sy' "$CALLS" | cut -d: -f1) -lt \
           $(grep -n -m1 '^pacstrap' "$CALLS" | cut -d: -f1) ]] || fail "pacstrap ran before the sync" ;;&
    base-online)
        want "── ■ 1,284 packages ──"
        want_line "PKG_COUNT=1284" ;;
    base-count-fails)
        # a count that fails never fails the install: the rule says done
        want "── ■ base system ──"
        want_line "PKG_COUNT=" ;;
    spine)
        # The chapter count comes from the installer's own list
        n=$(sed -n 's/^STEP_COUNT=//p' "$OUT")
        want_rc0
        # main() enters the chapters in CHAPTERS' order, so the count and
        # the tide never disagree with what is running
        eval "$(sed -n '/^CHAPTERS=(/,/)$/p' "$INSTALLER")"
        chapters=$(for c in "${CHAPTERS[@]}"; do printf '%s ' "${c%%=*}"; done)
        main_steps=$(awk '/^main\(\)/ { m = 1 } m && /^ *step / { s = $2; gsub(/[;\047]/, "", s); printf "%s ", s } m && /^}/ { exit }' "$INSTALLER")
        [[ "$main_steps" == "${chapters}done " ]] \
            || fail "main's steps ($main_steps) are not CHAPTERS' order ($chapters) then done"
        want "you answer  disk · you · machine · review"
        want_line "   then        prepare · base · system · apps · extras · dotfiles"
        want "hyprland on arch"
        want "1 of $n · disk"
        want "of $n · prepare disk"
        want "of $n · apps"
        want "hhh… boots on its own"
        want "── user install 10/10 · nnnn"
        want "n… ──"
        # welcome 1, prologue 1, disk 2, prepare 1 (not again once the
        # disk is touched), apps 1, done 1
        c=$(grep -cx CLEAR "$OUT")
        [[ $c -eq 7 ]] || fail "cleared $c times, expected 7"
        want_not "ERROR: Command failed" ;;
esac

# Every step: the temporary sudoers drop-in is gone when the step returns,
# and the installer's own Ctrl-C handling is back (the scenarios that end
# the installer never get there)
want_not "SUDOERS LEFT AFTER STEP"
# tty1 is 80 columns: no printed line may pass 79 (counted in characters by
# bash under a UTF-8 locale; a C locale, or mawk whatever the locale, counts
# bytes, and ■ × · are three each)
# shellcheck disable=SC2016  # expanded by the inner bash
long=$(LC_ALL=C.UTF-8 bash -c 'while IFS= read -r l || [[ -n $l ]]; do
           (( ${#l} > 79 )) && printf "%s\n" "$l"; done; exit 0' < "$OUT")
[[ -z $long ]] || fail "line(s) over 79 columns: ${long:0:120}"
case "$SCEN" in
    dot-exit-cleanup|cfg-pre-grub-fails|review-wrong-name|review-quit|review-esc) ;;
    ask-password-fails|err-card|err-heredoc|err-cancel) ;;
    *) want "INT trap after step: trap -- 'exit 130' SIGINT" ;;
esac
# F3: the online AUR builds run with the temporary passwordless sudo
case "$SCEN" in
    aur-online-*)
        grep -qx "sudoers-during-script: testuser ALL=(ALL:ALL) NOPASSWD: ALL" "$CALLS" \
            || fail "no temporary sudoers while the AUR builds ran" ;;
esac

if (( pass )); then echo "PASS $SCEN"; else echo "FAIL $SCEN"; sed 's/^/    | /' "$OUT"; exit 1; fi
