#!/usr/bin/env python3
"""Does every SchemaPad array in src/SaveV1.cpp still match what the
compiler actually lays out? (bead inc-xlwa)

Runs tools/save_pad_rows.py's own measurement (never the save code's
runtime uncovered-byte list -- that is the thing under test) and compares
it, array by array, against what src/SaveV1.cpp currently declares. A
class whose members moved (an inc-30ps-shaped change: a member inserted
that does not grow sizeof()) silently goes stale here without this check,
because the pinned pads are hand-written and nothing recomputes them.

Usage: tools/check_save_pad_rows.sh [--root DIR]
       tools/check_save_pad_rows.sh --selftest
Exit: 0 every array agrees, 1 a mismatch was found (printed), 2 could not
measure (see tools/save_pad_rows.py's own error).
"""

import argparse
import re
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import save_pad_rows as spr  # noqa: E402


def parse_declared_arrays(save_v1_path):
    """{ArrayName: [(off,len), ...]} for every
    'static const SchemaPad XxxPads[] = { {a,b}, ... };' in src/SaveV1.cpp."""
    text = save_v1_path.read_text()
    arrays = {}
    decl_re = re.compile(
        r"static const SchemaPad (\w+)\[\]\s*=\s*\{(.*?)\};",
        re.DOTALL,
    )
    pair_re = re.compile(r"\{\s*(\d+)\s*,\s*(\d+)\s*\}")
    for m in decl_re.finditer(text):
        name = m.group(1)
        pairs = [(int(a), int(b)) for a, b in pair_re.findall(m.group(2))]
        arrays[name] = pairs
    return arrays


def rows_as_pairs(rows):
    return [(off, length) for off, length, _names in rows]


def run(root):
    save_v1_path = root / "src" / "SaveV1.cpp"
    if not save_v1_path.is_file():
        print(f"COULD NOT MEASURE: missing {save_v1_path}")
        return 2

    old_root = spr.REPO_ROOT
    spr.REPO_ROOT = root
    try:
        measured = spr.measure_all()
    except spr.ToolError as e:
        print(f"COULD NOT MEASURE: {e}")
        return 2
    finally:
        spr.REPO_ROOT = old_root

    declared = parse_declared_arrays(save_v1_path)

    seen_arrays = {}
    for cls, array in spr.SCHEMA_PINS:
        seen_arrays.setdefault(array, cls)

    mismatches = []

    for array, primary_cls in seen_arrays.items():
        measured_sizeof, measured_rows = measured[primary_cls]
        measured_pairs = rows_as_pairs(measured_rows)
        declared_pairs = declared.get(array)
        if declared_pairs is None:
            mismatches.append((
                array, primary_cls,
                "src/SaveV1.cpp declares no such array",
                measured_pairs,
            ))
            continue
        if declared_pairs != measured_pairs:
            mismatches.append((array, primary_cls, declared_pairs,
                                measured_pairs))

    # A class that reuses another's array (Coin -> ItemPads, Armour ->
    # QItemPads) must also measure the same as that array itself.
    for cls, array in spr.SCHEMA_PINS:
        primary_cls = seen_arrays[array]
        if cls == primary_cls:
            continue
        own_sizeof, own_rows = measured[cls]
        primary_sizeof, primary_rows = measured[primary_cls]
        if rows_as_pairs(own_rows) != rows_as_pairs(primary_rows):
            mismatches.append((
                array, cls,
                f"{primary_cls}'s own measured rows "
                f"{rows_as_pairs(primary_rows)}",
                rows_as_pairs(own_rows),
            ))

    if not mismatches:
        print(f"PASS: {len(seen_arrays)} SchemaPad arrays agree with the "
              f"compiler's own layout")
        return 0

    for array, cls, declared_pairs, measured_pairs in mismatches:
        print(f"FAIL: {cls} ({array}):")
        print(f"    declared: {declared_pairs}")
        print(f"    measured: {measured_pairs}")
    print()
    print("Run tools/save_pad_rows.py and paste its output over the "
          "matching arrays in src/SaveV1.cpp.")
    return 1


def selftest():
    """Copy the tree into a scratch dir, insert an unarchived member into
    inc/Creature.h right after TouchDef, and confirm this check goes red
    and names Creature. Cleans up after itself either way."""
    repo_root = Path(__file__).resolve().parent.parent
    with tempfile.TemporaryDirectory(prefix="check_save_pad_rows-selftest-") as td:
        scratch = Path(td) / "tree"
        # Only what the measurement needs: headers, source, module data,
        # and this tool. Excludes build/ and other large/irrelevant dirs.
        needed = ["inc", "src", "lib", "compat", "tools"]
        scratch.mkdir()
        for name in needed:
            src_dir = repo_root / name
            if src_dir.is_dir():
                subprocess.run(
                    ["cp", "-R", str(src_dir), str(scratch / name)],
                    check=True,
                )

        green = run(scratch)
        if green != 0:
            print("SELFTEST FAIL: the unmodified scratch copy did not "
                  "pass (expected exit 0)")
            return 1

        creature_h = scratch / "inc" / "Creature.h"
        text = creature_h.read_text()
        needle = "int16  TouchDef;"
        if needle not in text:
            print(f"SELFTEST FAIL: {needle!r} not found in "
                  f"inc/Creature.h -- cannot insert the probe member")
            return 1
        text = text.replace(needle, needle + "\n      int16 XlwaProbe;", 1)
        creature_h.write_text(text)

        red = run(scratch)
        if red == 0:
            print("SELFTEST FAIL: the check still passed after inserting "
                  "an unarchived member into Creature")
            return 1

    print("SELFTEST PASS: an unarchived member in Creature turns this "
          "check red, and cleanup succeeded")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=None)
    parser.add_argument("--selftest", action="store_true")
    args = parser.parse_args()

    if args.selftest:
        return selftest()

    root = Path(args.root).resolve() if args.root else spr.REPO_ROOT
    return run(root)


if __name__ == "__main__":
    sys.exit(main())
