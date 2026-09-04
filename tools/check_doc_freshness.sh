#!/usr/bin/env bash
#
# Say which documents a range of commits may have made stale, and resolve every
# line citation in the documents and the source those commits touched.
#
#   tools/check_doc_freshness.sh                     since the last recorded run
#   tools/check_doc_freshness.sh --since HEAD~5      an explicit range
#   tools/check_doc_freshness.sh --since <sha> --quiet
#   tools/check_doc_freshness.sh --selftest
#
# WHY THIS EXISTS. On 2026-08-20 a sweep of sixteen documents checked 782 claims
# and corrected 358. Roughly 300 of those were line-number drift, and every one
# was mechanical: three insertions moved whole files under citations that had
# been right when they were written. A 102-line probe block at the top of
# src/Event.cpp moved 92 of that page's 131 citations. Nothing noticed for days.
#
# The work was mechanical, so a schedule can do it. This tool is the detector.
#
# WHAT IT DOES NOT DO, AND THAT IS DELIBERATE
#
# It does not edit anything. Detection is mechanical; correction needs judgement,
# and three kinds of judgement in particular that a script MUST NOT make:
#
#   1. A line number that RECORDS A PAST RUN is evidence, not a pointer. ASSERT
#      emits __FILE__ and __LINE__, so "asserts at Base.h:577 89,545 -> 0" quotes
#      what the tool printed in the build that was measured. Rewriting 577 to
#      today's line falsifies the record. src/Target.cpp:1104 is the worked
#      example: it keeps the run's number and names today's location beside it.
#   2. A citation can resolve perfectly and still be wrong, because the line it
#      names is no longer the line the prose described. This tool answers "does
#      that address exist"; only a person answers "is that the code you meant".
#   3. A citation can point into a #if 0 block. src/Display.cpp:575-693 holds
#      compiled-out twins of six accessors, and a citation into them passes every
#      address check while naming code the compiler never emits.
#
# So it reports. A human or an agent session fixes. A green run is not an
# all-clear; it means no address is broken.
#
# THE STALENESS MAP
#
# docs/doc-deps.tsv maps a source path to the documents that cite it, one
# `path<TAB>doc` per line. Given a commit range, the intersection of its changed
# paths with column 1 names the documents worth re-reading.
#
# The map is a starting point and it is NOT self-maintaining. It was built from
# what a sweep actually cited on 2026-08-20. A document that grows a citation
# into a file not yet in its column will not be flagged when that file changes.
# Re-derive it when the documents move enough to matter; until then it is better
# than nothing and honest about being so.
#
# Exit status:
#   0  nothing to report
#   1  something needs a human: a broken citation, or a stale document
#   2  the invocation was wrong, or the tree is not usable

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

DEPS="docs/doc-deps.tsv"
STATE=".beads/.doc-freshness-last"     # not tracked; a marker, not a source of truth
QUIET=0
SINCE=""

say()  { [ "$QUIET" = 1 ] || printf '%s\n' "$*"; }
warn() { printf '%s\n' "$*" >&2; }

# ------------------------------------------------------------------ helpers ---

# Documents that cite any of the paths on stdin. Reads the map once.
# Kept as a function so the selftest can drive it with a map of its own.
stale_docs_for() {
    local deps="$1" changed="$2"
    [ -s "$deps" ] || return 0
    awk -F'\t' '
        NR==FNR { changed[$0]=1; next }
        NF < 2  { next }
        ($1 in changed) { print $2 }
    ' "$changed" "$deps" | sort -u
}

# Every citation checker call goes through here so the refs are set in one place.
# Both refs are HEAD on purpose: these are OUR documents citing OUR tree, so the
# upstream-first model check_citations.sh uses for outgoing text does not apply,
# and leaving UPSTREAM_REF at its default would measure our pages against rmtew.
cite_check() {
    UPSTREAM_REF=HEAD FALLBACK_REF=HEAD tools/check_citations.sh "$1" 2>&1
}

# ------------------------------------------------------------------ selftest ---

