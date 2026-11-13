# UI Working Doc — Installer Look and Feel

## Build status (2026-11-13)

Everything below is built: all 21 items, optional ones included. When this table was written
the code was in the working tree, not yet committed. It was checked with s5 `all` (50 scenarios as of the F6/F8 fixes), shellcheck,
`tests/glyph-lint.sh` and renders through ter-116n. None of it has been seen on a VM yet; the
checklist is in BACKLOG D5. The rest of this doc is the approved design, left as written. Where
the build differs, this table says how. "Built" means as the item's body says, with its
Feasibility note applied.

| item | status | deviation |
|---|---|---|
| U1 glyph fixes | built | also `GUM_FILTER_*` prefixes and `GUM_SPIN_PADDING` |
| U2 vocabulary, colour | built | |
| U3 palette | built | |
| U4 lint, renderer | built, both | the lint adds a third check: a script that runs gum must export the `GUM_*` replacements for gum's default glyphs. The renderer also flags lines over 79 columns, reads the palette from the installer, and has `--check`/`--pty`. The font is fetched, not committed (`.gitignore`). `nvidia-setup`'s `═` lines are now `─` |
| U5 spine | built with deviation | one `CHAPTERS` list (`id` or `id=label`) derives `STEPS`/`LABELS`, the welcome route and the review's route |
| U6 masthead, tide | built | HOST is cut to the room the widest chapter label leaves, so it reads the same in every chapter; the boot note is dropped below 3 characters |
| U7 clear policy | built | |
| U8 welcome | built with deviation | copy says "then it does the heavy lifting", not "then it runs on its own". The offline line says "the packages install from this stick": it prints before `validate_offline_repo` has checked them |
| U9 animations | built with deviation | the whole wordmark rises out of the water a row per frame, its reflection growing beneath it: 5 frames of 0.05 s, not rows printed bottom-up at 0.03 s |
| U10 stream frames | built | the setup scripts' frame closes on "N of M set up" |
| U11 ledger | built | |
| U12 checkpoint | built | card copy kept in its limited form, though F1 and F2 are now fixed |
| U13 step-away | built with deviation | shown on both ISOs, not offline only: the online AUR builds run under the temporary NOPASSWD rule (F3). Left off the apps rule if that grant fails |
| U14 per-package rules | built | |
| U15 notes | built | more sites: setup scripts, post-GRUB writes, greetd, minimal system, staged payloads left behind. A failed `swapon` is noted as "check swap is on" with `swapon --show` |
| U16 receipt | built with deviation | to fit 25 rows it drops the padding, then the times, then cuts the notes (the report keeps them whole). If no copy of the report could be written nothing is cut, so a long command may wrap and push the masthead off. "Hyprland starts on its own" only when greetd is set up. The desktop row says "no dotfiles" or "dotfiles incomplete" |
| U17 voice | built | partial AUR runs get no success line (Feasibility option) |
| U18 report | built | |
| U19 review gate | built with deviation | the erase gate is a screen of its own (warning, `lsblk`, typed name), because card, menu and gate together pass 25 rows. A chapter changed from the review starts from its earlier answers, so Enter keeps each one: inputs pre-filled, the encryption, same-password and timezone confirms defaulting to the earlier choice, the GPU and firewall openings pre-selected (`--selected=`). Passwords are typed again. Cancel at "Erase?" keeps the old disk. The typed name stays on screen as typed, and the point-of-no-return rule holds for a second before `partition_disk` clears. Card values start at column 14, as drawn. The card gives the firewall a row of its own when the openings would not fit beside the GPU, and cuts the hostname before the timezone. 8 `review-*` scenarios, not 3 |
| U20 re-ask | built | |
| U21 failure card | built, not deferred | coral border, on stderr under the ERROR line; s5 `err-card`, `err-heredoc`, `err-cancel`. Shown for an unexpected error or any stop once the disk is touched, except Ctrl-C/SIGTERM (130/143: cleanup only), and not for a `die` before it. In the system chapter before GRUB the "usually" line goes by what failed (boot loader or initramfs, swapfile, or another setup step). The disk row says "may be partly written" |
| F1, F2 | fixed | INT bracket on both AUR branches; `run_setup` and `warn_note` after GRUB |
| F3 | fixed in code | temporary NOPASSWD rule around the online AUR builds; confirm on the VM |
| F4, F5, F7 | fixed | by U17, U17, U16 |
| F6 | open | check `locale` on tty1 |

Working notes for giving the installer a visual identity, a sense of progress, and some delight.
Target file: `archiso/airootfs/usr/local/bin/hyprland-install` (1,972 lines as of `1d34656`).
This doc combines three single-lens proposals (identity, wayfinding, states) into one
design and one build plan. They were written on 2026-11-12 and kept in the session scratchpad,
which is temporary. Nothing in the repo has been changed yet.

The brief, in the owner's words: *polished but with some character, something that sparks
delight.* It is not tied to any colour theme. It needs some sense of progress.

**How the mockups were made.** gum is **not installed** on this machine, so no mockup is real
gum output. Instead, the chrome below (masthead, rules, ledger, boxes) was built as a working
printf prototype. The prototype runs under `set -eEuo pipefail` with `LC_ALL=C`, and every line was
checked at 80 columns or less. Its output was then rendered **pixel for pixel through the real
`ter-116n` bitmap** (parsed from `terminus-font-4.49.1-8`, the version the ISO ships) with
the palette from U3. Those renders were used to choose the wave and to catch the glyph
problems listed under Ground truth. The gum-drawn parts of the mockups (choose lists,
confirm buttons, input) were drawn by hand to match gum's layout. Prototype and renderer:
`/tmp/claude-1000/-home-jacob-projects-arch-quickstart/0581879d-17cd-4286-8df0-268c35d3d862/scratchpad/synth/`
(`ui-lib.sh`, `proto.sh`, `scenes.sh`, `ttyrender.py`). That directory is temporary. U4 proposes
committing the renderer.

## Feasibility review (2026-11-12, second pass)

A skeptical-implementer pass over every item, checked against the real tools rather than
this doc's own claims. Method:

