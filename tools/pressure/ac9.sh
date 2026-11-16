#!/bin/bash
# The AC9 real-case driver (inc-cjos0 phase 9, AC9): in a scratch CLONE of the real repository, merge the branch under
# test (standing in as master) into the real epic inc-pu6v through a merge bead, then the epic into one live god
# branch (Maeve, inc-pu6v.9), with the real gate.
#
#   tools/pressure/scratch.sh clone logs/phase8/d2/ac9/repo <inc-cjos0 HEAD sha>    once, first
#   tools/pressure/ac9.sh <clone-dir> <step>                                          one step at a time
#   tools/pressure/ac9.sh --selftest                                                  no real clone, no build
#
# Steps, run in this order (Claude runs them one at a time and reads each result):
#   m10v7f   (real order, 1) merge the clone's master into the real branch inc-10v7f; resolve dir .../resolve/m10v7f/
#   land10   (real order, 2) inc-10v7f onto the clone's master, gate = the build (see step_m10v7f)
#   merge1   fake bead inc-ac9m (parent inc-pu6v); tools/worktree.sh inc-ac9m inc-pu6v; `git merge master` there.
#            A conflict is resolved ONLY from tools/pressure/ac9/resolve/merge1/ (resolve_conflict.py: hunk text per
#            path; src/yygram.cpp, inc/yygram.h and lib/dispatch.h are regenerated, never given hunk text). No resolve
#            dir, or a path left unmerged: <run>/merge1-conflicts.txt lists each unmerged path with its hunk count
#            and the step exits 3. Then the merge is committed with the hooks on; a refusal is recorded to
#            <run>/refusals.txt, the unchanged mover (tools/move_branch_values.py) runs, and the commit is tried once more.
#   base     the recorded gate base: tools/nightly_verify.sh --record in a detached worktree of the epic BEFORE the merge
#            (<run>/Incursion-base), state in <run>/gate-base/. Run it once, before land1; land1 refuses without it.
#   land1    INCURSION_BASE_BRANCH=inc-pu6v tools/finish_bead.sh inc-ac9m, the REAL gate (INCURSION_FINISH_GATE unset).
#   merge2   a worktree of the existing branch inc-pu6v.9; `git merge inc-pu6v` there; resolve dir .../resolve/merge2/;
#            same conflict handling (<run>/merge2-conflicts.txt) and commit rule.
#            AC9_MERGE2_REF=<branch> merges that branch instead (default inc-pu6v, which needs land1): the preparation run
#            against merge 1's branch inc-ac9m. Before the merge, master's converter runs on Maeve (commit `port: convert god
#            field tags to names (inc-pu6v.9)`), as it ran on the epic for merge1. `attrib2` re-runs the numbers-by-hand check
#            alone on the committed merge2 (allowances: tools/pressure/ac9/allowances-merge2.txt).
#   gate2    the landing gate's compare (tools/nightly_verify.sh --landing) in the Maeve worktree. Nothing lands. Its base is
#            <run>/gate-base-maeve/ (tools/nightly_verify.sh --record on the clone's 4ac7f9d5, detached worktree <run>/Incursion-maeve-base).
#   values1  (after merge1, before land1) the clone's master fixtures against the merged tree: master's saves (specimens,
#            chars/*.sav, and the .sav master's own binary builds from each .char) are decoded by master's build and by the
#            merged build, and compared (compare_values.py). <run>/values1.txt. Needs no merge2.
#   values   record field values of master, of the epic after land1 and of Maeve after merge2 (scratch.sh record);
#            compare every master fixture's values with master's record (compare_values.py). <run>/values.txt.
#   report   <run>/results.md: every step's exit and deciding line, every refusal and whether it names a space, the
#            values verdict, and the "numbers edited by hand" check.
#
# <run> is the directory that holds <clone-dir> (logs/phase8/d2/ac9/). The fake bd and beads sit in <run>/pressure-state.
# Exit: 0 step done, 1 step failed, 2 could not run, 3 (merge steps) conflicts the resolve dir does not cover.
#
# THE "NUMBERS EDITED BY HAND" CHECK. A merge commit is shown as a combined diff against both parents. A line in no
# parent (`++`) is content the merge made: resolution text, the mover's output, or a hand edit. A line of a generated
# file is regenerated, never judged here. Every other such line that holds a digit MUST appear in the committed resolve
# files or in the mover's saved diff (<run>/<step>-mover.diff); one that does not is a hand edit and FAILS the check.
# tools/check_define_dups.py also runs on each merge result. Ceiling: the check shows every number in the merge came
# from the committed resolution or the mover, not who typed it; the driver is the only writer between merge and commit.
#
# fact: the clone's three branches -- the real repository's inc-pu6v and inc-pu6v.9 at clone time, shas in <run>/pressure-state/clone.txt
# fact: master -- the sha the clone step was given, forced onto local master
# fact: the gate and the build -- the clone's own tools/nightly_verify.sh and BACKEND=posix ./build_macos.sh; frozen fixtures tools/fixtures/chars/*.sav; no seed, no key script
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
D2ROOT="${INCURSION_PRESSURE_D2ROOT:-$ROOT/logs/phase8/d2}"   # the override is for --selftest only
RESOLVE_ROOT="${INCURSION_AC9_RESOLVE:-$HERE/ac9/resolve}"     # the override is for --selftest only
RENAMES_FILE="${INCURSION_AC9_RENAMES:-$HERE/ac9/renames.txt}"   # the override is for --selftest only

# "old>new|..." for compare_values.py from renames.txt (old TAB new TAB commit TAB bead). The value files print a resource
# by its display name (no `;suffix`), so each pair is given in both forms.
renames_env() {
    [ -f "$RENAMES_FILE" ] || return 0
    awk -F'\t' '!/^#/ && NF >= 4 { o = $1; n = $2; so = o; sn = n; sub(/;.*/, "", so); sub(/;.*/, "", sn);
                                   printf "%s%s>%s|%s>%s", (c++ ? "|" : ""), o, n, so, sn }' "$RENAMES_FILE"
}
unset INCURSIONPATH INCURSION_LOAD INCURSION_OPTIONS INCURSION_RUN_DIR

die() { echo "ac9: $*" >&2; exit "${2:-2}"; }

