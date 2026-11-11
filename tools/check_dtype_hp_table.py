#!/usr/bin/env python3
# gate: cheap --selftest
# gate-fast: static, reads two source files only, well under 1 s
# fact: the damage-type numbers -- read from the `family: ad` block of inc/Defines.h text; no game run, no seed
# fact: the table rows -- read from the DTypeHP[] table in src/Tables.cpp text; no game run, no seed
# fact: which numbers lack a row, have two rows, or name a stranger -- computed from those two texts only
"""Does every damage type have exactly one row in the DTypeHP table? (inc-kx693)

DTypeTakesHP() answers "does this damage type take hit points?" from the
DTypeHP[] table in src/Tables.cpp. A damage type with no row answers false
silently, so this check FAILS the build when a number in the `family: ad`
block of inc/Defines.h has no row, has two rows, or when a row names a constant
that is not in the family. It also FAILS when it cannot find the block or the
table. An alias (a second name for one number) shares its target's row: name
only one of them. Exit 0 pass, 1 fail (one line per problem).

Run: python3 tools/check_dtype_hp_table.py | --selftest
"""
import os
import re
import sys

DEFINE_RE = re.compile(r"^\s*#define\s+(AD_[A-Za-z0-9_]+)\s+(\d+)\b")
ROW_RE = re.compile(r"^\s*\{\s*(AD_[A-Za-z0-9_]+)\s*,\s*(true|false)\s*\}")


def family(defines_text):
    """{name: number} for the AD_ defines inside the `family: ad` block, or None."""
    inside, found, out = False, False, {}
    for line in defines_text.splitlines():
        s = line.strip()
        if re.match(r"//\s*family:\s*ad\s*$", s):
            inside, found = True, True
        elif re.match(r"//\s*end family:\s*ad\s*$", s):
            inside = False
        elif inside:
            m = DEFINE_RE.match(line)
            if m:
                out[m.group(1)] = int(m.group(2))
    return out if found and out else None


def rows(tables_text):
    """List of row names inside DTypeHP[] = { ... }, or None when absent."""
    m = re.search(r"DTypeHPRow\s+DTypeHP\[\]\s*=\s*\{(.*?)\};", tables_text, re.S)
    if not m:
        return None
    out = []
    for line in m.group(1).splitlines():
        r = ROW_RE.match(line)
        if r:
            out.append(r.group(1))
    return out or None


def problems(defines_text, tables_text):
    fam = family(defines_text)
    if fam is None:
        return ["cannot find the `family: ad` block with AD_ defines in inc/Defines.h"]
    tab = rows(tables_text)
    if tab is None:
        return ["cannot find the DTypeHP[] table rows in src/Tables.cpp"]
    out = []
    for name in tab:
        if name not in fam:
            out.append("row %s is not a damage type in the `family: ad` block" % name)
    count = {}
    for name in tab:
        if name in fam:
            count[fam[name]] = count.get(fam[name], 0) + 1
    names = {}
    for n, v in fam.items():
        names.setdefault(v, []).append(n)
    for v in sorted(names):
        c = count.get(v, 0)
        label = "/".join(names[v])
        if c == 0:
            out.append("damage type %d (%s) has no row in DTypeHP[]" % (v, label))
        elif c > 1:
            out.append("damage type %d (%s) has %d rows in DTypeHP[]" % (v, label, c))
    return out


def selftest():
    d = "// family: ad\n#define AD_A 0\n#define AD_B 1\n#define AD_C 1 /* alias */\n// end family: ad\n"
    t = "DTypeHPRow DTypeHP[] = {\n  { AD_A, true },\n  { AD_B, false },\n  { -1, false } };\n"
    assert problems(d, t) == [], problems(d, t)
    miss = t.replace("  { AD_B, false },\n", "")
    assert any("no row" in p for p in problems(d, miss))
    two = t.replace("  { AD_B, false },\n", "  { AD_B, false },\n  { AD_C, true },\n")
    assert any("2 rows" in p for p in problems(d, two))
    dup = t.replace("  { AD_B, false },\n", "  { AD_B, false },\n  { AD_B, false },\n")
    assert any("2 rows" in p for p in problems(d, dup))
    stranger = t.replace("  { AD_B, false },\n", "  { AD_B, false },\n  { AD_Z, true },\n")
    assert any("AD_Z" in p for p in problems(d, stranger))
    assert any("family" in p for p in problems("nothing\n", t))
    assert any("table" in p for p in problems(d, "nothing\n"))
    print("selftest ok")


def main():
    if "--selftest" in sys.argv:
        selftest()
        return 0
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    try:
        d = open(os.path.join(root, "inc/Defines.h")).read()
        t = open(os.path.join(root, "src/Tables.cpp")).read()
    except OSError as e:
        print("check_dtype_hp_table: cannot read %s" % e)
        return 1
    p = problems(d, t)
    for line in p:
        print("check_dtype_hp_table: " + line)
    return 1 if p else 0


if __name__ == "__main__":
    sys.exit(main())
