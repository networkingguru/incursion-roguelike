#!/usr/bin/env python3
# gate: cheap --selftest
# fact: the game, a seed, a character -- none read; the check reads git and file text only
"""Refuse a commit that adds or changes a tools/check_* file whose fact lines
do not conform to docs/VERIFICATION.md "A check must not depend on the seed"
(inc-131k2).

Run by .beads/hooks/pre-commit on every commit, on every branch. Exit 0 pass,
1 refused (reasons on stderr), 2 could not measure.

Rules, per staged tools/check_* file (top level of tools/ only):
  R1  a fact line is required.
  R2  every fact line reads "fact -- control", both parts non-empty.
  R3  the control must not admit a hole ("none", "known hole", "pre-existing",
      "no control" unless "no control needed").
  R4  the control must not name a pinned seed, unless it names a bead id
      (a temporary crash reproduction) or says the check reads no seed.
  R5  a header line the owner has not approved cannot be added or changed.
A one-use pass file, minted by tools/fact_exempt_pass.py, lets one staged blob
through; the run that uses it deletes it.

Self-test: python3 tools/check_fact_lines.py --selftest
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

FACT_RE = re.compile(r"^\s*#\s*fact:(.*)$")
EXEMPT_RE = re.compile(r"^\s*#\s*fact-exempt:\s*(\S.*)$")
CHECK_RE = re.compile(r"^tools/check_[^/]+$")
SEED_RE = re.compile(r"(?<![-\w])seeds?\s*\d+|INCURSION_SEED\b(?!_)", re.I)
BEAD_RE = re.compile(r"\binc-[a-z0-9]+(\.\d+)*\b")
HOLE_RE = re.compile(r"known hole|pre-existing|no control(?! needed)")
NONE_FORMS = ("none read", "none;", "not read", "none,")

HINT = ("Close the hole as docs/VERIFICATION.md \"A check must not depend on "
        "the seed\" requires: add the control, file the missing hook, or choose "
        "a different scenario.")


class Unmeasurable(Exception):
    pass


def git(args, cwd=None, text=True):
    try:
        r = subprocess.run(["git"] + args, cwd=cwd, capture_output=True)
    except OSError as e:
        raise Unmeasurable("git failed: %s" % e)
    return r


def git_out(args, cwd=None):
    r = git(args, cwd)
    if r.returncode != 0:
        raise Unmeasurable("git %s failed: %s" % (" ".join(args),
                           r.stderr.decode("utf-8", "replace").strip()))
    return r.stdout.decode("utf-8", "replace")


def judge_control(control):
    """-> list of reason strings for one control, empty when it conforms."""
    out = []
    low = control.lower()
    if control.strip("*.; \t").lower() == "none" or HOLE_RE.search(low):
        out.append("control admits a hole (%r)" % control)
    if SEED_RE.search(control):
        if not BEAD_RE.search(control) and not low.startswith(NONE_FORMS):
            out.append("control names a pinned seed (%r)" % control)
    return out


def judge(path, text, head_text):
    """-> list of 'path:line: reason' for one file's staged text."""
    reasons = []
    facts, exempt = [], set()
    for n, line in enumerate(text.splitlines(), 1):
        m = FACT_RE.match(line)
        if m:
            facts.append((n, m.group(1).rstrip()))
        if EXEMPT_RE.match(line):
            exempt.add(line.strip())
    if exempt:
        old = set()
        if head_text is not None:
            old = {l.strip() for l in head_text.splitlines() if EXEMPT_RE.match(l)}
        if exempt != old:
            reasons.append("%s:1: header change not accepted" % path)
        return reasons
    if not facts:
        return ["%s:1: no fact line (\"# fact: <fact> -- <control>\")" % path]
    for n, body in facts:
        if " -- " not in body:
            reasons.append("%s:%d: fact line lacks \" -- \" between fact and control" % (path, n))
            continue
        fact, control = (s.strip() for s in body.split(" -- ", 1))
        if not fact or not control:
            reasons.append("%s:%d: fact or control is empty" % (path, n))
            continue
        for why in judge_control(control):
            reasons.append("%s:%d: %s" % (path, n, why))
    return reasons


