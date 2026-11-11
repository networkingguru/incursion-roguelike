#!/usr/bin/env bash
# gate: live
#
# Does tools/char_attribute.sh prove which commit caused a conversion difference,
# and does it fail when the proof is wrong?
#
# WHAT IS BEING PROVED (bead inc-10v7f, phase 11c). The tracked old save
# orc-barbarian-seed1-opt0822.sav was made before commit 95ddb886 gave orcs the
# Cannibalism feat, so a build of the hand-written .char on today's tree differs
# from it in four lines of that feat (and in more lines that no reversible commit
# explains). The check runs the tool five times:
#   1. The real save, the hand-written .char, commit 95ddb886. The tool MUST
#      report that undoing the commit removed at least one difference line.
#      Its build on the undone tree is the "old" save of the next steps: a save
#      that differs from today's tree ONLY by that commit.
#   2. That save, 95ddb886: the tool MUST say PROVEN (exit 0).
#   3. That save, 95ddb886 and an unrelated commit (bde7800d, a monster aura in
#      lib/mon4.irh): the tool MUST say PADDING (exit 3).
#   4. That save, the unrelated commit alone: the tool MUST say UNEXPLAINED
#      (exit 1). The real commit omitted.
#   5. That save, commit 25c91507 (the Beginner's Kit; src/Create.cpp has been
#      rewritten since): the tool MUST say NOT_REVERSIBLE (exit 4), naming the file.
# Mutation: CHAR_ATTR_TOOL=<a copy of the tool in tools/> runs the check on the
# copy. A copy whose reversal does nothing makes step 2 report UNEXPLAINED.
#
# fact: the character -- the tracked hand-written tools/fixtures/chars/orc-barbarian-seed1-opt0822.char and the tracked old .sav beside it; every draw is stated in the .char, so no seed or walk decides anything (inc-10v7f)
# fact: the settings -- the options: line of that .char names tools/fixtures/options-2026-08-22.dat; the tool passes it to every dump
# fact: the explaining commit -- 95ddb886, a fixed commit of this history; if it is not there, or its lib/ src/ inc/ part no longer reverses on the tree, the check reports INCONCLUSIVE and names the line the tool printed
# fact: the unrelated commit -- bde7800d, a fixed commit that edits only lib/mon4.irh (a monster aura); step 4 proves it explains nothing here, and a reverse that fails makes the check INCONCLUSIVE
# fact: the conflicting commit -- 25c91507, a fixed commit whose src/Create.cpp part no longer applies; if it ever reverses, step 5 is void and the check reports INCONCLUSIVE
# fact: the synthetic old save -- built by the tool itself, from the hand-written .char, on a copy of the tree with 95ddb886 undone; it is a function of the commit and the .char, not of a seed (inc-10v7f)
# fact: the machine -- rsync, python3 and a headless build in a scratch copy of the tree; the check reports INCONCLUSIVE when the tool reports BUILDFAIL
#
# Usage: INCURSION_BIN=./incursion-headless tools/check_char_attribute.sh
# Exit: 0 every step behaved as stated; 1 a step did not; 2 could not run.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2
BIN="${INCURSION_BIN:-./incursion-headless}"
[ -x "$BIN" ] || { echo "INCONCLUSIVE: $BIN is not built"; exit 2; }
export INCURSION_BIN="$BIN"
TOOL="${CHAR_ATTR_TOOL:-tools/char_attribute.sh}"
NAME=orc-barbarian-seed1-opt0822
CHAR=tools/fixtures/chars/$NAME.char
REAL=95ddb886; UNRELATED=bde7800d; CONFLICT=25c91507
[ -f "$CHAR" ] && [ -f tools/fixtures/chars/$NAME.sav ] && [ -x "$TOOL" ] || { echo "INCONCLUSIVE: $CHAR, its .sav or $TOOL is missing"; exit 2; }
for c in $REAL $UNRELATED $CONFLICT; do
    git cat-file -e "$c^{commit}" 2>/dev/null || { echo "INCONCLUSIVE: commit $c is not in this history"; exit 2; }
done

W="$(mktemp -d "$ROOT/logs/char-attr-check.XXXXXX")" || exit 2
trap 'rm -rf "$W"' EXIT
export CHAR_ATTR_LOGS="$W/logs"
mkdir -p "$W/fx"

fail=0
run() {   # <tag> <args...>: runs the tool; sets RC and OUT (the first line)
    local tag="$1"; shift
    "$TOOL" "$@" > "$W/$tag.out" 2>&1
    RC=$?
    OUT="$(head -1 "$W/$tag.out" | cut -c1-200)"
}
inconclusive() { echo "INCONCLUSIVE: $1: $OUT"; exit 2; }

# 1. The real save.
run s1 $NAME "$CHAR" $REAL
case "$RC" in 0|1) ;; *) inconclusive "step 1 (the tool exited $RC)" ;; esac
REMOVED="$(sed -n 's/.*the undo removed \([0-9][0-9]*\) of the base lines.*/\1/p' "$CHAR_ATTR_LOGS/$NAME/record.txt" 2>/dev/null)"
if [ -n "$REMOVED" ] && [ "$REMOVED" -gt 0 ]; then
    echo "ok   step 1: undoing $REAL removes $REMOVED difference line(s) of the real save"
else
    echo "FAIL step 1: undoing $REAL removed no difference line of the real save (record: ${REMOVED:-none}): $OUT"; fail=1
fi
SYN="$CHAR_ATTR_LOGS/$NAME/out-all-out/$(basename "$CHAR" .char).sav"
[ -f "$SYN" ] || inconclusive "step 1 left no build on the undone tree ($SYN)"
cp "$SYN" "$W/fx/synthetic.sav"
printf 'synthetic tools/keys/none.keys 1 tools/fixtures/options-2026-08-22.dat\n' > "$W/MANIFEST"
export CHAR_ATTR_DIR="$W/fx" CHAR_ATTR_MANIFEST="$W/MANIFEST"

expect() {   # <step> <tag> <exit> <word> <args...>
    local step="$1" tag="$2" want="$3" word="$4"; shift 4
    run "$tag" synthetic "$CHAR" "$@"
    case "$RC" in
        5) inconclusive "step $step (the tool exited 5)" ;;
        4) [ "$want" -ne 4 ] && inconclusive "step $step (the tool exited 4)" ;;
    esac
    if [ "$RC" -eq "$want" ] && [ "${OUT%%:*}" = "$word" ]; then
        echo "ok   step $step: $word ($(echo "$OUT" | cut -c1-120))"
    else
        echo "FAIL step $step: wanted $word (exit $want), got exit $RC: $OUT"; fail=1
    fi
}
expect 2 s2 0 PROVEN $REAL
expect 3 s3 3 PADDING $REAL $UNRELATED
expect 4 s4 1 UNEXPLAINED $UNRELATED
expect 5 s5 4 NOT_REVERSIBLE $CONFLICT
grep -q 'src/Create.cpp' "$W/s5.out" || { echo "FAIL step 5: NOT_REVERSIBLE did not name src/Create.cpp: $OUT"; fail=1; }

[ $fail -eq 0 ] && { echo "PASS: the tool proves a named commit, and says PADDING, UNEXPLAINED and NOT_REVERSIBLE when it should"; exit 0; }
exit 1
