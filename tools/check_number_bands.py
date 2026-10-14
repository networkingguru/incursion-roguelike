#!/usr/bin/env python3
# gate: none static but needs a git repository and a band table; run via
#           .beads/hooks/pre-commit and tools/fast_checks.sh, not the gate
"""Refuse a staged inc/Defines.h that adds a covered constant badly (inc-24cc).

Spec: docs/specs/2026-10-13-number-bands-brief.md

Families and band selection come from tools/next_number.sh / number_bands.py:
every "#define NAME <int>" between GENERIC_STATI and LAST_STATI is a STATI
member, every "#define EV_<NAME> <int>" is an EV member, and a branch's band is
master's row for master or nightly/*, else a row named for the branch, else the
first row found along the branch.<branch>.incursionBase chain (at most 10 hops,
stopping on a repeated name; the first branch in the chain that is master or has
a row wins). When no band can be proved (a detached HEAD, or a branch with no row
and no usable base chain) a new in-scope member is refused rather than measured
against master.

A member is IN SCOPE when its value is >= FLOOR(its family), the lowest `low`
of that family's rows (STATI 243, EV 221 today).

ponytail: the floor is a value test, not a name test. The STATI line range
also holds small non-stati constants (flag values, COMPEL_WALK_STUCK_TURNS 50),
and EV holds old by-value aliases (EV_WIELD/EV_PUTON/EV_WEAR = 13); the floor
keeps them out, but a NEW define given a number below the floor escapes the
check. Upgrade path: key STATI on the src/Tables.cpp stati name table, and
grandfather the old EV aliases by name.

Exit codes: 0 pass, 1 refused, 2 could not measure (no band table, no git,
unparseable). Never 1 for a measurement failure.
"""

import os
import re
import subprocess
import sys

SELF_DIR = os.path.dirname(os.path.abspath(__file__))
if SELF_DIR not in sys.path:
    sys.path.insert(0, SELF_DIR)

import number_bands  # noqa: E402

FAMILIES = ("STATI", "EV")
DEFINES_REL = "inc/Defines.h"
RES_REL = "inc/Res.h"

FAMILY_PARSER = {
    "STATI": number_bands.parse_stati,
    "EV": number_bands.parse_events,
}

