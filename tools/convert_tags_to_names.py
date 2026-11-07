#!/usr/bin/env python3
# gate: none static; reads C/C++ source text and inc/SaveLegacyTags.h only; needs no build and no game run
# fact: field names -- inc/SaveLegacyTags.h alone (the frozen table); this tool computes no name from a tag number
# fact: scopes and embed nesting -- the source text read lexically, by tools/number_values.py's scope rule; --selftest builds its own scratch tree
"""One-shot conversion record for inc-cjos0 (phase 2a): field call sites, tag number -> name.

Spec: docs/superpowers/specs/2026-11-07-names-in-the-file-design.md 5.1 and 5.4.

  convert_tags_to_names.py [--root ROOT] [--header FILE] [--dry-run]   report only (default)
  convert_tags_to_names.py [--root ROOT] [--header FILE] --apply       rewrite files
  convert_tags_to_names.py --selftest

Every FIELD_* macro, V1EmbedBegin, V1Str, V1Blob, V1RidStatus, V1ArrayWiden16 (both
tags), v1Find and the literal manifest/variable tag writes `v1PutU16(&v1Out, N)` in
ROOT/inc and ROOT/src take a tag number today.  Each site is keyed by (scope path, tag):
the scope path is the owner (number_values.py's scope rule) plus "." and the name of every
enclosing V1EmbedBegin ... V1EmbedEnd pair, the same path gen_legacy_tags.py wrote into
the header.  The name comes from the header row and from nowhere else.

Rewrite
  FIELD_U8(5, m)                   -> FIELD_U8("name", m)
  FIELD_RID((uint16)(1 + i), m)    -> FIELD_RID_AT("name", i, m)      a computed run, range row
  r.V1EmbedBegin(517, ...)         -> r.V1EmbedBegin("name", ...)
  r.V1EmbedBegin((uint16)(3+i),..) -> r.V1EmbedBegin_AT("name", i, ...)
  V1ArrayWiden16(448, 434, ...)    -> V1ArrayWiden16("Spells", "SpellsU16", ...)
  v1Find(2) / v1PutU16(&v1Out, 2)  -> v1Find("RowCount") / v1PutU16(&v1Out, "RowCount")
The v1PutU16(..., 0) terminators stay.  A tag inside a #define body is rewritten once, and
every expansion must map to the same text.

Exit 1 when any site is unmapped, ambiguous or unrecognised, or when two sites of one
frame get one name (a frame is one record's top level or one embed instance).
"""
import argparse
import bisect
import os
import re
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import number_values as nv   # noqa: E402
import gen_legacy_tags as gen   # noqa: E402

EXTS = (".h", ".hpp", ".c", ".cpp")
HEADER_REL = "inc/SaveLegacyTags.h"
SEGMENT = "Game.MDataSeg.Segment"
# Scope of a site the lexical rule cannot name (tools/legacy_tag_overrides.txt "scope" lines):
# (file, first line, last line, scope path, path is complete (no embed stack added)).
OWNER_OVERRIDES = [
    ("src/Base.cpp", 700, 730, "Array", False),
    ("src/SaveV1.cpp", 3140, 3160, "Array", False),
    ("src/SaveV1.cpp", 1030, 1145, SEGMENT, True),
    ("src/SaveV1.cpp", 1700, 1736, SEGMENT, True),
]
ONE_TAG_CALLS = ("V1EmbedBegin", "V1Str", "V1Blob", "V1RidStatus", "v1Find")
INT = r"(?:0[xX][0-9a-fA-F]+|\d+)"
CAST = r"(?:\(\s*uint16\s*\)\s*)?"
FIXED_RX = re.compile(r"^%s\(?\s*(%s)\s*\)?$" % (CAST, INT))
RUN_RX = re.compile(r"^%s\(\s*(%s)\s*\+\s*(.+?)\s*\)$" % (CAST, INT))
EMB_END = re.compile(r"(?:\.|->)\s*V1EmbedEnd\s*\(")
IDENT_AT_END = re.compile(r"[A-Za-z_]\w*")


