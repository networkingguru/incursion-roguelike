#!/usr/bin/env python3
# gate: cheap
# gate-fast: compiles one small C++ file per tree against inc/Incursion.h, about 1 s
"""Did a stored family keep every value it had on the base tree?

WHY THIS EXISTS. A save, Options.Dat or another file on disk holds the VALUE of
a stored #define or enumerator, not its name. If a branch changes that value,
removes the name, or hands the old number to a new name, every old file reads
as something else. Spec docs/superpowers/specs/2026-11-07-names-in-the-file-
design.md section 6 and AC5 (bead inc-cjos0, phase 5b).

WHAT IT DOES. It reads the family marks of the base tree (--base, default
master, taken with read-only `git archive`; nothing is checked out) and of the
tree under test (the working tree) through tools/check_define_dups.py
load_families. The class, shape and width come from the TREE's marks. The base
marks are read for membership only, so a base mark with no class is fine. For
every STORED family of the tree it FAILS (exit 1), naming family, name, both
values and file:line, when:
  1. a base name's value differs in the tree;
  2. a base name is absent from the tree, unless tools/retired_values.txt lists
     it (rows `<family> <NAME> <value>`);
  3. a tree-only name's value equals a value that a base name or a retired
     value holds in the same family (shape bits: the bits overlap);
  4. a name's value does not fit the width of the family (u8 0..255, i8
     -128..127 ...; shape bits: 0..2^w-1 as a bit pattern, or a negative
     value no lower than -2^(w-1));
  5. load_families reports any problem, an unclassified family included
     (a function-like #define inside a stored family is one, see
     check_define_dups.py);
  6. (shape bits) two names of the tree have different masks that overlap,
     tree-only names included, unless the larger mask is an AGGREGATE: exactly
     the OR of the smaller masks of the family (KN_IDENTIFIED is KN_ARTI |
     KN_RUSTPROOF). Equal masks are aliases, left to check_define_dups.py. A
     partial overlap is never allowed;
  7. (shape ordinal or enum, mark `bound <NAME>`) a value of the family is not
     below the bound's value, or the tree's mark drops a `bound` that the base
     mark carries. The bound sizes the array the values index (OPT_LAST sizes
     Options[]). The bound name itself is a stored value, compared by rule 1;
  9. (mark `grows <NAME>`, spec 6.1) a limit that sizes a saved array has a
     tree value BELOW the base's, or the tree's mark drops a `grows` the base
     mark carries. A value above the base's passes rule 1. The base value is
     read from the base's family, else compiled on the base tree (a limit
     that sat in a no-family block there). A new member of the family MAY take
     the value the limit had on the base: that value is not held (rule 3);
 10. (shape bits) a tree-only name holds several bits and is not exactly the OR
     of named smaller masks. A new flag takes one free bit, as the mover gives
     it. Base names are not tested (KN_IDENTIFIED 0x60 overlaps KN_ARTI 0x20
     and KN_RUSTPROOF 0x40 on master and passes);
 11. (families sk and ft, spec 6.2) a tree-only skill is not in
     SK_HIGH_FIRST .. SK_HIGH_END-1, or is above 999; a tree-only feat is above
     799; a tree-only feat or skill holds a number the other family holds.
     Feats and skills share one number space in a save. Skills 1-48 and base
     feats are not tested;
 12. (gap 8) a FIELD_ARRAY or FIELD_ARRAY_ROWS count in inc/ or src/ is neither
     an expression of `grows` limits nor frozen. A frozen count is a literal or an
     unmarked constant; its value MUST equal the value at the same site (file and
     member) on the base. A new site passes and is frozen from then on. A count that
     is no constant (a variable, a sizeof) is not compared. The fix names the site,
     the old and new value: mark the limit `grows` (spec 6.1) or restore it;
  8. inc/SaveLegacyTags.h differs from the base ref's copy. That table
     describes files already written; a branch never edits it. A base that has
     no such file freezes nothing.
WHICH CLASS DECIDES. When the BASE mark of a family carries a class, the base
class decides for that family's base names: a name of a base family that is
stored MUST appear in a stored family of the tree with the same value, else
FAIL as removed (unless retired). Moving it to an internal family, or marking
the whole family internal, FAILs naming the name. Only when the base mark has
no class (master before inc-cjos0 lands) does the tree's class decide, and a
base name that the tree moved to another family keeps its value there without
a FAIL.
KNOWN LIMITS. A member that lives in a .cpp file takes the text evaluator's
value, with no compiler cross-check. A tree-only alias of a base value trips
rule 3, because load_families does not expose alias marks.
A name listed as `sentinel <NAME>` on a mark sizes memory only; it is exempt
from rules 1-4. A stored-array sentinel (ATTR_LAST) carries no such clause, so
rule 1 covers a changed one. A family the tree marks `internal`, or does not
mark, is not compared.
Exit 2 (UNMEASURED) when the base cannot be read, a name cannot be evaluated,
the compiler fails, or the compiler and the text evaluator of
check_define_dups.py disagree on a value. It never passes on a measurement it
could not make.

VALUES. The compiler is the authority. For each tree the check writes one C++
file that includes inc/Incursion.h and prints `NAME value` for every member
that lives in a header, then compiles and runs it with the posix flags of
tools/check_number_values.sh. A member that lives in a .cpp file (marked there
because it is local to that file) cannot be included, so its value is the text
evaluator's; the summary line counts them. Both trees compile at once. The
selftest skips the compiler and uses the text values only.

Usage: tools/check_stored_values.py [--base REF] [--selftest]
Exit:  0 clean   1 a stored value changed, collided or does not fit   2 unmeasured

# fact: the base tree -- a git ref read with `git archive`; default master, re-read on every run
# fact: define and enumerator values -- the compiler at the posix flags of build_macos.sh; no game run, no seed
# fact: family, class, shape, width -- the marks in inc/ and src/ of each tree; no randomness
# fact: retired values -- tools/retired_values.txt, a tracked file
"""
import concurrent.futures
import os
import re
import shutil
import subprocess
import sys
import tempfile
import warnings

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_define_dups as cdd  # noqa: E402

ROOT = cdd.ROOT
RETIRED = os.path.join(ROOT, "tools", "retired_values.txt")
FLAGS = ("-DDEBUG -DPOSIX_TERM -Iinc -Ilib -Icompat -fpermissive -Wno-narrowing "
         "-w -std=c++17").split()
BITS = {"u8": 8, "i8": 8, "u16": 16, "i16": 16, "u32": 32, "i32": 32}


class Unmeasured(Exception):
    pass


def fits(value, shape, width):
    n = BITS[width]
    if shape == "bits":
        return -(1 << (n - 1)) <= value < (1 << n)
    if width[0] == "u":
        return 0 <= value < (1 << n)
    return -(1 << (n - 1)) <= value < (1 << (n - 1))


def pattern(value, width):
    return value & ((1 << BITS[width]) - 1)


def clash(shape, width, a, b):
    if shape == "bits":
        return pattern(a, width) & pattern(b, width) != 0
    return a == b


