#!/usr/bin/env python3
"""tty-render: draw terminal output the way the live ISO's tty1 shows it.

Takes text with ANSI escapes (a capture of the installer, a scene script's
output, an s5 out.log) and draws it pixel for pixel through the console font
the ISO ships (ter-116n, 8x16, 256 glyphs) on an 80-column screen, with the
Linux console's own colour rules: 16 foregrounds, 8 backgrounds, bold drawn
as the bright partner. It also reports what tty1 would get wrong:

  * characters ter-116n has no glyph for (they draw as a small filled
    square, the same glyph as the installer's "done" mark, so the eye
    cannot be trusted to spot them);
  * lines wider than 79 columns (they wrap on an 80-column console).

Either problem makes the exit status 1. The image is written regardless.

Usage:
  tests/tty-render.py [options] IN OUT.png|OUT.ppm
  tests/tty-render.py --check IN           # report only, no image

  --rows N      screen height, default 25 (tty1's minimum). Output scrolls
                like the console's (no scrollback since Linux 5.9): only the
                last N rows are kept. 0 grows to fit everything instead.
  --cols N      screen width, default 80
  --vga         the kernel's default palette, ignoring any palette the input
                sets: the fallback when the installer's palette does not take
  --font PATH   the PSF1 console font
  --pty         IN is a raw capture of a pty (script(1), a pty driver): a
                bare LF moves down without returning to column 0, as it
                does while a program like gum has the tty in raw mode. By
                default IN is taken as a file, where LF is a new line.

Palette: starts as the one console_palette() in hyprland-install sets (read
from that file), and follows OSC P / OSC R escapes in the input, as the
console does.

Screen model: printable text, CR, LF, BS, TAB, SGR colours, `clear`
(ED/CUP), cursor movement (CUU/CUD/CUF/CUB/CHA/CUP), erase in line (EL), and
DECSCNM (the whole screen in reverse video). Enough for printf output and
gum's redraws; other escapes are dropped.

The font is not in the repo. The renderer looks for, in order: --font,
$TTY_FONT, tests/ter-116n.psf.gz, /usr/share/kbd/consolefonts/ter-116n.psf.gz
(the terminus-font package). To fetch it without installing anything:

  curl -sL "$(pacman -Sp terminus-font)" \\
    | bsdtar -xOf - usr/share/kbd/consolefonts/ter-116n.psf.gz \\
    > tests/ter-116n.psf.gz

(off Arch: download terminus-font-*-any.pkg.tar.zst from any Arch mirror's
extra/os/x86_64/ and extract the same path with `tar --zstd`).

Standard library only.
"""
import argparse
import gzip
import os
import re
import struct
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
INSTALLER = os.path.join(HERE, '..', 'archiso', 'airootfs', 'usr', 'local',
                         'bin', 'hyprland-install')
FONT_PATHS = [os.path.join(HERE, 'ter-116n.psf.gz'),
              '/usr/share/kbd/consolefonts/ter-116n.psf.gz']

# The kernel's default console palette (drivers/tty/vt/vt.c)
VGA = ['000000', 'aa0000', '00aa00', 'aa5500', '0000aa', 'aa00aa', '00aaaa',
       'aaaaaa', '555555', 'ff5555', '55ff55', 'ffff55', '5555ff', 'ff55ff',
       '55ffff', 'ffffff']


def installer_palette():
    """The 16 colours console_palette() sets, or VGA if it can't be read."""
    try:
        src = open(INSTALLER, encoding='utf-8').read()
    except OSError:
        return list(VGA)
    m = re.search(r'console_palette\(\)\s*\{.*?for c in (.*?);\s*do', src, re.S)
    cols = re.findall(r'\b[0-9a-fA-F]{6}\b', m.group(1)) if m else []
    return cols if len(cols) == 16 else list(VGA)


def load_font(path):
    """PSF1 font: (height, glyph bitmaps, {codepoint: glyph index})."""
    d = gzip.open(path).read() if path.endswith('.gz') else open(path, 'rb').read()
    if d[:2] != b'\x36\x04':
        sys.exit(f'{path}: not a PSF1 font')
    mode, h = d[2], d[3]
    n = 512 if mode & 1 else 256
    glyphs = [d[4 + i * h:4 + (i + 1) * h] for i in range(n)]
    umap = {}
    if mode & 2:                       # PSF1_MODEHASTAB
        tab, g, i = d[4 + n * h:], 0, 0
        while i + 1 < len(tab) and g < n:
            v = struct.unpack('<H', tab[i:i + 2])[0]
            i += 2
            if v == 0xFFFF:
                g += 1
            elif v != 0xFFFE:          # sequences (after FFFE) are skipped
                umap.setdefault(v, g)
    else:
        umap = {c: c for c in range(n)}
    return h, glyphs, umap


