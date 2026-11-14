#!/usr/bin/env python3
# gate: none static; reads C/C++ source text and tools/retired_field_names.txt only; needs no build and no game run
# fact: field names -- the quoted first argument of every FIELD_*, V1EmbedBegin(_AT), V1Str, V1Blob, V1RidStatus, v1Find and V1ArrayWiden16 (new name only) call in inc/ and src/; no tag number, no save, no seed
# fact: scope of a field -- tools/convert_tags_to_names.py site_scope (the owner by number_values.py's scope rule, plus every open V1EmbedBegin name); --selftest builds its own scratch tree
# fact: retired and renamed names -- tools/retired_field_names.txt (the file the engine's inc/SaveRetiredNames.h copies; tools/check_field_names.sh keeps the two equal)
# fact: migration names -- the v1Migrations[] table in src/SaveV1.cpp, read as text
# fact: the revision owner -- the trailing `rev owner:` comment on the SCHEMA_REV define in src/SaveV1.cpp, read as text
# fact: the base tree -- a git ref (default master, re-read on every run) whose inc/ and src/ `git archive` gives; the migration functions it registers
"""Static checks of the names a save file carries (inc-cjos0, spec 5.3 and 8).

  check_save_names.py [--root ROOT] [--base REF] [--fast]  run every check (--fast: all but check 4); exit 0 pass, 1 refuse, 2 cannot measure
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
  4. A migration name that master registers must run the same function, with the same body,
     in the tree (--base REF, default master, read with `git archive` of inc/ and src/).  A
     name is permanent and its function is frozen once it lands: a file that lists the name
     skips the migration, so a changed function never reaches it.  Only the named function's
     text is compared (comments and spacing ignored); a helper it calls is not.
  5. The SCHEMA_REV define must end in `/* rev owner: <bead id> */` (or `pre-registry`).  Two branches that
     each bump the revision write two different owner ids on that one line, so git stops on a conflict
     instead of merging two container changes into one revision number.
V1ArrayWiden16 reads its OLD name on purpose; only its new name is checked.  A name a macro
argument carries (AC8_X("name", m)) is invisible here: the engine refuses it at run time
(v1WNameId and v1Find in src/SaveV1.cpp).
"""
import argparse
import os
import re
import shutil
import subprocess
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
MIGRATION_FN_ROW = re.compile(r'\{\s*"([^"]*)"\s*,\s*(\d+)\s*,\s*&\s*(?:\w+::)?(\w+)')


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


_UNITS = {}   # root -> units, filled only while run_all runs (one parse of the tree, not one per check)


def load_units(root):
    if _UNITS.get(root) is not None:
        return _UNITS[root]
    units = []
    for sub in ("inc", "src"):
        for dp, dn, fn in os.walk(os.path.join(root, sub)):
            dn.sort()
            for f in sorted(fn):
                rel = os.path.relpath(os.path.join(dp, f), root)
                if f.endswith(ct.EXTS) and rel != ct.HEADER_REL:
                    units.append(ct.Unit(root, rel))
    units = sorted(units, key=lambda u: u.rel)
    if root in _UNITS:
        _UNITS[root] = units
    return units


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
            decl.setdefault((path, nm), []).append((member, where))
    for (path, nm), writes in sorted(decl.items()):
        members = {m for m, _w in writes}
        w = sorted(x for _m, x in writes)
        if len(members) > 1:
            bad.append("%s: name \"%s\" in scope %s is declared with %d different members (%s)"
                       % (w[0], nm, path, len(members), ", ".join(w[1:])))
        elif len(w) > 1:
            bad.append("%s: name \"%s\" in scope %s is written at %d sites with the same spelling (%s). "
                       "A name is written once in its scope; keep one site"
                       % (w[0], nm, path, len(w), ", ".join(w[1:])))
    return bad, len(sites)


def check_literal_args(root):
    """-> [FAIL line] for every FIELD_* call outside inc/Base.h whose name argument is not one string
    literal. V1LiteralName refuses a pointer at compile time; an array variable only this text check sees."""
    bad = []
    for u in load_units(root):
        if u.rel == "inc/Base.h":
            continue
        for grp in u.calls():
            if u.in_pp(grp[0].off):
                continue
            s0 = grp[0]
            if s0.name.startswith("FIELD_") and s0.name != "FIELD_SKIP" and literal(u, s0.span) is None:
                bad.append("%s:%d: %s name argument is not a string literal (V1LiteralName; the name check reads literal names only)"
                           % (u.rel, u.line(s0.off), s0.name))
    return bad


