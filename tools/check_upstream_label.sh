#!/usr/bin/env bash
# Verify that every base-code bug in the reporting ledger carries the beads
# label `upstream`, so tools/sync_issues.sh publishes its GitHub issue with that
# label.
#
# WHY THIS EXISTS. There are three independent ways this port records that a
# fixed defect is upstream's, and only one of them ever reaches GitHub:
#
#   1. an `upstream:` comment at the fix site (gated by check_upstream_marks.sh),
#   2. a row in the "Base-code bugs fixed locally" table in
#      docs/REPORTING-GATE.md (gated by check_ledger_rows.sh), and
#   3. the beads label `upstream`, which tools/sync_issues.sh turns into the
#      GitHub `upstream` label when it publishes a `public` bead.
#
# check_upstream_marks.sh ties 1 and 2 together. NOTHING tied either to 3. So on
# 2026-09-04 the tracker carried 90-odd fixed upstream defects and only FOUR of
# them wore the `upstream` label -- the four whose beads someone had labelled by
# hand. A reader filtering GitHub by `upstream` saw four bugs and concluded the
# port had barely touched the base code. This check closes that gap: a ledger row
# is the settled record that a defect is upstream's, so its bead MUST carry the
# label that publishes that fact.
#
# WHAT THIS CHECKS. Every tracking id named in the ledger table has a bead, and
# that bead carries the `upstream` label. It reads the ids straight from the last
# cell of each row, and it reads the labelled set from the live bead database.
#
#   MANY IDS IN ONE CELL. A row may name more than one id -- inc-f13 and inc-5xn
#   share a row -- and check_upstream_marks.sh's single-id extraction skips such
#   a row in silence. This check takes EVERY id in the last cell, so a shared row
#   is checked, not skipped.
#
# WHAT THIS CANNOT CHECK, and do not let a PASS tell you otherwise:
#   - whether the ledger row itself is correct. That the defect is upstream's,
#     not a port artefact, is the judgement check_upstream_marks.sh's header
#     describes and no script can make.
#   - a fixed upstream bug that has NO ledger row. That gap is check_ledger_rows'
#     and the mark rule's; a bead nobody wrote a row for is invisible here too.
#
# Usage:
#   tools/check_upstream_label.sh            exit 0 pass, 1 fail, 2 cannot measure
#   tools/check_upstream_label.sh --selftest prove the detector still detects
#
# The labelled set is read from `bd` unless $LABELED_IDS is set (even to empty),
# which --selftest uses to drive the logic without touching the real database.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

REGISTRY="${REGISTRY:-docs/REPORTING-GATE.md}"
ID_RE="inc-[a-z0-9]+(\.[0-9]+)*"

# Emit every tracking id named in the last cell of every row of the
# "Base-code bugs fixed locally" table, one per line. The last cell is taken as
# the text after the row's final pipe separator, so a cell naming several ids
# yields all of them.
ledger_ids() {
    local reg=$1 in_table=0 row last
    while IFS= read -r row; do
        case "$row" in
            "### Base-code bugs fixed locally"*) in_table=1; continue ;;
            "#"*) in_table=0; continue ;;
        esac
        [ "$in_table" = 1 ] || continue
        case "$row" in "|"*) ;; *) continue ;; esac

        last=${row%"${row##*[![:space:]]}"}   # strip trailing whitespace
        last=${last%|}                         # drop the trailing pipe
        last=${last##*|}                       # everything after the last separator
        printf '%s\n' "$last" | grep -oE "$ID_RE"
    done < "$reg"
}

# The set of beads that carry the `upstream` label, one id per line. Overridable
# so the self-test can supply a synthetic set.
labelled_ids() {
    if [ "${LABELED_IDS+set}" = set ]; then
        printf '%s\n' $LABELED_IDS
        return 0
    fi
    command -v bd >/dev/null 2>&1 || return 2
    local out
    out=$(bd list --label upstream --all --limit 0 --flat --json 2>/dev/null) || return 2
    printf '%s' "$out" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except ValueError:
    sys.exit(3)
iss = d if isinstance(d, list) else (d.get("issues") or [])
for i in iss:
    print(i["id"])
' || return 2
}

