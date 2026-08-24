#!/bin/bash
# Verify that each ledger row in docs/REPORTING-GATE.md sits under the heading
# whose shape it has.
#
# WHY THIS EXISTS. The document holds two tables that a fix can plausibly be
# appended to, and CLAUDE.md used to say only "the table":
#
#   ### Base-code bugs fixed locally   | Fix | Tier | Sent? | Tracked |
#   ### Not sent                       | Issue | Tier | Why not |
#
# On 2026-08-24 twenty-six rows carrying the FOUR-column shape had been appended
# under "### Not sent", which is a three-column table. A markdown reader drops
# the surplus cell, so the tracking id of all twenty-six rendered as nothing and
# the registry silently lost the link from a fix to its bead. Nothing caught it,
# because tools/check_upstream_marks.sh greps the WHOLE file for an id and does
# not care which table the id sits in.
#
# WHAT THIS CHECKS, in three passes.
#
#   A. NOT SENT HOLDS NO LEDGER ROWS. A row under "### Not sent" whose last cell
#      is a tracking id has the four-column ledger shape and belongs in
#      "Base-code bugs fixed locally". "Not sent" means "we decided not to
#      report this", and it takes | Issue | Tier | Why not | -- no id column.
#
#   B. THE LEDGER HOLDS ONLY LEDGER ROWS. Every data row under "### Base-code
#      bugs fixed locally" must END with a tracking id cell. A row that does not
#      is truncated, mis-shaped, or was written for a different table.
#
#   C. EVERY MARKED FIX REACHES THE LEDGER. For each `upstream:` marker in src/,
#      inc/ and lib/, the first tracking id in its comment block must appear as
#      the last cell of a row in the ledger table. This is the pass that would
#      have caught the 2026-08-24 misfiling on the day it happened: the ids were
#      in the file, so check_upstream_marks.sh stayed green, but they were not
#      in the ledger.
#
#      Measured before it was turned on: 118 markers, and the only 26 that
#      failed were exactly the misfiled ones. It has no known false positive.
#
# WHY THE COLUMN COUNT IS NOT COUNTED. Several rows carry an unescaped `|`
# inside a code span (`FI_MODIFIER|FI_MOBILE`), and one carries nested
# backticks, so counting cells reports 1, 4, 5 or 6 for rows that are all the
# same shape. The last cell is the shape difference that matters and it survives
# every one of those, so that is what is tested.
#
# WHAT THIS CANNOT CHECK: whether the row says anything TRUE, and whether an
# unmarked fix should have been marked. See tools/check_upstream_marks.sh.
#
# Usage:
#   tools/check_ledger_rows.sh            exit 0 pass, 1 fail
#   tools/check_ledger_rows.sh --selftest prove the detectors still detect
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Overridable so --selftest can point the passes at a synthetic document.
REGISTRY="${REGISTRY:-docs/REPORTING-GATE.md}"

LEDGER_HEAD="### Base-code bugs fixed locally"
NOTSENT_HEAD="### Not sent"

ID_RE="inc-[a-z0-9]+(\.[0-9]+)*"
# A row's LAST cell, and it holds nothing but tracking ids. One row cites two,
# comma separated -- the Map::At row is tracked as "inc-f13, inc-5xn" -- so the
# list form is part of the shape, not a violation of it.
TAIL_ID_RE="\|[[:space:]]*${ID_RE}([[:space:]]*,[[:space:]]*${ID_RE})*[[:space:]]*\|[[:space:]]*\$"

FAIL=0

# Print "lineno<TAB>row" for every table row under heading $2 of file $1. The
# header row and its |---|---| rule are rows like any other; the callers decide
# what to do with them.
rows_under() {
    local reg=$1 head=$2
    awk -v head="$head" '
        /^#/ { inside = ($0 == head) ? 1 : 0; next }
        inside && /^\|/ { printf "%d\t%s\n", NR, $0 }
    ' "$reg"
}

# The last cell of every ledger row that has an id in it.
ledger_ids() {
    rows_under "$REGISTRY" "$LEDGER_HEAD" |
        grep -oE "$TAIL_ID_RE" |
        grep -oE "$ID_RE"
}

