#!/usr/bin/env python3
# gate: cheap --selftest
# fact: bead text (description, acceptance_criteria, notes, status) -- fake `bd` answering from JSON fixtures in a temp dir
# fact: commit messages on the bead branch -- scratch git repo built by --selftest with crafted messages
# fact: follow-up bead status -- fixture beads, one open and one closed
# fact: seed, character, map -- none read; this check never starts the game
"""Does a bead's branch carry evidence for every acceptance criterion?

    tools/check_bead_evidence.py <bead-id> <base-branch> [--repo <path>]
    tools/check_bead_evidence.py --selftest

WHY THIS EXISTS (inc-v4xe). tools/finish_bead.sh landed a bead whose
acceptance criteria nobody had verified. This check makes the landing refuse.

THE CONTRACT. The bead lists its acceptance criteria, in the description under
a line `## Acceptance Criteria` and/or in the `acceptance_criteria` field. They
number AC1, AC2, ... in that order. Each commit message on the bead's branch
(not a merge commit) MAY carry lines `AC<n>: <evidence>`. The newest commit's
line for a number wins.

A commit's `AC<n>:` lines count ONLY when its SUBJECT (first line of the
message) names the bead being landed as a whole id (`inc-abc` does not match
inside `inc-abcd`, `inc-abc.2` or `xinc-abc`). The body does not matter: a body
that mentions the bead does not make the commit count. A bead branch can carry
commits of another bead, such as a cherry-pick; their lines are ignored, even
an out-of-range number.

REFUSED (exit 1), every fault reported in one run:
  - a criterion has no `AC<n>:` line;
  - a line has under 10 characters of evidence, or numbers no criterion;
  - a line says not observed / traced only / unverified / not verified /
    untested / not tested / deferred / unobserved / not checked / unchecked /
    not run / skipped / reasoned only / not yet / todo, UNLESS it names another
    bead that is not closed AND whose description or notes hold the id of the
    bead being landed (a whole id), or it says `exception:` and the bead's notes hold a line that starts
    `AC<n> exception (Brian`.
A bead with no criteria passes. Ends: 0 pass, 1 refused, 2 could not measure.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

HEDGE = re.compile(
    r"not observed|traced only|unverified|not verified|untested|not tested|deferred"
    r"|unobserved|not checked|unchecked|not run|skipped|reasoned only|not yet|\btodo\b",
    re.I)
BEAD_ID = re.compile(r"inc-[0-9a-z]+(?:\.[0-9]+)*")
EVIDENCE = re.compile(r"^\s*AC(\d+):\s*(.+)$")
BULLET = re.compile(r"^(?:[-*]|\d+\.)\s+(.*)$")
MIN_EVIDENCE = 10


class Unmeasured(Exception):
    pass


def bd_show(bead, repo):
    try:
        p = subprocess.run(["bd", "show", bead, "--json"], cwd=repo,
                           capture_output=True, text=True)
    except OSError as e:
        raise Unmeasured("cannot run bd: %s" % e)
    if p.returncode != 0:
        raise Unmeasured("bd show %s failed (exit %d): %s"
                         % (bead, p.returncode, p.stderr.strip()))
    try:
        data = json.loads(p.stdout)
    except ValueError:
        raise Unmeasured("bd show %s printed non-JSON" % bead)
    if not isinstance(data, list) or not data or not isinstance(data[0], dict):
        raise Unmeasured("bd show %s returned no bead" % bead)
    return data[0]


def bullets(lines):
    """Top-level bullets; a non-blank non-bullet line continues the last one."""
    out = []
    for line in lines:
        m = BULLET.match(line)
        if m:
            out.append(m.group(1).strip())
        elif line.strip() and out:
            out[-1] += " " + line.strip()
    return out


def criteria_of(bead):
    crit = []
    section = []
    inside = False
    for line in (bead.get("description") or "").splitlines():
        if inside:
            if line.startswith("#"):
                break
            section.append(line)
        elif re.match(r"^## Acceptance Criteria\s*$", line):
            inside = True
    crit += bullets(section)
    field = (bead.get("acceptance_criteria") or "").strip()
    if field:
        found = bullets(field.splitlines())
        crit += found if found else [" ".join(field.split())]
    return crit


def names_bead(text, bead):
    """True when text holds bead as a whole id."""
    return re.search(r"(?<![0-9a-z-])%s(?![0-9a-z-]|\.[0-9])" % re.escape(bead),
                     text) is not None


def commit_lines(base, bead, repo):
    """Message lines of the non-merge commits in base..bead whose subject names bead, newest first."""
    p = subprocess.run(["git", "-C", repo, "log", "--no-merges", "--format=%B%x1e",
                        "%s..%s" % (base, bead)], capture_output=True, text=True)
    if p.returncode != 0:
        raise Unmeasured("git log %s..%s failed: %s" % (base, bead, p.stderr.strip()))
    lines = []
    for msg in p.stdout.split("\x1e"):
        if names_bead(msg.lstrip("\n").split("\n", 1)[0], bead):
            lines += msg.splitlines()
    return lines


def evaluate(bead_id, base, repo):
    """Return (exit code, stdout lines, stderr lines)."""
    try:
        bead = bd_show(bead_id, repo)
        crit = criteria_of(bead)
        if not crit:
            return 0, ["%s has no acceptance criteria; nothing to check" % bead_id], []
        evidence = {}
        faults = []
        for line in commit_lines(base, bead_id, repo):
            m = EVIDENCE.match(line)
            if not m:
                continue
            n = int(m.group(1))
            if n < 1 or n > len(crit):
                faults.append("AC%d: %s -- the bead has %d criteria, so AC%d numbers none"
                              % (n, m.group(2).strip(), len(crit), n))
            else:
                evidence.setdefault(n, m.group(2).strip())
        notes = (bead.get("notes") or "").splitlines()
        for n, text in enumerate(crit, 1):
            if n not in evidence:
                faults.append("AC%d: %s -- no AC%d: line in a commit message on %s "
                              "whose subject names %s" % (n, text, n, bead_id, bead_id))
                continue
            ev = evidence[n]
            if len(ev) < MIN_EVIDENCE:
                faults.append("AC%d: evidence %r is under %d characters" % (n, ev, MIN_EVIDENCE))
            if HEDGE.search(ev) and not excused(n, ev, bead_id, notes, repo):
                faults.append("AC%d: %r admits the criterion was not verified, and names "
                              "no open follow-up bead or recorded exception" % (n, ev))
        if faults:
            return 1, [], faults
        return 0, ["AC%d ok" % n for n in range(1, len(crit) + 1)], []
    except Unmeasured as e:
        return 2, [], [str(e)]


def excused(n, ev, bead_id, notes, repo):
    for other in BEAD_ID.findall(ev):
        if other == bead_id:
            continue
        b = bd_show(other, repo)
        if b.get("status") != "closed" and names_bead(
                (b.get("description") or "") + "\n" + (b.get("notes") or ""), bead_id):
            return True
    if "exception:" in ev.lower():
        pat = re.compile(r"^\s*AC%d exception \(Brian" % n)
        return any(pat.match(x) for x in notes)
    return False


# ---------------------------------------------------------------- selftest

def selftest():
    here = os.path.dirname(os.path.abspath(__file__))
    tmp = tempfile.mkdtemp(prefix="bead-evidence-selftest.")
    try:
        return run_cases(here, tmp)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def run_cases(here, tmp):
    fix = os.path.join(tmp, "fixtures")
    os.mkdir(fix)
    binp = os.path.join(tmp, "bin")
    os.mkdir(binp)
    fake = os.path.join(binp, "bd")
    with open(fake, "w") as f:
        f.write('#!/bin/sh\n[ "$1" = show ] && [ "$3" = --json ] && '
                '[ -f "$BD_FIXTURES/$2.json" ] && exec cat "$BD_FIXTURES/$2.json"\n'
                'echo "unknown bead" >&2\nexit 1\n')
    os.chmod(fake, 0o755)
    env = dict(os.environ, PATH=binp + os.pathsep + os.environ["PATH"],
               BD_FIXTURES=fix, GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1")
    repo = os.path.join(tmp, "repo")

    def git(*a):
        r = subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@t",
                            "-c", "commit.gpgsign=false", "-C", repo] + list(a),
                           capture_output=True, text=True, env=env)
        if r.returncode != 0:
            raise RuntimeError("git %s: %s" % (a, r.stderr))
    subprocess.run(["git", "init", "-q", repo], check=True, env=env)
    git("symbolic-ref", "HEAD", "refs/heads/master")
    git("commit", "-q", "--allow-empty", "-m", "base")

    def bead(bid, **kw):
        d = {"id": bid, "status": "open", "description": "", "notes": ""}
        d.update(kw)
        with open(os.path.join(fix, bid + ".json"), "w") as f:
            json.dump([d], f)

    def branch(bid, *msgs):
        git("checkout", "-q", "-b", bid, "master")
        for m in msgs:
            git("commit", "-q", "--allow-empty", "-m", m)

    def run(bid):
        r = subprocess.run([sys.executable, os.path.join(here, "check_bead_evidence.py"),
                            bid, "master", "--repo", repo],
                           capture_output=True, text=True, env=env)
        return r.returncode, r.stdout + r.stderr

    three = "## Acceptance Criteria\n- alpha works\n- beta works\n- gamma works\n"
    bead("inc-open", status="open")
    bead("inc-shut", status="closed")
    results = []

    def case(name, bid, code, needle):
        rc, out = run(bid)
        ok = rc == code and needle in out
        results.append(ok)
        print("%s  %s (exit %d, want %d%s)" % ("ok  " if ok else "FAIL", name, rc, code,
                                             "" if needle in out else "; %r not in output" % needle))
        if not ok:
            print("      " + out.strip().replace("\n", "\n      "))

    good = "fix: x (inc-t01)\n\nAC1: observed alpha in a seeded run\nAC2: observed beta in a seeded run\nAC3: observed gamma in a seeded run"
    bead("inc-t01", description=three); branch("inc-t01", good)
    case("1 all lines present", "inc-t01", 0, "AC3 ok")

    bead("inc-t02", description=three)
    branch("inc-t02", "x (inc-t02)\n\nAC1: observed alpha in a seeded run\nAC3: observed gamma in a seeded run")
    case("2 one line missing", "inc-t02", 1, "AC2: beta works")

    bead("inc-t03", description=three); branch("inc-t03", "no evidence here (inc-t03)")
    rc, out = run("inc-t03")
    ok = rc == 1 and all(s in out for s in ("alpha works", "beta works", "gamma works"))
    results.append(ok); print("%s  3 no AC lines names every criterion" % ("ok  " if ok else "FAIL"))

    one = "## Acceptance Criteria\n- alpha works\n"
    bead("inc-t04", description=one); branch("inc-t04", "x (inc-t04)\n\nAC1: not observed in any run")
    case("4 not observed, no follow-up", "inc-t04", 1, "not verified")

    bead("inc-open", status="open", description="follow-up for inc-t05")
    bead("inc-t05", description=one); branch("inc-t05", "x (inc-t05)\n\nAC1: Traced only, follow-up is inc-open")
    case("5 traced only, open follow-up", "inc-t05", 0, "AC1 ok")

    bead("inc-t06", description=one); branch("inc-t06", "x (inc-t06)\n\nAC1: unverified, follow-up was inc-shut")
    case("6 unverified, closed follow-up", "inc-t06", 1, "AC1")

    bead("inc-t07", description=one, notes="AC1 exception (Brian, 2026-10-26): no oracle")
    branch("inc-t07", "x (inc-t07)\n\nAC1: deferred, exception: Brian ruled in notes")
    case("7a deferred, exception with notes line", "inc-t07", 0, "AC1 ok")
    bead("inc-t07b", description=one, notes="nothing recorded")
    branch("inc-t07b", "x (inc-t07b)\n\nAC1: deferred, exception: Brian ruled in notes")
    case("7b deferred, exception without notes line", "inc-t07b", 1, "AC1")

    bead("inc-t08", description="plain text, no heading")
    branch("inc-t08", "x")
    case("8 no criteria anywhere", "inc-t08", 0, "no acceptance criteria")

    bead("inc-t09", acceptance_criteria="The whole sentence is one criterion.")
    branch("inc-t09", "x")
    case("9 plain-sentence field, line missing", "inc-t09", 1, "The whole sentence is one criterion.")

    bead("inc-t10", description=one)
    branch("inc-t10", "old (inc-t10)\n\nAC1: not observed yet", "new (inc-t10)\n\nAC1: observed alpha in a seeded run")
    case("10 newer AC1 overrides older", "inc-t10", 0, "AC1 ok")

    bead("inc-t11", description=one)
    branch("inc-t11", "work (inc-t11)")
    git("checkout", "-q", "-b", "side-t11", "master")
    git("commit", "-q", "--allow-empty", "-m", "side work")
    git("checkout", "-q", "inc-t11")
    git("merge", "-q", "--no-ff", "side-t11", "-m", "merge (inc-t11)\n\nAC1: observed alpha in a seeded run")
    case("11 merge commit does not count", "inc-t11", 1, "AC1: alpha works")

    bead("inc-t12", description=one); branch("inc-t12", "x")
    os.remove(os.path.join(fix, "inc-t12.json"))
    case("12 bd fails for the bead", "inc-t12", 2, "bd show inc-t12 failed")

    bead("inc-t13", description=three)
    branch("inc-t13", good.replace("inc-t01", "inc-t13") + "\nAC9: observed something unrelated")
    case("13 AC9 with three criteria", "inc-t13", 1, "AC9")

    wrapped = "## Acceptance Criteria\n- alpha works\n  and keeps working\n- beta works\n\n## Other\n- not a criterion\n"
    n = len(criteria_of({"description": wrapped}))
    bead("inc-t14", description=wrapped)
    branch("inc-t14", "x (inc-t14)\n\nAC1: observed alpha in a seeded run\nAC2: observed beta in a seeded run")
    rc, out = run("inc-t14")
    ok = n == 2 and rc == 0 and "AC2 ok" in out and "AC3" not in out
    results.append(ok); print("%s  14 wrapped bullet is one criterion (count %d)" % ("ok  " if ok else "FAIL", n))

    bead("inc-unrel", status="open", description="unrelated work")
    bead("inc-t16", description=one); branch("inc-t16", "x (inc-t16)\n\nAC1: not observed, see inc-unrel")
    case("16 hedge names open bead that omits the target", "inc-t16", 1, "AC1")

    bead("inc-near", status="open", description="follow-up for inc-t17x")
    bead("inc-t17", description=one); branch("inc-t17", "x (inc-t17)\n\nAC1: not observed, see inc-near")
    case("17 follow-up names a longer id only", "inc-t17", 1, "AC1")

    for i, w in enumerate(("unobserved", "not checked", "unchecked", "not run", "skipped",
                           "reasoned only", "not yet", "TODO"), 18):
        bid = "inc-t%d" % i
        bead(bid, description=one); branch(bid, "x (%s)\n\nAC1: alpha is %s here" % (bid, w))
        case("%d hedge word %r" % (i, w), bid, 1, "AC1")

    other = "x (inc-other)\n\nAC1: observed alpha in a seeded run\nAC2: observed beta in a seeded run\n" \
            "AC3: observed gamma in a seeded run\nAC4: observed delta in a seeded run\nAC5: observed more in a seeded run"
    two = "## Acceptance Criteria\n- alpha works\n- beta works\n"
    bead("inc-t30", description=two)
    branch("inc-t30", other, "own (inc-t30)\n\nAC1: observed alpha in a seeded run\nAC2: observed beta in a seeded run")
    case("30 other bead's lines ignored, even out of range", "inc-t30", 0, "AC2 ok")

    bead("inc-t31", description=two)
    branch("inc-t31", "x (inc-t31)", other)
    case("31 other bead's lines do not count as evidence", "inc-t31", 1, "AC1: alpha works")

    bead("inc-t32", description=one)
    branch("inc-t32", "x (inc-t32x)\n\nAC1: observed alpha in a seeded run")
    case("32 longer id does not match", "inc-t32", 1, "AC1: alpha works")

    bead("inc-t33", description=two)
    branch("inc-t33", "x (inc-other)\n\nfor inc-t33\n\nAC1: observed alpha in a seeded run\nAC2: observed beta in a seeded run\n"
           "AC3: observed gamma in a seeded run\nAC4: observed delta in a seeded run\nAC5: observed more in a seeded run",
           "own (inc-t33)\n\nAC1: observed alpha in a seeded run\nAC2: observed beta in a seeded run")
    case("33 other bead's subject, target in body only", "inc-t33", 0, "AC2 ok")

    bead("inc-t34", description=one)
    branch("inc-t34", "x\n\nfor inc-t34\n\nAC1: observed alpha in a seeded run")
    case("34 target only in a body", "inc-t34", 1, "AC1: alpha works")

    with open(os.path.join(here, "finish_bead.sh")) as f:
        wired = re.search(r'^"\$ROOT/tools/check_bead_evidence\.py" ', f.read(), re.M) is not None
    results.append(wired)
    print("%s  15 finish_bead.sh invokes check_bead_evidence.py" % ("ok  " if wired else "FAIL"))

    print("selftest: %d/%d passed" % (sum(results), len(results)))
    return 0 if all(results) else 1


def main(argv):
    if argv[1:] == ["--selftest"]:
        return selftest()
    repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    args = argv[1:]
    if "--repo" in args:
        i = args.index("--repo")
        if i + 1 >= len(args):
            print("--repo needs a path", file=sys.stderr)
            return 2
        repo = args[i + 1]
        del args[i:i + 2]
    if len(args) != 2:
        print(__doc__.split("WHY")[0].strip(), file=sys.stderr)
        return 2
    code, out, err = evaluate(args[0], args[1], repo)
    for line in out:
        print(line)
    for line in err:
        print(line, file=sys.stderr)
    return code


if __name__ == "__main__":
    sys.exit(main(sys.argv))
