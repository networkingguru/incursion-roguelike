#!/usr/bin/env python3
# gate: none static; reads a dump file, an override file and C/C++ source text; needs no build and no game run
# fact: master's tag numbers -- the dump of the tree named on the command line (tools/number_values.py output) and tools/legacy_tag_overrides.txt; nothing else
# fact: embed nesting -- the V1EmbedBegin/V1EmbedEnd calls in the source files the dump names, read lexically; --selftest builds its own scratch tree
# fact: save revisions -- 3 to 6 (MIN_READ_REV to SCHEMA_REV of the tree the header was generated from), written into every row's revision range
"""Generate inc/SaveLegacyTags.h (inc-cjos0 phase 1, spec 5.4), once, from master.

  gen_legacy_tags.py --dump DUMP [--overrides FILE] [--root ROOT] [--commit C] [--out FILE]
  gen_legacy_tags.py --verify-scan HEADER MANIFEST
  gen_legacy_tags.py --selftest

The header maps a revision 3-6 save's tag numbers to names, so the revision 7
reader can build the name table of an old file.  After it lands the header is
FROZEN: the tags of master never change, and a field added later has no row.

Rows
  fixed  {scope, tag, name, revLo, revHi}      one tag, one name, in a revision range
  range  {scope, baseTag, count, name}         a computed run (uint16)(base+i): tag base+i
                                               reads as name "<name>#i", i < count
A scope is the runtime owner (the string V1ProbeScope receives: Player, Map,
MapGrid, Array, ...) plus, for fields written inside a V1EmbedBegin ... V1EmbedEnd
pair, "/" and the embed's name: "Player/QuickKeys/QuickKey".  Embed scopes exist
because inner tags restart at 1 in every embed, so (owner, tag) alone is not unique.

Input: the dump's tag rows, plus tools/legacy_tag_overrides.txt for what the dump
cannot give (see that file).  Refused: a (scope, tag) with two names in
overlapping revisions, a (scope, name) with two tags in overlapping revisions, a
range overlapping a range or a fixed row in one scope, a call row without a name,
a dump scope "?" without a scope override, an embed without a name.

--verify-scan: every (runtime scope, tag, reading line) that a loaded save holds
(the manifest of tools/check_number_values.sh part 4) must map to exactly one row
of the header, using the save's own revision stamp.  Prints "problems: N".
"""
import collections
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import number_values as nv   # noqa: E402

REV_LO, REV_HI = 3, 6
CALLISH = re.compile(r"^(?:V1\w+#\d+(?:\.arg2)?|v1Find#\d+)$")
EMB_BEGIN = re.compile(r"(?:\.|->)\s*V1EmbedBegin\s*\(")
EMB_END = re.compile(r"(?:\.|->)\s*V1EmbedEnd\s*\(")


class Refuse(Exception):
    pass


# ------------------------------------------------------------------ inputs
def read_dump(path):
    """-> (tag rows [(dscope, label, value, file, line)], defines {name: value})."""
    tags, defs = [], {}
    for ln in open(path):
        ln = ln.rstrip("\n")
        if not ln or ln.startswith("#"):
            continue
        p = ln.split("\t")
        if p[0] == "## unevaluated":
            break
        if len(p) < 4:
            continue
        if p[0] == "define":
            defs.setdefault(p[1], int(p[2]))
        elif p[0] == "tag":
            f, l = p[3].rsplit(":", 1)
            sc, label = p[1].split(".", 1)
            tags.append((sc, label, int(p[2]), f, int(l)))
    return tags, defs


def read_overrides(path):
    ov = {"name": {}, "rev": {}, "scope": [], "range": []}
    for n, ln in enumerate(open(path), 1):
        ln = re.sub(r"(^|\s)#.*$", "", ln).strip()
        if not ln or ln.startswith("#"):
            continue
        p = ln.split()
        try:
            if p[0] == "name" and len(p) == 3:
                ov["name"][p[1]] = p[2]
            elif p[0] == "rev" and len(p) == 4:
                ov["rev"][p[1]] = (int(p[2]), int(p[3]))
            elif p[0] == "scope" and len(p) == 5:
                ov["scope"].append((p[1], int(p[2]), int(p[3]), p[4]))
            elif p[0] == "range" and len(p) in (6, 7):
                if len(p) == 7 and p[6] != "embed":
                    raise ValueError
                ov["range"].append((p[1], p[2], p[3], p[4], p[5], len(p) == 7))
            else:
                raise ValueError
        except ValueError:
            raise Refuse("%s:%d: cannot read override line: %s" % (path, n, ln))
    return ov


