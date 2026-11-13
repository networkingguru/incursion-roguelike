#!/usr/bin/env python3
# gate: cheap
# gate-fast: static, reads the C++ text of inc/ and src/ and one registry file, well under 1 s
# fact: the environment names the code reads -- string literals of inc/ and src/ text; no game run, no seed
# fact: the registry rows -- the text of tools/probe_names.txt; no randomness, no clock
"""Does every INCURSION_* environment name the code reads have exactly one row
in tools/probe_names.txt, and every row a reader? (bead inc-cjos0)

WHY THIS EXISTS. The binary reads diagnostic variables such as
INCURSION_BESTOW_PROBE. Two branches can each add the same name with two
different meanings, and git merges both without a conflict. One registry file,
one row per name, sorted, makes the second branch conflict on that row.

RULE FOR IMPLEMENTERS. A new INCURSION_* name read by src/ or inc/ gets a row
`NAME<TAB>OWNER<TAB>MEANING` in tools/probe_names.txt, in byte order. OWNER is
your bead id; MEANING is one short line. `pre-registry` rows are the names that
existed when the registry began; MEANING there is `-`.

A name counts when it is a whole string literal, outside comments, in a .cpp,
.c, .h or .hpp file of src/ or inc/ (generated yygram.cpp, yygram.h and
dispatch.h excluded). This covers getenv("X") and any wrapper taking a name.

Exit 0 PASS; 1 FAIL (name and file:line on stdout); 2 cannot run.
Self-test: python3 tools/check_probe_names.py --selftest
"""
import os
import re
import sys
import tempfile

NAME_RE = re.compile(r"^INCURSION_[A-Za-z0-9_]+$")
OWNER_RE = re.compile(r"^inc-[A-Za-z0-9]+(\.[A-Za-z0-9]+)*$")
SRC_EXT = (".cpp", ".c", ".h", ".hpp")
GENERATED = ("yygram.cpp", "yygram.h", "dispatch.h")
REGISTRY = "tools/probe_names.txt"


def literals(text):
    """Yield (line, string-body) of every string literal outside comments."""
    i, n, line = 0, len(text), 1
    while i < n:
        c = text[i]
        two = text[i:i + 2]
        if c == "\n":
            line += 1
            i += 1
        elif two == "//":
            while i < n and text[i] != "\n":
                i += 1
        elif two == "/*":
            j = text.find("*/", i + 2)
            j = n if j < 0 else j + 2
            line += text.count("\n", i, j)
            i = j
        elif c in "\"'":
            q, j = c, i + 1
            while j < n and text[j] != q and text[j] != "\n":
                j += 2 if text[j] == "\\" else 1
            if q == '"':
                yield line, text[i + 1:j]
            i = j + 1
        else:
            i += 1


def code_names(root):
    """Return {name: [file:line, ...]} read by the code, or None if no source."""
    found, files = {}, 0
    for sub in ("src", "inc"):
        d = os.path.join(root, sub)
        for dp, _, fns in os.walk(d):
            for fn in sorted(fns):
                if not fn.endswith(SRC_EXT) or fn in GENERATED:
                    continue
                files += 1
                p = os.path.join(dp, fn)
                with open(p, encoding="utf-8", errors="replace") as f:
                    text = f.read()
                rel = os.path.relpath(p, root)
                for ln, body in literals(text):
                    if NAME_RE.match(body):
                        found.setdefault(body, []).append("%s:%d" % (rel, ln))
    return found if files else None


