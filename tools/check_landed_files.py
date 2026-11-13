#!/usr/bin/env python3
# gate: none finish_bead.sh and .beads/hooks/pre-commit run it on a bead branch; it needs the branch to be a bead id, so it exits 2 on master or a nightly/ branch
"""Refuse a branch that adds a resource or a module-level script variable
anywhere but lib/landed-<bead-id>.irh.

    tools/check_landed_files.py             check the module in the tree
    tools/check_landed_files.py --selftest  prove the check bites, no build

Authority: docs/superpowers/specs/2026-10-31-no-shared-tail-design.md, 4.1.

The bead id is the current branch name and MUST match
^inc-[a-z0-9]+(\\.[0-9]+)*$. The names come from the `-resorder` dump that
tools/resource_order_check.py runs. A name is NEW when the base branch's ledger
(`git show <base>:tools/resource_order.ledger`, base =
`git config branch.<bead>.incursionBase`, default master) does not hold it in
the same array, matched by array NAME (slot numbers shift when an array is
added, a name does not), or, for a module-level script variable (V record,
owner -1 -1), does not hold it in the module-level list. A new resource must
appear as a quoted string in lib/landed-<bead>.irh; a new variable as a whole
word. Comments in the landed file do not count. Where else the name is
declared does not matter.

Two kinds of name are NOT new to the bead, though the base ledger lacks them:

  Merged-in (a master-into-epic merge bead, whose base is the epic). Every
  parent of a merge commit on base..HEAD other than its first parent, and
  MERGE_HEAD while a merge is uncommitted, is a merged parent. The first parent
  is the bead's own line and never counts. A name that the ledger of a merged
  parent holds, or that a lib/landed-<other bead>.irh holds, is not new, when
  that file is in the merged parent's tree, not in the base's, and is not this
  bead's own. Master's gate already admitted them. A resource the bead adds
  itself, outside its landed file, is still new and refused. A parent with no
  ledger holds nothing.

  Renamed in place. In the same array, a name that sits at a position where the
  base ledger (or a merged parent's ledger) holds a different name, and that
  old name is absent from the whole array in the tree, is not new (an in-place
  rename: docs/SAVE-SCHEMA-SPEC.md Amendment 1). The ledger records positions
  (the E lines, in order). A rename whose old name still exists elsewhere in the
  array is an addition plus a move, and stays new.

  Retired (kept: the rule above needs the same position, and this one does not,
  e.g. a merged-parent name that sits at another position in the epic).
  "X;retired" (a tombstone: a retired name keeps its slot) is not new
  when the base ledger, or a merged parent, holds "X" or "X;retired". Retire
  means a name that master had. A name that is retired on its first appearance
  has no live name to retire, so it stays new.

It also refuses a lib/landed-*.irh that lib/landed.irc does not include, and
an include line in lib/landed.irc that names a missing file or is not an
include line.

Exit 0 clean, 1 refusal, 2 cannot establish (module dump, a ledger, the bead id
or lib/landed.irc unreadable).

# fact: current branch name and its incursionBase -- --bead override; git rev-parse and git config otherwise
# fact: the module's resource and variable names -- --dump override in --selftest; incursion-headless -resorder otherwise
# fact: the base ledger -- --base-ledger override in --selftest; git show <base>:tools/resource_order.ledger otherwise
# fact: the contents of lib/ -- --lib override, a scratch directory under logs/ in --selftest
# This tool reads no seed, no character and no world.
"""
import argparse
import os
import pathlib
import re
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import resource_order_check as roc  # noqa: E402

ROOT_OVERRIDDEN = False  # --root: run this copy against another checkout
BEAD_RE = re.compile(r"^inc-[a-z0-9]+(\.[0-9]+)*$")
INCLUDE_RE = re.compile(r'^#include "(landed-inc-[a-z0-9]+(?:\.[0-9]+)*\.irh)"$')


class Cannot(Exception):
    """The check cannot establish its facts: exit 2."""


