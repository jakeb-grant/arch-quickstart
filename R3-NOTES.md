# R3 Working Doc — Installer Hardening

Working notes for BACKLOG item R3 ("Decompose the 1,490-line installer monolith").
Target file: `archiso/airootfs/usr/local/bin/hyprland-install` (1,546 lines as of
commit `fa6e8dd`). Line numbers below refer to that revision.

## Decision

**Harden in place; do NOT split into sourced modules.**

Rationale: the file is already well-sectioned (one function per install phase,
14-line `main()` at 1511). A module split means 6-8 new files under
`airootfs/usr/local/lib`, profiledef permission entries, and sourcing/scoping
risk across a disk-wiping script we cannot integration-test locally (CI ISO
build ≈ 1h; never push). The real R3 problem is the failure path, not the size.
If a module split is ever wanted, it is its own multi-session effort with a
QEMU boot test of a locally built ISO.

## Diagnosis summary

1. **Failure leaves the machine dirty and unrerunnable.** The ERR trap (line 10)
   prints `$LINENO`/`$BASH_COMMAND`, pauses on `read`, exits — no cleanup.
   Failure after formatting leaves `/mnt` + 5 submounts + `/mnt/boot` mounted
   and possibly LUKS `cryptroot` open. A rerun then fails differently
   (`mount: busy`, `btrfs subvolume create: exists`) with no recovery hint.