# ------------------------------------------------------------------ source
class Source:
    """Embed nesting and macro expansion sites of the source files, read lexically."""

    def __init__(self, root):
        self.root = root
        self.cache = {}

    def get(self, rel):
        if rel not in self.cache:
            raw = open(os.path.join(self.root, rel), encoding="utf-8", errors="replace").read()
            text = nv.clean(raw)
            pp = [(m.start(), m.end()) for m in nv.LOGICAL_PP.finditer(text)]
            starts = [a for a, _ in pp]

            def in_pp(off):
                import bisect
                i = bisect.bisect_right(starts, off) - 1
                return i >= 0 and off < pp[i][1]
            toks = []
            for rx, k in ((EMB_BEGIN, "B"), (EMB_END, "E")):
                for m in rx.finditer(text):
                    if not in_pp(m.start()):
                        toks.append((m.start(), nv.lineno(text, m.start()), k))
            toks.sort()
            self.cache[rel] = (raw, text, toks, pp)
        return self.cache[rel]

    def tokens(self, rel):
        return self.get(rel)[2]

    def expansion_lines(self, rel, line):
        """Lines where a row written at rel:line is reported: the line itself, or,
        inside a #define body, every use of that macro outside directives."""
        raw, text, _, pp = self.get(rel)
        lines = raw.split("\n")
        first = line
        while first > 1 and lines[first - 2].rstrip().endswith("\\"):
            first -= 1
        m = re.match(r"\s*#\s*define\s+(\w+)", lines[first - 1])
        if not m:
            return [line]
        name = m.group(1)
        out = []
        for u in re.finditer(r"\b%s\b" % re.escape(name), text):
            if not any(a <= u.start() < b for a, b in pp):
                out.append(nv.lineno(text, u.start()))
        if not out:
            raise Refuse("%s:%d: macro %s is never used" % (rel, line, name))
        return sorted(set(out))


# ------------------------------------------------------------------ model
class Table:
    def __init__(self):
        self.fixed = {}    # (scope, tag, name, lo, hi) -> set of "file:line"
        self.ranges = {}   # (scope, base, count, name) -> set of "file:line"

    def add_fixed(self, scope, tag, name, lo, hi, sites):
        self.fixed.setdefault((scope, tag, name, lo, hi), set()).update(sites)

    def add_range(self, scope, base, count, name, sites):
        self.ranges.setdefault((scope, base, count, name), set()).update(sites)


def overlap(a, b):
    return a[0] <= b[1] and b[0] <= a[1]


def validate(t):
    """The three refusals of the spec, on a Table."""
    rows = sorted(t.fixed)
    for i, a in enumerate(rows):
        for b in rows[i + 1:]:
            if a[0] != b[0] or not overlap(a[3:5], b[3:5]):
                continue
            if a[1] == b[1] and a[2] != b[2]:
                raise Refuse("scope %s tag %d has two names %s and %s in overlapping revisions" % (a[0], a[1], a[2], b[2]))
            if a[2] == b[2] and a[1] != b[1]:
                raise Refuse("scope %s name %s has two tags %d and %d in overlapping revisions" % (a[0], a[2], a[1], b[1]))
    rg = sorted(t.ranges)
    for i, a in enumerate(rg):
        for b in rg[i + 1:]:
            if a[0] == b[0] and overlap((a[1], a[1] + a[2] - 1), (b[1], b[1] + b[2] - 1)):
                raise Refuse("scope %s: range %s [%d..%d] overlaps range %s [%d..%d]"
                             % (a[0], a[3], a[1], a[1] + a[2] - 1, b[3], b[1], b[1] + b[2] - 1))
        if a[1] + a[2] - 1 > 0xFFFF:
            raise Refuse("scope %s: range %s runs past tag 65535" % (a[0], a[3]))
        for f in rows:
            if f[0] == a[0] and a[1] <= f[1] < a[1] + a[2]:
                raise Refuse("scope %s: range %s [%d..%d] overlaps fixed tag %d (%s)"
                             % (a[0], a[3], a[1], a[1] + a[2] - 1, f[1], f[2]))


