#!/usr/bin/env python3
# gate: none static; reads C/C++ source text and tools/retired_field_names.txt only; needs no build and no game run
# fact: field names -- the quoted first argument of every FIELD_*, V1EmbedBegin(_AT), V1Str, V1Blob, V1RidStatus, v1Find and V1ArrayWiden16 (new name only) call in inc/ and src/; no tag number, no save, no seed
# fact: scope of a field -- tools/convert_tags_to_names.py site_scope (the owner by number_values.py's scope rule, plus every open V1EmbedBegin name); --selftest builds its own scratch tree
# fact: retired and renamed names -- tools/retired_field_names.txt (the file the engine's inc/SaveRetiredNames.h copies; tools/check_field_names.sh keeps the two equal)
# fact: migration names -- the v1Migrations[] table in src/SaveV1.cpp, read as text
"""Static checks of the names a save file carries (inc-cjos0, spec 5.3 and 8).

  check_save_names.py [--root ROOT]            run every check; exit 0 pass, 1 refuse, 2 cannot measure
  check_save_names.py migrations all           print the comma list the writer saves (every registered name)
  check_save_names.py migrations run REV       print the comma list a load runs for a file of revision REV
                                               that holds no applied migration
  check_save_names.py --selftest

Checks
  1. A field call must not use a name its scope lists as retired, or as the OLD side of a rename.
     Two branches meet here: one retires or renames x, the other adds a new field x.
  2. Two field calls in one scope with one name and different member expressions are two
     declarations of one name.  One declaration reached from several records (a loop, a shared
     FieldsV1) has one member expression and passes.
  3. Two migrations registered under one name.
V1ArrayWiden16 reads its OLD name on purpose; only its new name is checked.  A name a macro
argument carries (AC8_X("name", m)) is invisible here: the engine refuses it at run time
(v1WNameId and v1Find in src/SaveV1.cpp).
"""
import argparse
import os
import re
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import convert_tags_to_names as ct   # noqa: E402
import number_values as nv           # noqa: E402

RETIRED_REL = "tools/retired_field_names.txt"
SAVEV1_REL = "src/SaveV1.cpp"
EMBED_AT = re.compile(r"\bV1EmbedBegin_AT\s*\(")
MIGRATION_ROW = re.compile(r'\{\s*"([^"]*)"\s*,\s*(\d+)\s*,')


def parse_retired(path):
    """-> (retired set of (scope, name), old-side dict (scope, name) -> new name)."""
    retired, old = set(), {}
    for ln in open(path, encoding="utf-8"):
        w = ln.split("#", 1)[0].split()
        if len(w) == 2:
            retired.add((w[0], w[1]))
        elif len(w) == 4 and w[0] == "rename":
            old[(w[1], w[2])] = w[3]
        elif w:
            raise ValueError("bad line in %s: %s" % (path, " ".join(w)))
    return retired, old


def literal(u, a):
    """The string a call argument holds, or None when it is not one literal."""
    t = u.raw[a[0]:a[1]].strip()
    return t[1:-1] if len(t) >= 2 and t[0] == '"' and t[-1] == '"' and '"' not in t[1:-1] else None


def load_units(root):
    units = []
    for sub in ("inc", "src"):
        for dp, dn, fn in os.walk(os.path.join(root, sub)):
            dn.sort()
            for f in sorted(fn):
                rel = os.path.relpath(os.path.join(dp, f), root)
                if f.endswith(ct.EXTS) and rel != ct.HEADER_REL:
                    units.append(ct.Unit(root, rel))
    return sorted(units, key=lambda u: u.rel)


