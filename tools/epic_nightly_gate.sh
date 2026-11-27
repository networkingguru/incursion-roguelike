#!/usr/bin/env bash
# gate: none <why: it builds and runs the whole gate on the epic tip; the 05:45 launchd job calls it>
#
# Run the full gate on the inc-pu6v epic tip and report checks that turned red since the last night.
#   tools/epic_nightly_gate.sh             # build, record, compare, report
#   tools/epic_nightly_gate.sh --selftest  # test the comparison only; no git, no build
# The nightly gate runs on master only, so a master change can break epic checks unseen.
# This job uses a detached worktree of the epic, so it never makes a branch or a commit.
# State: incursion-epic-verify-<date>.txt (one `<exit><TAB><check>` line each) in $INCURSION_EPIC_GATE_STATE
# (default ~/Scripts/nightly-harness/state/incursion-epic: nightly_verify.sh writes its pass record beside the state).
# Report: <date>.md and latest.txt in $INCURSION_EPIC_GATE_REPORTS. Exit: 0 done, 1 build failed.

set -euo pipefail

# compare_states <old-file|""> <new-file>: print "NEWRED|STILLRED|FIXED|NEWCHECKRED|FIRSTRUN <name>" lines.
compare_states() {
    awk -F'\t' -v hasold="$([ -n "$1" ] && echo 1 || echo 0)" -v oldfile="$1" '
        hasold == 1 && FILENAME == oldfile { old[$2] = $1; next }
        {
            id = $2; rc = $1
            if (hasold == 0) { if (rc != 0) print "FIRSTRUN " id; next }
            if (!(id in old)) { if (rc != 0) print "NEWCHECKRED " id; next }
            if (old[id] == 0 && rc != 0) print "NEWRED " id
            else if (old[id] != 0 && rc != 0) print "STILLRED " id
            else if (old[id] != 0 && rc == 0) print "FIXED " id
        }' ${1:+"$1"} "$2"
}

# write_norecord <reports-dir> <date> <sha> <rc>: report and latest.txt for a gate that recorded nothing.
write_norecord() {
    local rep="$1/$2.md"
    {
        echo "# Epic gate $2"; echo
        echo "- Epic tip: $3"
        echo "- The gate recorded nothing: nightly_verify.sh --record exited $4 and wrote no state."
    } > "$rep"
    echo "$2 gate recorded nothing (record exit $4) -- $rep" > "$1/latest.txt"
}

selftest() {
    local d out fail=0
    d="$(mktemp -d)"; trap 'rm -rf "$d"' RETURN
    printf '0\ta\n0\tb\n1\tc\n1\td\n' > "$d/old"
    printf '1\ta\n0\tb\n1\tc\n0\td\n1\te\n0\tf\n' > "$d/new"
    out="$(compare_states "$d/old" "$d/new")"
    want=$'NEWRED a\nSTILLRED c\nFIXED d\nNEWCHECKRED e'
    [ "$out" = "$want" ] || { echo "FAIL compare: got: $out"; fail=1; }
    out="$(compare_states "" "$d/new")"
    want=$'FIRSTRUN a\nFIRSTRUN c\nFIRSTRUN e'
    [ "$out" = "$want" ] || { echo "FAIL first run: got: $out"; fail=1; }
    write_norecord "$d" 2026-01-02 abc123 7
    grep -q 'exited 7' "$d/2026-01-02.md" && grep -q 'recorded nothing (record exit 7) -- ' "$d/latest.txt" \
        || { echo "FAIL norecord report"; fail=1; }
    [ "$fail" = 0 ] && echo "selftest ok"
    return "$fail"
}

if [ "${1:-}" = "--selftest" ]; then selftest; exit $?; fi

