#!/usr/bin/env python3
# gate: cheap --selftest
# gate-fast: static, reads two source files only, well under 1 s
# fact: the quality names -- read from the `family: wq`, `aq` and `wq, aq` blocks of inc/Defines.h text; no game run, no seed
# fact: the table rows -- read from the QualityTable[] table in src/Tables.cpp text; no game run, no seed
# fact: which names lack a row, have two rows, or name a stranger -- computed from those two texts only
"""Does every item quality name have exactly one row in the QualityTable? (inc-rddai)

QualityIsWeapon() and QualityIsArmor() answer from QualityTable[] in
src/Tables.cpp. A quality with no row answers false silently, so this check
FAILS the build when a WQ_/AQ_/IQ_ name in the quality blocks of inc/Defines.h
(the TRUELAST aliases excluded) has no row, has two rows, or when a row
names a constant that is not in those blocks. It also FAILS when it cannot find
a block or the table. Exit 0 pass, 1 fail (one line per problem).

Run: python3 tools/check_quality_table.py | --selftest
"""
import os
import re
import sys

DEFINE_RE = re.compile(r"^\s*#define\s+((?:WQ|AQ|IQ)_[A-Za-z0-9_]+)\s+(\d+)\b")
ROW_RE = re.compile(r"^\s*\{\s*((?:WQ|AQ|IQ)_[A-Za-z0-9_]+)\s*,\s*(true|false)\s*,\s*(true|false)\s*\}")
FAMILIES = ("wq", "aq", "wq, aq")
MARKERS = ("WQ_TRUELAST", "AQ_TRUELAST")


def names(defines_text):
    """{name: number} for quality defines inside the wq/aq blocks, or None."""
    fam, found, out = None, set(), {}
    for line in defines_text.splitlines():
        s = line.strip()
        m = re.match(r"//\s*family:\s*(.*?)\s*$", s)
        if m:
            fam = m.group(1)
            if fam in FAMILIES:
                found.add(fam)
        elif re.match(r"//\s*end family:", s):
            fam = None
        elif fam in FAMILIES:
            d = DEFINE_RE.match(line)
            if d and d.group(1) not in MARKERS:
                out[d.group(1)] = int(d.group(2))
    return out if {"wq", "aq"} <= found and out else None


def rows(tables_text):
    """List of row names inside QualityTable[] = { ... }, or None when absent."""
    m = re.search(r"QualityRow\s+QualityTable\[\]\s*=\s*\{(.*?)\};", tables_text, re.S)
    if not m:
        return None
    out = []
    for line in m.group(1).splitlines():
        r = ROW_RE.match(line)
        if r:
            out.append(r.group(1))
    return out or None


def problems(defines_text, tables_text):
    fam = names(defines_text)
    if fam is None:
        return ["cannot find the quality blocks with WQ_/AQ_ defines in inc/Defines.h"]
    tab = rows(tables_text)
    if tab is None:
        return ["cannot find the QualityTable[] rows in src/Tables.cpp"]
    out = []
    for name in tab:
        if name not in fam:
            out.append("row %s is not a quality name in the quality blocks" % name)
    for name in sorted(fam, key=lambda n: (fam[n], n)):
        c = tab.count(name)
        if c == 0:
            out.append("quality %d (%s) has no row in QualityTable[]" % (fam[name], name))
        elif c > 1:
            out.append("quality %d (%s) has %d rows in QualityTable[]" % (fam[name], name, c))
    return out


def selftest():
    d = ("// family: wq\n#define WQ_A 1\n#define WQ_TRUELAST 9\n// end family: wq\n"
         "// family: aq\n#define AQ_B 1\n// end family: aq\n"
         "// family: wq, aq\n#define IQ_C 7\n// end family: wq, aq\n")
    t = ("QualityRow QualityTable[] = {\n  { WQ_A, true, false },\n"
         "  { AQ_B, false, true },\n  { IQ_C, false, false },\n  { -1, false, false } };\n")
    assert problems(d, t) == [], problems(d, t)
    miss = t.replace("  { AQ_B, false, true },\n", "")
    assert any("AQ_B" in p and "no row" in p for p in problems(d, miss))
    two = t.replace("  { AQ_B, false, true },\n", "  { AQ_B, false, true },\n  { AQ_B, false, true },\n")
    assert any("2 rows" in p for p in problems(d, two))
    stranger = t.replace("  { AQ_B, false, true },\n", "  { AQ_B, false, true },\n  { AQ_Z, true, true },\n")
    assert any("AQ_Z" in p for p in problems(d, stranger))
    assert any("blocks" in p for p in problems("nothing\n", t))
    assert any("QualityTable" in p for p in problems(d, "nothing\n"))
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
        print("check_quality_table: cannot read %s" % e)
        return 1
    p = problems(d, t)
    for line in p:
        print("check_quality_table: " + line)
    return 1 if p else 0


if __name__ == "__main__":
    sys.exit(main())
