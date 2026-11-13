#!/usr/bin/env bash
# glyph-lint — fail on any character the live ISO's console cannot draw as
# meant, in the scripts that print on tty1 during an install.
#
# tty1 is the Linux console with ter-116n, a 256-glyph font. A character
# outside it draws as a small filled square, the same glyph as the "done"
# mark, so a missing glyph hides in plain sight and the eye cannot be
# trusted to catch it. This lint (and tests/tty-render.py's missing-glyph
# report) can.
#
# Usage: bash tests/glyph-lint.sh [FILE...]   (default: the scripts below)
#
# Three checks:
#  1. Every non-ASCII character is in ALLOWED, a hand-written list of glyphs
#     whose bitmaps were looked at, not merely "mapped in the font".
#  2. gum flags that draw glyphs the source never spells out: --border
#     other than normal/hidden/none, --spinner (-s) other than
#     line/ellipsis, or a value the lint cannot read (a variable, or one
#     continued on the next line).
#  3. gum defaults that draw such glyphs: a script that runs a gum
#     subcommand must export the GUM_* variables that replace them, the
#     help lines set to false and Choose's header to empty.
set -euo pipefail

# FILE arguments are taken relative to where the lint was run, and a
# missing one is an error, not a silent pass
files=()
for a in "$@"; do
    [[ -f "$a" ]] || { echo "glyph-lint: no such file: $a" >&2; exit 2; }
    files+=("$(readlink -f "$a")")
done

cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.."
export LC_ALL=C.UTF-8

# Drawn as intended on tty1 (UI-NOTES, Ground truth 3 and the glyph kit):
#   box drawing, single line only      ─ │ ┌ ┐ └ ┘ ├ ┤ ┬ ┴ ┼
#   the tide, four scan-line heights   ⎽ ⎼ ⎻ ⎺
#   shades                             █ ▒ ░
#   marks                              ■ ▶ ◀ ◆ • · ×
#   typography                         … — – « »
ALLOWED='─│┌┐└┘├┤┬┴┼⎽⎼⎻⎺█▒░■▶◀◆•·×…—–«»'

# Known traps, with the reason. Some of these ARE mapped in ter-116n, which
# is why "in the font" is not the test:
#   ▲ ▼   mapped, but to the ↑ ↓ arrow bitmaps: a triangle draws as an arrow
#   ↑ ↓   share their bitmap with ▲ ▼, so neither can be trusted to read as
#         what was written
#   → ←   share their bitmaps with ▶ ◀: an arrow draws as a filled triangle
#   ═ ║   not in the font (no double-line box drawing at all; the corners
#         ╔ ╗ ╚ ╝ neither), so they draw as squares
#   ╭ ╮ ╰ ╯  rounded corners: not in the font
#   ▓ ▀ ▄ ▌ ▐  dark shade and half blocks: not in the font
#   ✓ ✗   not in the font (gum choose's default selected prefix is ✓)
#   braille (U+2800-28FF): not in the font (gum spin's default `dot`)
declare -A WHY=(
    [▲]="draws as the up arrow"   [▼]="draws as the down arrow"
    [↑]="shares its glyph with ▲" [↓]="shares its glyph with ▼"
    [→]="draws as a filled triangle (▶)" [←]="draws as a filled triangle (◀)"
    [═]="not in the font (no double-line box drawing); use ─"
    [║]="not in the font (no double-line box drawing); use │"
    [╔]="not in the font; use ┌" [╗]="not in the font; use ┐"
    [╚]="not in the font; use └" [╝]="not in the font; use ┘"
    [╭]="not in the font; use ┌" [╮]="not in the font; use ┐"
    [╰]="not in the font; use └" [╯]="not in the font; use ┘"
    [▓]="not in the font; use █ or ▒"
    [✓]="not in the font; use ■" [✗]="not in the font; use ×"
)