def git(*args):
    p = subprocess.run(["git", "-C", str(ROOT)] + list(args), stdin=subprocess.DEVNULL,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return p.returncode, p.stdout.decode("utf-8", "replace")


def strip_comments(text):
    """Remove /* */ and // comments; leave string literals alone."""
    out, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if c == '"':
            j = i + 1
            while j < n and text[j] != '"':
                j += 2 if text[j] == "\\" else 1
            out.append(text[i:j + 1])
            i = j + 1
        elif text.startswith("/*", i):
            j = text.find("*/", i + 2)
            i = n if j < 0 else j + 2
            out.append(" ")
        elif text.startswith("//", i):
            j = text.find("\n", i)
            i = n if j < 0 else j
        else:
            out.append(c)
            i += 1
    return "".join(out)


def read_report(path, what):
    try:
        text = pathlib.Path(path).read_text(encoding="utf-8", errors="replace")
        return roc.parse(text)
    except (OSError, ValueError) as e:
        raise Cannot("cannot read %s %s: %s" % (what, path, e))


def array_entries(rep):
    """array name -> list of entry names."""
    return {rep.array_names.get(k, "?%d" % k[1]): v for k, v in rep.arrays.items()}


def module_vars(rep):
    out = []
    for (slot, oa, op), names in rep.owners.items():
        if oa == -1 and op == -1:
            out.extend(names)
    return out


RETIRED = ";retired"


def new_names(dump, base, parents=()):
    """[(kind, array name or '', name)] the dump holds and neither the base nor a merged parent does."""
    out = []
    held = [array_entries(r) for r in (base,) + tuple(parents)]
    for arr, names in array_entries(dump).items():
        have = set()
        present = set(names)
        for h in held:
            have.update(h.get(arr, []))
            old = h.get(arr, [])
            for i, o in enumerate(old[:len(names)]):
                if o != names[i] and o not in present:
                    have.add(names[i])
        seen = set()
        for nm in names:
            if nm.endswith(RETIRED) and nm[:-len(RETIRED)] in have:
                continue
            if nm not in have and nm not in seen:
                seen.add(nm)
                out.append(("resource", arr, nm))
    have = set(module_vars(base))
    for r in parents:
        have.update(module_vars(r))
    seen = set()
    for nm in module_vars(dump):
        if nm not in have and nm not in seen:
            seen.add(nm)
            out.append(("variable", "module-level script variable", nm))
    return out


def declared_in(kind, nm, body):
    if kind == "resource":
        return ('"%s"' % nm) in body
    return re.search(r"(?<![A-Za-z0-9_])%s(?![A-Za-z0-9_])" % re.escape(nm), body) is not None


def check(bead, dump, base, lib, parents=(), parent_bodies=()):
    """Return the list of refusal messages (empty = clean)."""
    refusals = []
    landed_irc = lib / "landed.irc"
    try:
        irc_lines = landed_irc.read_text(encoding="utf-8").splitlines()
    except OSError as e:
        raise Cannot("cannot read %s: %s" % (landed_irc, e))
    included = set()
    for ln in irc_lines:
        ln = ln.rstrip("\r")
        if ln == "":
            continue
        m = INCLUDE_RE.match(ln)
        if not m:
            refusals.append('lib/landed.irc holds a line that is not `#include "landed-<bead-id>.irh"`: %r' % ln)
            continue
        included.add(m.group(1))
        if not (lib / m.group(1)).is_file():
            refusals.append("lib/landed.irc includes lib/%s, which does not exist" % m.group(1))
    for f in sorted(lib.glob("landed-*.irh")):
        if f.name not in included:
            refusals.append('lib/%s is not included: append `#include "%s"` to lib/landed.irc'
                            % (f.name, f.name))
    mine = "landed-%s.irh" % bead
    try:
        body = strip_comments((lib / mine).read_text(encoding="utf-8", errors="replace"))
    except OSError:
        body = None
    for kind, arr, nm in new_names(dump, base, parents):
        found = body is not None and declared_in(kind, nm, body)
        if not found and any(declared_in(kind, nm, pb) for pb in parent_bodies):
            continue
        if not found:
            refusals.append(
                'new %s %r (%s) is not declared in lib/%s: declare it there and append '
                '`#include "%s"` to lib/landed.irc' % (kind, nm, arr, mine, mine))
    return refusals


def merged_parents(bead, base_name):
    """(reports, landed bodies) of the merged parents of this branch; see the docstring."""
    shas = []
    rc, out = git("rev-list", "--merges", "--parents", "%s..HEAD" % base_name)
    if rc == 0:
        for ln in out.splitlines():
            shas.extend(ln.split()[2:])
    rc, out = git("rev-parse", "-q", "--verify", "MERGE_HEAD")
    if rc == 0 and out.strip():
        shas.append(out.strip())
    rc, out = git("ls-tree", "-r", "--name-only", base_name, "lib/")
    in_base = set(out.split("\n")) if rc == 0 else set()
    reports, bodies = [], []
    for sha in dict.fromkeys(shas):
        rc, text = git("show", "%s:tools/resource_order.ledger" % sha)
        if rc == 0:
            try:
                reports.append(roc.parse(text))
            except ValueError as e:
                raise Cannot("ledger of merged parent %s unreadable: %s" % (sha[:10], e))
        rc, out = git("ls-tree", "-r", "--name-only", sha, "lib/")
        for path in (out.split("\n") if rc == 0 else []):
            fn = path[len("lib/"):]
            if (path.startswith("lib/landed-") and path.endswith(".irh") and path not in in_base
                    and fn != "landed-%s.irh" % bead):
                rc, text = git("show", "%s:%s" % (sha, path))
                if rc == 0:
                    bodies.append(strip_comments(text))
    return reports, bodies


def run(bead, dump_path, base_path, lib, parent_paths=None):
    if bead is None:
        rc, out = git("rev-parse", "--abbrev-ref", "HEAD")
        if rc != 0:
            raise Cannot("cannot read the branch name")
        bead = out.strip()
    if not BEAD_RE.match(bead):
        raise Cannot("branch %r is not a bead id (inc-<id>[.<n>])" % bead)
    if dump_path is None:
        try:
            if not roc.BIN.exists():
                raise Cannot("%s not built; run BACKEND=posix ./build_macos.sh" % roc.BIN.name)
            dump = roc.parse(roc.module_report(ROOT if ROOT_OVERRIDDEN else None))
        except SystemExit as e:
            raise Cannot(str(e.code))
        except (OSError, ValueError) as e:
            raise Cannot("cannot read the module dump: %s" % e)
    else:
        dump = read_report(dump_path, "module dump")
    if base_path is None:
        rc, base_name = git("config", "--get", "branch.%s.incursionBase" % bead)
        base_name = base_name.strip() if rc == 0 and base_name.strip() else "master"
        rc, text = git("show", "%s:tools/resource_order.ledger" % base_name)
        if rc != 0:
            raise Cannot("cannot read %s:tools/resource_order.ledger" % base_name)
        try:
            base = roc.parse(text)
        except ValueError as e:
            raise Cannot("base ledger unreadable: %s" % e)
    else:
        base = read_report(base_path, "base ledger")
    if parent_paths is None:
        rc, base_name = git("config", "--get", "branch.%s.incursionBase" % bead)
        base_name = base_name.strip() if rc == 0 and base_name.strip() else "master"
        parents, bodies = merged_parents(bead, base_name)
    else:
        parents = [read_report(p, "merged parent ledger") for p in parent_paths]
        bodies = []
        for p in parent_paths:
            for f in sorted(pathlib.Path(str(p) + ".landed").glob("*.irh")):
                bodies.append(strip_comments(f.read_text(encoding="utf-8", errors="replace")))
    return check(bead, dump, base, lib, parents, bodies)


def selftest():
    work = ROOT / "logs" / ("check-landed-selftest-%d" % os.getpid())
    shutil.rmtree(work, ignore_errors=True)
    work.mkdir(parents=True)
    fails = []

    def rec(arrays, vars_=()):
        lines = []
        for i, (an, names) in enumerate(arrays):
            lines.append("A\t0\t%d\t%s" % (i, an))
            for p, nm in enumerate(names):
                lines.append("E\t0\t%d\t%d\t%s" % (i, p, nm))
        lines.append("O\t0\t-1\t-1\t(module)")
        for o, v in enumerate(vars_):
            lines.append("V\t0\t-1\t-1\t%d\t%s\tint16" % (o, v))
        return "\n".join(lines) + "\n"

    base_arrays = [("Effect", ["Fire", "Ice"]), ("Flavour", ["red", "red", "blue"])]
    n = [0]

    def case(label, want, *, bead="inc-t1", dump=None, base=None, irc="", files=None,
             badbead=None, nodump=False, nobase=False, parent=None, parent_landed=None):
        n[0] += 1
        d = work / ("c%d" % n[0])
        lib = d / "lib"
        lib.mkdir(parents=True)
        (lib / "landed.irc").write_text(irc)
        for fn, body in (files or {}).items():
            (lib / fn).write_text(body)
        dp = d / "dump"
        bp = d / "base"
        dp.write_text(dump if dump is not None else rec(base_arrays, ["v1"]))
        if nodump:
            dp = d / "absent"
        bp.write_text(base if base is not None else rec(base_arrays, ["v1"]))
        if nobase:
            bp.write_text("garbage line\n")
        pp = []
        if parent is not None:
            pl = d / "parent"
            pl.write_text(parent)
            pp = [pl]
            if parent_landed:
                (d / "parent.landed").mkdir()
                for fn, body in parent_landed.items():
                    (d / "parent.landed" / fn).write_text(body)
        try:
            got = 1 if run(badbead or bead, dp, bp, lib, pp) else 0
        except Cannot:
            got = 2
        if got != want:
            fails.append("%s: want exit %d, got %d" % (label, want, got))

    inc = '#include "landed-inc-t1.irh"\n'
    plus = rec([("Effect", ["Fire", "Ice", "Zap"]), ("Flavour", ["red", "red", "blue"])], ["v1"])
    case("clean pass", 0)
    case("new effect absent", 1, dump=plus)
    case("new effect present", 0, dump=plus, irc=inc,
         files={"landed-inc-t1.irh": 'Effect "Zap" : 1 { }\n'})
    case("new effect only in comment", 1, dump=plus, irc=inc,
         files={"landed-inc-t1.irh": '// Zap\n/* "Zap" */\n'})
    case("new effect unquoted", 1, dump=plus, irc=inc,
         files={"landed-inc-t1.irh": 'Zap\n'})
    plusv = rec(base_arrays, ["v1", "newvar"])
    case("new variable absent", 1, dump=plusv)
    case("new variable present", 0, dump=plusv, irc=inc,
         files={"landed-inc-t1.irh": "int16 newvar;\n"})
    case("new variable only a substring", 1, dump=plusv, irc=inc,
         files={"landed-inc-t1.irh": "int16 newvar2;\n"})
    case("unincluded landed file", 1, files={"landed-inc-t2.irh": "\n"})
    case("include names a missing file", 1, irc=inc)
    case("non-include line in landed.irc", 1, irc="junk\n")
    case("bad branch name", 2, badbead="master")
    case("unreadable dump", 2, nodump=True)
    case("unreadable ledger", 2, nobase=True)
    dupe = rec([("Effect", ["Fire", "Ice"]), ("Flavour", ["red", "red", "blue", "red"])], ["v1"])
    case("repeated Flavour name", 0, dump=dupe)
    # merge bead: base is the epic, a merged parent (master) holds what the epic lacks
    master = rec([("Effect", ["Fire", "Ice", "Zap"]), ("Flavour", ["red", "red", "blue"])], ["v1"])
    case("merged-parent resource accepted", 0, dump=plus, parent=master)
    case("merge bead's own stray resource refused", 1, dump=plus, parent=rec(base_arrays, ["v1"]))
    case("merged-parent landed file accepted", 0, dump=plus, parent=rec(base_arrays, ["v1"]),
         parent_landed={"landed-inc-t9.irh": 'Effect "Zap" : 1 { }\n'})
    case("merged-parent landed file comment only", 1, dump=plus, parent=rec(base_arrays, ["v1"]),
         parent_landed={"landed-inc-t9.irh": '// "Zap"\n'})
    case("merged-parent variable accepted", 0, dump=plusv,
         parent=rec(base_arrays, ["v1", "newvar"]))
    ret = rec([("Effect", ["Fire", "Ice;retired"]), ("Flavour", ["red", "red", "blue"])], ["v1"])
    case("tombstone of a base name accepted", 0, dump=ret)
    case("tombstone already in the base accepted", 0, dump=ret,
         base=rec([("Effect", ["Fire", "Ice;retired"]), ("Flavour", ["red", "red", "blue"])], ["v1"]))
    case("tombstone of a merged-parent name accepted", 0, dump=rec(
         [("Effect", ["Fire", "Ice", "Zap;retired"]), ("Flavour", ["red", "red", "blue"])], ["v1"]),
         parent=master)
    case("brand-new retired name refused", 1, dump=rec(
         [("Effect", ["Fire", "Ice", "Zap;retired"]), ("Flavour", ["red", "red", "blue"])], ["v1"]))
    ren = rec([("Effect", ["Fire", "Ice;grw"]), ("Flavour", ["red", "red", "blue"])], ["v1"])
    case("in-place rename accepted", 0, dump=ren)
    case("rename in place of a merged-parent name accepted", 0, dump=ren,
         parent=rec([("Effect", ["Fire", "Ice"]), ("Flavour", ["red", "red", "blue"])], ["v1"]),
         base=rec([("Effect", ["Fire", "Ice;grw"]), ("Flavour", ["red", "red", "blue"])], ["v1"]))
    case("rename with old name still present refused", 1, dump=rec(
         [("Effect", ["Fire", "Ice", "Ice;grw"]), ("Flavour", ["red", "red", "blue"])], ["v1"]))
    case("old name moved to another slot, new name added, refused", 1, dump=rec(
         [("Effect", ["Ice", "Fire2"]), ("Flavour", ["red", "red", "blue"])], ["v1"]))
    case("new name at a new position refused", 1, dump=rec(
         [("Effect", ["Fire", "Ice", "Zap2"]), ("Flavour", ["red", "red", "blue"])], ["v1"]))
    shutil.rmtree(work, ignore_errors=True)
    if fails:
        for f in fails:
            sys.stderr.write("SELFTEST FAIL: %s\n" % f)
        return 1
    print("selftest: %d cases pass" % n[0])
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--bead")
    ap.add_argument("--dump")
    ap.add_argument("--base-ledger")
    ap.add_argument("--lib")
    ap.add_argument("--root", help="checkout to measure (its branch, lib/ and module); default is this copy's")
    a = ap.parse_args()
    if a.root:
        global ROOT, ROOT_OVERRIDDEN
        ROOT = pathlib.Path(a.root).resolve()
        ROOT_OVERRIDDEN = True
    if a.selftest:
        return selftest()
    lib = pathlib.Path(a.lib) if a.lib else ROOT / "lib"
    try:
        refusals = run(a.bead, a.dump, a.base_ledger, lib)
    except Cannot as e:
        sys.stderr.write("check_landed_files: cannot establish: %s\n" % e)
        return 2
    for r in refusals:
        sys.stderr.write("REFUSED: %s\n" % r)
    if refusals:
        return 1
    print("check_landed_files: clean")
    return 0


if __name__ == "__main__":
    sys.exit(main())
