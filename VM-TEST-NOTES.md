# VM Acceptance Test — Findings & Fix Plans (2026-07-03)

Working doc for the fixes coming out of the first real install test of the ISO
(QEMU/OVMF, online variant, CI run 28639461352 artifacts). Follow-up to
`R3-NOTES.md`. Items tracked in `BACKLOG.md` as **V1–V3**.

## Test session summary

Setup: `~/vm-test/` — 40G qcow2 virtio disk, OVMF (pflash CODE+VARS), 12G RAM /
8 cores (first attempt with 4G RAM OOM'd, see V3), QEMU user-net.

What the test proved:

- ✅ **Full encrypted install end-to-end** — partitioning, LUKS, btrfs
  subvolumes, pacstrap, swapfile+hibernation config, GRUB, AUR builds, greetd.
  Produced a bootable system.
- ✅ **ERR-trap + cleanup path fired on a real failure** (R3 Section 1/3
  behavior): when the AUR step failed, the trap reported the exact
  line/command, `cleanup_on_failure` unmounted the target and closed LUKS, and
  the "safe to re-run" + "Press Enter to exit" flow worked exactly as designed.
- ✅ **Re-run on a dirty disk** — second install over the leftovers of the
  failed one proceeded cleanly (pre-flight/teardown path).
- ✅ **No-network path** — clean error + exit when the host briefly lost
  connectivity (Press-Enter-to-exit flow, no hang).
- ✅ **GPU detection UI, Skip path** — worked, but exposed V1.
- ⚠️ Not representative in the VM: boot-medium exclusion (booted from
  `/dev/sr0`, never matches the disk regex — untested in anger) and everything
  involving OVMF NVRAM (see "VM-only boot pain" below).

### VM-only boot pain (NOT repo bugs — context for V2)

Post-install boots failed repeatedly, but every failure traced to QEMU/OVMF
ops, not the installer: `bootindex=0` makes OVMF rewrite BootOrder (demotes the
GRUB entry behind PXE); changing disk attachment syntax between runs moved the
disk's PCI slot so the NVRAM entry no longer resolved; a bare `grub>` prompt
appeared even via the fallback loader (embedded prefix is `(,gpt1)/grub`,
"same disk I booted from" — suspected OVMF boot-device reporting quirk,
unresolved, VM-only). On real hardware, where the disk never changes PCI
address and nothing rewrites BootOrder, install → reboot → GRUB works — the
first-install boot in the VM proved that before the flag churn began.
Takeaway: NVRAM-only bootloader registration is a single point of failure → V2.

---

## V1. GPU detection: `ati` regex matches "compatible" — every machine shows a phantom AMD GPU

**Severity:** 🟠 high (wrong hardware detection on ~every system) · **Verified:** ✅ empirically

**Evidence:** VM showed `AMD: Red Hat, Inc. Virtio 1.0 GPU (rev 01) (discrete)`.
Cause confirmed by hand: `grep -iE 'amd|radeon|ati'` matches the substring
**ati** in "VGA comp**ati**ble controller", present in the lspci line of
virtually every GPU. So `DETECTED_AMD` is set on all systems; on Intel/NVIDIA
machines the menu shows a phantom "amd-setup (AMD … - detected)" entry and the
recommendation logic can be skewed toward AMD.

**Sites (2 real + 1 benign):**
- `archiso/airootfs/usr/local/bin/hyprland-install:734` — `DETECTED_AMD=$(… grep -iE 'amd|radeon|ati' …)`
- `archiso/airootfs/usr/local/lib/setup-common.sh:167` — identical line in `detect_gpus()` (sourced by all 7 setup scripts)
- `amd-setup`/`nvidia-setup`/`intel-setup` use `detect_gpus` from the lib (no
  private copies); `intel-setup:86` has its own *intel* regex — not affected.
  NVIDIA (`grep -i 'nvidia'`) and Intel (`intel.*(graphics|…)`) patterns have
  no in-word false-positive exposure — leave them.

**Fix:** `grep -iE '\b(amd|radeon|ati)\b'` at both sites (GNU grep `\b` word
boundary). Verified against the failing line: no match on
"VGA compatible controller: Red Hat…"; still matches
"Advanced Micro Devices, Inc. [AMD/ATI]", "Radeon RX 7800 XT", bare "ATI".

**Verification plan:** table-driven test — run the new regex against a set of
real lspci one-liners (virtio, NVIDIA-only, Intel iGPU, AMD dGPU [AMD/ATI]
form, AMD APU "Radeon Graphics", old ATI) and assert DETECTED_AMD is
set/unset correctly. Shellcheck + the usual ≤2-agent diff review.

**Effort:** ~15 min. No design decisions.

---

## V2. GRUB registered via NVRAM only — add `--removable` fallback loader

**Severity:** 🟡 medium (robustness; real-hardware recovery path) · **Verified:** ✅ (behavior observed in VM; mechanism is UEFI-spec standard)

**Problem:** `configure_system` runs one `grub-install --bootloader-id=GRUB`
(`hyprland-install:1198`), which writes `EFI/GRUB/grubx64.efi` + an NVRAM boot
entry. If NVRAM is lost or invalidated (CMOS reset, board swap/RMA, disk moved
to another machine, firmware update eating entries — and, as observed, VM
device-path changes), firmware finds nothing at the UEFI default path
`EFI/BOOT/BOOTX64.EFI` and falls through to PXE on a perfectly bootable disk.
Major distros ship the fallback copy for exactly this reason.

**Fix:** after the existing grub-install at :1198, add:
```bash
arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --removable
```
(`--removable` = install to `EFI/BOOT/BOOTX64.EFI`, skip efibootmgr/NVRAM.)
Extend the existing post-step verification at :1201 to also require
`-s /mnt/boot/EFI/BOOT/BOOTX64.EFI`.

**Notes:**
- Order: primary first, `--removable` second (removable pass touches no NVRAM).
- Works offline — grub runs entirely from the chroot.
- Sole-owner ESP (installer wipes the disk), so no fallback-path contention
  with other OSes.
- Optional: README "What Gets Created" one-liner about the fallback loader.

**Verification plan:** shellcheck; s2/s4-style harness not needed (two lines +
one test extension); diff review. Real validation lands with the next full VM
install run (fresh disk): after install, a disk-only boot must work even with
factory-reset OVMF vars — that directly exercises the fallback path.

**Effort:** ~30 min including README + review.

---

## V3. Online AUR step: all-or-nothing failure nukes a finished, bootable system

**Severity:** 🟠 high (UX/robustness; observed in the wild on run #1) · **Verified:** ✅ empirically

**What happened:** `awww-git` and `quickshell-git` failed to build (makepkg
exit 4) → `install-aur.sh` (set -e) died → ERR trap → full teardown → "safe to
re-run the installer." But the AUR step runs **after** GRUB
(`main`: `configure_system` :1768 → `install_aur_packages` :1770), so at that
moment the disk held a complete, bootable base system. The installer threw it
away and told the user to re-wipe — for two optional packages.

**Root cause of the build failures themselves:** OOM. dmesg showed the kernel
killing `rustc` (3.3 GB RSS, awww-git) and `cc1plus` (quickshell-git) with 4 GB
VM RAM. Real 4–8 GB machines will hit the same wall. The RAM-sized swapfile
already exists on the target by this point (`configure_swap` :1287 runs before
`configure_system`/AUR) but is never activated during install.

**Fix — three parts:**

**(a) Per-package tolerance in the online path** — mirror the offline path's
existing semantics (`:1475-1493`: loop, collect `failed_packages`, warn +
"install manually with: yay -S …", continue). Online (`:1494-1532`):
- Keep `set -e` inside `install-aur.sh` for the yay bootstrap only.
- Install packages one at a time: `yay -S --noconfirm "$pkg" || echo "$pkg" >> ~/.aur-failed`.
- Parent reads `/mnt/home/$USERNAME/.aur-failed` (then removes it), reports
  the same warn-summary as the offline path.
- If the yay **bootstrap** itself fails (network blip mid-clone): warn that
  ALL AUR packages were skipped + manual instructions, `return 0`. Base
  system is complete; a bootable machine with missing extras beats a wiped disk.
- Wrap the `arch-chroot … install-aur.sh` call so a nonzero exit downgrades
  to the same warn path instead of tripping the ERR trap.

**(b) Activate target swap during the install** — in `configure_swap`, after
`mkswap` (:1330): `swapon /mnt/swap/swapfile || warn "…continuing without…"`
(non-fatal — swap is a mitigation, not a requirement). Then release it on
every exit path, since active swap on the target btrfs makes `umount -R /mnt`
fail EBUSY:
- `finish()`: `swapoff /mnt/swap/swapfile` (or `2>/dev/null || true`) before
  the success-path `umount -R /mnt`.
- `teardown_target()`: add swapoff (guarded, non-fatal) **before** the umount
  attempts — this is the path the R3 harness scenarios cover, so re-run the
  s1 harness after the change.
- Note: btrfs swapfile requirements (nodatacow +C, no compression) are already
  satisfied by `configure_swap`; `swapon` of a btrfs swapfile needs the file
  fully allocated — the existing `dd` fill does that.

**(c) Decision for Jacob (default = per-package tolerance from (a)):**
whether hard-fail should remain for *some* AUR failures. Options: (1) never
fatal — always warn-and-continue [recommended; matches offline path];
(2) fatal only if >N% of list fails; (3) keep fatal. Plan below assumes (1).

**Verification plan:**
- Harness (s5): source real installer with stubbed `arch-chroot`/`yay`; scenarios —
  all succeed; one fails (continue + correct summary); yay bootstrap fails
  (skip-all warn, return 0, no ERR trap); offline path regression (unchanged);
  swapon failure non-fatal; teardown with active swap (stub swapoff/umount
  ordering assertion).
- Re-run s1 harness (teardown changes touch R3 Section 1 surface).
- Shellcheck at CI severity; ≤2-agent diff review per standing workflow.
- Real-world: next VM run at 4G RAM *should now succeed* (swap absorbs the
  rustc build) — that's the acceptance test for (b); a deliberate bogus
  package appended to aur-packages tests (a) end-to-end.

**Effort:** the big one — plan a full section (build + harness + review),
~same weight as an R3 section.

---

## Execution order

V1 → V2 → V3, one commit per item, standing workflow (build → lint →
harness where warranted → ≤2-agent terse diff review → BACKLOG update →
local commit; **no push** — CI ~1h, batch at the end with Jacob's say-so).

## Status

- [x] V1 GPU regex word boundaries (installer + setup-common) — done; 10-case
  table test passed, shellcheck clean, 2-agent review clean
- [x] V2 grub-install --removable + verification + README note — done;
  shellcheck clean, 2-agent review clean (VM acceptance pending next fresh
  install run)
- [ ] V3a online AUR per-package tolerance (+ Jacob's decision on severity)
- [ ] V3b swapon during install + swapoff in finish/teardown (re-run s1)
- [ ] Cumulative diff review across V1–V3, BACKLOG closure