if (( ! $# )); then
    files=(archiso/airootfs/usr/local/bin/*
           archiso/airootfs/usr/local/lib/*.sh
           archiso/airootfs/usr/local/share/user-installs/*/*)
fi

bad=0
report() { printf '%s\n' "$1"; bad=1; }

# flag_values REGEX FILE: "line:value" for every match of REGEX (its first
# group is the value) on each line that is not all comment. Every match, so
# a second flag on one line is checked too
flag_values() {
    FV_RE=$1 perl -ne 'next if /^\s*#/; while (/$ENV{FV_RE}/g) { print "$.:$1\n" }' "$2" || true
}

# check_value WHERE FLAG VALUE OK SAY: VALUE (a shell word, perhaps quoted)
# must be a literal matching the OK alternatives
check_value() {
    local v="$3"
    v=${v#[\"\']}; v=${v%%[\"\';)]*}
    if [[ ! "$v" =~ ^[a-z-]+$ ]]; then
        report "$1: $2 '$3' is not a literal on this line, so it cannot be checked; use $5"
    elif [[ ! "$v" =~ ^($4)$ ]]; then
        report "$1: $2 '$v' draws glyphs tty1 lacks; use $5"
    fi
}

for f in "${files[@]}"; do
    [[ -f "$f" ]] || continue

    # 1. Characters. -a: a file with invalid UTF-8 would otherwise be
    # "binary" to grep and pass unread; its bad bytes are reported below
    if ! iconv -f UTF-8 -t UTF-8 "$f" >/dev/null 2>&1; then
        report "$f: not valid UTF-8 (the console would draw its bad bytes as squares)"
    fi
    while IFS=: read -r line ch; do
        [[ "$ALLOWED" == *"$ch"* ]] && continue
        why="${WHY[$ch]:-not in the shape-checked kit}"
        report "$f:$line: '$ch' (U+$(printf '%04X' "'$ch")) $why"
    done < <(grep -anoP '[^\x00-\x7F]' "$f" | awk '!seen[$0]++' || true)

    # 2. gum flags whose glyphs never appear in the source. The value must
    # be a literal on the same line: a variable, or a value continued on
    # the next line, is one the lint cannot check, so it is refused too.
    # A line that is all comment is passed over: it runs nothing
    while IFS=: read -r line val; do
        check_value "$f:$line" "--border" "$val" "normal|hidden|none" normal
    done < <(flag_values '--border[= ]+(\S+)' "$f")
    # -s is gum spin's short --spinner, looked for before the command's --
    while IFS=: read -r line val; do
        check_value "$f:$line" spinner "$val" "line|ellipsis" "line or ellipsis"
    done < <(flag_values '(?:--spinner[= ]+|GUM_SPIN_SPINNER=)(\S+)' "$f"
             grep -noP -- '^(?!\s*#).*?gum +spin((?! -- ).)*?(?<![[:alnum:]_-])-s[= ]+\K\S+' "$f" || true)

    # 3. gum defaults whose glyphs never appear in the source
    for pair in \
        "spin:GUM_SPIN_SPINNER" \
        "choose:GUM_CHOOSE_SELECTED_PREFIX GUM_CHOOSE_SHOW_HELP GUM_CHOOSE_HEADER" \
        "filter:GUM_FILTER_SELECTED_PREFIX GUM_FILTER_UNSELECTED_PREFIX GUM_FILTER_SHOW_HELP" \
        "confirm:GUM_CONFIRM_SHOW_HELP" \
        "input:GUM_INPUT_SHOW_HELP"; do
        sub=${pair%%:*}
        grep -qE "(^|[^[:alnum:]_-])gum +$sub( |$)" "$f" || continue
        for var in ${pair#*:}; do
            # a commented-out assignment does not count
            if ! grep -qE "^[^#]*(^|[[:space:]])$var=" "$f"; then
                report "$f: runs gum $sub but never sets $var (its default draws glyphs tty1 lacks or a help line)"
                continue
            fi
            # The value matters too: true brings the help line back, and a
            # Choose header is a line the screens do not budget for
            case $var in
                *_SHOW_HELP) want='false([[:space:]]|$)' say=false ;;
                *_HEADER)    want='(""|'"''"'|)([[:space:]]|$)' say='""' ;;
                *)           continue ;;
            esac
            grep -qE "^[^#]*(^|[[:space:]])$var=$want" "$f" \
                || report "$f: $var must be set to $say"
        done
    done
done

if (( bad )); then
    echo "glyph-lint: FAILED (see tests/glyph-lint.sh for the kit and why)" >&2
    exit 1
fi
echo "glyph-lint: ok (${#files[@]} files)"
