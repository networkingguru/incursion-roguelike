#!/usr/bin/env bash
# Prove which commit caused a difference between a converted .char and its old
# .sav (bead inc-10v7f, phase 11c).
#
# tools/char_convert.sh stops at lines no mapping can set: an old .sav was made
# before later rules changes, so a build on today's rules differs from its dump
# in RESULTS (an ability that became a feat, a derived attribute). The owner's
# ruling of 2026-11-09: such a difference MAY be accepted when a named later
# commit explains it, and the explanation MUST be proved by undoing that
# commit's content on today's tree, rebuilding, and seeing the difference
# vanish. This tool is that proof. It names no commit itself.
#
# Usage: tools/char_attribute.sh [--per-commit] <fixture> <out.char> <commit>...
#        tools/char_attribute.sh --candidates <fixture>
#        INCURSION_BIN=<binary>       the TODAY'S-TREE binary (default ./incursion-headless);
#                                     build it first: BACKEND=posix ./build_macos.sh
#        CHAR_ATTR_LOGS=<dir>         specimens (default logs/phase11c/attr)
#        CHAR_ATTR_MANIFEST=<file>    the MANIFEST (default tools/fixtures/chars/MANIFEST)
#        CHAR_ATTR_DIR=<dir>          where <fixture>.sav lives (default tools/fixtures/chars)
#        CHAR_ATTR_KEEP_TREE=1        keep the scratch trees (default: remove them)
#
#   <fixture>   a MANIFEST name; its old .sav is the oracle.
#   <out.char>  the converted .char (tools/char_convert.sh output, written even
#               when the fixture does not convert). Its options: line names the
#               settings both dumps use, and its `# arrival:` header line (key
#               script, seed, skip, tick, map stream) names the arrival replayed on every
#               build, through tools/char_arrive.sh, the script tools/char_convert.sh
#               also calls. A .char with no arrival line is compared at the end of
#               creation, and the record says so.
#   <commit>    one or more commits whose lib/ src/ inc/ part is undone.
#
# STEPS
#   0. BASE: build <out.char> with today's binary (the worktree's own tools,
#      binary and module), play its arrival, dump it and the old .sav; keep the
#      diff lines.
#   1. For the set of all named commits: copy today's tree to a scratch tree
#      (rsync of the working tree minus .git, logs, save, build, docs and build
#      products; never a git worktree or branch), reverse the lib/ src/ inc/ part
#      of each commit newest first (`git show <c> -- lib src inc | git apply -R`),
#      build the headless binary AND the module IN THE COPY, then (when the .char's
#      `# rolls:` header lines name unseen rolls) search those rolls again in the
#      COPY (tools/char_roll_search.py, the copy's binary), so a roll and a rules
#      change that move the same lines are separated; a search that does not
#      match leaves the .char's values. Then build the .char (or the search's
#      match) and dump both with the COPY's tools, binary and module. The record shows
#      the copy's binary and module are newer than the copy and by checksum
#      whether they differ from the worktree's.
#   2. With more than one commit and an empty difference at step 1 (or with
#      --per-commit), repeat step 1 once per commit, that commit alone; the lines its undo removes from the BASE
#      difference are counted (a line of the base diff absent from the new diff).
#
# RESULTS (first line of stdout; exit 0 only for PROVEN)
#   PROVEN         exit 0  the dumps match outside the allowlist of
#                          tools/canon_compare.py with all commits undone, and
#                          (more than one commit) each commit alone removes at
#                          least one line of the base difference.
#   UNEXPLAINED    exit 1  lines remain with all commits undone; they are printed.
#   PADDING        exit 3  a named commit whose undo alone removes no line; or the
#                          dumps already match on today's tree, so nothing needs
#                          explaining.
#   NOT_REVERSIBLE exit 4  a reverse did not apply; the commit and the file are named.
#   BUILDFAIL      exit 5  the copy or the .char did not build; the line is printed.
#   exit 2: usage or an input is missing.
#
# Writes <logs>/<fixture>/record.txt (fixture, old .sav date, commits, result,
# line counts, per commit the lines its undo removed) and one line to
# <logs>/<fixture>/history.txt per run.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