- **gum.** `gum-2.0.2-1` was extracted from the Arch package (`pacman -Sp gum`, the version
  the ISO's `packages.x86_64` pulls in). It was driven in an 80x25 pty with a tty1-like
  environment (`TERM=linux`, no `COLORTERM`), and the screens were read back through a
  terminal emulator. Every subcommand, flag and `GUM_*` variable this doc uses exists in 2.0.2.
- **Glyphs.** The unicode table and bitmaps of `ter-116n.psf.gz` were read from
  `terminus-font-4.49.1-8`, a PSF1 font with 256 glyphs.
- **Columns.** Every mockup line was measured. The mastheads and rules are 79 columns, and
  nothing on screen goes past 80. Lines over 80 are source code or annotations, not screen output.
- **Semantics.** Each item was checked against `hyprland-install` and `tests/s5-runner.sh`.

**Verdict: the core set holds.** No core item is infeasible. Seven need a change, listed below.
None of them touches a streamed step, a trap, a prompt wrapper or the no-abort zone.

| item | verdict | change needed |
|---|---|---|
| U1 glyph fixes | ok with change | "today" mockup corrected (drawn as `■`, not `�`); **space does not toggle in gum 2.0.2** (`x`/`tab` do), so fix the firewall copy; also blank `GUM_CHOOSE_HEADER` and hide help lines |
| U2 vocabulary, colour | ok | real capture: today's `warn` (#f9e2af) and `die` (#f38ba8) both emit SGR 91, the same red |
| U3 palette | ok | VM-only check; gum's help separator uses SGR 30 and disappears on slot 0 (harmless) |
| U4 glyph lint | ok with change | it also fails today on `nvidia-setup` (four `═` banner lines, the legacy-GPU path) |
| U5 spine | ok | `step()` tested under `set -eEuo pipefail` with an ERR trap: no trips |
| U6 masthead, tide | ok with change | truncate the hostname: past about 19 characters the boot note pushes the line over 79 |
| U7 clear policy | ok | the masthead scrolls off inside long chapters (see U12) |
| U8 welcome | ok with change | gum 2.0.2 confirm takes 5 rows, not 3 (help line); set `GUM_CONFIRM_SHOW_HELP=false` |
| U9 animations | ok | |
| U10 stream frames | ok with change | "1,284 packages" can't be known before pacstrap (the list has 110 names); count afterwards or say "plus dependencies" |
| U11 ledger | ok | |
| U12 checkpoint | ok with change | the masthead does **not** stay on screen through AUR builds (they scroll it off); put the reassurance in the stream rule |
| U13 step-away | ok | DECSCNM (`\e[?5h`) is supported by the Linux console |
| U14 per-package rules | ok | |
| U15 notes | ok | |
| U16 receipt | ok with change | 24 rows plus a 5-row confirm is 26: needs the help line hidden; truncate host and user names in the card |
| U17 voice | ok with change | test-edit contradiction: `want_not "AUR packages installed"` matches "1 of 2 AUR packages installed" |
| U18 report | ok | |
| U19 review gate | ok with change | hide gum choose's `Choose:` header and help line (verified that env vars remove them); stub cost unchanged |
| U20 re-ask | ok | owner's call, as stated |
| U21 failure card | ok (deferred) | |

**Findings that cut across items:**

1. **Missing glyphs draw as `■`, not `�`.** ter-116n maps U+FFFD to the same glyph as `■`
   (0xC6). So the double-border banner shows today as a frame of small squares. The done mark
   `■` also looks exactly like a missing glyph. A VM check for "no `�`" can't see anything;
   look for unexpected `■` instead, and rely on U4's lint for the source side.
2. **gum 2.0.2 adds chrome the mockups leave out.** `choose` prints a `Choose:` header, two
   blank rows and a help line. `confirm` and `input` print a blank row and a help line. The
   help lines use `←↓↑→`, which draw on tty1 as `◀↓↑▶`. All of this can be turned off with
   environment variables, so the s5 stub needs no change (verified):
   `GUM_CHOOSE_HEADER=""`, plus `GUM_CHOOSE_SHOW_HELP` / `GUM_CONFIRM_SHOW_HELP` /
   `GUM_INPUT_SHOW_HELP` set to `false`. `GUM_{CHOOSE,CONFIRM,INPUT}_PADDING` puts prompts on
   the 3-column gutter: `"0 3"` for choose and input, and `"0 2"` for confirm, which adds its
   own space. Keep a toggle hint for the one `--no-limit` list, in the copy or by leaving its help on.
3. **Space does not toggle in `gum choose --no-limit` on 2.0.2.** Only `x` and `tab` do (tested
   three times, and the help line says `x toggle`). Today's "space to select" copy is wrong,
   and so is U17's proposed "space toggles".
4. **Esc on `gum confirm` returns 1 ("no") in 2.0.2. Ctrl-C returns 130.** Esc on `choose` and
   `input` returns 1, which the wrappers already treat as cancel. The UI items don't change
   this, but the installer's comment "Esc on newer gum = 130" is wrong, and the VM checklist
   line "Esc → 130" applies to the wrappers, not to `confirm()`.
5. **Ground truth 4 (C locale) is probably false.** mkarchiso copies airootfs, including
   `/etc/locale.gen` with `en_US.UTF-8`, *before* it installs packages (`_make_custom_airootfs`
   runs before `_make_packages`). glibc's `10-glibc-locale-gen.hook` then runs `locale-gen`, and
   `/etc/locale.conf` sets `LANG=en_US.UTF-8`. Keep the `width()` guard anyway; it costs
   nothing. Two corrections:
   - `C.utf8` is a directory shipped in the glibc package, not something built into glibc.
   - When `LANG` names a locale that was never generated, bash **stays** in C.UTF-8 after the
     `local LC_ALL` goes out of scope (tested), so the change isn't scoped to one function. It is benign.

   Also, `lsblk` draws its tree as `├─` in a UTF-8 locale but as `` `- `` in C.
6. **User-supplied names have no length limit worth trusting.** Hostnames can be up to 63
   characters and usernames up to 32. Every printf line that embeds them (masthead,
   checkpoint, receipt, review card) needs to truncate them with `…` to stay within 79 columns.

Real gum 2.0.2 output (`TERM=linux`, U1's env vars). This is the firewall list after `x` on
row 1, with the cursor moved to row 2. `Choose:` and the help line are gum's own defaults:

```
Choose:
  ■ SSH (port 22)
▶ · HTTP/HTTPS (ports 80, 443)
  · KDE Connect / GSConnect (ports 1714-1764)


x toggle • ←↓↑→ navigate • enter submit • ctrl+a select all
```

The same prompts with the header blanked, help hidden and the gutter padding from finding 2
(`choose`, then `confirm`):

```
   ▶ Install on /dev/nvme0n1
     Change the disk
     Quit, nothing written

   Ready?

      Let's go        Not now
```

SGR emitted under `TERM=linux`: `GUM_*_FOREGROUND=6` gives `36`, `=2` gives `32`, and
`=13` gives `95`. The confirm buttons come out as selected `46`/`30` and unselected `40`/`37`.
The current hex colours land as follows:

| hex | SGR | colour on the console |
|---|---|---|
| `#cba6f7` | `94` | bright blue |
| `#89b4fa` | `94` | bright blue |
| `#a6e3a1` | `92` | bright green |
| `#f9e2af` | `91` | bright red |
| `#f38ba8` | `91` | bright red |

## Decision

**"The tide."** The installer is treated as a short voyage. A small `◆ arch quickstart` masthead
sits over a single line of water drawn with the console's four scan-line glyphs `⎽⎼⎻⎺`. That line
is the step tracker: finished chapters roll as a wave and the rest stays calm. It is honest
about measuring chapters, not bytes. Everything else serves that idea:

- One mark for each meaning.
- The installer's voice is indented. The machine's raw output runs flush left between labelled rules.
- There is a checkpoint at the true midpoint, the moment the disk can boot on its own.
- The finish screen is a receipt: what was built, how long it took, and what is left to do.

Delight comes from **true specifics**, not decoration. The copy uses the user's hostname and
name. It says "boots on its own" only after GRUB has been verified. It gives a real build time.
It notices that you walked away, and flashes when it needs you back. All chrome is drawn with
printf. gum is used only for interaction: prompts and spinners.

## Ground truth (checked on this pass)

These facts override some claims in the lens docs.

1. **The current banner can't be drawn on tty1.** The font has no double-line box glyphs
   (`═ ║ ╔ ╗ ╚ ╝`), so `header()`'s `--border double` shows as a frame of `�` on all ~18 screens.
   This was checked by parsing ter-116n's unicode table. The wayfinding and states docs assumed
   these glyphs were present, so their `══` headers, `║` gate and `╔═╗` cards are out.
   *(Second pass: the frame actually draws as `■`, because ter-116n gives U+FFFD the glyph of `■`.
   The list of missing glyphs below is confirmed.)*
   - Also missing: rounded corners `╭╮╰╯` (`finish()`), `▓`, half blocks `▀▄▌▐`, braille
     (`gum spin --spinner dot`, all 5 calls in `partition_disk`), and `✓`. `✓` is gum choose's
     default selected prefix, so the **firewall multi-select shows `�` today**.
   - `pulse` (`█▓▒░`) is out too, so the only usable built-in spinners are `line` and `ellipsis`.
2. **A glyph being mapped doesn't mean it looks right.** The bitmaps show that `▲` maps to the
   **`↑` arrow** glyph, `▼` to `↓`, and `→` shares its glyph with `▶`. So the identity doc's `▲`
   brand and attention mark would draw as arrows, and `finish()`'s `→` keybind arrows already
   draw as filled triangles. U4's lint therefore uses a list of glyphs whose shapes were checked,
   not "is it in the font".
3. **These glyphs draw as intended:** `─ │ ┌ ┐ └ ┘ ├ ┤ ┬ ┴ ┼`, `⎽ ⎼ ⎻ ⎺`, `█ ▒ ░`, `■` (a small
   square), `▶ ◀`, `◆`, `• ·`, `×`, `… — – « »`.
4. **bash on tty1 runs in the C locale.** `.bash_profile` launches the installer directly, and
   nothing calls `.automated_script.sh`, so its `locale-gen` never runs (root's shell is bash and
   there is no `.zlogin`). In the C locale `${#s}` counts **bytes**: `◆` counts as 3 and boxes
   come out misaligned. The prototype showed exactly this misalignment. The fix is to measure inside
   `local LC_ALL=C.UTF-8`. `C.UTF-8` is built into glibc, so it needs no locale-gen, and the
   change stays scoped to that one function. This was checked locally. Confirm `locale -a` on tty1.
   *(Second pass: probably false. glibc's locale-gen hook runs during mkarchiso's package
   install, so `en_US.UTF-8` likely exists on the ISO. And the `local LC_ALL` change sticks when
   `LANG` is ungenerated. See Feasibility, finding 5.)*
5. **No VT scrollback since Linux 5.9.** Anything that has been cleared or scrolled off is gone. Today that
   includes every `warn …; sleep 3` (the next `header` clears it) and the
   `dotfiles_retry_hint` "(see above)".
6. **Colour.** The console has 16 foregrounds and 8 backgrounds, and bold is drawn as the bright
   partner. With `TERM=linux`, gum and lipgloss use the ANSI profile and approximate the hex
   colours, so the Catppuccin pastels land unpredictably (near white). The fix is to name colours by
   **ANSI index**.
7. **The s5 harness constrains everything.**
   - The runner sets `set -u` *before* it sources the installer, so new globals must be
     initialised at the top level and stay `${X:-}`-safe.
   - stdout is a file. Gate colour on `[[ -t 1 ]]` and the logs stay plain.
   - The gum stub prints positional arguments, drops `--flag=value` tokens whole, skips the
     value of `--padding/--margin/--border/--align/--border-foreground/--foreground`, and its
     `confirm` always says yes.
   - `choose` and `input` return their own positional args or placeholder, so any **new prompt
     flow needs stub knobs** before it can be tested.
   - Assertions use `grep -F` on substrings, so adding glyph prefixes keeps them passing, but
     changing wording does not.

## The design

### Glyph kit (the only marks used)

| role | glyph | colour role | notes |
|---|---|---|---|
| brand mark, milestones | `◆` | sea | masthead, welcome, checkpoint, finish only, so it stays special |
| done | `■` | leaf | |
| now / cursor | `▶` | sea | gum choose cursor, filter indicator |
| aside / breadcrumb | `·` | dim | "doing X" lines, separators |
| attention | `!` | amber, bold | ASCII on purpose: `▲` draws `↑` |
| failed | `×` | coral, bold | `die()` only |
| progress | `⎽⎼⎻⎺` | sea / dim | wave period 10: `⎽⎽⎽⎼⎻⎺⎺⎺⎻⎼` (a period of 6 rendered as choppy dashes) |
| rules, boxes | `─ │ ┌ ┐ └ ┘` | dim / sea | gum `--border normal` only |
| welcome art | `█ ░` | sea / dim | |

### Colour roles

Colours are named by ANSI index everywhere: SGR in printf, and plain numbers in the `GUM_*` env vars.

| role | SGR | U3 palette slot | hex | default VGA fallback |
|---|---|---|---|---|
| background (ink) | — | 0 | `#101418` | black |
| body text (sand) | 37 / default | 7 | `#d8d3c4` | light grey |
| dim: chrome, labels, calm water | 90 | 8 | `#6b7585` | dark grey |
| brand, tide, cursor (sea) | 36 / 1;36 | 6 / 14 | `#4fd1c5` / `#8af0e4` | cyan |
| **you**: the user's own answers (buoy) | 1;35 | 13 | `#ffb38a` | bright magenta |
| done (leaf) | 32 | 2 | `#8fcf6b` | green |
| attention (amber) | 1;33 | 11 | `#ffe08a` | yellow |
| danger, errors only (coral) | 1;31 | 9 | `#ff8a80` | bright red |
| left to the tools (harbor; pacman's `::`) | 34 | 4 / 12 | `#5a9bd8` | blue |

Rules:

- Hue never carries meaning on its own; every status has its own glyph shape.
- Bright slots (8-15) are never used as backgrounds.
- The renders confirmed that the roles still read on the default VGA palette, so U3 is
  polish, not a dependency.

### Grid and rhythm

- **Columns.**
  - The masthead starts at column 1.
  - **Everything the installer says starts at column 4** (a 3-space gutter) on a 76-column measure.
  - **Machine output stays at column 0**, untouched. A line's position tells you who is speaking.
  - Nothing is centred: gum prompts and raw output can't be.
- **Vertical rhythm.** One blank line between groups, never two.
  - The masthead is 3 rows, down from today's 8.
  - Key/value summaries put the key in dim, padded to 11, and the user's own values in "you".

### Voice

1. **Say what is happening, then what it means for you.** "Installing 1,284 packages from the
   ISO. No downloads."
2. **Warm at the edges, plain in the middle, flat at danger.** Personality belongs on welcome,
   the checkpoint and the finish screen. Prompts are short questions. Erase warnings and errors are exact and never playful.
3. **Use their words.** The hostname and username go into the copy: "orion can boot on its own now",
   "Welcome home, jacob."
4. **Never claim what didn't happen.** No "AUR packages installed" after failures, no checkpoint
   before GRUB has been verified, and no "nothing to answer" unless that is true (see F3).
5. **No exclamation marks, and no `WARNING:` prefixes.** The `!` glyph already says it. The
   installer has 33 messages that end in `!` today.
6. **Diagnostics stay verbatim:** `ERROR: Command failed at line N: …`, `Cleaning up...`, and the
   teardown lines.

### Conflicts between the lenses, resolved

| question | identity | wayfinding | states | decision | why |
|---|---|---|---|---|---|
| progress indicator | wave fills the masthead rule | block rail `██ ▓▓ ░░ ║` | `═══ 2/8 ═` rules | **wave** with `n of 10 · label` on the right | the rail's `▓ ║` and the rules' `═` aren't in the font; the wave reads on monochrome by its shape, and the label gives the exact count |
| where step state lives | `header N name` at 18 call sites | `step id` spine in `main()`, `header()` keeps no args | registry | **spine** | one source of truth; call sites and tests don't change |
| status vocabulary | glyphs `■ ▲ × ▶` | colour roles only | `[ OK ] [WARN]` tags | **glyphs, with `!` for attention** | tags look like the systemd boot log, not character; glyph shapes stay colour-blind safe; `▲` draws `↑` |
| chapters | 8 | 11 (check numbered) | 8 | **10, with the prologue unnumbered**, the same in both ISO modes | the network check is seconds long and automatic; the review is a real stop |
| elapsed time | finish only | live in the header after the gate | close rules | **close rules + finish** | a clock in a static header looks frozen between redraws |
| boxes | `--border normal` | `double` | `╔═╗` | **normal** (single line) | the only border the font has |
| spinner | `line` | `pulse` | `pulse` | **`line`** | `pulse` needs `▓` |
| chrome renderer | printf + some gum style | printf | printf | **printf** with a `width()` helper | no stub cost; exact SGR; C-locale-safe measuring |
| destructive confirm | keep in `select_disk` | move to a review screen | move to a review screen, type the disk name | **move to a review screen (U19), last section** | today the confirm that actually starts `wipefs` is labelled "Proceed with these settings?" |

## Chapters

| n | id | masthead label | functions | offline/online difference |
|---|---|---|---|---|
| — | prologue | `hyprland on arch` | welcome (hero, no masthead), validate_offline_repo, check_network, connect_wifi | offline adds the repo check |
| 1 | disk | disk | select_disk | |
| 2 | you | you | configure_user | |
| 3 | machine | machine | configure_extras | |
| 4 | review | review | review_plan (**new, U19**) | |
| 5 | prepare | prepare disk | partition_disk, format_partitions, mount_partitions | |
| 6 | base | base system | install_base | hint: "from the ISO, no downloads" / "downloading" |
| 7 | system | system | configure_swap, configure_system | |
| 8 | apps | apps | install_aur_packages, run_user_installs | hint: "from the ISO" / "building from the AUR" |
| 9 | extras | extras | install_extras | after apps since F8: online, `nvidia-setup`'s legacy driver needs yay |
| 10 | dotfiles | dotfiles | setup_dotfiles, restore_pacman_conf (moved, U16) | |
| done | — | `done` | finish | |

Until U19 lands, the spine has **9** chapters (no review). U19 inserts it.

## Ranked core set (value per unit of risk)

1. U1 glyph fixes
2. U2 vocabulary and colour roles
3. U5 + U6 spine and tide
4. U10 stream frames
5. U15 + U16 notes and receipt
6. U12 checkpoint
7. U8 welcome hero
8. U17 voice pass
9. U13 step-away / your turn
10. U7 clear policy
11. U11 ledger
12. U19 review gate
13. U3 palette
14. U4 glyph lint

**Optional:** U9, U14, U18, U20, U21.

---

## Section 1 — Foundation: draw only what tty1 can draw (no layout change)

About 50 lines. Smallest and safest. It fixes visible bugs on its own.

### U1. Glyph fixes · core

- **What.** Next to the existing `GUM_*` exports:

  ```bash
  export GUM_CHOOSE_CURSOR="▶ " GUM_CHOOSE_CURSOR_PREFIX="· "
  export GUM_CHOOSE_SELECTED_PREFIX="■ " GUM_CHOOSE_UNSELECTED_PREFIX="· "
  export GUM_FILTER_INDICATOR="▶" GUM_SPIN_SPINNER=line
  ```

  Then make the per-call fixes:
  - Drop `--spinner dot` from the 5 `gum spin` calls, because a flag overrides the env var.
  - `finish()`: change `--border rounded` to `normal`.
  - `header()`: change `--border double` to `normal`. This is interim; U6 replaces the banner.
  - `finish()`: change the `→` in the keybinds to spacing.
- **Mockup** (firewall multi-select on tty1):

  ```
  today (row 1 toggled; gum's tick draws as ■) after
  > ■ SSH (port 22)                            ▶ ■ SSH (port 22)
    • HTTP/HTTPS (ports 80, 443)                 · HTTP/HTTPS (ports 80, 443)
  ```

- **Touches:** the top-of-file exports, `header`, `partition_disk`, `finish`.
- **Value:** high (it fixes visible breakage on every screen). **Risk:** none. **Stub:** none.
  Env vars never reach the stub, and `--spinner` already leaks its value harmlessly.
- **Verify:**
  - s5 `all` stays green.
  - VM (offline ISO): no `�` anywhere, the firewall prefixes show, the spinner turns.
  - Check the env var names with `gum choose --help` / `gum spin --help` on the ISO's gum. The
    lens docs say Arch ships gum 2.0.2, a major version bump; I have not verified that.
- **Feasibility: ok with change.**
  - Verified on gum 2.0.2 (the Arch version): all six variables exist and render as in the
    capture under Feasibility. `line` is ASCII `| / - \`. `dot` is braille.
  - The "today" mockup was wrong and has been corrected. The firewall list shows `•` until a
    row is toggled, and then gum's `✓` draws as `■` (U+FFFD's glyph). So today it only *looks*
    deliberate.
  - Add to the export block, at no stub cost: `GUM_CHOOSE_HEADER=""` (2.0.2 prints
    `Choose:`) and the `*_SHOW_HELP=false` / `*_PADDING` variables from finding 2.
  - **Fix the copy:** space does not toggle in 2.0.2. Change "space to select" to "x or tab to
    select", or leave this list's help line on.
  - Out of this file's scope: `nvidia-setup`'s `═` banner (see U4).

### U2. Status vocabulary and colour roles · core

- **What.** Rewrite the helpers with printf, using glyph marks and colour roles by ANSI index. Colour
  is on only when stdout is a terminal.

  ```bash
  if [[ -t 1 ]]; then UI_TTY=1
      C0=$'\e[0m' CB=$'\e[1m' CDIM=$'\e[90m' CSEA=$'\e[36m' CSEAB=$'\e[1;36m'
      CYOU=$'\e[1;35m' COK=$'\e[32m' CWARN=$'\e[1;33m' CBAD=$'\e[1;31m'
  else UI_TTY=0 C0='' CB='' CDIM='' CSEA='' CSEAB='' CYOU='' COK='' CWARN='' CBAD=''; fi

  info()    { printf '   %s\n' "$1"; }                               # questions, explanations
  doing()   { printf '   %s· %s%s\n' "$CDIM" "$1" "$C0"; }           # breadcrumb before a command
  success() { printf '   %s■%s %s\n' "$COK" "$C0" "$1"; }
  warn()    { printf '   %s! %s%s\n' "$CWARN" "$1" "$C0"; }
  die()     { printf '   %s× ERROR: %s%s\n' "$CBAD" "$1" "$C0"; exit 1; }
  you()     { printf '%s%s%s' "$CYOU" "$1" "$C0"; }                  # the user's own words
  ```

  The `GUM_*` colours move to indices:

  ```bash
  export GUM_CHOOSE_CURSOR_FOREGROUND=6 GUM_CHOOSE_SELECTED_FOREGROUND=2
  export GUM_INPUT_CURSOR_FOREGROUND=6 GUM_INPUT_PROMPT_FOREGROUND=5
  export GUM_CONFIRM_PROMPT_FOREGROUND=7 GUM_SPIN_SPINNER_FOREGROUND=6
  export GUM_CONFIRM_SELECTED_BACKGROUND=6 GUM_CONFIRM_SELECTED_FOREGROUND=0
  export GUM_CONFIRM_UNSELECTED_BACKGROUND=0 GUM_CONFIRM_UNSELECTED_FOREGROUND=7
  export GUM_FILTER_INDICATOR_FOREGROUND=6 GUM_FILTER_MATCH_FOREGROUND=5
  ```

  The inline `gum style --foreground="#…"` calls (in select_disk, configure_*, welcome and
  finish) become `info` lines or `--foreground=N`.
- **Mockup** (a stream of mixed lines, plain text):

  ```
     · Generating fstab
     ■ Swap file configured · 16GB
     ! Could not activate swap - continuing without it
     × ERROR: GRUB did not produce a bootable configuration in /boot
  ```

- **Touches:** `info`, `success`, `warn`, `die`, and new `doing`/`you`; the `GUM_*` block; inline
  `gum style --foreground` sites. `die()` stops depending on gum, so update the comment in `main()`
  that explains why the gum check comes first.
- **Value:** high (meaning survives a dim panel and a colour-blind reader).
- **Risk:** low.
  - `exit 1` stays in `die`.
  - `warn` is still a dumb, non-failing print inside `teardown_target` and `cleanup_on_failure`
    (printf is safer there than gum).
  - All asserted substrings still match, because only prefixes are added.
- **Verify:**
  - s5 `all` green; check that `out.log` contains glyphs and no escape codes.
  - Render capture of a scene script.
  - VM: confirm buttons show a cyan block on ink, and selection reads by luminance.
- **Feasibility: ok.**
  - Every `GUM_*` colour variable listed exists in 2.0.2.
  - Index values pass through as basic SGR (6 → `36`, 2 → `32`, 13 → `95`), and the confirm
    buttons come out `46`/`30` and `40`/`37`.
  - It fixes a real bug: today `warn` and `die` both land on SGR 91.
  - All asserted substrings survive. The streamed steps, traps and wrappers are untouched.
  - Stub: none, because printf replaces `gum style`.

### U3. Console palette · core (separable)

- **What.** The Linux console's own palette escape, set once on tty1. It turns the screen ink-dark
  the moment the installer starts, which says straight away that this is not the stock live shell.
  It also makes U2's roles exact.

  ```bash
  console_palette() {     # main(), after the root check. TERM=linux only: on xterm-likes an
      [[ ${TERM:-} == linux && -t 1 ]] || return 0      # unterminated OSC P eats output
      local i=0 c
      for c in 101418 f0635a 8fcf6b f2c14e 5a9bd8 ff9e64 4fd1c5 d8d3c4 \
               6b7585 ff8a80 b5e48c ffe08a 8ec5ff ffb38a 8af0e4 fbf7ec; do
          printf '\e]P%X%s' "$i" "$c"; i=$((i + 1))       # not ((i++)): rc 1 at 0 under set -e
      done
      clear
  }
  ```

- **Touches:** a new `console_palette`; one call in `main`.
- **Value:** medium-high (the identity moment; contrast guaranteed). **Risk:** low.
  - It runs before anything stateful.
  - Tests never call `main`.
  - Leaving the palette set at exit is fine on a live ISO (`printf '\e]R'` resets it).
- **Verify:** VM. Check that OSC P takes effect on the rig's `virtio-vga` fbcon (and on efifb if
  possible). Capture it with QEMU `screendump` (see Verification). If it doesn't take, the
  VGA fallback still keeps the roles; the renders checked that.
- **Feasibility: ok.**
  - The `ESC ] P n rrggbb` format and the `ESC ] R` reset are the Linux console's own.
    Whether it takes on fbcon can only be shown on the VM.
  - One side effect: gum's help-line separator `•` is emitted as SGR 30 and becomes invisible
    on slot 0. Harmless, and moot once help lines are hidden.
  - Stub: none.

### U4. Glyph lint (core) + tty renderer (optional)

- **What.**
  - `tests/glyph-lint.sh` extracts every non-ASCII character in
    `airootfs/usr/local/bin/*` and fails on anything outside the **shape-checked** kit above.
    The allowlist is written by hand, with a comment explaining why `▲ ▼ ↑ ↓ → ═ ║ ▓` are banned
    even though some of them are mapped.
  - Optional: commit the renderer as `tests/tty-render.py` (about 60 lines, no
    dependencies). It turns ANSI text into a PPM using `ter-116n.psf.gz`, taken from the
    terminus-font package, which you can extract without installing it. That makes "render capture" a
    repeatable check for every later item.
- **Touches:** new files under `tests/` only.
- **Value:** medium (it prevents the next `▲`). **Risk:** none.
- **Verify:** the lint fails on today's file (4× `→`; the only other non-ASCII are `•` and one `—`,
  both allowed) and passes after U1. It can't see glyphs that come from gum flags or defaults
  (`--border double`, `--spinner dot`, the `✓` prefix), so U1 adds a second grep that bans
  `--border (double|rounded|thick)` and `--spinner` values other than `line`/`ellipsis`.
- **Feasibility: ok with change.**
  - The installer's non-ASCII characters are as stated (4 `→`, 4 `•`, 1 `—`).
  - But the lint's scope, `usr/local/bin/*`, also contains `nvidia-setup`, which has 4 lines
    of `═` (256 characters). They form the legacy-GPU banner that prints on tty1 during
    `install_extras`. So the lint fails today there too. Fix those lines (`─`, or `=`) in the
    same commit, or exempt the file on purpose.
  - Because missing glyphs draw as `■`, the lint and the renderer's unmapped-glyph report are
    the only reliable detectors. The eye is not.

**Section 1 exit check:** s5 `all` green, the lint green, and one VM look. The VM look can be
batched with Section 2, because every ISO build is about an hour on CI.

---

## Section 2 — The spine and the tide (progress)

About 90 lines. This is the "sense of progress".

### U5. The step spine · core

- **What.** `main()` calls `step ID` before each group. `step` records per-chapter durations
  and moves the cursor. `header()` keeps its zero-argument signature and reads the state.

  ```bash
  STEPS=(disk you machine prepare base system apps extras dotfiles)   # U19 inserts review
  LABELS=(disk you machine "prepare disk" "base system" system apps extras dotfiles)
  STEP_N=0 STEP_T0=$SECONDS HEADER_N=-1 BOOTABLE=0 STEP_SECS=() STEP_SKIP=()
  step() {
      local i n=$(( ${#STEPS[@]} + 1 ))                  # unknown id = "done"
      for i in "${!STEPS[@]}"; do [[ ${STEPS[i]} == "$1" ]] && n=$((i + 1)); done
      (( STEP_N > 0 )) && STEP_SECS[STEP_N]=$(( SECONDS - STEP_T0 ))
      STEP_N=$n STEP_T0=$SECONDS
      return 0
  }
  step_skip() { STEP_SKIP[STEP_N]=1; }                   # setup_dotfiles' decline paths
  ```

  The new `main()` body:

  ```bash
  detect_offline_mode; console_palette
  welcome; validate_offline_repo; check_network
  step disk;     select_disk
  step you;      configure_user
  step machine;  configure_extras
  step prepare;  partition_disk; format_partitions; mount_partitions
  step base;     install_base
  step system;   configure_swap; configure_system
  step extras;   install_extras
  step apps;     install_aur_packages; run_user_installs
  step dotfiles; setup_dotfiles
  step done;     finish
  ```

- **Touches:** new globals at the top level (so they exist under the harness's `set -u`), `step`,
  `step_skip`, `main`, and `setup_dotfiles` (calls `step_skip` on its 4 skip returns).
- **Value:** high (every progress item builds on it). **Risk:** low.
  - The `(( ))` tests sit in `&&` lists or end in `return 0`, so `set -e` and ERR never see them.
  - Tests call step functions directly with `STEP_N=0` and get the prologue masthead.
- **Verify:** s5 `all`. Masthead labels never contain `failed` or `skipped`, which two scenarios
  `want_not`. A render capture of the masthead at each `step`.
- **Feasibility: ok.**
  - `step()` was run as written under `set -eEuo pipefail` with an ERR trap, with the
    sequence disk, you, done: n=1, 2, 10, and no ERR.
  - Two notes. The new `main()` body must keep the existing gum and root checks in front. Any
    reader of `STEP_SECS[i]` / `STEP_SKIP[i]` must use `${…:-}`, because s5 runs under `set -u`
    and unset elements are fatal there.
  - Stub: none.

### U6. The masthead and the tide · core

- **What.** `header()` draws 3 rows instead of 8:
  - row 1: the brand mark on the left, the chapter on the right;
  - row 2: the tide;
  - row 3: blank.

  The tide works like this: finished chapters roll in sea, the current chapter crests in bright
  sea, and the rest is calm `⎽` in dim. Because the wave's **shape** carries the progress, it reads on
  monochrome too.

  ```
   ◆ arch quickstart                                             hyprland on arch
   ⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽

   ◆ arch quickstart                                               1 of 10 · disk
   ⎽⎽⎽⎼⎻⎺⎺⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽

   ◆ arch quickstart                                       5 of 10 · prepare disk
   ⎽⎽⎽⎼⎻⎺⎺⎺⎻⎼⎽⎽⎽⎼⎻⎺⎺⎺⎻⎼⎽⎽⎽⎼⎻⎺⎺⎺⎻⎼⎽⎽⎽⎼⎻⎺⎺⎺⎻⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽

   ◆ arch quickstart  ■ orion boots on its own                     8 of 10 · apps
   ⎽⎽⎽⎼⎻⎺⎺⎺⎻⎼⎽⎽⎽⎼⎻⎺⎺⎺⎻⎼⎽⎽⎽⎼⎻⎺⎺⎺⎻⎼⎽⎽⎽⎼⎻⎺⎺⎺⎻⎼⎽⎽⎽⎼⎻⎺⎺⎺⎻⎼⎽⎽⎽⎼⎻⎺⎺⎺⎻⎼⎽⎽⎽⎼⎻⎺⎺⎺⎻⎼⎽⎽⎽⎽⎽⎽⎽⎽

   ◆ arch quickstart  ■ orion boots on its own                               done
   ⎽⎽⎽⎼⎻⎺⎺⎺⎻⎼⎽⎽⎽⎼⎻⎺⎺⎺⎻⎼⎽⎽⎽⎼⎻⎺⎺⎺⎻⎼⎽⎽⎽⎼⎻⎺⎺⎺⎻⎼⎽⎽⎽⎼⎻⎺⎺⎺⎻⎼⎽⎽⎽⎼⎻⎺⎺⎺⎻⎼⎽⎽⎽⎼⎻⎺⎺⎺⎻⎼⎽⎽⎽⎼⎻⎺⎺⎺
  ```

  On the console each glyph is a 1-pixel line at one of four heights. A period of 10 renders as
  broad swells, while 6 looks like dashes. Rendered PNGs from the prototype are in the
  scratchpad (`synth/waves.png`, `synth/mast.png`). The code is in `synth/ui-lib.sh`
  (`masthead`, `width`, `rep`). In outline:

  ```bash
  # Display width: bash runs in the C locale on tty1 (Ground truth 4)
  width() {
      local LC_ALL=C.UTF-8 s=$1 re=$'\e\\[[0-9;]*m'
      while [[ $s =~ $re ]]; do s=${s/"${BASH_REMATCH[0]}"/}; done
      UI_W=${#s}
  }
  # masthead: left = "◆ arch quickstart" (+ "■ HOST boots on its own" once BOOTABLE),
  # right = "N of T · label", padded to 78 with width(); then 78 cells of
  # wave=(⎽ ⎽ ⎽ ⎼ ⎻ ⎺ ⎺ ⎺ ⎻ ⎼): i < lo sea, lo <= i < hi bright sea, else dim "⎽",
  # lo = 78*(n-1)/T, hi = 78*n/T. Lines come out 79 columns: clear of the last-column wrap.
  ```

- **Touches:** `header` and a new `masthead`, `width` and `rep`.
- **Value:** high (identity and progress in one element, and 5 rows handed back on every screen).
- **Risk:** low. It is pure printf; `clear` happens today anyway.
- **Verify:**
  - Prototype checks passed under `set -eEuo pipefail` and `LC_ALL=C`: every line is at most
    79 columns, the return code is 0, and nothing reaches the ERR trap.
  - s5 `all`.
  - VM: the wave pixels, and the fit at 80x25. Run `stty rows 25 cols 80` before launching to fake
    the minimum size.
- **Feasibility: ok with change.**
  - Glyphs: the bitmaps were checked. `⎺⎻⎼⎽` are 1-pixel lines at rows 0, 4, 11 and 15 of the
    16-row cell. `◆` and `■` are distinct shapes. Every mockup line is 79 columns.
  - `width()` was re-tested with `◆` plus SGR under an exported `LC_ALL=C`: it returns 17.
  - **Change:** the left side `◆ arch quickstart  ■ HOST boots on its own` plus the longest
    right side (`10 of 10 · dotfiles`) only fits 79 columns while HOST is 19 characters or
    fewer. Hostnames can be 63. Truncate HOST with `…`, or drop the boot note when it doesn't fit.
  - Stub: none.

### U7. Clear only on a new chapter after the gate · core

- **What.** Before the disk is touched, every screen is a question, so it always starts clean
  (this is also safe with the `configure_*` / `connect_wifi` self-recursion). After the disk is
  touched, only a new chapter clears. partition, format and mount then build one continuous
  screen, and the AUR failure list stays up while user installs run.

  ```bash
  header() {
      if (( DISK_TOUCHED == 0 || STEP_N != HEADER_N )); then
          clear; (( UI_TTY )) && printf '\e[?5l'    # also undoes a U13 flash
          masthead
      else
          echo
      fi
      HEADER_N=$STEP_N
  }
  ```

- **Touches:** `header` only (it reads `DISK_TOUCHED`, never writes it).
- **Value:** medium (no flicker, and output you can't scroll back to is no longer thrown away).
  **Risk:** low. `clear` is stubbed to `:` in s5.
- **Verify:** s5 `all`. VM: watch the prepare and apps chapters each stay on one screen.
- **Feasibility: ok.**
  - Both `(( ))` tests sit in `if`/`&&` contexts, and `\e[?5l` is a Linux console mode.
  - Expect this: "stay on one screen" means *not cleared*. The prepare chapter (mkfs and
    btrfs output), base and apps all run past 25 rows, so the masthead scrolls off partway
    through them, and there is no scrollback to bring it back.
  - Stub: none (`clear` is stubbed).

### U8. The welcome hero · core

- **What.** The one screen with spare height gets the full identity:
  - a block-letter wordmark on the tide, with its reflection;
  - one warm line;
  - a promise that is true;
  - the route split into its two acts (this teaches the chapter names once and shows where the
    gate is);
  - the offline note as a `◆` line instead of today's all-caps banner;
  - named buttons.

  23 rows:

  ```

       ███  █   █ ███  ████ █   █  ████ █████  ███  ████  █████
      █   █ █   █  █  █     █  █  █       █   █   █ █   █   █
      █   █ █   █  █  █     ███    ███    █   █████ ████    █
      █  █  █   █  █  █     █  █      █   █   █   █ █  █    █
       ██ █  ███  ███  ████ █   █ ████    █   █   █ █   █   █
      ⎽⎽⎽⎼⎻⎺⎺⎺⎻⎼⎽⎽⎽⎼⎻⎺⎺⎺⎻⎼⎽⎽⎽⎼⎻⎺⎺⎺⎻⎼⎽⎽⎽⎼⎻⎺⎺⎺⎻⎼⎽⎽⎽⎼⎻⎺⎺⎺⎻⎼⎽⎽⎽⎼⎻⎺⎺⎺
       ░░ ░  ░░░  ░░░  ░░░░ ░   ░ ░░░░    ░   ░   ░ ░   ░   ░
      ░  ░  ░   ░  ░  ░     ░  ░      ░   ░   ░   ░ ░  ░    ░

     Hi. Let's build you a Hyprland desktop on Arch Linux.

     You answer a few questions, then it runs on its own. Nothing touches
     a disk until you type its name on the review screen.

     you answer  disk · you · machine · review
     then        prepare · base · system · apps · extras · dotfiles

     ◆ offline ISO   every package is already on this stick

     Ready?

        Let's go      Not now
  ```

  Colour: the letters in bold sea, the wave in sea, the reflection and route labels in dim.
  Until U19 lands, the promise reads "…until you type yes", and the route has no `review`. The
  call becomes `confirm --affirmative="Let's go" --negative="Not now" "Ready?"`. The `=` form
  means the stub drops it. The decline path stays the same (exit 0), with new copy: "No
  problem, nothing was changed. Run hyprland-install when you're ready."
- **Touches:** `welcome`.
- **Value:** high (the first impression). **Risk:** none (the confirm semantics are unchanged; no test
  covers welcome).
- **Verify:** render capture (done: `synth/welcome.png`); VM look.
- **Feasibility: ok with change.**
  - Glyphs `█ ░ ⎽⎼⎻⎺ ◆ ·` are all covered.
  - The mockup draws the confirm as 3 rows. Real gum 2.0.2 draws 5: prompt, blank, buttons,
    blank, and the help line `←→ toggle • enter submit • y Let's go • n Not now`. That makes
    the screen 25 rows, right at the limit. Set `GUM_CONFIRM_SHOW_HELP=false` (verified) to get
    back to 23.
  - `GUM_CONFIRM_PADDING="0 2"` puts `Ready?` at column 3 and the buttons at column 6, as drawn.
  - `--affirmative=`/`--negative=` exist; the stub drops the `=` form.
  - Esc here returns 1, which counts as "Not now" (exit 0), the same as today.

### U9. Two 0.3 s animations · optional

- **What.**
  - The wordmark rises out of the water on welcome: rows printed bottom-up with `sleep 0.03`.
  - The tide rolls in from chapter 10's edge to full on finish: 6 frames, `sleep 0.05`.
  - Both run once, only when `UI_TTY` and `TERM=linux`.
- **Value:** low-medium (pure garnish, and shorter than the `sleep 1`s the installer already has).
  **Risk:** none.
- **Verify:** VM.
- **Feasibility: ok.** Pure printf and `sleep` (stubbed in s5), gated on a terminal.

---

## Section 3 — The long middle: frames, ledger, checkpoint

About 60 lines. The streamed steps' I/O is **never** touched. Everything here is a print by the parent,
placed before or after the existing commands and their `|| rc=$?` guards.

### U10. Stream frames · core

- **What.** A labelled rule opens each streamed section, with a dim line that says what
  is normal. Machine output then runs flush left, untouched. A closing rule gives the outcome and the
  elapsed time.

  ```
     Installing 1,284 packages from the ISO. No downloads.

     ── pacstrap ────────────────────────────────────────────── live output ──
     pacman's (n/N) counter below is the real progress bar.
  :: Synchronizing package databases...
  (1283/1284) installing kitty                       [######################] 100%
  (1284/1284) installing yazi                        [######################] 100%
     ── ■ 1,284 packages ────────────────────────────────────────────── 3m 41s ──
     ■ Base system installed
  ```

  With failures (the warn lines stay; they are asserted):

  ```
     ── AUR builds ──────────────────────────────────────────── live output ──
     yay builds one package at a time. Its red ==> lines are its own.
  ==> ERROR: A failure occurred in build().
     ── ! 23 of 24 built ───────────────────────────────────────────── 12m 34s ──
     ! 1 AUR packages failed to build/install: hyprshot
     ! After rebooting, install manually with: yay -S hyprshot
  ```

  `stream_open LABEL [HINT]` and `stream_close ok|note TEXT` are about 20 lines; see
  `synth/ui-lib.sh`. Sites:

  | site | open | close |
  |---|---|---|
  | `install_base`, both branches | before `pacman -Sy` / `pacstrap` | after the `/mnt/usr/bin/ln` check |
  | `install_extras` | "drivers and services" before bluetooth-setup | after GPU |
  | `install_aur_packages` offline loop and online `arch-chroot … install-aur.sh` | before | after the `aur_rc` / `failed_packages` are known |
  | `run_user_installs` | before `trap ':' INT` | after `trap 'exit 130' INT` |
  | `apply_dotfiles` | before `trap ':' INT`, hint: "chezmoi may ask a question or two. Ctrl-C stops chezmoi only." | after `trap 'exit 130' INT` |

- **Touches:** `install_base`, `install_extras`, `install_aur_packages`, `run_user_installs`,
  `apply_dotfiles`, and the new `stream_open`/`stream_close`.
- **Value:** high (the scroll turns into a framed chapter, and you get a payoff number after the wait).
- **Risk:** low.
  - If a streamed command fails under `set -e`, the close rule is never printed, and the ERR line
    follows the open rule; that reads correctly.
  - **Wording rule:** success-path text must never contain `failed` or `skipped`. The scenarios
    `ui-offline-payload`, `aur-online-bootstrap-ok` and `aur-online-all-ok` `want_not` them.
  - Ctrl-C hints only state what is true today: stops chezmoi or the current user install only,
    and nothing about the AUR step (see F1).
  - `dot-ctrl-c`'s INT-trap assertion is unaffected, because the rules sit outside the bracket.
- **Verify:** s5 `all`. Grep `out.log` for both rules in the `aur-*`, `ui-*` and `dot-*` scenarios
  (assertions are optional to add). VM: online pacstrap and an offline AUR run.
- **Feasibility: ok with change.**
  - All five sites print before or after the existing command and its `|| rc=$?` guard, or
    outside the `trap ':' INT` bracket. No I/O is wrapped or redirected.
  - **Change:** `target-packages.x86_64` lists **110** names, and pacstrap pulls in
    dependencies, so "Installing 1,284 packages" can't be known up front. Before pacstrap, say
    "Installing 110 packages plus dependencies". For the close rule, count afterwards:
    `n=$(pacman -r /mnt -Qq 2>/dev/null | wc -l) || n=""`, after the `ln` check.
  - Mockup widths are fine: the rules are 79 columns, and pacman sizes its own lines.

### U11. Ledger for spinner and silent sub-steps · core

- **What.**
  - After each of `partition_disk`'s 5 `gum spin` calls, print a `success` line. The spinner shows
    what is running, and the ledger keeps what is done.
  - The ~30 `info "  Doing X..."` sub-lines (`format_partitions`, `mount_partitions`,
    `install_base`, `configure_swap`, `configure_system`) become `doing "X"`. These are dim
    breadcrumbs printed *before* the command, so on a failure the last breadcrumb names the step.
  - The `success "  Bluetooth configured!"`-style lines lose their leading spaces.

  ```
     ■ Wiped /dev/nvme0n1
     ■ GPT partition table
     ■ EFI partition, 512 MiB
     ■ Root partition
     · Formatting EFI partition (FAT32)
  mkfs.fat 4.2 (2021-01-31)
  ```

- **Touches:** the functions listed. The changes are mechanical.
- **Value:** medium. **Risk:** low. The asserted strings `Swap file configured` and
  `Could not activate swap` stay intact.
- **Verify:** s5 `all` (the `swap-*` scenarios cover `configure_swap`). Render capture.
- **Feasibility: ok.**
  - Output only. `gum spin`'s `line` frames are ASCII.
  - The mkfs lines in the mockup sit flush left as machine output.
  - Stub: none, since the `--spinner dot` value already leaked harmlessly.

### U12. The checkpoint · core

- **What.** At the end of `configure_system`, after the GRUB artifact check (only then is it
  true), replace `success "System configured!"` with a small card, set `BOOTABLE=1`, and hold for
  2 s. From then on, the masthead carries `■ orion boots on its own`. That keeps the reassurance on
  screen through the long AUR builds, where `==> ERROR` lines would otherwise look like disaster.

  ```
     ■ GRUB, plus the UEFI fallback loader
     ■ greetd, iwd, resolved

     ┌────────────────────────────────────────────────────────────────────────┐
     │ ◆ Checkpoint  orion can boot on its own now.                           │
     │                                                                        │
     │ The rest is extras: AUR apps, user installs, drivers, dotfiles.        │
     └────────────────────────────────────────────────────────────────────────┘
  ```

  A `box LINE...` helper (printf, 74 wide, measured with `width()`) is shared with U16.
- **Copy is deliberately limited.** It says "can boot on its own", which is true even if the
  installer later dies, because teardown only unmounts. It does **not** promise that "a failure
  later just becomes a note". That isn't true yet: `install_extras` runs under `set -e`, and
  Ctrl-C during the AUR step exits (F1, F2). Strengthen the copy once those are fixed.
- **Touches:** `configure_system` (tail), and the new `box` and `BOOTABLE`.
- **Value:** high (the emotional midpoint, built on a true fact). **Risk:** none. It is output only, with
  no prompt, in the no-abort zone.
- **Verify:** render capture (`synth/rc.png`); VM.
- **Feasibility: ok with change.**
  - The card itself works: placed after the GRUB artifact check, it is true, and it's
    output-only.
  - **Not true:** "the masthead carries it through the long AUR builds". yay, pacman and the
    user installs stream hundreds of lines within the same chapter (U7 doesn't clear), so the
    masthead is gone within seconds. The pinned header that could keep it is rejected.
  - **Change:** repeat the reassurance in the `extras`/`apps` stream-open hint instead, for
    example "orion already boots; these are extras." Keep within what F1 and F2 allow.
  - Truncate the hostname to keep the box 74 wide.

### U13. "Step away" and "your turn" · core (step-away copy gated, see F3)

- **What.**
  - The first post-gate screen and the `base`/`apps` open rules say *"Nothing to answer until
    dotfiles. Go make a coffee."*
  - At the top of `setup_dotfiles`, the screen briefly inverts using the console's own reverse-video
    mode, a visual bell that catches the eye from across the room:
    `(( UI_TTY )) && { printf '\e[?5h'; sleep 0.15; printf '\e[?5l'; }`. Then:

  ```
   ◆ arch quickstart  ■ orion boots on its own                10 of 10 · dotfiles
   ⎽⎽⎽⎼⎻⎺⎺⎺⎻⎼⎽⎽⎽⎼⎻⎺⎺⎺⎻⎼⎽⎽⎽⎼⎻⎺⎺⎺⎻⎼⎽⎽⎽⎼⎻⎺⎺⎺⎻⎼⎽⎽⎽⎼⎻⎺⎺⎺⎻⎼⎽⎽⎽⎼⎻⎺⎺⎺⎻⎼⎽⎽⎽⎼⎻⎺⎺⎺⎻⎼⎽⎽⎽⎼⎻⎺⎺⎺

     Welcome back. This one needs you.

     Your dotfiles are on this stick. Apply them now?

        Yes      No
  ```

  **Truth gate:** online, `makepkg -si` and `yay -S` run under `sudo -u $USERNAME` with no
  NOPASSWD rule (the drop-in exists only inside `apply_dotfiles`), so the AUR step probably asks for
  the user's password, perhaps more than once (F3). Until a VM run settles that, show the step-away
  line **only when `OFFLINE_MODE=1`**.
- **Touches:** `partition_disk` (one `info`), U10's hints, and the `setup_dotfiles` head.
  `header` resets the flash (U7).
- **Value:** medium-high. This is where the "it noticed I wasn't watching" delight comes from.
- **Risk:** low.
  - If Ctrl-C lands inside the 0.15 s, the screen stays inverted until the next `header`. That is
    cosmetic.
  - `sleep` is stubbed in s5, and the escape is gated on a terminal.
- **Verify:** s5 `dot-*`. VM: the flash is visible; an online run answers F3.
- **Feasibility: ok.**
  - The console implements DECSCNM (`?5h`/`?5l`). The mockup is 79 columns.
  - The dotfiles confirm stays a bare `gum confirm`. Esc returns 1 and Ctrl-C returns 130,
    and both mean "no", as today.
  - The F3 gate stands: `makepkg -si` and `yay` call sudo as the user, with only the
    password-required `10-wheel` rule in place.

### U14. Per-package rules for AUR and user installs · optional

- **What.** A light rule for each package: `── AUR 3/24 · hyprshot ──` in the offline loop (it
  replaces `info "  Installing $pkg..."`), in the `run_user_installs` loop, and online as a
  `printf` inside the `AURSCRIPT` heredoc (with escaped `\$`).
- **Value:** medium (yay has no counter of its own).
- **Risk:** low-medium. The heredoc line changes the generated script that the `aur-online-*`
  scenarios run. `printf` is a builtin, so the stubs-only PATH is fine.
- **Verify:** s5 `aur-*`, `ui-*`.
- **Feasibility: ok.**
  - `printf` is a builtin, so the stubs-only PATH is fine. The heredoc is unquoted, so escape
    `\$i`/`\$pkg`.
  - The rule text must avoid `failed`/`skipped` (`want_not` in `aur-online-bootstrap-ok` and `ui-offline-payload`).

---

## Section 4 — The ending and the voice

About 100 lines plus test edits.

### U15. Notes carried to the end · core

- **What.** With no scrollback, every warn-with-a-fix is lost at the next clear. Add
  `NOTES=()` and `note WHAT FIX` (one array append; it cannot fail) **next to** each existing
  warn. The warns stay, because the tests assert them. The sites:

  | where | note |
  |---|---|
  | `install_aur_packages`: offline fails, online fails, yay bootstrap | `yay -S <pkgs>` / install yay, then `yay -S <all>` |
  | `run_user_installs` failures | `user-installs-setup <names>` |
  | `dotfiles_retry_hint`, 3 branches | `chezmoi apply` / `chezmoi init --apply` / `dotfiles-setup <repo>` |
  | `apply_dotfiles`: sudoers rm failed | `sudo rm /etc/sudoers.d/90-arch-quickstart-install` |
  | `configure_swap`: offset or swapon failed | hibernation not enabled (no command) |
  | `restore_pacman_conf` (U16): `pacman -Sy` failed | `sudo pacman -Syu` |
  | `setup_dotfiles`: remote chosen, no network | `dotfiles-setup <repo>` |
  | `validate_offline_repo`: continued with missing packages | N packages were missing |

- **Touches:** the functions above, plus a top-level `NOTES=()`.
- **Value:** high (it is what makes the finish screen honest). **Risk:** none.
- **Verify:** s5 `all`. Optionally, each failing scenario echoes `${NOTES[*]}` in exec mode, and the
  test asserts it.
- **Feasibility: ok.**
  - Array appends can't fail, and `"${NOTES[@]}"` on an empty array is safe under `set -u`
    on bash 4.4 or later.
  - The warns stay, so the assertions stay. Stub: none.

### U16. The finish receipt · core

- **What.** Rewrite `finish()` as one screen that fits in 24 rows:
  - a card with the hostname and the user's name, the disk spec, the desktop spec (package count,
    dotfiles applied) and **built in** (timed from `DISK_TOUCHED=1`, so it is install time, not
    question time);
  - one line of per-chapter times from `STEP_SECS`, with a skipped chapter shown honestly;
  - the notes, each with its exact command, **or** "Nothing left to do. Clean run.";
  - the keybind cheat sheet **only** when dotfiles were not applied and there are no notes;
  - the reboot prompt.

  The offline `pacman.conf` restore moves out to `restore_pacman_conf`. It is the same code, its
  warn becomes a note, and `main` calls it before `step done`, so the card has the screen to itself.

  ```
   ◆ arch quickstart                                                         done
   ⎽⎽⎽⎼⎻⎺⎺⎺⎻⎼⎽⎽⎽⎼⎻⎺⎺⎺⎻⎼⎽⎽⎽⎼⎻⎺⎺⎺⎻⎼⎽⎽⎽⎼⎻⎺⎺⎺⎻⎼⎽⎽⎽⎼⎻⎺⎺⎺⎻⎼⎽⎽⎽⎼⎻⎺⎺⎺⎻⎼⎽⎽⎽⎼⎻⎺⎺⎺⎻⎼⎽⎽⎽⎼⎻⎺⎺⎺

     ┌────────────────────────────────────────────────────────────────────────┐
     │                                                                        │
     │ ◆ orion is ready. Welcome home, jacob.                                 │
     │                                                                        │
     │ disk      /dev/nvme0n1 · btrfs · encrypted                             │
     │ desktop   Hyprland · 1,284 packages · dotfiles applied                 │
     │ built in  21m 47s                                                      │
     │                                                                        │
     └────────────────────────────────────────────────────────────────────────┘

     prepare 0:21  base 6:41  system 2:05  apps 12:34  extras 0:48  dotfiles 1:18

     Two things to finish after you reboot:
     ! hyprshot didn't build          yay -S hyprshot
     ! one dotfiles script failed     chezmoi apply

     After the reboot, log in as jacob. Hyprland starts on its own.

     Reboot now?

        Reboot      Not yet
  ```

  A clean run without dotfiles swaps the notes for `■ Nothing left to do. Clean run.` and adds
  `SUPER+Enter terminal   SUPER+E files   SUPER+Q close   SUPER+1-9 workspaces`. With three or more
  notes, the card drops its blank padding rows to stay inside 25 rows.
- **The rest stays exactly as it is:**
  - the bare `gum confirm` (labels only: `--affirmative=Reboot --negative="Not yet"`);
  - `swapoff` before it;
  - `umount -R /mnt; DISK_TOUCHED=0; reboot`;
  - the decline path. Its copy becomes "Whenever you're ready: umount -R /mnt, then reboot."
- **Touches:** `finish`, a new `restore_pacman_conf`, `main`, `partition_disk`
  (`INSTALL_T0=$SECONDS` next to `DISK_TOUCHED=1`), and `setup_dotfiles` (`DOTFILES_APPLIED=1` on
  its 2 success paths).
- **Value:** high (the payoff screen; today it is about 37 rows, and its banner scrolls away before
  the prompt). **Risk:** low. Everything sits in code that must not abort; array appends and
  `SECONDS` arithmetic can't fail.
- **Verify:** render captures of the clean, notes and many-notes cases (the first two are done:
  `synth/af.png`). Optionally, an s5 scenario that calls `finish` with the stub's yes, plus `reboot` /
  `umount` stubs, asserting the notes appear and `umount -R /mnt` was logged. VM: a full run.
- **Feasibility: ok with change.**
  - The mockup is 24 rows, and it draws the confirm as 3. Real gum adds a blank row and a help
    line, which makes **26**. `GUM_CONFIRM_SHOW_HELP=false` is required, not optional.
  - The package count needs the post-install count from U10, guarded with `|| n=""`
    because this is the no-abort zone.
  - Truncate HOST and USER in the card. The `Welcome home` line overflows the 74-wide box
    once host plus user pass about 40 characters.
  - The keybind line is 78 columns: fine.
  - The reboot, umount and decline paths are unchanged.

### U17. Voice pass · core

- **What.** Apply the voice rules: drop the 33 `!`s and the `WARNING:` prefixes, and use the user's
  words. Also make two honest fixes and two kind ones:
  - **Honest:** print `AUR packages installed` only on a clean run, and say "1 of 2 AUR packages
    installed" otherwise.
  - **Honest:** offline with no network, "No network. The install doesn't need it; only a remote
    dotfiles repo would." The current line wrongly says dotfiles will be skipped (F5).
  - **Kind:** `cancelled()` branches on `DISK_TOUCHED` (read only; it still ends in `exit 130`).
  - **Kind:** welcome's decline copy (U8).

  ```
     ! Stopped. Nothing was written to any disk.
     Run hyprland-install whenever you're ready.

     ! Stopped. Cleaning up the partly written disk...      (on_exit's own lines follow)
  ```

  Key rewrites:

  | where | today | proposed |
  |---|---|---|
  | select_disk | Select the target disk for installation: | Which disk becomes the new system? |
  | select_disk | (not listing /dev/sdb - it is the installer boot medium) | · /dev/sdb is the stick you booted from, so it isn't listed |
  | select_disk | WARNING: All data on X will be destroyed! | ! Everything on X will be erased. There is no undo. (coral) |
  | select_disk | Are you sure you want to erase X? | Erase X?  `Erase it` / `Cancel` (default stays Cancel) |
  | configure_user | Configure your system: / Enter hostname: | Who's this machine for? / Name this machine |
  | configure_user | Enable full disk encryption? | Encrypt the disk? You'll type a passphrase at every boot. |
  | configure_extras | Select firewall rules to enable (space to select, enter to confirm): | Open any ports? Everything else stays closed. (space toggles, enter confirms) |
  | install_base | This will take several minutes (downloading packages)... | Installing N packages. This is the long part. |
  | install_aur_packages | AUR packages installed! *(even after failures)* | clean: ■ AUR packages installed · partial: no success line (the warn and close rule say it) |
  | run_user_installs | User installs done! | ■ User installs done |
  | setup_dotfiles | Apply pre-loaded dotfiles using chezmoi? | Your dotfiles are on this stick. Apply them now? |
  | setup_dotfiles | Dotfiles applied successfully! | ■ Dotfiles applied |
  | dotfiles_retry_hint | Some dotfiles did not apply (see above). After rebooting, run: chezmoi apply | Some dotfiles did not apply. After rebooting, run: chezmoi apply |

  **Test edits in the same commit:**
  - `want "AUR packages installed!"` becomes `want "AUR packages installed"` in all-ok and
    bootstrap-ok, and becomes `want_not` plus `want "1 of 2"` in `aur-online-one-fails` and
    `aur-offline-one-fails`.
  - `"User installs done!"` becomes `"User installs done"` (both the want and the want_not).
  - `"Dotfiles applied successfully!"` becomes `"Dotfiles applied"`.
  - The `dot-preloaded-fails` hint string loses "(see above)".
- **Touches:** strings across most functions, `cancelled`, and `tests/s5-runner.sh` assertions.
- **Value:** high (this is the character). **Risk:** low. Traps, return codes and wrappers don't change; the
  only coupling is the listed test edits.
- **Verify:** s5 `all` with the edited assertions. Mutation check: temporarily restore the "installed"
  line on the partial path, and `aur-*-one-fails` must fail.
- **Feasibility: ok with change.**
  - **Contradiction to settle first.** The text above says to print "1 of 2 AUR packages
    installed" on a partial run. The test edits say `want_not "AUR packages installed"`. With
    `grep -F`, that substring matches the partial line, so the test fails. Follow the
    key-rewrites table instead: no success line on a partial run, with "1 of 2" coming from
    U10's close rule (`! 1 of 2 built`). That makes U17 depend on U10. Or word the partial
    line without the substring.
  - The firewall row must say "x toggles" (space does nothing on 2.0.2).
  - `cancelled()`'s `DISK_TOUCHED=1` branch is effectively unreachable: no wrapper prompt
    runs after the gate, and Ctrl-C goes through `exit 130`, not `cancelled`. It is harmless.

### U18. Install report on the target · optional

- **What.** `finish` writes the receipt as plain text (no SGR) to `/mnt/var/log/arch-quickstart-install.txt`
  and `~/install-report.txt`. Every write is `|| true`, and the chown runs through the chroot. The
  card adds "Saved to ~/install-report.txt".
- **Value:** medium (the notes survive the reboot). **Risk:** low (the no-abort zone; `|| true`).
- **Verify:** VM: the file exists after a reboot.
- **Feasibility: ok.** File writes with `|| true` in the no-abort zone. Strip SGR (it comes
  out plain anyway when rendered with `UI_TTY=0`).

---

## Section 5 — The gate (a workflow change; review this one alone)

About 90 lines, stub knobs and new scenarios. It is the only section that **moves a safety
confirmation**.

### U19. The review screen, and typing the disk's name · core (medium risk)

- **What.** Today `select_disk` asks for the typed `yes` at chapter 1, before any settings, and the
  confirm that actually starts `wipefs` is `configure_extras`' "Proceed with these settings?".
  Instead:
  - Add `review_plan` as chapter 4 (`step review`) between `configure_extras` and `partition_disk`.
    It shows every answer on one card, says plainly that nothing has been written, and previews what
    runs on its own and where it will ask again.
  - The menu is a `prompt_choose` loop with: `Install on /dev/X`, `Change the disk`, `Change you`,
    `Change machine`, `Quit, nothing written`.
  - "Change …" runs `step disk; select_disk; step review` (and so on), then loops.
  - "Install" shows `lsblk -o NAME,SIZE,FSTYPE,LABEL "$DISK"` and asks the user to **type the disk's
    name** (`nvme0n1`; `/dev/nvme0n1` is also accepted). That proves they read *which* disk.
  - A mismatch still `die`s, exactly like today's mistyped `yes`. Esc goes through
    `prompt_input` to `cancelled` (130).
  - The gate line prints last, and then `step prepare` clears the screen.

  ```
   ◆ arch quickstart                                             4 of 10 · review
   ⎽⎽⎽⎼⎻⎺⎺⎺⎻⎼⎽⎽⎽⎼⎻⎺⎺⎺⎻⎼⎽⎽⎽⎼⎻⎺⎺⎺⎻⎼⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽⎽

     Nothing has been written yet. Here's the plan.

     disk       /dev/nvme0n1  953.9G  Samsung SSD 980 PRO
       becomes  EFI 512M · btrfs (5 subvolumes) · 16G swapfile · encrypted
     machine    orion · user jacob · America/Denver
     locale     en_US.UTF-8 · us keyboard
     git        jacob <you@example.com>
     graphics   nvidia (hybrid) · firewall deny all + SSH

     then, on its own: prepare · base · system · apps · extras
     it asks again at: dotfiles

     ▶ Install on /dev/nvme0n1
       Change the disk
       Change you
       Change machine
       Quit, nothing written
  ```

  ```
     ! Everything on /dev/nvme0n1 will be erased. There is no undo.

     NAME          SIZE FSTYPE LABEL
     nvme0n1     953.9G
     ├─nvme0n1p1   260M vfat   SYSTEM
     └─nvme0n1p2 953.6G ntfs   Windows

     Type the disk's name to erase it. Esc stops, nothing written.
     > nvme0n1

     ─── past the point of no return · writing to /dev/nvme0n1 ───
  ```

  The other changes that come with it:
  - `select_disk` keeps its soft `confirm --default=false` ("Erase X?") but loses the
    `prompt_input CONFIRM` block.
  - `configure_user` and `configure_extras` lose their summary blocks and "Proceed?" confirms,
    because the card replaces them. That also removes their self-recursion.
  - The swap size on the card is computed the same way `configure_swap` computes it (`free -m`),
    and `configure_swap` still does the work.
  - "Quit" behaves like welcome's decline (exit 0).
- **The invariant to review the diff against:** `DISK_TOUCHED=1` stays the first statement of
  `partition_disk` after the leftovers pre-flight, and the typed name is the **last** prompt
  before it. There must be exactly one gate.
- **Stub cost:**
  - Add knobs to the gum stub. When `S_GUM_CHOOSE` / `S_GUM_INPUT` are set, `choose` / `input` print
    them and exit 0 (about 6 lines). Today `choose` returns every option and `input` returns its
    placeholder.
  - Add an `lsblk` stub.
  - Add scenarios with exec-mode case `review-*) DISK=/dev/vda …; review_plan; echo "TOUCHED=$DISK_TOUCHED"`:
    - `review-install` (right name: rc 0, `TOUCHED=0`, no partitioning call);
    - `review-wrong-name` (rc 1, `TOUCHED=0`);
    - `review-quit` (rc 0).
- **Touches:** a new `review_plan`, `select_disk`, `configure_user`, `configure_extras`, `main`,
  `STEPS`, the welcome copy (U8), and `tests/s5-runner.sh` (stub plus 3 scenarios).
- **Value:** high (it closes a real gap: today the moment that destroys data is unlabelled).
- **Risk:** medium (it reorders pre-disk prompts). Every prompt goes through the existing wrappers, and
  everything happens while `DISK_TOUCHED=0`, so no teardown can trigger.
- **Verify:**
  - The 3 new s5 scenarios plus `all`.
  - VM: cancel at the review (Esc → 130, disks untouched); "Change you" round-trip; a wrong name
    gives the `die` pause and leaves the disk untouched (`lsblk` unchanged); a right name runs the
    full install.
- **Feasibility: ok with change.**
  - The menu mockup leaves out gum's chrome: the `Choose:` header, two blank rows and the help
    line. Without the env vars from finding 2 the screen grows by 4 rows. With
    `GUM_CHOOSE_HEADER=""` and `GUM_CHOOSE_SHOW_HELP=false` it renders as drawn (verified).
    The typed-name `gum input` also needs `GUM_INPUT_SHOW_HELP=false`.
  - Verified that Esc in `gum input` returns 1, which goes through `prompt_input` to
    `cancelled` (130).
  - The typed-name gate stays the last prompt before `DISK_TOUCHED=1`.
  - The `lsblk` tree in the mockup (`├─`) assumes a UTF-8 locale (finding 5).
  - Stub cost as listed: `S_GUM_CHOOSE`/`S_GUM_INPUT` knobs, an `lsblk` stub and 3 scenarios.
    Without the knob, `choose` returns every option on separate lines, and the menu `case`
    loops forever.

### U20. Re-ask on pre-disk typos · optional (changes `die` paths)

- **What.** Mismatched or empty passwords and passphrases, and a wrong typed disk name, re-ask up to 3
  times (`! Those didn't match. Try again (Esc cancels).`) instead of `die` + pause + starting over.
- **Value:** medium (kindness). **Risk:** low technically, because it all happens before the disk is
  touched. But it deliberately changes error-path behaviour, so it is the owner's call.
- **Verify:** s5 with the U19 knobs, extended to a sequence of inputs; VM.
- **Feasibility: ok.**
  - Everything happens before the disk is touched, through the wrappers.
  - It needs the stub knob to return a *sequence* of values, a few more lines than U19's.

### U21. Failure card in `on_exit` · optional, deferred

- **What.** This comes from the states doc: one printf card after cleanup and before the pause, giving the
  failed chapter, the command and line, a per-chapter "usually means", the disk state, and that a
  re-run is safe.
- **Why deferred.** It touches `on_exit`, the most safety-critical function. With U6 and U10, the
  masthead and the open rule already name the chapter on screen, and the existing lines already say
  "safe to re-run". Revisit after a VM failure run, if the context still feels thin. If it is done:
  use a subshell with `set +e … || true`, printf only, never gum, and an s5 `err-card` scenario
  asserting that `ERROR: Command failed` still prints first.
- **Feasibility: ok as deferred.** The constraints are stated correctly: printf only, a
  `set +e` subshell, and after cleanup.

---

## Considered and rejected

- **`[ OK ]` / `[WARN]` tag dialect (states P1).** It is the systemd boot log's look: functional,
  without character, and wider. Glyph marks plus words do the same job. setup-common's
  own `[INFO]` lines stay where they are, at column 0, as machine voice.
- **Double-line chrome, the `██ ▓▓ ░░ ║` rail, and the `pulse` spinner (wayfinding, states).** The glyphs
  aren't in the font. Kept from the rail: the spine, a count that doesn't change between ISO modes,
  and showing skips honestly.
- **`▲` as a mark (identity).** It draws `↑`.
- **A clock in the masthead (wayfinding P1).** It only updates on redraw, so it looks frozen.
- **A session transcript via `script` (states P4).** It puts a pty layer between the VT and
  pacman/yay/chezmoi, changes the launch path, and any chezmoi prompt that echoes would land in the log.
  The notes ledger covers the main loss (warnings). Revisit only if failure diagnosis proves painful.
- **A pinned header via a DECSTBM scroll region; a live ticking clock or background writer (wayfinding
  P9, states).** Programs that home the cursor break it, the region needs an `on_exit` reset, and a
  background writer interleaves bytes into pacman's output.
- **Percentages or byte-accurate bars.** Impossible with streamed steps, and they would lie. pacman's
  own `(n/N)` counter is pointed out instead (U10).
- **"Looks like an installed OS" detection on the erase screen (states P7).** `lsblk`'s
  FSTYPE/LABEL shows the facts. A heuristic that misses would give false comfort.
- **Dropping the `sleep 3`s (states P3).** Churn for no gain once U7 and U15 keep the warnings.
- **Unifying exit codes for the different "no"s (states appendix 3).** That is a semantics change,
  not UI. It is the owner's call, and BACKLOG material.
- **gum style for the chrome.** It costs stub flags for every value flag (`--width`), and it is
  unnecessary: `width()` measures correctly in the C locale.
- **Typewriter text, quips, `fortune`, beeps, centring, or a figlet masthead (identity's list).** I agree with the identity doc's reasons:
  they wear thin, cost height, and fight streamed output.

## Found on the way (not UI; BACKLOG candidates)

1. **F1. Ctrl-C during the AUR step aborts a bootable install.** INT is still `exit 130` in
   both branches of `install_aur_packages`. Offline, that also leaves the target's `pacman.conf`
   pointing at the offline repo, because `finish` is skipped. The fix is the `trap ':' INT` bracket
   already used by `run_user_installs` / `apply_dotfiles`. (From states.)
2. **F2. `install_extras` runs its four setup scripts bare under `set -e` after GRUB.** Several
   post-GRUB lines in `configure_system` (the `systemctl enable` calls) are also bare. Any failure
   there fires ERR and runs teardown on a bootable install, which contradicts "nothing may abort
   after bootable". The disk stays bootable, because teardown only unmounts, but the installer
   reports a failure and skips `finish`.
3. **F3. Online AUR builds probably prompt for the user's sudo password.** `makepkg -si` and
   `yay -S` run as the user with no NOPASSWD rule, and builds outlast sudo's 5-minute timestamp. Check
   during the D5 VM run. If confirmed, either give the AUR step the same temporary drop-in as
   `apply_dotfiles`, or say so in U13's copy.
4. **F4. "AUR packages installed!" prints after failures.** Fixed by U17.
5. **F5. The offline, no-network line says dotfiles setup "will be skipped".** Pre-loaded dotfiles
   still apply offline. Fixed by U17.
6. **F6. `.automated_script.sh` never runs** (its `locale-gen`, `pacman-key` and `setfont`). The font
   still comes from `vconsole.conf`, and `install_base` inits the keyring itself. The only visible
   effect is the C locale (Ground truth 4). Confirm with `locale` on tty1, then either wire it up
   or delete it. *(Second pass: it is `.bash_profile` that launches the installer, and the font
   comes from `vconsole.conf`. The C-locale effect is probably not real; see Feasibility, finding 5.)*
7. **F7. `finish()` overflows 25 rows today** (about 37 rows). Fixed by U16.

## Verification toolkit

- **s5:** `bash tests/s5-runner.sh all` (17 scenarios today, plus 3 from U19) after every item. It runs
  inside `unshare -rm` and touches nothing on the host.
- **Render capture:** run a scene script that sources the installer's helpers (or the exec-mode
  harness) with colour forced, then render the output with `ttyrender.py` (U4) through
  `ter-116n.psf.gz` and the U3 palette:
  `python3 -I ttyrender.py ter-116n.psf.gz scene.ans out.ppm --rows 25 && magick out.ppm out.png`.
  Add `--vga` to see the fallback palette. It reports any glyph that isn't in the font.
- **VM** (`~/vm-test`, offline ISO):
  - Add `-monitor unix:/tmp/qmon.sock,server,nowait`. It adds no PCI device, so NVRAM boot entries are
    safe. Then `echo 'screendump /tmp/s.ppm' | socat - UNIX:/tmp/qmon.sock` captures the real
    console. `stty rows 25 cols 80` on tty1 fakes the minimum size.
  - Each ISO build is about an hour on CI and is never pushed without the owner's go-ahead, so batch the
    VM passes: one after Sections 1-3, and one after Sections 4-5.
  - Checklist:
    - no `�`;
    - the palette takes effect on virtio-vga;
    - the gum env var names, and Esc → 130 on the ISO's gum (2.0.2 locally: the names are
      verified; Esc gives 1 on every prompt, which the wrappers turn into 130 but which
      means "no" for `confirm`; Ctrl-C gives 130);
    - no unexpected `■` (missing glyphs draw as `■`, not `�`);
    - `locale` and `locale -a | grep -i c.utf`;
    - the wave and the flash look right;
    - finish and review fit in 25 rows;
    - F3 (online run).