BAND_RE = re.compile(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s+(\S+)\s+([0-9]+)\s+([0-9]+)\s*$")

REFUSAL_FIX = "get a number with tools/next_number.sh %s %s"

# Returned as the band_branch when no band can be proved.
BAND_UNKNOWN = "<no band>"
# Returned as the band_branch when the family has rows but the chosen band
# branch has none: the allocator refuses this (exit 2, "no <FAMILY> band row for
# master"), so the checker must refuse it too rather than pass silently.
BAND_NO_ROW = "<no band row>"


class CouldNotMeasure(Exception):
    """A measurement failure; the caller reports it and exits 2."""


def run_git(args, cwd=None):
    """Return (rc, stdout_text). rc is None when git could not be run."""
    try:
        p = subprocess.run(
            ["git"] + args,
            cwd=cwd,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        )
    except OSError:
        return None, ""
    return p.returncode, p.stdout.decode("utf-8", "replace")


def git_text_or_fail(args, cwd=None, what=""):
    rc, out = run_git(args, cwd=cwd)
    if rc is None:
        raise CouldNotMeasure("git could not be run")
    if rc != 0:
        raise CouldNotMeasure("git %s failed%s" % (" ".join(args), ": " + what if what else ""))
    return out


def load_bands(path):
    """Parse the band table into {family: [(branch, low, high), ...]}."""
    if not os.path.isfile(path):
        raise CouldNotMeasure("no band table at %s" % path)
    rows = {}
    try:
        with open(path, "r", encoding="utf-8") as fh:
            lines = fh.readlines()
    except OSError as exc:
        raise CouldNotMeasure("cannot read band table %s: %s" % (path, exc))
    for raw in lines:
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        m = BAND_RE.match(line)
        if not m:
            raise CouldNotMeasure("unparseable band row: %r" % line)
        fam, branch, low, high = m.group(1), m.group(2), int(m.group(3)), int(m.group(4))
        rows.setdefault(fam, []).append((branch, low, high))
    if not rows:
        raise CouldNotMeasure("band table %s has no rows" % path)
    return rows


def floor_of(rows, family):
    """Lowest `low` across the family's rows, or None when it has none."""
    fam_rows = rows.get(family)
    if not fam_rows:
        return None
    return min(low for (_branch, low, _high) in fam_rows)


def branch_band(rows, family, branch, config_get):
    """Return (band_branch, low, high) by next_number.sh's rules.

    Returns (None, None, None) three ways, told apart by the sentinel:
      - BAND_UNKNOWN: the band cannot be proved (detached HEAD, or a branch with
        no row and no usable base chain);
      - BAND_NO_ROW: the family has rows, but the band branch the rules chose
        (master or a chain base) has no row for it. The allocator refuses this
        with exit 2, so it is not the same as having no rows at all;
      - a plain (None, None, None): the family has no rows at all.
    """
    if not branch or branch == "HEAD":
        return BAND_UNKNOWN, None, None
    if branch == "master" or branch.startswith("nightly/"):
        chosen = "master"
    else:
        chosen = None
        for (row_branch, _low, _high) in rows.get(family, []):
            if row_branch == branch:
                chosen = branch
                break
        if chosen is None:
            # Follow the incursionBase chain. Take the first branch that is
            # master or has a row for this family. Stop after 10 hops or on a
            # repeat.
            cand = branch
            seen = set()
            hops = 0
            while hops < 10:
                base = config_get("branch.%s.incursionBase" % cand)
                if not base or base in seen:
                    break
                seen.add(base)
                if base == "master":
                    chosen = "master"
                    break
                for (row_branch, _low, _high) in rows.get(family, []):
                    if row_branch == base:
                        chosen = base
                        break
                if chosen is not None:
                    break
                cand = base
                hops += 1
        if chosen is None:
            return BAND_UNKNOWN, None, None
    for (row_branch, low, high) in rows.get(family, []):
        if row_branch == chosen:
            return chosen, low, high
    if rows.get(family):
        return BAND_NO_ROW, None, None
    return None, None, None


def members(text, family):
    """[(value, name), ...] for a family, via the phase-1 parser."""
    return FAMILY_PARSER[family](text)


def in_scope(rows, family, pairs):
    """The (value, name) pairs at or above the family floor."""
    floor = floor_of(rows, family)
    if floor is None:
        raise CouldNotMeasure("no %s rows in the band table" % family)
    return [(v, n) for (v, n) in pairs if v >= floor]


def new_members(index_pairs, head_pairs):
    """(value, name) in the index that is not a (value, name) in HEAD.

    A renamed or renumbered define therefore counts as new.
    """
    head_set = set(head_pairs)
    return [(v, n) for (v, n) in index_pairs if (v, n) not in head_set]


def parse_issued(path):
    """Set of (family, value, name) triples in issued.log."""
    issued = set()
    if not os.path.isfile(path):
        return issued
    try:
        with open(path, "r", encoding="utf-8") as fh:
            for line in fh:
                fields = line.split()
                if len(fields) < 3:
                    continue
                fam, value, name = fields[0], fields[1], fields[2]
                if value.isdigit():
                    issued.add((fam, int(value), name))
    except OSError:
        return issued
    return issued


def numbers_dir(cwd):
    env = os.environ.get("INCURSION_NUMBERS_DIR")
    if env:
        return env
    common = git_text_or_fail(["rev-parse", "--git-common-dir"], cwd=cwd)
    common = common.strip()
    if not common:
        raise CouldNotMeasure("empty git-common-dir")
    if not os.path.isabs(common):
        common = os.path.join(cwd, common)
    return os.path.join(common, "incursion-numbers")


def config_getter(cwd):
    def get(key):
        rc, out = run_git(["config", "--get", key], cwd=cwd)
        if rc != 0:
            return ""
        return out.strip()
    return get


def check_staged(cwd, rows, table_path):
    """Mode --staged: index vs HEAD, rules 1-3. Returns (rc, lines)."""
    # Exit 0 at once when Defines.h is not staged.
    rc, _out = run_git(["diff", "--cached", "--name-only", "--", DEFINES_REL], cwd=cwd)
    if rc is None:
        raise CouldNotMeasure("git could not be run")
    if rc != 0:
        raise CouldNotMeasure("git diff --cached failed")
    # Re-list explicitly: --name-only above returns names; check membership.
    rc2, names = run_git(["diff", "--cached", "--name-only"], cwd=cwd)
    if rc2 != 0:
        raise CouldNotMeasure("git diff --cached failed")
    if DEFINES_REL not in names.split():
        return 0, []

    index_text = git_text_or_fail(["show", ":%s" % DEFINES_REL], cwd=cwd)
    head_text = git_text_or_fail(["show", "HEAD:%s" % DEFINES_REL], cwd=cwd)

    res_text = git_text_or_fail(["show", ":%s" % RES_REL], cwd=cwd)
    width = number_bands.nature_width(res_text)
    if width is None:
        raise CouldNotMeasure("no Nature bitfield in index %s" % RES_REL)

    git_dir = git_text_or_fail(["rev-parse", "--absolute-git-dir"], cwd=cwd).strip()
    merge_in_progress = bool(git_dir) and os.path.exists(os.path.join(git_dir, "MERGE_HEAD"))

    if merge_in_progress:
        return check_merge(cwd, rows, index_text, width)

    branch = git_text_or_fail(["rev-parse", "--abbrev-ref", "HEAD"], cwd=cwd).strip()
    get = config_getter(cwd)
    issued_path = os.path.join(numbers_dir(cwd), "issued.log")
    issued = parse_issued(issued_path)

    lines = []
    refused = False

    for family in FAMILIES:
        if family not in rows:
            continue
        scope = in_scope(rows, family, members(index_text, family))
        new = new_members(members(index_text, family), members(head_text, family))
        new_scope = [(v, n) for (v, n) in new if (v, n) in set(scope)]

        band_branch, low, high = branch_band(rows, family, branch, get)

        if band_branch == BAND_UNKNOWN:
            # rule 2 still runs: any in-scope duplicate in the index.
            if new_scope:
                lines.append(no_band_refusal(branch))
                refused = True
                by_value = {}
                for v, n in scope:
                    by_value.setdefault(v, []).append(n)
                for v, name in new_scope:
                    if family == "STATI" and v > 2 ** width - 1:
                        lines.append(width_refusal(name, v, width))
                        refused = True
                    others = [n for n in by_value.get(v, []) if n != name]
                    if others:
                        lines.append(duplicate_refusal(
                            family, name, v, ", ".join(sorted(others))))
                        refused = True
            continue
        if band_branch == BAND_NO_ROW:
            # The family has rows, but the chosen band branch has none: the
            # allocator refuses this with exit 2, so refuse a new member too
            # rather than pass silently.
            if new_scope:
                lines.append(no_row_refusal(family, branch))
                refused = True
            continue
        if low is None:
            continue

        # rule 2: any in-scope duplicate of the same value in the index.
        by_value = {}
        for v, n in scope:
            by_value.setdefault(v, []).append(n)

        for v, name in new_scope:
            if family == "STATI" and v > 2 ** width - 1:
                lines.append(width_refusal(name, v, width))
                refused = True
            if v < low or v > high:
                lines.append(refusal(family, name, v, band_branch, low, high,
                                     "outside the %s band %d-%d" % (family, low, high)))
                refused = True
            others = [n for n in by_value.get(v, []) if n != name]
            if others:
                lines.append(refusal(
                    family, name, v, band_branch, low, high,
                    "also used by %s in the index" % ", ".join(sorted(others))))
                refused = True
            if (family, v, name) not in issued:
                lines.append(refusal(family, name, v, band_branch, low, high,
                                     "not in issued.log"))
                refused = True

    return (1 if refused else 0), lines


def check_merge(cwd, rows, index_text, width):
    """Merge in progress: the width rule and rule 2, over the whole index."""
    lines = []
    refused = False
    for family in FAMILIES:
        if family not in rows:
            continue
        scope = in_scope(rows, family, members(index_text, family))
        by_value = {}
        for v, n in scope:
            by_value.setdefault(v, []).append(n)
        for v, names in sorted(by_value.items()):
            if family == "STATI" and v > 2 ** width - 1:
                for name in sorted(names):
                    lines.append(width_refusal(name, v, width))
                refused = True
            if len(names) > 1:
                refused = True
                lines.append(
                    "DUPLICATE: %s value %d is used by %s in the index (merge)"
                    % (family, v, ", ".join(sorted(names))))
    return (1 if refused else 0), lines


def width_refusal(name, value, width):
    return (
        "REFUSED: STATI %s = %d exceeds the %d-bit Nature field in %s "
        "(max %d); a master stati MUST fit 8 bits. Fix: %s"
        % (name, value, width, RES_REL, 2 ** width - 1, REFUSAL_FIX % ("STATI", name))
    )


def refusal(family, name, value, band_branch, low, high, why):
    return (
        "REFUSED: %s %s = %d is %s. Band %s %d-%d (branch %s). "
        "Fix: %s" % (
            family, name, value, why, family, low, high, band_branch,
            REFUSAL_FIX % (family, name),
        )
    )


def duplicate_refusal(family, name, value, others):
    return (
        "REFUSED: %s %s = %d is also used by %s in the index. "
        "Fix: %s" % (
            family, name, value, others, REFUSAL_FIX % (family, name),
        )
    )


def no_band_refusal(branch):
    if branch == "HEAD":
        return "REFUSED: detached HEAD; check out the bead's branch"
    return (
        "REFUSED: branch '%s' has no band and no recorded base; record one with: "
        "git config branch.%s.incursionBase <base-branch>" % (branch, branch)
    )


def no_row_refusal(family, branch):
    return (
        "REFUSED: no %s band row for the branch '%s' selects; the allocator "
        "refuses this, so add a %s row for that branch to the band table"
        % (family, branch, family)
    )


def check_tree(cwd, rows, text, width):
    """Mode --tree: the width rule and an in-scope duplicate over the tree.

    width is None when no inc/Res.h was measured: the width rule is skipped and
    the caller has said so on stderr.
    """
    lines = []
    refused = False
    for family in FAMILIES:
        if family not in rows:
            continue
        scope = in_scope(rows, family, members(text, family))
        if family == "STATI" and width is not None:
            for v, name in scope:
                if v > 2 ** width - 1:
                    lines.append(width_refusal(name, v, width))
                    refused = True
        by_value = {}
        for v, n in scope:
            by_value.setdefault(v, []).append(n)
        for v, names in sorted(by_value.items()):
            if len(names) > 1:
                refused = True
                lines.append(
                    "REFUSED: %s value %d is used by %s in the working tree" % (
                        family, v, ", ".join(sorted(names))))
    return (1 if refused else 0), lines


# --- selftest ---------------------------------------------------------------

SELFTEST_DEFINES = """\
#define GENERIC_STATI 0
#define SICKNESS 1
#define POISONED 2
#define BLINDNESS 3
#define BLIND 3
#define SLEEP_MAGIC 1
#define SLEEP_NATURAL 2
#define AGG_MON 8
#define LAST_STATI 5
#define EV_MOVE 1
#define EV_BREAK 2
#define EV_WIELD 13
#define EV_PUTON 13
#define EV_WEAR 13
#define EV_ALIAS EV_MOVE
"""

SELFTEST_RES_8 = """\
struct Status
{
  unsigned int Nature :8;
  signed int Val      :16;
};
"""

SELFTEST_RES_16 = SELFTEST_RES_8.replace("Nature :8", "Nature :16")

SELFTEST_RES_NONE = """\
struct Status
{
  signed int Val      :16;
};
"""


def _write(path, text):
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)