LOGS="${CHAR_ATTR_LOGS:-logs/phase11c/attr}"
MANIFEST="${CHAR_ATTR_MANIFEST:-tools/fixtures/chars/MANIFEST}"
FDIR="${CHAR_ATTR_DIR:-tools/fixtures/chars}"
BASEBIN="${INCURSION_BIN:-./incursion-headless}"

usage() {
    echo "usage: tools/char_attribute.sh [--per-commit] <fixture> <out.char> <commit>..." >&2
    echo "       tools/char_attribute.sh --candidates <fixture>" >&2
    exit 2
}

PERCOMMIT=0; CANDIDATES=0
while [ $# -gt 0 ]; do
    case "$1" in
        --per-commit) PERCOMMIT=1; shift ;;
        --candidates) CANDIDATES=1; shift ;;
        --) shift; break ;;
        -*) usage ;;
        *) break ;;
    esac
done
NAME="${1:-}"
[ -n "$NAME" ] || usage
SAV="$FDIR/$NAME.sav"
[ -f "$SAV" ] || { echo "char_attribute: no such save: $SAV" >&2; exit 2; }
grep -vE '^[[:space:]]*(#|$)' "$MANIFEST" | awk -v n="$NAME" '$1 == n { f=1 } END { exit !f }' \
    || { echo "char_attribute: no MANIFEST row for $NAME in $MANIFEST" >&2; exit 2; }

SAVCOMMIT="$(git log -1 --format=%H -- "$SAV" 2>/dev/null)"
SAVDATE=untracked
if [ -n "$SAVCOMMIT" ]; then
    SAVDATE="$(git log -1 --format=%cI "$SAVCOMMIT")"
elif [ "$CANDIDATES" -eq 1 ]; then
    echo "char_attribute: $SAV is not committed; its date is unknown" >&2; exit 2
fi

if [ "$CANDIDATES" -eq 1 ]; then
    echo "# $NAME: old .sav last committed $SAVDATE ($(git rev-parse --short "$SAVCOMMIT"))"
    echo "# commits after that date that touch lib/, src/ or inc/: id date subject | files"
    git log --no-merges --after="$SAVDATE" --format='@%h|%cs|%s' --name-only -- lib src inc \
        | awk -F'|' '
            function flush() { if (id != "") { printf "%s %s %s | %s%s\n", id, date, subj, files, (n > 4 ? sprintf(" (+%d more)", n - 4) : "") } }
            /^@/ { flush(); id = substr($1, 2); date = $2; subj = $3; for (i = 4; i <= NF; i++) subj = subj "|" $i; files = ""; n = 0; next }
            NF == 0 { next }
            { n++; if (n <= 4) files = files (files == "" ? "" : ", ") $0 }
            END { flush() }'
    exit 0
fi

