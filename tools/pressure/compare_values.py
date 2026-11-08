#!/usr/bin/env python3
"""Compare two field-value files from tools/pressure/field_values.sh.

  tools/pressure/compare_values.py <before> <after>

A line is "<scope path> <field> <kind> <value>". The key is (scope path, field, n), where n numbers repeats
of one (scope, field) in file order. Prints each changed value ("changed"), each field present before and
missing after ("missing"), and each field only after ("added"; not a failure).
Exit: 0 equal (added fields allowed), 1 a value changed or a field is missing, 2 could not measure.
With INCURSION_PRESSURE_GROWS=1 (a case that adds resources) the module-shape lines of the data segment may differ
(printed `shape`), except a pool length or variable count that shrank.

  tools/pressure/compare_values.py --planted <fixture-values> <content-values>
prints what planting changed, for a human: `added` lines first, then `changed` ones, up to 8 lines, leaving out the
Game-scope counters (a call count differs between any two loads). Exit 0.
"""
import os
import sys


def load(path):
    rows = {}
    seen = {}
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line:
                continue
            parts = line.split(" ", 3)
            if len(parts) != 4:
                raise ValueError("malformed line: %r" % line[:80])
            scope, field, kind, value = parts
            n = seen.get((scope, field), 0)
            seen[(scope, field)] = n + 1
            rows[(scope, field, n)] = (kind, value)
    return rows


def shape_line(scope, field):
    """A line that describes the SHAPE of the module the writer ran in (the pool lengths and names of the data
    segment, its variable list and size), not a value the character holds. A case that adds resources to the
    module (a `grows-module` file in its directory; route.sh sets INCURSION_PRESSURE_GROWS=1) changes these lines
    for every save, by construction. Never set for any other case."""
    if scope.endswith("/Game") and field.startswith("MDataSegSize["):
        return True
    return "/Game.MDataSeg.Segment#" in scope and field.split("[")[0] in ("PoolLengths", "PoolNames", "Rows", "Variables", "VariableCount")


def renames():
    """INCURSION_PRESSURE_RENAMES="old>new|old2>new2": the resource renames the case makes on purpose (a `renames`
    file in its directory). A resource-id value that names `old` before and `new` after is the same resource: the
    value files print rIDs by name, so a legal rename would otherwise read as a change."""
    out = {}
    for pair in os.environ.get("INCURSION_PRESSURE_RENAMES", "").split("|"):
        if ">" in pair:
            o, n = pair.split(">", 1)
            out[o] = n
    return out


def renamed(kind, before, after, table):
    if kind != "rid" or "=" not in before or "=" not in after:
        return False
    bm, bv = before.split("=", 1)
    am, av = after.split("=", 1)
    return bm == am and table.get(bv) == av


def count_of(value):
    try:
        return int(value.rsplit("=", 1)[1])
    except (IndexError, ValueError):
        return None


def planted(argv):
    try:
        before, after = load(argv[2]), load(argv[3])
    except (OSError, ValueError) as e:
        print("compare_values: %s" % e, file=sys.stderr)
        return 2
    added = ["planted: added   %s %s %s" % (k[0], k[1], " ".join(v)) for k, v in sorted(after.items()) if k not in before]
    changed = ["planted: changed %s %s: %s %s -> %s %s" % (k[0], k[1], *before[k], *v) for k, v in sorted(after.items())
               if k in before and before[k] != v]
    for line in [x for x in added + changed if "/Game " not in x][:8]:
        print(line)
    return 0


def main(argv):
    if len(argv) == 4 and argv[1] == "--planted":
        return planted(argv)
    if len(argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    try:
        before, after = load(argv[1]), load(argv[2])
    except (OSError, ValueError) as e:
        print("compare_values: %s" % e, file=sys.stderr)
        return 2
    if not before or not after:
        print("compare_values: an input has no rows", file=sys.stderr)
        return 2
    bad = 0
    grows = os.environ.get("INCURSION_PRESSURE_GROWS") == "1"
    ren = renames()
    for k in sorted(before):
        tag = "%s %s" % (k[0], k[1])
        if k not in after:
            if grows and shape_line(k[0], k[1]):
                print("shape    %s gone" % tag)
                continue
            print("missing  %s (was %s %s)" % (tag, *before[k]))
            bad += 1
        elif after[k] != before[k]:
            if before[k][0] == after[k][0] and renamed(before[k][0], before[k][1], after[k][1], ren):
                print("renamed  %s: %s -> %s" % (tag, before[k][1], after[k][1]))
                continue
            if grows and shape_line(k[0], k[1]):
                # a module that grew keeps every pool at least as long and every variable it had; any other
                # difference of these lines is the new shape. A pool or count that SHRANK is still a failure.
                if k[1].split("[")[0] in ("PoolLengths", "VariableCount"):
                    b, a = count_of(before[k][1]), count_of(after[k][1])
                    if b is not None and a is not None and a < b:
                        print("changed  %s: %s %s -> %s %s" % (tag, *before[k], *after[k]))
                        bad += 1
                        continue
                print("shape    %s: %s -> %s" % (tag, before[k][1][-40:], after[k][1][-40:]))
                continue
            print("changed  %s: %s %s -> %s %s" % (tag, *before[k], *after[k]))
            bad += 1
    for k in sorted(after):
        if k not in before:
            print("added    %s %s %s" % (k[0], k[1], " ".join(after[k])))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