pass_a() {
    local n=0 lineno row
    while IFS=$'\t' read -r lineno row; do
        [ -n "$lineno" ] || continue
        printf '%s\n' "$row" | grep -qE "$TAIL_ID_RE" || continue
        echo "FAIL: $REGISTRY:$lineno is a four-column ledger row filed under \"Not sent\""
        echo "      ${row:0:100}..."
        n=$((n + 1))
    done <<< "$(rows_under "$REGISTRY" "$NOTSENT_HEAD")"

    if [ "$n" -gt 0 ]; then
        echo
        echo "$n row(s) under \"$NOTSENT_HEAD\" carry the ledger's | Fix | Tier | Sent? | Tracked |"
        echo "shape. \"Not sent\" means we decided NOT to report an issue and takes three"
        echo "columns, so a markdown reader DROPS the tracking id of every row above."
        echo "Move them to \"$LEDGER_HEAD\"."
        echo
        FAIL=1
    fi
    return 0
}

pass_b() {
    local n=0 lineno row seen=0
    while IFS=$'\t' read -r lineno row; do
        [ -n "$lineno" ] || continue
        # Skip the header row and the |---|---| rule that follows it.
        seen=$((seen + 1))
        [ "$seen" -le 2 ] && continue
        printf '%s\n' "$row" | grep -qE "$TAIL_ID_RE" && continue
        echo "FAIL: $REGISTRY:$lineno is a ledger row whose last cell is not a tracking id"
        echo "      ${row:0:100}..."
        n=$((n + 1))
    done <<< "$(rows_under "$REGISTRY" "$LEDGER_HEAD")"

    if [ "$seen" -lt 3 ]; then
        echo "FAIL: found no data rows under \"$LEDGER_HEAD\" in $REGISTRY."
        echo "      Either the heading was renamed or nothing was examined."
        FAIL=1
        return 0
    fi
    [ "$n" -gt 0 ] && FAIL=1
    return 0
}

pass_c() {
    local ids hit FILE REST LINE BLOCK ID n=0 count=0
    ids="$(ledger_ids | sort -u)"

    local dirs=() d
    for d in src inc lib; do [ -d "$d" ] && dirs+=("$d"); done
    if [ "${#dirs[@]}" -eq 0 ]; then
        echo "FAIL: none of src/ inc/ lib/ exist under $ROOT; nothing was examined"
        FAIL=1
        return 0
    fi

    while IFS= read -r hit; do
        [ -n "$hit" ] || continue
        FILE="${hit%%:*}"
        REST="${hit#*:}"
        LINE="${REST%%:*}"
        count=$((count + 1))

        BLOCK="$(sed -n "${LINE},$((LINE + 20))p" "$FILE")"
        ID="$(printf '%s\n' "$BLOCK" | grep -oE "$ID_RE" | head -1)"
        [ -n "$ID" ] || continue          # check_upstream_marks.sh owns that failure

        printf '%s\n' "$ids" | grep -qxF "$ID" && continue

        echo "FAIL: $FILE:$LINE marks a base-code fix tracked as $ID, and no row in"
        echo "      \"$LEDGER_HEAD\" ends with that id."
        echo "      A marked fix that is not in the ledger is not findable. Add the row"
        echo "      there -- not under \"$NOTSENT_HEAD\", which drops the id column."
        n=$((n + 1))
    done <<< "$(grep -rn "upstream:" "${dirs[@]}" 2>/dev/null | grep -v '^Binary')"

    if [ "$count" -eq 0 ]; then
        echo "FAIL: no 'upstream:' markers found in ${dirs[*]}; nothing was examined."
        FAIL=1
        return 0
    fi
    [ "$n" -gt 0 ] && FAIL=1
    LAST_MARKER_COUNT=$count
    return 0
}

run_checks() {
    LAST_MARKER_COUNT=0
    [ -f "$REGISTRY" ] || { echo "FAIL: $REGISTRY is missing"; return 1; }
    grep -qxF "$LEDGER_HEAD" "$REGISTRY" || {
        echo "FAIL: $REGISTRY has no \"$LEDGER_HEAD\" heading"; return 1; }
    grep -qxF "$NOTSENT_HEAD" "$REGISTRY" || {
        echo "FAIL: $REGISTRY has no \"$NOTSENT_HEAD\" heading"; return 1; }

    pass_a
    pass_b
    pass_c

    if [ "$FAIL" -ne 0 ]; then
        echo "LEDGER ROWS MISFILED: see above."
        return 1
    fi
    echo "PASS: $(ledger_ids | wc -l | tr -d ' ') ledger row(s), none misfiled under"
    echo "      \"$NOTSENT_HEAD\", and all $LAST_MARKER_COUNT upstream: marker(s) reach the ledger."
    return 0
}

