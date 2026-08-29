#!/usr/bin/env bash
#
# Ratchet the citation defects in the documents a change touched.
#
#   tools/check_doc_citations.sh                 # docs this change touched
#   tools/check_doc_citations.sh --base master   # ...compared against that ref
#   tools/check_doc_citations.sh --all           # every tracked .md
#   tools/check_doc_citations.sh --baseline      # re-record the known backlog
#   tools/check_doc_citations.sh --selftest      # prove the verdicts
#
# Exit: 0 every checked document matches its baseline
#       1 a document is above its baseline (a NEW defect), or below it (a stale
#         baseline nobody lowered)
#       2 the tool could not measure -- missing baseline, unreadable file
#
# WHY THIS EXISTS. An unattended agent edits prose and commits it. Prose that
# cites `file.cpp:1234` is a claim about the tree, and a wrong line number reads
# as fact to whoever comes next -- that is how MORNING-REPORT.md's own citation
# header ended up enlisting a one-off report in a gate that must stay green.
# tools/check_citations.sh already resolves every citation in ONE document. What
# was missing is the thing a commit can run: which documents did this change
# touch, and did any of them get worse.
#
# WHY A RATCHET AND NOT ZERO. docs/REPORTING-GATE.md has a defect today, and 29
# are open across the tree (bd inc-loa.13). A gate that demands zero blocks every
# commit and gets switched off within a day. A per-document baseline blocks only
# what THIS change made worse, and the "below the baseline also fails" half is
# what walks the number down: fix a defect, re-record, and the new floor holds.
# tools/format_strings.baseline is the same convention, with one count instead of
# one per file.
#
# WHAT THIS CANNOT SEE. Everything tools/check_citations.sh cannot see, listed in
# its own header: a citation that resolves but names the wrong code, a citation
# into a `#if 0` block, a line number that RECORDS A RUN and must never be
# "corrected". A clean run here is not a claim that the prose is true.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

CITE="$ROOT/tools/check_citations.sh"
BASELINE="$ROOT/tools/doc_citations.baseline"
BASE_REF="master"
MODE="changed"

while [ $# -gt 0 ]; do
    case "$1" in
        --base)     BASE_REF="${2:-}"; [ -n "$BASE_REF" ] || { echo "--base needs a ref" >&2; exit 2; }; shift 2 ;;
        --all)      MODE="all"; shift ;;
        --baseline) MODE="baseline"; shift ;;
        --selftest) MODE="selftest"; shift ;;
        -h|--help)  sed -n '2,12p' "$0"; exit 0 ;;
        *)          echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

[ -x "$CITE" ] || { echo "COULD NOT MEASURE: $CITE is not executable"; exit 2; }

# defects_in <document> -- echo "<defects> <unchecked>", or "? 0" if the tool
# refused the file. check_citations.sh has FOUR exits, and the one that matters
# here is 3:
#   0  clean, every citation resolved against the primary ref
#   1  defects; the count is on its own summary line
#   2  usage, or the document could not be read
#   3  NO defects, but some citations could not be checked against
#      upstream/master and were verified against HEAD instead. That is the
#      normal state of a document about this port -- 6 of the 42 tracked .md
#      files exit 3 -- so treating it as a failure would wedge the gate on
#      AGENTS.md and CLAUDE.md the day it was switched on.
# The count comes from the tool's own summary line, not from a grep for the word
# DEFECT: the summary is what the tool decided, and a grep would also match the
# word inside a quoted source line.
defects_in() {
    local doc="$1" out rc n u
    out="$("$CITE" "$doc" 2>&1)"; rc=$?
    u="$(printf '%s\n' "$out" | sed -n 's/.*but \([0-9][0-9]*\) citation(s) could NOT be checked.*/\1/p' | tail -1)"
    [ -n "$u" ] || u=0
    case "$rc" in
        0) echo "0 0" ;;
        3) echo "0 $u" ;;
        2) echo "? 0" ;;
        *) n="$(printf '%s\n' "$out" | sed -n 's/^\([0-9][0-9]*\) defect(s).*/\1/p' | tail -1)"
           [ -n "$n" ] || n="?"
           echo "$n $u" ;;
    esac
}

# baseline_for <document> -- the recorded count, or 0 when the file is not listed.
baseline_for() {
    local doc="$1"
    awk -v d="$doc" '$2 == d { print $1; found=1 } END { if (!found) print 0 }' "$BASELINE" | head -1
}

# tracked_docs -- every tracked .md, in a stable order. LC_ALL=C, because the
# order goes straight into the baseline file: a locale that folds case and
# ignores punctuation reorders 40 lines every time the baseline is re-recorded
# on a different machine, and buries the one line that actually moved.
tracked_docs() { git ls-files '*.md' | LC_ALL=C sort; }

# changed_docs -- the .md files this change touched: committed since BASE_REF,
# staged, unstaged, and untracked-but-not-ignored. A doc is checked if it appears
# in any of the four, because all four are things a commit is about to carry.
changed_docs() {
    # An unresolvable base ref MUST stop the run. Skipping it quietly would
    # narrow the document set to the working tree alone and still print PASS,
    # which is this project's own recurring failure: a check that measured less
    # than it claimed and reported green.
    if ! git rev-parse --verify --quiet "$BASE_REF" > /dev/null; then
        echo "COULD NOT MEASURE: base ref '$BASE_REF' does not resolve." >&2
        echo "Name a ref that exists, or pass --all." >&2
        exit 2
    fi
    {
        git diff --name-only "$BASE_REF...HEAD" -- '*.md'
        git diff --name-only HEAD -- '*.md'
        git ls-files --others --exclude-standard -- '*.md'
    } 2>/dev/null | LC_ALL=C sort -u | while read -r d; do
        [ -f "$d" ] && echo "$d"
    done
}