run_check() {
    [ -f "$REGISTRY" ] || { echo "FAIL: $REGISTRY is missing; nothing was examined"; return 1; }

    local ids
    ids=$(ledger_ids "$REGISTRY" | sort -u)
    # A green result from a run that parsed no ids is the same false pass the
    # sibling checks guard against: the table moved or the parser broke, and a
    # silent 0 hides it. The ledger always has rows, so zero ids is a defect.
    if [ -z "$ids" ]; then
        echo "FAIL: no tracking id parsed from the '$REGISTRY' ledger table;"
        echo "      the table heading or row shape changed. Nothing was examined."
        return 1
    fi

    local labelled rc=0
    labelled=$(labelled_ids); rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "check_upstream_label: cannot read the bead label set (bd unavailable" >&2
        echo "      or unreadable). State NOT checked." >&2
        return 2
    fi
    labelled=$(printf '%s\n' "$labelled" | sort -u)

    local missing="" id
    while IFS= read -r id; do
        [ -n "$id" ] || continue
        printf '%s\n' "$labelled" | grep -qxF "$id" || missing="$missing $id"
    done <<< "$ids"

    local total checked
    total=$(printf '%s\n' "$ids" | grep -c .)
    if [ -n "$missing" ]; then
        echo "FAIL: these ledger beads are upstream defects but carry no beads-label 'upstream':"
        for id in $missing; do echo "  $id"; done
        echo "      The ledger heading is 'Base-code bugs fixed locally', so each row IS an"
        echo "      upstream defect. Without the label, tools/sync_issues.sh publishes its"
        echo "      GitHub issue with no 'upstream' tag. Fix each: bd label add <id> upstream"
        return 1
    fi
    echo "PASS: all $total ledger bead(s) carry the 'upstream' label"
    return 0
}

# ---------------------------------------------------------------------------
# Self-test. Synthetic ledger, synthetic label set, in and out in one function.
# It proves the detector reports a missing label, checks BOTH ids of a shared
# row, ignores rows outside the table, and fails loudly on an empty parse.
selftest() {
    local rc=0 dir out
    dir="${TMPDIR:-/tmp}/check-upstream-label-selftest.$$"
    mkdir -p "$dir" || return 1

    {
        printf '### Base-code bugs fixed locally\n\n'
        printf '| Fix | Tier | Sent? | Tracked |\n|---|---|---|---|\n'
        printf '| A plain single-id row (`src/A.cpp`) | **Traced** | no | inc-aaa |\n'
        printf '| A row that names two ids at once (`src/B.cpp`) | **Observed** | no | inc-f13, inc-5xn |\n'
        printf '\n### Not sent\n'
        printf '| A row past the table that must be ignored | inc-outside |\n'
    } > "$dir/ledger.md"

    # 1. Every id present -> pass, and the id outside the table is not required.
    out=$( REGISTRY="$dir/ledger.md" LABELED_IDS="inc-aaa inc-f13 inc-5xn" \
           bash "$0" 2>&1 )
    if printf '%s\n' "$out" | grep -q '^PASS:' &&
       ! printf '%s\n' "$out" | grep -q 'inc-outside'; then
        printf 'selftest ok    %-38s -> pass, row past the table ignored\n' "all labelled"
    else
        printf 'selftest FAIL  %-38s\n%s\n' "all labelled" "$out"; rc=1
    fi

    # 2. The second id of the shared row is missing -> fail, naming exactly it.
    out=$( REGISTRY="$dir/ledger.md" LABELED_IDS="inc-aaa inc-f13" bash "$0" 2>&1 )
    if printf '%s\n' "$out" | grep -q '^FAIL:' &&
       printf '%s\n' "$out" | grep -qx '  inc-5xn' &&
       ! printf '%s\n' "$out" | grep -qx '  inc-f13'; then
        printf 'selftest ok    %-38s -> shared-row id checked, not skipped\n' "one id of a shared row missing"
    else
        printf 'selftest FAIL  %-38s\n%s\n' "one id of a shared row missing" "$out"; rc=1
    fi

    # 3. A single-id row unlabelled -> fail, naming it.
    out=$( REGISTRY="$dir/ledger.md" LABELED_IDS="inc-f13 inc-5xn" bash "$0" 2>&1 )
    if printf '%s\n' "$out" | grep -qx '  inc-aaa'; then
        printf 'selftest ok    %-38s -> reported\n' "plain row missing the label"
    else
        printf 'selftest FAIL  %-38s\n%s\n' "plain row missing the label" "$out"; rc=1
    fi

    # 4. Empty parse (no table) must FAIL, never pass green.
    printf '### Something Else\n\nno table here\n' > "$dir/empty.md"
    out=$( REGISTRY="$dir/empty.md" LABELED_IDS="" bash "$0" 2>&1 )
    if printf '%s\n' "$out" | grep -q 'FAIL:' &&
       printf '%s\n' "$out" | grep -qi 'nothing was examined'; then
        printf 'selftest ok    %-38s -> fails loudly\n' "empty parse"
    else
        printf 'selftest FAIL  %-38s\n%s\n' "empty parse" "$out"; rc=1
    fi

    rm -rf "$dir"
    echo
    [ "$rc" -eq 0 ] && echo "selftest: pass" || echo "selftest: FAIL"
    return "$rc"
}

case "${1:-}" in
    "")         run_check; exit $? ;;
    --selftest) selftest; exit $? ;;
    *)          echo "usage: $0 [--selftest]" >&2; exit 2 ;;
esac