class Site:
    """One tag argument of one call."""
    def __init__(self, file, off, kind, name, op, span, expr, name_end):
        self.file, self.off, self.kind, self.name = file, off, kind, name
        self.op = op            # offset of the call's "("
        self.span = span        # (start, end) of the tag argument, whitespace trimmed
        self.expr = expr        # its text
        self.name_end = name_end  # offset just after the call's identifier
        self.line = 0
        self.results = []       # [(scope path, replacement or None, error or None, rowkey)]


def blank_dead(raw):
    """Length-preserving: comments, strings and '#if 0' blocks blanked."""
    b = nv.blank_comments(raw)
    ins = b.split("\n")
    outs = nv.drop_if0(b).split("\n")
    return "\n".join(i if o == i else " " * len(i) for i, o in zip(ins, outs))


def split_args(T, op, cl):
    """[(start, end, text)] of the top-level arguments between T[op] "(" and T[cl] ")"."""
    inner = T[op + 1:cl]
    out, pos = [], op + 1
    for piece in nv.split_top(inner):
        lead = len(piece) - len(piece.lstrip())
        out.append((pos + lead, pos + len(piece.rstrip()), piece.strip()))
        pos += len(piece) + 1
    return out


class Unit:
    """One source file."""
    def __init__(self, root, rel):
        self.rel = rel
        self.raw = open(os.path.join(root, rel), encoding="utf-8", errors="replace", newline="").read()
        self.T = blank_dead(self.raw)
        T = self.T
        self.pp = [(m.start(), m.end()) for m in nv.LOGICAL_PP.finditer(T)]
        self.pstarts = [a for a, _ in self.pp]
        self.ivs = nv.scope_intervals(T)
        self.nl = [i for i, c in enumerate(T) if c == "\n"]

    def line(self, off):
        return bisect.bisect_left(self.nl, off) + 1

    def in_pp(self, off):
        i = bisect.bisect_right(self.pstarts, off) - 1
        return i >= 0 and off < self.pp[i][1]

    def scope_at(self, off):
        best = None
        for o, c, sc in self.ivs:
            if o < off < c and (best is None or o > best[0]):
                best = (o, sc)
        return best if best else (-1, "?")

    def calls(self, lo=0, hi=None):
        """Calls (FIELD_*, tag-taking calls, raw v1PutU16) in T[lo:hi]; each call is a list of its tag Sites."""
        T = self.T
        hi = len(T) if hi is None else hi
        out = []
        for rx, k in ((nv.FIELD, "F"), (nv.CALLS, "C"), (nv.RAWPUT, "P")):
            for m in rx.finditer(T, lo, hi):
                op = m.end() - 1
                cl = nv.balanced(T, op)
                if cl < 0:
                    continue
                args = split_args(T, op, cl)
                ident = IDENT_AT_END.match(T, m.start()).group(0)
                end_ident = m.start() + len(ident)
                if k == "F":
                    name = ident
                    if len(args) < 2:
                        continue
                    out.append([Site(self.rel, m.start(), "F", name, op, args[0][:2], args[0][2], end_ident)])
                elif k == "C":
                    name = ident
                    a0 = args[0][2] if args else ""
                    if not args or re.fullmatch(r"\s*\w+[\s*&]+\w+\s*", a0):
                        continue    # a declaration or definition
                    sites = [Site(self.rel, m.start(), "C", name, op, args[0][:2], a0, end_ident)]
                    if name == "V1ArrayWiden16" and len(args) > 1:
                        sites.append(Site(self.rel, m.start(), "C", name, op, args[1][:2], args[1][2], end_ident))
                    out.append(sites)
                else:
                    if T[:m.start()].rstrip().endswith("void"):
                        continue
                    if len(args) != 2 or args[0][2] != "&v1Out" or args[1][2] == "0":
                        continue    # not a tag write, or a terminator
                    out.append([Site(self.rel, m.start(), "P", "v1PutU16", op, args[1][:2], args[1][2], end_ident)])
        return out


