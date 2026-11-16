#!/bin/bash
# Run one AC8 case through one real merge route in a scratch repository (inc-cjos0 phase 8, D2).
#
#   tools/pressure/route.sh <dir> <route> <case-dir>
#
# <dir> is a repository made by `tools/pressure/scratch.sh make` (under logs/phase8/d2/). <route> is M, E, G, or H.
# <case-dir> holds A.patch, B.patch, optional P.patch (applied by scratch.sh make, not here), optional witness.sh,
# `expect` (`works`, or `refuse <space regex>`), and optional `recover-named` (a regex the first refusal MUST match
# when a works run needed the mover recovery, routes M and G) and `mover-named` (a regex the mover's output MUST
# match on route E).
#
# The routes, as logs/phase8/ac8-cases.md "Routes" defines them. Every landing is the real tools/worktree.sh and
# tools/finish_bead.sh of the scratch repository; the only substitution is INCURSION_FINISH_GATE (owner ruling
# 2026-11-07): the 32-66 minute landing gate becomes tools/pressure/oracle.sh, the case oracle.
#   M  A and B both branch from master. Land A, then land B (finish_bead merges A's master into B first).
#   E  B branches from the epic inc-pu6v, A from master. Land B on the epic, land A on master, then start a
#      merge bead from the epic, `git merge master` in it, and land it on the epic.
#   G  A and B both branch from the epic; master stays P. Land A on the epic, then land B on the epic (finish_bead
#      merges the epic into B first, then builds and loads in the oracle). The mover and the checks use their
#      default master reference, which is P.
#   R  Repeated merges (G32). B (epic bead) lands on the epic; A (master bead, A.patch) lands on master; merge bead 1
#      merges master into the epic and lands; god bead C (C.patch) is forked from the epic; A2 (A2.patch) lands on
#      master; merge bead 2 merges master into the epic again and lands; then C (epic merged into the god branch)
#      lands on the epic. Beads inc-<case>a, b, c (A2), d (C), m, n. `mover-named` judges merge 1, `mover-named.2` merge 2.
#   H  F10 only. A and B both branch from master. Land A, then hand-merge master into B with `git merge
#      --no-verify`, then run the normal headless build.
# A case dir may hold plant.P (content planted in P's own build, before any landing), plant.A / plant.B (a spec for tools/pressure/plant.sh: content that side adds, by symbolic
# name) and plant-fixture (the fixture name to plant in; default the first fixture). A landing of side A or B runs
# the planter in the oracle with the build it just made; after the landing succeeds the new content save and its
# value file (the baseline, from that pre-merge build) are kept in <run>/pressure-state/content/. Every later
# landing's oracle loads each kept save and compares. A landing on master scores it (INCURSION_PRESSURE_PLANT_
# SCORED=1); one on the epic does not (an epic save is disposable).
# The baseline of P is shared by the routes of a case (and of a pressure_numbers.sh run): <d2>/baseline-cache/<tree>.
# Where a landing stops because tools/move_branch_values.py moved values (or a refusal that the mover can
# repair), the driver commits the mover's generated diff on the bead branch and retries ONCE. A git text conflict
# is resolved ONLY from the case's committed resolution, <case-dir>/resolve/<path> (one file per conflicted path; the
# format is in tools/pressure/resolve_conflict.py); a conflict with no resolution, or a resolution that does not fit,
# FAILS the case. A case with a resolve/ dir merges the base into each bead before finish_bead.sh runs, so the route
# resolves the conflict wherever it arises. When the resolved merge commit is refused by the pre-commit fast checks (two
# sides chose one stored number), a works run does what a developer does: tools/move_branch_values.py, stage, commit the
# merge (that refusal is the case's mover recovery, judged by recover-named); a refuse run records the refusal.
#
# What each landing runs (D5, owner ruling 2026-11-08: build only where a save is loaded). LAND_KIND is `source` (the
# three source checks that need no binary, no build) or `full` (build or module-only rebuild, 74-fixture compare, content, witness):
#   side A landing on master   full only when the case has plant.A, or plant.P (A's tree must still load P's content)
#   side B landing on the epic source always; a plant.B is skipped and the verdict reason says so
#   the merged landing         full always: the merge bead on E, B on M, the god landing on G, every landing of R after
#                              the first merge
# A source landing records no values, so the next baseline is the one the landing was given.
#
# Per step it records: command, exit, deciding line, source and destination SHAs, whether the destination advanced,
# whether git conflicted, seconds (<run>/steps.tsv, full output in <run>/log/).
#
# Last stdout line: `VERDICT <PASS|FAIL|UNMEASURED> <reason>`. Exit 0 PASS, 1 FAIL, 2 UNMEASURED.
#
# fact: this working tree's snapshot P -- committed by scratch.sh make; the run records its SHA
# fact: the case oracle -- tools/pressure/oracle.sh with frozen fixtures tools/fixtures/chars/*.sav; no seed, no key script
# fact: memory pressure -- tools/load_guard.sh of the scratch repository, the real guard; a refusal is UNMEASURED
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
unset INCURSIONPATH INCURSION_LOAD INCURSION_OPTIONS INCURSION_RUN_DIR
[ $# -eq 3 ] || { echo "usage: $0 <dir> <route> <case-dir>" >&2; exit 2; }
DIR="$(cd "$1" && pwd -P)" || exit 2
ROUTE="$2"
CASE="$(cd "$3" && pwd -P)" || exit 2
case "$DIR" in */logs/phase8/d2/*) ;; *) echo "route: REFUSED: $DIR is not under logs/phase8/d2/" >&2; exit 2;; esac
[ -d "$DIR/.git" ] || { echo "route: $DIR is not a scratch repository" >&2; exit 2; }
case "$ROUTE" in M|E|G|H|R) ;; *) echo "route: unknown route $ROUTE" >&2; exit 2;; esac
RUN="$(dirname "$DIR")"
STATE="$RUN/pressure-state"
[ -x "$STATE/bin/bd" ] || { echo "route: no fake bd in $STATE" >&2; exit 2; }
LOG="$RUN/log"; STEPS="$RUN/steps.tsv"
mkdir -p "$LOG" "$STATE/values" "$STATE/tmp" || exit 2
: > "$STEPS"
export PATH="$STATE/bin:$PATH" TMPDIR="$STATE/tmp" INCURSION_LOAD_GUARD_LOG="$STATE/load-guard.log" \
    INCURSION_FINISH_LOCK_POLL=1
export GIT_AUTHOR_NAME="AC8 pressure driver" GIT_COMMITTER_NAME="AC8 pressure driver"
export GIT_AUTHOR_EMAIL=pressure@example.invalid GIT_COMMITTER_EMAIL=pressure@example.invalid

# The binaries of C++ trees this suite built, shared by every run (tools/pressure/srchash.sh names a tree): the oracle
# of a merged landing reuses the one whose C++ sources equal its own and recompiles only the module (D5).
export INCURSION_PRESSURE_BINCACHE="$(dirname "$(dirname "$(dirname "$RUN")")")/bin-cache"

CASE_NAME="$(basename "$CASE")"
SLUG="$(printf '%s' "$CASE_NAME" | tr 'A-Z' 'a-z' | tr -cd 'a-z0-9')"
BEAD_A="inc-${SLUG}a"; BEAD_B="inc-${SLUG}b"; BEAD_M="inc-${SLUG}m"
BEAD_A2="inc-${SLUG}c"; BEAD_C="inc-${SLUG}d"; BEAD_M2="inc-${SLUG}n"   # route R only
# A case that changes the module (adds resources: a `grows-module` file; renames or retires one: a `renames` file)
# changes the module-shape lines of every save by construction: compare_values.py then lets those lines differ
# (never a pool that shrank). A case with neither file keeps the shape lines strict.
unset INCURSION_PRESSURE_GROWS
{ [ -f "$CASE/grows-module" ] || [ -f "$CASE/renames" ]; } && export INCURSION_PRESSURE_GROWS=1
# A case that renames a resource on purpose lists the pairs in a `renames` file (old>new|old>new): compare_values.py
# reads a resource value that names the old resource before and the new one after as the same resource.
unset INCURSION_PRESSURE_RENAMES
[ -f "$CASE/renames" ] && export INCURSION_PRESSURE_RENAMES="$(head -1 "$CASE/renames")"
# `expect.<ROUTE>` (when present) overrides `expect` for that route: a case may work on M and E and refuse on G.
EXPECT_FILE="$CASE/expect"; [ -f "$CASE/expect.$ROUTE" ] && EXPECT_FILE="$CASE/expect.$ROUTE"
EXPECT_LINE="$(head -1 "$EXPECT_FILE" 2>/dev/null)"
EXPECT="${EXPECT_LINE%% *}"; EXPECT_RE=""
[ "$EXPECT" = refuse ] && EXPECT_RE="${EXPECT_LINE#refuse }"
case "$EXPECT" in works|refuse) ;; *) echo "route: $EXPECT_FILE must say works or refuse <regex>" >&2; exit 2;; esac
# The oracle counts an engine refusal at fixture load as a refusal (not "could not measure") when it names the space.
unset INCURSION_PRESSURE_REFUSAL_RE
[ "$EXPECT" = refuse ] && export INCURSION_PRESSURE_REFUSAL_RE="$EXPECT_RE"
RECOVER_RE="$(head -1 "$CASE/recover-named" 2>/dev/null || true)"
ORACLE="$DIR/tools/pressure/oracle.sh"
[ -f "$ORACLE" ] || { echo "route: no $ORACLE in the scratch repository" >&2; exit 2; }
WITNESS=""; [ -f "$CASE/witness.sh" ] && WITNESS="$CASE/witness.sh"
CONTENT="$STATE/content"; rm -rf "$CONTENT"; mkdir -p "$CONTENT" || exit 2
PLANT_FIXTURE="$(head -1 "$CASE/plant-fixture" 2>/dev/null || true)"
[ -n "$PLANT_FIXTURE" ] || PLANT_FIXTURE="$(basename "$(ls "$DIR"/tools/fixtures/chars/*.sav | head -1)" .sav)"

NSTEP=0
RECOVERED_LINE=""
FIRST_FAIL_LABEL=""; FIRST_FAIL_LINE=""; FIRST_FAIL_LOG=""; FIRST_FAIL_KIND=""   # kind: refused|unmeasured|conflict

now() { date +%s; }
sha() { git -C "$DIR" rev-parse --short=10 "$1" 2>/dev/null || echo none; }

mkbead() { # <id> : a fake bead with one acceptance criterion
    printf '[{"id":"%s","status":"open","issue_type":"task","description":"## Acceptance Criteria\\n- the case oracle passes on the landed tree\\n","notes":""}]\n' "$1" > "$STATE/beads/$1.json"
}

wt() { printf '%s/Incursion-%s' "$RUN" "$1"; }

decide() { # <logfile> -> the deciding line, plus the first named refusal under it
    local l d
    l="$(grep -m1 -E '^(STOPPED|REFUSED|INCONCLUSIVE)' "$1")"
    [ -n "$l" ] || l="$(grep -m1 -E '^Landed\.' "$1")"
    [ -n "$l" ] || l="$(grep -m1 -E '^(pre-commit: (a fast check|REFUSED)|build: STOPPED|oracle: (PASS|FAIL|UNMEASURED)$)' "$1")"
    [ -n "$l" ] || l="$(grep -v -E '^[[:space:]]*$|^beads:' "$1" | tail -1)"
    [ -n "$l" ] || l=ok
    d="$(grep -m1 -E '^[[:space:]]*(REFUSED|FAIL): ' "$1" | sed 's/^[[:space:]]*//')"
    printf '%s' "$l${d:+ | $d}" | tr '\t' ' ' | cut -c1-260
}

