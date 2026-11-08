#!/usr/bin/env python3
"""Resolve the deliberate git conflict of an AC8 `-conflict` case from a committed resolution (inc-cjos0 phase 9, A6).

  tools/pressure/resolve_conflict.py <worktree> <resolve-dir>
  tools/pressure/resolve_conflict.py --selftest

<worktree> is mid-merge. <resolve-dir> is tools/pressure/cases/<case>/resolve/, which holds one file per conflicted
path, at that path: resolve/inc/Target.h resolves inc/Target.h. Such a file holds the text that replaces each
conflict hunk of the path, in file order, the replacements separated by a line that reads exactly `@@@ next hunk`.
(Text outside the hunks is git's own merge, so a resolution survives a change elsewhere in the file.)
Each resolved path is `git add`ed; the caller commits the merge.
Exit 0 every unmerged path resolved. Exit 1 and a loud line for: an unmerged path with no resolution file, a
resolution file for a path that is not unmerged, a hunk count that differs from the path's, a marker left over.
Exit 2 could not measure (not a git worktree, no resolve dir).
"""
import os
import re
import subprocess
import sys
import tempfile

SEP = "@@@ next hunk"
HUNK = re.compile(r"^<<<<<<< [^\n]*\n(.*?)^=======\n(.*?)^>>>>>>> [^\n]*\n", re.S | re.M)


def git(w, *args):
    return subprocess.run(["git", "-C", w] + list(args), capture_output=True, text=True)


def resolve(w, rdir):
    r = git(w, "diff", "--name-only", "--diff-filter=U")
    if r.returncode != 0:
        print("resolve_conflict: git diff failed: %s" % r.stderr.strip()[:200], file=sys.stderr)
        return 2
    unmerged = [p for p in r.stdout.split("\n") if p]
    if not os.path.isdir(rdir):
        print("resolve_conflict: no resolve dir %s" % rdir, file=sys.stderr)
        return 2
    have = []
    for root, _, files in os.walk(rdir):
        for f in files:
            have.append(os.path.relpath(os.path.join(root, f), rdir))
    bad = 0
    for p in unmerged:
        if p not in have:
            print("resolve_conflict: FAIL: %s is in conflict and %s has no resolution for it" % (p, rdir))
            bad += 1
    for p in have:
        if p not in unmerged:
            print("resolve_conflict: FAIL: %s has a resolution for %s, which is not in conflict" % (rdir, p))
            bad += 1
    if bad:
        return 1
    for p in unmerged:
        text = open(os.path.join(w, p), encoding="utf-8", errors="surrogateescape").read()
        repl = open(os.path.join(rdir, p), encoding="utf-8", errors="surrogateescape").read()
        repl = re.split(r"^" + re.escape(SEP) + r"\n", repl, flags=re.M)
        n = len(HUNK.findall(text))
        if n != len(repl):
            print("resolve_conflict: FAIL: %s has %d conflict hunk(s) and its resolution gives %d" % (p, n, len(repl)))
            return 1
        it = iter(repl)
        out = HUNK.sub(lambda m: next(it), text)
        if re.search(r"^(<<<<<<<|=======|>>>>>>>)", out, re.M):
            print("resolve_conflict: FAIL: a conflict marker is left in %s" % p)
            return 1
        open(os.path.join(w, p), "w", encoding="utf-8", errors="surrogateescape").write(out)
        a = git(w, "add", "--", p)
        if a.returncode != 0:
            print("resolve_conflict: git add %s failed: %s" % (p, a.stderr.strip()[:200]))
            return 1
        print("resolve_conflict: resolved %s (%d hunk(s))" % (p, n))
    return 0


def selftest():
    bad = 0
    with tempfile.TemporaryDirectory() as d:
        w = os.path.join(d, "r")
        os.makedirs(w)

        def sh(*a):
            subprocess.run(["git", "-C", w, "-c", "user.name=t", "-c", "user.email=t@t"] + list(a), check=True, capture_output=True)
        sh("init", "-q", "-b", "m")
        open(os.path.join(w, "f.txt"), "w").write("a\nb\nc\n")
        sh("add", "."); sh("commit", "-q", "-m", "p")
        sh("checkout", "-q", "-b", "x")
        open(os.path.join(w, "f.txt"), "w").write("a\nX\nc\n"); sh("commit", "-qam", "x")
        sh("checkout", "-q", "m")
        open(os.path.join(w, "f.txt"), "w").write("a\nY\nc\n"); sh("commit", "-qam", "y")
        merge = subprocess.run(["git", "-C", w, "merge", "x"], capture_output=True, text=True)
        if merge.returncode == 0:
            print("FAIL selftest setup: no conflict"); return 1
        rdir = os.path.join(d, "res")
        os.makedirs(os.path.join(d, "empty"))
        cases = [("no resolution file", os.path.join(d, "empty"), None, 1),
                 ("hunk count differs", rdir, "one\n@@@ next hunk\ntwo\n", 1),
                 ("resolved", rdir, "X\nY\n", 0)]
        for name, rd, body, want in cases:
            if body is not None:
                os.makedirs(rdir, exist_ok=True)
                open(os.path.join(rdir, "f.txt"), "w").write(body)
            got = resolve(w, rd)
            ok = got == want
            if want == 0:
                ok = ok and open(os.path.join(w, "f.txt")).read() == "a\nX\nY\nc\n"
            print("%s %s (rc %d, want %d)" % ("ok  " if ok else "FAIL", name, got, want))
            bad += 0 if ok else 1
        os.makedirs(os.path.join(rdir, "g"), exist_ok=True)
    print("resolve_conflict selftest: %s" % ("FAIL" if bad else "PASS"))
    return 1 if bad else 0


if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] == "--selftest":
        sys.exit(selftest())
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    sys.exit(resolve(sys.argv[1], sys.argv[2]))
