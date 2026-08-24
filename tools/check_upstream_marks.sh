#!/bin/bash
# Verify that every base-code bug we have fixed is marked, and marked completely.
#
# The rule is in AGENTS.md and CLAUDE.md: a fix to a defect that is upstream's
# rather than the port's carries an 'upstream:' comment at the fix site and a row
# in the "Base-code bugs fixed locally" table in docs/REPORTING-GATE.md. The
# point is that if the original maintainer ever returns, the work is findable.
#
# WHAT THIS CHECKS, in three passes.
#
#   1. MARK -> TABLE. Each well-formed marker states the four required things,
#      and its tracking id reaches the registry. That is the failure that
#      actually happens: somebody marks the code, and the table never hears
#      about it.
#
#   2. MALFORMED MARKS. A comment that says 'upstream' in a marker's shape but
#      does not spell the tag as the documented `upstream: ` is invisible to
#      `grep -rn "upstream:" src/ inc/` (docs/REPORTING-GATE.md:154), so pass 1
#      never sees it and the old version of this script counted a clean run
#      while a fix site went unchecked. src/rle.c:270 and src/lz.c:500 both
#      wrote the tag as `upstream (inc-l0t, Traced, not sent):` and were skipped
#      in silence for months. This pass FAILS on that shape.
#
#      Mark-like means: the word 'upstream' opens the comment text on its line
#      (after an optional /* // or * leader), it is not the possessive
#      "upstream's", and the same line carries a tracking id or an evidence
#      tier. All three are needed. Ordinary prose that merely uses the word --
#      src/TextTerm.cpp:71 "a bare upstream version here would misidentify the
#      binary" -- opens a line the same way, and only the id/tier requirement
#      keeps it from tripping this check. Widen the pattern and you get a
#      checker that cries wolf, which is worse than the blind spot it replaced.
#      Known limit: the pattern reads one line, so a malformed tag whose id and
#      tier sit on the NEXT line is still missed.
#
#   3. TABLE -> MARK, the reverse direction. For every fix site the table names
#      -- the backticked src/ or inc/ paths in the LAST parenthesised list in a
#      row's Fix cell -- at least one named file must carry a marker mentioning
#      that row's tracking id. A table row that names a file with no mark in it
#      passes every other check in this script.
#
#      Two details, both settled on 2026-08-24 (inc-6s5 follow-up) when twenty-
#      six rows were moved out of "Not sent" and this pass saw them for the
#      first time:
#
#        - AT LEAST ONE, not every one. A row may name several files because the
#          fix touched several -- inc-izuu names inc/Defines.h, inc/ConstNam.h,
#          lib/m_items.irh and src/Item.cpp -- and the house convention is ONE
#          mark, at the primary site. Demanding a mark in the header that gained
#          a constant asks for a marker the rule never wanted. A row naming a
#          single wrong file still fails, which is the case this pass exists for.
#
#        - THE LAST LIST, even when it names no src/ or inc/ path. A fix that
#          lives in lib/ ends its Fix cell with "(`lib/prestige.irh`)", and the
#          src/ paths earlier in the cell are citations, not fix sites. Taking
#          the last list that happens to hold a src/ path picked up the citation
#          and demanded a marker there. Two rows were affected, inc-tek.24 and
#          inc-tek.8.8, and in both the "fix site" it found was evidence the row
#          argued from. This script cannot read lib/, so such a row simply has
#          no fix site this pass can check -- see the note on lib/ below.
#
#      WHY lib/ IS NOT SCANNED. Widening the greps to lib/ was measured on
#      2026-08-24: 35 markers there, and one of them, lib/m_items.irh:7092,
#      fails the four-part test because it is a cross-reference in prose ("see
#      the upstream: mark on that handler") whose id sits on the line ABOVE it.
#      Widening would turn this script red and stop the nightly, so it was not
#      done. tools/check_ledger_rows.sh covers lib/ instead: it requires every
#      marker in src/, inc/ AND lib/ to reach the ledger table.
#
#      This pass FAILS. It used to warn, because two rows were unmatched and
#      neither was this script's to settle: whether the right answer is a new
#      marker or a corrected table row is a provenance judgement, and a gate
#      that is red for a reason nobody may act on gets switched off. Both were
#      settled on 2026-08-23 (bd inc-6s5), the backlog is empty, and the mode
#      the header always called for is now the default. `--strict` is still
#      accepted and does nothing, so an older caller does not break.
#
# WHAT THIS CANNOT CHECK, and do not let a PASS tell you otherwise:
#   - whether the provenance claim is TRUE. Deciding that a defect would also
#     misbehave on Win32 with the original typedefs is a judgement, and a wrong
#     one mislabels our port artefact as upstream's bug. Only a human reading
#     the code can settle it.
#   - whether an UNMARKED fix should have been marked. Nothing here knows which
#     diffs were bug fixes. That gap is the reason the rule lives in AGENTS.md
#     and CLAUDE.md, where every agent reads it, rather than only in this script.
#
# Usage:
#   tools/check_upstream_marks.sh            exit 0 pass, 1 fail
#   tools/check_upstream_marks.sh --strict   accepted, and already the default
#   tools/check_upstream_marks.sh --selftest prove the detectors still detect
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Overridable so --selftest can point pass 3 at a synthetic table. Nothing else
# sets it; a caller who does is testing the checker, not the tree.
REGISTRY="${REGISTRY:-docs/REPORTING-GATE.md}"
FAIL=0
UNMATCHED=0