# record <label> <logfile> <rc> <src-ref> <dst-branch> <dst-before> <secs> [src-sha]
record() {
    local label="$1" lf="$2" rc="$3" src="$4" dst="$5" before="$6" secs="$7" srcsha="${8:-}" after adv conf kind
    [ -n "$srcsha" ] || srcsha="$(sha "$src")"
    after="$(sha "$dst")"
    adv=no; [ "$before" != "$after" ] && adv=yes
    conf=no; grep -qE 'CONFLICT|does not merge cleanly' "$lf" && conf=yes
    NSTEP=$((NSTEP + 1))
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$NSTEP" "$label" "$rc" "$(decide "$lf")" "$srcsha" \
        "$before" "$after" "$adv" "$conf" "$secs" >> "$STEPS"
    echo "route: step $NSTEP $label rc=$rc dest=$dst $before->$after advanced=$adv conflict=$conf (${secs}s) $(decide "$lf")"
    if [ "$rc" -ne 0 ] && [ -z "$FIRST_FAIL_LABEL" ]; then
        kind=refused
        [ "$rc" -eq 2 ] && kind=unmeasured
        [ "$conf" = yes ] && kind=conflict
        grep -q '^oracle: UNMEASURED$' "$lf" && kind=unmeasured
        FIRST_FAIL_LABEL="$label"; FIRST_FAIL_LOG="$lf"; FIRST_FAIL_KIND="$kind"
        FIRST_FAIL_LINE="$(decide "$lf")"
    fi
    return 0
}