class Table:
    def __init__(self, header):
        self.fixed, self.ranges = gen.parse_header(header)
        self.by_fixed = {}
        for r in self.fixed:
            self.by_fixed.setdefault((r[0], r[1]), []).append(r)
        self.by_range = {}
        for r in self.ranges:
            self.by_range.setdefault((r[0], r[1]), []).append(r)
        self.used = set()
        self.drift = []

    def fixed_name(self, path, tag, where):
        rows = self.by_fixed.get((path, tag), [])
        names = {r[2] for r in rows}
        if not rows:
            return None, "no legacy row for (%s, %d)" % (path, tag), None
        if len(names) > 1:
            return None, "(%s, %d) has several names %s" % (path, tag, sorted(names)), None
        for r in rows:
            self.used.add(("F",) + tuple(r[:5]))
            if where not in r[5]:
                self.drift.append("%s: row (%s, %d, %s) lists %s" % (where, path, tag, r[2], ",".join(r[5])))
        return rows[0][2], None, rows[0]

    def range_name(self, path, base, where):
        rows = self.by_range.get((path, base), [])
        if not rows:
            return None, "no legacy range row for (%s, base %d)" % (path, base)
        r = rows[0]
        self.used.add(("R",) + tuple(r[:4]))
        if where not in r[4]:
            self.drift.append("%s: range (%s, %d, %s) lists %s" % (where, path, base, r[3], ",".join(r[4])))
        return r[3], None


def q(name):
    return '"%s"' % name.replace("\\", "\\\\").replace('"', '\\"')


def resolve(site, path, table, where):
    """-> (replacement for the tag argument, name suffix to put after the call's identifier, error)."""
    e = site.expr
    if e.startswith('"'):
        return None, "", "named"
    m = FIXED_RX.fullmatch(e)
    if m:
        name, err, _ = table.fixed_name(path, int(m.group(1), 0), where)
        if err:
            return None, "", err
        return q(name), "", None
    m = RUN_RX.fullmatch(e)
    if m:
        name, err = table.range_name(path, int(m.group(1), 0), where)
        if err:
            return None, "", err
        return "%s, %s" % (q(name), m.group(2)), "_AT", None
    if re.fullmatch(r"[A-Za-z_]\w*", e):
        return None, "", "variable"
    return None, "", "unrecognised tag expression '%s'" % e