def build(dump, ov, src):
    tags, defs = read_dump(dump) if isinstance(dump, str) else dump
    # embed names: (file, line) of a V1EmbedBegin -> name
    begin_name = {}
    for sc, label, val, f, l in tags:
        if label.startswith("V1EmbedBegin#"):
            ident = "%s.%s" % (sc, label)
            if ident not in ov["name"]:
                raise Refuse("%s (%s:%d) is an embed without a name; add a name line" % (ident, f, l))
            begin_name[(f, l)] = ov["name"][ident]
    ranges = []
    for owner, base, count, name, site, embed in ov["range"]:
        f, l = site.rsplit(":", 1)
        c = int(count, 0) if re.fullmatch(r"(0[xX][0-9a-fA-F]+|\d+)", count) else defs.get(count)
        if c is None:
            raise Refuse("range %s: count %s is not a number or a dumped define" % (name, count))
        b = int(base, 0)
        ranges.append((owner, b, c, name, f, int(l), embed))
        if embed:
            begin_name[(f, int(l))] = name

    def stack_at(f, line, is_begin):
        st = []
        for pos, ln, k in src.tokens(f):
            if ln >= line:
                if ln == line and not is_begin:
                    raise Refuse("%s:%d: a row shares its line with an embed call; split the line" % (f, line))
                break
            if k == "B":
                if (f, ln) not in begin_name:
                    raise Refuse("%s:%d: V1EmbedBegin with no name (no dump row, no embed range)" % (f, ln))
                st.append(begin_name[(f, ln)])
            else:
                if not st:
                    raise Refuse("%s:%d: V1EmbedEnd with no matching V1EmbedBegin" % (f, ln))
                st.pop()
        return st

    for f in {x[3] for x in tags} | {r[4] for r in ranges}:
        depth = 0
        for pos, ln, k in src.tokens(f):
            depth += 1 if k == "B" else -1
            if depth < 0:
                raise Refuse("%s:%d: V1EmbedEnd with no matching V1EmbedBegin" % (f, ln))
        if depth:
            raise Refuse("%s: %d V1EmbedBegin without V1EmbedEnd" % (f, depth))

    t = Table()
    for sc, label, val, f, l in tags:
        ident = "%s.%s" % (sc, label)
        name = ov["name"].get(ident)
        if name is None:
            if CALLISH.match(label):
                raise Refuse("%s (%s:%d) is a call row without a name; add a name line" % (ident, f, l))
            name = label
        owner = sc
        if sc == "?":
            hit = [o for (ff, a, b, o) in ov["scope"] if ff == f and a <= l <= b]
            if len(hit) != 1:
                raise Refuse("%s:%d: dump scope '?' needs exactly one scope override (found %d)" % (f, l, len(hit)))
            owner = hit[0]
        path = owner
        st = stack_at(f, l, label.startswith("V1EmbedBegin#"))
        if st:
            path += "/" + "/".join(st)
        lo, hi = ov["rev"].get(ident, (REV_LO, REV_HI))
        t.add_fixed(path, val, name, lo, hi, ["%s:%d" % (f, l)])
    for owner, b, c, name, f, l, embed in ranges:
        st = stack_at(f, l, embed)
        path = owner + ("/" + "/".join(st) if st else "")
        sites = ["%s:%d" % (f, x) for x in src.expansion_lines(f, l)]
        t.add_range(path, b, c, name, sites)
    validate(t)
    return t


# ------------------------------------------------------------------ header
def esc(s):
    return s.replace("\\", "\\\\").replace('"', '\\"')