verdict() { # <PASS|FAIL|UNMEASURED> <reason>
    echo "VERDICT $1 $2"
    case "$1" in PASS) exit 0;; FAIL) exit 1;; *) exit 2;; esac
}

# start <bead> [base]: tools/worktree.sh from the scratch repository.
start_bead() {
    mkbead "$1"
    local lf="$LOG/start-$1.log" rc
    ( cd "$DIR" && tools/worktree.sh "$@" ) > "$lf" 2>&1; rc=$?
    [ $rc -eq 0 ] || { record "start $1" "$lf" "$rc" HEAD master "$(sha master)" 0; return $rc; }
    return 0
}

# patch_bead <bead> <patch>: apply and commit on the bead branch, through the hooks. A patch that changes lib/ is built
# first: the real pre-commit hook refuses a lib/ change the worktree's module was not built from.
patch_bead() {
    local id="$1" patch="$2" w lf rc t0
    w="$(wt "$id")"; lf="$LOG/commit-$id.log"; t0=$(now)
    {
        git -C "$w" apply "$patch" \
          && { ! grep -qE '^diff --git a/lib/' "$patch" || ( cd "$w" && BACKEND=posix ./build_macos.sh ); } \
          && git -C "$w" add -A \
          && git -C "$w" commit -q -m "tools: $id case patch for $CASE_NAME" \
               -m "AC1: the case oracle loads every fixture in the landed tree and compares its field values"
    } > "$lf" 2>&1; rc=$?
    record "commit $id" "$lf" "$rc" "$id" "$id" "$(sha "$id")" $(( $(now) - t0 ))
    return $rc
}

# merge_in <worktree> <base> <logfile>: `git merge --no-edit <base>` in a bead worktree. A conflict is resolved from
# $CASE/resolve/ (tools/pressure/resolve_conflict.py) and the merge committed; with no resolution it stays a conflict
# (rc 1, the log says CONFLICT) and the case fails. rc 0 merged (cleanly or by resolution), 1 conflict unresolved,
# 3 resolved but the pre-commit checks refused the merge commit: the merge stays in progress, the refusal output is
# in the log and in MERGE_REFUSED_LOG (<log>-commit.log), and `land` decides what follows (premerge_refused).
MERGE_REFUSED_LOG=""
merge_in() {
    local w="$1" b="$2" lf="$3" rc crc cl="${3%.log}-commit.log"
    git -C "$w" merge --no-edit "$b" > "$lf" 2>&1; rc=$?
    [ $rc -eq 0 ] && return 0
    if [ -z "$(git -C "$w" diff --name-only --diff-filter=U)" ]; then return $rc; fi
    if [ ! -d "$CASE/resolve" ]; then
        echo "route: FAIL: CONFLICT merging $b, and $CASE has no resolve/ directory with a resolution" >> "$lf"; return 1
    fi
    python3 "$HERE/resolve_conflict.py" "$w" "$CASE/resolve" >> "$lf" 2>&1 || { echo "route: CONFLICT is unresolved" >> "$lf"; return 1; }
    git -C "$w" commit --no-edit > "$cl" 2>&1; crc=$?
    cat "$cl" >> "$lf"
    if [ $crc -ne 0 ]; then MERGE_REFUSED_LOG="$cl"; return 3; fi
    echo "route: the conflict was resolved from $CASE/resolve" >> "$lf"
    return 0
}

# close_open_merge <worktree>: a merge left open by merge_in rc 3 is committed with the mover's changes inside it. The
# evidence commit that follows is an ordinary commit, because the AC check reads non-merge commits only.
close_open_merge() {
    git -C "$1" rev-parse -q --verify MERGE_HEAD > /dev/null || return 0
    git -C "$1" add -A && git -C "$1" commit -q --no-edit
}