# STRICT IS THE DEFAULT NOW. It was 0, because two table rows named a fix site
# with no marker in it and neither was this script's to settle -- a gate that is
# red for a reason nobody may act on gets switched off. Both were settled on
# 2026-08-23 (inc-6s5): src/Fight.cpp's inc-dzz row was superseded by inc-nie's
# marker, and inc/Target.h gained a reasoned marker for inc-upw.13. The backlog
# is empty, so the warning becomes the failure the header always said it should.
STRICT=1

APOS=$(printf '\047')
BT=$(printf '\140')

# The documented form, and nothing else: the literal token `upstream:` followed
# by whitespace. This is the pattern docs/REPORTING-GATE.md:154 and
# docs/FIXED.md:587 tell a reader to grep for, so it is the pattern that
# defines "well formed".
WELL_FORMED="(^|[^A-Za-z0-9_])upstream:[[:space:]]"

# 'upstream' opens the comment text on this line, and is not "upstream's".
MARK_LIKE="^[[:space:]]*((/\*+|//+|\*+)[[:space:]]*)?[Uu]pstream([^A-Za-z0-9_${APOS}]|$)"

# ... and the line carries something only a marker carries.
MARK_CONTEXT="inc-[a-z0-9]+(\.[0-9]+)*|Observed|Traced|Reasoned"

ID_RE="inc-[a-z0-9]+(\.[0-9]+)*"

# One line in, one word out: wellformed, malformed or none.
classify_line() {
    local text=$1
    if printf '%s\n' "$text" | grep -qE "$WELL_FORMED"; then
        printf 'wellformed\n'; return
    fi
    if printf '%s\n' "$text" | grep -qE "$MARK_LIKE" &&
       printf '%s\n' "$text" | grep -qE "$MARK_CONTEXT"; then
        printf 'malformed\n'; return
    fi
    printf 'none\n'
}

