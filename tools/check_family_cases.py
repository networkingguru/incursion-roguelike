#!/usr/bin/env python3
# gate: cheap --selftest
# fact: the families -- the marks of inc/ and src/ read by tools/check_define_dups.py load_families; committed text, no game run, no seed
# fact: the cases -- tools/pressure/cases/*/ (A.patch, B.patch, plant.A, plant.B, expect); committed text, no game run, no seed
# fact: the exemptions -- tools/pressure/family_coverage.txt, one committed line per family; no seed
"""Does every stored family have a pressure case that exercises it? (inc-cjos0 9f-pre P6a)

A family is COVERED when a case that expects `works` either
  add    adds a member to it: an A.patch or B.patch line `#define NAME` or an
         enumerator inside the family's mark block, found by the member names
         of the hunk's context lines (the line number of the hunk is the
         fallback), or
  plant  plants a member of it: a name of the family (a member of the tree,
         or one the case adds) on a plant.A or plant.B line.
A family with no covering case MUST be listed in tools/pressure/family_coverage.txt
as `<family> <reason>`. A listed family that has a case, or is not a stored family,
is stale and fails the same as an uncovered one.

Usage: tools/check_family_cases.py [--cases DIR] [--coverage FILE] [--selftest]
Exit:  0 every stored family has a case or a reason   1 a family has neither, or an entry is stale
       2 could not read the marks, the cases or the coverage file
"""
import os
import re
import sys
import tempfile
import shutil

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
CASES = os.path.join(HERE, "pressure", "cases")
COVERAGE = os.path.join(HERE, "pressure", "family_coverage.txt")

HUNK = re.compile(r"^@@ -(\d+)(?:,\d+)? \+\d+(?:,\d+)? @@")
DEFINE = re.compile(r"^\s*#\s*define\s+([A-Za-z_]\w*)")
ENUMERATOR = re.compile(r"^\s*([A-Za-z_]\w*)\s*(?:=[^;{}]*)?,?\s*(?://.*|/\*.*)?$")
IDENT = re.compile(r"[A-Za-z_]\w*")
KEYWORDS = {"enum", "struct", "class", "union", "typedef", "public", "private", "protected", "else", "end", "return"}


class Unmeasurable(Exception):
    pass


def line_name(text):
    """The name a patch line declares: a #define, or an enumerator line."""
    m = DEFINE.match(text)
    if m:
        return m.group(1)
    m = ENUMERATOR.match(text)
    if m and m.group(1) not in KEYWORDS:
        return m.group(1)
    return None


def read_patch(path):
    """Return [(file, [(kind, text)], old_start)] for the C/C++ files of a unified diff."""
    try:
        with open(path, encoding="latin-1") as f:
            lines = f.read().split("\n")
    except OSError as e:
        raise Unmeasurable("cannot read %s: %s" % (path, e))
    out, cur = [], None
    for ln in lines:
        if ln.startswith("+++ "):
            name = ln[4:].split("\t")[0].strip()
            name = name[2:] if name.startswith("b/") else name
            cur = None
            if name.endswith((".h", ".hpp", ".cpp", ".c", ".inc")):
                cur = name
            continue
        m = HUNK.match(ln)
        if m and cur:
            out.append((cur, [], int(m.group(1))))
            continue
        if cur and out and out[-1][0] == cur and ln[:1] in ("+", "-", " ") and not ln.startswith(("+++", "---")):
            out[-1][1].append((ln[0], ln[1:]))
    return out


def block_spans(families_root, rel):
    """(first, last, [families]) for each mark block of a tree file; used for the line fallback."""
    import check_define_dups as c
    p = os.path.join(families_root, rel)
    try:
        with open(p, encoding="latin-1") as f:
            events, _n, _s, _b = c.read_marks(f.read().split("\n"))
    except (OSError, c.Unmeasurable):
        return []
    spans, start = [], None
    for no, what, kind, fams in events:
        if what == "open":
            start = (no, kind, fams)
        elif start:
            spans.append((start[0], no, list(start[2]) if start[1] == "family" else []))
            start = None
    return spans


def added_members(patch, members, root):
    """{name: set(family)} for the members a patch adds. members: name -> set(family)."""
    out = {}
    for fname, body, old_start in patch:
        spans = None
        old = old_start
        for i, (kind, text) in enumerate(body):
            if kind in (" ", "-"):
                old += 1
                continue
            name = line_name(text)
            if not name:
                continue
            fams = set()
            # the nearest context or removed line before it, then after it, that names a family member
            order = list(range(i - 1, -1, -1)) + list(range(i + 1, len(body)))
            for j in order:
                if body[j][0] == "+":
                    continue
                n2 = line_name(body[j][1])
                if n2 and n2 in members:
                    fams = set(members[n2])
                    break
            if not fams:
                if spans is None:
                    spans = block_spans(root, fname)
                for a, b, fl in spans:
                    if a < old <= b:
                        fams |= set(fl)
            if fams:
                out.setdefault(name, set()).update(fams)
    return out