def convert(root, header, apply_=False):
    """-> result dict."""
    table = Table(header)
    units = []
    for sub in ("inc", "src"):
        for dp, dn, fn in os.walk(os.path.join(root, sub)):
            dn.sort()
            for f in sorted(fn):
                rel = os.path.relpath(os.path.join(dp, f), root)
                if f.endswith(EXTS) and rel != HEADER_REL:
                    units.append(Unit(root, rel))
    units.sort(key=lambda u: u.rel)
    byrel = {u.rel: u for u in units}

    # macros whose body holds a literal or computed tag
    macros = {}   # name -> (unit, [Site])
    for u in units:
        for m in nv.DEFINE.finditer(u.T):
            end = m.end()
            j = end
            while True:
                k = u.T.find("\n", j)
                if k < 0:
                    k = len(u.T)
                    break
                if u.T[k - 1:k] == "\\":
                    j = k + 1
                    continue
                break
            body = [s for grp in u.calls(end, k) for s in grp if FIXED_RX.fullmatch(s.expr) or RUN_RX.fullmatch(s.expr)]
            if body:
                macros[m.group(1)] = (u, body)
    exp_rx = re.compile(r"\b(%s)\b" % "|".join(re.escape(n) for n in sorted(macros))) if macros else None

    unmapped, mapped_n, per_file = [], 0, {}
    edits = {u.rel: [] for u in units}
    frames = {}      # (frame key, kind class, name, index text) -> first site "file:line"
    dups = []
    body_results = {}   # (macro, body site index) -> {replacement: [expansion lines]}
    where_of = lambda u, off: "%s:%d" % (u.rel, u.line(off))

    def override(u, line):
        for f, a, b, sc, full in OWNER_OVERRIDES:
            if f == u.rel and a <= line <= b:
                return sc, full
        return None

    def record_dup(u, off, fkey, kcls, name, idx):
        key = (fkey, kcls, name, idx)
        w = where_of(u, off)
        if key in frames:
            dups.append("%s and %s both write name '%s'%s in one frame" % (frames[key], w, name, "" if idx is None else " at index " + idx))
        else:
            frames[key] = w

    for u in units:
        tl = []   # timeline: (offset, order, type, payload)
        for grp in u.calls():
            if u.in_pp(grp[0].off):
                continue
            tl.append((grp[0].off, 1, "site", grp))
        for m in EMB_END.finditer(u.T):
            if not u.in_pp(m.start()):
                tl.append((m.start(), 0, "end", None))
        if exp_rx:
            for m in exp_rx.finditer(u.T):
                if u.in_pp(m.start()):
                    continue
                mu, body = macros[m.group(1)]
                tl.append((m.start(), 2, "exp", (m.group(1), body)))
        tl.sort(key=lambda t: (t[0], t[1]))
        stack = []   # (name, begin offset)

        def path_for(off, line):
            ov = override(u, line)
            ostart, owner = u.scope_at(off)
            if ov and ov[1]:
                return ov[0], ostart, ov[0]
            if ov:
                owner = ov[0]
            if owner == "?":
                return None, ostart, None
            return owner + "".join("." + n for n, _ in stack), ostart, owner

        for off, _, typ, pl in tl:
            if typ == "end":
                if stack:
                    stack.pop()
                continue
            if typ == "site":
                members = pl
                line = u.line(members[0].off)
                path, ostart, owner = path_for(members[0].off, line)
                for s in members:
                    s.line = line
                    where = "%s:%d" % (u.rel, line)
                    rep, suf, err = resolve(s, path if path is not None else "?", table, where)
                    if err in ("named", "variable"):
                        continue
                    if path is None and not err:
                        err = "scope '?' with no override"
                    if err:
                        unmapped.append((path, s.expr, where, err))
                        if s.name == "V1EmbedBegin":
                            stack.append(("?", members[0].off))   # keep the End calls balanced
                        continue
                    mapped_n += 1
                    per_file[u.rel] = per_file.get(u.rel, 0) + 1
                    edits[u.rel].append((s.span[0], s.span[1], rep))
                    if suf and s.span == members[0].span:
                        edits[u.rel].append((s.name_end, s.name_end, suf))
                    nm = rep.split(",")[0]
                    idx = rep.split(",", 1)[1].strip() if "," in rep else None
                    fkey = (u.rel, ostart, tuple(b for _, b in stack), None)
                    record_dup(u, members[0].off, fkey, "P" if s.kind == "P" else ("R" if s.name in ("v1Find", "V1ArrayWiden16") else "W"), nm, idx)
                    if s.name == "V1EmbedBegin":
                        stack.append((nm.strip('"'), members[0].off))
                continue
            # expansion of a tag-bearing macro
            mname, body = pl
            line = u.line(off)
            path, ostart, owner = path_for(off, line)
            for bi, s in enumerate(body):
                where = "%s:%d" % (u.rel, line)
                if path is None:
                    unmapped.append((None, s.expr, where, "macro %s expanded where the scope is '?' with no override" % mname))
                    continue
                rep, suf, err = resolve(s, path, table, where)
                if err:
                    unmapped.append((path, s.expr, where, "macro %s: %s" % (mname, err)))
                    continue
                body_results.setdefault((mname, bi), {}).setdefault((rep, suf), []).append(where)
                nm = rep.split(",")[0]
                idx = rep.split(",", 1)[1].strip() if "," in rep else None
                fkey = (u.rel, ostart, tuple(b for _, b in stack), off)
                record_dup(u, off, fkey, "W", nm, idx)
                if s.name == "V1EmbedBegin":
                    pass

    for (mname, bi), reps in sorted(body_results.items()):
        mu, body = macros[mname]
        s = body[bi]
        where = "%s:%d" % (mu.rel, mu.line(s.off))
        if len(reps) > 1:
            unmapped.append((None, s.expr, where, "macro %s expands to %d different names: %s" % (mname, len(reps), sorted(r for r, _ in reps))))
            continue
        (rep, suf), uses = next(iter(reps.items()))
        mapped_n += 1
        per_file[mu.rel] = per_file.get(mu.rel, 0) + 1
        mu_edits = edits[mu.rel]
        mu_edits.append((s.span[0], s.span[1], rep))
        if suf:
            mu_edits.append((s.name_end, s.name_end, suf))

    unused = []
    for r in table.fixed:
        if ("F",) + tuple(r[:5]) not in table.used:
            unused.append("fixed  %s tag %d %s (rev %d-%d) listed at %s" % (r[0], r[1], r[2], r[3], r[4], ",".join(r[5])))
    for r in table.ranges:
        if ("R",) + tuple(r[:4]) not in table.used:
            unused.append("range  %s base %d count %d %s listed at %s" % (r[0], r[1], r[2], r[3], ",".join(r[4])))

    changed = []
    for u in units:
        ed = sorted(edits[u.rel], key=lambda e: (e[0], e[1]))
        for a, b in zip(ed, ed[1:]):
            if a[1] > b[0]:
                unmapped.append((None, "", "%s:%d" % (u.rel, u.line(a[0])), "two edits overlap"))
        if not ed:
            continue
        out = u.raw
        for a, b, text in sorted(ed, key=lambda e: (e[0], e[1]), reverse=True):
            out = out[:a] + text + out[b:]
        changed.append((u.rel, out))
    if apply_ and not unmapped and not dups:
        for rel, out in changed:
            with open(os.path.join(root, rel), "w", encoding="utf-8", newline="") as f:
                f.write(out)
    return {"mapped": mapped_n, "per_file": per_file, "unmapped": unmapped, "unused": unused,
            "dups": dups, "drift": table.drift, "changed": dict(changed)}


