#!/usr/bin/env python3
# gate: cheap --selftest
# fact: the game, a seed, a character -- none read; the check reads git and file text only
# fact: a vetting pass -- the selftest writes its own pass files in a scratch repo; a real run reads <git-common-dir>/fast-vetted
"""Guard the fast-check set at commit time (inc-rst61).

Run by .beads/hooks/pre-commit on every commit. Exit 0 pass, 1 refused
(reasons on stderr), 2 could not measure. Rules, on the STAGED change:

  A  Only the owner vets a check. Every line of tools/fast_checks.vetted that
     the commit adds or changes needs a one-commit vetting pass for each
     check+kind the line grants. The owner gives a pass by answering yes to
     "Is tools/check_<name> vetted for <kind>?"; the PreToolUse hook
     tools/fact_exempt_pass.py mints it. A session cannot mint one. Removing a
     line, or narrowing its kinds with the reason unchanged, needs no pass.
  B  A commit may not remove the '# gate-fast:' marker from a check that has no
     gate tier (no '# gate:' line in its first 40 lines, or '# gate: none'):
     the fast set is then the only run that check gets before landing.
     Deleting the whole check file is allowed.

A pass is consumed (deleted) only when the commit is otherwise allowed.
Self-test: python3 tools/check_fast_vetted.py --selftest
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

VETTED = "tools/fast_checks.vetted"
KINDS = ("game", "build", "git-history", "sleep", "bd", "compiler")
CHECK_RE = re.compile(r"^tools/check_[^/]+\.(sh|py)$")
FAST_RE = re.compile(r"^#\s*gate-fast:\s*\S")
TIER_RE = re.compile(r"^#\s*gate:\s*(\S+)")


class Unmeasurable(Exception):
    pass


def git(args):
    r = subprocess.run(["git"] + args, capture_output=True)
    return r


def git_out(args):
    r = git(args)
    if r.returncode != 0:
        raise Unmeasurable("git %s failed" % " ".join(args))
    return r.stdout.decode("utf-8", "replace")


def parse_vetted(text):
    """-> {line: (check, [kinds], reason)} for the non-comment lines."""
    out = {}
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split(None, 2)
        kinds = parts[1].split(",") if len(parts) > 1 else []
        out[raw] = (parts[0], kinds, parts[2] if len(parts) > 2 else "")
    return out


def first40(text):
    return text.splitlines()[:40]


def has_fast(text):
    return any(FAST_RE.match(l) for l in first40(text))


def has_tier(text):
    for l in first40(text):
        m = TIER_RE.match(l)
        if m:
            return m.group(1) != "none"
    return False


def rule_a(passdir, staged, head):
    """-> (reasons, passes to consume)."""
    reasons, used = [], []
    old = parse_vetted(head)
    old_by_check = {}
    for check, kinds, reason in old.values():
        old_by_check.setdefault(check, []).append((kinds, reason))
    for raw, (check, kinds, reason) in parse_vetted(staged).items():
        if raw in old:
            continue
        need = list(kinds)
        for okinds, oreason in old_by_check.get(check, []):
            if oreason == reason and set(kinds) <= set(okinds):
                need = []          # a pure narrowing
        if not kinds:
            reasons.append("%s: line for %s names no kind: %r" % (VETTED, check, raw))
        for kind in need:
            if kind not in KINDS:
                reasons.append("%s: %s has unknown kind %r" % (VETTED, check, kind))
                continue
            ticket = os.path.join(passdir, "%s.%s" % (check, kind))
            if os.path.isfile(ticket):
                used.append(ticket)
            else:
                reasons.append(
                    "%s adds or changes a vetting of %s for kind %s, and only the "
                    "owner may vet. The owner must answer yes to: "
                    "\"Is tools/%s vetted for %s?\" (a session cannot mint the pass)."
                    % (VETTED, check, kind, check, kind))
    return reasons, used


def main():
    try:
        git_out(["rev-parse", "--git-dir"])
        merge_head = git_out(["rev-parse", "--git-path", "MERGE_HEAD"]).strip()
        # ponytail: a merge commit's changes were judged where they were made.
        # Ceiling: an edit hidden in a merge's conflict resolution is not read.
        if os.path.exists(os.path.abspath(merge_head)):
            return 0
        common = git_out(["rev-parse", "--git-common-dir"]).strip()
        passdir = os.path.join(os.path.abspath(common), "fast-vetted")
        names = git_out(["diff", "--cached", "--name-only", "-z",
                         "--diff-filter=ACMR"]).split("\0")
        reasons, used = [], []
        if VETTED in names:
            staged = git_out(["show", ":" + VETTED])
            hr = git(["show", "HEAD:" + VETTED])
            head = hr.stdout.decode("utf-8", "replace") if hr.returncode == 0 else ""
            r, u = rule_a(passdir, staged, head)
            reasons += r
            used += u
        mods = git_out(["diff", "--cached", "--name-only", "-z",
                        "--diff-filter=M"]).split("\0")
        for p in mods:
            if not CHECK_RE.match(p):
                continue
            hr = git(["show", "HEAD:" + p])
            if hr.returncode != 0:
                continue
            if not has_fast(hr.stdout.decode("utf-8", "replace")):
                continue
            staged = git_out(["show", ":" + p])
            if has_fast(staged) or has_tier(staged):
                continue
            reasons.append(
                "%s loses its '# gate-fast:' marker and has no '# gate:' tier, so "
                "no run of it would remain before landing. Keep the marker, or "
                "give the check a gate tier." % p)
    except Unmeasurable as e:
        print("check_fast_vetted: could not measure: %s" % e, file=sys.stderr)
        return 2
    if reasons:
        print("check_fast_vetted: REFUSED.", file=sys.stderr)
        for r in reasons:
            print("  " + r, file=sys.stderr)
        return 1
    for t in used:
        try:
            os.remove(t)
        except OSError:
            pass
    return 0


# ---------------------------------------------------------------- selftest

def selftest():
    me = os.path.abspath(__file__)
    work = tempfile.mkdtemp(prefix="fastvet")
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    fails = [0]

    def g(repo, *a):
        return subprocess.run(["git"] + list(a), cwd=repo, env=env,
                              capture_output=True, text=True)

    def put(repo, rel, content, stage=True):
        path = os.path.join(repo, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as f:
            f.write(content)
        if stage:
            g(repo, "add", rel)

    def run(repo):
        return subprocess.run([sys.executable, me], cwd=repo, env=env,
                              capture_output=True, text=True).returncode

    def case(label, want, got):
        ok = got == want
        print("  %s  %s" % ("ok  " if ok else "FAIL", label)
              + ("" if ok else " (got %s, wanted %s)" % (got, want)))
        if not ok:
            fails[0] += 1

    def mk(n):
        repo = os.path.join(work, "r%d" % n)
        os.makedirs(repo)
        g(repo, "init", "-q")
        g(repo, "config", "user.email", "t@t")
        g(repo, "config", "user.name", "t")
        put(repo, VETTED, "# header\ncheck_a.sh bd reason a\n")
        put(repo, "tools/check_a.sh", "#!/bin/sh\n# gate-fast: quick\necho\n")
        put(repo, "tools/check_b.sh", "#!/bin/sh\n# gate: cheap\n# gate-fast: quick\n")
        g(repo, "commit", "-q", "-m", "base")
        return repo

    def mkpass(repo, check, kind):
        d = os.path.join(repo, ".git", "fast-vetted")
        os.makedirs(d, exist_ok=True)
        p = os.path.join(d, "%s.%s" % (check, kind))
        open(p, "w").write("x\n")
        return p

    try:
        r = mk(1)
        case("nothing staged: pass", 0, run(r))

        r = mk(2)
        put(r, VETTED, "# header\ncheck_a.sh bd reason a\ncheck_c.py compiler new\n")
        case("A: added line, no pass: refused", 1, run(r))
        p = mkpass(r, "check_c.py", "game")
        case("A: pass for another kind: refused", 1, run(r))
        case("  that pass is not consumed on refusal", True, os.path.exists(p))
        p2 = mkpass(r, "check_c.py", "compiler")
        case("A: pass for the kind: allowed", 0, run(r))
        case("  pass consumed", False, os.path.exists(p2))
        case("  other pass kept", True, os.path.exists(p))
        case("  second run refused again", 1, run(r))

        r = mk(3)
        put(r, VETTED, "# header\ncheck_a.sh bd,game reason a\n")
        mkpass(r, "check_a.sh", "bd")
        case("A: added kind, pass for old kind only: refused", 1, run(r))
        mkpass(r, "check_a.sh", "game")
        case("A: added kind with its pass: allowed", 0, run(r))

        r = mk(4)
        put(r, VETTED, "# header\ncheck_a.sh bd a different reason\n")
        case("A: changed reason, no pass: refused", 1, run(r))

        r = mk(5)
        put(r, VETTED, "# header\ncheck_a.sh bd reason a\ncheck_c.py bogus x\n")
        mkpass(r, "check_c.py", "bogus")
        case("A: unknown kind: refused even with a file named for it", 1, run(r))

        r = mk(6)
        put(r, VETTED, "# header\n")
        case("A: removing a line needs no pass", 0, run(r))
        r = mk(7)
        put(r, VETTED, "# header\n# comment only changed\ncheck_a.sh bd reason a\n")
        case("A: comment-only change needs no pass", 0, run(r))
        r = mk(8)
        put(r, VETTED, "# header\ncheck_a.sh bd,game reason a\n")
        g(r, "commit", "-q", "-m", "x", "--no-verify")
        put(r, VETTED, "# header\ncheck_a.sh bd reason a\n")
        case("A: narrowing kinds, same reason: no pass", 0, run(r))

        r = mk(9)
        put(r, "tools/check_a.sh", "#!/bin/sh\necho\n")
        case("B: marker removed, no tier: refused", 1, run(r))
        put(r, "tools/check_a.sh", "#!/bin/sh\n# gate: none -- manual\necho\n")
        case("B: marker removed, gate: none: refused", 1, run(r))
        put(r, "tools/check_a.sh", "#!/bin/sh\n# gate: cheap\necho\n")
        case("B: marker removed, gate tier present: allowed", 0, run(r))
        put(r, "tools/check_a.sh", "#!/bin/sh\n# gate-fast: still\necho\n")
        case("B: marker kept: allowed", 0, run(r))
        put(r, "tools/check_a.sh", "#!/bin/sh\n" + "\n" * 45 + "# gate: cheap\n")
        case("B: tier only after line 40 does not count: refused", 1, run(r))

        r = mk(10)
        g(r, "rm", "-q", "-f", "tools/check_a.sh")
        case("B: deleting the whole check: allowed", 0, run(r))

        r = mk(11)
        put(r, "tools/check_n.sh", "#!/bin/sh\necho\n")
        put(r, "tools/other.sh", "#!/bin/sh\n")
        case("B: new check and non-check files: allowed", 0, run(r))

        notrepo = os.path.join(work, "plain")
        os.makedirs(notrepo)
        case("not a repo: could not measure", 2, run(notrepo))
    finally:
        shutil.rmtree(work, ignore_errors=True)
    print()
    if fails[0]:
        print("SELFTEST FAIL: %d" % fails[0])
        return 1
    print("SELFTEST PASS")
    return 0


if __name__ == "__main__":
    if "--selftest" in sys.argv[1:]:
        sys.exit(selftest())
    sys.exit(main())