selftest() {
    local tmp rc=0
    tmp="$(mktemp -d)" || return 2
    trap 'rm -rf "$tmp"' RETURN

    # 1. The intersection picks exactly the documents that cite a changed path.
    printf 'src/Event.cpp\tENGINE-EVENTS\nsrc/Event.cpp\tENGINE-MAP\ninc/Map.h\tENGINE-MAP\n' \
        > "$tmp/deps.tsv"
    printf 'src/Event.cpp\n' > "$tmp/changed"
    local got want
    got="$(stale_docs_for "$tmp/deps.tsv" "$tmp/changed" | tr '\n' ' ')"
    want="ENGINE-EVENTS ENGINE-MAP "
    if [ "$got" != "$want" ]; then
        warn "selftest: intersection wrong. want '$want' got '$got'"; rc=1
    fi

    # 2. A changed path nothing cites yields nothing. The empty case is the one
    #    that would otherwise flag every document on every commit.
    printf 'src/Nothing.cpp\n' > "$tmp/changed"
    got="$(stale_docs_for "$tmp/deps.tsv" "$tmp/changed" | tr '\n' ' ')"
    if [ -n "$got" ]; then
        warn "selftest: unrelated path matched '$got', want nothing"; rc=1
    fi

    # 3. A malformed map line is skipped, not treated as a document named "".
    printf 'src/Event.cpp\nbroken-line-with-no-tab\n' > "$tmp/deps.tsv"
    printf 'src/Event.cpp\n' > "$tmp/changed"
    got="$(stale_docs_for "$tmp/deps.tsv" "$tmp/changed" | tr '\n' ' ')"
    if [ -n "$got" ]; then
        warn "selftest: malformed map line produced '$got', want nothing"; rc=1
    fi

    # 4. The citation checker really is a gate: a citation past end of file MUST
    #    fail. Without this the whole run can go green on a broken resolver.
    #
    #    The specimen MUST have a basename unique in the tree. README.md does
    #    not -- there are several -- and the checker rejects it as ambiguous,
    #    which fails check 4 for a reason that has nothing to do with range.
    #    That is the trap check 5 exists to expose, and it did.
    local lines
    lines=$(wc -l < src/Wposix.cpp | tr -d ' ')
    printf 'A planted citation: Wposix.cpp:%d\n' "$((lines + 5000))" > "$tmp/bad.md"
    if cite_check "$tmp/bad.md" >/dev/null 2>&1; then
        warn "selftest: check_citations.sh passed an out-of-range citation"; rc=1
    fi

    # 5. And a real one MUST pass, or check 4 proves nothing.
    printf 'A real citation: Wposix.cpp:1\n' > "$tmp/good.md"
    if ! cite_check "$tmp/good.md" >/dev/null 2>&1; then
        warn "selftest: check_citations.sh failed a valid citation"; rc=1
    fi

    # 6. The shift filter must never widen the set it filters. Whatever range is
    #    used, a path reported as SHIFTED must also be a path that CHANGED --
    #    otherwise the filter is inventing work rather than removing it.
    local chg shf extra
    chg="$(git diff --name-only HEAD~3 HEAD 2>/dev/null | sort)"
    if [ -n "$chg" ]; then
        shf=""
        while IFS= read -r p; do
            [ -n "$p" ] || continue
            local la lb
            la=$(git show "HEAD~3:$p" 2>/dev/null | wc -l | tr -d ' ')
            lb=$(git show "HEAD:$p"   2>/dev/null | wc -l | tr -d ' ')
            [ "$la" = "$lb" ] || shf="$shf$p"$'\n'
        done <<< "$chg"
        extra="$(comm -13 <(printf '%s\n' "$chg") <(printf '%s' "$shf" | sort) | tr -d '[:space:]')"
        if [ -n "$extra" ]; then
            warn "selftest: shift filter reported a path that did not change: $extra"; rc=1
        fi
    fi

    # 7. An empty range must be silent and exit 0. A tool that reports findings
    #    when nothing happened trains its reader to ignore it.
    local emptyout
    emptyout="$("$0" --since HEAD --quiet 2>&1)"
    if [ $? != 0 ] || [ -n "$emptyout" ]; then
        warn "selftest: empty range was not silent (exit $?, output '$emptyout')"; rc=1
    fi

    [ "$rc" = 0 ] && say "PASS: check_doc_freshness selftest"
    return $rc
}

# ---------------------------------------------------------------- arguments ---

