#!/usr/bin/env python3
"""Git merge driver for the two files every bead touches at its end.

    tools/merge_landed.py landed %O %A %B          lib/landed.irc
    tools/merge_landed.py landed-ledger %O %A %B   tools/resource_order.ledger
    tools/merge_landed.py --selftest               prove both drivers, no build

WHY. docs/superpowers/specs/2026-10-31-no-shared-tail-design.md, 4.2 and 4.4.
Every bead that adds a resource appends one include line to lib/landed.irc, so
two beads append at the same end of the file and git stops. This driver merges
the lines instead. tools/resource_order.ledger is re-recorded at landing, so
the driver always takes master's copy.

MODE landed. Every line of every input MUST be exactly
`#include "landed-<bead-id>.irh"`, bead id `inc-[a-z0-9]+(\\.[0-9]+)*`.
  * A trailing CR is stripped (CRLF input is accepted; output is LF).
  * A trailing space or tab makes the line malformed.
  * A blank line is malformed, except one final empty line (the newline that
    ends the file). A zero-byte file is an empty list.
The result is written into %A, in this order, with no line twice:
  1. the lines of master:lib/landed.irc, in master's order;
  2. the other lines of the current branch's base branch
     (git config branch.<branch>.incursionBase, default master), in its order;
  3. the other lines of %A; 4. the other lines of %B.
It exits 1, leaving %A untouched so git records a conflict, when any line of
any input is malformed or when master's or the base branch's copy cannot be
read. It prints a one-line reason to stderr.

MODE landed-ledger. Writes `git show master:tools/resource_order.ledger` into
%A, whatever the merge direction. Exits 1 when master's copy cannot be read.

# fact: git state (the three inputs, master, the base branch) -- the scratch repositories --selftest builds under logs/merge-landed-selftest-<pid>/
# fact: current branch name and its incursionBase -- `git checkout -b` and `git config` inside the scratch repository
# fact: the merge driver configuration -- set in the scratch repository, unset for the fail-safe case
# This tool reads no seed, no character and no world.
"""
import os
import re
import shutil
import subprocess
import sys

LANDED = "lib/landed.irc"
LEDGER = "tools/resource_order.ledger"
LINE_RE = re.compile(r'#include "landed-inc-[a-z0-9]+(\.[0-9]+)*\.irh"')


class Refuse(Exception):
    pass


def git(*args, cwd=None):
    return subprocess.run(["git", *args], cwd=cwd, capture_output=True,
                          text=True, encoding="utf-8", errors="replace")


def parse(text, label):
    """Return the include lines of one input, or raise Refuse."""
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()                      # the newline that ends the file
    out = []
    for n, raw in enumerate(lines, 1):
        line = raw[:-1] if raw.endswith("\r") else raw
        if not LINE_RE.fullmatch(line):
            raise Refuse("%s line %d is not a landed include line: %r"
                         % (label, n, line))
        out.append(line)
    return out


def show(ref, path, label):
    r = git("show", "%s:%s" % (ref, path))
    if r.returncode != 0:
        raise Refuse("cannot read %s:%s (%s)" % (ref, path, label))
    return r.stdout


def base_branch():
    head = git("rev-parse", "--abbrev-ref", "HEAD")
    if head.returncode != 0:
        return "master"
    cfg = git("config", "--get", "branch.%s.incursionBase" % head.stdout.strip())
    base = cfg.stdout.strip()
    return base if cfg.returncode == 0 and base else "master"


def read_file(path):
    # newline="" keeps a CR for parse() to strip.
    with open(path, encoding="utf-8", newline="") as f:
        return f.read()


def merge_landed(o_path, a_path, b_path):
    base = base_branch()
    sources = [
        ("master", show("master", LANDED, "master's copy")),
        (base, show(base, LANDED, "base branch's copy")),
        ("%A", read_file(a_path)),
        ("%B", read_file(b_path)),
        ("%O", read_file(o_path)),
    ]
    parsed = [parse(text, label) for label, text in sources]
    result, seen = [], set()
    for lines in parsed[:4]:             # %O is checked, not merged
        for line in lines:
            if line not in seen:
                seen.add(line)
                result.append(line)
    with open(a_path, "w", encoding="utf-8", newline="\n") as f:
        f.write("".join(line + "\n" for line in result))