# premerge_refused <bead> <base> <merge-log> <refusal-log>: the resolved merge commit was refused (merge_in rc 3).
# A refuse run records the refusal (kind refused, destination not advanced) and aborts the merge. A works run runs the
# unchanged mover in the bead worktree, stages its changes and commits the merge; a second refusal fails the landing.
# rc 0 the merge is committed, 1 the step is recorded as failed.
premerge_refused() {
    local id="$1" base="$2" lf="$3" cl="$4" w out moved line rlf rc cc
    w="$(wt "$id")"
    if [ "$EXPECT" = refuse ]; then
        git -C "$w" merge --abort >> "$lf" 2>&1
        record "merge $base into $id" "$cl" 1 "$base" "$base" "$(sha "$base")" 0
        return 1
    fi
    rlf="$LOG/recover-$id.log"
    out="$( cd "$w" && python3 tools/move_branch_values.py 2>&1 )"
    printf '%s\n' "$out" > "$rlf"
    line=""
    [ -z "$RECOVER_RE" ] || line="$(grep -vE '^[[:space:]]*KNOWN:' "$cl" | grep -m1 -E "$RECOVER_RE" | sed 's/^[[:space:]]*//' | cut -c1-200)"
    [ -n "$line" ] || line="$(grep -m1 -E '^[[:space:]]*FAIL: family |^stati |^[a-z_0-9]+ [A-Za-z_0-9]+ .* -> ' "$cl" | sed 's/^[[:space:]]*//' | cut -c1-200)"
    RECOVERED_LINE="${line:-$(decide "$cl")}"
    cc="$LOG/premerge-$id-$LAND_N-recommit.log"
    { git -C "$w" add -A && git -C "$w" commit --no-edit -q; } > "$cc" 2>&1; rc=$?
    if [ $rc -ne 0 ]; then
        RECOVERED_LINE=""
        record "merge $base into $id (commit after the mover)" "$cc" 1 "$base" "$id" "$(sha "$id")" 0
        return 1
    fi
    echo "route: the merge commit of $id was refused; the mover's diff was added and the merge committed" >> "$lf"
    return 0
}

# land <bead> <base> <baseline-dir> <base-sha>: tools/finish_bead.sh with the case oracle as its gate.
# Sets LAND_RC and LAND_VALUES (the oracle's after-values of this attempt).
LAND_N=0
LAND_KIND=full; SKIPPED_PLANTS=""
a_kind() { # the kind of a landing of side A on master
    LAND_KIND=source
    { [ -f "$CASE/plant.A" ] || [ -f "$CASE/plant.P" ]; } && LAND_KIND=full
    return 0
}
keep_baseline() { # <dest> <fallback>: the values the landing recorded, or (a source landing) the baseline it was given
    rm -rf "$1"
    if [ -d "$LAND_VALUES/values" ]; then cp -R "$LAND_VALUES/values" "$1"; else cp -R "$2" "$1"; fi
}
land() {
    local id="$1" base="$2" bl="$3" bsha="$4" lf rc t0 before srcsha
    LAND_N=$((LAND_N + 1))
    lf="$LOG/land-$id-$LAND_N.log"; before="$(sha "$base")"; t0=$(now); srcsha="$(sha "$id")"
    if [ -d "$CASE/resolve" ] && [ -d "$(wt "$id")" ]; then
        # a case with a deliberate conflict merges the base here, so the driver can resolve it (finish_bead.sh then finds it merged)
        merge_in "$(wt "$id")" "$base" "$LOG/premerge-$id-$LAND_N.log"; rc=$?
        if [ $rc -eq 3 ]; then
            premerge_refused "$id" "$base" "$LOG/premerge-$id-$LAND_N.log" "$MERGE_REFUSED_LOG"; rc=$?
            [ $rc -eq 0 ] || { LAND_RC=$rc; return $rc; }
        elif [ $rc -ne 0 ]; then
            record "merge $base into $id" "$LOG/premerge-$id-$LAND_N.log" "$rc" "$base" "$id" "$(sha "$id")" 0
            LAND_RC=$rc; return $rc
        fi
    fi
    land_attempt "$id" "$base" "$bl" "$bsha" "$lf"; rc=$?
    record "land $id on $base" "$lf" "$rc" "$id" "$base" "$before" $(( $(now) - t0 )) "$srcsha"
    LAND_RC=$rc
    return $rc
}