while [ $# -gt 0 ]; do
    case "$1" in
        --selftest) selftest; exit $? ;;
        --since)    SINCE="${2:-}"; [ -n "$SINCE" ] || { warn "--since needs a ref"; exit 2; }; shift 2 ;;
        --quiet)    QUIET=1; shift ;;
        -h|--help)  sed -n '2,12p' "$0"; exit 0 ;;
        *)          warn "unknown argument '$1'"; exit 2 ;;
    esac
done

git rev-parse --git-dir >/dev/null 2>&1 || { warn "not a git tree"; exit 2; }

# The range. An explicit --since wins. Otherwise the last recorded run, and if
# there is none, the previous commit -- which is the right default for a cron
# firing after each push, and harmless for a first run.
if [ -z "$SINCE" ]; then
    if [ -r "$STATE" ] && SINCE="$(cat "$STATE")" && git rev-parse --verify --quiet "$SINCE^{commit}" >/dev/null; then
        :
    else
        SINCE="HEAD~1"
    fi
fi
git rev-parse --verify --quiet "$SINCE^{commit}" >/dev/null || { warn "cannot resolve '$SINCE'"; exit 2; }

HEAD_SHA="$(git rev-parse HEAD)"
say "Range: $SINCE..$HEAD_SHA"

TMP="$(mktemp -d)" || exit 2
trap 'rm -rf "$TMP"' EXIT

git diff --name-only "$SINCE" HEAD > "$TMP/changed" || exit 2

# SHIFTED, not merely CHANGED. A citation moves only when lines are inserted or
# removed above it, so a file whose length is identical at both ends of the range
# cannot have moved any citation into it. Editing a line in place is the common
# case -- a renamed variable, a corrected comment -- and flagging every document
# that cites the file for that is how a daily report becomes noise nobody reads.
#
# This is a proxy, and it is deliberately the cheap one. A file that gains three
# lines and loses three elsewhere has the same length and DOES shift the
# citations between those two points. Such a commit is rare and the citation
# resolver below still reads every changed file, so the address check is not
# weakened -- only the "worth re-reading" list is narrowed.
: > "$TMP/shifted"
while IFS= read -r p; do
    a=$(git show "$SINCE:$p" 2>/dev/null | wc -l | tr -d ' ')
    b=$(git show "HEAD:$p"   2>/dev/null | wc -l | tr -d ' ')
    [ "$a" = "$b" ] || printf '%s\n' "$p" >> "$TMP/shifted"
done < "$TMP/changed"
if [ ! -s "$TMP/changed" ]; then
    say "No files changed in range. Nothing to check."
    printf '%s\n' "$HEAD_SHA" > "$STATE" 2>/dev/null || true
    exit 0
fi
say "Changed files: $(wc -l < "$TMP/changed" | tr -d ' ')"

FINDINGS=0

# ---------------------------------------------- 1. documents made stale ------

if [ -r "$DEPS" ]; then
    stale_docs_for "$DEPS" "$TMP/shifted" > "$TMP/stale"
    if [ -s "$TMP/stale" ]; then
        say ""
        say "Documents citing source that changed LENGTH in this range:"
        while IFS= read -r d; do
            say "  $d"
        done < "$TMP/stale"
        say ""
        say "  These are not necessarily wrong. They are the pages worth re-reading."
        FINDINGS=1
    fi
else
    warn "note: $DEPS is missing, so no staleness map was applied."
fi

# ------------------------- 2. citations in the documents and source touched ---

# Both are checked, because a rotted citation inside a source COMMENT is the
# defect nothing else gates: tools/check_citations.sh is pointed at outgoing
# documents only, and four rotted comment citations were found on 2026-08-20,
# two of them inside `upstream:` blocks -- the text that goes to rmtew.

# doc_for_label -- the second column of docs/doc-deps.tsv holds a LABEL, not a
# path, so every use of one has to turn it back into a file. That mapping lives
# here and only here: it used to be written inline in the loop below, and a
# second copy would drift from the first the moment either grew a case.
#
# Prints the path, or prints nothing when the label names no document.
doc_for_label() {
    case "$1" in
        README) [ -f README.md ] && echo README.md ;;
        TOOLS)  [ -f tools/README.md ] && echo tools/README.md ;;
        AGENTS) [ -f AGENTS.md ] && echo AGENTS.md ;;
        *)      [ -f "docs/$1.md" ] && echo "docs/$1.md" ;;
    esac
}

