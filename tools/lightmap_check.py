#!/usr/bin/env python3
"""Does the light map obey its invariants? Reads logs/light.log.

The log is written by src/Light.cpp when INCURSION_LIGHT_PROBE is set. Each
block: a header, one "S x y r red green blue kind cells" line per source, then
the source-light grid with ambient left out: '#' opaque unlit, '%' opaque lit,
'.' unlit, '0'-'9' lit and how brightly.

Invariants checked, on every block:
  1. A lit cell is within radius under the game's distance metric of a source
     that reaches it: a straight line from the source, in either axis-major
     rasterisation, crosses no opaque cell strictly between them. This is an
     independent re-implementation of the game's line-of-sight rule, not a
     call into it.
  2. A player who carries a light stands on a lit cell.
  3. Every non-opaque neighbour of a source with radius at least one is lit.
  4. Among cells reached by only one source, brightness never rises with
     distance from that same source.

Usage: tools/lightmap_check.py <light.log>      exit 0 pass, 1 fail, 2 no blocks
       tools/lightmap_check.py --selftest       proves all four assertions bite
"""
import re
import sys

HEADER = re.compile(r"^LIGHT map=(\d+) (\d+) player=(-?\d+) (-?\d+) plight=(\d+) sources=(\d+)$")


def game_distance(dx, dy):
    """Mirror dist() in inc/Inline.h independently, without calling the game."""
    a, b = abs(dx), abs(dy)
    return a + b // 2 if a > b else b + a // 2


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
        filter_grid = None
        if i < len(lines) and lines[i] == "FILTER":
            i += 1
            filter_grid = lines[i:i + h]
            i += h
        blocks.append(dict(w=w, h=h, px=px, py=py, plight=plight,
                           sources=sources, grid=grid, filter=filter_grid))
    return blocks


def opaque(grid, x, y):
    return grid[y][x] in "#%"


def lit(grid, x, y):
    return grid[y][x] == "%" or grid[y][x].isdigit()


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


def crosses_filter(b, sx, sy, tx, ty):
    if b["filter"] is None:
        return False
    dx, dy = tx - sx, ty - sy
    n = max(abs(dx), abs(dy))
    for k in range(1, n):
        x = sx + round(dx * k / n)
        y = sy + round(dy * k / n)
        if 0 <= x < b["w"] and 0 <= y < b["h"] and b["filter"][y][x] != "-":
            return True
    return False