# ------------------------------------------------------------------ selftest
selftest() {
    local tmp src rev rc bad=0 out
    tmp="$(mktemp -d "${TMPDIR:-/tmp}/ac9-selftest.XXXXXX")" && tmp="$(cd "$tmp" && pwd -P)" || die "no temp dir"
    # shellcheck disable=SC2064
    trap "rm -rf '$tmp'" EXIT
    check() { # <name> <condition rc>
        if [ "$2" -eq 0 ]; then echo "ok   $1"; else echo "FAIL $1"; bad=$((bad + 1)); fi
    }
    export GIT_AUTHOR_NAME=t GIT_COMMITTER_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_EMAIL=t@t
    src="$tmp/src"
    mkdir -p "$src/tools" "$src/docs" "$tmp/d2" "$tmp/resolve" || die "mkdir"
    cp "$ROOT/tools/worktree.sh" "$src/tools/" || die "no worktree.sh"
    echo "inc-x" > "$src/docs/REPORTING-GATE.md"
    printf 'a\nb\nc\n' > "$src/f.txt"
    git -C "$src" init -q -b master && git -C "$src" add . && git -C "$src" commit -q -m base || die "git setup"
    git -C "$src" checkout -q -b inc-pu6v && printf 'a\nX\nc\n' > "$src/f.txt" && git -C "$src" commit -qam epic || die "git setup"
    git -C "$src" branch inc-pu6v.9 || die "git setup"
    git -C "$src" checkout -q master && printf 'a\nY\nc\n' > "$src/f.txt" && git -C "$src" commit -qam master || die "git setup"
    rev="$(git -C "$src" rev-parse master)"
    export INCURSION_PRESSURE_D2ROOT="$tmp/d2" INCURSION_AC9_SOURCE="$src" INCURSION_AC9_RESOLVE="$tmp/resolve"

    out="$("$HERE/scratch.sh" clone "$tmp/outside/repo" "$rev" 2>&1)"; rc=$?
    check "clone refuses a dir outside logs/phase8/d2/ (rc $rc)" "$([ $rc -eq 2 ] && printf '%s' "$out" | grep -q '^scratch: REFUSED' && echo 0 || echo 1)"
    check "the refused clone made nothing" "$([ ! -e "$tmp/outside" ] && echo 0 || echo 1)"

    out="$("$HERE/scratch.sh" clone "$tmp/d2/ac9/repo" "$rev" 2>&1)"; rc=$?
    check "clone of the throwaway repository runs (rc $rc)" "$rc"
    [ "$rc" -eq 0 ] || printf '%s\n' "$out" | tail -5 >&2
    check "the clone has no remote" "$([ -z "$(git -C "$tmp/d2/ac9/repo" remote)" ] && echo 0 || echo 1)"
    check "the clone has master, inc-pu6v and inc-pu6v.9" "$(git -C "$tmp/d2/ac9/repo" for-each-ref --format='%(refname:short)' refs/heads | sort | tr '\n' ' ' | grep -qx 'inc-pu6v inc-pu6v.9 master ' && echo 0 || echo 1)"
    check "master is the given rev" "$([ "$(git -C "$tmp/d2/ac9/repo" rev-parse master)" = "$rev" ] && echo 0 || echo 1)"
    check "clone.txt names the source" "$(grep -q "^source $src" "$tmp/d2/ac9/pressure-state/clone.txt" && echo 0 || echo 1)"

    out="$("$HERE/ac9.sh" "$tmp/d2/ac9/repo" merge1 2>&1)"; rc=$?
    check "merge1 with no resolve dir stops with exit 3 (rc $rc)" "$([ $rc -eq 3 ] && echo 0 || echo 1)"
    check "merge1 wrote the conflicts file naming f.txt with 1 hunk" "$(grep -q '^f.txt	1$' "$tmp/d2/ac9/merge1-conflicts.txt" 2>/dev/null && echo 0 || echo 1)"
    # the values1 rule: a removed field of master value 0 passes, a removed nonzero one fails, a changed kept one fails
    printf 'h1:t7/Character Anger[0] uint Anger=0\nh1:t7/Character Kept uint Kept=1\n' > "$tmp/v0.txt"
    printf 'h1:t7/Character Kept uint Kept=1\n' > "$tmp/v-ok.txt"
    printf 'h1:t7/Character Anger[0] uint Anger=4\nh1:t7/Character Kept uint Kept=1\n' > "$tmp/v-nz.txt"
    printf 'h1:t7/Character Kept uint Kept=2\n' > "$tmp/v-ch.txt"
    INCURSION_PRESSURE_REMOVED_ZERO=1 python3 "$HERE/compare_values.py" "$tmp/v0.txt" "$tmp/v-ok.txt" > /dev/null; rc=$?
    check "values1 rule: a removed field of master value 0 passes" "$rc"
    INCURSION_PRESSURE_REMOVED_ZERO=1 python3 "$HERE/compare_values.py" "$tmp/v-nz.txt" "$tmp/v-ok.txt" > /dev/null; rc=$?
    check "values1 rule: a removed field of nonzero master value fails" "$([ $rc -eq 1 ] && echo 0 || echo 1)"
    INCURSION_PRESSURE_REMOVED_ZERO=1 python3 "$HERE/compare_values.py" "$tmp/v0.txt" "$tmp/v-ch.txt" > /dev/null; rc=$?
    check "values1 rule: a changed kept value fails" "$([ $rc -eq 1 ] && echo 0 || echo 1)"
    # renames.txt: a rID line passes only for a listed old -> new pair
    printf 'Old;x\tNew;x\tabc\tinc-t\n' > "$tmp/renames.txt"
    printf 'h1:t5/Item eID rid eID=Old\n' > "$tmp/r-b.txt"; printf 'h1:t5/Item eID rid eID=New\n' > "$tmp/r-a.txt"; printf 'h1:t5/Item eID rid eID=Other\n' > "$tmp/r-u.txt"
    ( INCURSION_AC9_RENAMES="$tmp/renames.txt"; RENAMES_FILE="$INCURSION_AC9_RENAMES"
      INCURSION_PRESSURE_RENAMES="$(renames_env)" python3 "$HERE/compare_values.py" "$tmp/r-b.txt" "$tmp/r-a.txt" > /dev/null ); rc=$?
    check "values1 rule: a listed rename passes" "$rc"
    ( RENAMES_FILE="$tmp/renames.txt"; INCURSION_PRESSURE_RENAMES="$(renames_env)" python3 "$HERE/compare_values.py" "$tmp/r-b.txt" "$tmp/r-u.txt" > /dev/null ); rc=$?
    check "values1 rule: an unlisted rename fails" "$([ $rc -eq 1 ] && echo 0 || echo 1)"
    [ "$bad" -eq 0 ] || printf '%s\n' "$out" | tail -5 >&2
    echo "ac9 selftest: $([ "$bad" -eq 0 ] && echo PASS || echo FAIL)"
    [ "$bad" -eq 0 ]
}

if [ "${1:-}" = --selftest ]; then selftest; exit $?; fi

