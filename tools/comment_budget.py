#!/usr/bin/env python3
"""Measure comment and _PROBE block sizes in src/ and inc/.

Called by tools/check_comment_budget.sh, which carries the documentation.
The rule is in AGENTS.md, "The comment budget".
"""

import os
import re
import sys

CEILING = 30
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASELINE = os.path.join(ROOT, "tools", "comment_budget.baseline")

PROBE_OPEN = re.compile(r"^\s*#\s*if(def|ndef)?\s+.*_PROBE\b")
COND_OPEN = re.compile(r"^\s*#\s*if(def|ndef)?\b")
COND_CLOSE = re.compile(r"^\s*#\s*endif\b")


def signature(lines):
    """A stable name for a block: its first line of real text, trimmed.

    Line numbers move on every insertion above, so they cannot key a baseline.
    The opening text of a block almost never changes; when it does, the block
    is reported as new, which is the safe direction.
    """
    for ln in lines:
        text = " ".join(ln.strip().lstrip("/*# ").split())
        if text:
            return text[:60]
    return "(empty)"


def blocks(path):
    """Yield (kind, start_line, size, signature) for every block in one file."""
    with open(path, "r", errors="replace") as fh:
        lines = fh.read().splitlines()

    i = 0
    n = len(lines)
    while i < n:
        line = lines[i]

        if PROBE_OPEN.match(line):
            depth = 1
            j = i + 1
            while j < n and depth:
                if COND_OPEN.match(lines[j]):
                    depth += 1
                elif COND_CLOSE.match(lines[j]):
                    depth -= 1
                j += 1
            yield ("probe", i + 1, j - i, signature(lines[i + 1:j]))
            i = j
            continue

        stripped = line.lstrip()

        if stripped.startswith("/*") and "*/" not in line:
            j = i + 1
            while j < n and "*/" not in lines[j]:
                j += 1
            j = min(j + 1, n)
            yield ("comment", i + 1, j - i, signature(lines[i:j]))
            i = j
            continue

        if stripped.startswith("//"):
            j = i
            while j < n and lines[j].lstrip().startswith("//"):
                j += 1
            if j - i > 1:
                yield ("comment", i + 1, j - i, signature(lines[i:j]))
            i = max(j, i + 1)
            continue

        i += 1


def sources():
    for sub in ("src", "inc"):
        d = os.path.join(ROOT, sub)
        if not os.path.isdir(d):
            continue
        for name in sorted(os.listdir(d)):
            if name.endswith((".cpp", ".c", ".h")):
                yield os.path.join(sub, name), os.path.join(d, name)


def measure():
    """Every block at or over the ceiling, keyed by file, kind and signature."""
    out = {}
    for rel, full in sources():
        for kind, start, size, sig in blocks(full):
            if size >= CEILING:
                out[(rel, kind, sig)] = max(size, out.get((rel, kind, sig), 0))
    return out


def load_baseline():
    if not os.path.exists(BASELINE):
        return None
    known = {}
    with open(BASELINE) as fh:
        for raw in fh:
            raw = raw.rstrip("\n")
            if not raw.strip() or raw.lstrip().startswith("#"):
                continue
            parts = raw.split("\t")
            if len(parts) != 4:
                continue
            rel, kind, size, sig = parts
            known[(rel, kind, sig)] = int(size)
    return known


def record(found):
    with open(BASELINE, "w") as fh:
        fh.write("# Comment and _PROBE blocks already at or over the %d-line\n" % CEILING)
        fh.write("# ceiling, frozen 2026-08-25. Columns: file, kind, lines,\n")
        fh.write("# opening text. Cutting these is bd inc-5ysg follow-up work.\n")
        fh.write("# Delete a line when the block is cut. Never add one by hand.\n")
        for (rel, kind, sig), size in sorted(found.items()):
            fh.write("%s\t%s\t%d\t%s\n" % (rel, kind, size, sig))
    total = sum(found.values())
    print("recorded %d block(s) over the ceiling, %d lines" % (len(found), total))


def selftest():
    import tempfile
    import shutil

    tmp = tempfile.mkdtemp()
    try:
        src = os.path.join(tmp, "src")
        os.makedirs(src)
        body = "\n".join("   probe line %d" % k for k in range(40))
        with open(os.path.join(src, "T.cpp"), "w") as fh:
            fh.write("#ifdef FOO_PROBE\n" + body + "\n#endif\n")
            fh.write("/* short one\n   two lines */\n")
            fh.write("/* long one\n" + "\n".join(" * %d" % k for k in range(40)) + "\n */\n")

        got = list(blocks(os.path.join(src, "T.cpp")))
        kinds = [(k, s) for k, _, s, _ in got]
        st = 0

        probes = [s for k, s in kinds if k == "probe"]
        if probes != [42]:
            print("SELFTEST FAIL: probe block measured %s, wanted [42]" % probes)
            st = 1

        comments = sorted(s for k, s in kinds if k == "comment")
        if 2 not in comments:
            print("SELFTEST FAIL: missed the two-line comment")
            st = 1
        if 42 not in comments:
            print("SELFTEST FAIL: long comment measured %s, wanted a 42" % comments)
            st = 1
        if any(s >= CEILING for s in comments if s == 2):
            print("SELFTEST FAIL: a two-line comment counted as over the ceiling")
            st = 1

        if st == 0:
            print("SELFTEST PASS: comment_budget.py sizes probes and comments")
        return st
    finally:
        shutil.rmtree(tmp)


def main(argv):
    if "--selftest" in argv:
        return selftest()

    found = measure()

    if "--record" in argv:
        record(found)
        return 0

    known = load_baseline()
    if known is None:
        print("missing %s; run --record" % BASELINE, file=sys.stderr)
        return 2

    bad = []
    for key, size in sorted(found.items()):
        was = known.get(key)
        if was is None:
            bad.append((key, size, "new"))
        elif size > was:
            bad.append((key, size, "grew from %d" % was))

    print("check_comment_budget: ceiling %d lines, %d block(s) in the backlog"
          % (CEILING, len(known)))

    if bad:
        print("FAIL: these blocks are over the ceiling and are not the backlog's:")
        for (rel, kind, sig), size, why in bad:
            print("  %s  %s  %d lines (%s)  %s" % (rel, kind, size, why, sig))
        print('See AGENTS.md, "The comment budget".')
        return 1

    print("PASS: no block was added or grown past the ceiling")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