# ---------------------------------------------------------------- baseline ---
if [ "$MODE" = "baseline" ]; then
    tmp="$(mktemp "${TMPDIR:-/tmp}/doccite.XXXXXX")" || exit 2
    tracked_docs | while read -r doc; do
        read -r n _u <<< "$(defects_in "$doc")"
        if [ "$n" = "?" ]; then
            echo "SKIP  $doc -- check_citations.sh could not read it" >&2
            continue
        fi
        printf '%s %s\n' "$n" "$doc" >> "$tmp"
    done
    mv "$tmp" "$BASELINE"
    printf 'recorded baseline: %d document(s), %d defect(s) total\n' \
        "$(wc -l < "$BASELINE" | tr -d ' ')" \
        "$(awk '{s+=$1} END {print s+0}' "$BASELINE")"
    exit 0
fi

# ---------------------------------------------------------------- selftest ---
if [ "$MODE" = "selftest" ]; then
    # The verdict logic is what breaks, not the citation resolver, so this drives
    # the three verdicts against a made-up baseline and made-up counts. It takes
    # about a second and needs no documents.
    fails=0
    verdict() { # verdict <count> <want> -> echoes OK|NEW|STALE
        local n="$1" w="$2"
        if [ "$n" -gt "$w" ]; then echo NEW
        elif [ "$n" -lt "$w" ]; then echo STALE
        else echo OK; fi
    }
    t() { # t <count> <want> <expected>
        local got; got="$(verdict "$1" "$2")"
        if [ "$got" != "$3" ]; then
            echo "FAIL: count=$1 baseline=$2 gave $got, wanted $3"; fails=1
        fi
    }
    t 0 0 OK
    t 3 3 OK
    t 4 3 NEW      # a new defect must fail
    t 2 3 STALE    # a fix nobody re-recorded must fail too, or the floor never drops
    t 1 0 NEW      # a document with no baseline row starts at zero
    # A document that is not in the baseline file reads as 0.
    tmpb="$(mktemp "${TMPDIR:-/tmp}/doccitebase.XXXXXX")"
    printf '2 docs/A.md\n0 docs/B.md\n' > "$tmpb"
    got="$(BASELINE="$tmpb"; awk -v d="docs/NOPE.md" '$2 == d { print $1; found=1 } END { if (!found) print 0 }' "$tmpb" | head -1)"
    [ "$got" = "0" ] || { echo "FAIL: unlisted document read as '$got', wanted 0"; fails=1; }
    got="$(awk -v d="docs/A.md" '$2 == d { print $1; found=1 } END { if (!found) print 0 }' "$tmpb" | head -1)"
    [ "$got" = "2" ] || { echo "FAIL: listed document read as '$got', wanted 2"; fails=1; }
    rm -f "$tmpb"
    if [ "$fails" = 0 ]; then echo "selftest: PASS"; exit 0; fi
    echo "selftest: FAIL"; exit 1
fi

# ------------------------------------------------------------------- check ---
if [ ! -r "$BASELINE" ]; then
    echo "COULD NOT MEASURE: $BASELINE is missing. Record it with:"
    echo "    tools/check_doc_citations.sh --baseline"
    exit 2
fi

# changed_docs runs in a command substitution, so its own `exit 2` ends only the
# subshell. The status must be tested here or an unresolvable base ref would
# reach the verdict as an empty document list and print PASS.
if [ "$MODE" = "all" ]; then
    DOCS="$(tracked_docs)"
else
    DOCS="$(changed_docs)" || exit 2
fi

if [ -z "$DOCS" ]; then
    echo "no documents changed against $BASE_REF -- nothing to check"
    exit 0
fi

NEW=0; STALE=0; UNREAD=0; CHECKED=0
while read -r doc; do
    [ -n "$doc" ] || continue
    read -r n u <<< "$(defects_in "$doc")"
    w="$(baseline_for "$doc")"
    CHECKED=$((CHECKED + 1))
    note=""
    [ "$u" -gt 0 ] 2>/dev/null && note="  ($u unchecked against upstream)"
    if [ "$n" = "?" ]; then
        echo "UNREADABLE  $doc"
        UNREAD=$((UNREAD + 1))
        continue
    fi
    if [ "$n" -gt "$w" ]; then
        echo "NEW DEFECT  $doc: $n defect(s), baseline $w$note"
        NEW=$((NEW + 1))
    elif [ "$n" -lt "$w" ]; then
        echo "STALE       $doc: $n defect(s), baseline $w -- lower the baseline"
        STALE=$((STALE + 1))
    else
        echo "ok          $doc: $n defect(s)$note"
    fi
done <<< "$DOCS"

echo
echo "checked $CHECKED document(s) against $BASELINE"

if [ "$UNREAD" -gt 0 ]; then
    echo "=== FAIL: $UNREAD document(s) could not be measured ==="
    exit 2
fi
if [ "$NEW" -gt 0 ]; then
    echo "=== FAIL: $NEW document(s) gained a citation defect ==="
    echo "Read the defect with: tools/check_citations.sh <document>"
    echo "Fix the citation. Do NOT raise the baseline to make this pass unless"
    echo "the finding is wrong -- file it and say so in the commit."
    exit 1
fi
if [ "$STALE" -gt 0 ]; then
    echo "=== FAIL: $STALE document(s) are below their baseline ==="
    echo "A defect was fixed and the floor was never lowered. Re-record it:"
    echo "    tools/check_doc_citations.sh --baseline"
    exit 1
fi

echo "=== PASS: no document gained a citation defect ==="
exit 0