# ------------------------------------------------------------------ the steps
[ $# -eq 2 ] || die "usage: ac9.sh <clone-dir> base|m10v7f|land10|merge1|values1|land1|merge2|gate2|values|report   |   ac9.sh --selftest"
STEP="$2"
DIR="$(cd "$1" 2>/dev/null && pwd -P)" || die "no such directory: $1"
D2="$(mkdir -p "$D2ROOT" && cd "$D2ROOT" && pwd -P)" || die "cannot resolve $D2ROOT"
case "$DIR" in "$D2"/*) ;; *) die "REFUSED: $DIR is not under $D2" ;; esac
[ -e "$DIR/.git" ] || die "$DIR is not a repository"
RUN="$(dirname "$DIR")"
STATE="$RUN/pressure-state"
[ -x "$STATE/bin/bd" ] || die "no fake bd in $STATE (run scratch.sh clone first)"
LOG="$RUN/log"; STEPS="$RUN/ac9-steps.tsv"; REFUSALS="$RUN/refusals.txt"
mkdir -p "$LOG" "$STATE/tmp" || die "cannot create $LOG"
# TMPDIR lies outside every git repository and outside every Incursion path: tools/check_fact_lines.py's "not a git repo"
# case, check_citations.sh and check_dispatch_gate.sh's "run from elsewhere" case all make a scratch directory under it.
AC9TMP="${INCURSION_AC9_TMP:-/tmp/incursion-ac9-$(id -u)}"
mkdir -p "$AC9TMP" || die "cannot create $AC9TMP"
AC9TMP="$(cd "$AC9TMP" && pwd -P)"
case "$AC9TMP" in "$ROOT"|"$ROOT"/*|"$HOME/Scripts/Incursion"|"$HOME/Scripts/Incursion"/*|"$HOME/Scripts/Incursion-"*) die "REFUSED: $AC9TMP lies inside an Incursion tree" ;; esac
[ -z "$(git -C "$AC9TMP" rev-parse --git-dir 2> /dev/null)" ] || die "REFUSED: $AC9TMP lies inside a git repository"
export PATH="$STATE/bin:$PATH" TMPDIR="$AC9TMP" INCURSION_LOAD_GUARD_LOG="$STATE/load-guard.log" INCURSION_FINISH_LOCK_POLL=1
export GIT_AUTHOR_NAME="AC8 pressure driver" GIT_COMMITTER_NAME="AC8 pressure driver"
export GIT_AUTHOR_EMAIL=pressure@example.invalid GIT_COMMITTER_EMAIL=pressure@example.invalid

BEAD_M=inc-ac9m
GOD=inc-pu6v.9

wt() { printf '%s/Incursion-%s' "$RUN" "$1"; }
now() { date +%s; }

decide() { # <logfile> -> the deciding line
    local l d
    l="$(grep -m1 -E '^(STOPPED|REFUSED|INCONCLUSIVE)' "$1")"
    [ -n "$l" ] || l="$(grep -m1 -E '^Landed\.' "$1")"
    [ -n "$l" ] || l="$(grep -m1 -E '^(pre-commit: (a fast check|REFUSED)|build: STOPPED)' "$1")"
    [ -n "$l" ] || l="$(grep -v -E '^[[:space:]]*$|^beads:' "$1" | tail -1)"
    [ -n "$l" ] || l=ok
    d="$(grep -m1 -E '^[[:space:]]*(REFUSED|FAIL): ' "$1" | sed 's/^[[:space:]]*//')"
    printf '%s' "$l${d:+ | $d}" | tr '\t' ' ' | cut -c1-260
}

steplog() { # <step> <rc> <logfile>
    printf '%s\t%s\t%s\n' "$1" "$2" "$(decide "$3")" >> "$STEPS"
    echo "ac9: $1 rc=$2 $(decide "$3")"
}

note_refusals() { # <label> <logfile>: every refusal line of a log, to refusals.txt
    grep -E 'REFUSED|FAIL:|a fast check|STOPPED' "$2" | sed 's/^[[:space:]]*//' | cut -c1-300 \
        | sed "s/^/$1\t/" >> "$REFUSALS"
}

mkbead() { # <id> <parent>: a fake bead with one acceptance criterion
    printf '[{"id":"%s","status":"open","issue_type":"task","parent":"%s","description":"## Acceptance Criteria\\n- the real landing gate passes on the merged epic\\n","notes":""}]\n' "$1" "$2" > "$STATE/beads/$1.json"
}

wait_load_guard() { ( cd "$DIR" && until tools/load_guard.sh > /dev/null 2>&1; do sleep 30; done ); }

# list every unmerged path with its hunk count (generated paths say so), to <file>
list_conflicts() { # <worktree> <file>
    local w="$1" f="$2" p n
    : > "$f"
    git -C "$w" diff --name-only --diff-filter=U | while IFS= read -r p; do
        n="$(grep -c '^<<<<<<< ' "$w/$p" 2>/dev/null || true)"
        case "$p" in
            src/yygram.cpp|inc/yygram.h|lib/dispatch.h) printf '%s\tgenerated(%s hunks)\n' "$p" "${n:-0}" >> "$f" ;;
            *) printf '%s\t%s\n' "$p" "${n:-0}" >> "$f" ;;
        esac
    done
}