OUTCHAR="${2:-}"
[ -n "$OUTCHAR" ] && [ -f "$OUTCHAR" ] || { echo "char_attribute: no such .char: ${OUTCHAR:-<none>}" >&2; usage; }
shift 2
[ $# -ge 1 ] || { echo "char_attribute: name at least one commit" >&2; usage; }
OUTCHAR="$(cd "$(dirname "$OUTCHAR")" && pwd)/$(basename "$OUTCHAR")"
OPTS="$(sed -n 's/^options: *//p' "$OUTCHAR" | head -1)"
ARRIVAL="$(sed -n 's/^# arrival: *//p' "$OUTCHAR" | head -1)"
if [ -n "$ARRIVAL" ]; then
    read -r AKEYS ASEED ASKIP ATICK ASTREAM EXTRA <<< "$ARRIVAL"
    { [ -n "$ASTREAM" ] && [ -z "$EXTRA" ]; } || { echo "char_attribute: the .char's arrival line is not '<keys> <seed> <skip> <tick> <stream>': $ARRIVAL" >&2; exit 2; }
    ARRIVAL_NOTE="arrival replayed: key script $AKEYS, seed $ASEED, skip $ASKIP, tick $ATICK, map stream $ASTREAM"
else
    AKEYS=""; ASEED=""; ASKIP="-"; ATICK="-"; ASTREAM="-"
    ARRIVAL_NOTE="no arrival line in the .char: compared at the end of creation, no arrival replayed"
fi
[ -n "$OPTS" ] && [ -f "$OPTS" ] || { echo "char_attribute: the .char names no existing options: file ($OPTS)" >&2; exit 2; }
# The unseen rolls the converter searched (its `# rolls:` header lines: key|context|ordinal|lo|hi). In every tree with
# commits undone the search runs again (variant), so a roll and a rules change that move the same lines are separated.
ROLLS_TXT=""
[ -x "$BASEBIN" ] || { echo "char_attribute: $BASEBIN not built. Run: BACKEND=posix ./build_macos.sh" >&2; exit 2; }
BASEBIN="$(cd "$(dirname "$BASEBIN")" && pwd)/$(basename "$BASEBIN")"

# Resolve and order the commits, newest first.
FULL=()
for c in "$@"; do
    f="$(git rev-parse --verify -q "$c^{commit}")" || { echo "char_attribute: not a commit: $c" >&2; exit 2; }
    FULL+=("$f")
done
ORDERED=()
while IFS= read -r f; do ORDERED+=("$f"); done < <(git rev-list --no-walk=sorted "${FULL[@]}")
short() { git rev-parse --short "$1"; }

OD="$(mkdir -p "$LOGS/$NAME" && cd "$LOGS/$NAME" && pwd)"
rm -f "$OD"/diff-*.txt "$OD"/built-*.canon "$OD"/old-*.canon "$OD"/rev-*.patch "$OD"/build-*.log "$OD"/err-*.txt
rm -rf "$OD"/out-* "$OD"/tree "$OD"/tree-*
rm -f "$OD"/err-arrive-*.txt "$OD"/rs-* "$OD"/rolls.txt
sed -n 's/^# rolls: *//p' "$OUTCHAR" | tr '|' '\t' > "$OD/rolls.txt"
[ -s "$OD/rolls.txt" ] && ROLLS_TXT="$OD/rolls.txt"
RS_NOTES=""
SUM_BEFORE="$(cksum < "$SAV")"
SAVABS="$(cd "$(dirname "$SAV")" && pwd)/$(basename "$SAV")"

V_RESULT=""; V_MSG=""
# variant <tag> <commit>... : sets V_RESULT (OK, NOT_REVERSIBLE, BUILDFAIL) and V_MSG;
# writes $OD/diff-<tag>.txt. Tag "base" is today's tree in place; any other tag
# is a scratch copy with the named commits undone (none = a plain copy).
variant() {
    local tag="$1"; shift
    local T BIN c p err bad rc log
    V_RESULT=OK; V_MSG=""
    if [ "$tag" = base ]; then
        T="$ROOT"; BIN="$BASEBIN"
    else
        T="$OD/tree"; [ "$tag" != all ] && T="$OD/tree-$tag"
        rm -rf "$T"; mkdir -p "$T"
        rsync -a --exclude='/.git' --exclude='/logs' --exclude='/save' --exclude='/build' \
            --exclude='/docs' --exclude='/website' --exclude='/libtcod' --exclude='/SDL2' \
            --exclude='/pdcurs34' --exclude='/fonts' --exclude='/graphics' --exclude='/mod' \
            --exclude='/lib/program.i' --exclude='/incursion*' --exclude='*.o' "$ROOT/" "$T/" \
            || { V_RESULT=BUILDFAIL; V_MSG="cannot copy the tree"; return; }
        for c in "$@"; do
            p="$OD/rev-$tag-$(short "$c").patch"
            git show --binary --format= "$c" -- lib src inc > "$p"
            [ -s "$p" ] || continue     # no lib/src/inc part: a no-op (PADDING shows it)
            err="$OD/err-$tag-$(short "$c").txt"
            ( cd "$T" && GIT_CEILING_DIRECTORIES="$(dirname "$T")" git apply -R --whitespace=nowarn "$p" ) > "$err" 2>&1
            if [ $? -ne 0 ]; then
                bad="$(sed -n -e 's/^error: patch failed: \(.*\):[0-9]*$/\1/p' -e 's/^error: \(.*\): patch does not apply$/\1/p' "$err" | head -1)"
                V_RESULT=NOT_REVERSIBLE
                V_MSG="$(short "$c") does not reverse on today's tree; file ${bad:-unknown} ($(head -1 "$err" | cut -c1-160))"
                return
            fi
        done
        touch "$T/.attr-marker"
        log="$OD/build-$tag.log"
        ( cd "$T" && BACKEND=posix ./build_macos.sh ) > "$log" 2>&1 \
            || { V_RESULT=BUILDFAIL; V_MSG="the copy did not build: $(grep -m1 -iE 'error|FAIL' "$log" | cut -c1-200)"; return; }
        BIN="$T/incursion-headless"
        { [ -x "$BIN" ] && [ "$BIN" -nt "$T/.attr-marker" ] && [ "$T/mod/Incursion.Mod" -nt "$T/.attr-marker" ]; } \
            || { V_RESULT=BUILDFAIL; V_MSG="the copy's binary or module was not built in the copy"; return; }
    fi
    local pfx="$OD/out-$tag" err="$OD/err-arrive-$tag.txt" use="$OUTCHAR" rsout rsrc
    INCURSION_BIN="$BIN" INCURSION_OPTIONS="$OPTS" "$T/tools/char_dump.sh" "$SAVABS" "$OD/old-$tag.canon" > /dev/null 2>&1 \
        || { V_RESULT=BUILDFAIL; V_MSG="cannot dump $SAV"; return; }
    # In a tree with commits undone the unseen rolls are searched again, in that tree: the values the converter found
    # in today's tree may be the ones that hide a rules change. A search that does not match leaves the .char's values.
    if [ "$tag" != base ] && [ -n "$ROLLS_TXT" ] && [ -n "$AKEYS" ]; then
        rsout="$(INCURSION_BIN="$BIN" "$T/tools/char_roll_search.py" "$OUTCHAR" "$ROLLS_TXT" "$OD/old-$tag.canon" "$OD/rs-$tag" \
            "$AKEYS" "$ASEED" "$OPTS" "$ASKIP" "$ATICK" "$ASTREAM" 2> "$OD/rs-$tag.err")"
        rsrc=$?
        [ "$rsrc" -eq 0 ] && use="$OD/rs-$tag.char"
        RS_NOTES="$RS_NOTES  tree-$tag (exit $rsrc, $([ "$rsrc" -eq 0 ] && echo "its values used" || echo "the .char's values used")): ${rsout:-$(head -1 "$OD/rs-$tag.err")}"$'\n'
    fi
    INCURSION_BIN="$BIN" "$T/tools/char_arrive.sh" "$use" "$pfx" "$AKEYS" "$ASEED" "$OPTS" "$ASKIP" "$ATICK" "$ASTREAM" 2> "$err" \
        || { V_RESULT=BUILDFAIL; V_MSG="the .char did not build or arrive: $(head -1 "$err" | cut -c1-200)"; return; }
    cp "$pfx.canon" "$OD/built-$tag.canon" || { V_RESULT=BUILDFAIL; V_MSG="cannot dump the build"; return; }
    "$ROOT/tools/canon_compare.py" --all "$OD/built-$tag.canon" "$OD/old-$tag.canon" > "$OD/diff-$tag.txt" 2>&1
    rc=$?
    [ "$rc" -le 1 ] || { V_RESULT=BUILDFAIL; V_MSG="canon_compare failed (exit $rc)"; return; }
    if [ "$tag" != base ]; then
        echo "tree-$tag: binary $(cksum < "$BIN" | cut -d' ' -f1) (worktree $(cksum < "$BASEBIN" | cut -d' ' -f1)), module $(cksum < "$T/mod/Incursion.Mod" | cut -d' ' -f1) (worktree $(cksum < "$ROOT/mod/Incursion.Mod" | cut -d' ' -f1)); both built in the copy after $T/.attr-marker" >> "$OD/proof.tmp"
    fi
}

# difflines <diff file>: the content lines of a canon_compare diff.
difflines() { python3 - "$1" <<'PY'
import sys
for i, l in enumerate(open(sys.argv[1]).read().split("\n")):
    if not l or l.startswith("@@") or (i < 2 and l[:4] in ("--- ", "+++ ")):
        continue
    if l[0] in "+-":
        print(l)
PY
}
# removed <base diff> <other diff>: base lines absent from other (a multiset difference).
removed() { python3 - "$1" "$2" <<'PY'
import sys
from collections import Counter
def lines(p):
    out = []
    for i, l in enumerate(open(p).read().split("\n")):
        if not l or l.startswith("@@") or (i < 2 and l[:4] in ("--- ", "+++ ")):
            continue
        if l[0] in "+-":
            out.append(l)
    return Counter(out)
a, b = lines(sys.argv[1]), lines(sys.argv[2])
for l, n in (a - b).items():
    for _ in range(n):
        print(l)
PY
}

rm -f "$OD/proof.tmp"
REC="$OD/record.txt"
fail() {   # fail <RESULT> <exit> <message>
    {
        echo "fixture: $NAME"
        echo "old .sav: $SAV, last committed $SAVDATE"
        echo "converted .char: $OUTCHAR"
        echo "$ARRIVAL_NOTE"
        echo "commits named: $(for f in "${ORDERED[@]}"; do short "$f"; done | tr '\n' ' ')"
        echo "result: $1"
        echo "message: $3"
        [ -n "$RS_NOTES" ] && { echo "roll search inside the undone trees:"; printf '%s' "$RS_NOTES"; }
        [ -f "$OD/proof.tmp" ] && cat "$OD/proof.tmp"
    } > "$REC"
    echo "$(date +%Y-%m-%dT%H:%M:%S) $NAME $(for f in "${ORDERED[@]}"; do short "$f"; done | tr '\n' ' ')=> $1" >> "$OD/history.txt"
    echo "$1: $3"
    exit "$2"
}
cleanup() { [ "${CHAR_ATTR_KEEP_TREE:-}" = 1 ] || rm -rf "$OD"/tree "$OD"/tree-*; }
trap cleanup EXIT

# 0. Base.
variant base
[ "$V_RESULT" = OK ] || fail BUILDFAIL 5 "today's tree: $V_MSG"
BASE_N="$(difflines "$OD/diff-base.txt" | grep -c '')"
if [ "$BASE_N" -eq 0 ]; then
    fail PADDING 3 "the dumps already match on today's tree; no commit is needed to explain anything"
fi

# 1. All commits undone.
variant all "${ORDERED[@]}"
case "$V_RESULT" in
    NOT_REVERSIBLE) fail NOT_REVERSIBLE 4 "$V_MSG" ;;
    BUILDFAIL) fail BUILDFAIL 5 "$V_MSG" ;;