def read_retired(path):
    """Return {family: [(name, value)]}."""
    out = {}
    try:
        with open(path) as f:
            for no, line in enumerate(f, 1):
                s = line.split("#", 1)[0].split()
                if not s:
                    continue
                try:
                    if len(s) != 3:
                        raise ValueError
                    out.setdefault(s[0], []).append((s[1], int(s[2], 0)))
                except ValueError:
                    raise Unmeasured("%s line %d: want '<family> <NAME> <value>'"
                                     % (path, no))
    except OSError as e:
        raise Unmeasured("cannot read %s: %s" % (path, e))
    return out


def where(m):
    return "%s:%d" % (m[2], m[3])


LEGACY_TABLE = "inc/SaveLegacyTags.h"


def legacy_table_problem(ref, root):
    """Rule 8. Return a FAIL line, or None when the tree's table is the base's
    (or the base has none). Raises Unmeasured when git cannot answer."""
    r = subprocess.run(["git", "-C", root, "cat-file", "-e", "%s:%s" % (ref, LEGACY_TABLE)],
                       capture_output=True, text=True)
    if r.returncode != 0:
        return None  # no such file on the base: nothing frozen yet
    r = subprocess.run(["git", "-C", root, "show", "%s:%s" % (ref, LEGACY_TABLE)],
                       capture_output=True)
    if r.returncode != 0:
        raise Unmeasured("cannot read %s of %s: %s" % (LEGACY_TABLE, ref,
                                                         r.stderr.decode().strip()))
    try:
        with open(os.path.join(root, LEGACY_TABLE), "rb") as f:
            now = f.read()
    except OSError as e:
        return ("FAIL: %s is gone from the tree; it is on %s. It describes files already "
                "written, so a branch never removes it (%s)" % (LEGACY_TABLE, ref, e))
    if now != r.stdout:
        return ("FAIL: %s differs from %s. It describes files already written, so a "
                "branch never edits it. Fix: restore it with `git checkout %s -- %s`."
                % (LEGACY_TABLE, ref, ref, LEGACY_TABLE))
    return None


def overlap_problems(fam, t):
    """Rule 6 for one stored bits family t. Return FAIL lines."""
    width = t["width"]
    sent = set(t["sentinels"])
    mem = {}
    for m in t["members"]:
        if m[0] not in sent:
            mem.setdefault(m[0], m)
    pats = {n: pattern(m[1], width) for n, m in mem.items()}

    def aggregate(name):
        acc = 0
        for n, p in pats.items():
            if n != name and p and p != pats[name] and p & pats[name] == p:
                acc |= p
        return acc == pats[name]
    out, names = [], sorted(mem)
    for i, an in enumerate(names):
        for bn in names[i + 1:]:
            pa, pb = pats[an], pats[bn]
            if pa == pb or not pa & pb:
                continue
            if pa & pb == pb:
                hi, lo = an, bn
            elif pa & pb == pa:
                hi, lo = bn, an
            else:
                hi = lo = None
            if hi is not None and aggregate(hi):
                continue
            out.append("FAIL: family %s %s = 0x%X at %s and %s = 0x%X at %s share bits "
                       "0x%X with different meanings. Fix: give each its own free bit; "
                       "a larger mask is allowed only as exactly the OR of the smaller "
                       "masks of the family"
                       % (fam, an, mem[an][1], where(mem[an]), bn, mem[bn][1], where(mem[bn]),
                          pa & pb))
    return out


def new_bits_problems(fam, t, b):
    """Rule 10 for one stored bits family t; b is the base's family dict (may be {}).
    A tree-only member takes one bit, or is exactly the OR of named smaller masks
    (an aggregate). Members the base holds are not tested (KN_IDENTIFIED 0x60)."""
    width = t["width"]
    skip = set(t["sentinels"]) | set(t.get("grows", []))
    have = {m[0] for m in b.get("members", [])}
    mem = {}
    for m in t["members"]:
        mem.setdefault(m[0], m)
    pats = {n: pattern(m[1], width) for n, m in mem.items() if n not in skip}
    out = []
    for name, m in sorted(mem.items()):
        if name in have or name in skip:
            continue
        p = pats[name]
        if p & (p - 1) == 0:
            continue
        acc = 0
        for n, q in pats.items():
            if n != name and q and q != p and q & p == q:
                acc |= q
        if acc != p:
            out.append("FAIL: family %s %s = 0x%X at %s is a new member that holds several "
                       "bits and is not the OR of named members. Fix: take one free bit "
                       "(tools/move_branch_values.py gives the lowest); a new mask is "
                       "allowed only as exactly the OR of smaller masks of the family"
                       % (fam, name, m[1], where(m)))
    return out


SKILL_CEILING = 999    # spec 6.2: new skills take 800..999
FEAT_CEILING = 799     # feats stay below the first high skill


def space_problems(base, tree):
    """Rules 11 and 12: the feat and skill number space (spec 6.2, R14). A saved Feats bit and
    a saved SkillRanks row are keyed by one number. Only tree-only members are tested; skills
    1-48 and the feats of the base stay as they are. Return FAIL lines."""
    def new_members(fam):
        t = tree.get(fam)
        if t is None or t["class"] != "stored":
            return None, {}, {}
        skip = set(t["sentinels"]) | set(t.get("grows", []))
        have = {m[0] for m in base.get(fam, {}).get("members", [])}
        allm, new = {}, {}
        for m in t["members"]:
            if m[0] in skip:
                continue
            allm.setdefault(m[0], m)
            if m[0] not in have:
                new.setdefault(m[0], m)
        return t, allm, new
    sk, sk_all, sk_new = new_members("sk")
    ft, ft_all, ft_new = new_members("ft")
    out = []
    if sk is not None:
        first = end = None
        for d in tree.values():
            for m in d["members"]:
                if m[0] == "SK_HIGH_FIRST":
                    first = first if first is not None else m[1]
                if m[0] == "SK_HIGH_END" and d is sk:
                    end = end if end is not None else m
        if first is None or end is None:
            out.append("FAIL: family sk cannot be tested: SK_HIGH_FIRST or SK_HIGH_END is not "
                       "in the tree. Fix: keep both names (spec 6.2)")
        else:
            for name, m in sorted(sk_new.items()):
                if not first <= m[1] < end[1] or m[1] > SKILL_CEILING:
                    out.append("FAIL: family sk %s = %d at %s is outside the new-skill band "
                               "%d .. SK_HIGH_END-1 (SK_HIGH_END = %d), at most %d. Fix: take the "
                               "next number from SK_HIGH_FIRST and raise SK_HIGH_END by one "
                               "(a skill outside the band reads and writes the empty rank row)"
                               % (name, m[1], where(m), first, end[1], SKILL_CEILING))
    if ft is not None:
        for name, m in sorted(ft_new.items()):
            if m[1] > FEAT_CEILING:
                out.append("FAIL: family ft %s = %d at %s is in the shared feat/skill space above "
                           "the feat ceiling %d. Fix: take a feat number below %d; 800 and up "
                           "belong to skills" % (name, m[1], where(m), FEAT_CEILING, FEAT_CEILING + 1))
    for fam_a, new_a, all_b, fam_b in (("ft", ft_new, sk_all, "sk"), ("sk", sk_new, ft_all, "ft")):
        for name, m in sorted(new_a.items()):
            for hn, hm in sorted(all_b.items()):
                if hm[1] == m[1]:
                    out.append("FAIL: family %s %s = %d at %s and family %s %s = %d at %s share "
                               "one number in the shared feat/skill space. Fix: give the new "
                               "one a number no %s holds"
                               % (fam_a, name, m[1], where(m), fam_b, hn, hm[1], where(hm), fam_b))
    return out