# Numbers edited by hand: see the header. Writes <run>/<name>-attrib.txt; returns 0 clean, 1 a hand edit or no verdict.
attribute_check() { # <name> <worktree>
    local name="$1" w="$2" out="$RUN/$1-attrib.txt" dups drc
    dups="$( cd "$w" && python3 tools/check_define_dups.py 2>&1 )"; drc=$?
    { git -C "$w" log -2 --format='%H %P' ; } > "$RUN/$name-commits.txt" 2>&1
    python3 - "$w" "$RUN" "$name" "$RESOLVE_ROOT/$name" "$drc" "$(printf '%s' "$dups" | tail -1 | cut -c1-200)" > "$out" <<'PY'
import os, re, subprocess, sys
w, run, name, rdir, drc, dline = sys.argv[1:7]
GEN = {"src/yygram.cpp", "inc/yygram.h", "lib/dispatch.h"}
def git(*a):
    r = subprocess.run(["git", "-C", w] + list(a), capture_output=True, text=True, errors="replace")
    return r.returncode, r.stdout
rc, parents = git("log", "-1", "--format=%P", "HEAD")
if rc != 0:
    print("NUMBERS-BY-HAND FAIL: git log failed"); sys.exit(1)
heads = [("merge commit", "HEAD")]
# a mover commit made after a clean merge sits on top of it
rc, subj = git("log", "-1", "--format=%s", "HEAD")
attrib = set()
HASD = re.compile(r"[0-9]")
# NAMED ALLOWANCES (tools/pressure/ac9/allowances-<step>.txt): <path> TAB <kind> TAB <note> TAB <exact line>. A digit-bearing
# line of a resolution or of post.patch that is on neither side of the merge must be named there.
#   hand      the one number the owner ruled may be chosen by hand (src/Debug.cpp menu entry)
#   compiler  a value the compiler printed (size asserts)
#   rewrite   an edit that keeps every existing constant
allow = {}
afile = os.path.normpath(os.path.join(rdir, "..", "..", "allowances-%s.txt" % name))
if os.path.exists(afile):
    for ln in open(afile, encoding="utf-8", errors="replace").read().split("\n"):
        f = ln.split("\t")
        if len(f) == 4 and not ln.startswith("#"):
            allow[(f[0], f[3].strip())] = (f[1], f[2])
used = {}
sides = {}
def side_lines(path):
    if path not in sides:
        s = set()
        for par in parents.split():
            r2, txt = git("show", par + ":" + path)
            if r2 == 0:
                s.update(l.strip() for l in txt.split("\n"))
        sides[path] = s
    return sides[path]
foreign = []
def take(path, ln):
    t = ln.strip()
    if not t:
        return
    if not HASD.search(t) or t in side_lines(path):
        attrib.add(t)
    elif (path, t) in allow:
        used[(path, t)] = allow[(path, t)]
        attrib.add(t)
    else:
        foreign.append("%s: %s" % (path, t[:160]))
if os.path.isdir(rdir):
    for root, _, files in os.walk(rdir):
        for f in files:
            top = os.path.normpath(root) == os.path.normpath(rdir)
            if top and f in ("README.md", "deletions.txt", "keeps.txt"):
                continue   # the table that explains the resolution is no resolution text
            fp = os.path.join(root, f)
            rel = os.path.relpath(fp, rdir)
            if rel.endswith(".resolve"):
                rel = rel[:-len(".resolve")]   # <path>.resolve holds the hunk text of <path>
            txt = open(fp, encoding="utf-8", errors="replace").read()
            txt = re.sub(r"^# stale-quote-ok:[ \t]*\S[^\n]*\n", "", txt, count=1).split("\n")   # resolve_conflict.strip_marker
            if top and f == "post.patch":
                cur = None
                for ln in txt:
                    if ln.startswith("+++ b/"):
                        cur = ln[6:]
                    elif ln.startswith("+") and not ln.startswith("+++") and cur:
                        take(cur, ln[1:])
            else:
                for ln in txt:
                    if ln != "@@@ next hunk":
                        take(rel, ln)
mv = os.path.join(run, name + "-mover.diff")
if os.path.exists(mv):
    for ln in open(mv, encoding="utf-8", errors="replace").read().split("\n"):
        if ln.startswith("+") and not ln.startswith("+++") and ln[1:].strip():
            attrib.add(ln[1:].strip())
for k in sorted(set(allow) - set(used)):
    foreign.append("allowance never used: %s: %s" % k)
bad, seen, path = [], 0, None
rc, body = git("show", "--cc", "--format=", "HEAD")
if rc != 0:
    print("NUMBERS-BY-HAND FAIL: git show failed"); sys.exit(1)
ncols = max(1, len(parents.split()))
for ln in body.split("\n"):
    if ln.startswith("diff --cc ") or ln.startswith("diff --git "):
        path = ln.split(" ")[-1]
        if ln.startswith("diff --git "):
            path = ln.split(" b/")[-1]
        continue
    if path is None or path in GEN or ln.startswith("+++") or ln.startswith("---"):
        continue
    is_new = ln[:ncols] == "+" * ncols and len(ln) > ncols if ncols >= 2 else ln.startswith("+")
    if is_new:
        text = ln[ncols:].strip()
        if text and re.search(r"[0-9]", text):
            seen += 1
            if text not in attrib:
                bad.append("%s: %s" % (path, text[:160]))
print("merge-made lines with a digit (outside generated files): %d; not in the committed resolution or the mover's diff: %d" % (seen, len(bad)))
for b in bad[:40]:
    print("  UNATTRIBUTED " + b)
for f in foreign[:40]:
    print("  NOT ON A SIDE OR ALLOWED " + f)
for (pth, ln), (kind, note) in sorted(used.items()):
    print("  ALLOWANCE %s %s: %s  [%s]" % (kind, pth, ln[:100], note))
print("check_define_dups.py rc %s: %s" % (drc, dline))
if bad or foreign or drc != "0":
    print("NUMBERS-BY-HAND FAIL"); sys.exit(1)
print("NUMBERS-BY-HAND PASS")
PY
}

# run the unchanged mover in <worktree>; saves its unstaged diff to <run>/<name>-mover.diff; 0 the mover changed files
run_mover() { # <name> <worktree>
    local name="$1" w="$2" out
    out="$( cd "$w" && python3 tools/move_branch_values.py 2>&1 )"
    printf '%s\n' "$out" > "$LOG/$name-mover.log"
    git -C "$w" diff > "$LOG/$name-mover-last.diff"
    cat "$LOG/$name-mover-last.diff" >> "$RUN/$name-mover.diff"   # appended: the resolver may have run the mover already
    [ -s "$LOG/$name-mover-last.diff" ]
}

commit_merge() { # <name> <worktree> -> 0 committed
    local name="$1" w="$2" cl="$LOG/$name-commit.log" rc
    git -C "$w" commit --no-edit > "$cl" 2>&1; rc=$?
    [ $rc -eq 0 ] && return 0
    note_refusals "$name commit" "$cl"
    # the refusal is the stored-number collision (two sides chose one value): the unchanged mover is the recovery
    local rl="$LOG/$name-commit-retry.log"
    run_mover "$name" "$w" || true
    if grep -qE 'Incursion\.Mod|not built|rebuild' "$cl"; then
        ( cd "$w" && BACKEND=posix ./build_macos.sh ) > "$LOG/$name-build.log" 2>&1 || { echo "ac9: the module build failed (log $LOG/$name-build.log)" >> "$rl"; }
    fi
    git -C "$w" add -A > "$rl" 2>&1
    git -C "$w" commit --no-edit >> "$rl" 2>&1; rc=$?
    cat "$rl" >> "$cl"
    [ $rc -eq 0 ] || note_refusals "$name commit after the mover" "$rl"
    return $rc
}

# merge <ref> into <worktree>, resolving from the committed resolve dir, committing through the hooks.
merge_step() { # <name> <worktree> <ref>
    local name="$1" w="$2" ref="$3" lf="$LOG/$1-merge.log" rc rrc
    rm -f "$RUN/$name-mover.diff" "$RUN/$name-conflicts.txt"
    [ -z "$(git -C "$w" status --porcelain --untracked-files=no)" ] || die "$w is not clean before the merge" 2
    git -C "$w" merge --no-edit "$ref" > "$lf" 2>&1; rc=$?
    if [ $rc -ne 0 ]; then
        if [ -z "$(git -C "$w" diff --name-only --diff-filter=U)" ]; then steplog "$name" "$rc" "$lf"; return 1; fi
        INCURSION_RESOLVE_MOVER_DIFF="$RUN/$name-mover.diff" python3 "$HERE/resolve_conflict.py" "$w" "$RESOLVE_ROOT/$name" >> "$lf" 2>&1; rrc=$?
        # order: hunks, post.patch, the mover (diff saved to <run>/<name>-mover.diff), then the generated files are rebuilt
        if [ $rrc -ne 0 ] || [ -n "$(git -C "$w" diff --name-only --diff-filter=U)" ]; then
            list_conflicts "$w" "$RUN/$name-conflicts.txt"
            echo "ac9: $name stops: $(wc -l < "$RUN/$name-conflicts.txt" | tr -d ' ') path(s) in conflict not resolved by $RESOLVE_ROOT/$name; see $RUN/$name-conflicts.txt" | tee -a "$lf" >&2
            echo "     the merge stays open in $w" >&2
            steplog "$name" 3 "$lf"
            exit 3
        fi
        if [ "$name" = merge1 ]; then
            # tool-generated files of the merge (E2): the epic's .char fixtures, converted from its own d71c1823 saves
            # against the oracle dumps; the substep's added lines are attributed as tool output, like the mover's
            "$HERE/ac9_fixtures.sh" "$w" "$RUN/pressure-state" > "$LOG/$name-fixtures.log" 2>&1; rrc=$?
            cat "$LOG/$name-fixtures.log" >> "$lf"
            if [ $rrc -ne 0 ]; then
                echo "ac9: merge1 stops: the fixture substep failed (rc $rrc); see $LOG/$name-fixtures.log and $RUN/pressure-state/fixtures/failures.txt" | tee -a "$lf" >&2
                steplog "$name" 3 "$LOG/$name-fixtures.log"
                exit 3
            fi
            cp "$RUN/pressure-state/fixtures/result.tsv" "$RUN/merge1-fixtures.tsv"
            grep -E '^\+[^+]' "$RUN/pressure-state/fixtures/added.diff" >> "$RUN/$name-mover.diff"
        fi
        commit_merge "$name" "$w"; rc=$?
        cat "$LOG/$name-commit.log" >> "$lf"
        if [ $rc -ne 0 ]; then steplog "$name" "$rc" "$LOG/$name-commit.log"; return 1; fi
    else
        # git committed a clean merge itself. The mover still runs: a collision of stored numbers is not a text conflict.
        if run_mover "$name" "$w"; then
            git -C "$w" add -A && git -C "$w" commit -q -m "tools: $name moved colliding stored values (tools/move_branch_values.py)" \
                -m "Generated by the unchanged mover; no hand edit." >> "$LOG/$name-commit.log" 2>&1 || { steplog "$name" 1 "$LOG/$name-commit.log"; return 1; }
        fi
    fi
    git -C "$w" rev-parse HEAD > "$RUN/$name.sha"
    attribute_check "$name" "$w"
    steplog "$name" 0 "$lf"
    return 0
}