esac
ALL_N="$(difflines "$OD/diff-all.txt" | grep -c '')"
REMOVED_ALL="$(removed "$OD/diff-base.txt" "$OD/diff-all.txt" | grep -c '')"

# 2. Each commit alone.
PERLINES=""; PADDED=""
if { [ "${#ORDERED[@]}" -gt 1 ] && [ "$ALL_N" -eq 0 ]; } || [ "$PERCOMMIT" -eq 1 ]; then
    for c in "${ORDERED[@]}"; do
        s="$(short "$c")"
        variant "$s" "$c"
        case "$V_RESULT" in
            NOT_REVERSIBLE) fail NOT_REVERSIBLE 4 "alone: $V_MSG" ;;
            BUILDFAIL) fail BUILDFAIL 5 "alone, $s: $V_MSG" ;;
        esac
        n="$(removed "$OD/diff-base.txt" "$OD/diff-$s.txt" | grep -c '')"
        PERLINES="$PERLINES$s: undoing it alone removes $n of $BASE_N base difference line(s) (left: $(difflines "$OD/diff-$s.txt" | grep -c ''))"$'\n'
        removed "$OD/diff-base.txt" "$OD/diff-$s.txt" | sed "s/^/    [$s] /" > "$OD/diff-removed-$s.txt"
        [ "$n" -eq 0 ] && PADDED="$PADDED $s"
    done