BASE_REL = "inc/Base.h"   # defines the FIELD_ macros; its #defines are the macros themselves
# A macro that writes field names as literals and takes only a type: the engine's four Array
# specialisations. Its names ("Count", "Element") are fixed, so no argument carries a name.
MACRO_ALLOWED = {("src/SaveV1.cpp", "V1_ELEM_ARRAY_FIELDS")}
DEFINE_HEAD = re.compile(r"^[ \t]*#[ \t]*define[ \t]+(\w+)", re.M)
FIELD_CALL = re.compile(r"\b(FIELD_\w+|V1Field|V1Rid\w*|V1Str\w*)\s*\(")


def check_macros(root):
    """-> [FAIL line] for every #define outside inc/Base.h whose body calls FIELD_*, V1Field, V1Rid or V1Str.
    A macro argument carries the name, so the name check cannot read it."""
    bad = []
    for u in load_units(root):
        if u.rel == BASE_REL:
            continue
        t = nv.blank_comments(u.raw)
        for m in DEFINE_HEAD.finditer(t):
            end = m.end()
            while True:
                nl = t.find("\n", end)
                if nl < 0:
                    end = len(t)
                    break
                end = nl
                if t[nl - 1:nl] != "\\":
                    break
                end = nl + 1
            c = FIELD_CALL.search(t, m.end(), end)
            if c and (u.rel, m.group(1)) not in MACRO_ALLOWED:
                bad.append("%s:%d: macro %s calls %s; write the FIELD_ call out with a literal name "
                           "(the name check reads literal names only)" % (u.rel, u.line(m.start()), m.group(1), c.group(1)))
    return bad


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


def migration_fns(root):
    """-> [(name, function name)] in table order, from the v1Migrations[] table of src/SaveV1.cpp."""
    raw = open(os.path.join(root, SAVEV1_REL), encoding="utf-8", errors="replace").read()
    t = nv.blank_comments(raw)
    m = re.search(r"\bv1Migrations\s*\[\s*\]\s*=\s*\{", t)
    if not m:
        raise ValueError("no v1Migrations[] table in %s" % SAVEV1_REL)
    op = m.end() - 1
    cl = t.find("};", op)
    return [(g.group(1), g.group(3)) for g in MIGRATION_FN_ROW.finditer(raw, op, cl)]


def strip_comments(raw):
    """raw without its comments; string and character literals stay."""
    out, i, n = [], 0, len(raw)
    while i < n:
        two = raw[i:i + 2]
        if two == "//":
            j = raw.find("\n", i)
            i = n if j < 0 else j
        elif two == "/*":
            j = raw.find("*/", i + 2)
            i = n if j < 0 else j + 2
            out.append(" ")
        elif raw[i] in "\"'":
            j = i + 1
            while j < n and raw[j] != raw[i]:
                j += 2 if raw[j] == "\\" else 1
            out.append(raw[i:j + 1])
            i = j + 1
        else:
            out.append(raw[i])
            i += 1
    return "".join(out)


def function_bodies(root, fn):
    """-> every definition of `fn()` in inc/ and src/ (inline or `Class::fn`), comments dropped
    and white space collapsed, in file order."""
    out = []
    pat = re.compile(r"(?<![\w])(?:\w+::)*%s\s*\(\s*\)\s*(?:const\s*)?\{" % re.escape(fn))
    for sub in ("inc", "src"):
        for dp, dn, fnames in os.walk(os.path.join(root, sub)):
            dn.sort()
            for f in sorted(fnames):
                if not f.endswith(ct.EXTS):
                    continue
                raw = open(os.path.join(dp, f), encoding="utf-8", errors="replace").read()
                if fn not in raw:
                    continue
                t = nv.blank_comments(raw)
                for m in pat.finditer(t):
                    op, depth = m.end() - 1, 0
                    for k in range(op, len(t)):
                        depth += (t[k] == "{") - (t[k] == "}")
                        if depth == 0:
                            out.append(" ".join(strip_comments(raw[op:k + 1]).split()))
                            break
    return out