# The fake bd says every bead a ledger names carries the upstream label. The clone step wrote that list from master's
# ledger only; the epic's and the god's ledgers name more beads, so the list is the union over the three branches.
refresh_labelled() {
    local b
    { for b in master inc-pu6v "$GOD"; do git -C "$DIR" show "$b:docs/REPORTING-GATE.md"; done; } \
        | python3 -c '
import json, re, sys
ids = sorted(set(re.findall(r"inc-[a-z0-9]+(?:\.[0-9]+)*", sys.stdin.read())))
json.dump([{"id": i} for i in ids], open(sys.argv[1], "w"))
json.dump([{"id": i, "status": "open", "issue_type": "task"} for i in ids], open(sys.argv[2], "w"))' "$STATE/upstream-labelled.json" "$STATE/beads-all.json" \
        || die "cannot refresh the fake upstream-label list"
}

step_merge1() {
    refresh_labelled
    mkbead "$BEAD_M" inc-pu6v
    local lf="$LOG/start-$BEAD_M.log" rc
    if [ ! -d "$(wt "$BEAD_M")" ]; then
        ( cd "$DIR" && tools/worktree.sh "$BEAD_M" inc-pu6v ) > "$lf" 2>&1; rc=$?
        if [ $rc -ne 0 ]; then steplog "start $BEAD_M" "$rc" "$lf"; exit 1; fi
    fi
    # AC7 order: the epic's field calls take names FIRST (master's converter, run on the epic), then master merges in
    local w cv; w="$(wt "$BEAD_M")"; cv="$LOG/convert-$BEAD_M.log"
    if git -C "$DIR" cat-file -e master:tools/convert_tags_to_names.py 2> /dev/null \
        && ! git -C "$w" log --format=%s "inc-pu6v..HEAD" | grep -qF "port: convert epic field tags to names ($BEAD_M)"; then
        [ -z "$(git -C "$w" status --porcelain --untracked-files=no)" ] || die "$w is not clean before the conversion" 2
        git -C "$DIR" show master:tools/convert_tags_to_names.py > "$STATE/tmp/convert_tags_to_names.py" 2> "$cv" \
            || { steplog "convert $BEAD_M" 1 "$cv"; exit 1; }
        # the converter imports tools/number_values.py and tools/gen_legacy_tags.py from its own directory: put master's copies beside it
        for f in number_values.py gen_legacy_tags.py; do
            git -C "$DIR" show "master:tools/$f" > "$STATE/tmp/$f" 2>> "$cv" || { steplog "convert $BEAD_M" 1 "$cv"; exit 1; }
        done
        # the epic has no inc/SaveLegacyTags.h yet (master's frozen table): the converter reads master's copy
        git -C "$DIR" show master:inc/SaveLegacyTags.h > "$STATE/tmp/SaveLegacyTags.h" 2>> "$cv" || { steplog "convert $BEAD_M" 1 "$cv"; exit 1; }
        python3 "$STATE/tmp/convert_tags_to_names.py" --root "$w" --header "$STATE/tmp/SaveLegacyTags.h" --apply >> "$cv" 2>&1 || { steplog "convert $BEAD_M" 1 "$cv"; exit 1; }
        git -C "$w" add -A && git -C "$w" commit -q -m "port: convert epic field tags to names ($BEAD_M)" \
            -m "Generated by master's tools/convert_tags_to_names.py --apply; no hand edit." >> "$cv" 2>&1 \
            || { steplog "convert $BEAD_M" 1 "$cv"; exit 1; }
    fi
    merge_step merge1 "$w" master || exit 1
}

# The recorded gate base of AC9: tools/nightly_verify.sh --record on the epic BEFORE the merge (the clone's inc-pu6v at the
# sha clone.txt names), in its own detached worktree. --landing reads its base from $NIGHTLY_VERIFY_STATE.
GATE_BASE="$RUN/gate-base/nightly-verify-base.txt"; GATE_BASE_FILE="$GATE_BASE"
step_base() {
    local sha w lf rc
    sha="$(sed -n 's/^inc-pu6v //p' "$STATE/clone.txt")"
    [ -n "$sha" ] || die "no inc-pu6v sha in $STATE/clone.txt"
    w="$RUN/Incursion-base"; lf="$LOG/base.log"
    if [ ! -d "$w" ]; then
        git -C "$DIR" worktree add -q --detach "$w" "$sha" > "$LOG/start-base.log" 2>&1 || { steplog "start base" 1 "$LOG/start-base.log"; exit 1; }
    fi
    [ "$(git -C "$w" rev-parse HEAD)" = "$sha" ] || die "$w is not at $sha"
    mkdir -p "$RUN/gate-base" && rm -f "$GATE_BASE"
    wait_load_guard
    ( cd "$w" && NIGHTLY_VERIFY_STATE="$GATE_BASE" tools/nightly_verify.sh --record ) > "$lf" 2>&1; rc=$?
    # --record exits 0 when it recorded, even when checks failed; the base file is what counts
    [ -s "$GATE_BASE" ] || rc=1
    echo "base: $(wc -l < "$GATE_BASE" 2> /dev/null | tr -d ' ') line(s) in $GATE_BASE, epic $sha" >> "$lf"
    steplog base "$rc" "$lf"
    exit "$([ $rc -eq 0 ] && echo 0 || echo 1)"
}

