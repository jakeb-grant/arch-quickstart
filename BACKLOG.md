# Review Backlog

Working doc tracking issues found in a broad review of the repo (installer,
setup scripts, CI workflow, archiso profile, cross-cutting architecture).

Reviewed on 2026-07-02 against commit `d466822`. Findings were produced by
parallel review agents and then spot-verified against the actual code; the
**Verified** column notes whether the specific claim was confirmed by hand
(✅) or is agent-reported and plausible but not independently re-run (☑️).

Severity: 🔴 critical · 🟠 high · 🟡 medium · ⚪ low/info.

## Progress

| Section | Items | Status |
|---------|-------|--------|
| 1. Security & profile config | C1, H1, H7, M5, M6, M11 | ✅ Fixed 2026-07-02, diff-reviewed (LGTM) |
| 2. CI security | H3, H4, M1, M4, L1, L2 | ✅ Fixed 2026-07-02, diff-reviewed (LGTM) |
| 3. Installer correctness | H2, M3, M8, L4 | ✅ Fixed 2026-07-02, diff-reviewed (2× LGTM) |
| 4. Setup scripts | H5, H6, M2/R1, L5, L6 | ✅ Fixed 2026-07-02, diff-reviewed (2× LGTM) |
| 5. Validation, tests, docs | H8, M9, M10, M7, M8-docs | ✅ Fixed 2026-07-02, diff-reviewed (2 agents: 1 LGTM, 1 real finding fixed + re-verified) |
| Unscheduled | R3 (L8 fixed 2026-07-02 — dotfiles.conf moved into airootfs/etc as single source of truth; R2 completed with Section 5; L3 closed by design — fork note added to README) | ⬜ |
| AUR security audit | Reviewed PKGBUILDs + .install scriptlets + helper scripts of all 24 AUR package bases for malicious/risky execution. Verdict 2026-07-02: no malicious content; one weakness — railwayapp-cli pins no checksums (`sha256sums=('SKIP')` on a binary release). Everything else: official upstream sources with pinned hashes, benign scriptlets. Jacob's decision: accept and monitor (not production-critical) — review yay's PKGBUILD diff on railwayapp-cli updates. | ✅ |
| Later (collaborative w/ Jacob) | Audit package lists against Jacob's current system — spot-check for missing packages his dotfiles/workflow expect. Interactive session, not solo agent work. | ✅ Done 2026-07-02 — 99/102 official + 21/22 AUR overlap; added duckdb + jq per Jacob; nothing dropped (list matches his real machine); flagged polkit-agent + terminus-font absence on his machine as observations |

---

## 🔴 Critical

### ✅ C1. Passwordless root SSH exposed on the live ISO — FIXED (key-only auth, password auth disabled)
- **Where:** `archiso/airootfs/etc/ssh/sshd_config.d/10-archiso.conf` + `archiso/airootfs/etc/systemd/system-preset/00-archiso.preset:4` + `archiso/airootfs/etc/shadow:1`
- **Verified:** ✅
- **What:** The preset enables `sshd.service`; the drop-in sets `PermitRootLogin yes` and `PasswordAuthentication yes`; root has an **empty** password (`root::14871::...`). Upstream releng ships this drop-in with `PermitRootLogin no` / `PasswordAuthentication no` precisely to avoid this.
- **Scope:** This affects the **live USB environment only**, not the installed machine. Everything under `archiso/airootfs/` becomes the live boot environment; the target system is built fresh by `pacstrap` from `target-packages.x86_64` (which does not include `openssh`), and the installer never enables sshd or copies this config onto the target. So the finished machine has no SSH server and is unaffected.
- **Impact:** While a machine is booted from this USB running the installer, if it is on a reachable network anyone can `ssh root@<ip>` with a blank password and get root in the live environment (read/tamper with the disk being partitioned, passwords typed into the installer, etc.). The window is the duration of the install. Low practical risk on a trusted LAN; genuinely exploitable on an untrusted/reachable network.
- **Fix:** Set `PermitRootLogin prohibit-password` and `PasswordAuthentication no` (match upstream), or do not enable `sshd.service` in the preset. If remote/headless recovery is genuinely wanted, require a key or a build-time password.