# land_attempt <bead> <base> <baseline-dir> <base-sha> <logfile>: one finish_bead.sh run
land_attempt() {
    local id="$1" base="$2" bl="$3" bsha="$4" lf="$5" rc
    LAND_VALUES="$STATE/values/$id-$LAND_N"; rm -rf "$LAND_VALUES"; mkdir -p "$LAND_VALUES"
    local ptag="" pspec="" pscored=0
    case "$id" in "$BEAD_A") ptag=A;; "$BEAD_B") ptag=B;; "$BEAD_A2") ptag=A2;; "$BEAD_C") ptag=C;; esac
    [ -n "$ptag" ] && [ -f "$CASE/plant.$ptag" ] && pspec="$CASE/plant.$ptag"
    [ "$base" = master ] && pscored=1
    if [ "$LAND_KIND" = source ]; then
        [ -n "$pspec" ] && { SKIPPED_PLANTS="${SKIPPED_PLANTS}${SKIPPED_PLANTS:+, }plant.$ptag skipped on $id (source landing)"; echo "route: plant.$ptag SKIPPED: $id lands as a source landing"; }
        pspec=""
    fi
    echo "route: $id lands on $base as a $LAND_KIND landing"
    ( cd "$DIR" \
      && INCURSION_BASE_BRANCH="$base" INCURSION_FINISH_GATE="$ORACLE" \
         INCURSION_PRESSURE_BASELINE="$bl" INCURSION_PRESSURE_BASE_SHA="$bsha" \
         INCURSION_PRESSURE_VALUES_OUT="$LAND_VALUES" INCURSION_PRESSURE_WITNESS="$WITNESS" \
         INCURSION_PRESSURE_PLANT="$pspec" INCURSION_PRESSURE_PLANT_TAG="$ptag" \
         INCURSION_PRESSURE_PLANT_FIXTURE="$PLANT_FIXTURE" INCURSION_PRESSURE_PLANT_SCORED="$pscored" \
         INCURSION_PRESSURE_CONTENT="$CONTENT" INCURSION_PRESSURE_LANDING="$LAND_KIND" \
         tools/finish_bead.sh "$id" ) > "$lf" 2>&1
    rc=$?
    # content planted by a landing that went through becomes the baseline of every later landing
    if [ $rc -eq 0 ] && [ -d "$LAND_VALUES/content-new" ]; then
        cp -f "$LAND_VALUES"/content-new/* "$CONTENT"/
        # the save is readable only in a tree that holds this commit (content_check.sh)
        for cs in "$LAND_VALUES"/content-new/*.sav; do
            [ -f "$cs" ] && git -C "$DIR" rev-parse "$base" > "$CONTENT/$(basename "$cs" .sav).commit"
        done
    fi
    return $rc
}

# recover <bead> : the mover's generated diff, committed on the bead branch. 0 committed, 1 nothing to commit.
recover() {
    local id="$1" w lf out moved
    w="$(wt "$id")"; lf="$LOG/recover-$id.log"
    [ -d "$w" ] || return 1
    if [ -z "$(git -C "$w" status --porcelain)" ]; then
        out="$( cd "$w" && python3 tools/move_branch_values.py 2>&1 )"
        printf '%s\n' "$out" > "$lf"
        moved="$(printf '%s\n' "$out" | sed -n 's/^move_branch_values: moved \([0-9][0-9]*\) value.*/\1/p' | tail -1)"
        [ "${moved:-0}" -gt 0 ] || return 1
    fi
    {
        git -C "$w" status --porcelain
        git -C "$w" add -A \
          && git -C "$w" commit -q -m "tools: $id moved colliding stored values (tools/move_branch_values.py)" \
               -m "Generated by the unchanged mover; no hand edit."
    } >> "$lf" 2>&1 || return 1
    return 0
}

# land_with_recovery: land once; on a refusal of a works run, commit the mover's diff and land once more.
land_with_recovery() { # <bead> <base> <baseline> <base-sha>
    land "$@" && return 0
    [ "$EXPECT" = works ] || return "$LAND_RC"
    [ "$LAND_RC" -eq 1 ] || return "$LAND_RC"
    local first_log="$LOG/land-$1-$LAND_N.log" line
    grep -qE 'CONFLICT|does not merge cleanly' "$first_log" && return 1
    if recover "$1"; then
        line=""
        [ -z "$RECOVER_RE" ] || line="$(grep -vE '^[[:space:]]*KNOWN:' "$first_log" | grep -m1 -E "$RECOVER_RE" | sed 's/^[[:space:]]*//' | cut -c1-200)"
        [ -n "$line" ] || line="$(grep -m1 -E '^[[:space:]]*FAIL: family |^stati |^[a-z_0-9]+ [A-Za-z_0-9]+ .* -> ' "$first_log" | sed 's/^[[:space:]]*//' | cut -c1-200)"
        RECOVERED_LINE="${line:-$(decide "$first_log")}"
        # the first failure was repaired: it no longer decides the verdict, unless the case names it
        local keep_label="$FIRST_FAIL_LABEL" keep_log="$FIRST_FAIL_LOG"
        FIRST_FAIL_LABEL=""; FIRST_FAIL_KIND=""
        echo "route: recovered $1 with the mover's diff; landing again"
        land "$@"
        local rc=$?
        if [ $rc -ne 0 ]; then FIRST_FAIL_LABEL="$keep_label"; FIRST_FAIL_LOG="$keep_log"; fi
        return $rc
    fi
    return "$LAND_RC"
}

finish_works() { # after the last landing
    local reason="$1"
    if [ -n "$RECOVERED_LINE" ]; then
        if [ -n "$RECOVER_RE" ] && ! printf '%s' "$RECOVERED_LINE" | grep -qE "$RECOVER_RE" \
           && ! cat "$LOG"/land-*-1.log 2>/dev/null | grep -vE '^[[:space:]]*KNOWN:' | grep -qE "$RECOVER_RE"; then
            verdict FAIL "recovered, but the first refusal did not name /$RECOVER_RE/ (line: $RECOVERED_LINE)"
        fi
        reason="$reason; first refusal then mover recovery: $RECOVERED_LINE"
    elif [ -n "$RECOVER_RE" ]; then
        verdict FAIL "the case expects a refusal naming /$RECOVER_RE/ then recovery, but every landing was accepted at once"
    fi
    verdict PASS "$reason${SKIPPED_PLANTS:+; $SKIPPED_PLANTS}"
}

finish_from_failure() { # the first failing step decides
    local kind="$FIRST_FAIL_KIND" label="$FIRST_FAIL_LABEL" lf="$FIRST_FAIL_LOG" line="$FIRST_FAIL_LINE" named
    [ -n "$kind" ] || verdict UNMEASURED "internal: no failing step recorded"
    case "$kind" in
        unmeasured) verdict UNMEASURED "$label could not measure: $line";;
        conflict)   verdict FAIL "$label: git text conflict with no usable resolution (resolve/ of the case): $(grep -hm1 -E 'FAIL|CONFLICT' "$lf" | cut -c1-200)";;
    esac
    if [ "$EXPECT" = refuse ]; then
        named="$(grep -vE '^[[:space:]]*KNOWN:' "$lf" | grep -m1 -E "$EXPECT_RE" | sed 's/^[[:space:]]*//' | cut -c1-200)"   # KNOWN lines are the checks' standing notes, not the refusal
        local adv; adv="$(awk -F'\t' -v l="$label" '$2==l {a=$8} END{print a}' "$STEPS")"
        if [ -n "$named" ] && [ "$adv" != yes ]; then
            verdict PASS "refused at $label naming the space, destination did not advance: $named"
        fi
        [ -n "$named" ] || verdict FAIL "refused at $label but no line names /$EXPECT_RE/ ($line)"
        verdict FAIL "refused at $label naming the space, but the destination advanced ($named)"
    fi
    verdict FAIL "refused at $label: $line"
}