# The real order is inc-cjos0, then inc-10v7f, then the master-into-epic merge. m10v7f merges the clone's master into the
# real branch inc-10v7f (resolve dir .../resolve/m10v7f/); land10 lands it on the clone's master. For THIS landing only the
# gate is the fast checks plus the build (INCURSION_FINISH_GATE): inc-10v7f's real landing runs its own real gate.
step_m10v7f() {
    local w lf rc
    w="$(wt inc-10v7f)"; lf="$LOG/start-inc-10v7f.log"
    git -C "$DIR" rev-parse -q --verify inc-10v7f > /dev/null || die "the clone has no branch inc-10v7f"
    mkbead inc-10v7f master
    if [ ! -d "$w" ]; then
        { git -C "$DIR" worktree add "$w" inc-10v7f && git -C "$DIR" config "branch.inc-10v7f.incursionBase" master; } > "$lf" 2>&1; rc=$?
        if [ $rc -ne 0 ]; then steplog "start inc-10v7f" "$rc" "$lf"; exit 1; fi
    fi
    merge_step m10v7f "$w" master || exit 1
}

step_land10() {
    local w lf rc
    w="$(wt inc-10v7f)"; [ -d "$w" ] || die "no $w: run m10v7f first"
    [ -f "$RUN/m10v7f.sha" ] || die "m10v7f has not finished"
    if ! git -C "$w" log --no-merges --format=%B "master..HEAD" | grep -q '^AC1:'; then
        git -C "$w" commit -q --allow-empty -m "tools: inc-10v7f merges master for AC9" \
            -m "AC1: inc-10v7f lands on the clone's master with the fast checks and the build" > "$LOG/evidence-inc-10v7f.log" 2>&1 \
            || { steplog "evidence inc-10v7f" 1 "$LOG/evidence-inc-10v7f.log"; exit 1; }
    fi
    lf="$LOG/land10.log"
    ( cd "$DIR" && AC9_GATE_BASE="$GATE_BASE_FILE" INCURSION_FINISH_GATE="$HERE/ac9_cheapgate.sh" tools/finish_bead.sh inc-10v7f ) > "$lf" 2>&1; rc=$?
    if [ $rc -ne 0 ]; then
        note_refusals land10 "$lf"
        if [ -d "$w" ] && run_mover land10 "$w"; then
            git -C "$w" add -A && git -C "$w" commit -q -m "tools: inc-10v7f moved colliding stored values (tools/move_branch_values.py)" -m "Generated by the unchanged mover; no hand edit."
            ( cd "$DIR" && AC9_GATE_BASE="$GATE_BASE_FILE" INCURSION_FINISH_GATE="$HERE/ac9_cheapgate.sh" tools/finish_bead.sh inc-10v7f ) > "$LOG/land10-retry.log" 2>&1; rc=$?
            lf="$LOG/land10-retry.log"
        fi
    fi
    steplog land10 "$rc" "$lf"
    [ $rc -eq 0 ] && git -C "$DIR" rev-parse master > "$RUN/land10.sha"
    exit "$([ $rc -eq 0 ] && echo 0 || echo 1)"
}

step_land1() {
    local w lf rc
    [ -s "$GATE_BASE" ] || die "no recorded gate base: run 'ac9.sh <clone> base' first"
    export NIGHTLY_VERIFY_STATE="$GATE_BASE"
    w="$(wt "$BEAD_M")"; [ -d "$w" ] || die "no $w: run merge1 first"
    [ -f "$RUN/merge1.sha" ] || die "merge1 has not finished"
    # STEP 2b of finish_bead.sh reads the non-merge commits: one line per acceptance criterion
    if ! git -C "$w" log --no-merges --format=%B "inc-pu6v..HEAD" | grep -q '^AC1:'; then
        git -C "$w" commit -q --allow-empty -m "tools: $BEAD_M merges master into the epic for AC9" \
            -m "AC1: the real landing gate runs on the merged epic and every master fixture is compared with its master values" \
            > "$LOG/evidence-$BEAD_M.log" 2>&1 || { steplog "evidence $BEAD_M" 1 "$LOG/evidence-$BEAD_M.log"; exit 1; }
    fi
    lf="$LOG/land1.log"
    ( cd "$DIR" && INCURSION_BASE_BRANCH=inc-pu6v tools/finish_bead.sh "$BEAD_M" ) > "$lf" 2>&1; rc=$?
    if [ $rc -ne 0 ]; then
        note_refusals land1 "$lf"
        if [ -d "$w" ] && run_mover land1 "$w"; then
            git -C "$w" add -A && git -C "$w" commit -q -m "tools: $BEAD_M moved colliding stored values (tools/move_branch_values.py)" \
                -m "Generated by the unchanged mover; no hand edit."
            lf="$LOG/land1-retry.log"
            ( cd "$DIR" && INCURSION_BASE_BRANCH=inc-pu6v tools/finish_bead.sh "$BEAD_M" ) > "$lf" 2>&1; rc=$?
            [ $rc -eq 0 ] || note_refusals "land1 retry" "$lf"
        fi
    fi
    steplog land1 "$rc" "$lf"
    [ $rc -eq 0 ] && git -C "$DIR" rev-parse inc-pu6v > "$RUN/land1.sha"
    exit "$([ $rc -eq 0 ] && echo 0 || echo 1)"
}

# Preparation run (inc-cjos0 AC9 phase E3): AC9_MERGE2_REF=inc-ac9m merges merge 1's tip, not the landed epic, into Maeve.
# The default inc-pu6v is the real run and needs land1.
step_merge2() {
    local w lf rc ref="${AC9_MERGE2_REF:-inc-pu6v}" cv
    if [ "$ref" = inc-pu6v ]; then [ -f "$RUN/land1.sha" ] || die "land1 has not finished"; fi
    refresh_labelled
    w="$(wt "$GOD")"; lf="$LOG/start-$GOD.log"
    if [ ! -d "$w" ]; then
        { git -C "$DIR" worktree add "$w" "$GOD" \
            && git -C "$DIR" config "branch.$GOD.incursionBase" inc-pu6v; } > "$lf" 2>&1; rc=$?
        if [ $rc -ne 0 ]; then steplog "start $GOD" "$rc" "$lf"; exit 1; fi
    fi
    # AC7 order, as for merge 1: Maeve's own field calls take names FIRST (master's converter, run on Maeve), then the epic merges in
    cv="$LOG/convert-$GOD.log"
    if git -C "$DIR" cat-file -e master:tools/convert_tags_to_names.py 2> /dev/null \
        && [ "$(git -C "$w" log --format=%s "inc-pu6v..HEAD" | grep -cF "port: convert god field tags to names ($GOD)")" = 0 ]; then
        [ -z "$(git -C "$w" status --porcelain --untracked-files=no)" ] || die "$w is not clean before the conversion" 2
        local f
        git -C "$DIR" show master:tools/convert_tags_to_names.py > "$STATE/tmp/convert_tags_to_names.py" 2> "$cv" \
            || { steplog "convert $GOD" 1 "$cv"; exit 1; }
        for f in number_values.py gen_legacy_tags.py; do
            git -C "$DIR" show "master:tools/$f" > "$STATE/tmp/$f" 2>> "$cv" || { steplog "convert $GOD" 1 "$cv"; exit 1; }
        done
        git -C "$DIR" show master:inc/SaveLegacyTags.h > "$STATE/tmp/SaveLegacyTags.h" 2>> "$cv" || { steplog "convert $GOD" 1 "$cv"; exit 1; }
        python3 "$STATE/tmp/convert_tags_to_names.py" --root "$w" --header "$STATE/tmp/SaveLegacyTags.h" --apply >> "$cv" 2>&1 || { steplog "convert $GOD" 1 "$cv"; exit 1; }
        git -C "$w" add -A && git -C "$w" commit -q -m "port: convert god field tags to names ($GOD)" \
            -m "Generated by master's tools/convert_tags_to_names.py --apply; no hand edit." >> "$cv" 2>&1 \
            || { steplog "convert $GOD" 1 "$cv"; exit 1; }
    fi
    merge_step merge2 "$w" "$ref" || exit 1
}