def named_sites(root):
    """-> [(scope path or None, name, member text or None, where, call identifier)] of every field call
    that names its field with a string literal."""
    out = []
    for u in load_units(root):
        tl = []
        for grp in u.calls():
            if not u.in_pp(grp[0].off):
                tl.append((grp[0].off, 1, "site", grp))
        for m in ct.EMB_END.finditer(u.T):
            if not u.in_pp(m.start()):
                tl.append((m.start(), 0, "end", None))
        for m in EMBED_AT.finditer(u.T):
            if not u.in_pp(m.start()):
                tl.append((m.start(), 1, "at", m))
        tl.sort(key=lambda t: (t[0], t[1]))
        stack = []
        for off, _, typ, pl in tl:
            if typ == "end":
                if stack:
                    stack.pop()
                continue
            if typ == "at":
                op = pl.end() - 1
                cl = nv.balanced(u.T, op)
                args = ct.split_args(u.T, op, cl) if cl >= 0 else []
                stack.append((literal(u, args[0][:2]) if args else None) or "?")
                continue
            for k, s in enumerate(pl):
                if k == 1:
                    continue   # V1ArrayWiden16's second argument: the old name, read on purpose
                nm = literal(u, s.span)
                if nm is None:
                    continue
                cl = nv.balanced(u.T, s.op)
                args = ct.split_args(u.T, s.op, cl) if cl >= 0 else []
                path = ct.site_scope(u, s.off, stack)[0]
                member = None
                if s.name.startswith("FIELD_") or s.name in ("V1EmbedBegin", "V1Str", "V1Blob", "V1RidStatus"):
                    skip = 2 if s.name.endswith("_AT") else 1
                    member = "".join("".join(u.raw[a:b].split()) + "," for a, b, _ in args[skip:])
                out.append((path, nm, member, "%s:%d" % (u.rel, u.line(s.off)), s.name))
            if pl[0].name == "V1EmbedBegin":
                stack.append(literal(u, pl[0].span) or "?")
    return out


def check_fields(root, retired_path):
    retired, old = parse_retired(retired_path)
    bad, decl = [], {}
    sites = named_sites(root)
    for path, nm, member, where, call in sites:
        if path is None:
            continue
        if (path, nm) in retired:
            bad.append("%s: %s(\"%s\") in scope %s uses a retired name (%s)" % (where, call, nm, path, RETIRED_REL))
        elif (path, nm) in old:
            bad.append("%s: %s(\"%s\") in scope %s uses the old name of a rename to \"%s\" (%s)"
                       % (where, call, nm, path, old[(path, nm)], RETIRED_REL))
        if member is not None:
            decl.setdefault((path, nm), {}).setdefault(member, where)
    for (path, nm), members in sorted(decl.items()):
        if len(members) > 1:
            w = sorted(members.values())
            bad.append("%s: name \"%s\" in scope %s is declared with %d different members (%s)"
                       % (w[0], nm, path, len(members), ", ".join(w[1:])))
    return bad, len(sites)


def migration_rows(root):
    """-> [(name, impliedRev)] in table order, from the v1Migrations[] table of src/SaveV1.cpp."""
    t = nv.blank_comments(open(os.path.join(root, SAVEV1_REL), encoding="utf-8", errors="replace").read())
    raw = open(os.path.join(root, SAVEV1_REL), encoding="utf-8", errors="replace").read()
    m = re.search(r"\bv1Migrations\s*\[\s*\]\s*=\s*\{", t)
    if not m:
        raise ValueError("no v1Migrations[] table in %s" % SAVEV1_REL)
    op = m.end() - 1
    cl = t.find("};", op)
    return [(g.group(1), int(g.group(2))) for g in MIGRATION_ROW.finditer(raw, op, cl)]


def check_migrations(root):
    rows = migration_rows(root)
    bad, seen = [], {}
    for name, _ in rows:
        if name in seen:
            bad.append("%s: migration \"%s\" is registered %s" % (SAVEV1_REL, name, "twice" if seen[name] == 1 else "%d times" % (seen[name] + 1)))
        seen[name] = seen.get(name, 0) + 1
    if not rows:
        bad.append("%s: the v1Migrations[] table holds no row" % SAVEV1_REL)
    return bad, len(rows)


def run_all(root):
    rp = os.path.join(root, RETIRED_REL)
    if not os.path.isfile(rp) or not os.path.isfile(os.path.join(root, SAVEV1_REL)):
        print("UNMEASURED: %s or %s is missing under %s" % (RETIRED_REL, SAVEV1_REL, root))
        return 2
    try:
        fb, nsites = check_fields(root, rp)
        mb, nmig = check_migrations(root)
    except ValueError as e:
        print("UNMEASURED: %s" % e)
        return 2
    for b in fb + mb:
        print("REFUSED: " + b)
    if fb or mb:
        return 1
    print("check_save_names: PASS (%d named field calls, %d migrations)" % (nsites, nmig))
    return 0