# ------------------------------------------------------------------ the run
P_SHA="$(git -C "$DIR" rev-parse master)"
BL_P="$STATE/baseline-P"
echo "route: $CASE_NAME route=$ROUTE expect=$EXPECT P=$(sha master)"
t_base=$(now)
if [ ! -d "$BL_P" ]; then
    # the routes of a case share one baseline of P: the key is P's tree, which no route changes
    KEY="$(git -C "$DIR" rev-parse 'master^{tree}')"
    CACHE="$(dirname "$(dirname "$(dirname "$RUN")")")/baseline-cache/$KEY"
    if [ -d "$CACHE" ] && [ -f "$CACHE/.complete" ]; then
        cp -R "$CACHE" "$BL_P" && rm -f "$BL_P/.complete"
        echo "route: baseline of P taken from the shared cache ($(( $(now) - t_base ))s)"
    else
        "$HERE/scratch.sh" baseline "$DIR" "$BL_P" > "$LOG/baseline-P.log" 2>&1; rc=$?
        echo "route: baseline of P recorded (rc=$rc, $(( $(now) - t_base ))s)"
        [ $rc -eq 0 ] || verdict UNMEASURED "the baseline of P could not be recorded (see $LOG/baseline-P.log)"
        mkdir -p "$(dirname "$CACHE")" && rm -rf "$CACHE.tmp" && cp -R "$BL_P" "$CACHE.tmp" \
            && : > "$CACHE.tmp/.complete" && mv "$CACHE.tmp" "$CACHE"
    fi
fi
[ -z "$(git -C "$DIR" status --porcelain --untracked-files=no)" ] \
    || verdict UNMEASURED "the scratch master checkout is dirty after the baseline build: $(git -C "$DIR" status --porcelain --untracked-files=no | head -3 | tr '\n' ' ')"

# plant.P: content planted by P's own build (the scratch master checkout, P.patch applied) before any landing. Every
# landing's oracle loads it and compares with the values P's build recorded (scored: P is master).
if [ -f "$CASE/plant.P" ]; then
    ( cd "$DIR" && BACKEND=posix ./build_macos.sh ) > "$LOG/build-P.log" 2>&1 \
        || verdict UNMEASURED "the build of P for plant.P failed (see $LOG/build-P.log)"
    "$HERE/plant.sh" "$DIR" "$DIR/tools/fixtures/chars/$PLANT_FIXTURE.sav" "$CASE/plant.P" \
        "$CONTENT/P.sav" "$CONTENT/P.txt" > "$LOG/plant-P.log" 2>&1 \
        || verdict UNMEASURED "plant.P did not resolve in P's own build: $(head -c 200 "$LOG/plant-P.log")"
    echo "$PLANT_FIXTURE" > "$CONTENT/P.fixture"; : > "$CONTENT/P.scored"
    echo "route: planted plant.P in $PLANT_FIXTURE with P's own build"
fi

case "$ROUTE" in
M)
    start_bead "$BEAD_A" || finish_from_failure
    patch_bead "$BEAD_A" "$CASE/A.patch" || finish_from_failure
    start_bead "$BEAD_B" || finish_from_failure
    patch_bead "$BEAD_B" "$CASE/B.patch" || finish_from_failure
    a_kind
    land_with_recovery "$BEAD_A" master "$BL_P" "$P_SHA" || finish_from_failure
    BL_A="$STATE/baseline-A"; keep_baseline "$BL_A" "$BL_P"
    LAND_KIND=full
    land_with_recovery "$BEAD_B" master "$BL_A" "$(git -C "$DIR" rev-parse master)" || finish_from_failure
    [ "$EXPECT" = works ] || verdict FAIL "expected a refusal /$EXPECT_RE/, but both beads landed on master"
    finish_works "A then B landed on master; oracle passed on both"
    ;;
