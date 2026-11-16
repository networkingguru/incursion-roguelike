#!/usr/bin/env python3
"""Resolve the deliberate git conflict of an AC8 `-conflict` case from a committed resolution (inc-cjos0 phase 9, A6).

  tools/pressure/resolve_conflict.py <worktree> <resolve-dir>
  tools/pressure/resolve_conflict.py --selftest

<worktree> is mid-merge. <resolve-dir> is tools/pressure/cases/<case>/resolve/, which holds one file per conflicted
path, at that path: resolve/inc/Target.h resolves inc/Target.h;
so does resolve/inc/Target.h.resolve (the suffixed form, used where the tree scans files as source or docs). Such a file holds the text that replaces each
conflict hunk of the path, in file order, the replacements separated by a line that reads exactly `@@@ next hunk`.
(Text outside the hunks is git's own merge, so a resolution survives a change elsewhere in the file.)
Each resolved path is `git add`ed; the caller commits the merge.
A GENERATED path (src/yygram.cpp, inc/yygram.h, lib/dispatch.h) takes no hunk text: it needs no resolution file, and a
resolution file for one FAILS. After every other path is resolved, the tool regenerates them in <worktree>: yygram with
tools/regen_yygram.sh, lib/dispatch.h with `BACKEND=posix ./build_macos.sh` run twice (see .gitattributes). Then it
`git add`s them.
An optional <resolve-dir>/post.patch (a unified diff) is applied after the hunks and before the generated files are
rebuilt; <resolve-dir>/README.md is the table that explains the resolution and is never read as one.
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


GENERATED = {"src/yygram.cpp": "yygram", "inc/yygram.h": "yygram", "lib/dispatch.h": "dispatch"}
REGEN = {"yygram": [["tools/regen_yygram.sh"]],
         "dispatch": [["./build_macos.sh"], ["./build_macos.sh"]]}


def regenerate(w, paths):
    """Take 'ours' for each generated path, run its generator, stage the result. 0 done, 1 a generator failed."""
    for p in paths:
        r = git(w, "checkout", "--ours", "--", p)
        if r.returncode != 0:
            print("resolve_conflict: FAIL: git checkout --ours %s: %s" % (p, r.stderr.strip()[:200]))
            return 1
    for kind in sorted(set(GENERATED[p] for p in paths)):
        for cmd in REGEN[kind]:
            env = dict(os.environ)
            if kind == "dispatch":
                env["BACKEND"] = "posix"
            r = subprocess.run(cmd, cwd=w, env=env, capture_output=True, text=True)
            if r.returncode != 0:
                print("resolve_conflict: FAIL: %s failed (rc %d): %s" % (" ".join(cmd), r.returncode, (r.stdout + r.stderr)[-300:].strip()))
                return 1
        print("resolve_conflict: regenerated %s" % kind)
    for p in paths:
        a = git(w, "add", "--", p)
        if a.returncode != 0:
            print("resolve_conflict: git add %s failed: %s" % (p, a.stderr.strip()[:200]))
            return 1
        print("resolve_conflict: %s is generated output, staged" % p)
    if any(GENERATED[p] == "yygram" for p in paths):
        for q in ("src/yygram.cpp", "inc/yygram.h"):
            if q not in paths and git(w, "status", "--porcelain", "--", q).stdout.strip():
                git(w, "add", "--", q)
    return 0


def git(w, *args):
    return subprocess.run(["git", "-C", w] + list(args), capture_output=True, text=True)


CONTROL = ("README.md", "post.patch", "deletions.txt", "keeps.txt")
SUFFIX = ".resolve"
MARKER = re.compile(r"^# stale-quote-ok:[ \t]*\S[^\n]*\n")


def strip_marker(text):
    """Drop ONE leading `# stale-quote-ok: <why>` line (the exemption form tools/check_stale_quotes.sh reads) from a
    resolution file or post.patch. Only line 1 counts; a second marker line or a marker lower down stays text."""
    return MARKER.sub("", text, count=1)


def load_resolution_files(rdir):
    """Return ([paths with a resolution], {path: file holding it}), or (None, None) after a loud line.
    A file `<path>.resolve` resolves <path>; a plain file `<path>` does too. Both for one path is refused."""
    have, src_of = [], {}
    for root, _, files in (os.walk(rdir) if os.path.isdir(rdir) else []):
        for f in files:
            full = os.path.join(root, f)
            rel = os.path.relpath(full, rdir)
            if rel in CONTROL:
                continue   # the explaining table and the optional patch are no resolution of a path
            if rel.endswith(SUFFIX):
                rel = rel[:-len(SUFFIX)]
            if rel in src_of:
                print("resolve_conflict: FAIL: %s holds both %s and %s%s for one path" % (rdir, rel, rel, SUFFIX))
                return None, None
            src_of[rel] = full
            have.append(rel)
    return have, src_of


def resolve(w, rdir):
    r = git(w, "diff", "--name-only", "--diff-filter=U")
    if r.returncode != 0:
        print("resolve_conflict: git diff failed: %s" % r.stderr.strip()[:200], file=sys.stderr)
        return 2
    unmerged_all = [p for p in r.stdout.split("\n") if p]
    # deletions.txt: one path per line, a modify/delete conflict resolved by taking the deletion (the other side removed
    # the file, this side changed it). The path MUST be unmerged and MUST carry no conflict marker (a content conflict is
    # never settled by deleting).
    dfile = os.path.join(rdir, "deletions.txt")
    if os.path.isfile(dfile):
        for p in [l.strip() for l in open(dfile).read().split("\n") if l.strip() and not l.startswith("#")]:
            if p not in unmerged_all:
                print("resolve_conflict: FAIL: deletions.txt names %s, which is not in conflict" % p)
                return 1
            fp = os.path.join(w, p)
            if os.path.exists(fp) and re.search(r"^<<<<<<< ", open(fp, errors="surrogateescape").read(), re.M):
                print("resolve_conflict: FAIL: %s has conflict hunks; deleting it would drop a content conflict" % p)
                return 1
            a = git(w, "rm", "-q", "-f", "--", p)
            if a.returncode != 0:
                print("resolve_conflict: git rm %s failed: %s" % (p, a.stderr.strip()[:200]))
                return 1
            print("resolve_conflict: deleted %s (the other side removed it)" % p)
        unmerged_all = [p for p in git(w, "diff", "--name-only", "--diff-filter=U").stdout.split("\n") if p]
    # keeps.txt: one path per line, the mirror image of deletions.txt: the other side removed the file, this side kept
    # it (an epic-only file that master's conversion did not cover), and this side's file stays. The path MUST be
    # unmerged and MUST carry no conflict marker.
    kfile = os.path.join(rdir, "keeps.txt")
    if os.path.isfile(kfile):
        for p in [l.strip() for l in open(kfile).read().split("\n") if l.strip() and not l.startswith("#")]:
            if p not in unmerged_all:
                print("resolve_conflict: FAIL: keeps.txt names %s, which is not in conflict" % p)
                return 1
            fp = os.path.join(w, p)
            if not os.path.exists(fp):
                print("resolve_conflict: FAIL: keeps.txt names %s, which this side no longer holds" % p)
                return 1
            if re.search(r"^<<<<<<< ", open(fp, errors="surrogateescape").read(), re.M):
                print("resolve_conflict: FAIL: %s has conflict hunks; keeping it would drop a content conflict" % p)
                return 1
            a = git(w, "add", "--", p)
            if a.returncode != 0:
                print("resolve_conflict: git add %s failed: %s" % (p, a.stderr.strip()[:200]))
                return 1
            print("resolve_conflict: kept %s (the other side removed it)" % p)
        unmerged_all = [p for p in git(w, "diff", "--name-only", "--diff-filter=U").stdout.split("\n") if p]
    gen = [p for p in unmerged_all if p in GENERATED]
    unmerged = [p for p in unmerged_all if p not in GENERATED]
    if unmerged and not os.path.isdir(rdir):
        print("resolve_conflict: no resolve dir %s" % rdir, file=sys.stderr)
        return 2
    have, src_of = load_resolution_files(rdir)
    if have is None:
        return 1
    bad = 0
    for p in unmerged:
        if p not in have:
            print("resolve_conflict: FAIL: %s is in conflict and %s has no resolution for it" % (p, rdir))
            bad += 1
    for p in have:
        if p in GENERATED:
            print("resolve_conflict: FAIL: %s has a resolution for %s, which is generated output: it is regenerated, never given hunk text" % (rdir, p))
            bad += 1
        elif p not in unmerged:
            print("resolve_conflict: FAIL: %s has a resolution for %s, which is not in conflict" % (rdir, p))
            bad += 1
    if bad:
        return 1
    for p in unmerged:
        text = open(os.path.join(w, p), encoding="utf-8", errors="surrogateescape").read()
        repl = strip_marker(open(src_of[p], encoding="utf-8", errors="surrogateescape").read())
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
    # edits outside the conflict hunks that the build or the commit checks need: a unified diff, applied before the
    # generated files are rebuilt (the build reads these edits)
    post = os.path.join(rdir, "post.patch")
    if os.path.isfile(post):
        patch = strip_marker(open(post, encoding="utf-8", errors="surrogateescape").read())
        a = subprocess.run(["git", "-C", w, "apply", "--index", "-"], input=patch.encode("utf-8", "surrogateescape"), capture_output=True)
        a.stderr = a.stderr.decode("utf-8", "replace")
        if a.returncode != 0:
            print("resolve_conflict: FAIL: %s does not apply: %s" % (post, a.stderr.strip()[:300]))
            return 1
        print("resolve_conflict: applied post.patch")
    # the project's own procedure (.claude/rules/epic-branches.md): the unchanged mover, before the generated files are
    # rebuilt, because the build refuses two names that hold one stored value. Its unstaged diff is the record of what
    # it moved (INCURSION_RESOLVE_MOVER_DIFF names the file); nobody edits a stored number by hand.
    mover = os.path.join(w, "tools", "move_branch_values.py")
    if unmerged and os.path.isfile(mover):
        r = subprocess.run([sys.executable, mover], cwd=w, capture_output=True, text=True)
        print((r.stdout + r.stderr).rstrip())
        if r.returncode != 0:
            print("resolve_conflict: FAIL: tools/move_branch_values.py failed (rc %d)" % r.returncode)
            return 1
        # the mover's files: changed in the work tree, and not one of the still-unmerged generated paths
        still = set(git(w, "diff", "--name-only", "--diff-filter=U").stdout.split("\n"))
        moved = [m for m in git(w, "diff", "--name-only").stdout.split("\n") if m and m not in still]
        d = git(w, "diff", "--", *moved).stdout if moved else ""
        if d:
            out = os.environ.get("INCURSION_RESOLVE_MOVER_DIFF")
            if out:
                open(out, "w", encoding="utf-8", errors="surrogateescape").write(d)
            if git(w, "add", "--", *moved).returncode != 0:
                print("resolve_conflict: git add after the mover failed")
                return 1
            print("resolve_conflict: the mover moved values (diff saved)")
    if gen:
        return regenerate(w, gen)
    return 0


def selftest_generated(d):
    """A conflict in a generated path is regenerated, not resolved from hunk text; a resolution file for one fails."""
    w = os.path.join(d, "gen")
    os.makedirs(os.path.join(w, "src"))
    os.makedirs(os.path.join(w, "inc"))
    os.makedirs(os.path.join(w, "tools"))

    def sh(*a):
        subprocess.run(["git", "-C", w, "-c", "user.name=t", "-c", "user.email=t@t"] + list(a), check=True, capture_output=True)
    sh("init", "-q", "-b", "m")
    open(os.path.join(w, "src/yygram.cpp"), "w").write("a\nb\nc\n")
    open(os.path.join(w, "inc/yygram.h"), "w").write("h\n")
    gen = os.path.join(w, "tools/regen_yygram.sh")
    open(gen, "w").write("#!/bin/sh\nprintf 'regenerated\\n' > src/yygram.cpp\nprintf 'regenerated h\\n' > inc/yygram.h\n")
    os.chmod(gen, 0o755)
    sh("add", "."); sh("commit", "-q", "-m", "p")
    sh("checkout", "-q", "-b", "x")
    open(os.path.join(w, "src/yygram.cpp"), "w").write("a\nX\nc\n"); sh("commit", "-qam", "x")
    sh("checkout", "-q", "m")
    open(os.path.join(w, "src/yygram.cpp"), "w").write("a\nY\nc\n"); sh("commit", "-qam", "y")
    if subprocess.run(["git", "-C", w, "merge", "x"], capture_output=True, text=True).returncode == 0:
        print("FAIL selftest setup: no generated-path conflict")
        return 1
    bad = 0
    res = os.path.join(d, "genres")
    os.makedirs(os.path.join(res, "src"))
    open(os.path.join(res, "src/yygram.cpp"), "w").write("hand text\n")
    got = resolve(w, res)
    ok = got == 1
    print("%s generated path with a resolution file (rc %d, want 1)" % ("ok  " if ok else "FAIL", got))
    bad += 0 if ok else 1
    os.remove(os.path.join(res, "src/yygram.cpp"))
    got = resolve(w, os.path.join(d, "no-such-dir"))
    left = subprocess.run(["git", "-C", w, "diff", "--name-only", "--diff-filter=U"], capture_output=True, text=True).stdout.strip()
    ok = got == 0 and not left and open(os.path.join(w, "src/yygram.cpp")).read() == "regenerated\n"
    print("%s generated path regenerated, no resolve dir needed (rc %d, want 0)" % ("ok  " if ok else "FAIL", got))
    bad += 0 if ok else 1
    return bad


def selftest_keeps(d):
    """A modify/delete conflict listed in keeps.txt keeps this side's file; one not listed fails."""
    w = os.path.join(d, "keep")
    os.makedirs(w)

    def sh(*a):
        subprocess.run(["git", "-C", w, "-c", "user.name=t", "-c", "user.email=t@t"] + list(a), check=True, capture_output=True)
    sh("init", "-q", "-b", "m")
    open(os.path.join(w, "k.txt"), "w").write("a\n")
    sh("add", "."); sh("commit", "-q", "-m", "p")
    sh("checkout", "-q", "-b", "x")
    open(os.path.join(w, "k.txt"), "w").write("a\nX\n"); sh("commit", "-qam", "x")
    sh("checkout", "-q", "m")
    sh("rm", "-q", "k.txt"); sh("commit", "-qm", "gone")
    if subprocess.run(["git", "-C", w, "merge", "x"], capture_output=True, text=True).returncode == 0:
        print("FAIL selftest setup: no modify/delete conflict")
        return 1
    rd = os.path.join(d, "keepres")
    os.makedirs(rd)
    open(os.path.join(rd, "keeps.txt"), "w").write("nosuch.txt\n")
    got = resolve(w, rd)
    ok = got == 1
    print("%s keeps.txt naming a path not in conflict (rc %d, want 1)" % ("ok  " if ok else "FAIL", got))
    bad = 0 if ok else 1
    open(os.path.join(rd, "keeps.txt"), "w").write("k.txt\n")
    got = resolve(w, rd)
    left = subprocess.run(["git", "-C", w, "diff", "--name-only", "--diff-filter=U"], capture_output=True, text=True).stdout.strip()
    ok = got == 0 and not left and open(os.path.join(w, "k.txt")).read() == "a\nX\n"
    print("%s keeps.txt keeps this side's file (rc %d, want 0)" % ("ok  " if ok else "FAIL", got))
    return bad + (0 if ok else 1)