# ---------------------------------------------------------------------------
# Self-test. Synthetic documents, in and out in one function, nothing left on
# disk. It proves each pass BITES, because a guard never seen red proves
# nothing -- which is the whole lesson of the misfiling it was written for.
selftest() {
    local rc=0 dir out
    dir="${TMPDIR:-/tmp}/checkledger-selftest.$$"
    mkdir -p "$dir" || return 1

    expect() {
        local name=$1 want=$2 wantrc=$3 doc=$4
        out=$( REGISTRY="$doc" run_checks 2>&1 )
        local got=$?
        FAIL=0
        if [ "$got" = "$wantrc" ] && printf '%s\n' "$out" | grep -q "$want"; then
            printf 'selftest ok    %-38s -> exit %s\n' "$name" "$got"
        else
            printf 'selftest FAIL  %-38s -> exit %s (wanted %s, matching %s)\n' \
                "$name" "$got" "$wantrc" "$want"
            printf '%s\n' "$out" | sed 's/^/    | /'
            rc=1
        fi
    }

    # A document whose ledger names the one marker id the tree really carries at
    # a known site, so pass C is satisfied without a fixture source file. Every
    # other marker id in the tree must also appear, so the ledger is built from
    # the real one.
    local real_ledger
    real_ledger=$(awk -v head="$LEDGER_HEAD" '
        /^#/ { inside = ($0 == head) ? 1 : 0 }
        inside { print }
    ' docs/REPORTING-GATE.md)

    # 1. Clean: the real ledger, and a "Not sent" holding only three-column rows.
    {
        printf '%s\n' "$real_ledger"
        printf '\n%s\n\n' "$NOTSENT_HEAD"
        printf '| Issue | Tier | Why not |\n|---|---|---|\n'
        printf '| window flicker | **Reasoned** | fails the gate |\n'
    } > "$dir/clean.md"
    expect "clean document passes" "^PASS:" 0 "$dir/clean.md"

    # 2. Pass A bites: one four-column row appended under "Not sent".
    {
        cat "$dir/clean.md"
        printf '| A fix with a tracking id | **Observed** | no | inc-tek.8.8 |\n'
    } > "$dir/misfiled.md"
    expect "ledger row under Not sent fails" "four-column ledger row filed under" 1 \
        "$dir/misfiled.md"

    # 3. Pass B bites: a ledger row that stops before its id column.
    {
        printf '%s\n' "$real_ledger"
        printf '| A row that lost its last cell | **Observed** | no |\n'
        printf '\n%s\n\n' "$NOTSENT_HEAD"
        printf '| Issue | Tier | Why not |\n|---|---|---|\n'
    } > "$dir/truncated.md"
    expect "truncated ledger row fails" "last cell is not a tracking id" 1 \
        "$dir/truncated.md"

    # 4. Pass C bites: a ledger with the rows, minus every row for one real
    #    marker id. inc-qep is marked at lib/classes.irh:1401 and nowhere else.
    {
        printf '%s\n' "$real_ledger" | grep -v 'inc-qep |'
        printf '\n%s\n\n' "$NOTSENT_HEAD"
        printf '| Issue | Tier | Why not |\n|---|---|---|\n'
    } > "$dir/dropped.md"
    expect "marker with no ledger row fails" "marks a base-code fix tracked as inc-qep" 1 \
        "$dir/dropped.md"

    # 5. An empty ledger must fail, not pass quietly on nothing.
    {
        printf '%s\n\n' "$LEDGER_HEAD"
        printf '| Fix | Tier | Sent? | Tracked |\n|---|---|---|---|\n'
        printf '\n%s\n\n' "$NOTSENT_HEAD"
        printf '| Issue | Tier | Why not |\n|---|---|---|\n'
    } > "$dir/empty.md"
    expect "empty ledger fails" "found no data rows" 1 "$dir/empty.md"

    rm -rf "$dir"

    # 6. And the tree as it stands, so the results above are not masked by a
    #    pre-existing failure somewhere else.
    out=$( run_checks 2>&1 ); local tree_rc=$?
    FAIL=0
    if [ "$tree_rc" -eq 0 ]; then
        printf 'selftest ok    %-38s -> exit 0\n' "the working tree passes"
    else
        printf 'selftest FAIL  %-38s -> exit %s\n' "the working tree passes" "$tree_rc"
        printf '%s\n' "$out" | sed 's/^/    | /'
        rc=1
    fi

    echo
    [ "$rc" -eq 0 ] && echo "selftest: pass" || echo "selftest: FAIL"
    return "$rc"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --selftest) selftest; exit $? ;;
        *) echo "usage: $0 [--selftest]" >&2; exit 2 ;;
    esac
done

run_checks
exit $?