E)
    start_bead "$BEAD_B" inc-pu6v || finish_from_failure
    patch_bead "$BEAD_B" "$CASE/B.patch" || finish_from_failure
    start_bead "$BEAD_A" || finish_from_failure
    patch_bead "$BEAD_A" "$CASE/A.patch" || finish_from_failure
    LAND_KIND=source
    land_with_recovery "$BEAD_B" inc-pu6v "$BL_P" "$P_SHA" || finish_from_failure
    a_kind
    land_with_recovery "$BEAD_A" master "$BL_P" "$P_SHA" || finish_from_failure
    BL_A="$STATE/baseline-A"; keep_baseline "$BL_A" "$BL_P"
    MASTER_A="$(git -C "$DIR" rev-parse master)"
    # The merge bead: merge master (a merge commit runs no hook), run the unchanged mover, and commit ONLY its
    # generated reconciliation, with the evidence line. An evidence commit before the mover would be refused by the
    # real pre-commit fast set (the epic lacks A's value, or after the merge it holds both colliding names).
    start_bead "$BEAD_M" inc-pu6v || finish_from_failure
    mw="$(wt "$BEAD_M")"
    mlf="$LOG/merge-$BEAD_M.log"; t0=$(now)
    merge_in "$mw" master "$mlf"; mrc=$?
    [ $mrc -eq 3 ] && mrc=0   # resolved, commit refused: the merge stays open for the mover below, then mbead_commit
    record "merge master into $BEAD_M" "$mlf" "$mrc" master "$BEAD_M" "$(sha "$BEAD_M")" $(( $(now) - t0 ))
    [ $mrc -eq 0 ] || finish_from_failure
    mvlf="$LOG/mover-$BEAD_M.log"; t0=$(now)
    ( cd "$mw" && python3 tools/move_branch_values.py ) > "$mvlf" 2>&1; mvrc=$?
    record "move_branch_values on $BEAD_M" "$mvlf" "$mvrc" "$BEAD_M" "$BEAD_M" "$(sha "$BEAD_M")" $(( $(now) - t0 ))
    [ $mvrc -eq 0 ] || finish_from_failure
    MOVER_RE="$(head -1 "$CASE/mover-named" 2>/dev/null || true)"
    if [ -n "$MOVER_RE" ] && ! grep -qE "$MOVER_RE" "$mvlf"; then
        verdict FAIL "the mover's output does not match /$MOVER_RE/: $(grep -m1 '^move_branch_values' "$mvlf")"
    fi
    MOVED_LINE="$(grep -m1 -E '^move_branch_values: moved [0-9]+ value' "$mvlf")"
    MBEAD_MODE=empty
    if [ -n "$(git -C "$mw" status --porcelain)" ]; then
        MBEAD_MODE=mover
        RECOVERED_LINE="$(grep -m1 -E '^[a-z_0-9]+ [A-Za-z_0-9]+ .* -> ' "$mvlf" | cut -c1-200); $MOVED_LINE"
        echo "route: the mover changed files in the merge bead: $MOVED_LINE"
    fi
    mbead_commit() { # <logfile>
        close_open_merge "$mw" || return 1
        if [ "$MBEAD_MODE" = mover ]; then
            git -C "$mw" add -A \
              && git -C "$mw" commit -q --allow-empty -m "tools: $BEAD_M moved colliding stored values (tools/move_branch_values.py)" \
                   -m "AC1: the case oracle loads every fixture in the merged epic and compares its field values" \
                   -m "Generated by the unchanged mover; no hand edit."
        else
            git -C "$mw" commit -q --allow-empty -m "tools: $BEAD_M merges master into the epic for $CASE_NAME" \
                -m "AC1: the case oracle loads every fixture in the merged epic and compares its field values"
        fi > "$1" 2>&1
    }
    mbead_commit "$LOG/commit-$BEAD_M.log"; mrc=$?
    record "commit $BEAD_M" "$LOG/commit-$BEAD_M.log" "$mrc" "$BEAD_M" "$BEAD_M" "$(sha "$BEAD_M")" 0
    [ $mrc -eq 0 ] || finish_from_failure
    # A is master: the frozen master of this landing is master after A.
    EXPECT_SAVE="$EXPECT"
    LAND_KIND=full
    # a works run recovers from the mover's stop, as the route defines
    land_with_recovery "$BEAD_M" inc-pu6v "$BL_A" "$MASTER_A" || finish_from_failure
    [ "$EXPECT" = works ] || verdict FAIL "expected a refusal /$EXPECT_RE/, but the merge bead landed on the epic"
    RECOVER_RE=""   # the named first refusal belongs to the routes whose landing refuses (M, G); E's mover is judged above
    finish_works "B on the epic, A on master, merge bead landed on the epic; oracle passed on all three"
    ;;
G)
    start_bead "$BEAD_A" inc-pu6v || finish_from_failure
    patch_bead "$BEAD_A" "$CASE/A.patch" || finish_from_failure
    start_bead "$BEAD_B" inc-pu6v || finish_from_failure
    patch_bead "$BEAD_B" "$CASE/B.patch" || finish_from_failure
    LAND_KIND=source
    land_with_recovery "$BEAD_A" inc-pu6v "$BL_P" "$P_SHA" || finish_from_failure
    LAND_KIND=full
    land_with_recovery "$BEAD_B" inc-pu6v "$BL_P" "$P_SHA" || finish_from_failure
    [ "$EXPECT" = works ] || verdict FAIL "expected a refusal /$EXPECT_RE/, but the god bead landed on the epic"
    finish_works "A on the epic, then the god bead (epic merged in) landed on the epic; oracle passed on both"
    ;;
