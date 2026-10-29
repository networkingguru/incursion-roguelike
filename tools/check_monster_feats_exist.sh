#!/bin/bash
# gate: live
# Regression check for inc-4trf: every feat in a monster's `Feats:` list in the
# built module must have a row in src/FeatTab.cpp's FeatInfo[] table.
#
# WHY THIS EXISTS. `FeatName()` (src/Help.cpp) looks a feat id up in FeatInfo[]
# and, when it finds none, returns a debug fallback string
# "---N (below M = <name>)---". A monster whose `Feats:` line names such an id
# therefore prints that fallback in its description where the feat's name
# belongs. FT_DASH was defined in inc/Defines.h and listed on the juvenile
# arrowhawk, the cheetah and the plague of rats, but had no FeatInfo row.
#
# THE RULE UNDER TEST (lib/program.i): a `Feats:` list names only feats the
# feat table defines. lib/program.i is the preprocessed module source, so
# `#if 0` blocks are gone and every FT_ name is already a number. The check
# maps each number back to its FT_ name through inc/Defines.h, and fails naming
# the resource (Monster/Template line), program.i line and feat when
# src/FeatTab.cpp has no `{ FT_...` row for it.
#
# A stale lib/program.i FAILs: it may not show the current sources, so the
# check refuses to judge it. Rebuild with `BACKEND=posix ./build_macos.sh`.
#
# This check is static: it reads fixed files and no seed controls any fact it
# reads. Facts and their controls:
#   # fact: the Feats: lists -- lib/program.i, the preprocessed module source the build writes
#   # fact: program.i is current -- its mtime is not older than any lib/*.irh or lib/*.irc
#   # fact: the feat table -- the text of src/FeatTab.cpp
#   # fact: which names are feats -- the FT_ prefix, declared in inc/Defines.h
#
# Usage: tools/check_monster_feats_exist.sh      (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ ! -f src/FeatTab.cpp ]; then
    echo "FAIL: src/FeatTab.cpp not found; run from the repository root"
    exit 2
fi

python3 - "$ROOT" <<'PY'
import re, glob, sys, os

root = sys.argv[1]
os.chdir(root)
PROG = "lib/program.i"
REBUILD = "rebuild with BACKEND=posix ./build_macos.sh"

if not os.path.isfile(PROG):
    print("FAIL: %s not found; %s" % (PROG, REBUILD))
    sys.exit(1)

stale = [p for p in sorted(glob.glob("lib/*.irh") + glob.glob("lib/*.irc"))
         if os.path.getmtime(p) > os.path.getmtime(PROG)]
if stale:
    print("FAIL: %s is older than %s; the feat check cannot judge the current "
          "sources. %s" % (PROG, ", ".join(stale[:5]), REBUILD))
    sys.exit(1)

# Feats the feat table defines: a row in FeatInfo[] begins `{ FT_...`.
tab = set()
for line in open("src/FeatTab.cpp"):
    m = re.match(r"\s*\{\s*(FT_[A-Z0-9_]+)", line)
    if m:
        tab.add(m.group(1))
if not tab:
    print("FAIL: no `{ FT_...` rows parsed from src/FeatTab.cpp; the table's "
          "shape changed and this check can no longer measure.")
    sys.exit(2)

# program.i holds each Feats: entry as a number. An entry is an FT_ feat, an
# SK_ skill, or an M_ monster flag (the source lists M_IALIGN there). Map each
# number back to its names: `#define FT_X (FT_Y + 21)` style, arithmetic only.
# A define that does not evaluate is skipped; its number then has no name and
# the check FAILs on it.
defs = {}
for line in open("inc/Defines.h", encoding="utf-8", errors="replace"):
    m = re.match(r"#define\s+((?:FT|SK|M)_[A-Z0-9_]+)\s+(.*)$", line)
    if m:
        defs[m.group(1)] = re.split(r"/\*|//", m.group(2))[0].strip()

ARITH = re.compile(r"[0-9a-fA-FxX()+\-* \t]+")

def value(name, depth=0):
    expr = re.sub(r"\b(?:FT|SK|M)_[A-Z0-9_]+\b",
                  lambda m: str(value(m.group(0), depth + 1)), defs[name])
    if depth > 20 or not ARITH.fullmatch(expr):
        raise ValueError(name)
    return eval(expr, {"__builtins__": {}})

names_of = {}
for n in defs:
    try:
        names_of.setdefault(value(n), []).append(n)
    except (ValueError, KeyError, SyntaxError, ZeroDivisionError):
        pass
if not names_of:
    print("FAIL: no FT_ or SK_ name in inc/Defines.h evaluates to a number; "
          "the define shape changed and this check can no longer measure.")
    sys.exit(2)

# Walk program.i: remember the resource line, then read each Feats: list
# through its closing `;`.
bad, unparsed, seen = [], [], 0
resource = "(no resource line before)"
lines = open(PROG, encoding="utf-8", errors="replace").read().split("\n")
i = 0
while i < len(lines):
    m = re.match(r'([A-Za-z]+) "([^"]*)"', lines[i])
    if m:
        resource = '%s "%s"' % (m.group(1), m.group(2))
    if lines[i].startswith("Feats:"):
        seen += 1
        start, buf, j = i, lines[i][len("Feats:"):], i
        while ";" not in lines[j] and j + 1 < len(lines):
            j += 1
            buf += " " + lines[j]
        buf = buf.split(";")[0]
        for item in buf.split(","):
            item = item.strip()
            if not item:
                continue
            if not ARITH.fullmatch(item):
                unparsed.append((start + 1, item))
                continue
            v = eval(item, {"__builtins__": {}})
            hit = names_of.get(v, [])
            if any(n.startswith("SK_") for n in hit):
                continue  # a skill; ids 0..SK_LAST. The FT_*_LIST aliases share these small numbers
            ft = [n for n in hit if n.startswith("FT_")]
            if ft:
                # A number can also name an M_ flag (M_IGNORE_ITEMS = FT_DASH's
                # value); the FT_ name is still judged, so the M_ name cannot hide it.
                if not any(n in tab for n in ft):
                    bad.append((resource, start + 1, "/".join(ft)))
            elif not hit:
                bad.append((resource, start + 1,
                            "feat id %d (no FT_ name in inc/Defines.h)" % v))
            # else: only an SK_ skill or M_ flag, judged by other tables
        i = j + 1
    else:
        i += 1

if seen == 0:
    print("FAIL: no Feats: list found in %s; the module shape changed and this "
          "check can no longer measure." % PROG)
    sys.exit(2)
if unparsed:
    print("FAIL: a Feats: list in %s holds an expression this check cannot "
          "evaluate:" % PROG)
    for ln, item in unparsed:
        print("  %s:%d: %s" % (PROG, ln, item))
    sys.exit(2)
if bad:
    print("FAIL: a monster's Feats: list names a feat with no src/FeatTab.cpp "
          "row (its description would print the ---N (below ...)--- fallback):")
    for res, ln, label in bad:
        print("  %s (%s:%d): %s" % (res, PROG, ln, label))
    sys.exit(1)

print("PASS: every feat in every Feats: list of %s has a src/FeatTab.cpp row." % PROG)
PY