def bound_problems(fam, t, b):
    """Rule 7 for one stored family t; b is the base's family dict (may be {})."""
    out = []
    bounds = t.get("bounds", [])
    for bn in b.get("bounds", []):
        if bn not in bounds:
            out.append("FAIL: family %s: the base mark says 'bound %s' and the tree's mark "
                       "drops it. Fix: keep the `bound %s` clause" % (fam, bn, bn))
    sent = set(t["sentinels"])
    vals = {}
    for m in t["members"]:
        vals.setdefault(m[0], m)
    for bn in bounds:
        if bn not in vals:
            continue  # load_families reported it
        lim = vals[bn][1]
        for name, m in sorted(vals.items()):
            if name in sent or name in bounds or m[1] < lim:
                continue
            out.append("FAIL: family %s %s = %d at %s is not below the bound %s = %d (%s). "
                       "The bound sizes the array this value indexes. Fix: take a free "
                       "value below it"
                       % (fam, name, m[1], where(m), bn, lim, where(vals[bn])))
    return out


def compare(base, tree, problems, retired):
    """base, tree: load_families results. Return (FAIL lines, names compared)."""
    out = ["FAIL: " + (p[6:] if p.startswith("FAIL: ") else p) for p in problems]
    ncomp = 0
    anywhere = {}  # name -> member, over every family of the tree
    for d in tree.values():
        for m in d["members"]:
            anywhere.setdefault(m[0], m)
    for fam in sorted(set(tree) | set(base)):
        t = tree.get(fam)
        b_stored = base.get(fam, {}).get("class") == "stored"
        if t is None or t["class"] != "stored":
            if b_stored:  # the base says stored; the tree must not drop the class
                ret = dict(retired.get(fam, []))
                for m in base[fam]["members"]:
                    if m[0] in base[fam]["sentinels"] or m[0] in ret:
                        continue
                    ncomp += 1
                    now = anywhere.get(m[0])
                    out.append("FAIL: family %s %s = %d (base %s) is stored on the base but "
                               "the tree %s. Fix: keep it in a stored family, or list it in "
                               "tools/retired_values.txt"
                               % (fam, m[0], m[1], where(m),
                                  "has it in %s at %s" % ("an internal family", where(now))
                                  if now else "no longer has it"))
            continue
        shape, width = t["shape"], t["width"]
        sent = set(t["sentinels"])
        grows = set(t.get("grows", []))
        tvals = {}
        for m in t["members"]:
            tvals.setdefault(m[0], m)
        bvals = {}
        for m in base.get(fam, {}).get("members", []):
            bvals.setdefault(m[0], m)
        ret = dict(retired.get(fam, []))
        for gn in base.get(fam, {}).get("grows", []):
            if gn not in grows:
                out.append("FAIL: family %s: the base mark says 'grows %s' and the tree's mark "
                           "drops it. Fix: keep the `grows %s` clause" % (fam, gn, gn))
        for gn, bv in sorted(t.get("grows_base", {}).items()):
            if gn in grows and gn in tvals and gn not in bvals:
                ncomp += 1
                if tvals[gn][1] < bv:
                    out.append("FAIL: family %s %s shrank: base %d, tree %d (%s). A limit "
                               "that sizes a saved array may grow and must not shrink"
                               % (fam, gn, bv, tvals[gn][1], where(tvals[gn])))
        for name, m in sorted(tvals.items()):
            if name not in sent and not fits(m[1], shape, width):
                out.append("FAIL: family %s %s = %d at %s does not fit %s (shape %s)"
                           % (fam, name, m[1], where(m), width, shape))
        for name, b in sorted(bvals.items()):
            if name in sent:
                continue
            ncomp += 1
            # A name the tree moved to another family (an internal one) is not
            # gone: it keeps its value, and the tree's class says it is not stored.
            now = tvals.get(name) if b_stored else anywhere.get(name)
            if now is not None:
                if name in grows and now[1] >= b[1]:
                    pass   # a limit that sizes a saved array may grow
                elif name in grows:
                    out.append("FAIL: family %s %s shrank: base %d (%s), tree %d (%s). A limit "
                               "that sizes a saved array may grow and must not shrink"
                               % (fam, name, b[1], where(b), now[1], where(now)))
                elif now[1] != b[1]:
                    out.append("FAIL: family %s %s changed: base %d (%s), tree %d (%s)"
                               % (fam, name, b[1], where(b), now[1], where(now)))
            elif name not in ret:
                out.append("FAIL: family %s %s = %d (base %s) is gone from the tree. "
                           "Fix: keep the name, or list it in tools/retired_values.txt"
                           % (fam, name, b[1], where(b)))
            if (name in tvals or b_stored) and not fits(b[1], shape, width):
                out.append("FAIL: family %s %s = %d at base %s does not fit %s (shape %s)"
                           % (fam, name, b[1], where(b), width, shape))
        if shape == "bits":
            out += overlap_problems(fam, t)
            out += new_bits_problems(fam, t, base.get(fam, {}))
        out += bound_problems(fam, t, base.get(fam, {}))
        for name, m, hn, hv, why in family_collisions(t, base.get(fam, {}), ret):
            out.append("FAIL: family %s tree-only %s = %d at %s reuses the value "
                       "of %s = %d (%s)" % (fam, name, m[1], where(m), hn, hv, why))
    out += space_problems(base, tree)
    return out, ncomp


def family_collisions(t, b, ret):
    """Rule 3 for one stored family. t, b: the tree's and the base's family dict
    (b may be {}); ret: {name: value} retired. Return [(name, member, holder name,
    holder value, why)], one per clash, in the order compare reports them.
    tools/move_branch_values.py imports it."""
    shape, width = t["shape"], t["width"]
    sent = set(t["sentinels"])
    grows = set(t.get("grows", []))   # a limit is no stored value: its base value is free
    tvals = {}
    for m in t["members"]:
        tvals.setdefault(m[0], m)
    bvals = {}
    for m in b.get("members", []):
        bvals.setdefault(m[0], m)
    held = [(n, bm[1], "base %s" % where(bm)) for n, bm in bvals.items()
            if n not in sent and n not in grows]
    held += [(n, v, "retired") for n, v in ret.items()]
    out = []
    for name, m in sorted(tvals.items()):
        if name in bvals or name in sent or name in grows:
            continue
        for hn, hv, why in held:
            if clash(shape, width, m[1], hv):
                out.append((name, m, hn, hv, why))
    return out