def merge_ledger(o_path, a_path, b_path):
    text = show("master", LEDGER, "master's ledger")
    with open(a_path, "w", encoding="utf-8", newline="") as f:
        f.write(text)


def driver(argv):
    if len(argv) != 4 or argv[0] not in ("landed", "landed-ledger"):
        print("usage: merge_landed.py landed|landed-ledger %O %A %B", file=sys.stderr)
        return 2
    mode, o, a, b = argv
    try:
        (merge_landed if mode == "landed" else merge_ledger)(o, a, b)
    except Refuse as e:
        print("merge_landed: %s" % e, file=sys.stderr)
        return 1
    except OSError as e:
        print("merge_landed: %s" % e, file=sys.stderr)
        return 1
    return 0


# ---------------------------------------------------------------- selftest

SELF = os.path.abspath(__file__)


def inc(n):
    return '#include "landed-inc-%s.irh"' % n


class Scratch:
    def __init__(self, root):
        self.root = root

    def g(self, *args, check=True):
        r = git(*args, cwd=self.root)
        if check and r.returncode != 0:
            raise RuntimeError("git %s: %s" % (" ".join(args), r.stderr.strip()))
        return r

    def write(self, path, text):
        full = os.path.join(self.root, path)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "w", encoding="utf-8", newline="") as f:
            f.write(text)

    def read(self, path):
        with open(os.path.join(self.root, path), encoding="utf-8", newline="") as f:
            return f.read()

    def commit(self, msg):
        self.g("add", "-A")
        self.g("commit", "-q", "-m", msg)


def make_repo(parent, name, drivers=True, files=None):
    root = os.path.join(parent, name)
    os.makedirs(os.path.join(root, "tools"))
    s = Scratch(root)
    s.g("init", "-q", "-b", "master")
    s.g("config", "user.name", "selftest")
    s.g("config", "user.email", "selftest@example.invalid")
    shutil.copy(SELF, os.path.join(root, "tools", "merge_landed.py"))
    s.write(".gitattributes",
            "lib/landed.irc merge=landed\n%s merge=landed-ledger\n" % LEDGER)
    if drivers:
        for mode in ("landed", "landed-ledger"):
            s.g("config", "merge.%s.name" % mode, mode)
            s.g("config", "merge.%s.driver" % mode,
                "python3 tools/merge_landed.py %s %%O %%A %%B" % mode)
    for path, text in (files or {}).items():
        s.write(path, text)
    s.commit("base")
    return s


def lines_of(text):
    return text.split("\n")[:-1] if text.endswith("\n") else text.split("\n")