def selftest():
    import shutil
    import tempfile

    tmp = tempfile.mkdtemp(prefix="check-number-bands-selftest.")
    fails = 0
    passed = 0

    def case(ok, what, detail=""):
        nonlocal fails, passed
        if ok:
            passed += 1
            print("PASS: %s" % what)
        else:
            fails += 1
            print("FAIL: %s %s" % (what, detail))

    try:
        repo = os.path.join(tmp, "repo")
        numdir = os.path.join(tmp, "nums")
        bands = os.path.join(tmp, "bands.txt")
        os.makedirs(os.path.join(repo, "inc"))
        os.makedirs(numdir)
        shutil.copy(os.path.join(SELF_DIR, "number_bands.txt"), bands)

        def git(*args, cwd=repo):
            return subprocess.run(["git"] + list(args), cwd=cwd,
                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode

        _write(os.path.join(repo, DEFINES_REL), SELFTEST_DEFINES)
        _write(os.path.join(repo, RES_REL), SELFTEST_RES_8)
        if git("init", "-q", "-b", "master") != 0 or git("add", "-A") != 0 or \
                git("-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "init") != 0:
            print("selftest: repo setup failed")
            return 1

        env = dict(os.environ)
        env["INCURSION_NUMBER_BANDS"] = bands
        env["INCURSION_NUMBERS_DIR"] = numdir
        env.pop("INCURSION_NUMBER_BANDS_OK", None)

        def run(args, cwd=repo, extra_env=None):
            e = dict(env)
            if extra_env:
                e.update(extra_env)
            p = subprocess.run([sys.executable, "-I", os.path.abspath(__file__)] + list(args),
                               cwd=cwd, env=e,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            return p.returncode, p.stdout.decode("utf-8", "replace")

        def stage(mutator):
            _write(os.path.join(repo, DEFINES_REL), SELFTEST_DEFINES)
            text = open(os.path.join(repo, DEFINES_REL)).read()
            text = mutator(text)
            _write(os.path.join(repo, DEFINES_REL), text)
            git("add", DEFINES_REL)

        def unstage():
            git("reset", "-q", DEFINES_REL)

        # The band table's STATI master is 243-255; EV master 301-499.
        # A legal new stati: value 250, issued, unique, and within 8 bits.
        _write(os.path.join(numdir, "issued.log"), "STATI 250 NEWSTATI master t\n")
        stage(lambda t: t.replace("#define LAST_STATI 5",
                                  "#define NEWSTATI 250\n#define LAST_STATI 251"))
        rc, out = run(["--staged"])
        case(rc == 0, "legal new stati passes", "(rc=%d)\n%s" % (rc, out))
        unstage()

        # master has no STATI row for the family (scratch table): a new member
        # must be refused, consistent with the allocator's exit 2, rather than
        # pass silently.
        scratch_bands = os.path.join(tmp, "scratch-bands.txt")
        _write(scratch_bands, "STATI other 243 255\nEV master 301 499\n")
        _write(os.path.join(numdir, "issued.log"), "")
        stage(lambda t: t.replace("#define LAST_STATI 5",
                                  "#define NOROW 250\n#define LAST_STATI 251"))
        rc, out = run(["--staged"], extra_env={"INCURSION_NUMBER_BANDS": scratch_bands})
        case(rc == 1 and "no STATI band row" in out,
             "master with no family row refuses the new member", "(rc=%d)\n%s" % (rc, out))
        unstage()

        # outside band -> refused. EV master is 301-499, so 500 is at or above
        # the family floor (221) yet above the band.
        _write(os.path.join(numdir, "issued.log"), "EV 500 OOB master t\n")
        stage(lambda t: t + "#define EV_OOB 500\n")
        rc, out = run(["--staged"])
        case(rc == 1 and "outside" in out, "outside band refused", "(rc=%d)\n%s" % (rc, out))
        unstage()

        # duplicate value -> refused
        _write(os.path.join(numdir, "issued.log"), "STATI 250 DUPED master t\n")
        stage(lambda t: t.replace("#define LAST_STATI 5",
                                  "#define DUPED 250\n#define SENESCHAL_ONLY 250\n#define LAST_STATI 251"))
        rc, out = run(["--staged"])
        case(rc == 1 and "also used by" in out, "duplicate value refused", "(rc=%d)\n%s" % (rc, out))
        unstage()

        # not in issued.log -> refused
        _write(os.path.join(numdir, "issued.log"), "")
        stage(lambda t: t.replace("#define LAST_STATI 5",
                                  "#define UNISSUED 251\n#define LAST_STATI 252"))
        rc, out = run(["--staged"])
        case(rc == 1 and "not in issued.log" in out, "not issued refused", "(rc=%d)\n%s" % (rc, out))
        unstage()

        # a new EV alias written by name passes with no issued line.
        _write(os.path.join(numdir, "issued.log"), "")
        stage(lambda t: t + "#define EV_X EV_MOVE\n")
        rc, out = run(["--staged"])
        case(rc == 0, "EV alias by name passes", "(rc=%d)\n%s" % (rc, out))
        unstage()

        # small flag dups below the floor, and a by-value EV alias below floor,
        # do not refuse.
        _write(os.path.join(numdir, "issued.log"), "")
        stage(lambda t: t + "#define FLAG_B 3\n#define EV_Y 13\n")
        rc, out = run(["--staged"])
        case(rc == 0, "below-floor dups do not refuse", "(rc=%d)\n%s" % (rc, out))
        unstage()

        # the master high stati, 255, is issued, unique and fits 8 bits -> pass.
        _write(os.path.join(numdir, "issued.log"), "STATI 255 EDGE master t\n")
        stage(lambda t: t.replace("#define LAST_STATI 5",
                                  "#define EDGE 255\n#define LAST_STATI 256"))
        rc, out = run(["--staged"])
        case(rc == 0, "staged master stati 255 passes", "(rc=%d)\n%s" % (rc, out))
        unstage()

        # 256 does not fit 8 bits and is outside the band -> refused for both.
        _write(os.path.join(numdir, "issued.log"), "STATI 256 TOOBIG master t\n")
        stage(lambda t: t.replace("#define LAST_STATI 5",
                                  "#define TOOBIG 256\n#define LAST_STATI 257"))
        rc, out = run(["--staged"])
        case(rc == 1 and "Nature" in out and "outside" in out,
             "staged master stati 256 refused (width and band)", "(rc=%d)\n%s" % (rc, out))
        unstage()

        # merge: unique and within 8 bits passes; a >255 stati is refused for
        # width, a duplicate for rule 2.
        gitdir = subprocess.run(["git", "rev-parse", "--absolute-git-dir"], cwd=repo,
                                stdout=subprocess.PIPE).stdout.decode().strip()
        stage(lambda t: t.replace("#define LAST_STATI 5",
                                  "#define MERGED 250\n#define LAST_STATI 251"))
        _write(os.path.join(gitdir, "MERGE_HEAD"), "0" * 40 + "\n")
        rc, out = run(["--staged"])
        case(rc == 0, "merge unique in-width passes", "(rc=%d)\n%s" % (rc, out))
        stage(lambda t: t.replace("#define LAST_STATI 5",
                                  "#define MERGED 300\n#define LAST_STATI 301"))
        rc, out = run(["--staged"])
        case(rc == 1 and "Nature" in out, "merge too-wide stati refused", "(rc=%d)\n%s" % (rc, out))
        stage(lambda t: t.replace("#define LAST_STATI 5",
                                  "#define MERGED 250\n#define MERGED2 250\n#define LAST_STATI 251"))
        rc, out = run(["--staged"])
        case(rc == 1 and "DUPLICATE" in out, "merge duplicate refused", "(rc=%d)\n%s" % (rc, out))
        os.remove(os.path.join(gitdir, "MERGE_HEAD"))
        unstage()

        # --tree passes on a clean file and refuses an in-scope duplicate.
        _write(os.path.join(repo, DEFINES_REL), SELFTEST_DEFINES)
        rc, out = run(["--tree"])
        case(rc == 0, "--tree clean passes", "(rc=%d)\n%s" % (rc, out))
        _write(os.path.join(repo, DEFINES_REL),
               SELFTEST_DEFINES.replace("#define LAST_STATI 5",
                                        "#define T1 250\n#define T2 250\n#define LAST_STATI 251"))
        rc, out = run(["--tree"])
        case(rc == 1 and "T1" in out and "T2" in out, "--tree duplicate refused",
             "(rc=%d)\n%s" % (rc, out))

        # --tree width rule: 300 is refused with an 8-bit Res.h, passes with 16.
        _write(os.path.join(repo, DEFINES_REL),
               SELFTEST_DEFINES.replace("#define LAST_STATI 5",
                                        "#define T3 300\n#define LAST_STATI 301"))
        _write(os.path.join(repo, RES_REL), SELFTEST_RES_8)
        rc, out = run(["--tree"])
        case(rc == 1 and "Nature" in out, "--tree stati 300 refused at 8 bits",
             "(rc=%d)\n%s" % (rc, out))
        _write(os.path.join(repo, RES_REL), SELFTEST_RES_16)
        rc, out = run(["--tree"])
        case(rc == 0, "--tree stati 300 passes at 16 bits", "(rc=%d)\n%s" % (rc, out))
        _write(os.path.join(repo, RES_REL), SELFTEST_RES_8)

        # --tree --file <epic Defines.h> --res <epic Res.h>: a 16-bit epic tree
        # accepts stati 300.
        epic_defines = os.path.join(tmp, "epic-Defines.h")
        epic_res = os.path.join(tmp, "epic-Res.h")
        _write(epic_defines,
               SELFTEST_DEFINES.replace("#define LAST_STATI 5",
                                        "#define E1 300\n#define LAST_STATI 301"))
        _write(epic_res, SELFTEST_RES_16)
        rc, out = run(["--tree", "--file", epic_defines, "--res", epic_res])
        case(rc == 0, "--tree --file --res epic passes", "(rc=%d)\n%s" % (rc, out))

        # --tree --file with no --res: width rule skipped, said on stderr.
        rc, out = run(["--tree", "--file", epic_defines])
        case(rc == 0 and "skipped" in out, "--tree --file no --res skips width",
             "(rc=%d)\n%s" % (rc, out))

        # a Res.h with no Nature line -> exit 2 (could not measure).
        _write(os.path.join(repo, RES_REL), SELFTEST_RES_NONE)
        _write(os.path.join(repo, DEFINES_REL), SELFTEST_DEFINES)
        rc, out = run(["--tree"])
        case(rc == 2, "--tree no Nature line exits 2", "(rc=%d)\n%s" % (rc, out))
        _write(os.path.join(repo, RES_REL), SELFTEST_RES_8)

        # a staged Defines.h with a staged Res.h that has no Nature line -> 2.
        _write(os.path.join(repo, RES_REL), SELFTEST_RES_NONE)
        _write(os.path.join(repo, DEFINES_REL), SELFTEST_DEFINES)
        git("add", RES_REL)
        stage(lambda t: t.replace("#define LAST_STATI 5",
                                  "#define S1 250\n#define LAST_STATI 251"))
        _write(os.path.join(repo, RES_REL), SELFTEST_RES_NONE)
        git("add", RES_REL)
        rc, out = run(["--staged"])
        case(rc == 2, "staged no Nature line exits 2", "(rc=%d)\n%s" % (rc, out))
        git("reset", "-q", RES_REL)
        unstage()
        _write(os.path.join(repo, RES_REL), SELFTEST_RES_8)

        # INCURSION_NUMBER_BANDS_OK=1 passes a refused case.
        _write(os.path.join(numdir, "issued.log"), "")
        stage(lambda t: t.replace("#define LAST_STATI 5",
                                  "#define OOB2 200\n#define LAST_STATI 201"))
        rc, out = run(["--staged"], extra_env={"INCURSION_NUMBER_BANDS_OK": "1"})
        case(rc == 0 and "warning" in out.lower(), "OK=1 bypasses", "(rc=%d)\n%s" % (rc, out))
        unstage()

        # no staged Defines.h -> exit 0.
        _write(os.path.join(repo, DEFINES_REL), SELFTEST_DEFINES)
        git("reset", "-q")
        rc, out = run(["--staged"])
        case(rc == 0, "nothing staged exits 0", "(rc=%d)\n%s" % (rc, out))

        # --- band selection: next_number.sh's chain / no-base / cycle rules ---

        # two-hop chain: sub -> mid -> inc-pu6v (rows). A new STATI inside the
        # inc-pu6v band passes; the 16-bit Res.h is staged so the width rule
        # cannot mask the band choice.
        git("checkout", "-q", "-b", "mid")
        git("checkout", "-q", "-b", "sub")
        git("config", "branch.sub.incursionBase", "mid")
        git("config", "branch.mid.incursionBase", "inc-pu6v")
        _write(os.path.join(repo, RES_REL), SELFTEST_RES_16)
        git("add", RES_REL)
        case(git("-c", "user.email=t@t", "-c", "user.name=t",
                 "commit", "-qm", "16-bit res") == 0,
             "16-bit res commit succeeds")
        _write(os.path.join(numdir, "issued.log"), "STATI 350 CHAINOK sub t\n")
        stage(lambda t: t.replace("#define LAST_STATI 5",
                                  "#define CHAINOK 350\n#define LAST_STATI 351"))
        rc, out = run(["--staged"])
        case(rc == 0, "two-hop chain: stati in inc-pu6v band passes",
             "(rc=%d)\n%s" % (rc, out))
        unstage()

        # a value inside the master band (243-255) is outside the inc-pu6v band
        # (300-399) -> refused naming the inc-pu6v band, not master.
        _write(os.path.join(numdir, "issued.log"), "STATI 250 CHAINBAD sub t\n")
        stage(lambda t: t.replace("#define LAST_STATI 5",
                                  "#define CHAINBAD 250\n#define LAST_STATI 251"))
        rc, out = run(["--staged"])
        case(rc == 1 and "outside" in out and "300-399" in out,
             "two-hop chain: master-band stati refused as outside inc-pu6v",
             "(rc=%d)\n%s" % (rc, out))
        unstage()

        # no base: a branch with no row and no base adding a new member is
        # refused with the config-fix line; a commit adding no new member passes.
        git("checkout", "-q", "master")
        git("checkout", "-q", "-b", "orphan")
        git("config", "--unset", "branch.orphan.incursionBase")
        _write(os.path.join(numdir, "issued.log"), "STATI 250 ORPHAN orphan t\n")
        stage(lambda t: t.replace("#define LAST_STATI 5",
                                  "#define ORPHAN 250\n#define LAST_STATI 251"))
        rc, out = run(["--staged"])
        case(rc == 1 and "has no band" in out and "git config branch.orphan.incursionBase" in out,
             "no-base branch with a new member refused with the config-fix line",
             "(rc=%d)\n%s" % (rc, out))
        unstage()

        # the same branch adding no new number passes.
        _write(os.path.join(numdir, "issued.log"), "")
        _write(os.path.join(repo, DEFINES_REL), SELFTEST_DEFINES)
        stage(lambda t: t.replace("#define LAST_STATI 5", "#define LAST_STATI 6"))
        rc, out = run(["--staged"])
        case(rc == 0, "no-base branch with no new member passes",
             "(rc=%d)\n%s" % (rc, out))
        unstage()

        # base cycle a -> b -> a with no rows: refused, does not hang.
        git("checkout", "-q", "-b", "cyc_a")
        git("checkout", "-q", "-b", "cyc_b")
        git("config", "branch.cyc_b.incursionBase", "cyc_a")
        git("config", "branch.cyc_a.incursionBase", "cyc_b")
        _write(os.path.join(numdir, "issued.log"), "STATI 250 CYCADD cyc_b t\n")
        stage(lambda t: t.replace("#define LAST_STATI 5",
                                  "#define CYCADD 250\n#define LAST_STATI 251"))
        rc, out = run(["--staged"])
        case(rc == 1 and "has no band" in out,
             "base cycle refused and does not hang", "(rc=%d)\n%s" % (rc, out))
        unstage()

        git("config", "--unset", "branch.cyc_b.incursionBase")
        git("config", "--unset", "branch.cyc_a.incursionBase")
        git("checkout", "-q", "master")
        _write(os.path.join(repo, RES_REL), SELFTEST_RES_8)
        git("add", RES_REL)

        print("selftest: %d passed" % passed)
        return 1 if fails else 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


# --- main -------------------------------------------------------------------

def width_for_tree(cwd, file_override, res_override):
    """Nature width for --tree, or None when it cannot be measured.

    With --file the working tree's Res.h is meaningless (the file may be an
    epic blob), so the width comes from --res; without --res the rule is skipped
    and the caller is told on stderr. Without --file the width comes from the
    working tree's inc/Res.h.
    """
    if file_override:
        if not res_override:
            sys.stderr.write(
                "check_number_bands: --file given without --res; "
                "STATI width rule skipped\n")
            return None
        try:
            with open(res_override, "r", encoding="utf-8") as fh:
                res_text = fh.read()
        except OSError as exc:
            raise CouldNotMeasure("cannot read %s: %s" % (res_override, exc))
    else:
        top = git_text_or_fail(["rev-parse", "--show-toplevel"], cwd=cwd).strip()
        if not top:
            raise CouldNotMeasure("empty git toplevel")
        res_path = os.path.join(top, RES_REL)
        if not os.path.isfile(res_path):
            raise CouldNotMeasure("no %s in %s" % (RES_REL, top))
        with open(res_path, "r", encoding="utf-8") as fh:
            res_text = fh.read()
    width = number_bands.nature_width(res_text)
    if width is None:
        raise CouldNotMeasure("no Nature bitfield in %s" % (res_override or RES_REL))
    return width


def usage():
    sys.stderr.write(
        "usage: check_number_bands.sh [--staged|--tree] [--file <path>] "
        "[--res <path>]\n")


def main(argv):
    cwd = os.getcwd()
    mode = None
    file_override = None
    res_override = None
    args = list(argv[1:])
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--staged":
            mode = "staged"
        elif a == "--tree":
            mode = "tree"
        elif a == "--file":
            i += 1
            if i >= len(args):
                usage()
                return 2
            file_override = args[i]
            if mode is None:
                mode = "tree"
        elif a == "--res":
            i += 1
            if i >= len(args):
                usage()
                return 2
            res_override = args[i]
        elif a in ("-h", "--help"):
            usage()
            return 0
        else:
            sys.stderr.write("unknown argument: %s\n" % a)
            usage()
            return 2
        i += 1
    if mode is None:
        mode = "staged"

    if os.environ.get("INCURSION_NUMBER_BANDS_OK") == "1":
        print("check_number_bands: WARNING: INCURSION_NUMBER_BANDS_OK=1, "
              "number bands NOT checked")
        return 0

    table_path = os.environ.get("INCURSION_NUMBER_BANDS") or \
        os.path.join(SELF_DIR, "number_bands.txt")

    try:
        rows = load_bands(table_path)
        if mode == "staged":
            rc, lines = check_staged(cwd, rows, table_path)
        else:
            if file_override:
                try:
                    with open(file_override, "r", encoding="utf-8") as fh:
                        text = fh.read()
                except OSError as exc:
                    raise CouldNotMeasure("cannot read %s: %s" % (file_override, exc))
            else:
                top = git_text_or_fail(["rev-parse", "--show-toplevel"], cwd=cwd).strip()
                if not top:
                    raise CouldNotMeasure("empty git toplevel")
                path = os.path.join(top, DEFINES_REL)
                if not os.path.isfile(path):
                    raise CouldNotMeasure("no %s in %s" % (DEFINES_REL, top))
                with open(path, "r", encoding="utf-8") as fh:
                    text = fh.read()
            width = width_for_tree(cwd, file_override, res_override)
            rc, lines = check_tree(cwd, rows, text, width)
    except CouldNotMeasure as exc:
        sys.stderr.write("check_number_bands: could not measure: %s\n" % exc)
        return 2

    for line in lines:
        print(line)
    return rc


if __name__ == "__main__":
    if len(sys.argv) >= 2 and sys.argv[1] == "--selftest":
        sys.exit(selftest())
    sys.exit(main(sys.argv))