---

## 🟠 High

### ✅ H1. Installed system can end up with no working admin account — FIXED (sudoers.d drop-in + visudo -cf)
- **Where:** `archiso/airootfs/usr/local/bin/hyprland-install:934` (and no root password is ever set — only `:916` sets the user password)
- **Verified:** ✅
- **What:** `sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /mnt/etc/sudoers` matches the stock line exactly and is not checked for success. If the sudoers layout ever differs by a character, the edit no-ops, `sed` still exits 0, and — because root has no password — the machine has no way to escalate privileges.
- **Fix:** Write a validated drop-in instead: `echo '%wheel ALL=(ALL:ALL) ALL' > /mnt/etc/sudoers.d/10-wheel && chmod 440 /mnt/etc/sudoers.d/10-wheel`, then `arch-chroot /mnt visudo -cf /etc/sudoers.d/10-wheel`.

### ✅ H2. Hibernation is advertised and sized for, but never actually configured — FIXED (resume hook + resume=/resume_offset= via map-swapfile; configure_swap now runs before configure_system)
- **Where:** `hyprland-install:1032-1083` (`configure_swap`), called at `:1483` — **after** `configure_system` at `:1482` already ran `mkinitcpio -P` (`:952`) and `grub-mkconfig` (`:958`)
- **Verified:** ✅
- **What:** Swap is sized to RAM "for hibernation," but nothing sets `resume=`/`resume_offset=` kernel params, adds the `resume` mkinitcpio hook, or computes the swapfile physical offset. Even if it did, it runs after the initramfs and grub.cfg were already generated.
- **Impact:** Hibernation silently never works; the RAM-sized swapfile is wasted effort.
- **Fix:** Either drop the hibernate framing (and size swap smaller), or move swap creation before `configure_system`, add `resume`/`resume_offset` to `GRUB_CMDLINE_LINUX` and the `resume` hook, and regenerate initramfs + grub.cfg.

### ✅ H3. CI: `dotfiles_repo` workflow input injected into a shell command line — FIXED (passed via step env:)
- **Where:** `.github/workflows/build-iso.yml:156`
- **Verified:** ✅
- **What:** `-e DOTFILES_REPO="${{ github.event.inputs.dotfiles_repo }}"` — `${{ }}` is expanded before the shell runs, so an input like `"; malicious #` or `$(...)` executes arbitrary commands on the runner. Restricted to write-access users, but still true script injection.
- **Fix:** Pass via `env:` and reference `"$DOTFILES_REPO_INPUT"` in the script; never interpolate `${{ }}` directly onto a command line.

### ✅ H4. CI: `dotfiles.conf` is `source`d into a root shell in a privileged container — FIXED (parsed with grep, not sourced)
- **Where:** `.github/workflows/build-iso.yml:328-329`
- **Verified:** ✅
- **What:** `source /workspace/archiso/dotfiles.conf` executes a checked-in file as shell as root inside the `--privileged` build container (which holds `GITHUB_TOKEN`). Reachable by any same-repo contributor via PR (the fork guard allows same-repo PRs); also breaks on any value containing spaces/`$(...)`.
- **Fix:** Don't `source`. Parse the value (`grep -oP '^DOTFILES_REPO=\K.*'`) and validate it against `^https://` before use.

### ✅ H5. `nvidia-setup` mkinitcpio edit is not idempotent — duplicates `nvidia` on re-run — FIXED (word-boundary removal scoped to the MODULES= line; simulated: idempotent, heals already-duplicated files, leaves comments/HOOKS alone)
- **Where:** `archiso/airootfs/usr/local/bin/nvidia-setup:501`
- **Verified:** ✅ (reproduced by simulation)
- **What:** The removal regex `s/ ?nvidia( |$)/ /g` requires a space or EOL after `nvidia`, so a bare `nvidia` immediately before `)` survives; the add-step then prepends the full list. `MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)` → `MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm nvidia)`.
- **Fix:** Use word-boundary removal, e.g. `s/(nvidia_drm|nvidia_uvm|nvidia_modeset|nvidia|i915|amdgpu) ?//g` before re-adding, then trim.