step_gate2() {
    local w lf rc
    w="$(wt "$GOD")"; [ -d "$w" ] || die "no $w: run merge2 first"
    [ -f "$RUN/merge2.sha" ] || die "merge2 has not finished"
    lf="$LOG/gate2.log"
    # the gate base of pre-merge Maeve (tools/nightly_verify.sh --record on the clone's 4ac7f9d5 in a detached worktree):
    # <run>/gate-base-maeve/. Without it the compare has no base and says so.
    local base2="$RUN/gate-base-maeve/nightly-verify-base.txt"
    [ -s "$base2" ] || die "no recorded gate base for pre-merge Maeve ($base2)"
    # the landing gate as tools/finish_bead.sh runs it, but nothing lands and no ledger row is written
    ( cd "$w" && NIGHTLY_VERIFY_STATE="$base2" INCURSION_LANDING_DIFF_REF="${AC9_MERGE2_REF:-inc-pu6v}" INCURSION_LANDING_VIA_SHARED=1 tools/nightly_verify.sh --landing ) > "$lf" 2>&1; rc=$?
    [ $rc -eq 0 ] || note_refusals gate2 "$lf"
    steplog gate2 "$rc" "$lf"
    exit "$([ $rc -eq 0 ] && echo 0 || echo 1)"
}

build_and_record() { # <tag> <tree>
    local tag="$1" tree="$2"
    ( cd "$tree" && BACKEND=posix ./build_macos.sh ) > "$LOG/values-build-$tag.log" 2>&1 \
        || { echo "ac9: the $tag build failed (log $LOG/values-build-$tag.log)" >&2; return 1; }
    rm -rf "$RUN/values/$tag"
    "$HERE/scratch.sh" record "$tree" "$RUN/values/$tag" > "$LOG/values-record-$tag.log" 2>&1 \
        || { echo "ac9: recording $tag failed: $(tail -2 "$LOG/values-record-$tag.log")" >&2; return 1; }
}

