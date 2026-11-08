#!/usr/bin/env bash
# gate: cheap --selftest
#
# Does every kind of starting perk, and every member of the Perk struct's union,
# have a line the .char file can state?
#
# WHAT IS BEING PROVED. Spec section 9, C5 (bead inc-10v7f, phase 7b): a perk
# is part of the character, and the .char file states each one field by field
# from ONE table, CreationPerkFields (src/CreationSource.cpp), which the
# recorder and the parser both walk. A new PerkType, or a new member of the
# Perk union, that the table does not know would be a perk the file cannot
# state, and a build would then rebuild it from a random draw. Two rules:
#   P1  every PerkType value except PERK_NONE has a row in CreationPerkFields;
#   P2  every member of the union `p` in the Perk struct (inc/Creature.h) is
#       written by the write function of some row AND read back by the read
#       function of some row (the function bodies name `p.p.<member>`).
#
# fact: the text of inc/Creature.h and src/CreationSource.cpp -- read from the working tree by python; no game run, no seed, no map, no character
# fact: the PerkType values and the union members -- read from inc/Creature.h at run time, so a new one is covered the moment it is added
# fact: which functions write and read a member -- the bodies of the functions the table rows name, read from src/CreationSource.cpp
#
# Usage: tools/check_perk_fields.sh [--selftest]
#        --selftest copies the two files, adds a PerkType value, adds a union
#        member and deletes a table row in turn, and proves this script goes red
#        on each copy (and green on the untouched copies).
# Exit: 0 every perk kind and member is covered; 1 one is not; 2 could not measure.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

HDR="${PERK_FIELDS_HEADER:-inc/Creature.h}"
SRC="${PERK_FIELDS_SOURCE:-src/CreationSource.cpp}"

measure() {
python3 - "$HDR" "$SRC" <<'PY'
import re, sys
hdr, src = sys.argv[1], sys.argv[2]
try:
    h = open(hdr).read()
    c = open(src).read()
except OSError as e:
    print("INCONCLUSIVE: %s" % e); sys.exit(2)

def strip_comments(t):
    t = re.sub(r"/\*.*?\*/", " ", t, flags=re.S)
    return re.sub(r"//[^\n]*", " ", t)

h = strip_comments(h); c = strip_comments(c)

m = re.search(r"typedef\s+enum\s*\{(.*?)\}\s*PerkType\s*;", h, re.S)
if not m:
    print("INCONCLUSIVE: no `typedef enum { ... } PerkType;` in %s" % hdr); sys.exit(2)
types = [t.strip().split("=")[0].strip() for t in m.group(1).split(",") if t.strip()]

m = re.search(r"typedef\s+struct\s*\{\s*PerkType\s+type\s*;\s*union\s*\{(.*)\}\s*p\s*;\s*\}\s*Perk\s*;", h, re.S)
if not m:
    print("INCONCLUSIVE: no Perk struct with a union named p in %s" % hdr); sys.exit(2)
body = m.group(1)
members, depth, cur = [], 0, ""
for ch in body:
    if ch == "{": depth += 1
    elif ch == "}": depth -= 1
    if ch == ";" and depth == 0:
        name = re.findall(r"[A-Za-z_]\w*", cur.split("}")[-1] if "}" in cur else cur)
        if name: members.append(name[-1])
        cur = ""
    else:
        cur += ch
if not members:
    print("INCONCLUSIVE: no union members found"); sys.exit(2)

m = re.search(r"const\s+CreationPerkField\s+CreationPerkFields\s*\[\s*\]\s*=\s*\{(.*?)\n\};", c, re.S)
if not m:
    print("INCONCLUSIVE: no CreationPerkFields table in %s" % src); sys.exit(2)
rows = re.findall(r"\{\s*(PERK_\w+)\s*,\s*(CK_\w+)\s*,\s*(\w+)\s*,\s*(\w+)\s*\}", m.group(1))
if not rows:
    print("INCONCLUSIVE: the table has no rows"); sys.exit(2)

def fn_body(name, sig):
    mm = re.search(r"static\s+%s\s+%s\s*\([^)]*\)\s*\{" % (sig, re.escape(name)), c)
    if not mm: return None
    i, depth = mm.end(), 1
    while i < len(c) and depth:
        depth += {"{": 1, "}": -1}.get(c[i], 0); i += 1
    return c[mm.end():i]

bad = 0
have = {r[0] for r in rows}
for t in types:
    if t == "PERK_NONE": continue
    if t not in have:
        print("P1 PerkType %s has no row in CreationPerkFields (%s)" % (t, src)); bad = 1
for mem in members:
    pat = re.compile(r"\bp\.p\.%s\b" % re.escape(mem))
    w = r = False
    for _, _, wf, rf in rows:
        wb = fn_body(wf, r"std::string"); rb = fn_body(rf, "bool")
        if wb is None or rb is None:
            print("INCONCLUSIVE: a row names %s / %s, which are not static functions in %s" % (wf, rf, src)); sys.exit(2)
        w = w or bool(pat.search(wb)); r = r or bool(pat.search(rb))
    if not w:
        print("P2 union member `%s` is written by no row's write function" % mem); bad = 1
    if not r:
        print("P2 union member `%s` is read by no row's read function" % mem); bad = 1
sys.exit(bad)
PY
}