def selftest():
    bad = []

    def check(name, cond):
        print("%s  %s" % ("ok  " if cond else "FAIL", name))
        if not cond:
            bad.append(name)

    def run(src, retired="", migs=None, rel="inc/Foo.h"):
        with tempfile.TemporaryDirectory() as d:
            for sub in ("inc", "src", "tools"):
                os.makedirs(os.path.join(d, sub))
            open(os.path.join(d, rel), "w").write(src)
            open(os.path.join(d, RETIRED_REL), "w").write(retired)
            rows = migs or [("A", 5), ("B", 6)]
            open(os.path.join(d, SAVEV1_REL), "w").write(
                "static const V1Migration v1Migrations[] = {\n%s\n};\n"
                % "\n".join('    { "%s", %d, &Player::Fn },' % r for r in rows))
            return check_fields(d, os.path.join(d, RETIRED_REL))[0], check_migrations(d)[0], d

    good = """class Foo {
  void FieldsV1(Registry &r)
    {
      FIELD_U8("a", a);
      FIELD_I32("b", b);
      r.V1EmbedBegin("E", &e, sizeof(e));
      FIELD_U8("x", e.x);
      r.V1EmbedEnd();
      r.V1EmbedBegin("F", &f, sizeof(f));
      FIELD_U8("x", f.x);
      r.V1EmbedEnd();
      for (i = 0; i != 4; i++)
        { r.V1EmbedBegin_AT("G", i, &g[i], sizeof(g[i]));
          FIELD_U8("x", g[i].x);
          r.V1EmbedEnd(); }
      r.V1ArrayWiden16("New", "Old", Spells, 3);
    }
};
"""
    ret = "Foo Old\nrename Foo oldname newname\n"
    f, m, _ = run(good, ret)
    check("green: a clean scratch tree passes", not f and not m)
    check("green: sibling embeds repeat a name, V1ArrayWiden16 reads its old name", not f)
    f, _, _ = run(good.replace('FIELD_I32("b", b)', 'FIELD_I32("Old", b)'), ret)
    check("red (F02): a retired name is refused", len(f) == 1 and "retired" in f[0])
    f, _, _ = run(good.replace('FIELD_I32("b", b)', 'FIELD_I32("oldname", b)'), ret)
    check("red (F01): the old side of a rename is refused", len(f) == 1 and "old name of a rename" in f[0])
    f, _, _ = run(good.replace('FIELD_I32("b", b)', 'FIELD_I32("newname", b)'), ret)
    check("green: the new side of a rename is allowed", not f)
    f, _, _ = run(good.replace('FIELD_U8("x", e.x)', 'FIELD_U8("Old", e.x)'), "Foo.E Old\n")
    check("red: a retired name in an embed scope is refused", len(f) == 1)
    f, _, _ = run(good.replace('FIELD_I32("b", b)', 'FIELD_I32("a", c)'), ret)
    check("red (F03): one name, two members, one scope is refused", len(f) == 1 and "2 different members" in f[0])
    f, _, _ = run(good.replace('FIELD_I32("b", b)', 'FIELD_U8("a", a)'), ret)
    check("green: one declaration written twice is one declaration", not f)
    f, _, _ = run(good.replace('FIELD_U8("x", g[i].x);', 'FIELD_U8("x", g[i].x); FIELD_U8("x", g[i].y);'), ret)
    check("red: two members of one name inside an _AT embed are refused", len(f) == 1 and "Foo.G" in f[0])
    f, _, _ = run(good.replace('r.V1EmbedEnd(); }', 'r.V1EmbedEnd(); } FIELD_U8("a", z);'), ret)
    check("red: the _AT embed's end closes its scope (a later site is back in Foo)", len(f) == 1 and "scope Foo " in f[0])
    f, m, _ = run(good, ret, [("A", 5), ("B", 6), ("A", 0)])
    check("red (F11): a duplicate migration name is refused", len(m) == 1 and '"A"' in m[0])
    check("green: distinct migration names pass", not run(good, ret, [("A", 5), ("B", 6), ("C", 0)])[1])
    print("selftest: %s" % ("FAILED: " + ", ".join(bad) if bad else "passed"))
    return 1 if bad else 0


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--root", default=os.path.dirname(HERE))
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("what", nargs="*")
    a = ap.parse_args(argv)
    if a.selftest:
        return selftest()
    if a.what[:1] == ["migrations"]:
        rows = migration_rows(a.root)
        if a.what[1:2] == ["all"]:
            print(",".join(n for n, _ in rows))
            return 0
        if a.what[1:2] == ["run"] and len(a.what) == 3:
            rev = int(a.what[2])
            print(",".join(n for n, r in rows if not (r and r <= rev)))
            return 0
        ap.error("usage: migrations all | migrations run REV")
    if a.what:
        ap.error("unknown argument")
    return run_all(a.root)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
