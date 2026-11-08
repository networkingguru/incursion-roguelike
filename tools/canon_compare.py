#!/usr/bin/env python3
"""Compare two canonical character dumps (tools/char_dump.sh) outside ONE
allowlist, defined here and nowhere else (bead inc-10v7f, spec 8 and A7).

A dump of a character built from a .char and a dump of the same character
walked through the screens differ in facts that are not part of the character:
the clock, the map he stands on, the flavors, a generation counter. This file
names each kind of line it drops. Everything else MUST match byte for byte.

Usage: tools/canon_compare.py [--all] <a.canon> <b.canon>   exit 0 same, 1 differ
                                          (--all prints every differing line, not the first 30)
       tools/canon_compare.py --filter <x.canon>    print the dump minus the allowlist
       tools/canon_compare.py --list                print the allowlist

Exit: 0 the dumps match outside the allowlist; 1 they differ (the first lines
that differ are printed); 2 bad usage or an unreadable file.
"""
import difflib
import re
import sys

# Whole sections dropped, by their "=== name ===" heading prefix.
DROP_SECTIONS = [
    ("Journal and Time", "clocks: turn counters, keystrokes, the timed journal"),
    ("Location", "map: where the character stands on which level"),
    ("Effect Memory", "flavors: the random potion and wand names and what is known of them"),
    ("Script Variables", "script variable slots hold uninitialized memory until a script sets them"),
    ("Monster Memory", "map: the monsters he has seen on the level he arrived on"),
]

# Inside the "Derived Sheet" section, everything from the line "Journal:" on.
DERIVED_SHEET = "Derived Sheet"
DERIVED_CUT = ("Journal:", "journal text and level statistics: clock times, hit points at "
               "the time, and messages the level generator wrote")

# Tokens removed from lines that carry them, each with the reason.
TOKENS = [
    (re.compile(r" GenNum=-?\d+"), "", "item generation counter: candidate items the screens create and discard move it"),
    (re.compile(r"(Thing: Image=\S+) Timeout=-?\d+"), r"\1", "Thing timeout: the creature's action clock"),
    (re.compile(r"^(    +Thing: )Image=\S+"), r"\1Image=-", "flavors: the glyph color of a potion, scroll or wand comes from its flavor (items only; indented Thing lines)"),
    (re.compile(r"  AoO: -?\d+  FFCount: -?\d+"), "", "attack-of-opportunity and free-form counters: turn counters"),
    (re.compile(r"GallerySlot: -?\d+"), "GallerySlot: -", "gallery slot: a build writes no gallery entry"),
    (re.compile(r"HungerShown: -?\d+"), "HungerShown: -", "hunger display clock"),
    (re.compile(r"(Nature=HUNGER Val=-?\d+ Mag=-?\d+ )Duration=-?\d+"), r"\1Duration=-", "hunger clock: counts the turns played since creation"),
    (re.compile(r"Flags: statiChanged=\d shownFF=\d"), "Flags:", "display refresh flags"),
    (re.compile(r" 201=1(?= |$)"), "", "OPT_AUTOMORE: the build forces it on (spec A8)"),
    (re.compile(r"LastRest=-?\d+"), "LastRest=-", "rest clock"),
    (re.compile(r"GenStats: .*$"), "GenStats:", "provenance: the generator's note of the depth range it made the item for"),
    (re.compile(r" Age=-?\d+"), "", "item age: a torch burns while a key script plays a turn"),
    (re.compile(r"\(with \d+ turns of light left\)"), "(with turns of light left)", "the same torch age, in the derived sheet"),
]


def describe():
    out = []
    for name, why in DROP_SECTIONS:
        out.append("section  %-18s %s" % (name, why))
    out.append("section  %-18s from the line \"%s\" on: %s" % (DERIVED_SHEET, DERIVED_CUT[0], DERIVED_CUT[1]))
    for pat, _repl, why in TOKENS:
        out.append("token    %-34s %s" % (pat.pattern, why))
    return out


def filtered(path):
    try:
        text = open(path, errors="replace").read().split("\n")
    except OSError as e:
        print("canon_compare: cannot read %s: %s" % (path, e), file=sys.stderr)
        sys.exit(2)
    out = []
    section = ""
    cut = False
    for line in text:
        m = re.match(r"^=== (.*) ===$", line)
        if m:
            section = m.group(1)
            cut = False
            if any(section.startswith(n) for n, _ in DROP_SECTIONS):
                continue
        if any(section.startswith(n) for n, _ in DROP_SECTIONS):
            continue
        if section.startswith(DERIVED_SHEET):
            if line.strip() == DERIVED_CUT[0]:
                cut = True
            if cut:
                continue
        for pat, repl, _why in TOKENS:
            line = pat.sub(repl, line)
        out.append(line)
    return out


def main(argv):
    show_all = False
    if len(argv) > 1 and argv[1] == "--all":
        show_all = True
        argv = [argv[0]] + argv[2:]
    if len(argv) == 2 and argv[1] == "--list":
        print("\n".join(describe()))
        return 0
    if len(argv) == 3 and argv[1] == "--filter":
        print("\n".join(filtered(argv[2])))
        return 0
    if len(argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    a, b = filtered(argv[1]), filtered(argv[2])
    if not any(l.startswith("=== Identity") for l in a) or not any(l.startswith("=== Identity") for l in b):
        print("canon_compare: not a canonical dump (no Identity section)", file=sys.stderr)
        return 2
    if a == b:
        return 0
    n = 0
    for l in difflib.unified_diff(a, b, argv[1], argv[2], lineterm="", n=0):
        print(l[:200])
        n += 1
        if n > 30 and not show_all:
            break
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