step_values() {
    local epic tree fx tag rc f n=0 bad=0 vf="$RUN/values.txt"
    [ -f "$RUN/merge2.sha" ] || die "merge2 has not finished"
    epic="$(wt epic)"
    if [ ! -d "$epic" ]; then git -C "$DIR" worktree add "$epic" inc-pu6v > "$LOG/values-epic-wt.log" 2>&1 || die "cannot make the epic worktree"; fi
    git -C "$epic" checkout -q --detach inc-pu6v || die "cannot move the epic worktree to inc-pu6v"
    build_and_record master "$DIR" || { steplog values 2 "$LOG/values-record-master.log"; exit 2; }
    build_and_record epic "$epic" || { steplog values 2 "$LOG/values-record-epic.log"; exit 2; }
    build_and_record maeve "$(wt "$GOD")" || { steplog values 2 "$LOG/values-record-maeve.log"; exit 2; }
    # the merged modules hold resources master lacks, so the module-shape lines may differ (never a pool that shrank)
    export INCURSION_PRESSURE_GROWS=1
    : > "$vf"
    for f in "$RUN"/values/master/*.txt; do
        fx="$(basename "$f")"
        for tag in epic maeve; do
            n=$((n + 1))
            if [ ! -f "$RUN/values/$tag/$fx" ]; then
                echo "FAIL $fx $tag: no record" >> "$vf"; bad=$((bad + 1)); continue
            fi
            tree="$epic"; [ "$tag" = maeve ] && tree="$(wt "$GOD")"
            ren=""; [ -f "$tree/tools/retired_field_names.txt" ] && ren="$tree/tools/retired_field_names.txt"
            INCURSION_PRESSURE_RENAME_FILE="$ren" python3 "$HERE/compare_values.py" "$f" "$RUN/values/$tag/$fx" > "$LOG/cmp-$tag-${fx%.txt}.log" 2>&1; rc=$?
            if [ $rc -eq 0 ]; then echo "PASS $fx master->$tag" >> "$vf"
            else echo "FAIL $fx master->$tag (rc $rc): $(grep -m1 -E 'changed|missing|FAIL' "$LOG/cmp-$tag-${fx%.txt}.log" | cut -c1-200)" >> "$vf"; bad=$((bad + 1)); fi
        done
    done
    [ "$n" -gt 0 ] || { echo "FAIL no master fixture was recorded" >> "$vf"; bad=1; }
    echo "VALUES $([ "$bad" -eq 0 ] && echo PASS || echo FAIL): $n comparison(s), $bad failed" >> "$vf"
    steplog values "$([ "$bad" -eq 0 ] && echo 0 || echo 1)" "$vf"
    exit "$([ "$bad" -eq 0 ] && echo 0 || echo 1)"
}

# values1 (E1: after merge 1, before the epic lands): every master fixture is a save master's own build holds, loaded by the
# merged build. A specimen and a chars/*.sav are files; a chars/*.char is the .sav master's binary builds from it
# (tools/fixture_cache.sh, run in the clone's master). The SAME save file is decoded by master's build and by the merged
# build (tools/pressure/field_values.sh), and compare_values.py compares the two records. <run>/values1.txt.
step_values1() {
    local m="$DIR" t sv name lab b n=0 bad=0 skipped=0 unmeasured=0 NO_BUILD="${INCURSION_AC9_NO_BUILD:-}" vf="$RUN/values1.txt" out="$RUN/values1" tag ren
    t="$(wt "$BEAD_M")"; [ -f "$RUN/merge1.sha" ] || die "merge1 has not finished"
    ( cd "$m" && BACKEND=posix ./build_macos.sh ) > "$LOG/values1-build-master.log" 2>&1 || { steplog values1 2 "$LOG/values1-build-master.log"; exit 2; }
    ( cd "$t" && BACKEND=posix ./build_macos.sh ) > "$LOG/values1-build-merged.log" 2>&1 || { steplog values1 2 "$LOG/values1-build-merged.log"; exit 2; }
    rm -rf "$out"; mkdir -p "$out/master" "$out/merge1" "$out/saves"
    # the master saves, by label
    for sv in "$m"/tools/fixtures/specimens/*.sav; do [ -f "$sv" ] && cp "$sv" "$out/saves/specimens__$(basename "$sv")"; done
    for sv in "$m"/tools/fixtures/chars/*.sav; do [ -f "$sv" ] && cp "$sv" "$out/saves/chars__$(basename "$sv")"; done
    : > "$vf"
    for sv in "$m"/tools/fixtures/chars/*.char; do
        name="$(basename "$sv" .char)"
        # a .char master's own binary cannot build is no merge question: SKIP, listed, not counted. NO_BUILD (empty by
        # default; the coordinator measured orc-mage-seed5-opt0822 under 90 s on master and merged) names a fixture whose
        # build never ends; it is then UNMEASURED in the comparison, never excluded from it.
        b=""
        if [[ " $NO_BUILD " == *" $name "* ]]; then
            echo "(master's own build never ends)" > "$out/saves/$name.build.err"; unmeasured=$((unmeasured + 1))
            echo "UNMEASURED char__$name: master's own build never ends" >> "$vf"
        else
            b="$( cd "$m" && env -u INCURSION_LOAD -u INCURSION_OPTIONS -u INCURSION_RUN_DIR INCURSION_BIN="$m/incursion-headless" tools/fixture_cache.sh "$name" 2> "$out/saves/$name.build.err" )"
        fi
        if [ -n "$b" ] && [ -f "$b" ]; then
            cp "$b" "$out/saves/char__$name.sav"
        else
            echo "SKIP char__$name: master could not build its own fixture: $(tail -1 "$out/saves/$name.build.err" | cut -c1-160)" >> "$vf"; skipped=$((skipped + 1))
        fi
    done
    # THE VALUES1 RULE (inc-cjos0 AC9, coordinator ruling): a master value line passes when it is unchanged in the merged
    # build, OR is a module-shape line (GROWS), OR is a field or script variable the merged tree no longer has AND whose
    # master value is 0 (REMOVED_ZERO). A removed field holding a nonzero master value FAILS and is listed.
    export INCURSION_PRESSURE_GROWS=1 INCURSION_PRESSURE_REMOVED_ZERO=1 INCURSION_PRESSURE_RENAMES="$(renames_env)"
    ren=""; [ -f "$t/tools/retired_field_names.txt" ] && ren="$t/tools/retired_field_names.txt"
    for sv in "$out"/saves/*.sav; do
        lab="$(basename "$sv" .sav)"; n=$((n + 1))
        if ! "$HERE/field_values.sh" "$m" "$sv" "$out/master/$lab.txt" 2> "$out/master/$lab.err"; then
            echo "FAIL $lab: master's build could not decode its own save: $(head -c 160 "$out/master/$lab.err")" >> "$vf"; bad=$((bad + 1)); continue
        fi
        if ! "$HERE/field_values.sh" "$t" "$sv" "$out/merge1/$lab.txt" 2> "$out/merge1/$lab.err"; then
            echo "FAIL $lab: the merged build could not load it: $(head -c 160 "$out/merge1/$lab.err")" >> "$vf"; bad=$((bad + 1)); continue
        fi
        INCURSION_PRESSURE_RENAME_FILE="$ren" python3 "$HERE/compare_values.py" "$out/master/$lab.txt" "$out/merge1/$lab.txt" > "$LOG/cmp1-$lab.log" 2>&1; rc=$?
        if [ $rc -eq 0 ]; then echo "PASS $lab master->merge1" >> "$vf"
        else
            echo "FAIL $lab master->merge1 (rc $rc): $(grep -c -E '^(changed|missing)' "$LOG/cmp1-$lab.log") failing line(s)" >> "$vf"
            grep -E '^(changed|missing)' "$LOG/cmp1-$lab.log" | head -20 | cut -c1-240 | sed 's/^/     /' >> "$vf"; bad=$((bad + 1))
        fi
    done
    bad=$((bad + unmeasured))   # an UNMEASURED save is no pass
    echo "VALUES1 $([ "$bad" -eq 0 ] && echo PASS || echo FAIL): $n master save(s) compared, $((n - bad)) passed, $bad failed, $unmeasured unmeasured, $skipped skipped (master could not build its own .char)" >> "$vf"
    steplog values1 "$([ "$bad" -eq 0 ] && echo 0 || echo 1)" "$vf"
    exit "$([ "$bad" -eq 0 ] && echo 0 || echo 1)"
}

step_report() {
    local r="$RUN/results.md" name
    python3 - "$RUN" > "$r" <<'PY'
import os, re, sys
run = sys.argv[1]
def rd(p):
    return open(os.path.join(run, p), encoding="utf-8", errors="replace").read() if os.path.exists(os.path.join(run, p)) else None
print("# AC9 results\n")
print("Clone: " + (rd("pressure-state/clone.txt") or "missing").replace("\n", "; ") + "\n")
print("## Steps (exit and deciding line; later runs of a step replace earlier ones)\n")
last = {}
for ln in (rd("ac9-steps.tsv") or "").splitlines():
    p = ln.split("\t")
    if len(p) >= 3:
        last[p[0]] = p
for s in ("merge1", "land1", "merge2", "gate2", "values"):
    p = last.get(s)
    print("- %s: %s" % (s, ("exit %s: %s" % (p[1], p[2])) if p else "NOT RUN"))
print("\n## Refusals\n")
SPACE = re.compile(r"family [A-Za-z_]+|stati|space|pool|range|collid|same (stored )?(number|value)", re.I)
ref = [l for l in (rd("refusals.txt") or "").splitlines() if l.strip()]
if not ref:
    print("none recorded")
for l in ref:
    lab, _, text = l.partition("\t")
    print("- [%s] names a space: %s | %s" % (lab, "yes" if SPACE.search(text) else "no", text))
print("\n## Conflicts the resolve dir covered or did not\n")
for s in ("merge1", "merge2"):
    c = rd(s + "-conflicts.txt")
    print("- %s: %s" % (s, ("UNRESOLVED: " + c.replace("\t", " ").replace("\n", "; ")) if c else "none left"))
print("\n## Values\n")
v = rd("values.txt")
print(v if v else "NOT RUN (values step)")
print("\n## Numbers edited by hand\n")
for s in ("merge1", "merge2"):
    a = rd(s + "-attrib.txt")
    print("### %s\n" % s)
    print("```\n" + (a.strip() if a else "NO VERDICT (step not run, or no tool could establish it): FAIL") + "\n```")
PY
    echo "ac9: wrote $r"
    grep -q 'NUMBERS-BY-HAND PASS' "$RUN/merge1-attrib.txt" 2>/dev/null && grep -q 'NUMBERS-BY-HAND PASS' "$RUN/merge2-attrib.txt" 2>/dev/null \
        && grep -q '^VALUES PASS' "$RUN/values.txt" 2>/dev/null
    local rc=$?
    echo "ac9: report verdict $([ $rc -eq 0 ] && echo PASS || echo FAIL)"
    exit "$rc"
}

case "$STEP" in
    base)   step_base ;;
    m10v7f) step_m10v7f ;;
    land10) step_land10 ;;
    merge1) step_merge1 ;;
    land1)  step_land1 ;;
    merge2) step_merge2 ;;
    attrib2) attribute_check merge2 "$(wt "$GOD")"; rc=$?; cat "$RUN/merge2-attrib.txt"; exit "$rc" ;;   # the numbers-by-hand check alone, on the committed merge2
    gate2)  step_gate2 ;;
    values1) step_values1 ;;
    values) step_values ;;
    report) step_report ;;
    *) die "unknown step $STEP" ;;
esac