def report(res, apply_):
    L = []
    w = L.append
    w("convert_tags_to_names: %s" % ("APPLY" if apply_ else "dry run"))
    w("sites converted: %d" % res["mapped"])
    w("sites per file:")
    for f, n in sorted(res["per_file"].items()):
        w("  %5d  %s" % (n, f))
    w("unmapped sites: %d" % len(res["unmapped"]))
    for path, expr, where, err in res["unmapped"]:
        w("  %s  scope=%s  tag=%s  %s" % (where, path, expr, err))
    w("same-frame duplicate names: %d" % len(res["dups"]))
    for d in res["dups"]:
        w("  " + d)
    w("legacy rows no site used: %d" % len(res["unused"]))
    for x in res["unused"]:
        w("  " + x)
    w("sites whose line is not in their row's source list (informational): %d" % len(res["drift"]))
    for x in res["drift"]:
        w("  " + x)
    return "\n".join(L) + "\n"


# ---------------------------------------------------------------- selftest
HDR = '''#ifndef X
struct LegacyTagRow   { const char *scope; unsigned tag; const char *name; unsigned revLo, revHi; };
struct LegacyTagRange { const char *scope; unsigned baseTag; unsigned count; const char *name; };
static const LegacyTagRow LEGACY_TAG_ROWS[] = {
%s
};
static const LegacyTagRange LEGACY_TAG_RANGES[] = {
%s
};
#endif
'''