def clean_path(path, tmp):
    return path[len(tmp) + 1:] if path.startswith(tmp + os.sep) else path


def read_families(tree_root, strictly):
    """Return (families, problems) for the tree on disk at tree_root."""
    defines = os.path.join(tree_root, "inc", "Defines.h")
    if not os.path.isfile(defines):
        raise Unmeasured("%s does not exist" % defines)
    files = [defines] + [p for p in cdd.marked_files(tree_root) if p != defines]
    try:
        fams, problems = cdd.load_families(files=files)
    except cdd.Unmeasurable as e:
        raise Unmeasured(str(e))
    for d in fams.values():
        d["members"] = [(n, v, clean_path(p, tree_root), l) for n, v, p, l in d["members"]]
    return fams, (problems if strictly else [])


def compile_values(tree_root, names, optional=False):
    """Compile and run a printer for the names. Return {name: value}. optional:
    a name the tree does not #define is left out (the base may lack a new limit)."""
    if not names:
        return {}
    work = tempfile.mkdtemp(prefix="stored_values.")
    try:
        lines = ['#include "Incursion.h"', "#include <cstdio>",
                 '#define NVP(n, v) printf("%s %lld\\n", n, (long long)(v))',
                 "int main() {"]
        if optional:
            lines += ['#ifdef %s\nNVP("%s", %s);\n#endif' % (n, n, n) for n in sorted(names)]
        else:
            lines += ['NVP("%s", %s);' % (n, n) for n in sorted(names)]
        lines += ["return 0; }"]
        cpp, exe = os.path.join(work, "sv.cpp"), os.path.join(work, "sv")
        with open(cpp, "w") as f:
            f.write("\n".join(lines) + "\n")
        r = subprocess.run(["clang++"] + FLAGS + ["-ferror-limit=5", "-o", exe, cpp],
                           cwd=tree_root, capture_output=True, text=True)
        if r.returncode != 0:
            raise Unmeasured("the compiler failed in %s:\n%s" % (tree_root, r.stderr[-1500:]))
        r = subprocess.run([exe], capture_output=True, text=True)
        out = {}
        for ln in r.stdout.split("\n"):
            if ln.strip():
                n, v = ln.split()
                out[n] = int(v)
        missing = set() if optional else names - set(out)
        if missing:
            raise Unmeasured("the compiler printed no value for %s" % sorted(missing)[:5])
        return out
    except OSError as e:
        raise Unmeasured("cannot run the compiler: %s" % e)
    finally:
        shutil.rmtree(work, ignore_errors=True)


def apply_compiler(fams, tree_root):
    """Replace each header member's value by the compiler's. Return the number
    of members whose value stayed the text evaluator's (.cpp members)."""
    names = {m[0] for d in fams.values() for m in d["members"] if m[2].endswith(".h")}
    vals = compile_values(tree_root, names)
    kept = 0
    for fam, d in fams.items():
        new = []
        for n, v, p, l in d["members"]:
            if p.endswith(".h"):
                c = vals[n]
                if c != v and (c - v) % (1 << 64) != 0:
                    raise Unmeasured("%s at %s:%d: compiler says %d, text evaluator says %d"
                                     % (n, p, l, c, v))
                v = c
            else:
                kept += 1
            new.append((n, v, p, l))
        d["members"] = new
    return kept


def attach_grows_base(base, tree, base_root):
    """Put the base value of each `grows` limit the base families do not hold into
    tree[fam]["grows_base"]. On the base such a limit may sit in a no-family block,
    where no family reads it; the compiler reads it from the base tree."""
    def need(fam, d):
        have = {m[0] for m in base.get(fam, {}).get("members", [])}
        return [g for g in d.get("grows", []) if g not in have] if d["class"] == "stored" else []
    want = {g for fam, d in tree.items() for g in need(fam, d)}
    vals = compile_values(base_root, want, optional=True)
    for fam, d in tree.items():
        d["grows_base"] = {g: vals[g] for g in need(fam, d) if g in vals}


def extract_base(ref, dest, root=None):
    """Read-only: git archive of the source directories of ref into dest."""
    root = root or ROOT
    r = subprocess.run(["git", "-C", root, "ls-tree", "--name-only", ref],
                       capture_output=True, text=True)
    if r.returncode != 0:
        raise Unmeasured("cannot read base %s: %s" % (ref, r.stderr.strip()))
    top = [x for x in r.stdout.split() if x in ("inc", "src", "lib", "compat")]
    if "inc" not in top:
        raise Unmeasured("base %s has no inc/" % ref)
    arch = subprocess.Popen(["git", "-C", root, "archive", ref] + top, stdout=subprocess.PIPE)
    t = subprocess.run(["tar", "-x", "-C", dest], stdin=arch.stdout, capture_output=True)
    arch.stdout.close()
    if arch.wait() != 0 or t.returncode != 0:
        raise Unmeasured("cannot extract base %s: %s" % (ref, t.stderr.decode()[-300:]))


ARRAY_SITES = ({}, {})  # (base, tree) FIELD_ARRAY sites of the last measure() call


def measure(ref, root=None, use_compiler=True, retired_path=None):
    """Read the base ref and the tree at root. Return (base, tree, problems,
    retired, kept): the inputs of compare(). Raises Unmeasured. The base is
    extracted to a temporary directory that is removed before return.
    use_compiler False keeps the text evaluator's values (selftests)."""
    root = root or ROOT
    tmp = tempfile.mkdtemp(prefix="stored_base.")
    try:
        extract_base(ref, tmp, root)
        retired = read_retired(retired_path or os.path.join(root, "tools", "retired_values.txt"))
        base, _ignored = read_families(tmp, False)
        tree, problems = read_families(root, True)
        kept = 0
        global ARRAY_SITES
        ARRAY_SITES = (read_array_sites(tmp), read_array_sites(root))
        if use_compiler:
            with concurrent.futures.ThreadPoolExecutor(2) as ex:
                fb = ex.submit(apply_compiler, base, tmp)
                ft = ex.submit(apply_compiler, tree, root)
                kept = ft.result()
                fb.result()
            attach_grows_base(base, tree, tmp)
        return base, tree, problems, retired, kept
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def run(ref):
    try:
        base, tree, problems, retired, kept = measure(ref, ROOT, True, RETIRED)
        msgs, ncomp = compare(base, tree, problems, retired)
        grows_names = {g for d in tree.values() if d["class"] == "stored" for g in d["grows"]}
        arr, nsites, nfrozen = array_problems(ARRAY_SITES[0], ARRAY_SITES[1], grows_names)
        msgs += arr
        legacy = legacy_table_problem(ref, ROOT)
        if legacy:
            msgs.append(legacy)
        nfam = sum(1 for d in tree.values() if d["class"] == "stored")
        if msgs:
            print("\n".join(msgs), file=sys.stderr)
            return 1
        print("check_stored_values: PASS (%d stored families, %d base names compared "
              "against %s, %d tree values from source text; %d saved-array counts, %d frozen "
              "and compared)" % (nfam, ncomp, ref, kept, nsites, nfrozen))
        return 0
    except Unmeasured as e:
        print("check_stored_values: UNMEASURED: %s" % e, file=sys.stderr)
        return 2