### ✅ H6. `amd-setup` ROCm install hard-fails on offline systems — FIXED (ROCm prompt skipped in offline mode with a "re-run once online" message; ROCm packages deliberately NOT added to the offline repo — multi-GB)
- **Where:** `archiso/airootfs/usr/local/bin/amd-setup:221` — `rocm-opencl-runtime` / `rocm-hip-runtime` are in no package list
- **Verified:** ✅ (`grep -rn rocm archiso/airootfs/root` → nothing)
- **What:** On an offline-installed machine pacman points only at `file:///opt/offline-repo`, so answering "y" to ROCm runs `pacman -S rocm-*` → "target not found" → `set -e` aborts the script before Hyprland env is written. README documents ROCm as network-required, but the prompt isn't gated on offline mode.
- **Fix:** Gate the ROCm prompt behind an offline check (skip with a clear message), or add the packages to `setup-packages.x86_64` so they're in the offline repo.

### ✅ H7. `polkit-gnome` autostarted but not installed — FIXED (added to target-packages)
- **Where:** `archiso/airootfs/etc/skel/.config/hypr/hyprland.conf:23` vs all package lists
- **Verified:** ✅ (flagged independently by two agents)
- **What:** `exec-once = /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1` but `polkit-gnome` is in no list, so no polkit agent runs. GUI privilege-escalation prompts (mounting, network config, etc.) never appear; some apps hang waiting.
- **Fix:** Add `polkit-gnome` to `target-packages.x86_64`, or switch the autostart to an installed agent (e.g. `hyprpolkitagent`).

### ✅ H8. No automated verification of the installer/scripts — FIXED (CI `lint` job: `bash -n` over all scripts + shellcheck --severity=warning -x over maintained scripts; both build jobs gated with `needs: lint`; 6 shellcheck findings triaged — 3 code fixes, 3 directives)
- **Where:** repo-wide; CI only builds ISOs
- **Verified:** ✅
- **What:** 4,200+ lines of destructive root bash with zero `bash -n`/`shellcheck`/tests. A syntax error or a bad edit ships to an ISO that wipes disks.
- **Fix:** Add a CI gate running `bash -n` and `shellcheck` over `archiso/airootfs/usr/local/bin/*` and `.github/scripts/*`. Triage shellcheck to real classes (quoting, word-splitting), not style.

---

## 🟡 Medium

### ✅ M1. CI: no `permissions:` block — privileged build runs with default token scope — FIXED (top-level read, release write)
- **Where:** `.github/workflows/build-iso.yml` (top level)
- **Verified:** ✅
- **What:** Both build jobs run `--privileged` containers executing repo-controlled code (package lists, `dotfiles.conf`, AUR PKGBUILDs). With no `permissions:` declared, the job gets the repo default token scope (often `contents: write`).
- **Fix:** Set top-level `permissions: contents: read`; grant `contents: write` only to the `release` job.

### ✅ M2. Offline-mode detection is inconsistent / absent across setup scripts — FIXED (single `is_offline_mode` in the shared lib, sourced by all 7 setup scripts; see R1)
- **Where:** installer uses filesystem presence (`hyprland-install:80-87`); GPU scripts grep pacman.conf (`nvidia-setup:58`); `bluetooth-setup`, `printer-setup`, `firewall-setup` have **no** offline detection at all
- **Verified:** ✅
- **What:** Half the setup scripts just call `pacman -S` and work offline only because `install_base` swapped `/mnt/etc/pacman.conf` to the offline conf. Offline behavior is implicit, not asserted, and three detection strategies can drift.
- **Fix:** Extract one `is_offline_mode` helper into a shared library and source it everywhere (see R1).