def render(t, commit):
    L = []
    w = L.append
    w("// inc/SaveLegacyTags.h -- GENERATED ONCE by tools/gen_legacy_tags.py (inc-cjos0 phase 1) from master")
    w("// at %s, then FROZEN. NEVER EDIT. Master's tag numbers never change, so this table never changes;" % commit)
    w("// a field added after it has no row, because no revision 3-6 file can hold it.")
    w("//")
    w("// It maps the tag numbers of a revision 3-6 save to field names, so the revision 7 reader can build")
    w("// the name table of an old file. Scope = the runtime owner, plus \"/\" and the embed's name for a field")
    w("// written inside a V1EmbedBegin pair. A range row maps tag baseTag+i (i < count) to \"<name>#<i>\".")
    w("// The trailing comment of a row lists the source lines (file:line) that wrote and read it.")
    w("#ifndef SAVELEGACYTAGS_H")
    w("#define SAVELEGACYTAGS_H")
    w("")
    w("struct LegacyTagRow   { const char *scope; unsigned tag; const char *name; unsigned revLo, revHi; };")
    w("struct LegacyTagRange { const char *scope; unsigned baseTag; unsigned count; const char *name; };")
    w("")
    w("static const LegacyTagRow LEGACY_TAG_ROWS[] = {")
    for (sc, tag, name, lo, hi) in sorted(t.fixed, key=lambda k: (k[0], k[1], k[3], k[2])):
        w('  { "%s", %d, "%s", %d, %d },  /* %s */' % (esc(sc), tag, esc(name), lo, hi, ",".join(sorted(t.fixed[(sc, tag, name, lo, hi)]))))
    w("};")
    w("")
    w("static const LegacyTagRange LEGACY_TAG_RANGES[] = {")
    for (sc, base, count, name) in sorted(t.ranges, key=lambda k: (k[0], k[1])):
        w('  { "%s", %d, %d, "%s" },  /* %s */' % (esc(sc), base, count, esc(name), ",".join(sorted(t.ranges[(sc, base, count, name)]))))
    w("};")
    w("")
    w("#define LEGACY_TAG_ROW_COUNT   (sizeof(LEGACY_TAG_ROWS) / sizeof(LEGACY_TAG_ROWS[0]))")
    w("#define LEGACY_TAG_RANGE_COUNT (sizeof(LEGACY_TAG_RANGES) / sizeof(LEGACY_TAG_RANGES[0]))")
    w("")
    w("#endif")
    return "\n".join(L) + "\n"


ROW_RX = re.compile(r'^\s*\{ "((?:[^"\\]|\\.)*)", (\d+), "((?:[^"\\]|\\.)*)", (\d+), (\d+) \},\s*/\* (.*) \*/\s*$')
RNG_RX = re.compile(r'^\s*\{ "((?:[^"\\]|\\.)*)", (\d+), (\d+), "((?:[^"\\]|\\.)*)" \},\s*/\* (.*) \*/\s*$')


def parse_header(path):
    fixed, ranges = [], []
    for ln in open(path):
        m = ROW_RX.match(ln)
        if m:
            fixed.append((m.group(1), int(m.group(2)), m.group(3), int(m.group(4)), int(m.group(5)), m.group(6).split(",")))
            continue
        m = RNG_RX.match(ln)
        if m:
            ranges.append((m.group(1), int(m.group(2)), int(m.group(3)), m.group(4), m.group(5).split(",")))
    return fixed, ranges


# ------------------------------------------------------------------ verify
def verify_scan(header, manifest):
    fixed, ranges = parse_header(header)
    if not fixed or not ranges:
        print("  header holds no rows")
        print("problems: 1")
        return 1
    items = {}            # (runtime scope, tag, file, line, rev) -> first label
    nsaves = nskip = 0
    problems = 0
    revs = collections.Counter()
    for ln in open(manifest):
        label, sav, stamp, rc, scanf, errf = ln.rstrip("\n").split("\t")
        m = re.fullmatch(r"IS1\.(\d+)", stamp)
        if not m:
            nskip += 1      # v0 memory image or unstamped: no tags
            continue
        if rc != "0":
            nskip += 1      # part 4 reports the refused load
            continue
        rev = int(m.group(1))
        nsaves += 1
        revs[rev] += 1
        for sl in open(scanf):
            s, t, k, fl = sl.split()
            f, l = fl.rsplit(":", 1)
            key = (s, int(t), f, int(l), rev)
            if key not in items or label < items[key]:
                items[key] = label
    bad = []
    nfix = nrng = 0
    def dist(sites, f, l):
        d = [l - int(x.rsplit(":", 1)[1]) for x in sites if x.rsplit(":", 1)[0] == f]
        d = [x for x in d if 0 <= x <= 3]
        return min(d) if d else None

    for (s, t, f, l, rev), label in sorted(items.items()):
        cand = []    # (distance from the writing line, scope, name, kind)
        for sc, tag, name, lo, hi, sites in fixed:
            if tag == t and lo <= rev <= hi and owner_ok(sc, s):
                d = dist(sites, f, l)
                if d is not None:
                    cand.append((d, sc, name, "fixed"))
        for sc, base, count, name, sites in ranges:
            if base <= t < base + count and owner_ok(sc, s):
                d = dist(sites, f, l)
                if d is not None:
                    cand.append((d, sc, "%s#%d" % (name, t - base), "range"))
        best = [c for c in cand if c[0] == min(x[0] for x in cand)] if cand else []
        if len({(c[1], c[2]) for c in best}) == 1:
            if best[0][3] == "fixed": nfix += 1
            else: nrng += 1
        else:
            bad.append((s, t, "%s:%d" % (f, l), rev, label, sorted({(c[1], c[2]) for c in best})))
    print("part 5 legacy table: %d saves read (%s), %d without tags or refused (see part 4)"
          % (nsaves, ", ".join("revision %d=%d" % kv for kv in sorted(revs.items())), nskip))
    print("  distinct (owner, tag, reading line, revision) in those saves: %d" % len(items))
    print("  mapped to exactly one name by a fixed row: %d; by a range row: %d" % (nfix, nrng))
    for s, t, fl, rev, label, cand in bad[:40]:
        print("  %s: owner %s tag %d read at %s (revision %d, first in %s): %s" % (
            "NO NAME" if not cand else "AMBIGUOUS", s, t, fl, rev, label,
            "no row of the header" if not cand else " | ".join("%s %s" % c for c in cand)))
    print("problems: %d" % (problems + len(bad)))
    return 1 if (problems or bad) else 0