ARRAY_MACRO = re.compile(r"\bFIELD_ARRAY(_ROWS)?\s*\(")
# the count arguments: FIELD_ARRAY(name,p,elem,count); FIELD_ARRAY_ROWS(name,p,elem,rows,rowLen,..)
ARRAY_COUNTS = {"": (("count", 3),), "_ROWS": (("rows", 3), ("rowLen", 4))}
DEFINE_LINE = re.compile(r"\s*#\s*define\s+([A-Za-z_]\w*)\s+(.+)$")
CONST_LINE = re.compile(r"\bstatic\s+const(?:expr)?\s+(?:[A-Za-z_]\w*\s+)+([A-Za-z_]\w*)\s*=\s*"
                        r"([^;]+);|\bconst(?:expr)?\s+(?:[A-Za-z_]\w*\s+)+([A-Za-z_]\w*)\s*=\s*([^;]+);")


def source_texts(root, needle=None):
    """{relative path: text without comments} of inc/ and src/ (.h, .cpp); with needle, only
    the files that contain it."""
    out = {}
    for sub in ("inc", "src"):
        top = os.path.join(root, sub)
        for dp, _dn, fns in os.walk(top):
            for fn in sorted(fns):
                if fn.endswith((".h", ".cpp")):
                    path = os.path.join(dp, fn)
                    with open(path, errors="replace") as f:
                        raw = f.read()
                    if needle is None or needle in raw:
                        out[os.path.relpath(path, root)] = cdd.strip_comments(raw)
    return out


def define_env(texts):
    """{NAME: int} of every integer #define, enumerator and const of the tree, resolved
    across files by repeated passes. A name the text evaluator cannot resolve is left out."""
    env, pending = {}, []
    for rel in sorted(texts):
        text = texts[rel]
        for no, line in cdd.logical_lines(text):
            m = DEFINE_LINE.match(line)
            if m and "(" not in m.group(1):
                pending.append((no, m.group(1), m.group(2)))
        for m in CONST_LINE.finditer(text):
            n, e = (m.group(1), m.group(2)) if m.group(1) else (m.group(3), m.group(4))
            pending.append((0, n, e))
        try:
            for _no, name, value, kind in cdd.read_defines(text, strict=False):
                if kind == "enum":
                    env.setdefault(name, value)
        except Exception:  # a file the text evaluator cannot read gives no enumerators
            pass
    for _ in range(8):
        left = []
        for no, name, body in pending:
            if name in env:
                continue
            try:
                env[name] = cdd.evaluate(cdd.to_python(cdd.tokens(body), no), env, no, name)
            except Exception:  # an expression the text evaluator cannot read
                left.append((no, name, body))
        if len(left) == len(pending):
            break
        pending = left
    return env


def split_args(text, start):
    """text[start] is just past the `(` of a macro. Return (args, end) split at top-level commas."""
    depth, args, cur, i = 1, [], [], start
    while i < len(text):
        c = text[i]
        if c == '"':
            j = i + 1
            while j < len(text) and text[j] != '"':
                j += 2 if text[j] == "\\" else 1
            cur.append(text[i:j + 1])
            i = j + 1
            continue
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
            if depth == 0:
                args.append("".join(cur).strip())
                return args, i
        elif c == "," and depth == 1:
            args.append("".join(cur).strip())
            cur = []
            i += 1
            continue
        cur.append(c)
        i += 1
    return args, i


def read_array_sites(root):
    """Return {(file, member expression, count role): {"expr", "idents", "line", "value"}} for
    every FIELD_ARRAY and FIELD_ARRAY_ROWS call in inc/ and src/. value() gives the count, or
    None when it is no constant (a variable, a sizeof): such a site cannot be compared. The
    defines of the tree are read only when a count names one."""
    warnings.simplefilter("ignore", SyntaxWarning)  # the text evaluator reads odd literals
    lazy = []

    def env():
        if not lazy:
            lazy.append(define_env(source_texts(root)))
        return lazy[0]

    def valuer(expr, line, what):
        def value():
            try:
                toks = cdd.tokens(expr)
                names = [t for t in toks if re.fullmatch(r"[A-Za-z_]\w*", t)]
                return cdd.evaluate(cdd.to_python(toks, line), env() if names else {}, line, what)
            except Exception:  # an expression the text evaluator cannot read
                return None
        return value
    sites = {}
    for rel, text in sorted(source_texts(root, "FIELD_ARRAY").items()):
        for m in ARRAY_MACRO.finditer(text):
            ls = text.rfind("\n", 0, m.start()) + 1
            if text[ls:m.start()].lstrip().startswith("#"):
                continue  # the macro's own definition
            args, _end = split_args(text, m.end())
            roles = ARRAY_COUNTS[m.group(1) or ""]
            line = text.count("\n", 0, m.start()) + 1
            if len(args) <= roles[-1][1]:
                raise Unmeasured("%s:%d: cannot read the FIELD_ARRAY call" % (rel, line))
            for role, k in roles:
                key = (rel, args[1], role)
                while key in sites:  # a repeated member in one file
                    key = key[:2] + (key[2] + "'",)
                sites[key] = dict(expr=args[k], line=line, value=valuer(args[k], line, args[1]),
                                  idents=set(re.findall(r"[A-Za-z_]\w*", args[k])))
    return sites


def array_problems(bsites, tsites, grows_names):
    """Gap 8: a saved array's count is a `grows` limit (or an expression of them), or it is
    frozen. Return (FAIL lines, number of sites, number of frozen sites compared)."""
    out, frozen = [], 0
    for key, c in sorted(tsites.items()):
        if c["idents"] & grows_names:
            continue
        cv = c["value"]()
        b = bsites.get(key)
        bv = b["value"]() if b is not None else None
        if cv is None or bv is None:
            continue  # a variable count, or a new site: frozen from now on
        frozen += 1
        if bv != cv:
            out.append("FAIL: array member %s (%s) at %s:%d has count %d (%s), base %d (%s). A "
                       "saved array's count is frozen unless it is a `grows` limit. Fix: mark "
                       "the limit `grows` (spec 6.1) or restore %d"
                       % (key[1], key[2], key[0], c["line"], cv, c["expr"],
                          bv, b["expr"], bv))
    return out, len(tsites), frozen