### ✅ M3. `install_base` package-list parsing is weaker than the rest of the codebase — FIXED (read_package_list() helper, used at all 5 installer parse sites)
- **Where:** `hyprland-install:824` — `grep -v '^#' | grep -v '^$'`
- **Verified:** ✅
- **What:** Doesn't strip indented comments, inline `pkg # note`, trailing whitespace, or CR (CRLF). Any such line becomes a bogus package name passed to `pacstrap`, aborting the whole base install. Other functions (`validate_offline_repo`, `install_aur_packages`) already use a robust `while read` + trim; `validate-packages.sh` parses differently again.
- **Fix:** Extract one `read_package_list()` helper (strip `#.*`, trim whitespace/CR, drop blanks) and use it in the installer, setup scripts, and validator.

### ✅ M4. CI: dotfiles clone URL unvalidated, failure silently swallowed — FIXED (https-only case check, -- guard, no || true)
- **Where:** `.github/workflows/build-iso.yml:338` — `git clone --depth 1 "$DOTFILES_REPO" ... || true`
- **Verified:** ☑️
- **What:** Unvalidated URL flows to `git clone`; a value beginning with `-` or using `ext::`/`file://` transport can execute commands. `|| true` also masks a failed clone, producing a "successful" offline ISO with no dotfiles and no warning.
- **Fix:** Validate `^https://` first, use `git clone --depth 1 -- "$URL" dest`, and drop `|| true` (or at least warn on failure).

### ✅ M5. Preset enables `qemu-guest-agent.service` but the package isn't installed — FIXED (added to packages.x86_64)
- **Where:** `archiso/airootfs/etc/systemd/system-preset/00-archiso.preset:21` vs `archiso/packages.x86_64`
- **Verified:** ✅ (`qemu-guest-agent` absent from packages)
- **What:** In the very common QEMU/KVM boot case, `systemctl preset` warns and host↔guest integration (graceful shutdown, clipboard, IP reporting) is unavailable.
- **Fix:** Add `qemu-guest-agent` to `packages.x86_64`.

### ✅ M6. Preset enables `choose-mirror.service` but no such unit ships — FIXED (preset line removed)
- **Where:** `00-archiso.preset:9` — only the `choose-mirror` script exists, not the unit
- **Verified:** ✅
- **What:** Upstream ships this unit in its airootfs; this profile replaced airootfs without it. `systemctl preset` warns and mirror selection never runs (dead config).
- **Fix:** Drop the preset line, or add the upstream `choose-mirror.service` unit + cmdline generator.

### ✅ M7. Desktop advertised in README/finish-screen isn't wired up (Walker, quickshell, bar) — FIXED per Jacob's decision 2026-07-02: the base-Hyprland-plus-dotfiles design is intentional; removed Walker/Elephant entries from aur-packages, replaced the finish screen's false SUPER+D line with the real SUPER+E (yazi) bind + a "bar/launcher/theming come from your dotfiles" note, rewrote the README's "full desktop (with quickshell)" claim
- **Where:** `hyprland-install:1440` ("SUPER + D → Walker"), `README.md:72`; `aur-packages.x86_64:11` (`walker-bin` commented), `target-packages.x86_64:37` (`waybar` commented); `hyprland.conf` has no `SUPER+D` bind and never execs quickshell
- **Verified:** ✅
- **What:** The installed desktop boots into Hyprland with no bar, no launcher, and no shell process, while docs and the finish screen promise a launcher keybind and "full desktop (with quickshell)." (May be intentional if dotfiles supply this — needs a decision.)
- **Fix:** Either autostart quickshell/a bar and ship a launcher, or correct the README + finish-screen text to match what actually ships.