2. **Cancel is indistinguishable from failure.** Esc/Ctrl-C at any gum
   command-substitution site fires the ERR trap as "ERROR: Command failed".
   Ctrl-C at a `gum confirm` inside an `if` is silently treated as "No"
   (ERR doesn't fire in conditionals) — inconsistent with the above.
3. **Destructive steps mostly trust `set -e` alone.** Only pacstrap has a
   post-check (875). No verification after `cryptsetup open`, `mkfs.*`,
   `grub-install`/`grub-mkconfig`.
4. **`|| true` sites are mostly innocent** (inventory below); only two mask
   anything real, both low-stakes.

## Inventories

### Destructive / point-of-no-return steps

| Line | Step | Notes |
|------|------|-------|
| 685 | `wipefs -af "$DISK"` | Point of no return — set disk-touched flag just before |
| 688-697 | `parted` mklabel/mkpart ×3 + esp flag | wrapped in `gum spin` (swallows output) |
| 700 | `partprobe \|\| true` | benign: followed by `udevadm settle` + device-node wait loop 713-720 |
| 738 | `mkfs.fat -F32 "$EFI_PART"` | no post-check |
| 742 | `cryptsetup luksFormat` (pw via stdin) | |
| 745 | `cryptsetup open … cryptroot` | no check that `/dev/mapper/cryptroot` appeared |
| 751/754 | `mkfs.btrfs -f` | no post-check |
| 780-803 | mount root, create 5 subvolumes, remount all + `/mnt/boot` | state to unwind on failure |
| 860/871 | `pacstrap` (offline/online) | post-check at 875 (`/mnt/usr/bin/ln`) — the model to copy |
| 1112/1119 | swapfile `dd` + `mkswap` | **never `swapon`** during install → cleanup needs no swapoff |
| 987 | `arch-chroot mkinitcpio -P` | |
| 991-992 | `grub-install` + `grub-mkconfig` | no check that EFI binary / grub.cfg landed → "complete" then black screen |
| 1499 | `umount -R /mnt` in `finish()` | only on "Reboot now? yes"; no `cryptsetup close` (fine, rebooting) |

### gum prompt sites

Command-substitution sites — Esc/Ctrl-C → non-zero → assignment fails → ERR trap
(the "scary error on cancel" bug): 320, 328, 399, 420, 438, 445, 456, 463, 481,
487, 501, 510, 513, 632, 653, 1390. Worst offender: **1390** (dotfiles prompt —
cancelling there kills the installer *after* the system is fully installed).

`gum confirm` in if-conditions — Ctrl-C silently = "No" (ERR suppressed in
conditionals): 166, 255, 341, 373, 413, 475, 477, 498, 528, 670, 1343, 1367, 1498.

Retry-recursion sites (re-prompt loops via self-call): `connect_wifi` 342,
`configure_user` 529, `configure_extras` 671.

### `|| true` / masking inventory

| Line | Command | Verdict |
|------|---------|---------|
| 271 | `systemctl start iwd` | benign (may already run) |
| 283, 302 | `iwctl … scan` | benign |
| 550, 553-555 | `lspci \| grep` | benign (grep no-match) |
| 700 | `partprobe` | benign (see above) |
| 1033 | `usermod -aG video greeter` | masks real failure, low stakes → un-mask to `warn` (Section 3) |
| 1308 | `chown` on AUR helper script | masks, low stakes (home exists via `useradd -m`) |
| 1351, 1402 | `chezmoi … \|\| { warn; return; }` | proper handling, keep |
| 1124 | `if ! RESUME_OFFSET=$(btrfs inspect-internal …)` | proper handling — the pattern to imitate |

### Trap / set -e semantics notes (load-bearing for any trap edits)

- `set -eEo pipefail`; `-E` makes the ERR trap inherit into functions.
- bash does **not** expand variables in `$BASH_COMMAND` → the trap's echo cannot
  leak `$PASSWORD`/`$ENCRYPT_PASSWORD` (verified previously; noted in BACKLOG).
  Any trap rewrite must preserve this property.
- ERR does not fire for commands in `if`/`while` conditions or non-final
  `&&`/`||` list members — which is why `gum confirm` cancels are silent.
- `[[ cond ]] && cmd` as the *last* line of a function makes the function
  return 1 under set -e in the caller — mid-function uses at 605/617 are safe
  today; don't move them to function tails.
- Mid-install the trap's `read` runs on the live console; fine (tty present).

## Fix plan (three sections, user gates each)

### Section 1 — cleanup-on-failure infrastructure (~60 lines)

- `DISK_TOUCHED=0` global; set to 1 in `partition_disk` immediately before
  `wipefs` (685).
- **Trap wiring (per review):** cleanup hooks on `EXIT` (gated on flag +
  non-zero exit status) plus `INT TERM` — NOT ERR alone, because `die()` exits
  without firing ERR (called after disk-touched at 719, 876, 1314). The ERR
  trap keeps its current message + Enter-pause + no-expansion `$BASH_COMMAND`;
  cleanup runs from the EXIT trap after it.
- `cleanup_on_failure()` (per review): `trap - ERR; set +e`, then
  `gpgconf --homedir /mnt/etc/pacman.d/gnupg --kill all` (pacstrap's host-side
  gpg-agent pins /mnt), `fuser -km /mnt` if still busy, `umount -R /mnt`
  (retry ×3), `udevadm settle`, `cryptsetup close cryptroot` if the node exists
  (retry ×3). Warn-and-continue on step failure; loud message if state remains.
  Ends with "system unmounted — safe to re-run the installer".
- Idempotent pre-flight at the top of `partition_disk`: umount `/mnt` and close
  `cryptroot` if left over from a previous failed run.
- Redirect all trap output to `>&2` (fixes invisible-freeze + disk-list
  pollution when the trap fires inside `$( )`/`<( )` — exit-review #1/#2).
- No swapoff needed (installer never swapons).

### Section 2 — cancel ≠ error (~25 gum sites)

- Route Esc/Ctrl-C at prompts to a clean "Installation cancelled" exit that
  reuses Section 1 cleanup when `DISK_TOUCHED=1`.
- Mechanism TBD at implementation: small `ask`/`choose` wrappers vs per-site
  `|| cancel` — pick whichever keeps the diff mechanical and reviewable.
- Special care: 1390 (post-install dotfiles prompt) must degrade to "skip
  dotfiles", not cancel the whole install.

### Section 3 — post-step verification + silent-failure fixes (~50 lines)

- After `cryptsetup open`: `[[ -b /dev/mapper/cryptroot ]] || die`.
- After `mkfs.fat`/`mkfs.btrfs`: `blkid` reports expected fstype.
- After the three `sed -i` edits (964/973/982): `grep -q` that the `encrypt`/
  `resume` hooks and `GRUB_CMDLINE_LINUX` value actually landed — highest
  stakes (silent no-match = unbootable encrypted install reported as success).
- After GRUB: `/mnt/boot/EFI/GRUB/grubx64.efi` and `/mnt/boot/grub/grub.cfg`
  exist and are non-empty.
- Revive the dead fallback branches: `|| true` inside the substitutions at
  137, 276, 291, 304 so the existing `[[ -z ]]` handling runs on tool failure.
- `finish()` offline `pacman -Sy` (1461) → `|| warn` (post-install network
  hiccup must not abort a completed install).
- Un-mask 1033 (`usermod`) into an explicit `warn`; plain-echo fallback for
  the gum-missing check (1518).
- All new `die` paths benefit from Section 1 cleanup.

### Section 4 (proposed, from review) — exclude the live-boot device (~10 lines)

- `select_disk` (390) currently lists the USB stick the ISO booted from;
  wiping it destroys the running live system unless copytoram was used.
- Filter out `lsblk -no PKNAME` of the device backing `/run/archiso/bootmnt`
  from the candidate list (keep a warn if that leaves zero disks).
- Optional nicety while here: add `mmcblk` to the disk pattern (390) so
  eMMC-only machines aren't a dead end.

## Validation per section

- `shellcheck --severity=warning -x` (matches CI lint gate) + `bash -n`.
- Scratchpad harness: stub destructive commands (wipefs/parted/mkfs/cryptsetup/
  pacstrap/arch-chroot/gum), source or replay the trap/cleanup/cancel logic,
  simulate: mid-install failure, pre-format cancel, post-format cancel,
  post-install prompt cancel. (Same approach as the L8 grep-fallback sim.)
- Terse ≤2-agent diff review per section → fix real issues → BACKLOG update →
  local commit. **Never push** (CI ISO builds ≈ 1h).

## Review findings (two-agent pass over the current file)

### State-lifecycle agent (verified against arch-install-scripts source)

**Corrections to the Section 1 design — adopted:**

1. **Hook cleanup on `EXIT` (gated on flag + non-zero status) plus `INT TERM`,
   not ERR alone.** `die()` is a plain `exit 1` (line 54), which does NOT fire
   the ERR trap — and `die` is called after disk-touched at 719, 876, 1314.
   Ctrl-C mid-pacstrap is likewise ERR-invisible. Handler must start with
   `trap - ERR; set +e` so a failing umount can't abort the handler itself.
2. **gpg-agent from `pacstrap -K` can pin `/mnt`.** pacstrap runs
   `pacman-key --gpgdir /mnt/etc/pacman.d/gnupg --init` on the *host* (outside
   its PID namespace) and never kills the agent → intermittent
   "target is busy". Cleanup: `gpgconf --homedir /mnt/etc/pacman.d/gnupg
   --kill all` before umount, `fuser -km /mnt` as fallback.
3. **Ordering:** kill holders first (see above), then `umount -R /mnt`
   (retry ×3 — it stops recursing at the first failed branch), `udevadm settle`,
   then `cryptsetup close cryptroot` (retry ×3; udev probing can transiently
   hold the dm node). Avoid `umount -l` (lazy detach keeps close failing while
   looking unmounted). On final failure: print loudly, leave state, don't mask.
4. **Idempotent pre-flight in `partition_disk`:** before wipefs,
   `mountpoint -q /mnt && umount -R /mnt`; `[[ -e /dev/mapper/cryptroot ]] &&
   cryptsetup close cryptroot`. Makes re-run safe even if a prior cleanup
   failed (a held partition otherwise breaks partition re-read + `cryptsetup
   open` "already exists").

**Confirmations:** no swapon/losetup/other-dm anywhere → cleanup scope is
umount + cryptroot only. arch-chroot commands run under `unshare --fork --pid`,
so chroot-spawned daemons die on their own; `umount -R` covers the API mounts.
Re-run after successful cleanup is safe: `mkfs.fat`/`luksFormat`/`mkfs.btrfs -f`
overwrite all stale signatures at identical parted offsets. Interrupted
luksFormat / half-written dd swapfile are fully healed by re-run. The
`grub-install` NVRAM Boot#### entry can't be cleaned but is harmless and
replaced on re-run (same `--bootloader-id=GRUB`).

**New finding outside original R3 scope — proposed as Section 4:**

5. **`select_disk` (390) lists the USB stick the ISO booted from.** Unless the
   user booted with copytoram (not the default boot entry), choosing it means
   wipefs destroys the running live system's backing store mid-install.
   Fix: exclude the archiso device (`lsblk -no PKNAME` of the device backing
   `/run/archiso/bootmnt`) from the disk list.

### Exit-semantics agent

1. **ERR trap writes to stdout (line 10).** With `set -E` the trap fires inside
   `$( )`/`<( )` subshells too, where its output is *captured, not shown*: the
   user sees a frozen screen while the subshell's `read` blocks invisibly,
   then the trap fires a second time in the parent. Fix: redirect the trap's
   echoes to `>&2` (also prevents future cleanup logic running twice inside
   subshells — the EXIT-trap design already avoids that).
2. **`select_disk` procsub can feed trap text into the disk list (390-392).**
   On a machine with only `mmcblk` disks, `grep` exits 1 inside `<( )`,
   pipefail fails the pipeline there, and today `mapfile` captures the trap's
   own error text as "disks" — passing the empty-list guard and offering the
   error message as a selectable disk. The `>&2` fix resolves the pollution;
   an explicit `|| true` inside the procsub lets the intended empty-list `die`
   handle it cleanly. (The pattern's mmcblk omission itself = optional
   Section 4 nicety.)
3. **`sed -i` no-match is silent success (964, 973, 982).** If the stock
   `mkinitcpio.conf` `HOOKS=` or grub `GRUB_CMDLINE_LINUX=""` line ever changes
   format, an encrypted install silently gets no `encrypt` hook / no
   `cryptdevice=` → **unbootable system, installer reports success**. Needs
   `grep -q` post-checks — highest-stakes item in Section 3.
4. **Graceful-fallback branches are dead code for real tool failures
   (137, 276, 291, 304).** pipefail fails the assignment and fires the trap
   *before* the `[[ -z … ]]` fallback checks run (e.g. `iwctl` failure crashes
   instead of reaching `die "No WiFi device found!"`; a bad offline DB crashes
   instead of "skipping validation"). Fix: `|| true` inside those
   substitutions so empty output takes the intended path.
5. **`die()` is a second no-teardown exit path** (719, 876, 1313) — confirms
   the lifecycle agent's finding 1; covered by the EXIT-trap design.
6. **`finish()` offline path: `arch-chroot /mnt pacman -Sy` (1461) is fatal
   under errexit** — a mirror/DNS hiccup *after* the system is fully installed
   aborts via the scary ERR path before the completion banner. Fix: `|| warn`.
7. **`die` itself needs gum (minor, 53 / 1518).** If gum is missing, the
   gum-missing check dies via `gum style`, which fails first — use plain
   `echo` + exit for that one check.

**Checked and clean:** the `[[ ]] &&` guard lists (605/617/715), no
`local x=$(…)` masking anywhere, retry recursions are in then-bodies (errexit
stays live), 1124's `if !` guard is correct, the AURSCRIPT heredoc's inner
`set -e` propagates, arithmetic contexts safe, and `gum spin` propagates exit
codes (the wipefs/parted chain does abort on failure).

### Verification of findings (independent, 2026-07-02)

Empirical sandbox tests (`scratchpad/verify-r3-findings.sh`, all passed):

- ERR trap fires inside `$( )`/`<( )` subshells and its stdout is captured,
  not shown; procsub failure feeds the trap's own text into `mapfile` as
  array elements while the parent continues (**confirms exit #1/#2**); the
  `>&2` fix keeps the array clean so the empty-list guard works.
- Plain `exit 1` does not fire ERR; an EXIT trap gated on non-zero `$?` does
  (**confirms the die() gap + the EXIT-trap design**).
- pipefail + assignment fires the trap before `[[ -z ]]` fallbacks run;
  `|| true` inside the substitution revives them (**confirms exit #4**).
- `sed -i` no-match exits 0 silently (**confirms exit #3**).
- `[[ ]] && cmd` mid-function safe / at function tail fatal under set -e
  (**confirms the semantics note**).

Source/document checks:

- `man umount` (util-linux 2.42.2): `-R` "recursion … will stop if any
  unmount operation in the chain fails for any reason" (**confirms lifecycle
  ordering point**).
- arch-install-scripts upstream (GitHub mirror): `pacman-key --gpgdir
  "$newroot"/etc/pacman.d/gnupg --init` runs on the host; no `gpgconf --kill`
  anywhere (**confirms the gpg-agent /mnt-pinning risk**);
  `pid_unshare="unshare --fork --pid"` wraps arch-chroot/pacman and
  `trap 'chroot_teardown' EXIT` unmounts the API mounts (**confirms
  chroot-daemon safety**).
- gum source (`spin/command.go`): spin returns the wrapped command's exit
  status (**confirms the "cleared" wipefs/parted claim**). Nuance: without
  `--show-error` the failing command's output is hidden — consider adding
  `--show-error` to the spin-wrapped destructive steps in Section 3.
- Repo boot configs: copytoram is boot entry 03 in grub/efiboot/syslinux,
  not the default (**confirms Section 4's live-USB wipe risk**).

Not directly testable here, adopted as harmless design guidance: udev can
transiently hold the dm node during `cryptsetup close` (hence the retry ×3 +
`udevadm settle`); a held partition blocks partition-table re-read on re-run
(moot given the pre-flight).

## Implementation log (2026-07-02)

All sections implemented per plan, each validated by lint at CI severity
(`shellcheck --severity=warning -x` + `bash -n`), scenario harnesses run
against the real code (scratchpad `s1/s2/s4-harness.sh` — paths rewritten
mechanically for rootless testing, commands stubbed), and per-section agent
review. Deviations from / additions to the planned design, all review-driven:

- **S1 (`09463c4`)**: teardown extracted as `teardown_target()` (subshell
  body, so `set +e`/trap changes can't leak) shared by `cleanup_on_failure`
  and the pre-flight — the pre-flight originally lacked the gpgconf/fuser/
  settle mitigations it needs. Exit pause moved from the ERR trap into
  `on_exit` AFTER cleanup (power-cycle at the prompt now still leaves a clean
  machine); pause skipped for rc 130/143. `trap '' INT TERM` during teardown
  (Ctrl-C must not abort it partway). `DISK_TOUCHED=0` before the success-path
  `reboot` (shutdown's SIGTERM must not fire cleanup). TERM exits 143, INT 130.
  10-scenario harness.
- **S2 (`845dd55`)**: wrappers `prompt_input/prompt_choose/prompt_filter`
  (VAR-name first; gum in condition context; `printf -v` assignment works for
  callers' locals via dynamic scoping) + `confirm()` (130 → `cancelled()`).
  Choose/filter items fed via `< <(...)` NOT pipes — a piped wrapper would run
  in a subshell and its `exit 130` couldn't leave the installer. Post-install
  dotfiles prompt degrades to skip, not cancel. 7-scenario harness; review
  LGTM (one comment fix: Esc at confirm is 130 on newer gum).
- **S3 (`d4d9c7a`)**: all planned checks landed; reviewer verified blkid
  returns exactly `vfat`/`btrfs`, `cryptsetup open` blocks on the udev cookie
  (no node race), `/mnt/boot/EFI/GRUB/grubx64.efi` is the exact artifact path,
  and the grep anchors can't false-positive on stock configs. Extra fix from
  review: gum-missing check moved BEFORE the root check in `main()` (the root
  check dies via gum). `--show-error` added to the five destructive `gum spin`
  sites. The `|| true` fallback revivals also fix a latent `head -1` SIGPIPE
  spurious-ERR in the wifi_device pipeline.
- **S4 (`9160d7d`)**: boot-medium exclusion resolves the whole disk with ONE
  inverse-tree call — `lsblk -srno NAME "$boot_src" | tail -1` — after review
  caught (and reproduced on util-linux 2.42.2) that the first-draft PKNAME
  walk infinite-loops: `lsblk -no PKNAME <disk>` prints the whole subtree
  NOT queried-device-first, so `head -1` returns a child. Lesson recorded:
  the harness passed with idealized stubs — stubs must mirror real tool
  output shapes (harness fixed accordingly, and the fix verified against
  real devices). Disk regex tightened with a `[[:space:]]` anchor (adds
  `mmcblk`, excludes `mmcblkXboot0`/`rpmb`); exclusion note gated on the
  medium actually being a would-be candidate. Fails open (copytoram).
  5-scenario harness.

## Status

- [x] State-lifecycle review incorporated
- [x] Exit-semantics review incorporated
- [x] Section 1 — cleanup infrastructure (`09463c4`)
- [x] Section 2 — cancel handling (`845dd55`)
- [x] Section 3 — post-step verification (`d4d9c7a`)
- [x] Section 4 — exclude live-boot device (`9160d7d`; review blocker fixed
      and re-verified before commit)
- [x] BACKLOG.md R3 entry closed 2026-07-02. This doc retained as the R3
      record (referenced from BACKLOG); safe to delete once no longer useful.