def owner_ok(hscope, runtime):
    top = hscope.split("/", 1)[0]
    return top == runtime or (runtime == "Map" and top == "MapGrid") or runtime == "Array" and top == "Array"


# ------------------------------------------------------------------ main
def generate(dump, overrides, root, commit):
    ov = read_overrides(overrides)
    return render(build(dump, ov, Source(root)), commit)


def selftest():
    def check(cond, msg):
        if not cond:
            print("SELFTEST FAIL: " + msg)
            sys.exit(1)
        print("ok: " + msg)

    def refuses(t, frag, msg):
        try:
            validate(t)
        except Refuse as e:
            check(frag in str(e), "%s (%s)" % (msg, e))
            return
        check(False, msg + " (nothing refused)")

    def base():
        t = Table()
        t.add_fixed("Alpha", 1, "a", 3, 6, ["x.h:1"])
        t.add_fixed("Alpha", 2, "b", 3, 6, ["x.h:2"])
        t.add_fixed("Alpha/Emb", 1, "c", 3, 6, ["x.h:4"])
        t.add_fixed("Beta", 7, "a", 3, 6, ["x.h:9"])
        t.add_fixed("Gamma", 5, "g", 3, 3, ["x.h:10"])
        t.add_fixed("Gamma", 5, "h", 4, 6, ["x.h:11"])      # same tag, two meanings, disjoint revisions: allowed
        t.add_range("Alpha", 10, 5, "run", ["x.h:7"])
        return t
    validate(base())
    check(True, "an undamaged table validates (same tag in two scopes, a revision-ranged tag, a name in two scopes)")
    t = base(); t.add_fixed("Alpha", 1, "z", 3, 6, ["x.h:20"])
    refuses(t, "has two names", "one (scope, tag) with two names in overlapping revisions is refused")
    t = base(); t.add_fixed("Alpha", 99, "a", 5, 6, ["x.h:21"])
    refuses(t, "has two tags", "one (scope, name) with two tags in overlapping revisions is refused")
    t = base(); t.add_range("Alpha", 12, 5, "run2", ["x.h:22"])
    refuses(t, "overlaps range", "a range overlapping another range is refused")
    t = base(); t.add_fixed("Alpha", 12, "late", 3, 6, ["x.h:23"])
    refuses(t, "overlaps fixed tag", "a range overlapping a fixed row in its scope is refused")
    t = base(); t.add_range("Beta", 10, 5, "run", ["x.h:24"])
    validate(t); check(True, "the same range in another scope is fine")

    with tempfile.TemporaryDirectory() as d:
        os.makedirs(d + "/inc"); os.makedirs(d + "/src")
        open(d + "/inc/e.h", "w").write("""class Owner {
  void FieldsV1(Registry &r) {
    FIELD_U8(1, top);
    r.V1EmbedBegin(50, &emb, 4);
    FIELD_U8(9, inner);
    for (i = 0; i != 3; i++)
      FIELD_RID((uint16)(1 + i), Lst[i]);
    r.V1EmbedEnd();
    FIELD_U8(2, after);
  }
};
""")
        open(d + "/dump.txt", "w").write("tag\tOwner.top\t1\tinc/e.h:3\ntag\tOwner.V1EmbedBegin#1\t50\tinc/e.h:4\n"
                                         "tag\tOwner.inner\t9\tinc/e.h:5\ntag\tOwner.after\t2\tinc/e.h:9\n## unevaluated\n")
        open(d + "/ov.txt", "w").write("name Owner.V1EmbedBegin#1 emb\nrange Owner 1 3 Lst inc/e.h:7\n")
        hdr = generate(d + "/dump.txt", d + "/ov.txt", d, "selftest")
        check('{ "Owner", 1, "top", 3, 6 }' in hdr and '{ "Owner/emb", 9, "inner", 3, 6 }' in hdr
              and '{ "Owner", 2, "after", 3, 6 }' in hdr and '{ "Owner/emb", 1, 3, "Lst" }' in hdr,
              "embed nesting: an inner field gets scope Owner/emb, fields outside it stay in Owner, the run lands in the embed")
        open(d + "/h.h", "w").write(hdr)
        open(d + "/tu.cpp", "w").write('#include "h.h"\nint main() { return (int)(LEGACY_TAG_ROW_COUNT + LEGACY_TAG_RANGE_COUNT); }\n')
        r = subprocess.run(["clang++", "-std=c++17", "-fsyntax-only", d + "/tu.cpp"], capture_output=True, text=True)
        check(r.returncode == 0, "the generated header compiles (clang++ -std=c++17 -fsyntax-only): %s" % r.stderr[:200])
        # unnamed embed
        open(d + "/ov2.txt", "w").write("range Owner 1 3 Lst inc/e.h:7\n")
        try:
            generate(d + "/dump.txt", d + "/ov2.txt", d, "x"); check(False, "an unnamed embed is refused")
        except Refuse as e:
            check("without a name" in str(e), "an embed with no name is refused (%s)" % e)
        # dump scope '?' without override
        open(d + "/dump2.txt", "w").write("tag\t?.q\t9\tinc/e.h:3\n## unevaluated\n")
        try:
            generate(d + "/dump2.txt", d + "/ov.txt", d, "x"); check(False, "a '?' row is refused")
        except Refuse as e:
            check("scope '?'" in str(e), "a dump scope '?' with no scope override is refused (%s)" % e)
        # a damaged dump: two tags for one name -> the full pipeline refuses
        open(d + "/dump3.txt", "w").write(open(d + "/dump.txt").read().replace("## unevaluated\n", "tag\tOwner.top\t4\tinc/e.h:3\n## unevaluated\n"))
        try:
            generate(d + "/dump3.txt", d + "/ov.txt", d, "x"); check(False, "a damaged dump is refused")
        except Refuse as e:
            check("has two tags" in str(e), "end to end: a dump giving one name two tags is refused (%s)" % e)
        # verify-scan: a dropped row goes red
        open(d + "/scan.txt", "w").write("Owner 1 1 inc/e.h:3\nOwner 1 1 inc/e.h:5\nOwner 2 1 inc/e.h:9\nOwner 2 1 inc/e.h:7\n")
        open(d + "/man.tsv", "w").write("lab\tsav\tIS1.6\t0\t%s/scan.txt\t%s/none\n" % (d, d))
        import io, contextlib
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = verify_scan(d + "/h.h", d + "/man.tsv")
        check(rc == 0 and "problems: 0" in buf.getvalue(), "verify-scan: a scratch save whose every tag has a row is clean")
        open(d + "/h2.h", "w").write("".join(l for l in open(d + "/h.h") if '"top"' not in l))
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc2 = verify_scan(d + "/h2.h", d + "/man.tsv")
        check(rc2 == 1 and "NO NAME" in buf.getvalue(), "verify-scan: a dropped row goes red")
    print("SELFTEST PASS")


def main(argv):
    if argv[:1] == ["--selftest"]:
        selftest()
        return 0
    if argv[:1] == ["--verify-scan"] and len(argv) == 3:
        return verify_scan(argv[1], argv[2])
    opt = {"--overrides": os.path.join(HERE, "legacy_tag_overrides.txt"), "--root": os.path.join(HERE, ".."),
           "--out": None, "--commit": None, "--dump": None}
    i = 0
    while i < len(argv):
        if argv[i] in opt and i + 1 < len(argv):
            opt[argv[i]] = argv[i + 1]; i += 2
        else:
            print(__doc__); return 2
    if not opt["--dump"]:
        print(__doc__); return 2
    root = os.path.abspath(opt["--root"])
    commit = opt["--commit"] or subprocess.run(["git", "-C", root, "rev-parse", "--short", "HEAD"], capture_output=True, text=True).stdout.strip()
    try:
        out = generate(opt["--dump"], opt["--overrides"], root, commit)
    except Refuse as e:
        print("REFUSED: %s" % e, file=sys.stderr)
        return 1
    if opt["--out"]:
        open(opt["--out"], "w").write(out)
    else:
        sys.stdout.write(out)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
