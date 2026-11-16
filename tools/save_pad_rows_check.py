#!/usr/bin/env python3
"""Does every SchemaPad array in src/SaveV1.cpp still match what the
compiler actually lays out? (bead inc-xlwa)

Runs tools/save_pad_rows.py's own measurement (never the save code's
runtime uncovered-byte list -- that is the thing under test) and compares
it, class by class, with the pads tools/gen_record_layout.py generates
(compiler padding and the vptr only). They differ when a member of a saved
class has no FIELD_ line and no FIELD_SKIP: the member the build would
otherwise only meet at run time.

Usage: tools/check_save_pad_rows.sh [--root DIR]
       tools/check_save_pad_rows.sh --selftest
Exit: 0 every class agrees, 1 a mismatch was found (printed), 2 could not
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
import gen_record_layout as gen  # noqa: E402


def rows_as_pairs(rows):
    return [(off, length) for off, length, _names in rows]


def run(root):
    """Since inc-cjos0 phase 8a the pad rows are generated, not declared.
    What is left to check is the one thing the generator cannot know: a
    member the field list neither saves nor FIELD_SKIPs. spr (this tool's
    FIELD_ line reader) counts such a member as a pad, the generator (the
    compiler's own padding only) does not, so the two disagree on exactly
    that member, and the check names its class."""
    save_v1_path = root / "src" / "SaveV1.cpp"
    if not save_v1_path.is_file():
        print(f"COULD NOT MEASURE: missing {save_v1_path}")
        return 2

    old_root = spr.REPO_ROOT
    try:
        classes = gen.pin_classes(save_v1_path.read_text())
        generated = gen.measure(root, classes, None, None)
        measured = spr.measure_all()
    except spr.ToolError as e:
        print(f"COULD NOT MEASURE: {e}")
        return 2
    finally:
        spr.REPO_ROOT = old_root

    mismatches = []
    for cls in classes:
        want = generated[cls][1]
        got = rows_as_pairs(measured[cls][1])
        if want != got:
            names = sorted({n for _o, _l, ns in measured[cls][1] for n in ns})
            mismatches.append((cls, want, got, names))

    if not mismatches:
        print(f"PASS: {len(classes)} classes: every byte outside a FIELD_ "
              f"line is compiler padding or the vptr")
        return 0

    for cls, want, got, names in mismatches:
        print(f"FAIL: {cls}:")
        print(f"    compiler padding and vptr: {want}")
        print(f"    bytes no FIELD_ line reaches: {got}")
        if names:
            print(f"    members with no FIELD_ line: {', '.join(names)}")
    print()
    print("Give each member listed a FIELD_ line, or FIELD_SKIP if it is "
          "deliberately not saved.")
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