def selftest():
    tmp = tempfile.mkdtemp(prefix="stored_selftest.")
    n = [0]

    def fam(name, body, cls="stored ordinal u8"):
        return "// family: %s %s\n%s// end family: %s\n" % (name, cls, body, name)

    def tree_of(text):
        n[0] += 1
        d = os.path.join(tmp, "t%d" % n[0])
        os.makedirs(os.path.join(d, "inc"))
        with open(os.path.join(d, "inc", "Defines.h"), "w") as f:
            f.write(text)
        return d

    def go(base_text, tree_text, retired=None):
        base, _ = read_families(tree_of(base_text), False)
        tree, problems = read_families(tree_of(tree_text), True)
        msgs, _n = compare(base, tree, problems, retired or {})
        print("  %s" % (("RED   " + msgs[0][:100]) if msgs else "GREEN"))
        return (1 if msgs else 0), "\n".join(msgs)
    try:
        b = fam("stati", "#define A_X 1\n#define A_Y 2\n")
        assert go(b, b)[0] == 0
        c, m = go(b, fam("stati", "#define A_X 1\n#define A_Y 3\n"))
        assert c == 1 and "A_Y changed: base 2" in m and "tree 3" in m, (c, m)
        c, m = go(b, fam("stati", "#define A_X 1\n"))
        assert c == 1 and "A_Y = 2" in m and "is gone" in m, (c, m)
        assert go(b, fam("stati", "#define A_X 1\n"), {"stati": [("A_Y", 2)]})[0] == 0
        c, m = go(b, fam("stati", "#define A_X 1\n#define A_Y 2\n#define A_Z 2 /* x */\n"))
        assert c == 1 and "tree-only A_Z = 2" in m and "reuses the value of A_Y" in m, (c, m)
        assert go(b, b + fam("stati", "#define A_Z 3\n"))[0] == 0
        c, m = go(b, fam("stati", "#define A_X 1\n#define A_Y 2\n#define A_Z 3\n"),
                  {"stati": [("A_OLD", 3)]})
        assert c == 1 and "A_Z = 3" in m and "retired" in m, (c, m)
        c, m = go(b, fam("stati", "#define A_X 1\n#define A_Y 2\n#define A_Z 256\n"))
        assert c == 1 and "A_Z = 256" in m and "does not fit u8" in m, (c, m)
        c, m = go(b, fam("stati", "#define A_X 1\n#define A_Y 2\n#define A_Z -1\n"))
        assert c == 1 and "does not fit u8" in m, (c, m)
        i8 = "stored ordinal i8"
        assert go(fam("d", "#define D_X -128\n", i8), fam("d", "#define D_X -128\n", i8))[0] == 0
        c, m = go(fam("d", "#define D_X 1\n", i8), fam("d", "#define D_X 1\n#define D_Y 128\n", i8))
        assert c == 1 and "D_Y = 128" in m, (c, m)
        bits = "stored bits u16"
        bb = fam("f", "#define F_A 1\n#define F_B 4\n", bits)
        assert go(bb, bb + fam("f", "#define F_C 2\n", bits))[0] == 0
        c, m = go(bb, bb + fam("f", "#define F_C 0x0C\n", bits))
        assert c == 1 and "tree-only F_C" in m and "F_B" in m, (c, m)
        c, m = go(bb, bb + fam("f", "#define F_C 0x10000\n", bits))
        assert c == 1 and "does not fit u16" in m, (c, m)
        # rule 6: unequal overlapping masks, tree-only names included (F04)
        c, m = go(bb, bb + fam("f", "#define F_N 0x0300\n#define F_M 0x0600\n", bits))
        assert c == 1 and "F_N = 0x300" in m and "F_M = 0x600" in m and "share bits 0x200" in m, (c, m)
        c, m = go(bb, bb + fam("f", "#define F_N 0x0200\n#define F_M 0x0300\n", bits))
        assert c == 1 and "F_M = 0x300" in m and "F_N = 0x200" in m, (c, m)
        assert go(bb, bb + fam("f", "#define F_N 0x0100\n#define F_M 0x0200\n"
                                    "#define F_NM 0x0300\n", bits))[0] == 0  # an aggregate passes
        assert go(bb, bb + fam("f", "#define F_N 0x0100\n#define F_M 0x0100 /* alias */\n",
                               bits))[0] == 0  # equal masks are aliases (check_define_dups)
        # rule 10: a new member of a bits family takes one free bit, or exactly the OR of named bits (F04)
        c, m = go(bb, bb + fam("f", "#define F_N 0x0300\n", bits))
        assert c == 1 and "F_N = 0x300" in m and "one free bit" in m, (c, m)
        c, m = go(bb, bb + fam("f", "#define F_N 0x0600\n", bits))
        assert c == 1 and "F_N = 0x600" in m, (c, m)
        assert go(bb, bb + fam("f", "#define F_N 0x0100\n", bits))[0] == 0
        kb = fam("k", "#define K_A 0x20\n#define K_B 0x40\n#define K_AB 0x60\n", bits)
        assert go(kb, kb)[0] == 0  # an aggregate already on the base passes
        # rule 7: a bound is an exclusive limit; the mark must keep it (F05)
        bd = "stored ordinal u16 bound B_LAST"
        bz = fam("o", "#define B_X 1\n#define B_Y 2\n#define B_LAST 4\n", bd)
        assert go(bz, bz)[0] == 0
        assert go(bz, fam("o", "#define B_X 1\n#define B_Y 2\n#define B_Z 3\n"
                               "#define B_LAST 4\n", bd))[0] == 0
        c, m = go(bz, fam("o", "#define B_X 1\n#define B_Y 2\n#define B_Z 4\n"
                               "#define B_LAST 4\n", bd))
        assert c == 1 and "B_Z = 4" in m and "not below the bound B_LAST = 4" in m, (c, m)
        c, m = go(bz, fam("o", "#define B_X 1\n#define B_Y 2\n#define B_Z 5\n"
                               "#define B_LAST 4\n", bd))
        assert c == 1 and "B_Z = 5" in m, (c, m)
        c, m = go(bz, fam("o", "#define B_X 1\n#define B_Y 2\n#define B_LAST 4\n"))
        assert c == 1 and "drops it" in m and "bound B_LAST" in m, (c, m)
        # rule 9: a `grows` limit may rise, never fall; its old value is free (spec 6.1)
        gw = "stored ordinal u8 grows G_LAST"
        gb = fam("g", "#define G_X 1\n#define G_LAST 2\n", gw)
        assert go(gb, gb)[0] == 0
        assert go(gb, fam("g", "#define G_X 1\n#define G_NEW 2\n#define G_LAST 3\n", gw))[0] == 0
        c, m = go(gb, fam("g", "#define G_X 1\n#define G_NEW 2\n#define G_LAST 3\n",
                          "stored ordinal u8"))
        assert c == 1 and "G_LAST changed" in m and "drops it" in m, (c, m)
        c, m = go(gb, fam("g", "#define G_X 1\n#define G_LAST 1\n", gw))
        assert c == 1 and "G_LAST shrank: base 2" in m and "tree 1" in m, (c, m)
        c, m = go(gb, fam("g", "#define G_X 1\n#define G_LAST 2\n", "stored ordinal u8"))
        assert c == 1 and "drops it" in m, (c, m)
        c, m = go(gb, fam("g", "#define G_X 1\n#define G_NEW 3\n#define G_LAST 3\n", gw)
                  .replace("G_NEW 3", "G_NEW 1"))
        assert c == 1 and "tree-only G_NEW = 1" in m, (c, m)  # a stored value still collides
        # a frozen value of a family with a `grows` limit: a branch that raises it is refused
        sk = "stored ordinal i16 grows SK_HIGH_END"
        hf = fam("sk_high_first", "#define SK_HIGH_FIRST 800\n", "stored ordinal i16 sentinel SK_HIGH_FIRST")
        sb = fam("sk", "#define SK_X 1\n#define SK_LASTSKILL 49\n#define SK_HIGH_END 800\n", sk) + hf
        assert go(sb, sb)[0] == 0
        c, m = go(sb, fam("sk", "#define SK_X 1\n#define SK_LASTSKILL 50\n#define SK_HIGH_END 800\n", sk) + hf)
        assert c == 1 and "SK_LASTSKILL changed: base 49" in m and "tree 50" in m, (c, m)
        assert go(sb, fam("sk", "#define SK_X 1\n#define SK_LASTSKILL 49\n#define SK_NEW 800\n"
                                "#define SK_HIGH_END 801\n", sk) + hf)[0] == 0
        # rule 10: a new skill takes a number from SK_HIGH_FIRST to SK_HIGH_END-1, at most 999 (N08)
        def sktree(new, end):
            return fam("sk", "#define SK_X 1\n#define SK_LASTSKILL 49\n%s#define SK_HIGH_END %d\n"
                       % (new, end), sk) + hf
        c, m = go(sb, sktree("#define SK_OUT 801\n", 801))
        assert c == 1 and "SK_OUT = 801" in m and "outside" in m and "SK_HIGH_END" in m, (c, m)
        c, m = go(sb, sktree("#define SK_OUT 800\n", 800))
        assert c == 1 and "SK_OUT = 800" in m and "outside" in m, (c, m)
        c, m = go(sb, sktree("#define SK_OUT 5\n", 800))
        assert c == 1 and "SK_OUT = 5" in m and "outside" in m, (c, m)
        c, m = go(sb, sktree("".join("#define SK_N%d %d\n" % (i, 800 + i) for i in range(201)), 1001))
        assert c == 1 and "SK_N200 = 1000" in m and "999" in m, (c, m)
        assert go(sb, sktree("#define SK_A 800\n#define SK_B 801\n", 802))[0] == 0
        c, m = go(sb.replace("SK_HIGH_END 800", "SK_HI 800"), sb.replace("SK_HIGH_END 800", "SK_HI 800"))
        assert c == 1 and "SK_HIGH_END" in m and "cannot" in m, (c, m)
        # rule 11: a new feat stays below 800 (the skills' numbers) and shares no value with a skill (N09)
        ftm = "stored ordinal u16 grows FT_LAST"
        fb = fam("ft", "#define FT_X 1\n#define FT_LAST 364\n", ftm)

        def fttree(new, last):
            return fam("ft", "#define FT_X 1\n%s#define FT_LAST %d\n" % (new, last), ftm)
        assert go(sb + fb, sb + fb)[0] == 0
        assert go(sb + fb, sb + fttree("#define FT_NEW 799\n", 800))[0] == 0
        c, m = go(sb + fb, sb + fttree("#define FT_NEW 800\n", 801))
        assert c == 1 and "FT_NEW = 800" in m and "shared feat/skill space" in m, (c, m)
        c, m = go(sb + fb, sktree("#define SK_NEW 800\n", 801) + fttree("#define FT_NEW 800\n", 801))
        assert c == 1 and "FT_NEW = 800" in m and "SK_NEW" in m and "shared feat/skill space" in m, (c, m)
        c, m = go(sb + fb, sb + fttree("#define FT_NEW 49\n", 364))  # a skill's low number
        assert c == 1 and "FT_NEW = 49" in m and "shared feat/skill space" in m and "SK_LASTSKILL" in m, (c, m)
        # the base held the limit in a no-family block: its value comes from the compiler
        nf = "// no-family\n#define MAX_G 25\n// end no-family\n"
        bt, _ = read_families(tree_of(nf), False)

        def go_gb(tree_text, gbase):
            tree, problems = read_families(tree_of(tree_text), True)
            for d in tree.values():
                d["grows_base"] = dict(gbase)
            msgs, _n = compare(bt, tree, problems, {})
            print("  %s" % (("RED   " + msgs[0][:100]) if msgs else "GREEN"))
            return (1 if msgs else 0), "\n".join(msgs)
        lw = "stored ordinal u16 grows MAX_G"
        assert go_gb(fam("lim", "#define MAX_G 25\n", lw), {"MAX_G": 25})[0] == 0
        assert go_gb(fam("lim", "#define MAX_G 30\n", lw), {"MAX_G": 25})[0] == 0
        c, m = go_gb(fam("lim", "#define MAX_G 20\n", lw), {"MAX_G": 25})
        assert c == 1 and "MAX_G shrank: base 25, tree 20" in m, (c, m)
        eb = fam("e", "enum { E_A, E_B, E_C };\n", "stored enum i32")
        assert go(eb, eb)[0] == 0
        c, m = go(eb, fam("e", "enum { E_A, E_NEW, E_B, E_C };\n", "stored enum i32"))
        assert c == 1 and "E_B changed: base 1" in m and "E_C changed" in m, (c, m)
        c, m = go(eb, fam("e", "enum { E_A, E_B, E_C, E_D = 1 };\n", "stored enum i32"))
        assert c == 1 and "tree-only E_D = 1" in m, (c, m)
        # a stored-array sentinel is an ordinary stored value; a marked one is exempt
        arr = "#define ATTR_X 1\n#define ATTR_LAST 2\n"
        c, m = go(fam("attr", arr), fam("attr", "#define ATTR_X 1\n#define ATTR_NEW 2\n"
                                                 "#define ATTR_LAST 3\n"))
        assert c == 1 and "ATTR_LAST changed" in m and "tree-only ATTR_NEW" in m, (c, m)
        sc = "stored ordinal u8 sentinel T_LAST"
        c, m = go(fam("t", "#define T_X 1\n#define T_LAST 2\n", sc),
                  fam("t", "#define T_X 1\n#define T_Y 2\n#define T_LAST 3\n", sc))
        assert c == 0, (c, m)
        # a name moved to an internal family keeps its value: not gone; changed: red
        mv = fam("t", "#define T_X 1\n", "stored ordinal u8") + fam("t_all", "#define T_NEG -3\n", "internal")
        unclassified = "// family: t\n#define T_X 1\n#define T_NEG -3\n// end family: t\n"
        assert go(unclassified, mv)[0] == 0
        c, m = go(unclassified, mv.replace("-3", "-4"))
        assert c == 1 and "T_NEG changed" in m, (c, m)
        # classified base: a stored name moved to an internal family is red
        c, m = go(fam("t", "#define T_X 1\n#define T_NEG 3\n"), mv.replace("-3", "3"))
        assert c == 1 and "T_NEG = 3" in m and "gone from the tree" in m, (c, m)
        # classified base: the whole family reclassified internal is red
        c, m = go(b, fam("stati", "#define A_X 1\n#define A_Y 2\n", "internal"))
        assert c == 1 and "A_X" in m and "A_Y" in m and "stored on the base" in m, (c, m)
        assert go(b, fam("stati", "#define A_X 1\n#define A_Y 2\n", "internal"),
                  {"stati": [("A_X", 1), ("A_Y", 2)]})[0] == 0
        # an unclassified family in the tree
        c, m = go(b, "// family: stati\n#define A_X 1\n#define A_Y 2\n// end family: stati\n")
        assert c == 1 and "has no class" in m, (c, m)
        # a base family with no class at all is read for membership
        c, m = go("// family: stati\n#define A_X 1\n#define A_Y 2\n// end family: stati\n",
                  fam("stati", "#define A_X 1\n#define A_Y 9\n"))
        assert c == 1 and "A_Y changed" in m, (c, m)
        # an internal family is not compared
        assert go(fam("i", "#define I_X 1\n", "internal"),
                  fam("i", "#define I_X 2\n", "internal"))[0] == 0
        # retired_values rows
        rf = os.path.join(tmp, "retired.txt")
        with open(rf, "w") as f:
            f.write("# header\nstati A_OLD 7  # why\n")
        assert read_retired(rf) == {"stati": [("A_OLD", 7)]}
        with open(rf, "w") as f:
            f.write("stati A_OLD\n")
        try:
            read_retired(rf)
            raise AssertionError("a short row must be refused")
        except Unmeasured:
            pass
        # the git path: base read with `git archive`, tree is another directory
        repo = os.path.join(tmp, "repo")
        os.makedirs(os.path.join(repo, "inc"))
        with open(os.path.join(repo, "inc", "Defines.h"), "w") as f:
            f.write(b)
        g = ["git", "-C", repo, "-c", "user.name=t", "-c", "user.email=t@t"]
        subprocess.run(g + ["init", "-q", "-b", "master"], check=True)
        subprocess.run(g + ["add", "-A"], check=True)
        subprocess.run(g + ["commit", "-q", "-m", "base"], check=True)
        # rule 8: the legacy table is frozen against the base (F09)
        os.makedirs(os.path.join(repo, "inc"), exist_ok=True)
        lt = os.path.join(repo, LEGACY_TABLE)
        assert legacy_table_problem("master", repo) is None  # base has no table yet
        with open(lt, "w") as f:
            f.write('{ "Character", 411, "alignGE", 3, 6 },\n{ "Character", 412, "alignLC", 3, 6 },\n')
        subprocess.run(g + ["add", "-A"], check=True)
        subprocess.run(g + ["commit", "-q", "-m", "table"], check=True)
        assert legacy_table_problem("master", repo) is None  # tree == base
        with open(lt, "w") as f:
            f.write('{ "Character", 411, "alignLC", 3, 6 },\n{ "Character", 412, "alignGE", 3, 6 },\n')
        p = legacy_table_problem("master", repo)
        print("  %s" % ("RED   " + p[:100] if p else "GREEN"))
        assert p and "already written" in p and LEGACY_TABLE in p, p
        os.remove(lt)
        p = legacy_table_problem("master", repo)
        assert p and "is gone" in p, p
        subprocess.run(g + ["checkout", "-q", "--", LEGACY_TABLE], check=True)
        dest = os.path.join(tmp, "got")
        os.makedirs(dest)
        global ROOT
        keep, ROOT = ROOT, repo
        try:
            extract_base("master", dest)
            fams, _ = read_families(dest, False)
            assert sorted(m[0] for m in fams["stati"]["members"]) == ["A_X", "A_Y"], fams
            try:
                extract_base("no-such-ref", dest)
                raise AssertionError("a missing ref must be unmeasured")
            except Unmeasured:
                pass
        finally:
            ROOT = keep
        # rule 12: a saved array's count is a `grows` limit, or frozen against the base (gap 8)
        def arrays(base_defs, base_arr, tree_defs, tree_arr):
            def root(defs, arr):
                d = tree_of(defs)
                with open(os.path.join(d, "inc", "Arr.h"), "w") as f:
                    f.write(arr)
                return d
            br, tr = root(base_defs, base_arr), root(tree_defs, tree_arr)
            tfams, _ = read_families(tr, False)
            names = {g for d in tfams.values() if d["class"] == "stored" for g in d["grows"]}
            msgs, _n, _f = array_problems(read_array_sites(br), read_array_sites(tr), names)
            print("  %s" % (("RED   " + msgs[0][:100]) if msgs else "GREEN"))
            return "\n".join(msgs)
        lim = lambda v: fam("lim", "#define G_MAX %d\n" % v, "stored ordinal u16 grows G_MAX")
        nof = lambda v: "// no-family\n#define N_ROWS %d\n// end no-family\n" % v
        arr = lambda cnt: "void F() { FIELD_ARRAY(7, Rows, sizeof(int), %s); }\n" % cnt
        m = arrays(lim(8), arr(7), lim(8), arr(6))
        assert "Rows" in m and "count 6" in m and "base 7" in m and "`grows`" in m, m
        m = arrays(lim(8) + nof(8), arr("N_ROWS"), lim(8) + nof(9), arr("N_ROWS"))
        assert "Rows" in m and "count 9" in m and "base 8" in m, m
        assert arrays(lim(8), arr("G_MAX"), lim(9), arr("G_MAX")) == ""      # a grows limit rises
        assert arrays(lim(8), arr("G_MAX+1"), lim(9), arr("G_MAX+1")) == ""
        assert arrays(lim(8) + nof(8), arr("N_ROWS"), lim(8) + nof(8), arr("N_ROWS")) == ""
        assert arrays(lim(8), "", lim(8), arr(5)) == ""                       # a new literal site
        rows = lambda a, b: ("void F() { FIELD_ARRAY_ROWS(8, Tab, sizeof(int), %s, %s, TabRow, 0); }\n"
                             % (a, b))
        m = arrays(lim(8), rows(3, "G_MAX"), lim(9), rows(4, "G_MAX"))
        assert "Tab" in m and "rows" in m and "count 4" in m and "base 3" in m, m
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print("check_stored_values: selftest PASS (text values only; the compiler is skipped)")
    return 0


def main(argv):
    ref, st = "master", False
    it = iter(argv)
    for a in it:
        if a == "--base":
            ref = next(it, None)
            if ref is None:
                print("--base needs a ref", file=sys.stderr)
                return 2
        elif a == "--selftest":
            st = True
        else:
            print(__doc__.split("Usage:")[1].split("Exit:")[0], file=sys.stderr)
            return 2
    return selftest() if st else run(ref)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