def case_names(cdir, side, members, root):
    """(added, planted) for one case: added {name: families}, planted a set of identifiers."""
    added = {}
    for f in ("A.patch", "B.patch"):
        p = os.path.join(cdir, f)
        if os.path.isfile(p):
            for k, v in added_members(read_patch(p), members, root).items():
                added.setdefault(k, set()).update(v)
    planted = set()
    for f in ("plant.A", "plant.B"):
        p = os.path.join(cdir, f)
        if not os.path.isfile(p):
            continue
        try:
            with open(p, encoding="latin-1") as fh:
                for ln in fh:
                    if ln.lstrip().startswith("#"):
                        continue
                    planted.update(IDENT.findall(ln))
        except OSError as e:
            raise Unmeasurable("cannot read %s: %s" % (p, e))
    return added, planted


def read_coverage(path):
    out = {}
    try:
        with open(path, encoding="latin-1") as f:
            for no, ln in enumerate(f, 1):
                ln = ln.strip()
                if not ln or ln.startswith("#"):
                    continue
                parts = ln.split(None, 1)
                if len(parts) < 2 or not parts[1].strip():
                    raise Unmeasurable("%s:%d: a coverage line is `<family> <reason>`; this one has no reason" % (path, no))
                out[parts[0]] = parts[1].strip()
    except OSError as e:
        raise Unmeasurable("cannot read %s: %s" % (path, e))
    return out


def evaluate(fams, cases_dir, coverage_path, root=ROOT):
    """Return (exit code, output lines). fams is the load_families dict."""
    stored = sorted(f for f, d in fams.items() if d["class"] == "stored")
    members = {}
    for f in stored:
        for m in fams[f]["members"]:
            members.setdefault(m[0], set()).add(f)
    try:
        listed = read_coverage(coverage_path)
        names = sorted(d for d in os.listdir(cases_dir) if os.path.isdir(os.path.join(cases_dir, d)))
    except OSError as e:
        raise Unmeasurable("cannot read the cases: %s" % e)
    if not names:
        raise Unmeasurable("no case under %s" % cases_dir)
    cover = {f: [] for f in stored}
    for c in names:
        cdir = os.path.join(cases_dir, c)
        try:
            with open(os.path.join(cdir, "expect"), encoding="latin-1") as f:
                expect = f.read().split()
        except OSError:
            continue
        if not expect or expect[0] != "works":
            continue
        added, planted = case_names(cdir, None, members, root)
        for f in stored:
            how = None
            if any(f in v for v in added.values()):
                how = "add"
            elif any((n in members and f in members[n]) or (n in added and f in added[n]) for n in planted):
                how = "plant"
            if how:
                cover[f].append("%s(%s)" % (c, how))
    out, bad = [], 0
    for f in stored:
        if cover[f]:
            out.append("%s: %s" % (f, " ".join(cover[f])))
            if f in listed:
                out.append("STALE: %s is listed in %s but %s covers it. Fix: delete its line." % (f, os.path.basename(coverage_path), cover[f][0]))
                bad = 1
        elif f in listed:
            out.append("%s: none; listed: %s" % (f, listed[f]))
        else:
            out.append("UNCOVERED: %s has no positive case and no line in %s. Fix: add a case, or one line `%s <reason>`."
                       % (f, os.path.basename(coverage_path), f))
            bad = 1
    for f in sorted(listed):
        if f not in stored:
            out.append("STALE: %s is listed in %s but is not a stored family. Fix: delete its line." % (f, os.path.basename(coverage_path)))
            bad = 1
    return bad, out