### ✅ M8. `install.conf` defaults are duplicated as hardcoded fallbacks that disagree — FIXED (DEFAULT_SHELL fallback now /bin/bash, matching install.conf; Section 5 follow-up: dead `DEFAULT_FONT` wired — installer fallback, FONT= written to target vconsole.conf, terminus-font added to target-packages. DEFAULT_USERNAME's generic "user" fallback is intentional per L3)
- **Where:** `install.conf:19` `DEFAULT_SHELL="/bin/bash"` vs `hyprland-install:38` `DEFAULT_SHELL="${DEFAULT_SHELL:-/bin/zsh}"`
- **Verified:** ✅
- **What:** If `install.conf` is ever missing/unreadable the shell silently flips to `/bin/zsh` (which isn't installed), contradicting the documented default. Same duplicated-fallback pattern for other defaults.
- **Fix:** Make fallbacks match `install.conf`, or remove them and fail loudly if the config is missing.

### ✅ M9. CI: AUR validation query is unbounded and unencoded — FIXED (chunked POST to RPC v5 via `curl --data-urlencode`, 100 pkgs/chunk, `--retry 3`)
- **Where:** `.github/scripts/validate-packages.sh:127-134`
- **Verified:** ☑️
- **What:** Package names are concatenated into a GET `arg[]=` query with no URL-encoding or chunking. A long list can exceed the AUR RPC request-length limit, yielding truncated results → real packages reported "invalid" (false failure) or missing ones passing spuriously.
- **Fix:** Use POST (RPC v5 supports it) or `curl -G --data-urlencode`, and chunk the list.

### ✅ M10. `validate-packages.sh` misses the failure classes that actually occur — FIXED (rewrite: installer-identical `read_package_list` parsing; new checks — AUR-listed pkg present in official repos [the cloudflared incident], duplicates within/across target-system lists, exec-once binaries resolve via `pacman -F` to a listed package [would have caught H7], setup-script literal installs present in offline-repo lists [ROCm exempt per H6]; all 8 failure classes exercised against a synthetic broken tree)
- **Where:** `.github/scripts/validate-packages.sh`
- **Verified:** ☑️
- **What:** It only checks each listed package exists in a repo/AUR. It does not check packages *referenced by scripts/configs* are listed (would have caught H7 polkit-gnome), does not detect cross-list duplicates, and can't catch a repo package wrongly placed in the AUR list (passes either check).
- **Fix:** Add a lint that greps `pacman -S`/`yay -S` targets in scripts and `exec-once` targets in configs, and asserts each resolves to a listed package.

### ✅ M11. systemd-boot `default` matches no entry — FIXED (default 01-archlinux-x86_64-linux.conf)
- **Where:** `archiso/efiboot/loader/loader.conf:1` — `default archlinux.conf`; entries are `01-…`, `02-…`, `03-…`
- **Verified:** ✅
- **What:** No `archlinux.conf` exists, so the `default` directive is ignored (falls back to first entry). Impact limited because GRUB is the primary UEFI path, but the directive is wrong.
- **Fix:** `default 01-archlinux-x86_64-linux.conf` (or `default 01-*`).

---

## ⚪ Low / Info

- **✅ L1 (FIXED)** — CI actions pinned by mutable tag, not SHA; `softprops/action-gh-release@v1` is old and runs in the release path with `contents: write`. Pin to SHAs and bump. (`build-iso.yml`) ☑️
- **✅ L2 (FIXED — narrowed to /tmp/archiso-out)** — CI bind-mounts host `/tmp` into the privileged container (`-v /tmp:/tmp`), widening blast radius of the injection findings. Use a container-internal path. (`build-iso.yml:155`) ☑️
- **✅ L3 (CLOSED — by design, 2026-07-02)** — Personal identity baked into the ISO: `DEFAULT_USERNAME`, `GIT_USER_NAME`, `GIT_USER_EMAIL` in `install.conf`. Reviewed with Jacob: values are a first name and a GitHub noreply address (no real email/PII), the dotfiles link is intentionally public, and all are just pre-filled installer prompts. README now tells forkers to swap in their own values. ✅
- **✅ L4 (FIXED — partprobe + udevadm settle + device-node wait with die on timeout)** — No `partprobe`/`udevadm settle` after partitioning; relied on a fixed `sleep 1`. ☑️
- **✅ L5 (FIXED — unmatched marketing strings now classify by PCI device ID: ≥0x1E00 = Turing+ → nvidia-open-dkms, else/lookup-failure → legacy)** — NVIDIA GPU-generation detection keys off `lspci` marketing strings that are often absent; an unlabeled modern card can be misclassified as LEGACY and get the wrong driver. (`nvidia-setup`) ☑️
- **✅ L6 (FIXED — flips commented/uncommented setting in place, else inserts under `[Policy]`, else appends a new `[Policy]` section; simulated across 4 main.conf shapes)** — `bluetooth-setup` `AutoEnable` edit only rewrites the commented default; the append fallback can land outside `[Policy]` where bluez ignores it. (`bluetooth-setup`) ☑️
- **L7** — `Installation_guide` references `w3m` which isn't installed (degrades gracefully to printing the URL). Add `w3m` or drop the branch. ✅
- **✅ L8 (FIXED — dotfiles.conf moved to `airootfs/etc/`, so it ships on the live ISO and is copied to the installed system's `/etc/dotfiles.conf`; `dotfiles-setup` and the installer's remote-repo prompt both default from it via parse-not-source grep; CI syncs a dispatch-input override back into the baked conf)** — `dotfiles-setup` has its own empty `DEFAULT_REPO=""`, a third dotfiles source of truth independent of `dotfiles.conf`/`install.conf`. ☑️
- **Note** — The ERR trap echoes `$BASH_COMMAND` on failure; investigated as a possible password leak but bash does **not** expand variables in `$BASH_COMMAND`, so the LUKS/user passwords are not exposed. No action required; noted for future edits to that trap.

---

## Refactoring themes

### ✅ R1. Extract a shared library for the GPU/setup scripts — DONE
**Status:** Extracted as `/usr/local/lib/setup-common.sh` (named `setup-common`, not `gpu-setup-common`, since all 7 setup scripts source it — logging, run_cmd/pkg_install/svc_*, target_path, is_offline_mode, get_user_home/get_target_user, AUR helpers, detect_gpus + amd_is_apu, multilib/sync block, append_hyprland_env). Sourced via script-relative path with `/usr/local/lib` fallback; installer copies it alongside the scripts; `profiledef.sh` sets its perms. `hyprland-install` intentionally does NOT source it (its gum-styled `info`/`warn`/`error` would collide), so the GPU-detection regexes still exist in one extra place there.
The three GPU scripts share ~120 lines byte-for-byte (`run_cmd`, `pkg_install`, `target_path`, `is_offline_mode`, `get_user_home`, color/logging, the multilib-enable block, the hyprland-env-append pattern), and the APU/Arc-detection regex is maintained in 3–4 places and already diverges (nvidia/amd omit `arc`, intel includes it). Extract `/usr/local/lib/gpu-setup-common.sh`, source it from all setup scripts, and add it to the installer's copy loop (`hyprland-install:1017`, which currently enumerates only the seven scripts). This also gives H5 (mkinitcpio fix) and M2 (offline detection) a single home.

### R2. Single `read_package_list()` helper
Package-list parsing exists in at least three forms (robust `while read` in the installer's AUR/offline paths, weak `grep` in `install_base`, a third variant in `validate-packages.sh`). Unify them so the installer, setup scripts, and validator agree on comments/whitespace/CR handling (fixes M3, reduces M10 risk).
**Status:** ✅ DONE. Installer side with M3 (one helper, all 5 sites); `validate-packages.sh` now carries a byte-identical copy of the helper (Section 5 / M10); setup scripts have no list-parse sites (Section 4 / R1). Note: the workflow's inline `mapfile < <(grep -v ...)` sites in build-iso.yml still use the weak parse, but every list they read is pre-validated by the rewritten validator in the same run.

### R3. Decompose the 1,490-line installer monolith
Error handling leans entirely on a global `set -e` + ERR trap that pauses on `read`, which is fragile for a disk-wiping installer; several `|| true` calls mask failures. Consider explicit success checks + cleanup around the destructive steps (pacstrap, mkfs, cryptsetup, grub-install) and splitting into sourced modules. Lower priority than the correctness fixes above.