def check(root, registry):
    """Return (problems, nrows, nnames). Raises FileNotFoundError / ValueError."""
    names = code_names(root)
    if names is None:
        raise ValueError("no source file under %s/src or %s/inc" % (root, root))
    with open(registry, encoding="utf-8") as f:
        lines = f.read().split("\n")
    problems, rows, prev = [], {}, None
    for no, raw in enumerate(lines, 1):
        if not raw.strip() or raw.startswith("#"):
            continue
        cols = raw.split("\t")
        where = "%s:%d" % (REGISTRY, no)
        if len(cols) != 3:
            problems.append("%s: row has %d columns, need 3 (NAME TAB OWNER TAB MEANING)" % (where, len(cols)))
            continue
        name, owner, meaning = cols
        if not NAME_RE.match(name):
            problems.append("%s: %r is not an INCURSION_ name" % (where, name))
        if owner != "pre-registry" and not OWNER_RE.match(owner):
            problems.append("%s: %s has OWNER %r, need a bead id or pre-registry" % (where, name, owner))
        elif owner != "pre-registry" and meaning.strip() in ("", "-"):
            problems.append("%s: %s needs a MEANING, it is not a pre-registry row" % (where, name))
        if name in rows:
            problems.append("%s: %s has a second row (first at line %d)" % (where, name, rows[name]))
        else:
            rows[name] = no
        if prev is not None and name.encode() < prev.encode():
            problems.append("%s: %s is out of order, it sorts before %s" % (where, name, prev))
        prev = name
    for name in sorted(names):
        if name not in rows:
            problems.append("%s: read but has no row in %s" % (names[name][0], REGISTRY))
    for name in sorted(rows):
        if name not in names:
            problems.append("%s:%d: %s has a row but no code reads it (stale row)" % (REGISTRY, rows[name], name))
    return problems, len(rows), len(names)


def selftest():
    ok = True
    good = "#c\nINCURSION_A_PROBE\tpre-registry\t-\nINCURSION_B_PROBE\tinc-x1.2\tdoes b\n"
    src = ('#include <x>\n// "INCURSION_COMMENT"\nvoid f(){ getenv("INCURSION_A_PROBE");\n'
           ' probeOn("INCURSION_B_PROBE"); }\n')
    cases = [
        ("green", good, src, None),
        ("a unregistered name", good, src + 'void g(){getenv("INCURSION_C");}\n', "read but has no row"),
        ("b stale row", good + "INCURSION_D\tpre-registry\t-\n", src, "stale row"),
        ("c duplicate row", good.replace("INCURSION_B_PROBE\tinc-x1.2\tdoes b\n",
                                         "INCURSION_B_PROBE\tinc-x1.2\tdoes b\nINCURSION_B_PROBE\tinc-y\tother\n"),
         src, "second row"),
        ("d unsorted", "INCURSION_B_PROBE\tinc-x1.2\tdoes b\nINCURSION_A_PROBE\tpre-registry\t-\n", src, "out of order"),
        ("e column count", good.replace("\tdoes b", ""), src, "columns"),
        ("e bad owner", good.replace("inc-x1.2", "bob"), src, "OWNER"),
        ("e empty meaning", good.replace("does b", "-"), src, "needs a MEANING"),
    ]
    for label, reg, code, want in cases:
        with tempfile.TemporaryDirectory() as d:
            os.makedirs(os.path.join(d, "src"))
            os.makedirs(os.path.join(d, "inc"))
            os.makedirs(os.path.join(d, "tools"))
            with open(os.path.join(d, "src", "a.cpp"), "w") as f:
                f.write(code)
            rp = os.path.join(d, REGISTRY)
            with open(rp, "w") as f:
                f.write(reg)
            problems, _, _ = check(d, rp)
            if want is None:
                good_run = not problems
            else:
                good_run = any(want in p for p in problems)
            print("%s: %s" % ("ok" if good_run else "FAIL", label))
            ok = ok and good_run
    print("check_probe_names selftest: %s" % ("PASS" if ok else "FAIL"))
    return 0 if ok else 1


def main(argv):
    if "--selftest" in argv:
        return selftest()
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    registry = os.path.join(root, REGISTRY)
    try:
        problems, nrows, nnames = check(root, registry)
    except (OSError, ValueError) as e:
        print("COULD NOT MEASURE: %s" % e)
        return 2
    if problems:
        for p in problems:
            print("FAIL: " + p)
        return 1
    print("PASS: %d names read by the code, %d registry rows" % (nnames, nrows))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