def main():
    try:
        git_out(["rev-parse", "--git-dir"])
        merge_head = git_out(["rev-parse", "--git-path", "MERGE_HEAD"]).strip()
        # ponytail: a merge commit's checks were judged at the commit that
        # changed them; judging them again would refuse every merge of
        # pre-guard history. Ceiling: a check edited inside a merge's conflict
        # resolution is not read. Upgrade: diff against the first parent.
        if os.path.exists(os.path.abspath(merge_head)):
            return 0
        common = git_out(["rev-parse", "--git-common-dir"]).strip()
        passdir = os.path.join(os.path.abspath(common), "fact-exempt")
        names = git_out(["diff", "--cached", "--name-only", "-z",
                         "--diff-filter=ACMR"]).split("\0")
        paths = [p for p in names if CHECK_RE.match(p)]
        reasons, used = [], []
        for p in paths:
            text = git_out(["show", ":" + p])
            hr = git(["show", "HEAD:" + p])
            head = hr.stdout.decode("utf-8", "replace") if hr.returncode == 0 else None
            why = judge(p, text, head)
            if not why:
                continue
            sha = git_out(["rev-parse", ":" + p]).strip()
            ticket = os.path.join(passdir, sha)
            if os.path.isfile(ticket):
                used.append(ticket)
            else:
                reasons.extend(why)
    except Unmeasurable as e:
        print("check_fact_lines: could not measure: %s" % e, file=sys.stderr)
        return 2
    if reasons:
        print("check_fact_lines: REFUSED.", file=sys.stderr)
        for r in reasons:
            print("  " + r, file=sys.stderr)
        print(HINT, file=sys.stderr)
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
    work = tempfile.mkdtemp(prefix="factlines")
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    fails = [0]
    count = [0]

    def g(repo, *a):
        return subprocess.run(["git"] + list(a), cwd=repo, env=env,
                              capture_output=True, text=True)

    def mk():
        count[0] += 1
        repo = os.path.join(work, "r%d" % count[0])
        os.makedirs(repo)
        g(repo, "init", "-q")
        for k, v in (("user.email", "t@t"), ("user.name", "t"),
                     ("commit.gpgsign", "false"),
                     ("core.hooksPath", os.path.join(repo, ".git", "hooks"))):
            g(repo, "config", k, v)
        return repo

    def put(repo, rel, content, stage=True):
        full = os.path.join(repo, rel)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "w") as f:
            f.write(content)
        if stage:
            g(repo, "add", rel)

    def commit(repo):
        r = g(repo, "commit", "-q", "--no-verify", "-m", "x")
        assert r.returncode == 0, r.stderr

    def run(repo):
        r = subprocess.run([sys.executable, me], cwd=repo, env=env,
                           capture_output=True, text=True)
        return r.returncode, r.stderr

    def blob(repo, rel):
        return g(repo, "rev-parse", ":" + rel).stdout.strip()

    def passfile(repo, rel):
        return os.path.join(repo, ".git", "fact-exempt", blob(repo, rel))

    def mkpass(repo, rel):
        p = passfile(repo, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w") as f:
            f.write(rel + "\n")
        return p

    def case(label, want, got):
        ok = got == want
        print("  %s  %s" % ("ok  " if ok else "FAIL", label)
              + ("" if ok else " (got %s, wanted %s)" % (got, want)))
        if not ok:
            fails[0] += 1

    def hdr(control):
        return "#!/bin/sh\n# fact: the thing -- " + control + "\n"

    good = hdr("INCURSION_FORCE_SAVE_ROLL=1")
    CK = "tools/check_x.sh"
    ex = lambda why: "#!/bin/sh\n# fact-exempt: " + why + "\n"

    controls = [
        ("control 'none'", "none", 1),
        ("control '*none*'", "*none*", 1),
        ("control 'known hole: no fixture'", "known hole: no fixture", 1),
        ("control 'pre-existing'", "pre-existing", 1),
        ("control 'no control'", "no control", 1),
        ("control 'seed 4242'", "seed 4242", 1),
        ("control 'INCURSION_SEED=7'", "INCURSION_SEED=7", 1),
        ("control 'seed 2, re-pin authorized by inc-rt8l'",
         "seed 2, re-pin authorized by inc-rt8l", 0),
        ("fixture name with seed1 inside",
         "orc-mage-seed1-opt0822 (INCURSION_LOAD)", 0),
        ("control 'none read'", "none read", 0),
        ("control 'none; the self-check compares every call'",
         "none; the self-check compares every call", 0),
        ("control 'no control needed: D is read from the game'",
         "no control needed: D is read from the game", 0),
        ("control 'no game run'", "no game run", 0),
    ]
    try:
        for label, control, want in controls:
            repo = mk()
            put(repo, CK, hdr(control))
            case(label, want, run(repo)[0])

        repo = mk()
        put(repo, CK, "#!/bin/sh\necho hi\n")
        case("no fact line", 1, run(repo)[0])

        repo = mk()
        put(repo, CK, "#!/bin/sh\n# fact: the thing\n")
        case("fact line without ' -- '", 1, run(repo)[0])

        repo = mk()
        put(repo, CK, "#!/bin/sh\n# fact:  -- ctl\n")
        case("empty fact", 1, run(repo)[0])

        repo = mk()
        put(repo, CK, "#!/bin/sh\n# fact: a -- \n")
        case("empty control", 1, run(repo)[0])

        repo = mk()
        put(repo, CK, "#!/bin/sh\n# fact: a -- fixture f\n# fact: b -- none\n")
        case("second fact line bad", 1, run(repo)[0])

        repo = mk()
        put(repo, CK, "#!/bin/sh\necho hi\n")
        commit(repo)
        put(repo, "README", "touch\n")
        case("committed non-conforming check, untouched by next commit", 0, run(repo)[0])

        repo = mk()
        put(repo, "tools/sub/check_x.sh", "#!/bin/sh\necho hi\n")
        case("tools/sub/check_x.sh is not read", 0, run(repo)[0])

        repo = mk()
        put(repo, "tools/foo.sh", "#!/bin/sh\necho hi\n")
        case("non-check tools/foo.sh with no fact line", 0, run(repo)[0])

        repo = mk()
        put(repo, CK, "#!/bin/sh\necho hi\n", stage=False)
        put(repo, CK, "#!/bin/sh\necho hi\n")
        put(repo, CK, good, stage=False)
        case("staged content judged, not working tree", 1, run(repo)[0])

        repo = mk()
        put(repo, CK, ex("reason"))
        case("new file with exempt line, no pass", 1, run(repo)[0])

        repo = mk()
        put(repo, CK, ex("reason"))
        p = mkpass(repo, CK)
        case("same plus pass for its blob", 0, run(repo)[0])
        case("  pass file consumed", False, os.path.exists(p))
        commit(repo)
        put(repo, CK, ex("another reason"))
        case("next commit changes the exempt line, no pass", 1, run(repo)[0])

        repo = mk()
        put(repo, CK, ex("reason"))
        commit(repo)
        put(repo, CK, ex("reason") + "echo more\n")
        case("exempt line unchanged at HEAD, file otherwise changed", 0, run(repo)[0])

        repo = mk()
        put(repo, CK, "#!/bin/sh\necho hi\n")
        p = mkpass(repo, CK)
        case("non-conforming file with a pass", 0, run(repo)[0])
        case("  pass file consumed", False, os.path.exists(p))

        repo = mk()
        put(repo, CK, "#!/bin/sh\necho hi\n")
        put(repo, "tools/check_other.sh", "#!/bin/sh\necho other\n")
        p = mkpass(repo, "tools/check_other.sh")
        case("a pass for a different blob does not help", 1, run(repo)[0])
        case("  other pass left alone", True, os.path.exists(p))

        repo = mk()
        put(repo, CK, "#!/bin/sh\necho hi\n")
        with open(os.path.join(repo, ".git", "MERGE_HEAD"), "w") as f:
            f.write("0" * 40 + "\n")
        case("MERGE_HEAD present", 0, run(repo)[0])

        repo = mk()
        put(repo, CK, "#!/bin/sh\necho hi\n")
        rc, err = run(repo)
        low = err.lower()
        case("refusal stderr names the file", True, CK in err)
        case("refusal stderr has no 'exempt'", False, "exempt" in low or "pass" in low)
        repo = mk()
        put(repo, CK, ex("reason"))
        case("R5 refusal stderr has no 'exempt'", False,
             "exempt" in run(repo)[1].lower())

        case("not a git repo exits 2", 2,
             subprocess.run([sys.executable, me], cwd=work, env=env,
                            capture_output=True).returncode)

        # End to end: a real git commit through a real pre-commit hook.
        repo = mk()
        hook = os.path.join(repo, ".git", "hooks", "pre-commit")
        os.makedirs(os.path.dirname(hook), exist_ok=True)
        with open(hook, "w") as f:
            f.write('#!/bin/sh\nexec "%s" "%s"\n' % (sys.executable, me))
        os.chmod(hook, 0o755)
        put(repo, CK, "#!/bin/sh\necho hi\n")
        case("end to end: git commit of non-conforming check refused", True,
             g(repo, "commit", "-q", "-m", "x").returncode != 0)
        put(repo, CK, good)
        case("end to end: git commit of conforming check succeeds", 0,
             g(repo, "commit", "-q", "-m", "x").returncode)
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