def selftest():
    parent = os.path.join(os.path.dirname(os.path.dirname(SELF)), "logs")
    os.makedirs(parent, exist_ok=True)
    scratch = os.path.join(parent, "merge-landed-selftest-%d" % os.getpid())
    os.makedirs(scratch)
    failed = []

    def check(name, ok, detail=""):
        print("%s: %s%s" % ("ok  " if ok else "FAIL", name,
                            "" if ok else " -- " + detail))
        if not ok:
            failed.append(name)

    try:
        # (a) two branches each append; master first, then base, then branches.
        s = make_repo(scratch, "a", files={LANDED: inc("m1") + "\n"})
        s.g("branch", "inc-a")
        s.g("branch", "inc-b")
        s.write(LANDED, inc("m1") + "\n" + inc("m2") + "\n")
        s.commit("master adds m2")
        s.g("checkout", "-q", "inc-a")
        s.write(LANDED, inc("m1") + "\n" + inc("a1") + "\n")
        s.commit("a1")
        s.g("checkout", "-q", "inc-b")
        s.write(LANDED, inc("m1") + "\n" + inc("b1") + "\n" + inc("a1") + "\n")
        s.commit("b1 and a copy of a1")
        s.g("checkout", "-q", "inc-a")
        r = s.g("merge", "--no-edit", "inc-b", check=False)
        want = [inc("m1"), inc("m2"), inc("a1"), inc("b1")]
        got = lines_of(s.read(LANDED))
        check("a: two appends merge in master/base/A/B order, no duplicate",
              r.returncode == 0 and got == want,
              "exit %d, got %r" % (r.returncode, got))

        # (a2) a base branch other than master sits between master and %A.
        s = make_repo(scratch, "a2", files={LANDED: inc("m1") + "\n"})
        s.g("branch", "epic")
        s.g("branch", "inc-a")
        s.g("branch", "inc-b")
        s.g("checkout", "-q", "epic")
        s.write(LANDED, inc("m1") + "\n" + inc("e1") + "\n")
        s.commit("e1")
        s.g("checkout", "-q", "inc-a")
        s.g("config", "branch.inc-a.incursionBase", "epic")
        s.write(LANDED, inc("m1") + "\n" + inc("a1") + "\n")
        s.commit("a1")
        s.g("checkout", "-q", "inc-b")
        s.write(LANDED, inc("m1") + "\n" + inc("b1") + "\n")
        s.commit("b1")
        s.g("checkout", "-q", "inc-a")
        r = s.g("merge", "--no-edit", "inc-b", check=False)
        want = [inc("m1"), inc("e1"), inc("a1"), inc("b1")]
        got = lines_of(s.read(LANDED))
        check("a2: base branch lines come after master's, before A's",
              r.returncode == 0 and got == want,
              "exit %d, got %r" % (r.returncode, got))

        # (b) AC5, the red case: a malformed line leaves a conflict.
        s = make_repo(scratch, "b", files={LANDED: inc("m1") + "\n"})
        s.g("branch", "inc-a")
        s.g("branch", "inc-b")
        s.g("checkout", "-q", "inc-a")
        s.write(LANDED, inc("m1") + "\n" + "garbage line\n")
        s.commit("bad")
        s.g("checkout", "-q", "inc-b")
        s.write(LANDED, inc("m1") + "\n" + inc("b1") + "\n")
        s.commit("b1")
        s.g("checkout", "-q", "inc-a")
        r = s.g("merge", "--no-edit", "inc-b", check=False)
        unmerged = s.g("diff", "--name-only", "--diff-filter=U").stdout.split()
        print("RED (AC5): malformed line -> merge exit %d, unmerged=%r, stderr: %s"
              % (r.returncode, unmerged, (r.stdout + r.stderr).strip().splitlines()[-1:]))
        check("b: malformed line makes the merge fail with a conflict (AC5)",
              r.returncode != 0 and unmerged == [LANDED],
              "exit %d, unmerged %r" % (r.returncode, unmerged))

        # (c) ledger gives master's copy in both directions.
        s = make_repo(scratch, "c", files={LEDGER: "L0\n"})
        s.g("branch", "inc-a")
        s.write(LEDGER, "M2\n")
        s.commit("master ledger")
        s.g("checkout", "-q", "inc-a")
        s.write(LEDGER, "B1\n")
        s.commit("bead ledger")
        r1 = s.g("merge", "--no-edit", "master", check=False)
        got1 = s.read(LEDGER)
        s.g("checkout", "-q", "master")
        s.write("other.txt", "x\n")
        s.commit("master moves on")
        r2 = s.g("merge", "--no-edit", "inc-a", check=False)
        got2 = s.read(LEDGER)
        check("c: master into bead gives master's ledger",
              r1.returncode == 0 and got1 == "M2\n", "exit %d, got %r" % (r1.returncode, got1))
        check("c: bead into master gives master's ledger",
              r2.returncode == 0 and got2 == "M2\n", "exit %d, got %r" % (r2.returncode, got2))

        # (d) driver config unset: two appends conflict (fails safe).
        s = make_repo(scratch, "d", drivers=False, files={LANDED: inc("m1") + "\n"})
        s.g("branch", "inc-a")
        s.g("branch", "inc-b")
        s.g("checkout", "-q", "inc-a")
        s.write(LANDED, inc("m1") + "\n" + inc("a1") + "\n")
        s.commit("a1")
        s.g("checkout", "-q", "inc-b")
        s.write(LANDED, inc("m1") + "\n" + inc("b1") + "\n")
        s.commit("b1")
        s.g("checkout", "-q", "inc-a")
        r = s.g("merge", "--no-edit", "inc-b", check=False)
        check("d: driver config unset -> text merge conflicts", r.returncode != 0,
              "merge exit %d" % r.returncode)

        # Unit cases, run through the real command line in a scratch repo.
        u = make_repo(scratch, "u", files={LANDED: inc("m1") + "\n"})

        def unit(name, o, a, b, expect_rc, expect_lines=None, repo=u):
            for fname, text in (("o", o), ("a", a), ("b", b)):
                repo.write(fname, text)
            before = repo.read("a")
            r = subprocess.run(
                [sys.executable, SELF, "landed", "o", "a", "b"],
                cwd=repo.root, capture_output=True, text=True)
            after = repo.read("a")
            ok = r.returncode == expect_rc
            if expect_rc == 0 and expect_lines is not None:
                ok = ok and lines_of(after) == expect_lines and after.endswith("\n")
            if expect_rc == 1:
                ok = ok and after == before and bool(r.stderr.strip())
            check("unit: " + name, ok,
                  "exit %d, %r, stderr %r" % (r.returncode, after, r.stderr.strip()))

        unit("empty inputs give master's lines", "", "", "", 0, [inc("m1")])
        unit("duplicate line in an input appears once",
             "", inc("a1") + "\n" + inc("a1") + "\n", "", 0, [inc("m1"), inc("a1")])
        unit("CRLF is accepted and written as LF",
             "", inc("a1") + "\r\n", inc("b1") + "\r\n", 0,
             [inc("m1"), inc("a1"), inc("b1")])
        unit("no final newline is accepted", "", inc("a1"), "", 0, [inc("m1"), inc("a1")])
        unit("trailing space is malformed", "", inc("a1") + " \n", "", 1)
        unit("blank line in the middle is malformed",
             "", inc("a1") + "\n\n" + inc("a2") + "\n", "", 1)
        unit("malformed line in %B is malformed", "", "", "#include <x.h>\n", 1)
        unit("malformed %O is refused", "bad\n", "", "", 1)
        unit("bead id with dotted suffix is accepted",
             "", '#include "landed-inc-pu6v.17.irh"\n', "", 0,
             [inc("m1"), '#include "landed-inc-pu6v.17.irh"'])
        unit("bead id with a non-numeric dotted suffix is refused",
             "", '#include "landed-inc-pu6v.x.irh"\n', "", 1)
        nm = make_repo(scratch, "nomaster")          # no lib/landed.irc on master
        unit("unreadable master copy is refused", "", "", "", 1, repo=nm)
        nl = make_repo(scratch, "noledger")          # no ledger on master
        for fname in ("o", "a", "b"):
            nl.write(fname, "x\n")
        r = subprocess.run([sys.executable, SELF, "landed-ledger", "o", "a", "b"],
                           cwd=nl.root, capture_output=True, text=True)
        check("unit: ledger mode with no master copy is refused",
              r.returncode == 1 and nl.read("a") == "x\n", "exit %d" % r.returncode)
    except Exception as e:                           # a scratch repo failed to build
        check("scratch setup", False, repr(e))
    finally:
        if not failed:
            shutil.rmtree(scratch, ignore_errors=True)

    if failed:
        print("SELFTEST FAIL: %s (scratch kept at %s)" % (", ".join(failed), scratch))
        return 1
    print("SELFTEST PASS")
    return 0


def main(argv):
    if argv and argv[0] == "--selftest":
        return selftest()
    return driver(argv)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
