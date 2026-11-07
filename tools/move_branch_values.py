#!/usr/bin/env python3
# gate: cheap
# gate-fast: static plus read-only git; the selftest builds temporary git repos, about 3 s
"""Move the colliding stored values of this branch to free ones.

WHY THIS EXISTS. A save, Options.Dat or another file on disk holds the VALUE of
a stored #define or enumerator. When this branch adds a name whose value a
master name already holds (or a retired value held), tools/check_stored_values.py
rule 3 fails. Master's number stays; the branch's own name moves. Nobody edits
that number by hand. Spec docs/superpowers/specs/2026-11-07-names-in-the-file-
design.md section 6 and AC5 (bead inc-cjos0, phase 5c).

WHAT IT DOES. It reads the base ref (--base, default master) and the working
tree the way check_stored_values.py does, and takes every rule-3 collision (a
tree-only name whose value a base name or a retired value holds in the same
stored family). It rewrites the tree-only name's value in its source line by
the shape of the family:
  ordinal  the next value after the maximum of the merged family (base names,
           tree names, retired values; sentinel names left out). When the mark
           names `bound <NAME>` (the value that sizes the array the family
           indexes, OPT_LAST), the new value MUST be below the bound: the next
           value when it is below, else the highest free value below the bound,
           else REFUSED naming the family. The bound itself never moves.
  bits     the lowest free bit of the storage width, free of every base, tree
           and retired value. No free bit: REFUSED, the word is full.
  enum     the enumerator's line moves to the end of its enum (before the
           sentinel names that end it) with an explicit `= <value>` chosen as
           for ordinal (a `bound` binds here too), so no base enumerator shifts. An enumerator that
           followed it gets an explicit value only when the move would change
           its value; each is reported.
Then, in each family that moved a name, every `sentinel <NAME>` of the mark is
rewritten to max+1 of the merged family (ordinal and enum families; a bits
sentinel has no meaning and is left). Two moved names never take one value. A
new value that does not fit the storage width is REFUSED naming bead inc-xm3nq.
A value written as an expression (`FT_FIRST + 3`) is rewritten to the literal;
the report line says so. It changes no base name, no base value, and no line
outside the moved names and the sentinels (and the enum followers above).
Afterwards it runs check_stored_values again and exits 1 if that still fails.

ON MASTER (the current branch is the base ref, or HEAD is the base commit) it
prints "no-op on master" and changes nothing.

Output: one line per move, `family NAME old -> new file:line`, then
`move_branch_values: moved N value(s)`. tools/finish_bead.sh reads that last line.

Usage: tools/move_branch_values.py [--base REF] [--dry-run] [--selftest]
Exit:  0 done (or nothing to do)   1 refused, or the check still fails   2 unmeasured

# fact: the base tree -- a git ref read with `git archive`; default master, re-read on every run
# fact: define and enumerator values -- the compiler at the posix flags (check_stored_values.py); no game run, no seed
# fact: family, class, shape, width -- the marks in inc/ and src/ of each tree; no randomness
# fact: retired values -- tools/retired_values.txt, a tracked file
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_define_dups as cdd  # noqa: E402
import check_stored_values as csv  # noqa: E402

ROOT = cdd.ROOT
LITERAL = re.compile(r"-?(0[xX][0-9a-fA-F]+|\d+)[uUlL]*")
ENUM_LINE = re.compile(r"^(\s*)([A-Za-z_]\w*)(?:\s*=\s*(.*?))?\s*(,?)\s*$")


class Refused(Exception):
    pass


def where_of(m):
    return "%s:%d" % (m[2], m[3])


# ---------------------------------------------------------------- planning

def plan(base, tree, retired):
    """Return a list of moves. A move is a dict: fam, name, old, new, file, line,
    shape, sentinel (bool). Raises Refused."""
    moves = []
    for fam in sorted(tree):
        t = tree[fam]
        if t["class"] != "stored":
            continue
        ret = dict(retired.get(fam, []))
        hits = csv.family_collisions(t, base.get(fam, {}), ret)
        if not hits:
            continue
        shape, width = t["shape"], t["width"]
        sent = set(t["sentinels"])
        tvals = {}
        for m in t["members"]:
            tvals.setdefault(m[0], m)
        names = {}
        for name, m, _hn, _hv, _why in hits:
            names[name] = m
        order = sorted(names, key=lambda n: (names[n][2], names[n][3]))
        merged = [m[1] for m in base.get(fam, {}).get("members", []) if m[0] not in sent]
        merged += [m[1] for n, m in tvals.items() if n not in sent]
        merged += list(ret.values())
        if shape == "bits":
            held = 0
            for v in merged:
                held |= csv.pattern(v, width)
            for name in order:
                free = [k for k in range(csv.BITS[width]) if not (held >> k) & 1]
                if not free:
                    raise Refused("family %s: the %s word is full, no free bit for %s "
                                  "(bead inc-xm3nq)" % (fam, width, name))
                new = 1 << free[0]
                held |= new
                moves.append(dict(fam=fam, name=name, old=names[name][1], new=new,
                                  file=names[name][2], line=names[name][3],
                                  shape=shape, sentinel=False))
            continue
        bounds = [tvals[b][1] for b in t.get("bounds", []) if b in tvals]
        lim = min(bounds) if bounds else None
        below = [v for v in merged if lim is None or v < lim]
        taken = set(merged)
        mx = max(below, default=-1)
        for name in order:
            new = mx + 1
            if lim is not None and new >= lim:
                free = [v for v in range(lim - 1, min(below, default=0) - 1, -1)
                        if v not in taken]
                if not free:
                    raise Refused("family %s: no free value below the bound %s = %d for %s "
                                  "(bead inc-xm3nq)" % (fam, ",".join(t["bounds"]), lim, name))
                new = free[0]
            else:
                mx = new
            if not csv.fits(new, shape, width):
                raise Refused("family %s: %s would take %d, which does not fit %s "
                              "(bead inc-xm3nq)" % (fam, name, new, width))
            taken.add(new)
            moves.append(dict(fam=fam, name=name, old=names[name][1], new=new,
                              file=names[name][2], line=names[name][3],
                              shape=shape, sentinel=False))
        for s in t["sentinels"]:
            m = tvals.get(s)
            if m is not None and m[1] != mx + 1:
                moves.append(dict(fam=fam, name=s, old=m[1], new=mx + 1, file=m[2],
                                  line=m[3], shape=shape, sentinel=True))
    return moves


# ---------------------------------------------------------------- editing

def split_comment(line):
    """Return (code, gap, comment) of a line without its newline."""
    idx = [i for i in (line.find("//"), line.find("/*")) if i >= 0]
    cut = min(idx) if idx else len(line)
    code = line[:cut].rstrip()
    return code, line[len(code):cut], line[cut:]


def edit_define(lines, mv):
    """Rewrite the value of a #define in lines (a list, edited in place).
    Return the old expression text when it was not a plain literal, else None."""
    ln = lines[mv["line"] - 1]
    eol = "\r" if ln.endswith("\r") else ""
    core = ln[:-1] if eol else ln
    m = re.match(r"^(\s*#\s*define\s+%s\s+)(.*)$" % re.escape(mv["name"]), core)
    if not m:
        raise Refused("%s:%d: %s is not a plain `#define %s <value>` line"
                      % (mv["file"], mv["line"], mv["name"], mv["name"]))
    if core.rstrip().endswith("\\"):
        raise Refused("%s:%d: %s continues on the next line; edit it by hand"
                      % (mv["file"], mv["line"], mv["name"]))
    code, gap, comment = split_comment(m.group(2))
    body = code.strip()
    fmt = "0x%X" if mv["shape"] == "bits" else "%d"
    lines[mv["line"] - 1] = m.group(1) + (fmt % mv["new"]) + gap + comment + eol
    return None if LITERAL.fullmatch(body) else body


def parse_enum_line(text, no, name, path):
    eol = "\r" if text.endswith("\r") else ""
    core = text[:-1] if eol else text
    code, gap, comment = split_comment(core)
    m = ENUM_LINE.match(code)
    if not m or m.group(2) != name:
        raise Refused("%s:%d: the enumerator %s does not sit alone on its line; edit "
                      "the enum by hand" % (path, no, name))
    return dict(indent=m.group(1), name=name, expr=m.group(3), comma=bool(m.group(4)),
                gap=gap, comment=comment, eol=eol)


def build_enum_line(p):
    return (p["indent"] + p["name"] + (" = %s" % p["expr"] if p["expr"] is not None else "")
            + ("," if p["comma"] else "") + p["gap"] + p["comment"] + p["eol"])


def edit_enum(text, path, name, newv, vals, mode, sent_want):
    """Edit the enum that holds name. mode 'move': take the line to the end of the
    enum (before trailing sentinel names) with `= newv`. mode 'set': give name the
    value newv in place. vals: {enumerator: value}, updated. sent_want: {sentinel
    name: wanted value}. Return (new text, [(follower, value)])."""
    if mode == "set" and vals.get(name) == newv:
        return text, []
    lines = text.split("\n")
    hit = None
    for _first, _last, members in cdd.find_enums(cdd.strip_comments(text)):
        if any(m[1] == name for m in members):
            hit = members
            break
    if hit is None:
        raise Refused("%s: cannot find the enum that holds %s" % (path, name))
    if len({m[0] for m in hit}) != len(hit):
        raise Refused("%s: two enumerators of the enum holding %s share a line; edit it "
                      "by hand" % (path, name))
    line_of = {m[1]: m[0] for m in hit}
    parsed = {m[1]: parse_enum_line(lines[m[0] - 1], m[0], m[1], path) for m in hit}
    order = [m[1] for m in hit]
    last_comma = parsed[order[-1]]["comma"]
    new_order = list(order)
    anchor, after = None, True
    if mode == "move":
        new_order.remove(name)
        pos = len(new_order)
        while pos > 0 and new_order[pos - 1] in sent_want:
            pos -= 1
        if pos > 0:
            anchor = line_of[new_order[pos - 1]]
        elif new_order:
            anchor, after = line_of[new_order[0]], False
        new_order.insert(pos, name)
    followers = []
    prev = -1
    for i, nm in enumerate(new_order):
        p = parsed[nm]
        if nm == name:
            want = newv
            p["expr"] = str(newv) if (mode == "move" or p["expr"] is not None
                                      or prev + 1 != newv) else None
        elif nm in sent_want:
            want = sent_want[nm]
            cur = prev + 1 if p["expr"] is None else vals[nm]
            if cur != want:
                p["expr"] = str(want)
        else:
            want = vals[nm]
            if p["expr"] is None and prev + 1 != want:
                p["expr"] = str(want)
                followers.append((nm, want))
        p["comma"] = (i < len(new_order) - 1) or last_comma
        prev = want
        vals[nm] = want
    for nm in order:
        lines[line_of[nm] - 1] = build_enum_line(parsed[nm])
    if mode == "move" and anchor is not None:
        moved = lines[line_of[name] - 1]
        del lines[line_of[name] - 1]
        ai = anchor - 1 - (1 if anchor > line_of[name] else 0)
        lines.insert(ai + 1 if after else ai, moved)
    return "\n".join(lines), followers


def locate(text, name, shape):
    pat = (r"^\s*%s\b" % re.escape(name) if shape == "enum"
           else r"^\s*#\s*define\s+%s\b" % re.escape(name))
    for no, ln in enumerate(text.split("\n"), 1):
        if re.match(pat, ln):
            return no
    return 0


def apply_moves(root, moves, vals):
    """Edit the files in memory, write them all only when every edit worked.
    Return the report lines."""
    texts = {}

    def get(path):
        if path not in texts:
            with open(os.path.join(root, path), encoding="latin-1", newline="") as f:
                texts[path] = f.read()
        return texts[path]
    report, notes = [], {}
    by_fam = {}
    for mv in moves:
        by_fam.setdefault(mv["fam"], []).append(mv)
    for fam, ms in sorted(by_fam.items()):
        sent_want = {m["name"]: m["new"] for m in ms if m["sentinel"]}
        for mv in sorted(ms, key=lambda m: (m["sentinel"], m["file"], m["line"])):
            text = get(mv["file"])
            if mv["shape"] == "enum":
                mode = "set" if mv["sentinel"] else "move"
                text, fol = edit_enum(text, mv["file"], mv["name"], mv["new"], vals, mode,
                                      sent_want)
                texts[mv["file"]] = text
                for nm, v in fol:
                    notes[(fam, nm)] = (v, mv["file"])
            else:
                lines = text.split("\n")
                expr = edit_define(lines, mv)
                texts[mv["file"]] = "\n".join(lines)
                vals[mv["name"]] = mv["new"]
                if expr:
                    notes[(fam, mv["name"])] = expr
    for path, text in texts.items():
        with open(os.path.join(root, path), "w", encoding="latin-1", newline="") as f:
            f.write(text)
    for mv in sorted(moves, key=lambda m: (m["fam"], m["file"], m["line"])):
        line = locate(texts[mv["file"]], mv["name"], mv["shape"])
        s = "%s %s %d -> %d %s:%d" % (mv["fam"], mv["name"], mv["old"], mv["new"],
                                      mv["file"], line)
        n = notes.get((mv["fam"], mv["name"]))
        if isinstance(n, str):
            s += "  [the expression `%s` is now a literal]" % n
        if mv["sentinel"]:
            s += "  [sentinel]"
        report.append(s)
    for (fam, nm), val in sorted(notes.items(), key=lambda kv: str(kv[0])):
        if isinstance(val, tuple):
            file = val[1]
            report.append("%s %s %d -> %d %s:%d  [explicit value, because a move shifted it]"
                          % (fam, nm, val[0], val[0], file, locate(texts[file], nm, "enum")))
    return report


# ---------------------------------------------------------------- the run

def git(root, *args):
    r = subprocess.run(["git", "-C", root] + list(args), capture_output=True, text=True)
    if r.returncode != 0:
        raise csv.Unmeasured("git %s: %s" % (" ".join(args), r.stderr.strip()))
    return r.stdout.strip()


def run_move(root, ref, dry, use_compiler=True, out=print):
    branch = git(root, "rev-parse", "--abbrev-ref", "HEAD")
    head = git(root, "rev-parse", "HEAD")
    base_commit = git(root, "rev-parse", "--verify", ref + "^{commit}")
    if branch == ref or head == base_commit:
        out("move_branch_values: no-op on %s" % ref)
        return 0
    base, tree, problems, retired, _kept = csv.measure(ref, root, use_compiler)
    moves = plan(base, tree, retired)
    vals = {m[0]: m[1] for d in tree.values() for m in d["members"]}
    if dry:
        for mv in sorted(moves, key=lambda m: (m["fam"], m["file"], m["line"])):
            out("%s %s %d -> %d %s:%d%s" % (mv["fam"], mv["name"], mv["old"], mv["new"],
                                            mv["file"], mv["line"],
                                            "  [sentinel]" if mv["sentinel"] else ""))
        out("move_branch_values: dry run, would move %d value(s)" % len(moves))
        return 0
    for line in apply_moves(root, moves, vals):
        out(line)
    out("move_branch_values: moved %d value(s)" % len(moves))
    if not moves:
        return 0
    base, tree, problems, retired, _kept = csv.measure(ref, root, use_compiler)
    msgs, _n = csv.compare(base, tree, problems, retired)
    if msgs:
        out("move_branch_values: check_stored_values still fails after the moves:")
        for m in msgs:
            out("  " + m)
        return 1
    return 0


# ---------------------------------------------------------------- selftest

def selftest():
    tmp = tempfile.mkdtemp(prefix="move_selftest.")

    def fam(name, body, cls="stored ordinal u8"):
        return "// family: %s %s\n%s// end family: %s\n" % (name, cls, body, name)

    def g(d, *args):
        subprocess.run(["git", "-C", d, "-c", "user.name=t", "-c", "user.email=t@t",
                        "-c", "core.hooksPath=/dev/null"] + list(args),
                       check=True, capture_output=True)

    def mkrepo(base, tree, retired=""):
        d = tempfile.mkdtemp(dir=tmp)
        os.makedirs(os.path.join(d, "inc"))
        os.makedirs(os.path.join(d, "tools"))
        defs, ret = os.path.join(d, "inc", "Defines.h"), os.path.join(d, "tools",
                                                                      "retired_values.txt")
        with open(defs, "w") as f:
            f.write(base)
        with open(ret, "w") as f:
            f.write(retired)
        g(d, "init", "-q", "-b", "master")
        g(d, "add", "-A")
        g(d, "commit", "-q", "-m", "base")
        g(d, "checkout", "-q", "-b", "feat")
        with open(defs, "w") as f:
            f.write(tree)
        g(d, "commit", "-qam", "tree")
        return d, defs

    def read(p):
        with open(p) as f:
            return f.read()

    def check(d, ref="master"):
        base, tree, problems, retired, _k = csv.measure(ref, d, False)
        return csv.compare(base, tree, problems, retired)[0]

    def case(label, base, tree, retired="", want=None, code=0, grep=(), dry=False):
        print("case: " + label)
        d, defs = mkrepo(base, tree, retired)
        before = check(d)
        assert before, "case must start RED"
        print("  RED   " + before[0][:110])
        out = []
        try:
            c = run_move(d, "master", dry, False, out.append)
        except Refused as e:
            c = 1
            out.append("REFUSED: %s" % e)
        text = "\n".join(out)
        assert c == code, (label, c, text)
        for s in grep:
            assert s in text, (label, s, text)
        if code == 0 and not dry:
            assert check(d) == [], (label, check(d))
            print("  GREEN " + out[0])
        elif code == 0:
            assert read(defs) == tree, label
            print("  GREEN dry run wrote nothing: " + out[0])
        else:
            assert read(defs) == tree, label
            print("  GREEN refused, file untouched: " + out[0][:100])
        if want is not None:
            assert read(defs) == want, (label, read(defs))
        return d

    try:
        b = fam("stati", "#define A_X 1\n#define A_Y 2\n")
        case("ordinal collision cleared, base untouched", b,
             fam("stati", "#define A_X 1\n#define A_Y 2\n#define A_Z 2 /* x */\n"),
             want=fam("stati", "#define A_X 1\n#define A_Y 2\n#define A_Z 3 /* x */\n"),
             grep=["stati A_Z 2 -> 3 inc/Defines.h:4"])
        bits = "stored bits u16"
        case("bit collision cleared, expression becomes a literal",
             fam("f", "#define F_A 1\n#define F_B 4\n", bits),
             fam("f", "#define F_A 1\n#define F_B 4\n#define F_C (1 << 2)\n", bits),
             want=fam("f", "#define F_A 1\n#define F_B 4\n#define F_C 0x2\n", bits),
             grep=["f F_C 4 -> 2", "(1 << 2)"])
        en = "stored enum i32"
        eb = fam("e", "enum {\n    E_A,\n    E_B,\n    E_C\n};\n", en)
        case("enum collision cleared, follower made explicit, base values kept", eb,
             fam("e", "enum {\n    E_A,\n    E_B,\n    E_C,\n    E_D = 8,    // new\n"
                      "    E_F\n};\n", en),
             retired="e E_R 8\n",
             want=fam("e", "enum {\n    E_A,\n    E_B,\n    E_C,\n    E_F = 9,\n"
                           "    E_D = 10    // new\n};\n", en),
             grep=["e E_D 8 -> 10", "e E_F 9 -> 9", "explicit value"])
        es = "stored enum i32 sentinel E_LAST"
        case("enum collision stops before the sentinel, sentinel at max+1",
             fam("e", "enum {\n    E_A,\n    E_B,\n    E_C,\n    E_LAST\n};\n", es),
             fam("e", "enum {\n    E_A,\n    E_B,\n    E_C,\n    E_D = 1,\n    E_LAST\n};\n",
                 es),
             want=fam("e", "enum {\n    E_A,\n    E_B,\n    E_C,\n    E_D = 3,\n"
                           "    E_LAST\n};\n", es),
             grep=["e E_D 1 -> 3"])
        full = "".join("#define F_%d 0x%X\n" % (k, 1 << k) for k in range(8))
        case("a full bit word refuses",
             fam("f", full, "stored bits u8"),
             fam("f", full + "#define F_N 0x80\n", "stored bits u8"),
             code=1, grep=["word is full", "family f"])
        case("a value past the storage width refuses and names inc-xm3nq",
             fam("a", "#define A_X 255\n"), fam("a", "#define A_X 255\n#define A_Z 255\n"),
             code=1, grep=["family a", "inc-xm3nq"])
        ss = "stored ordinal u8 sentinel T_LAST"
        case("the sentinel is rewritten to max+1",
             fam("t", "#define T_X 1\n#define T_Y 2\n#define T_LAST 3\n", ss),
             fam("t", "#define T_X 1\n#define T_Y 2\n#define T_Z 2\n#define T_LAST 3\n", ss),
             want=fam("t", "#define T_X 1\n#define T_Y 2\n#define T_Z 3\n#define T_LAST 4\n",
                      ss),
             grep=["t T_LAST 3 -> 4", "[sentinel]"])
        case("two colliding tree names get two distinct values", b,
             fam("stati", "#define A_X 1\n#define A_Y 2\n#define A_Z 2\n#define A_W 2\n"),
             want=fam("stati", "#define A_X 1\n#define A_Y 2\n#define A_Z 3\n"
                               "#define A_W 4\n"))
        case("a retired value is not reused", fam("stati", "#define A_X 1\n"),
             fam("stati", "#define A_X 1\n#define A_Z 1\n"), retired="stati A_OLD 2\n",
             want=fam("stati", "#define A_X 1\n#define A_Z 3\n"))
        case("--dry-run writes nothing", b,
             fam("stati", "#define A_X 1\n#define A_Y 2\n#define A_Z 2\n"), dry=True,
             grep=["stati A_Z 2 -> 3", "would move 1"])
        bd = "stored ordinal u16 bound O_LAST"
        case("a bound: the next value is taken while it is below the bound",
             fam("o", "#define O_X 1\n#define O_Y 3\n#define O_LAST 5\n", bd),
             fam("o", "#define O_X 1\n#define O_Y 3\n#define O_Z 3\n#define O_LAST 5\n", bd),
             want=fam("o", "#define O_X 1\n#define O_Y 3\n#define O_Z 4\n#define O_LAST 5\n",
                      bd))
        case("a bound: no value at or above it, the highest free one below it",
             fam("o", "#define O_X 1\n#define O_Y 4\n#define O_LAST 5\n", bd),
             fam("o", "#define O_X 1\n#define O_Y 4\n#define O_Z 4\n#define O_LAST 5\n", bd),
             want=fam("o", "#define O_X 1\n#define O_Y 4\n#define O_Z 3\n#define O_LAST 5\n",
                      bd),
             grep=["o O_Z 4 -> 3"])
        case("a bound with no free value below it refuses naming the family",
             fam("o", "#define O_X 1\n#define O_Y 2\n#define O_LAST 3\n", bd),
             fam("o", "#define O_X 1\n#define O_Y 2\n#define O_Z 2\n#define O_LAST 3\n", bd),
             code=1, grep=["family o", "no free value below the bound O_LAST = 3"])
        print("case: no-op on master")
        d, defs = mkrepo(b, fam("stati", "#define A_X 1\n#define A_Y 2\n#define A_Z 2\n"))
        g(d, "checkout", "-q", "master")
        with open(defs, "w") as f:
            f.write(fam("stati", "#define A_X 1\n#define A_Y 2\n#define A_Z 2\n"))
        before = read(defs)
        out = []
        assert run_move(d, "master", False, False, out.append) == 0 and "no-op on master" in out[0]
        assert read(defs) == before
        print("  GREEN " + out[0])
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print("move_branch_values: selftest PASS")
    return 0


def main(argv):
    ref, dry, st = "master", False, False
    it = iter(argv)
    for a in it:
        if a == "--base":
            ref = next(it, None)
            if ref is None:
                print("--base needs a ref", file=sys.stderr)
                return 2
        elif a == "--dry-run":
            dry = True
        elif a == "--selftest":
            st = True
        else:
            print(__doc__.split("Usage:")[1].split("Exit:")[0], file=sys.stderr)
            return 2
    if st:
        return selftest()
    try:
        return run_move(ROOT, ref, dry)
    except Refused as e:
        print("move_branch_values: REFUSED: %s" % e, file=sys.stderr)
        return 1
    except (csv.Unmeasured, cdd.Unmeasurable) as e:
        print("move_branch_values: UNMEASURED: %s" % e, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