class Screen:
    def __init__(self, cols, rows):
        self.W, self.H = cols, rows    # rows 0: unlimited, no scrolling
        self.fg, self.bg, self.bold, self.rev = 7, 0, False, False
        self.reverse_screen = False
        self.seen = set()              # every character drawn, scrolled off or not
        self.wide = []                 # rows that reached the last column
        self.clear()

    def blank(self):
        return [(' ', 7, 0)] * self.W

    def clear(self):
        self.grid = [self.blank() for _ in range(self.H or 1)]
        self.x = self.y = 0
        self.pending = False           # deferred wrap at the last column

    def row(self, y):
        while y >= len(self.grid):
            if self.H and len(self.grid) >= self.H:
                self.grid.pop(0)       # scrolled off: gone, as on tty1
                y -= 1
                self.y -= 1
            else:
                self.grid.append(self.blank())
        return y

    def linefeed(self):
        self.pending = False
        self.y = self.row(self.y + 1)

    def put(self, ch):
        self.seen.add(ch)
        if self.pending:
            self.x = 0
            self.linefeed()
        f = self.fg | (8 if self.bold and self.fg < 8 else 0)
        b = self.bg
        if self.rev:
            f, b = b, f & 7
        self.y = self.row(self.y)
        r = self.grid[self.y]
        r[self.x] = (ch, f, b)
        if self.x == self.W - 1:
            self.pending = True
            self.wide.append(''.join(c for c, _, _ in r).strip())
        else:
            self.x += 1

    def sgr(self, params):
        for p in (params or '0').split(';'):
            p = int(p.split(':')[0] or 0)
            if p == 0:
                self.fg, self.bg, self.bold, self.rev = 7, 0, False, False
            elif p == 1:
                self.bold = True
            elif p in (21, 22):
                self.bold = False
            elif p == 7:
                self.rev = True
            elif p == 27:
                self.rev = False
            elif 30 <= p <= 37:
                self.fg = p - 30
            elif p == 39:
                self.fg = 7
            elif 40 <= p <= 47:
                self.bg = p - 40
            elif p == 49:
                self.bg = 0
            elif 90 <= p <= 97:
                self.fg = p - 90 + 8
            elif 100 <= p <= 107:      # no bright backgrounds on the console
                self.bg = p - 100

    def csi(self, priv, params, final):
        ps = [int(p.split(':')[0] or 0) for p in params.split(';')] if params else []
        n = max(ps[0], 1) if ps else 1
        if final == 'm' and not priv:
            self.sgr(params)
            return
        if priv == '?' and params == '5' and final in 'hl':
            self.reverse_screen = final == 'h'
            return
        if priv:
            return
        self.pending = False
        if final == 'A':
            self.y = max(0, self.y - n)
        elif final == 'B':
            self.y = self.row(self.y + n)
        elif final == 'C':
            self.x = min(self.W - 1, self.x + n)
        elif final == 'D':
            self.x = max(0, self.x - n)
        elif final == 'G':
            self.x = min(self.W - 1, n - 1)
        elif final in 'Hf':
            r = (ps[0] if ps else 1) or 1
            c = (ps[1] if len(ps) > 1 else 1) or 1
            self.y = self.row(r - 1)
            self.x = min(self.W - 1, c - 1)
        elif final == 'J':
            mode = ps[0] if ps else 0
            if mode in (2, 3):
                x, y = self.x, self.y
                self.grid = [self.blank() for _ in range(len(self.grid))]
                self.x, self.y = x, y
            elif mode == 0:
                r = self.grid[self.y]
                self.grid[self.y] = r[:self.x] + [(' ', 7, 0)] * (self.W - self.x)
                for i in range(self.y + 1, len(self.grid)):
                    self.grid[i] = self.blank()
        elif final == 'K':
            mode = ps[0] if ps else 0
            r = self.grid[self.row(self.y)]
            if mode == 0:
                self.grid[self.y] = r[:self.x] + [(' ', 7, 0)] * (self.W - self.x)
            elif mode == 1:
                self.grid[self.y] = [(' ', 7, 0)] * (self.x + 1) + r[self.x + 1:]
            else:
                self.grid[self.y] = self.blank()