# Emit "id<TAB>path path ..." -- ONE LINE PER ROW -- for every fix site named in
# the "Base-code bugs fixed locally" table of $1. The paths stay on one line so
# the caller can ask "did ANY of this row's files carry the mark?" rather than
# demanding one in each.
#
# A row's Fix cell cites many backticked paths that are NOT the fix site:
# sibling loops the fix was compared against, the ASSERT it relies on, the
# harness that confirmed it. The fix site is the house convention: the LAST
# parenthesised list of backticked paths in the cell, e.g. "(`src/Term.cpp`)"
# or "(`src/lz.c`, `src/rle.c`)". A cited path carrying a line number
# ("`inc/Defines.h:73`") is a reference, not a fix site, so the extraction
# requires the closing backtick straight after the extension.
#
# The LAST list wins outright. If it names only lib/ files, this row has no fix
# site this script can check and emits nothing -- it does NOT fall back to an
# earlier list, because that list is the row's evidence, not its fix.
table_fix_sites() {
    local reg=$1 in_table=0 row id body fixcell groups g ps best p
    while IFS= read -r row; do
        case "$row" in
            "### Base-code bugs fixed locally"*) in_table=1; continue ;;
            "#"*) in_table=0; continue ;;
        esac
        [ "$in_table" = 1 ] || continue
        case "$row" in "|"*) ;; *) continue ;; esac

        # The tracking id is the last cell.
        id=$(printf '%s\n' "$row" |
             grep -oE "\|[[:space:]]*${ID_RE}[[:space:]]*\|[[:space:]]*$" |
             grep -oE "$ID_RE")
        [ -n "$id" ] || continue

        # A cell may contain an escaped pipe (row 148 holds '\|\|'), so hide
        # those before splitting the row on its real cell separators.
        body=${row//\\|/@ESCAPEDPIPE@}
        body=${body#|}
        fixcell=${body%%|*}

        groups=$(printf '%s\n' "$fixcell" |
                 grep -oE "\(${BT}[A-Za-z0-9_/.:-]+${BT}(, ${BT}[A-Za-z0-9_/.:-]+${BT})*\)")
        best=""
        while IFS= read -r g; do
            [ -n "$g" ] || continue
            ps=$(printf '%s\n' "$g" |
                 grep -oE "${BT}(src|inc)/[A-Za-z0-9_]+\.(cpp|c|h)${BT}" |
                 tr -d "$BT")
            # The last list wins whatever it holds, so a lib/-only list clears
            # the src/ paths an earlier, citing list left behind.
            best=$ps
        done <<< "$groups"

        [ -n "$best" ] || continue
        printf '%s\t%s\n' "$id" "$(printf '%s\n' "$best" | tr '\n' ' ' | sed 's/ *$//')"
    done < "$reg"
}

run_checks() {
    [ -f "$REGISTRY" ] || { echo "FAIL: $REGISTRY is missing"; return 1; }

    # A check that cannot find the code must FAIL, never pass quietly. Without
    # this guard, running the script from anywhere but the repository reports
    # "no markers found" and exits 0 -- a green result from a run that examined
    # nothing. That is the same mistake as counting a session that never entered
    # a map as a pass (inc-loa.3), and it was caught by testing this script's own
    # failure path.
    for d in src inc; do
        [ -d "$d" ] || { echo "FAIL: no $d/ directory under $ROOT; nothing was examined"; return 1; }
    done

    # --- pass 2 first: a malformed tag is invisible to pass 1 ----------------
    local hit FILE REST LINE TEXT MALFORMED=0
    while IFS= read -r hit; do
        [ -n "$hit" ] || continue
        FILE="${hit%%:*}"
        REST="${hit#*:}"
        LINE="${REST%%:*}"
        TEXT="${REST#*:}"
        [ "$(classify_line "$TEXT")" = malformed ] || continue
        echo "FAIL: $FILE:$LINE writes the marker tag in a form the documented grep cannot see"
        echo "      $TEXT"
        echo "      Write it as 'upstream: ' -- lowercase word, colon, space -- and keep the"
        echo "      tier, the id and the sent status in the prose after it. As written,"
        echo "      grep -rn \"upstream:\" src/ inc/ misses this fix site entirely."
        MALFORMED=$((MALFORMED + 1))
        FAIL=1
    done <<< "$(grep -rnE "$MARK_LIKE" src inc 2>/dev/null | grep -v '^Binary')"

    # --- pass 1: MARK -> TABLE ----------------------------------------------
    local MARKS COUNT=0 BLOCK label ID i
    MARKS="$(grep -rn "upstream:" src inc 2>/dev/null | grep -v "^Binary")"

    if [ -z "$MARKS" ]; then
        echo "No 'upstream:' markers found in src/ or inc/."
        echo "That is not automatically a pass. Most defects in this codebase are"
        echo "upstream's, so zero markers more likely means the rule is being"
        echo "forgotten than that no base-code bug has ever been fixed. See inc-iqh."
        return "$FAIL"
    fi

    # "file<TAB>id" for every id any marker block mentions. The reverse pass
    # reads this. Every id in the block counts, not just the first: the marker
    # at src/Registry.cpp:726 opens by naming inc-zmk, the fix it builds on, and
    # states its own "Tracking: inc-upw.13" eighteen lines later.
    local MARKED=""

    while IFS= read -r hit; do
        FILE="${hit%%:*}"
        REST="${hit#*:}"
        LINE="${REST%%:*}"
        COUNT=$((COUNT + 1))

        # The marker is a comment block. Twenty lines is comfortably more than any
        # written so far and stops well short of the next function.
        BLOCK="$(sed -n "${LINE},$((LINE + 20))p" "$FILE")"

        label="$FILE:$LINE"

        # 2. evidence tier, in the words docs/REPORTING-GATE.md uses.
        if ! echo "$BLOCK" | grep -qE "Observed|Traced|Reasoned"; then
            echo "FAIL: $label states no evidence tier (Observed, Traced or Reasoned)"
            FAIL=1
        fi

        # 3. tracking id, and it must reach the registry.
        ID="$(echo "$BLOCK" | grep -oE "$ID_RE" | head -1)"
        if [ -z "$ID" ]; then
            echo "FAIL: $label names no tracking id"
            FAIL=1
        elif ! grep -q "$ID" "$REGISTRY"; then
            echo "FAIL: $label is tracked as $ID, which has no row in $REGISTRY"
            echo "      Add it to the 'Base-code bugs fixed locally' table."
            FAIL=1
        fi

        # 4. sent, or not sent. Either is fine; silence is not.
        if ! echo "$BLOCK" | grep -qiE "sent|submitted|filed upstream"; then
            echo "FAIL: $label does not say whether it has been sent upstream"
            FAIL=1
        fi

        while IFS= read -r i; do
            [ -n "$i" ] || continue
            MARKED="$MARKED$FILE	$i
"
        done <<< "$(echo "$BLOCK" | grep -oE "$ID_RE" | sort -u)"
    done <<< "$MARKS"

    # --- pass 3: TABLE -> MARK ----------------------------------------------
    local tid tpaths tp present matched
    while IFS=$'\t' read -r tid tpaths; do
        [ -n "$tid" ] || continue
        present=""
        matched=0
        for tp in $tpaths; do
            if [ ! -f "$tp" ]; then
                echo "FAIL: $REGISTRY names $tp as a fix site for $tid, and no such file exists"
                FAIL=1
                continue
            fi
            present="$present $tp"
            printf '%s' "$MARKED" | grep -qxF "$tp	$tid" && matched=1
        done
        [ -n "$present" ] || continue
        if [ "$matched" -eq 0 ]; then
            echo "WARN: $REGISTRY names${present} as the fix site(s) for $tid, and none of"
            echo "      them carries an upstream: marker mentioning $tid. Either the fix site"
            echo "      needs a properly reasoned marker, or the table row names the wrong file."
            echo "      Deciding which is a provenance judgement -- see docs/REPORTING-GATE.md."
            UNMATCHED=$((UNMATCHED + 1))
        fi
    done <<< "$(table_fix_sites "$REGISTRY")"

    echo
    if [ "$UNMATCHED" -gt 0 ]; then
        echo "$UNMATCHED table row(s) name a fix site that carries no matching marker."
        if [ "$STRICT" -eq 1 ]; then
            FAIL=1
        else
            echo "Not counted as a failure: this run was asked not to."
        fi
    fi

    if [ "$FAIL" -ne 0 ]; then
        echo "UPSTREAM MARKS INCOMPLETE: $COUNT marker(s) checked, $MALFORMED malformed"
        return 1
    fi
    echo "PASS: $COUNT upstream marker(s), all complete and all in $REGISTRY"
    return 0
}

# ---------------------------------------------------------------------------
# Self-test. Same shape as tools/check_citations.sh --selftest: synthetic
# inputs, in and out in one function, no fixtures on disk that outlive the run.
# It proves the two new detectors DETECT, which is the whole point -- the bug
# being fixed here is a checker that printed PASS while seeing nothing.
selftest() {
    local rc=0 got want name sample

    check_one() {
        name=$1; sample=$2; want=$3
        got=$(classify_line "$sample")
        if [ "$got" = "$want" ]; then
            printf 'selftest ok    %-34s -> %s\n' "$name" "$got"
        else
            printf 'selftest FAIL  %-34s -> %s (wanted %s)\n' "$name" "$got" "$want"
            rc=1
        fi
    }

    # The documented form, in each comment style the tree actually uses.
    check_one "well-formed /* mark" \
        '    /* upstream: base-code defect. Traced. inc-abc. Not sent. */' wellformed
    check_one "well-formed // mark" \
        '    // upstream: base-code defect. Observed. inc-abc. Not sent.' wellformed
    check_one "well-formed continuation-line mark" \
        '   upstream: that unbounded write is a base-code defect. Traced. inc-abc. Sent.' wellformed

    # The shape that hid for months: colon after the parenthesis, not after the
    # word. src/rle.c:270 and src/lz.c:500, verbatim as they were.
    check_one "malformed, colon after parenthesis" \
        '* upstream (inc-l0t, Traced, not sent): every bound check in this function' malformed
    check_one "malformed, capitalised tag" \
        '/* Upstream: base-code defect, Traced, inc-abc, not sent */' malformed
    check_one "malformed, dash instead of colon" \
        '// upstream - base-code defect, Observed, inc-abc, not sent' malformed

    # Prose that must NOT match. All four are real lines from src/, and the
    # first opens its line with the word exactly as a marker does.
    check_one "prose: 'a bare upstream version'" \
        '               upstream version here would misidentify the binary. */' none
    check_one "prose: possessive at line start" \
        "   upstream's: the breadcrumb is inside #ifdef DEBUG, upstream ships without" none
    check_one "prose: word mid-sentence" \
        '        // Secondary correctness fix, part of the same upstream mark above' none
    check_one "prose: parenthetical citation" \
        '       terrain in lib/ has that flag, $"chasm" (lib/dungeon.irh:680 upstream),' none

    # The reverse direction: a table that names a fix site.
    local dir="${TMPDIR:-/tmp}/checkmarks-selftest.$$"
    mkdir -p "$dir" || return 1
    {
        printf '### Base-code bugs fixed locally\n\n'
        printf '| Fix | Tier | Sent? | Tracked |\n|---|---|---|---|\n'
        printf '| A defect compared against `src/Other.cpp:12` and `src/Sibling.cpp`, fixed in (`src/Real.cpp`) | **Traced** | no | inc-aaa |\n'
        printf '| Two files this time, guarded at `Map::GetAt` (`src/One.cpp`, `inc/Two.h`) | **Observed** | no | inc-bbb |\n'
        printf '| A reference with a line number (`inc/Defines.h:73`) only logs; fixed instead (`src/Third.cpp`) | **Traced** -- ran (`tools/harness.sh`) | no | inc-ccc |\n'
        printf '| A lib fix argued from (`src/Fight.cpp`) and fixed in (`lib/prestige.irh`) | **Traced** | no | inc-eee |\n'
        printf '\n### Something else\n'
        printf '| Not a fix row (`src/NotAFixSite.cpp`) | x | x | inc-ddd |\n'
    } > "$dir/table.md"

    local sites expect
    sites=$(table_fix_sites "$dir/table.md" | sort | tr '\t' ' ')
    # One line per ROW, not per path. inc-eee emits nothing: its last list names
    # only lib/, so the src/Fight.cpp it argues from is not taken as a fix site.
    expect='inc-aaa src/Real.cpp
inc-bbb src/One.cpp inc/Two.h
inc-ccc src/Third.cpp'
    if [ "$sites" = "$expect" ]; then
        printf 'selftest ok    %-34s -> 3 rows, no references, no lib-only row, none past the table\n' \
            "table fix-site extraction"
    else
        printf 'selftest FAIL  %-34s\n  wanted: %s\n  got:    %s\n' \
            "table fix-site extraction" "$expect" "$sites"
        rc=1
    fi
    # PASS 3 MUST BITE, and until 2026-08-23 nothing proved that it did. The
    # pass only ever warned, so its result was never the exit status and a
    # silent break in it would have looked exactly like a clean tree. It fails
    # now, which makes an untested detector a live hazard rather than a dormant
    # one.
    #
    # Three rows, so the answer is three-sided. The files must all EXIST, or the
    # missing-file branch above answers instead and the marker matcher is never
    # exercised at all -- which is the mistake this case was written with on the
    # first attempt.
    #   src/MapAudit.cpp carries no upstream marker of any kind, so its row must
    #     be reported as unmatched.
    #   src/Target.cpp carries a real inc-upw.13 marker, so its row must be
    #     silent. A detector that reports everything passes the first row alone.
    #   src/NoSuchFile.cpp does not exist, so the missing-file branch must fire
    #     and keep its own separate wording.
    {
        printf '### Base-code bugs fixed locally\n\n'
        printf '| Fix | Tier | Sent? | Tracked |\n|---|---|---|---|\n'
        printf '| A row whose fix site carries no marker (`src/MapAudit.cpp`) | **Traced** | no | inc-aaa |\n'
        printf '| A row whose fix site does carry one (`src/Target.cpp`) | **Observed** | no | inc-upw.13 |\n'
        printf '| A row naming a file that is not there (`src/NoSuchFile.cpp`) | **Traced** | no | inc-bbb |\n'
        printf '| A row naming two files, one marked (`src/MapAudit.cpp`, `src/Registry.cpp`) | **Traced** | no | inc-zmk |\n'
    } > "$dir/pass3.md"

    local p3
    p3=$( REGISTRY="$dir/pass3.md" run_checks 2>&1 )
    # The fourth row proves "at least one" is really at least one: src/MapAudit.cpp
    # carries nothing and src/Registry.cpp carries an inc-zmk marker, so the row
    # must be silent even though half of it is unmarked.
    if printf '%s\n' "$p3" | grep -q 'WARN: .* names src/MapAudit.cpp as the fix site(s) for inc-aaa' &&
       printf '%s\n' "$p3" | grep -q 'FAIL: .* names src/NoSuchFile.cpp .* no such file exists' &&
       ! printf '%s\n' "$p3" | grep -q 'for inc-upw.13' &&
       ! printf '%s\n' "$p3" | grep -q 'for inc-zmk'; then
        printf 'selftest ok    %-34s -> unmatched row named, matched rows silent\n' \
            "table row without its marker"
    else
        printf 'selftest FAIL  %-34s -> pass 3 did not separate the two rows\n' \
            "table row without its marker"
        printf '%s\n' "$p3" | sed 's/^/    | /'
        rc=1
    fi

    rm -rf "$dir"

    # And the end-to-end failure path: a malformed tag must make the real run
    # exit non-zero, not merely print something.
    local probe="src/.selftest_malformed_probe.c"
    if [ -e "$probe" ]; then
        printf 'selftest FAIL  %-34s -> %s already exists\n' "probe file" "$probe"
        return 1
    fi
    printf '/* upstream (inc-l0t, Traced, not sent): synthetic selftest probe. */\n' > "$probe"
    ( run_checks ) > /dev/null 2>&1
    local probe_rc=$?
    rm -f "$probe"
    if [ "$probe_rc" -ne 0 ]; then
        printf 'selftest ok    %-34s -> exit %s\n' "malformed probe fails the run" "$probe_rc"
    else
        printf 'selftest FAIL  %-34s -> exit 0, the blind spot is back\n' \
            "malformed probe fails the run"
        rc=1
    fi

    # ... and that the tree as it stands passes, so the line above proves the
    # probe caused the failure and not some pre-existing defect.
    ( run_checks ) > /dev/null 2>&1
    local clean_rc=$?
    if [ "$clean_rc" -eq 0 ]; then
        printf 'selftest ok    %-34s -> exit 0\n' "tree without the probe passes"
    else
        printf 'selftest FAIL  %-34s -> exit %s, so the probe result proves nothing\n' \
            "tree without the probe passes" "$clean_rc"
        rc=1
    fi

    echo
    [ "$rc" -eq 0 ] && echo "selftest: pass" || echo "selftest: FAIL"
    return "$rc"
}

while [ $# -gt 0 ]; do
    case "$1" in
        # Kept as a no-op so a caller written before 2026-08-23 still runs.
        --strict)   STRICT=1; shift ;;
        --selftest) selftest; exit $? ;;
        *) echo "usage: $0 [--strict] | --selftest" >&2; exit 2 ;;
    esac
done

run_checks
exit $?