if [ "${1:-}" = "--selftest" ]; then
    T="$(mktemp -d "${TMPDIR:-/tmp}/perkfields.XXXXXX")" || exit 2
    trap 'rm -rf "$T"' EXIT
    export PERK_FIELDS_HEADER="$T/Creature.h" PERK_FIELDS_SOURCE="$T/CreationSource.cpp"
    REAL_HDR="$HDR"; REAL_SRC="$SRC"
    fresh() { cp "$ROOT/$REAL_HDR" "$T/Creature.h"; cp "$ROOT/$REAL_SRC" "$T/CreationSource.cpp"; }
    HDR="$PERK_FIELDS_HEADER"; SRC="$PERK_FIELDS_SOURCE"
    fresh
    out="$(measure 2>&1)"; rc=$?
    if [ $rc -ne 0 ]; then echo "SELFTEST FAIL: the untouched copies are not green (rc=$rc)"; printf '%s\n' "$out"; exit 1; fi
    echo "selftest: untouched copies green"
    fails=0
    expect_red() {   # <label> <pattern the output must hold>
        out="$(measure 2>&1)"; rc=$?
        if [ $rc -eq 1 ] && grep -q "$2" <<< "$out"; then
            echo "selftest: $1 -> red as expected: $(grep -m1 "$2" <<< "$out")"
        else
            echo "SELFTEST FAIL: $1 did not go red (rc=$rc)"; printf '%s\n' "$out"; fails=1
        fi
    }
    fresh
    python3 - "$T/Creature.h" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
a = "  PERK_TALENT, /* Wild Talent... when we do psi */\n"
assert a in s
open(p, "w").write(s.replace(a, a + "  PERK_MUTATION_NEW,\n"))
PY
    expect_red "a PerkType value is added" "P1 PerkType PERK_MUTATION_NEW"
    fresh
    python3 - "$T/Creature.h" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p).read()
t, n = re.subn(r"(    int32 immune;[ \t]*\n)", r"\1    int32 mutation_new;\n", s, count=1)
assert n == 1
open(p, "w").write(t)
PY
    expect_red "a union member is added" "P2 union member \`mutation_new\`"
    fresh
    python3 - "$T/CreationSource.cpp" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
a = "    { PERK_IMMUNE,  CK_PERK_IMMUNE,  PerkImmuneWrite,  PerkImmuneRead },\n"
assert a in s
open(p, "w").write(s.replace(a, ""))
PY
    expect_red "a table row is deleted" "P1 PerkType PERK_IMMUNE"
    [ $fails -eq 0 ] && echo "selftest: PASS" && exit 0
    exit 1
fi

out="$(measure 2>&1)"; rc=$?
if [ $rc -eq 0 ]; then
    echo "PASS: every PerkType has a CreationPerkFields row, and every Perk union member is written and read"
    exit 0
fi
printf '%s\n' "$out"
[ $rc -eq 1 ] && echo "FAIL: a perk the .char file cannot state (spec section 9, C5)"
exit $rc