{
    # every changed file that carries citations worth resolving
    grep -E '\.(md|cpp|c|h|sh|py|keys)$' "$TMP/changed" || true
    # plus every document flagged stale above, whether or not it changed
    if [ -s "$TMP/stale" ]; then
        while IFS= read -r name; do
            doc_for_label "$name"
        done < "$TMP/stale"
    fi
} | sort -u > "$TMP/tocheck"

# A LABEL THAT NAMES NO DOCUMENT IS A FINDING, NOT A SILENT SKIP.
#
# Until 2026-08-29 the loop above resolved a label by looking for
# docs/<label>.md, with hardcoded cases for README and TOOLS, and said nothing
# at all when it found neither. Three labels were in that state and had been
# since the map was written on 2026-08-21: AGENTS, whose file is AGENTS.md at
# the repository root and simply needed the third case; and SCRIPT-LANG and
# VERBS-HEADLESS, which name no document in this repository and never have.
#
# The cost was not the missing check. It was that the report named those pages
# as worth re-reading and there was no such page to open, so a reader who went
# looking learned to distrust the list. A map that names a document nobody can
# find is worse than a map with a hole in it, because the hole is invisible.
if [ -s "$TMP/stale" ]; then
    while IFS= read -r name; do
        [ -n "$(doc_for_label "$name")" ] && continue
        say ""
        say "UNRESOLVED LABEL \"$name\" in $DEPS names no document."
        say "  Nothing was cite-checked for it. Rename the label to a document"
        say "  that exists, or delete its rows."
        FINDINGS=1
    done < "$TMP/stale"
fi

say ""
BROKEN=0
while IFS= read -r f; do
    [ -f "$f" ] || continue          # deleted in the range
    # tools/check_citations.sh documents and tests citation-checking, so it is
    # deliberately full of broken citations -- in its explanatory comments as
    # well as its printf fixtures -- and cite-checking it only ever produces
    # findings nobody can act on. Comment-only scanning cannot help, because the
    # fakes are in the comments too. Its own --selftest is what guards it, so it
    # is skipped here by name (inc-loa.14). It is the only self-referential file:
    # the sibling citation tools cite-check clean.
    case "$f" in tools/check_citations.sh) continue ;; esac
    out="$(cite_check "$f")"
    rc=$?
    [ "$rc" = 0 ] && continue
    # WHAT THE HEADER MUST NOT SAY. tools/check_citations.sh also exits
    # non-zero when a document is CLEAN but carries citations it declined to
    # check -- a link into a third-party repository this clone has no remote
    # for is the usual one. Printing "CITATION DEFECT in AGENTS.md:" and then
    # listing nothing under it, which is what a bare rc test does, announces a
    # defect the reader cannot find and cannot fix. Report what was actually
    # measured: defects when there are defects, and the unchecked count
    # otherwise, which is a note and not a finding.
    lines="$(printf '%s\n' "$out" | grep -E '^(DEFECT|WARN)')"
    if [ -n "$lines" ]; then
        say "CITATION DEFECT in $f:"
        printf '%s\n' "$lines" | sed 's/^/  /'
        BROKEN=$((BROKEN + 1))
        FINDINGS=1
    else
        say "note: $f has $(printf '%s\n' "$out" | grep -c '^UNCHECKED') citation(s) this clone cannot check, and no defect."
    fi
done < "$TMP/tocheck"

if [ "$BROKEN" = 0 ]; then
    say "Every citation in the changed files and stale documents resolves."
fi

# --------------------------------------------------------------- the verdict --

say ""
if [ "$FINDINGS" = 0 ]; then
    say "PASS: nothing to report for $SINCE..$HEAD_SHA"
else
    say "Findings above need a human. Remember what this tool cannot see:"
    say "  - a citation that resolves but names the wrong code"
    say "  - a citation into a #if 0 block"
    say "  - a number in prose with no command beside it"
    say "  - a line number that RECORDS A RUN, which MUST NOT be 'corrected'"
fi

printf '%s\n' "$HEAD_SHA" > "$STATE" 2>/dev/null || true
exit "$FINDINGS"