def check_frozen(base_root, root):
    """Item 4. -> (FAIL lines, migrations compared). ValueError when the base cannot be read."""
    tree = {}
    for name, fn in migration_fns(root):
        tree.setdefault(name, fn)
    bad = []
    bp = os.path.join(base_root, SAVEV1_REL)
    # A base from before the migration table landed registers nothing, so it freezes nothing.
    held = os.path.isfile(bp) and "v1Migrations" in open(bp, encoding="utf-8", errors="replace").read()
    rows = migration_fns(base_root) if held else []
    for name, fn in rows:
        if name not in tree:
            bad.append("%s: migration \"%s\" is gone from the table; a registered name is permanent "
                       "(master runs %s for it)" % (SAVEV1_REL, name, fn))
        elif tree[name] != fn:
            bad.append("%s: migration \"%s\" has a changed function: master runs %s, the tree runs %s. "
                       "A name is permanent and its function is frozen once it lands. Fix: keep %s as it is "
                       "and register the new function under a new name"
                       % (SAVEV1_REL, name, fn, tree[name], fn))
        else:
            was = function_bodies(base_root, fn)
            if not was:
                raise ValueError("cannot find the body of %s (migration \"%s\") in the base" % (fn, name))
            now = function_bodies(root, fn)
            if not now:
                bad.append("%s: migration \"%s\" has a changed function: the body of %s is gone from the tree"
                           % (SAVEV1_REL, name, fn))
            elif now != was:
                bad.append("%s: migration \"%s\" has a changed function body: %s differs from master. "
                           "A name is permanent and its function is frozen once it lands. Fix: restore %s "
                           "and register the new work under a new name" % (SAVEV1_REL, name, fn, fn))
    return bad, len(rows)