def check_block(b, where):
    fails = []
    if len(b["grid"]) != b["h"] or any(len(r) != b["w"] for r in b["grid"]):
        return ["%s: grid is not %dx%d" % (where, b["w"], b["h"])]
    if b["filter"] is not None and (len(b["filter"]) != b["h"]
                                    or any(len(r) != b["w"] for r in b["filter"])):
        return ["%s: FILTER grid is not %dx%d" % (where, b["w"], b["h"])]
    g = b["grid"]
    sole_lit = {}
    for y in range(b["h"]):
        for x in range(b["w"]):
            ch = g[y][x]
            if ch in ".#":
                continue
            reached = [n for n, (sx, sy, r) in enumerate(b["sources"])
                       if game_distance(x - sx, y - sy) <= r
                       and clear_line(g, sx, sy, x, y)]
            if not reached:
                fails.append("%s: cell (%d,%d) is lit '%s' but no source reaches it"
                             % (where, x, y, ch))
            elif len(reached) == 1 and ch.isdigit():
                n = reached[0]
                sx, sy, unused_r = b["sources"][n]
                if crosses_filter(b, sx, sy, x, y):
                    continue
                distance = game_distance(x - sx, y - sy)
                sole_lit.setdefault(n, {}).setdefault(distance, []).append(
                    (int(ch), x, y))
    px, py = b["px"], b["py"]
    if b["plight"] > 0 and 0 <= px < b["w"] and 0 <= py < b["h"]:
        if g[py][px] in ".#":
            fails.append("%s: player at (%d,%d) carries light %d but the cell is unlit"
                         % (where, px, py, b["plight"]))
    for sx, sy, r in b["sources"]:
        if r < 1:
            continue
        # Every adjacent cell has game distance 1, so radius >= 1 reaches it.
        for y in range(max(0, sy - 1), min(b["h"], sy + 2)):
            for x in range(max(0, sx - 1), min(b["w"], sx + 2)):
                if (x, y) == (sx, sy) or opaque(g, x, y):
                    continue
                if not lit(g, x, y):
                    fails.append("%s: source (%d,%d) radius %d has dark neighbour (%d,%d)"
                                 % (where, sx, sy, r, x, y))
    for n, by_distance in sole_lit.items():
        sx, sy, unused_r = b["sources"][n]
        nearest_min = None
        for distance in sorted(by_distance):
            if nearest_min is not None:
                av, ax, ay, ad = nearest_min
                for bv, bx, by in by_distance[distance]:
                    if av < bv:
                        fails.append(
                            "%s: source (%d,%d) cell (%d,%d) distance %d digit %d "
                            "is dimmer than cell (%d,%d) distance %d digit %d"
                            % (where, sx, sy, ax, ay, ad, av,
                               bx, by, distance, bv))
            distance_min = min(by_distance[distance])
            candidate = (distance_min[0], distance_min[1],
                         distance_min[2], distance)
            if nearest_min is None or candidate[0] < nearest_min[0]:
                nearest_min = candidate
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
            "888#...\n"
            "898#...\n"
            "888#...\n"
            ".......\n")
    wall_leak = good.replace("898#...", "898#.2.")
    dark_player = good.replace("898#...", "8.8#...")
    source_only = good.replace("888#...", "...#...").replace("898#...", ".9.#...")
    rising = good.replace(".......\n888#...", ".9.....\n888#...", 1)
    two_source_rising = ("LIGHT map=11 3 player=-1 -1 plight=0 sources=2\n"
                         "S 1 1 2 255 147 41 0 9\n"
                         "S 9 1 1 255 147 41 0 9\n"
                         "5558....777\n"
                         "5958....797\n"
                         "5558....777\n")
    two_source_overlap = ("LIGHT map=7 3 player=-1 -1 plight=0 sources=2\n"
                          "S 2 1 2 255 147 41 0 9\n"
                          "S 4 1 2 255 147 41 0 9\n"
                          "5599955\n"
                          "5599955\n"
                          "5599955\n")
    game_metric_order = ("LIGHT map=11 7 player=-1 -1 plight=0 sources=1\n"
                         "S 5 5 6 255 147 41 0 9\n"
                         ".....5.....\n"
                         ".........4.\n"
                         "...........\n"
                         "...........\n"
                         "....888....\n"
                         "....898....\n"
                         "....888....\n")
    filtered_rise = ("LIGHT map=7 7 player=-1 -1 plight=0 sources=1\n"
                     "S 1 3 4 255 147 41 0 9\n"
                     ".4.....\n"
                     ".......\n"
                     "888....\n"
                     "8982...\n"
                     "888....\n"
                     ".......\n"
                     ".......\n"
                     "FILTER\n"
                     "-------\n"
                     "-------\n"
                     "-------\n"
                     "--i----\n"
                     "-------\n"
                     "-------\n"
                     "-------\n")
    unmarked_filtered_rise = filtered_rise.split("FILTER\n", 1)[0]
    results = [
        ("a clean block passes", check(good)[0] == 0),
        ("light behind a wall fails", check(wall_leak)[0] == 1),
        ("an unlit player with a light fails", check(dark_player)[0] == 1),
        ("an empty log is inconclusive", check("")[0] == 2),
        ("a log with no source is inconclusive",
         check(good.replace("sources=1\nS 1 2 3 255 147 41 0 9\n", "sources=0\n")
                   .replace("898#...", "...#...").replace("888#...", "...#..."))[0] == 2),
        ("a source that lights only its own square fails", check(source_only)[0] == 1),
        ("brightness that rises with distance fails", check(rising)[0] == 1),
        ("a two-source block still checks a sole-lit cell",
         check(two_source_rising)[0] == 1),
        ("two sources summing on one cell is not a failure",
         check(two_source_overlap)[0] == 0),
        ("the game's distance metric, not Chebyshev, orders the cells",
         check(game_metric_order)[0] == 0),
        ("filtered rays are exempt from monotonicity",
         check(filtered_rise)[0] == 0),
        ("the same dim ray without FILTER fails monotonicity",
         check(unmarked_filtered_rise)[0] == 1),
    ]
    ok = True
    for name, passed in results:
        print(("  ok   " if passed else "  FAIL ") + name)
        ok = ok and passed
    print("selftest: %d/%d passed" % (sum(passed for unused, passed in results),
                                      len(results)))
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