REPO="${INCURSION_EPIC_GATE_REPO:-$HOME/Scripts/Incursion}"
EPIC="${INCURSION_EPIC_GATE_BRANCH:-inc-pu6v}"
DIR="${INCURSION_EPIC_GATE_DIR:-$HOME/Scripts/Incursion-epic-gate}"
STATE_DIR="${INCURSION_EPIC_GATE_STATE:-$HOME/Scripts/nightly-harness/state/incursion-epic}"
REPORTS="${INCURSION_EPIC_GATE_REPORTS:-$HOME/Scripts/nightly-harness/projects/incursion/nightly-epic}"
DATE="$(date +%Y-%m-%d)"
STATE="$STATE_DIR/incursion-epic-verify-$DATE.txt"
REPORT="$REPORTS/$DATE.md"
log() { printf '%s epic-gate: %s\n' "$(date +%H:%M:%S)" "$*"; }

mkdir -p "$STATE_DIR" "$REPORTS"
START="$(date '+%Y-%m-%d %H:%M:%S')"

log "refresh worktree $DIR at $EPIC"
if [ -d "$DIR" ]; then
    git -C "$DIR" checkout --detach --force "$EPIC"
else
    git -C "$REPO" worktree add --detach "$DIR" "$EPIC"
fi
git -C "$DIR" clean -fdq -e logs/
SHA="$(git -C "$DIR" rev-parse --short HEAD)"

# The newest earlier state, found before this run writes its own.
OLD="$(ls -1 "$STATE_DIR"/incursion-epic-verify-*.txt 2>/dev/null | grep -v "/incursion-epic-verify-$DATE.txt$" | sort | tail -1 || true)"

BUILD="passed"
log "build SDL"
(cd "$DIR" && ./build_macos.sh) || BUILD="FAILED (SDL)"
if [ "$BUILD" = "passed" ]; then
    log "build headless"
    (cd "$DIR" && BACKEND=posix ./build_macos.sh) || BUILD="FAILED (headless)"
fi
if [ "$BUILD" != "passed" ]; then
    log "build $BUILD"
    {
        echo "# Epic gate $DATE"; echo
        echo "- Epic tip: $SHA ($EPIC)"; echo "- Start: $START"; echo "- End: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "- Build: $BUILD"
    } > "$REPORT"
    echo "$DATE build $BUILD -- $REPORT" > "$REPORTS/latest.txt"
    exit 1
fi

log "record gate"
RC=0
(cd "$DIR" && NIGHTLY_BASE_REF="$EPIC" NIGHTLY_VERIFY_STATE="$STATE" tools/nightly_verify.sh --record) || RC=$?
[ "$RC" = 0 ] || log "record exit $RC"
if [ ! -s "$STATE" ]; then
    log "gate recorded nothing"
    write_norecord "$REPORTS" "$DATE" "$SHA" "$RC"
    exit 1
fi
END="$(date '+%Y-%m-%d %H:%M:%S')"

log "compare with ${OLD:-nothing}"
RESULT="$(compare_states "$OLD" "$STATE")"
names() { printf '%s\n' "$RESULT" | sed -n "s/^$1 //p"; }
NEWRED="$(names NEWRED)"; NNEW="$(printf '%s' "$NEWRED" | grep -c . || true)"

{
    echo "# Epic gate $DATE"; echo
    echo "- Epic tip: $SHA ($EPIC)"; echo "- Start: $START"; echo "- End: $END"
    echo "- Build: $BUILD"; echo "- Compared with: ${OLD:-none (first run)}"
    for k in NEWRED STILLRED FIXED NEWCHECKRED FIRSTRUN; do
        echo; echo "## $k"; echo
        names "$k" | sed 's/^/- /'
    done
} > "$REPORT"

if [ "$NNEW" -gt 0 ]; then
    LIST="$(printf '%s\n' "$NEWRED" | head -10 | paste -sd, -)"
    echo "$DATE $NNEW new red: $LIST -- $REPORT" > "$REPORTS/latest.txt"
else
    : > "$REPORTS/latest.txt"
fi
log "done: $NNEW new red, report $REPORT"