def extract_base(ref, dest, root):
    """Read-only: git archive of inc/ and src/ of ref into dest."""
    try:
        a = subprocess.Popen(["git", "-C", root, "archive", ref, "inc", "src"],
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except FileNotFoundError:
        raise ValueError("git is not installed, so base %s cannot be read" % ref)
    t = subprocess.run(["tar", "-x", "-C", dest], stdin=a.stdout, capture_output=True)
    a.stdout.close()
    err = a.stderr.read().decode()
    if a.wait() != 0 or t.returncode != 0:
        raise ValueError("cannot read base %s: %s" % (ref, (err or t.stderr.decode()).strip()[-300:]))


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


REV_DEFINE = re.compile(r"^[ \t]*#[ \t]*define[ \t]+SCHEMA_REV[ \t]+\d+(.*)$", re.M)
REV_OWNER = re.compile(r"^\s*/\*\s*rev owner:\s*(inc-[A-Za-z0-9]+(?:\.[A-Za-z0-9]+)*|pre-registry)\s*\*/\s*$")


def check_rev_owner(root):
    """-> [FAIL line] unless the SCHEMA_REV define carries one `rev owner:` comment naming a bead id."""
    t = open(os.path.join(root, SAVEV1_REL), encoding="utf-8", errors="replace").read()
    rows = REV_DEFINE.findall(t)
    if len(rows) != 1:
        raise ValueError("%d `#define SCHEMA_REV <n>` lines in %s, expected 1" % (len(rows), SAVEV1_REL))
    if not REV_OWNER.match(rows[0]):
        return ["%s: the SCHEMA_REV define has no valid owner comment (found %r). End it with "
                "`/* rev owner: <bead id> */`, the bead that set this value; a second branch that bumps "
                "the revision then conflicts here instead of sharing revision %s"
                % (SAVEV1_REL, rows[0].strip(), "number")]
    return []


def run_all(root, base="master", fast=False):
    rp = os.path.join(root, RETIRED_REL)
    if not os.path.isfile(rp) or not os.path.isfile(os.path.join(root, SAVEV1_REL)):
        print("UNMEASURED: %s or %s is missing under %s" % (RETIRED_REL, SAVEV1_REL, root))
        return 2
    _UNITS[root] = None   # ask load_units to keep its result for this run
    try:
        fb, nsites = check_fields(root, rp)
        fb += check_macros(root)
        fb += check_literal_args(root)
        mb, nmig = check_migrations(root)
        mb += check_rev_owner(root)
        if not fast:  # check 4 alone needs the base snapshot (git archive, ~4 s)
            tmp = tempfile.mkdtemp(prefix="save_names_base.")
            try:
                extract_base(base, tmp, root)
                fb2, _n = check_frozen(tmp, root)
            finally:
                shutil.rmtree(tmp, ignore_errors=True)
            mb += fb2
    except ValueError as e:
        print("UNMEASURED: %s" % e)
        return 2
    finally:
        _UNITS.pop(root, None)
    for b in fb + mb:
        print("REFUSED: " + b)
    if fb or mb:
        return 1
    print("check_save_names:%s PASS (%d named field calls, %d migrations)" % (" fast (check 4 skipped)" if fast else "", nsites, nmig))
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
            return check_fields(d, os.path.join(d, RETIRED_REL))[0], check_migrations(d)[0], check_macros(d) + check_literal_args(d)

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
    check("red (N16): one name written at two sites is refused, whatever the member",
          len(f) == 1 and '"a"' in f[0] and "2 sites" in f[0] and "same spelling" in f[0])
    f, _, _ = run(good.replace('r.V1EmbedEnd();\n      r.V1EmbedBegin("F"', 'r.V1EmbedEnd();\n      r.V1EmbedBegin("F"')
                  .replace('FIELD_U8("x", e.x);', 'FIELD_U8("x", e.x); FIELD_U8("y", e.y);'), ret)
    check("green: one name in two different scopes is not a repeat", not f)
    f, _, d = run(good + "#define W(n, m) FIELD_U32(n, m)\n", ret)
    check("red (N15): a macro that calls FIELD_ outside Base.h is refused",
          len(d) == 1 and "macro W calls FIELD_U32" in d[0])
    f, _, d = run(good + "#define W(m) \\\n  do { r.V1Rid(\"n\", m); } while (0)\n", ret)
    check("red (N15): a continued macro body that calls V1Rid is refused", len(d) == 1)
    f, _, d = run(good + "#define W(m) (m)\n// #define V(m) FIELD_U8(\"z\", m)\n", ret)
    check("green: a macro that calls no field function, and a commented one, pass", not d)
    f, _, d = run(good.replace('FIELD_I32("b", b)', 'FIELD_I32(nm, b)'), ret)
    check("red: a FIELD_ call whose name is a variable is refused", len(d) == 1 and "not a string literal" in d[0])
    f, _, d = run("#define FIELD_U8(name,m) r.V1Field((name), K_U8, &(m), 1)\n", ret, rel="inc/Base.h")
    check("green: the FIELD_ macros of inc/Base.h are not refused", not d)
    f, _, _ = run(good.replace('FIELD_U8("x", g[i].x);', 'FIELD_U8("x", g[i].x); FIELD_U8("x", g[i].y);'), ret)
    check("red: two members of one name inside an _AT embed are refused", len(f) == 1 and "Foo.G" in f[0])
    f, _, _ = run(good.replace('r.V1EmbedEnd(); }', 'r.V1EmbedEnd(); } FIELD_U8("a", z);'), ret)
    check("red: the _AT embed's end closes its scope (a later site is back in Foo)", len(f) == 1 and "scope Foo " in f[0])
    f, m, _ = run(good, ret, [("A", 5), ("B", 6), ("A", 0)])
    check("red (F11): a duplicate migration name is refused", len(m) == 1 and '"A"' in m[0])
    check("green: distinct migration names pass", not run(good, ret, [("A", 5), ("B", 6), ("C", 0)])[1])
    # N19: a registered migration name keeps its function, and the function keeps its body
    def tree(rows, bodies):
        d = tempfile.mkdtemp()
        for sub in ("inc", "src", "tools"):
            os.makedirs(os.path.join(d, sub))
        open(os.path.join(d, SAVEV1_REL), "w").write(
            "static const V1Migration v1Migrations[] = {\n%s\n};\n"
            % "\n".join('    { "%s", %d, &Player::%s },' % r for r in rows))
        open(os.path.join(d, "src", "Mig.cpp"), "w").write(bodies)
        return d
    rows = [("A", 5, "FnA"), ("B", 0, "FnB")]
    body = ("void Player::FnA() { x = 1; /* note */ }\n"
            "class P { void FnB() { if (y == 1040) z = 101; } void Other() { q = 1; } };\n")
    with tempfile.TemporaryDirectory() as _scratch:
        bt = tree(rows, body)
        check("green: a tree equal to the base passes", not check_frozen(bt, bt)[0])
        check("green: a comment or spacing change in a body passes",
              not check_frozen(bt, tree(rows, body.replace("/* note */", "/* other */").replace("x = 1", "x  =  1")))[0])
        check("green: a new migration row and a body elsewhere passes",
              not check_frozen(bt, tree(rows + [("C", 0, "FnC")], body + "void Player::FnC() { w = 2; }\n"))[0])
        check("green: another function in the class may change",
              not check_frozen(bt, tree(rows, body.replace("q = 1", "q = 2")))[0])
        bad_rows = [("A", 5, "FnA"), ("B", 0, "FnB2")]
        f = check_frozen(bt, tree(bad_rows, body + "void Player::FnB2() { z = 202; }\n"))[0]
        check("red (N19): a name that runs another function is refused",
              len(f) == 1 and '"B"' in f[0] and "changed function" in f[0] and "FnB2" in f[0])
        f = check_frozen(bt, tree(rows, body.replace("z = 101", "z = 202")))[0]
        check("red (N19): the same function with another body is refused",
              len(f) == 1 and '"B"' in f[0] and "changed function" in f[0] and "FnB" in f[0])
        f = check_frozen(bt, tree(rows, body.replace("x = 1", "x = 2")))[0]
        check("red: a changed body outside a class is refused", len(f) == 1 and '"A"' in f[0])
        f = check_frozen(bt, tree(rows[:1], body))[0]
        check("red: a registered name that leaves the table is refused", len(f) == 1 and '"B"' in f[0] and "gone" in f[0])
        f = check_frozen(bt, tree(rows, body.replace("void Player::FnA() { x = 1; /* note */ }\n", "")))[0]
        check("red: a function whose body is gone is refused", len(f) == 1 and '"A"' in f[0])
        nt = tempfile.mkdtemp()
        os.makedirs(os.path.join(nt, "src"))
        open(os.path.join(nt, SAVEV1_REL), "w").write("// a base before the table landed\n")
        check("green: a base with no migration table freezes nothing", check_frozen(nt, bt) == ([], 0))
        try:
            check_frozen(tree(rows, "// no bodies\n"), bt)
            check("unmeasured: a base with no body for a registered function", False)
        except ValueError:
            check("unmeasured: a base with no body for a registered function", True)
    # item 5: the SCHEMA_REV owner comment
    with tempfile.TemporaryDirectory() as rd:
        os.makedirs(os.path.join(rd, "src"))

        def rev(line):
            open(os.path.join(rd, SAVEV1_REL), "w").write("x\n" + line + "\nstatic int y;\n")
            return check_rev_owner(rd)
        check("green: SCHEMA_REV with a bead owner passes", not rev("#define SCHEMA_REV 7 /* rev owner: inc-cjos0 */"))
        check("green: a dotted bead id and pre-registry pass",
              not rev("#define SCHEMA_REV 7 /* rev owner: inc-eikp.3 */") and not rev("#define SCHEMA_REV 7 /* rev owner: pre-registry */"))
        check("red: SCHEMA_REV with no owner comment is refused", len(rev("#define SCHEMA_REV 7")) == 1)
        check("red: a malformed owner is refused",
              len(rev("#define SCHEMA_REV 7 /* rev owner: bob */")) == 1 and len(rev("#define SCHEMA_REV 7 /* rev owner: inc- */")) == 1
              and len(rev("#define SCHEMA_REV 7 /* owner: inc-x */")) == 1)
        check("green: restored owner passes again", not rev("#define SCHEMA_REV 8 /* rev owner: inc-abc */"))
    # --fast end to end: check 1-3, 5 still refuse; only check 4 (the base snapshot) is skipped.
    def e2e(src, fast, base):
        import io, contextlib
        with tempfile.TemporaryDirectory() as d:
            for sub in ("inc", "src", "tools"):
                os.makedirs(os.path.join(d, sub))
            open(os.path.join(d, "inc/Foo.h"), "w").write(src)
            open(os.path.join(d, RETIRED_REL), "w").write("")
            open(os.path.join(d, SAVEV1_REL), "w").write(
                "#define SCHEMA_REV 7 /* rev owner: inc-abc */\n"
                'static const V1Migration v1Migrations[] = {\n    { "A", 5, &Player::Fn },\n};\n')
            with contextlib.redirect_stdout(io.StringIO()):
                return run_all(d, base, fast)
    one = "class Foo {\n void FieldsV1(Registry &r)\n {\n FIELD_U8(\"a\", a);\n }\n};\n"
    dup = one.replace(' }\n};', ' FIELD_U8("a", c);\n }\n};')
    check("green: --fast passes a clean tree and never reads the base ref", e2e(one, True, "no-such-ref-xyz") == 0)
    check("red: --fast refuses one name at two sites in one scope", e2e(dup, True, "no-such-ref-xyz") == 1)
    check("green: full mode does read the base ref (a bad ref cannot be measured)", e2e(one, False, "no-such-ref-xyz") != 0)
    print("selftest: %s" % ("FAILED: " + ", ".join(bad) if bad else "passed"))
    return 1 if bad else 0


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--root", default=os.path.dirname(HERE))
    ap.add_argument("--base", default="master")
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--fast", action="store_true", help="skip check 4 (needs the base snapshot)")
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
    return run_all(a.root, a.base, a.fast)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