fi

write_record() {   # write_record <RESULT>
    {
        echo "fixture: $NAME"
        echo "old .sav: $SAV, last committed $SAVDATE ${SAVCOMMIT:+($(short "$SAVCOMMIT"))}"
        echo "converted .char: $OUTCHAR (settings $OPTS)"
        echo "$ARRIVAL_NOTE"
        [ -n "$RS_NOTES" ] && { echo "roll search inside the undone trees (the unseen rolls searched again in each tree):"; printf '%s' "$RS_NOTES"; }
        echo "commits named (newest first): $(for f in "${ORDERED[@]}"; do git log -1 --format='%h %s' "$f"; done | tr '\n' ';')"
        echo "result: $1"
        echo "difference lines on today's tree: $BASE_N"
        echo "difference lines with all named commits undone: $ALL_N (the undo removed $REMOVED_ALL of the base lines)"
        [ -n "$PERLINES" ] && { echo "per commit:"; printf '%s' "$PERLINES" | sed 's/^/  /'; cat "$OD"/diff-removed-*.txt 2>/dev/null; }
        echo "base diff lines:"; difflines "$OD/diff-base.txt" | cut -c1-170 | sed 's/^/  /'
        [ "$ALL_N" -gt 0 ] && { echo "lines left with all undone:"; difflines "$OD/diff-all.txt" | cut -c1-170 | sed 's/^/  /'; }
        echo "proof the copy's binary and module were used:"
        sed 's/^/  /' "$OD/proof.tmp"
    } > "$REC"
    echo "$(date +%Y-%m-%dT%H:%M:%S) $NAME $(for f in "${ORDERED[@]}"; do short "$f"; done | tr '\n' ' ')=> $1 (base $BASE_N, all-undone $ALL_N)" >> "$OD/history.txt"
}

SUM_AFTER="$(cksum < "$SAV")"
[ "$SUM_BEFORE" = "$SUM_AFTER" ] || { echo "char_attribute: THE OLD .sav CHANGED during the run: $SAV" >&2; exit 2; }

if [ "$ALL_N" -gt 0 ]; then
    write_record UNEXPLAINED
    echo "UNEXPLAINED: $ALL_N of $BASE_N difference line(s) remain with all named commits undone:"
    difflines "$OD/diff-all.txt" | cut -c1-170 | head -40
    [ -n "$PERLINES" ] && printf '%s' "$PERLINES"
    echo "(record: $REC)"
    exit 1
fi
if [ -n "$PADDED" ]; then
    write_record PADDING
    echo "PADDING:$PADDED -- undoing it alone removes no difference line (record: $REC)"
    exit 3
fi
write_record PROVEN
echo "PROVEN: with $(for f in "${ORDERED[@]}"; do short "$f"; done | tr '\n' ' ')undone, the $BASE_N difference line(s) of today's tree vanish (record: $REC)"
[ -n "$PERLINES" ] && printf '%s' "$PERLINES"
exit 0