def selftest():
    bad = []

    def check(name, cond):
        print("%s  %s" % ("ok  " if cond else "FAIL", name))
        if not cond:
            bad.append(name)

    def run(src, rows, ranges, apply_=False):
        with tempfile.TemporaryDirectory() as d:
            os.makedirs(os.path.join(d, "inc"))
            os.makedirs(os.path.join(d, "src"))
            open(os.path.join(d, "inc", "Foo.h"), "w").write(src)
            hp = os.path.join(d, "inc", "SaveLegacyTags.h")
            open(hp, "w").write(HDR % ("\n".join(rows), "\n".join(ranges)))
            res = convert(d, hp, apply_)
            res["text"] = open(os.path.join(d, "inc", "Foo.h")).read()
            return res

    row = lambda sc, t, n, loc="inc/Foo.h:1": '  { "%s", %d, "%s", 3, 6 },  /* %s */' % (sc, t, n, loc)
    rng = lambda sc, b, c, n, loc="inc/Foo.h:1": '  { "%s", %d, %d, "%s" },  /* %s */' % (sc, b, c, n, loc)
    good = """class Foo {
  void FieldsV1(Registry &r)
    {
      FIELD_U8(1, a);
      FIELD_I32 (2, b);
      r.V1EmbedBegin(3, &e, sizeof(e));
      FIELD_U8(1, e.x);
      r.V1EmbedEnd();
      r.V1EmbedBegin(4, &f, sizeof(f));
      FIELD_U8(1, f.x);
      r.V1EmbedEnd();
      r.V1EmbedBegin(5, &g, sizeof(g));
      for (i = 0; i != 4; i++)
        FIELD_RID((uint16)(1 + i), g[i]);
      r.V1EmbedEnd();
    }
};
"""
    rows = [row("Foo", 1, "a"), row("Foo", 2, "b"), row("Foo", 3, "E"), row("Foo.E", 1, "x"),
            row("Foo", 4, "F"), row("Foo.F", 1, "x"), row("Foo", 5, "G")]
    ranges = [rng("Foo.G", 1, 4, "Item")]
    r = run(good, rows, ranges)
    check("green: every site mapped", not r["unmapped"] and r["mapped"] == 8)
    check("green: sibling embeds may repeat a name", not r["dups"])
    check("green: no unused row", not r["unused"])
    check("green: rewritten text", 'FIELD_U8("a", a)' in r["text"] or 'FIELD_U8("a", a)' in r["changed"]["inc/Foo.h"])
    ch = r["changed"]["inc/Foo.h"]
    check("green: _AT form", 'FIELD_RID_AT("Item", i, g[i])' in ch)
    check("green: embed call", 'r.V1EmbedBegin("E", &e' in ch and 'FIELD_U8("x", e.x)' in ch)
    r2 = run(good.replace("FIELD_I32 (2, b)", "FIELD_I32 (9, b)"), rows, ranges)
    check("red: an unmapped tag is reported", len(r2["unmapped"]) == 1 and "9" in r2["unmapped"][0][1])
    r3 = run(good.replace("FIELD_I32 (2, b)", "FIELD_I32 (2, b); FIELD_I32 (7, c)"), rows + [row("Foo", 7, "b")], ranges)
    check("red: one name on two sites of one frame is reported", len(r3["dups"]) == 1)
    r4 = run(good, rows + [row("Foo", 99, "z")], ranges)
    check("report: an unused row is listed", len(r4["unused"]) == 1)
    r5 = run(good.replace("FIELD_U8(1, e.x)", "FIELD_U8(1, e.x); FIELD_U8(1, e.y)"), rows, ranges)
    check("red: the same tag twice in one embed is reported", len(r5["dups"]) == 1)
    r6 = run(good, rows, ranges, apply_=True)
    check("apply: file rewritten", 'FIELD_U8("a", a)' in r6["text"])
    r7 = run(good.replace("FIELD_I32 (2, b)", "FIELD_I32 (9, b)"), rows, ranges, apply_=True)
    check("apply: nothing written while a site is unmapped", "FIELD_U8(1, a)" in r7["text"])
    print("selftest: %s" % ("FAILED: " + ", ".join(bad) if bad else "passed"))
    return 1 if bad else 0


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--root", default=os.path.dirname(HERE))
    ap.add_argument("--header", default=None)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args(argv)
    if a.selftest:
        return selftest()
    if a.apply and a.dry_run:
        ap.error("--apply and --dry-run exclude each other")
    header = a.header or os.path.join(a.root, HEADER_REL)
    res = convert(a.root, header, a.apply)
    sys.stdout.write(report(res, a.apply))
    return 1 if res["unmapped"] or res["dups"] else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