R)
    # merge_round <merge-bead> <baseline> <master-sha> <mover-regex-file>: merge master into a fresh epic bead, run the
    # unchanged mover, commit only its generated diff, land on the epic (the E route's merge bead, repeated).
    merge_round() {
        local mb="$1" bl="$2" msha="$3" mre="$4" mw mlf mvlf t0 mrc mvrc mode MOVER_RE MOVED_LINE mlog
        start_bead "$mb" inc-pu6v || finish_from_failure
        mw="$(wt "$mb")"; mlf="$LOG/merge-$mb.log"; t0=$(now)
        merge_in "$mw" master "$mlf"; mrc=$?
        [ $mrc -eq 3 ] && mrc=0   # resolved, commit refused: the merge stays open for the mover below
        record "merge master into $mb" "$mlf" "$mrc" master "$mb" "$(sha "$mb")" $(( $(now) - t0 ))
        [ $mrc -eq 0 ] || finish_from_failure
        mvlf="$LOG/mover-$mb.log"; t0=$(now)
        ( cd "$mw" && python3 tools/move_branch_values.py ) > "$mvlf" 2>&1; mvrc=$?
        record "move_branch_values on $mb" "$mvlf" "$mvrc" "$mb" "$mb" "$(sha "$mb")" $(( $(now) - t0 ))
        [ $mvrc -eq 0 ] || finish_from_failure
        MOVER_RE="$(head -1 "$CASE/$mre" 2>/dev/null || true)"
        if [ -n "$MOVER_RE" ] && ! grep -qE "$MOVER_RE" "$mvlf"; then
            verdict FAIL "the mover's output for $mb does not match /$MOVER_RE/: $(grep -m1 '^move_branch_values' "$mvlf")"
        fi
        MOVED_LINE="$(grep -m1 -E '^move_branch_values: moved [0-9]+ value' "$mvlf")"
        mode=empty
        if [ -n "$(git -C "$mw" status --porcelain)" ]; then
            mode=mover
            echo "route: the mover changed files in $mb: $MOVED_LINE"
            ROUND_MOVES="${ROUND_MOVES}${ROUND_MOVES:+; }$mb: $(grep -m1 -E '^[a-z_0-9]+ [A-Za-z_0-9]+ .* -> ' "$mvlf" | cut -c1-120)"
        fi
        mlog="$LOG/commit-$mb.log"
        if [ "$mode" = mover ]; then
            { close_open_merge "$mw" && git -C "$mw" add -A \
              && git -C "$mw" commit -q --allow-empty -m "tools: $mb moved colliding stored values (tools/move_branch_values.py)" \
                   -m "AC1: the case oracle loads every fixture in the merged epic and compares its field values" \
                   -m "Generated by the unchanged mover; no hand edit."; } > "$mlog" 2>&1; mrc=$?
        else
            close_open_merge "$mw" && git -C "$mw" commit -q --allow-empty -m "tools: $mb merges master into the epic for $CASE_NAME" \
                -m "AC1: the case oracle loads every fixture in the merged epic and compares its field values" > "$mlog" 2>&1; mrc=$?
        fi
        record "commit $mb" "$mlog" "$mrc" "$mb" "$mb" "$(sha "$mb")" 0
        [ $mrc -eq 0 ] || finish_from_failure
        land_with_recovery "$mb" inc-pu6v "$bl" "$msha" || finish_from_failure
    }
    ROUND_MOVES=""
    # round 1: B on the epic, A (A1) on master, merge bead 1; the god bead C forks from the epic after it
    start_bead "$BEAD_B" inc-pu6v || finish_from_failure
    patch_bead "$BEAD_B" "$CASE/B.patch" || finish_from_failure
    start_bead "$BEAD_A" || finish_from_failure
    patch_bead "$BEAD_A" "$CASE/A.patch" || finish_from_failure
    LAND_KIND=source
    land_with_recovery "$BEAD_B" inc-pu6v "$BL_P" "$P_SHA" || finish_from_failure
    a_kind
    land_with_recovery "$BEAD_A" master "$BL_P" "$P_SHA" || finish_from_failure
    BL_A1="$STATE/baseline-A1"; keep_baseline "$BL_A1" "$BL_P"
    LAND_KIND=full   # every landing after the first merge is merged: full
    MASTER_A1="$(git -C "$DIR" rev-parse master)"
    merge_round "$BEAD_M" "$BL_A1" "$MASTER_A1" mover-named
    # the god bead forks from the epic once the first merge landed, before the second (a tree that lacks master's
    # newest value is refused at commit by the stored-value check)
    start_bead "$BEAD_C" inc-pu6v || finish_from_failure
    patch_bead "$BEAD_C" "$CASE/C.patch" || finish_from_failure
    # round 2: A2 on master takes the next values; merge bead 2 merges master into the epic a second time
    start_bead "$BEAD_A2" || finish_from_failure
    patch_bead "$BEAD_A2" "$CASE/A2.patch" || finish_from_failure
    land_with_recovery "$BEAD_A2" master "$BL_A1" "$MASTER_A1" || finish_from_failure
    BL_A2="$STATE/baseline-A2"; keep_baseline "$BL_A2" "$BL_A1"
    MASTER_A2="$(git -C "$DIR" rev-parse master)"
    merge_round "$BEAD_M2" "$BL_A2" "$MASTER_A2" mover-named.2
    # round 3: the god branch (forked from the epic before round 2) takes the epic in, then lands on it
    land_with_recovery "$BEAD_C" inc-pu6v "$BL_A2" "$MASTER_A2" || finish_from_failure
    [ "$EXPECT" = works ] || verdict FAIL "expected a refusal /$EXPECT_RE/, but every landing went through"
    RECOVER_RE=""
    finish_works "B1 and A1, merge 1, A2, merge 2, then the god bead landed on the epic; oracle passed on every landing${ROUND_MOVES:+; moves: $ROUND_MOVES}"
    ;;
H)
    start_bead "$BEAD_A" || finish_from_failure
    patch_bead "$BEAD_A" "$CASE/A.patch" || finish_from_failure
    start_bead "$BEAD_B" || finish_from_failure
    patch_bead "$BEAD_B" "$CASE/B.patch" || finish_from_failure
    a_kind
    land "$BEAD_A" master "$BL_P" "$P_SHA" || finish_from_failure
    mlf="$LOG/handmerge-$BEAD_B.log"; t0=$(now); mb="$(sha "$BEAD_B")"
    git -C "$(wt "$BEAD_B")" merge --no-verify --no-edit master > "$mlf" 2>&1; mrc=$?
    record "hand merge (--no-verify) master into $BEAD_B" "$mlf" "$mrc" master "$BEAD_B" "$mb" $(( $(now) - t0 ))
    [ $mrc -eq 0 ] || finish_from_failure
    blf="$LOG/build-$BEAD_B.log"; t0=$(now); bb="$(sha "$BEAD_B")"
    ( cd "$(wt "$BEAD_B")" && BACKEND=posix ./build_macos.sh ) > "$blf" 2>&1; brc=$?
    record "headless build of $BEAD_B" "$blf" "$brc" "$BEAD_B" "$BEAD_B" "$bb" $(( $(now) - t0 ))
    [ $brc -eq 0 ] || finish_from_failure
    [ "$EXPECT" = works ] || verdict FAIL "expected a refusal /$EXPECT_RE/, but the hand-merged tree built"
    finish_works "hand merge built"
    ;;
esac
