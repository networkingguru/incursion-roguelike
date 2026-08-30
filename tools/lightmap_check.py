#!/usr/bin/env python3
"""Does the light map obey its two invariants? Reads logs/light.log.

The log is written by src/Light.cpp when INCURSION_LIGHT_PROBE is set. Each
block: a header, one "S x y r red green blue kind cells" line per source, then
the source-light grid with ambient left out: '#' opaque unlit, '%' opaque lit,
'.' unlit, '0'-'9' lit and how brightly.

Invariants checked, on every block:
  1. A lit cell is within radius of a source that reaches it: a straight line
     from the source, in either axis-major rasterisation, crosses no opaque
     cell strictly between them. This is an independent re-implementation of
     the game's line-of-sight rule, not a call into it.
  2. A player who carries a light stands on a lit cell.

Usage: tools/lightmap_check.py <light.log>      exit 0 pass, 1 fail, 2 no blocks
       tools/lightmap_check.py --selftest       proves both assertions bite
"""
import re
import sys

HEADER = re.compile(r"^LIGHT map=(\d+) (\d+) player=(-?\d+) (-?\d+) plight=(\d+) sources=(\d+)$")


def parse(text):
    lines = text.splitlines()
    i, blocks = 0, []
    while i < len(lines):
        m = HEADER.match(lines[i])
        if not m:
            i += 1
            continue
        w, h, px, py, plight, n = (int(g) for g in m.groups())
        i += 1
        sources = []
        for _ in range(n):
            f = lines[i].split()
            sources.append((int(f[1]), int(f[2]), int(f[3])))
            i += 1
        grid = lines[i:i + h]
        i += h
        blocks.append(dict(w=w, h=h, px=px, py=py, plight=plight,
                           sources=sources, grid=grid))
    return blocks


def opaque(grid, x, y):
    return grid[y][x] in "#%"


def clear_line(grid, sx, sy, tx, ty):
    """True if some axis-major line from (sx,sy) to (tx,ty) has no opaque
    cell strictly between the endpoints."""
    dx, dy = tx - sx, ty - sy
    steps = max(abs(dx), abs(dy))
    if steps <= 1:
        return True
    for major in ("x", "y"):
        n = abs(dx) if major == "x" else abs(dy)
        if n == 0:
            continue
        ok = True
        for k in range(1, n):
            x = sx + round(dx * k / n)
            y = sy + round(dy * k / n)
            if (x, y) != (tx, ty) and opaque(grid, x, y):
                ok = False
                break
        if ok:
            return True
    return False


def check_block(b, where):
    fails = []
    if len(b["grid"]) != b["h"] or any(len(r) != b["w"] for r in b["grid"]):
        return ["%s: grid is not %dx%d" % (where, b["w"], b["h"])]
    g = b["grid"]
    for y in range(b["h"]):
        for x in range(b["w"]):
            ch = g[y][x]
            if ch in ".#":
                continue
            reached = any(max(abs(x - sx), abs(y - sy)) <= r and clear_line(g, sx, sy, x, y)
                          for sx, sy, r in b["sources"])
            if not reached:
                fails.append("%s: cell (%d,%d) is lit '%s' but no source reaches it"
                             % (where, x, y, ch))
    px, py = b["px"], b["py"]
    if b["plight"] > 0 and 0 <= px < b["w"] and 0 <= py < b["h"]:
        if g[py][px] in ".#":
            fails.append("%s: player at (%d,%d) carries light %d but the cell is unlit"
                         % (where, px, py, b["plight"]))
    return fails


def check(text):
    blocks = parse(text)
    if not blocks:
        return 2, ["no LIGHT blocks found"]
    if not any(b["sources"] for b in blocks):
        return 2, ["no block has a source, so invariant 1 was never exercised"]
    fails = []
    for n, b in enumerate(blocks):
        fails += check_block(b, "block %d" % (n + 1))
    return (1 if fails else 0), fails


def selftest():
    good = ("LIGHT map=7 5 player=1 2 plight=2 sources=1\n"
            "S 1 2 3 255 147 41 0 9\n"
            ".......\n"
            "..2#...\n"
            "132#...\n"
            "..2#...\n"
            ".......\n")
    wall_leak = good.replace("132#...", "132#.2.")
    dark_player = good.replace("132#...", "1.2#...")
    results = [
        ("a clean block passes", check(good)[0] == 0),
        ("light behind a wall fails", check(wall_leak)[0] == 1),
        ("an unlit player with a light fails", check(dark_player)[0] == 1),
        ("an empty log is inconclusive", check("")[0] == 2),
        ("a log with no source is inconclusive",
         check(good.replace("sources=1\nS 1 2 3 255 147 41 0 9\n", "sources=0\n")
                   .replace("132#...", "...#...").replace("..2#...", "...#..."))[0] == 2),
    ]
    ok = True
    for name, passed in results:
        print(("  ok   " if passed else "  FAIL ") + name)
        ok = ok and passed
    return 0 if ok else 1


def main(argv):
    if len(argv) == 2 and argv[1] == "--selftest":
        return selftest()
    if len(argv) != 2:
        print(__doc__)
        return 2
    with open(argv[1]) as fp:
        code, msgs = check(fp.read())
    for m in msgs[:20]:
        print(("FAIL: " if code == 1 else "INCONCLUSIVE: ") + m)
    if code == 0:
        print("light map: every lit cell is reached by a source, player lit")
    return code


if __name__ == "__main__":
    sys.exit(main(sys.argv))
