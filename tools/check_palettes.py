#!/usr/bin/env python3
"""Check the colour palettes in both graphical backends.

Run: python3 tools/check_palettes.py

The palettes are plain C tables typed by hand in two files, and nothing in the
build makes them agree. This checks the four properties the engine relies on.
Each one has a real failure it catches, not a style preference:

  1. SIXTEEN ENTRIES.  Everything indexes a colour with `& COLOUR_MASK`
     (inc/Defines.h), so a short table is read out of bounds.

  2. NO DUPLICATE ENTRY inside one palette.  libtcodTerm reverse-looks-up an
     index by matching RGB (src/Wlibtcod.cpp, the `Colors[i].r == fgcolor.r`
     loops).  Two identical entries make that return the wrong index.

  3. INDEX i AND INDEX i|8 ARE THE SAME HUE.  BRIGHT_MASK is 8 and the engine
     ORs it in to brighten a glyph (src/Creature.cpp, src/MakeLev.cpp).  If the
     pair disagrees on hue, "bright green" comes out a different colour rather
     than a brighter green.  Near-neutral entries (black, the greys, white)
     have no meaningful hue and are skipped.

  4. THE TWO BACKENDS AGREE.  src/Wlibtcod.cpp and src/Wcurses.cpp each carry
     their own copy of every palette.  A palette present in both must hold the
     same numbers, or the SDL build and the curses build look different.

Exit status is 0 when every check passes, 1 otherwise.
"""
import re
import sys
import os

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIBTCOD = os.path.join(REPO, "src", "Wlibtcod.cpp")
CURSES = os.path.join(REPO, "src", "Wcurses.cpp")

MAX_COLOURS = 16
# How far apart two hues may sit and still count as the same colour. The pairs
# are hand-picked RGB, not computed, so they land a few degrees apart; 25 is
# wide enough for that and far narrower than the ~50 degrees between the
# palette's own neighbouring hues.
HUE_TOLERANCE_DEG = 25.0
# Below this saturation a colour has no usable hue, so rule 3 does not apply.
NEUTRAL_SAT = 0.10

# `TCOD_color_t RGBValues[MAX_COLOURS] = {` and the [3] variant in the curses
# backend. Only the table head differs between the two files.
TABLE_RE = re.compile(
    r"^\s*(?:TCOD_color_t|int32)\s+(RGB\w+)\s*\[MAX_COLOURS\](?:\[3\])?\s*=\s*\{",
    re.M)
ROW_RE = re.compile(r"\{\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\}")


def parse_tables(path):
    """Every RGB* palette in one source file, as {name: [(r,g,b), ...]}."""
    with open(path) as fh:
        text = fh.read()
    tables = {}
    for m in TABLE_RE.finditer(text):
        name = m.group(1)
        end = text.index("};", m.end())
        rows = ROW_RE.findall(text[m.end():end])
        tables[name] = [tuple(int(v) for v in row) for row in rows]
    return tables


def saturation(c):
    mx, mn = max(c), min(c)
    return (mx - mn) / mx if mx else 0.0


def hue_deg(c):
    """Hue in degrees, 0..360. Undefined for a grey; callers screen those out."""
    r, g, b = (v / 255.0 for v in c)
    mx, mn = max(r, g, b), min(r, g, b)
    d = mx - mn
    if d == 0:
        return 0.0
    if mx == r:
        h = ((g - b) / d) % 6
    elif mx == g:
        h = (b - r) / d + 2
    else:
        h = (r - g) / d + 4
    return h * 60.0


def hue_gap(a, b):
    """Smallest angle between two hues, 0..180."""
    d = abs(hue_deg(a) - hue_deg(b)) % 360.0
    return min(d, 360.0 - d)


def check_table(where, name, rows, fails):
    if len(rows) != MAX_COLOURS:
        fails.append("%s %s: has %d entries, needs %d"
                     % (where, name, len(rows), MAX_COLOURS))
        return
    seen = {}
    for i, c in enumerate(rows):
        if c in seen:
            fails.append("%s %s: entry %d duplicates entry %d, both %s -- the "
                         "RGB reverse lookup cannot tell them apart"
                         % (where, name, i, seen[c], c))
        seen[c] = i
    for i in range(MAX_COLOURS // 2):
        dark, bright = rows[i], rows[i + 8]
        if saturation(dark) < NEUTRAL_SAT or saturation(bright) < NEUTRAL_SAT:
            continue
        gap = hue_gap(dark, bright)
        if gap > HUE_TOLERANCE_DEG:
            fails.append("%s %s: entry %d %s and its bright partner %d %s are "
                         "%.0f degrees apart in hue, over the %.0f allowed"
                         % (where, name, i, dark, i + 8, bright,
                            gap, HUE_TOLERANCE_DEG))


def main():
    fails = []
    libtcod = parse_tables(LIBTCOD)
    curses = parse_tables(CURSES)

    if not libtcod:
        fails.append("src/Wlibtcod.cpp: found no palette tables at all")
    if not curses:
        fails.append("src/Wcurses.cpp: found no palette tables at all")

    for name, rows in sorted(libtcod.items()):
        check_table("src/Wlibtcod.cpp", name, rows, fails)
    for name, rows in sorted(curses.items()):
        check_table("src/Wcurses.cpp", name, rows, fails)

    for name in sorted(set(libtcod) & set(curses)):
        if libtcod[name] != curses[name]:
            differing = [i for i, (a, b) in
                         enumerate(zip(libtcod[name], curses[name])) if a != b]
            fails.append("%s differs between the backends at entries %s: "
                         "Wlibtcod has %s, Wcurses has %s"
                         % (name, differing,
                            [libtcod[name][i] for i in differing],
                            [curses[name][i] for i in differing]))

    if fails:
        print("check_palettes: FAIL")
        for f in fails:
            print("  " + f)
        return 1

    shared = sorted(set(libtcod) & set(curses))
    print("check_palettes: OK -- %d palettes in src/Wlibtcod.cpp (%s), "
          "%d in src/Wcurses.cpp, %d shared and identical"
          % (len(libtcod), ", ".join(sorted(libtcod)), len(curses), len(shared)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