def selftest_suffix(d):
    """A `<path>.resolve` file resolves <path>; both forms for one path are refused."""
    rd = os.path.join(d, "suffixres")
    os.makedirs(os.path.join(rd, "sub"))
    open(os.path.join(rd, "sub", "a.h.resolve"), "w").write("x\n")
    open(os.path.join(rd, "b.txt"), "w").write("y\n")
    open(os.path.join(rd, "README.md"), "w").write("t\n")
    have, src_of = load_resolution_files(rd)
    ok = have is not None and sorted(have) == ["b.txt", "sub/a.h"] and src_of["sub/a.h"].endswith("a.h.resolve")
    print("%s suffix and plain layouts both load" % ("ok  " if ok else "FAIL"))
    bad = 0 if ok else 1
    open(os.path.join(rd, "sub", "a.h"), "w").write("z\n")
    have, _ = load_resolution_files(rd)
    ok = have is None
    print("%s a path held in both forms is refused" % ("ok  " if ok else "FAIL"))
    return bad + (0 if ok else 1)


def selftest_marker():
    m = "# stale-quote-ok: why\n"
    cases = [("one leading marker is stripped", m + "A\n", "A\n"),
             ("a second marker line stays", m + m + "A\n", m + "A\n"),
             ("a marker after line 1 stays", "A\n" + m, "A\n" + m),
             ("a marker with no reason stays", "# stale-quote-ok:\nA\n", "# stale-quote-ok:\nA\n")]
    bad = 0
    for name, got, want in cases:
        ok = strip_marker(got) == want
        print("%s %s" % ("ok  " if ok else "FAIL", name))
        bad += 0 if ok else 1
    return bad


def selftest():
    bad = selftest_marker()
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
        bad += selftest_generated(d)
        bad += selftest_keeps(d)
        bad += selftest_suffix(d)
    print("resolve_conflict selftest: %s" % ("FAIL" if bad else "PASS"))
    return 1 if bad else 0


if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] == "--selftest":
        sys.exit(selftest())
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    sys.exit(resolve(sys.argv[1], sys.argv[2]))