def selftest():
    tmp = tempfile.mkdtemp(prefix="family-cases.")
    fails = []
    try:
        def put(rel, text):
            p = os.path.join(tmp, rel)
            os.makedirs(os.path.dirname(p), exist_ok=True)
            with open(p, "w") as f:
                f.write(text)
        fams = {
            "xa": {"class": "stored", "members": [("XA_ONE", 1, "inc/Defines.h", 3)]},
            "xb": {"class": "stored", "members": [("XB_ONE", 1, "inc/Defines.h", 8)]},
            "xc": {"class": "stored", "members": [("XC_ONE", 1, "inc/Defines.h", 12)]},
            "xi": {"class": "internal", "members": []},
        }
        put("inc/Defines.h", "// family: xa stored ordinal u8\n#define XA_ONE 1\n// end family: xa\n")
        put("cases/C1/expect", "works\n")
        put("cases/C1/A.patch", "--- a/inc/Defines.h\n+++ b/inc/Defines.h\n@@ -3,1 +3,2 @@\n #define XA_ONE 1\n+#define XA_TWO 2\n")
        put("cases/C2/expect", "works\n")
        put("cases/C2/plant.A", "# comment XC_ONE\nstatus FOO XB_ONE\n")
        put("cases/C3/expect", "refuse family xc\n")
        put("cases/C3/A.patch", "--- a/inc/Defines.h\n+++ b/inc/Defines.h\n@@ -12,1 +12,2 @@\n #define XC_ONE 1\n+#define XC_TWO 2\n")
        put("none.txt", "")
        put("cov.txt", "xc the width is full\n")
        put("stale.txt", "xc the width is full\nxa nothing\n")
        put("ghost.txt", "xc the width is full\nzz no such family\n")
        put("noreason.txt", "xc\n")
        cases = os.path.join(tmp, "cases")

        def run(cov, cdir=cases, f=fams):
            try:
                return evaluate(f, cdir, os.path.join(tmp, cov), tmp)
            except Unmeasurable:
                return 2, []
        code, out = run("cov.txt")
        if code != 0:
            fails.append("a covered family, a planted family and a listed family must pass: %s" % out)
        if not any(l.startswith("xa: C1(add)") for l in out):
            fails.append("an added member must cover its family by hunk context: %s" % out)
        if not any(l.startswith("xb: C2(plant)") for l in out):
            fails.append("a planted member must cover its family: %s" % out)
        if any("xc: C2" in l for l in out):
            fails.append("a name in a comment line must not count as planted: %s" % out)
        if any("xc: C3" in l for l in out):
            fails.append("a refusal case must not cover a family: %s" % out)
        code, out = run("none.txt")
        if code != 1 or not any(l.startswith("UNCOVERED: xc") for l in out):
            fails.append("a family with no case and no line must fail (RED): %s %s" % (code, out))
        code, out = run("stale.txt")
        if code != 1 or not any(l.startswith("STALE: xa") for l in out):
            fails.append("a listed family that has a case must fail (RED): %s %s" % (code, out))
        code, out = run("ghost.txt")
        if code != 1 or not any(l.startswith("STALE: zz") for l in out):
            fails.append("a listed name that is no stored family must fail (RED): %s %s" % (code, out))
        if run("noreason.txt")[0] != 2:
            fails.append("a coverage line with no reason must exit 2")
        if run("missing.txt")[0] != 2:
            fails.append("a missing coverage file must exit 2")
        if run("cov.txt", cdir=os.path.join(tmp, "nocases"))[0] != 2:
            fails.append("a missing case directory must exit 2")
        # the line-number fallback: a hunk whose context names no member
        put("cases2/C4/expect", "works\n")
        put("cases2/C4/A.patch", "--- a/inc/Defines.h\n+++ b/inc/Defines.h\n@@ -2,1 +2,2 @@\n // nothing\n+#define XA_NEW 5\n")
        code, out = run("cov.txt", cdir=os.path.join(tmp, "cases2"))
        if not any(l.startswith("xa: C4(add)") for l in out):
            fails.append("a hunk with no member in its context must fall back to the line and the block: %s" % out)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    for m in fails:
        print("check_family_cases selftest FAIL: " + m, file=sys.stderr)
    if not fails:
        print("check_family_cases selftest: ok")
    return 1 if fails else 0


def main(argv):
    cases, cov, st = CASES, COVERAGE, False
    it = iter(argv)
    for a in it:
        if a == "--cases":
            cases = next(it, None)
        elif a == "--coverage":
            cov = next(it, None)
        elif a == "--selftest":
            st = True
        else:
            print(__doc__.split("Usage:")[1].split("Exit:")[0], file=sys.stderr)
            return 2
        if cases is None or cov is None:
            print("a flag needs a value", file=sys.stderr)
            return 2
    if st:
        return selftest()
    try:
        import check_define_dups as c
        fams, problems = c.load_families()
        if problems:
            raise Unmeasurable("the marks have problems: %s" % problems[0])
        code, out = evaluate(fams, cases, cov)
    except (Unmeasurable, getattr(sys.modules.get("check_define_dups"), "Unmeasurable", Unmeasurable)) as e:
        print("check_family_cases: UNMEASURED: %s" % e, file=sys.stderr)
        return 2
    print("\n".join(out), file=sys.stderr if code else sys.stdout)
    return code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