TOKEN = re.compile(
    r'\x1b\[([?>=<]?)([0-9;:]*)[ -/]*([@-~])'  # CSI
    r'|\x1b\]P([0-9a-fA-F])([0-9a-fA-F]{6})'   # OSC P: set palette slot
    r'|\x1b\]R'                                # OSC R: reset palette
    r'|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)'      # other OSC: dropped
    r'|\x1b[()][0-9A-Za-z]|\x1b[^\[\]]'        # charset / other ESC: dropped
    r'|([\r\n\b\t])'
    r'|([^\x00-\x1f\x7f])', re.S)


def run(text, scr, pal, base, honour_osc, pty):
    for m in TOKEN.finditer(text):
        csi_final, slot, ctl, ch = m.group(3), m.group(4), m.group(6), m.group(7)
        if csi_final:
            scr.csi(m.group(1), m.group(2), csi_final)
        elif slot:
            if honour_osc:
                pal[int(slot, 16)] = m.group(5)
        elif m.group(0) == '\x1b]R':
            if honour_osc:
                pal[:] = base
        elif ctl == '\n':
            if not pty:                # a file: the tty's onlcr adds the CR
                scr.x = 0
            scr.linefeed()
        elif ctl == '\r':
            scr.x, scr.pending = 0, False
        elif ctl == '\b':
            scr.x, scr.pending = max(0, scr.x - 1), False
        elif ctl == '\t':
            scr.x = min(scr.W - 1, (scr.x // 8 + 1) * 8)
        elif ch:
            scr.put(ch)
    return scr


def write_image(path, w, h, rgb):
    if path.endswith('.png'):
        stride = w * 3
        raw = b''.join(b'\0' + bytes(rgb[y * stride:(y + 1) * stride]) for y in range(h))

        def chunk(t, d):
            return (struct.pack('>I', len(d)) + t + d
                    + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff))
        data = (b'\x89PNG\r\n\x1a\n'
                + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
                + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))
    else:
        data = b'P6 %d %d 255\n' % (w, h) + bytes(rgb)
    with open(path, 'wb') as fo:
        fo.write(data)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('input')
    ap.add_argument('output', nargs='?')
    ap.add_argument('--rows', type=int, default=25)
    ap.add_argument('--cols', type=int, default=80)
    ap.add_argument('--vga', action='store_true')
    ap.add_argument('--font')
    ap.add_argument('--check', action='store_true')
    ap.add_argument('--pty', action='store_true')
    a = ap.parse_args()
    if not a.check and not a.output:
        ap.error('OUT is required unless --check')

    font = a.font or os.environ.get('TTY_FONT') \
        or next((p for p in FONT_PATHS if os.path.exists(p)), None)
    if not font or not os.path.exists(font):
        sys.exit('tty-render: no ter-116n.psf.gz found; see the fetch '
                 'instructions at the top of tests/tty-render.py')
    h, glyphs, umap = load_font(font)
    repl = umap.get(0xFFFD, umap.get(ord('?'), 0))

    text = open(a.input, encoding='utf-8', errors='replace', newline='').read()
    if not a.pty:
        # A file's last newline ends its last line; it is not a row of its
        # own (on the console it would scroll a full screen up by one)
        text = text[:-1] if text.endswith('\n') else text
    base = list(VGA) if a.vga else installer_palette()
    pal = list(base)
    scr = run(text, Screen(a.cols, a.rows), pal, base, not a.vga, a.pty)

    status = 0
    missing = sorted(c for c in scr.seen if ord(c) > 127 and ord(c) not in umap)
    if missing:
        status = 1
        print('MISSING GLYPHS (draw as a square on tty1): '
              + ' '.join(f'{c} U+{ord(c):04X}' for c in missing), file=sys.stderr)
    for line in scr.wide:
        status = 1
        print(f'line reaches column {a.cols} (max {a.cols - 1}): {line[:60]}...',
              file=sys.stderr)

    if not a.check:
        rgb = [tuple(int(c[k:k + 2], 16) for k in (0, 2, 4)) for c in pal]
        px = bytearray()
        for r in scr.grid:
            for y in range(h):
                for ch, f, b in r:
                    if scr.reverse_screen:
                        f, b = b, f
                    bits = glyphs[umap.get(ord(ch), repl)][y]
                    fgc, bgc = rgb[f], rgb[b]
                    for x in range(8):
                        px += bytes(fgc if bits & (0x80 >> x) else bgc)
        write_image(a.output, a.cols * 8, len(scr.grid) * h, px)
    sys.exit(status)


if __name__ == '__main__':
    main()
