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
       tools/canon_compare.py --choices <x.canon>   print the CHOICE PROJECTION of a dump (phase 12a)
       tools/canon_compare.py --choices-diff <a.canon> <b.canon>
                                          multiset difference of the two projections: `- line`
                                          in <a> only, `+ line` in <b> only; exit 0 when empty, 1 not

The choice projection is what a player chose, not what the rules compute from it
(Brian's ruling, 2026-11-11: a conversion passes when its choices match): the
Gender, Race, Class, Faith and Align lines; the seven attribute base scores
(`STR base 12`); every line of Special Abilities, Feats, Inventory and CharGen
Options and Choices, led by the section name; skill ranks above 0
(`skill <name> ranks <n>`); known spell names (`spell <name>`). A section ends at
the next unindented `Heading:` line. Two projections compare as multisets.

Exit: 0 the dumps match outside the allowlist; 1 they differ (the first lines
that differ are printed); 2 bad usage or an unreadable file.
"""
import collections
import difflib
import os
import re
import sys

_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def code_only(text):
    """The C++ text with its comments blanked: a line inside `/* ... */` or after
    `//` states nothing the build does. String and character literals are kept
    whole, so a `//` inside one does not start a comment."""
    out, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if text.startswith("/*", i):
            j = text.find("*/", i + 2)
            j = n if j < 0 else j + 2
            out.append(re.sub(r"[^\n]", " ", text[i:j]))   # keep the newlines
            i = j
        elif text.startswith("//", i):
            j = text.find("\n", i)
            j = n if j < 0 else j
            out.append(" " * (j - i))
            i = j
        elif c in "\"'":
            j = i + 1
            while j < n and text[j] != c and text[j] != "\n":
                j += 2 if text[j] == "\\" else 1
            out.append(text[i:j + 1])
            i = j + 1
        else:
            out.append(c)
            i += 1
    return "".join(out)


def build_forced_options():
    """The options `-build` forces in the run's Options.Dat, read from the build
    code (src/CharFile.cpp, lines `bytes[OPT_X] = N;`) and the option numbers
    (inc/Defines.h). Returns [(number, value, name)]. Fails (exit 2) when the
    code names none or a name has no number: a comparison that silently stopped
    dropping the forced option would show it as a difference, and one that
    silently dropped nothing else would be a lie, so neither is allowed."""
    try:
        code = open(os.path.join(_ROOT, "src", "CharFile.cpp"), errors="replace").read()
        defs = open(os.path.join(_ROOT, "inc", "Defines.h"), errors="replace").read()
    except OSError as e:
        print("canon_compare: cannot read the build code: %s" % e, file=sys.stderr)
        sys.exit(2)
    out = []
    for name, val in re.findall(r"bytes\[(OPT_\w+)\]\s*=\s*(\d+)\s*;", code_only(code)):
        m = re.search(r"^#define\s+%s\s+(\d+)\b" % name, defs, re.M)
        if not m:
            print("canon_compare: build code forces %s, which inc/Defines.h does not number" % name, file=sys.stderr)
            sys.exit(2)
        out.append((int(m.group(1)), int(val), name))
    if not out:
        print("canon_compare: src/CharFile.cpp forces no option (no `bytes[OPT_X] = N;`)", file=sys.stderr)
        sys.exit(2)
    return out


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
    (re.compile(r"Flags: statiChanged=\d shownFF=\d"), "Flags:", "display refresh flags"),
    # The options -build forces, named by build_forced_options(): one entry per `bytes[OPT_X] = N;`.
    *[(re.compile(r" %d=%d(?= |$)" % (num, val)), "", "%s: the build forces it to %d (spec A8)" % (name, val))
      for num, val, name in build_forced_options()],
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


_HEADINGS = ("Special Abilities:", "Feats:", "Inventory:", "CharGen Options and Choices:",
             "Skill Ratings:", "Known Spells:")


def choices(path):
    """The choice projection of a dump (see the module docstring), a list of lines.
    Fails (exit 2) when the file is unreadable or holds none of the header lines,
    so a file that is not a dump cannot compare equal to another one."""
    try:
        lines = open(path, errors="replace").read().split("\n")
    except OSError as e:
        print("canon_compare: cannot read %s: %s" % (path, e), file=sys.stderr)
        sys.exit(2)
    out = []
    for l in lines:
        if re.match(r"^(Gender|Race|Class|Faith|Align) ", l):
            out.append(l.rstrip())
        m = re.match(r"^(STR|DEX|CON|INT|WIS|CHA|LUC):.*\(base (\d+)", l)
        if m:
            out.append("%s base %s" % (m.group(1), m.group(2)))
    cur = None
    for l in lines:
        if re.match(r"^[A-Z][A-Za-z' ]+:$", l):
            cur = l if l in _HEADINGS else None
            continue
        if cur in ("Special Abilities:", "Feats:", "Inventory:", "CharGen Options and Choices:"):
            if l.strip():
                out.append("%s %s" % (cur, l.strip()))
        elif cur == "Skill Ratings:":
            m = re.match(r"^\s+(.+?)\s+[+-]\d+\s+\((\d+) ranks", l)
            if m and m.group(2) != "0":
                out.append("skill %s ranks %s" % (m.group(1), m.group(2)))
        elif cur == "Known Spells:":
            m = re.match(r"^\s+(\S.*?)\s{2,}\d", l)
            if m:
                out.append("spell %s" % m.group(1))
    if not any(l.startswith("Race ") for l in out):
        print("canon_compare: %s is not a character dump (no Race line)" % path, file=sys.stderr)
        sys.exit(2)
    return out


def choices_diff(a_path, b_path):
    """[(sign, line)]: '-' in a only, '+' in b only, as multisets."""
    a, b = collections.Counter(choices(a_path)), collections.Counter(choices(b_path))
    out = [("-", l) for l in sorted((a - b).elements())]
    out += [("+", l) for l in sorted((b - a).elements())]
    return out


def main(argv):
    show_all = False
    if len(argv) > 1 and argv[1] == "--all":
        show_all = True
        argv = [argv[0]] + argv[2:]
    if len(argv) == 2 and argv[1] == "--list":
        print("\n".join(describe()))
        return 0
    if len(argv) == 3 and argv[1] == "--choices":
        print("\n".join(choices(argv[2])))
        return 0
    if len(argv) == 4 and argv[1] == "--choices-diff":
        d = choices_diff(argv[2], argv[3])
        for sign, l in d:
            print("%s %s" % (sign, l))
        return 1 if d else 0
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
