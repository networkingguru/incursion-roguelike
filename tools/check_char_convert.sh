#!/usr/bin/env bash
# gate: live
#
# Does the conversion table (tools/char_convert_map.py) set every kind of
# decision the dump of an old save states, and does the dump comparison catch a
# kind it leaves out?
#
# WHAT IS BEING PROVED (bead inc-10v7f, phase 11b). The hand-written
# tools/fixtures/chars/orc-barbarian-seed1-opt0822.char states the decisions of
# the tracked old save beside it. This check damages a copy of that .char in six
# places, one per kind of decision the table converts: a hit roll (scalar), a
# perk, a feat in the queue, two skill ranks, a kit item quantity, and the
# thrown quantity. It builds the damaged copy and dumps it. It then runs the
# conversion on the damaged copy with the dump of the OLD save: the converted
# .char MUST build a character whose dump equals the dump of the build of the
# hand-written file (outside the one allowlist of tools/canon_compare.py).
# Control: with any one of the six keys withheld (--withhold), the converted
# file MUST build a different character, so a kind the table dropped, or a
# comparison that cannot fail, goes red.
#
# fact: the character -- the tracked hand-written .char and the tracked old .sav beside it; both are committed and every draw is stated in the .char, so no seed or walk decides anything (inc-10v7f)
# fact: the settings -- tools/fixtures/options-2026-08-22-kit.dat, named in the .char's options: line and passed to the dumps (the old .sav was made with OPT_BEGINKIT on)
# fact: the damaged values -- text edits of lines of the tracked .char (a feat, a perk feat, two skill ranks, a hit roll, two quantities); an edit that finds no line fails the check as INCONCLUSIVE
# fact: the replacement feat -- "Endurance", a candidate of the level-1 feat menu for this race and class, read from the module by the build (a name that is not a candidate fails the build, which fails the check)
#
# Second part (phase 11e, the arrival; proved in phase 11g). tools/char_convert.sh
# loads each built character and plays the post-creation part of the old key
# script on it (tools/char_arrive.sh), and demands the line "method proof": the
# replay of the skeleton equals the walk's own final save. A proof that cannot
# fail proves nothing, and on most fixtures it cannot: the part of a key script
# after creation holds many keys that change nothing, so no replay at all, or a
# split point off by one, gives the same dump. So each control runs on a fixture
# whose dump the replay DOES change, and MUST exit 2 with the METHOD DEFECT
# message, the comparison turning red:
#   no replay      (a copy of char_arrive.sh that dumps the built save itself)   orc-rogue-seed1-opt0822
#   split + 1, - 1 (a copy of char_convert.sh that passes the split point +-1)   gnome-warrior-wis3-pickaxe-seed1-opt0822
#   seed tick + 1  (a copy of char_convert.sh that passes the tick + 1)          orc-rogue-seed4-opt0822
# Each fixture first converts with the real tools and prints the proof line.
# Third part (phase 11g): `tools/char_convert_map.py selftest` holds (the charges line of a replaced item perk is found
# by the item's context, a merged stack keeps its sources); INCURSION_KEYS_SKIP=abc is refused (exit 2), and
# tools/canon_compare.py reads the options the build forces from the code of
# src/CharFile.cpp, not from a comment there.
#
# fact: the arrival fixtures -- orc-rogue-seed1-opt0822, gnome-warrior-wis3-pickaxe-seed1-opt0822 and orc-rogue-seed4-opt0822, their MANIFEST rows (key script, seed, settings file) and the walks that record their skeletons; each proof compares the replay with that same walk's own save, and the three controls were measured red on these fixtures (inc-10v7f phase 11g); a fixture whose control no longer goes red makes the check fail, not pass
# fact: the split point and the seed tick -- written by Game::NewGameTail beside the walk save; the check reads them through the tool, never states them
# fact: the map stream position -- written by Game::NewGameTail beside the walk save (<name>.walk.stream), read through char_convert.sh; the fixture hunger-penalty-seed1-opt0822 is the one fixture whose proof the restore decides (measured red without the restore, inc-10v7f phase 11h)
# fact: the random() probe -- the engine's own inline random() from inc/Inline.h compiled with a stub generator and the argument -5; the stub's seed is fixed in this file and decides nothing but which values show
# fact: the roll search verdicts -- synthetic multisets of difference lines inside tools/char_roll_search.py selftest and a temporary dump pair; no game run, no seed
# fact: the comment case -- a copy of src/CharFile.cpp with two comment lines put in front, in a scratch root under logs/ with a copy of tools/canon_compare.py and inc/Defines.h; the two options named in the comments are not the one the code forces, and the case counts the forcing lines the tool lists
#
# Sixth part (phase 12a, the pass rule): a conversion passes when the CHOICES of the build equal the choices of the old
# save (tools/canon_compare.py --choices-diff), less the rows of KNOWN_DIFFERENCES in tools/char_convert_map.py. Controls:
# a changed computed line passes; a changed choice line fails and is named; the table cannot excuse a potion (the
# synthetic Cure Disease pair stays a remainder, and no name in the kit row is a dedupe-exempt kind); each row's cause is
# live (a commit that git resolves, a bead that `bd show` reports not closed).
# fact: the choice dumps -- the dump of the tracked orc-barbarian-seed1-opt0822.sav ($W/old.canon, already made above); the
#   controls edit copies of it, and an edit that finds no line fails the check as INCONCLUSIVE
# fact: the Cure Disease pair -- a synthetic choices-diff written by this file; no game run, no seed
# fact: the row causes -- commit 4e1fc266 in this repository's history; bead inc-tjvn's status read by `bd show inc-tjvn --json` in the live case, and by a synthetic JSONL named by CHAR_CONVERT_BEADS in the stale-row control (no database); the fake-bd runs (red with closed, green with open) are in logs/phase12a/controls-red.txt; no bd or no JSON makes the check fail (exit 2 from causes), not pass

# Usage: INCURSION_BIN=./incursion-headless tools/check_char_convert.sh
# Exit: 0 the table restores all six kinds and each withheld key shows; 1 not; 2 could not run.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2
BIN="${INCURSION_BIN:-./incursion-headless}"
[ -x "$BIN" ] || { echo "INCONCLUSIVE: $BIN is not built"; exit 2; }
export INCURSION_BIN="$BIN"
NAME=orc-barbarian-seed1-opt0822
GOOD=tools/fixtures/chars/$NAME.char
OLD=tools/fixtures/chars/$NAME.sav
KITOPTS=tools/fixtures/options-2026-08-22-kit.dat
[ -f "$GOOD" ] && [ -f "$OLD" ] && [ -f "$KITOPTS" ] || { echo "INCONCLUSIVE: $GOOD, $OLD or $KITOPTS is missing"; exit 2; }
[ -f lib/program.i ] || { echo "INCONCLUSIVE: lib/program.i is missing; build the module first"; exit 2; }

W="$(mktemp -d "$ROOT/logs/char-convert-check.XXXXXX")" || exit 2
trap 'rm -rf "$W"' EXIT

dump_build() {   # <char> <tag>: builds <char>, dumps it to $W/<tag>.canon
    tools/build_fixture.sh "$1" "$W/$2-out" > "$W/$2-build.log" 2>&1 \
        || { echo "INCONCLUSIVE: $1 did not build: $(grep -m1 'BUILD FAILED' "$W/$2-build.log" | cut -c1-300)"; exit 2; }
    INCURSION_OPTIONS="$KITOPTS" tools/char_dump.sh "$W/$2-out/$(basename "$1" .char).sav" "$W/$2.canon" > /dev/null 2>&1 \
        || { echo "INCONCLUSIVE: cannot dump the build of $1"; exit 2; }
}

INCURSION_OPTIONS="$KITOPTS" tools/char_dump.sh "$OLD" "$W/old.canon" > /dev/null 2>&1 \
    || { echo "INCONCLUSIVE: cannot dump $OLD"; exit 2; }
cp "$GOOD" "$W/good.char"
dump_build "$W/good.char" good

# The damage: six edits, each of which must find its line.
cp "$GOOD" "$W/damaged.char"
damage() {   # <exact line> <replacement>
    grep -qxF -- "$1" "$W/damaged.char" || { echo "INCONCLUSIVE: no line \"$1\" in $GOOD"; exit 2; }
    python3 - "$W/damaged.char" "$1" "$2" <<'PY'
import sys
p, old, new = sys.argv[1:4]
lines = open(p).read().split("\n")
lines[lines.index(old)] = new
open(p, "w").write("\n".join(lines))
PY
}
damage "hp_roll [Barbarian]: 12" "hp_roll [Barbarian]: 3"
damage "perk_feat [0]: Light Sleeper" "perk_feat [0]: Larcenous"
damage "feat: Alertness" "feat: Endurance"
damage "skill_ranks [Climb]: 2" "skill_ranks [Climb]: 1"
damage "skill_ranks [Jump]: 0" "skill_ranks [Jump]: 1"
damage "kit_item [Orc;a1]: strip of cured meat, quantity 11" "kit_item [Orc;a1]: strip of cured meat, quantity 5"
damage "thrown_quantity: 7" "thrown_quantity: 4"
dump_build "$W/damaged.char" damaged

fail=0
if tools/canon_compare.py "$W/good.canon" "$W/damaged.canon" > /dev/null 2>&1; then
    echo "INCONCLUSIVE: the damaged copy builds the same character, so the damage proves nothing"; exit 2
fi
echo "ok   the damaged copy builds a different character"

convert() {   # <tag> [--withhold <key>]: converts the damaged copy, builds, dumps
    local tag="$1"; shift
    tools/char_convert_map.py convert "$W/old.canon" "$W/damaged.canon" "$W/damaged.char" "$W/$tag.char" "$@" > "$W/$tag.log" 2>&1 \
        || { echo "FAIL $tag: the conversion stopped: $(tail -1 "$W/$tag.log" | cut -c1-300)"; fail=1; return 1; }
    dump_build "$W/$tag.char" "$tag"
}
if convert all; then
    if tools/canon_compare.py --all "$W/good.canon" "$W/all.canon" > "$W/all.diff" 2>&1; then
        echo "ok   the converted file builds the hand-written character ($(grep -c '^set ' "$W/all.log") values set)"
    else
        echo "FAIL the converted file builds another character:"; grep -E '^[-+][^-+]' "$W/all.diff" | head -8 | cut -c1-160; fail=1
    fi
fi

# Control: each key withheld leaves a difference.
for key in hp_roll perk_feat feat skill_ranks kit_item thrown_quantity; do
    if ! convert "w-$key" --withhold "$key"; then continue; fi
    if tools/canon_compare.py "$W/good.canon" "$W/w-$key.canon" > "$W/w-$key.diff" 2>&1; then
        echo "FAIL withholding $key left no difference: the table or the comparison cannot fail on it"; fail=1
    else
        echo "ok   withholding $key shows: $(grep -m1 -E '^[-+][^-+]' "$W/w-$key.diff" | cut -c1-110)"
    fi
done

# Arrival replay (phases 11e and 11g).
conv() {   # <tag> <fixture> [tool]: converts with the real tool or a mutant; sets CRC and COUT
    local tag="$1" fx="$2" tool="${3:-tools/char_convert.sh}"
    TAG="$tag"
    CHAR_CONVERT_LOGS="${W#$ROOT/}/$tag" "$tool" "$fx" "$W/$tag.char" > "$W/$tag.out" 2>&1
    CRC=$?
    COUT="$W/$tag.out"
}
mutant() {   # <script> <sed expression> <tag>: a copy of a tool with one change, under $W (removed on exit); its path in MUTPATH
    mkdir -p "$W/mut"
    MUTPATH="$W/mut/$3.sh"
    sed "$2" "tools/$1" > "$W/mut/$3.tmp"
    if cmp -s "tools/$1" "$W/mut/$3.tmp"; then
        echo "INCONCLUSIVE: the mutation of $1 ($2) changed nothing"; rm -f "$W/mut/$3.tmp"; exit 2
    fi
    sed "s|^ROOT=.*\$|ROOT=\"$ROOT\"|" "$W/mut/$3.tmp" > "$MUTPATH"   # a copy outside tools/ names the real root
    rm -f "$W/mut/$3.tmp"
    chmod +x "$MUTPATH"
}
want_red() {   # <label> <fixture>: the mutant run (COUT, CRC) must stop at the proof, red
    if [ "$CRC" -eq 2 ] && grep -q "METHOD DEFECT" "$COUT" && ! grep -q "method proof: the replay" "$COUT"; then
        echo "ok   $1: the proof goes red on $2 ($(grep -m1 -E '^[-+][^-+]' "$COUT" | cut -c1-70))"
    else
        echo "FAIL $1: the proof did not go red on $2 (exit $CRC): $(tail -1 "$COUT" | cut -c1-200)"; fail=1
    fi
}
want_green() {   # <fixture>: the real tool prints the proof line
    if grep -q "method proof: the replay of the skeleton equals the walk's final save" "$COUT"; then
        echo "ok   the arrival replay of the skeleton equals the walk's own final save ($1)"
    else
        echo "FAIL the method proof did not pass for $1: $(grep -m1 -E 'METHOD DEFECT|cannot|char_arrive:' "$COUT" | cut -c1-200)"; fail=1
    fi
}
RG=orc-rogue-seed1-opt0822; GN=gnome-warrior-wis3-pickaxe-seed1-opt0822; RT=orc-rogue-seed4-opt0822
conv rg "$RG";  want_green "$RG"
conv gn "$GN";  want_green "$GN"
conv rt "$RT";  want_green "$RT"

mutant char_arrive.sh 's|if \[ "\$SKIP" != "-" \]; then|if false; then|' char_arrive_mutant
CHAR_ARRIVE_TOOL="$MUTPATH" conv rg-norep "$RG"; rm -f "$MUTPATH"
want_red "no replay at all" "$RG"

mutant char_arrive.sh 's|INCURSION_KEYS_SKIP="\$SKIP" ||' char_arrive_mutant
CHAR_ARRIVE_TOOL="$MUTPATH" conv rg-noskip "$RG"; rm -f "$MUTPATH"
if [ "$CRC" -eq 2 ] && ! grep -q "method proof: the replay" "$COUT"; then
    echo "ok   without the split the whole script is replayed and the run stops (exit 2)"
else
    echo "FAIL the no-split mutant was not stopped (exit $CRC): $(tail -1 "$COUT" | cut -c1-200)"; fail=1
fi

mutant char_convert.sh 's|"\$KEYPOS" "\$TICK"|"$((KEYPOS+1))" "$TICK"|' char_convert_mutant
conv gn-p1 "$GN" "$MUTPATH"; rm -f "$MUTPATH"
want_red "split point + 1" "$GN"
mutant char_convert.sh 's|"\$KEYPOS" "\$TICK"|"$((KEYPOS-1))" "$TICK"|' char_convert_mutant
conv gn-m1 "$GN" "$MUTPATH"; rm -f "$MUTPATH"
want_red "split point - 1" "$GN"

mutant char_convert.sh 's|"\$KEYPOS" "\$TICK"|"$KEYPOS" "$((TICK+1))"|' char_convert_mutant
conv rt-t1 "$RT" "$MUTPATH"; rm -f "$MUTPATH"
want_red "seed tick + 1" "$RT"

# The map (phase 11h): the build stands where the walk stood before it made the map, so the proof also holds
# Position and Map. Green on a fixture; red when the restore is removed (the mutant passes `-` for the stream).
HP=hunger-penalty-seed1-opt0822
conv hp "$HP"; want_green "$HP"
if [ -s "$W/hp/$HP/skeleton.walk.stream" ] && [ ! -s "$W/hp/$HP/proof-location.txt" ] \
        && [ "$(grep -h '^Position' "$W/hp/$HP/built0.canon")" = "$(grep -h '^Position' "$W/hp/$HP/walkfinal.canon")" ]; then
    echo "ok   the replay stands where the walk stood ($(grep -h '^Position' "$W/hp/$HP/built0.canon")) on the walk's map (stream $(cat "$W/hp/$HP/skeleton.walk.stream"))"
else
    echo "FAIL the replay of $HP does not stand where the walk stood"; fail=1
fi
mutant char_convert.sh 's|"\$KEYPOS" "\$TICK" "\$STREAM" 2>|"$KEYPOS" "$TICK" - 2>|' char_convert_mutant
conv hp-nostream "$HP" "$MUTPATH"; rm -f "$MUTPATH"
want_red "no map stream restore" "$HP"
if grep -q "^[-+]Position" "$COUT"; then
    echo "ok   the red proof names Position ($(grep -m1 '^[-+]Position' "$COUT"))"
else
    echo "FAIL the proof without the restore did not go red on Position"; fail=1
fi

# F5 (phase 11h): random(mx) with a negative mx. The engine's own inline random() is compiled with a stub generator;
# the range the recorder states (src/VMachine.cpp ScriptRandom) MUST contain every value it gives.
cat > "$W/rnd.cpp" <<EOF
#include <cstdio>
typedef short int16;
unsigned long genrand_int32(void) { static unsigned long x = 123456789UL; x = x * 6364136223846793005UL + 1442695040888963407UL; return (x >> 20) & 0xffffffffUL; }
$(sed -n '/^inline int16 random(int16 mx)/,/^  }/p' inc/Inline.h)
int main() { int lo = 0, hi = 0; for (int i = 0; i < 400000; i++) { int v = random(-5); if (v < lo) lo = v; if (v > hi) hi = v; } printf("%d %d\n", lo, hi); }
EOF
c++ -o "$W/rnd" "$W/rnd.cpp" 2> "$W/rnd.err" || { echo "INCONCLUSIVE: cannot compile the random() probe: $(head -2 "$W/rnd.err")"; exit 2; }
read -r OBSLO OBSHI < <("$W/rnd")
rng_ok() {   # <VMachine.cpp copy>: the stated range for a negative mx holds the observed values
    python3 - "$1" "$OBSLO" "$OBSHI" <<'PY'
import re, sys
t = open(sys.argv[1]).read()
lo = re.search(r"int32 lo = mx < 0 \? (-?\d+) : 0;", t)
hi = re.search(r"int32 hi = mx < 0 \? (-?\d+) :", t)
sys.exit(0 if lo and hi and int(lo.group(1)) <= int(sys.argv[2]) and int(hi.group(1)) >= int(sys.argv[3]) else 1)
PY
}
sed 's|int32 lo = mx < 0 ? -32768 : 0;|int32 lo = mx < 0 ? -4 : 0;|; s|int32 hi = mx < 0 ? 32767 :|int32 hi = mx < 0 ? 0 :|' src/VMachine.cpp > "$W/VMachine.mut.cpp"
if rng_ok src/VMachine.cpp && ! rng_ok "$W/VMachine.mut.cpp" && [ "$OBSLO" -lt -4 ]; then
    echo "ok   random(-5) gives $OBSLO..$OBSHI; the recorder states a range that holds it (a copy stating -4..0 does not)"
else
    echo "FAIL the range for a negative random() does not hold the values it gives ($OBSLO..$OBSHI)"; fail=1
fi

# Third part (phase 11g).
SKIPOUT="$(INCURSION_KEYS_SKIP=abc INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat INCURSION_RUN_DIR="$W/skiprun" tools/headless.sh tools/keys/dive.keys 1 2>&1 < /dev/null)"
SRC_RC=$?
if [ "$SRC_RC" -ne 0 ] && grep -q "INCURSION_KEYS_SKIP=abc: not a number" <<< "$SKIPOUT"; then
    echo "ok   INCURSION_KEYS_SKIP=abc is refused, not read as 0 (exit $SRC_RC)"
else
    echo "FAIL INCURSION_KEYS_SKIP=abc was not refused (exit $SRC_RC): $(printf '%s' "$SKIPOUT" | tail -1 | cut -c1-160)"; fail=1
fi

# A settings choice that fails is exit 2 with the reason, not exit 1 with nothing (phase 11g).
mutant char_convert.sh 's|options "\$OD/old.canon"|options /dev/null|' char_convert_mutant
conv rg-opt "$RG" "$MUTPATH"; rm -f "$MUTPATH"
if [ "$CRC" -eq 2 ] && grep -q "cannot choose the settings.*has no Options line" "$COUT"; then
    echo "ok   a failed settings choice exits 2 and gives the reason ($(grep -m1 'cannot choose' "$COUT" | cut -c1-120))"
else
    echo "FAIL a failed settings choice did not exit 2 with its reason (exit $CRC): $(tail -1 "$COUT" | cut -c1-200)"; fail=1
fi

CR="$W/ccroot"; mkdir -p "$CR/tools" "$CR/src" "$CR/inc"
cp tools/canon_compare.py "$CR/tools/"; cp inc/Defines.h "$CR/inc/"
FORCED="$(grep -o 'bytes\[OPT_[A-Z_0-9]*\]' src/CharFile.cpp | head -1 | sed 's/bytes\[\(.*\)\]/\1/')"
OTHERS=($(grep -o '^#define OPT_[A-Z_0-9]*' inc/Defines.h | sed 's/#define //' | grep -vx "$FORCED" | head -2))
[ "${#OTHERS[@]}" -eq 2 ] || { echo "INCONCLUSIVE: inc/Defines.h names fewer than two other options"; exit 2; }
{ echo "/* old: bytes[${OTHERS[0]}] = 0; */"; echo "// bytes[${OTHERS[1]}] = 0;"; cat src/CharFile.cpp; } > "$CR/src/CharFile.cpp"
NF="$(python3 "$CR/tools/canon_compare.py" --list | grep -c 'the build forces')"
NC="$(grep -c 'bytes\[OPT_[A-Z_]*\] *= *[0-9]* *;' src/CharFile.cpp)"
sed 's/code_only(code)/code/' tools/canon_compare.py > "$CR/tools/canon_compare_mut.py"
NM="$(python3 "$CR/tools/canon_compare_mut.py" --list 2>/dev/null | grep -c 'the build forces')"
if [ "$NF" -eq "$NC" ] && [ "$NM" -gt "$NC" ]; then
    echo "ok   canon_compare lists the $NF option(s) the code forces and not the two named in comments (a copy that reads the comments lists $NM)"
else
    echo "FAIL canon_compare lists $NF forcing line(s) with two comment lines in front of the code (the code has $NC; a copy reading comments lists $NM)"; fail=1
fi

# Fifth part (phase 11h): the roll search's match rule and the map-independent pieces of the unset report.
# A single completed combination is not a match, a build that added an unseen key's line with a default is "not searched",
# no match keeps the walk's values, and the difference is a multiset. The copy with the one-combination rule loosened MUST fail.
if tools/char_roll_search.py selftest > "$W/rsself.out" 2>&1; then
    echo "ok   char_roll_search.py selftest: $(grep -c '^ok' "$W/rsself.out") cases (one combination is no match, an unseen default is not searched, the difference is a multiset)"
else
    grep FAIL "$W/rsself.out" | head -3 | cut -c1-200; echo "FAIL char_roll_search.py selftest"; fail=1
fi
mkdir -p "$W/mut"
sed "s|^HERE = .*|HERE = \"$ROOT/tools\"|; s|if len(done) < 2:|if len(done) < 1:|" tools/char_roll_search.py > "$W/mut/char_roll_search_mut.py"
if cmp -s tools/char_roll_search.py "$W/mut/char_roll_search_mut.py"; then echo "INCONCLUSIVE: the roll search mutation changed nothing"; exit 2; fi
if python3 "$W/mut/char_roll_search_mut.py" selftest > "$W/rsmut.out" 2>&1; then
    echo "FAIL the roll search selftest passes with the one-combination rule loosened: it cannot fail on it"; fail=1
else
    echo "ok   with the one-combination rule loosened the selftest goes red ($(grep -m1 FAIL "$W/rsmut.out" | cut -c1-90))"
fi

# Fourth part (phase 11g): perk charges follow their item's context, and merged stacks keep their sources.
if tools/char_convert_map.py selftest > "$W/selftest.out" 2>&1; then
    echo "ok   char_convert_map.py selftest: $(grep -c '^ok' "$W/selftest.out") cases (perk charges by context, gold, food and potion stacks, a stack of two asks)"
else
    grep FAIL "$W/selftest.out" | head -3 | cut -c1-200; echo "FAIL char_convert_map.py selftest"; fail=1
fi

# Sixth part (phase 12a).
cp "$W/old.canon" "$W/p1.canon"
python3 - "$W/p1.canon" <<'PY' || { echo "INCONCLUSIVE: no Defense Class or Fortitude line to edit in the dump"; exit 2; }
import re, sys
p = sys.argv[1]
t = open(p).read()
t2 = re.sub(r"^(Fortitude +)\+(\d+)", lambda m: "%s+%d" % (m.group(1), int(m.group(2)) + 3), t, count=1, flags=re.M)
if t2 == t: sys.exit(1)
open(p, "w").write(t2)
PY
tools/canon_compare.py --choices-diff "$W/old.canon" "$W/p1.canon" > "$W/p1.out" 2>&1
if [ $? -eq 0 ] && ! tools/canon_compare.py "$W/old.canon" "$W/p1.canon" > /dev/null 2>&1; then
    echo "ok   a changed computed line (Fortitude) differs in the full comparison and passes the choices comparison"
else
    echo "FAIL a changed computed line must pass the choices comparison and still differ in the full one"; cat "$W/p1.out" | head -3; fail=1
fi
cp "$W/old.canon" "$W/p2.canon"
python3 - "$W/p2.canon" <<'PY' || { echo "INCONCLUSIVE: no feat line to edit in the dump"; exit 2; }
import sys
p = sys.argv[1]
L = open(p).read().split("\n")
i = L.index("Feats:") + 1
L[i] = "  Zzz Changed Feat"
open(p, "w").write("\n".join(L))
PY
tools/canon_compare.py --choices-diff "$W/old.canon" "$W/p2.canon" > "$W/p2.out" 2>&1
if [ $? -eq 1 ] && grep -q '^+ Feats: Zzz Changed Feat' "$W/p2.out"; then
    echo "ok   a changed feat fails the choices comparison and the line is named: $(grep -m1 '^+ Feats' "$W/p2.out")"
else
    echo "FAIL a changed choice line must make --choices-diff exit 1 and name the line"; head -3 "$W/p2.out"; fail=1
fi
printf -- '- Inventory: 10 Potions of Cure Disease [0]\n+ Inventory: 7 Potions of Cure Disease [0]\n' > "$W/potion.diff"
tools/char_convert_map.py excuse "$W/potion.diff" > "$W/potion.out" 2>&1
if [ $? -eq 1 ] && grep -q '^remainder: - Inventory: 10 Potions of Cure Disease' "$W/potion.out" && ! grep -q '^excused' "$W/potion.out"; then
    echo "ok   the table does not excuse 10 -> 7 Potions of Cure Disease"
else
    echo "FAIL the table excused a potion stack"; cat "$W/potion.out" | head -3; fail=1
fi
printf -- '- Inventory: 5 tanglefoot bags\n+ Inventory: tanglefoot bag\n' > "$W/bags.diff"
if tools/char_convert_map.py excuse "$W/bags.diff" > "$W/bags.out" 2>&1 && grep -q '^excused: .*bead inc-tjvn' "$W/bags.out"; then
    echo "ok   the table excuses 5 tanglefoot bags -> tanglefoot bag, naming bead inc-tjvn"
else
    echo "FAIL the table did not excuse the named kit stack"; head -3 "$W/bags.out"; fail=1
fi
if python3 - <<'PY'
import importlib.util, re, sys
spec = importlib.util.spec_from_file_location("ccm", "tools/char_convert_map.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
bad = [n for pair in m.KIT_DEDUPE_ITEMS for n in pair if re.search(r"potion|scroll|food|gold|arrow|bolt|ration|meat", n, re.I)]
sys.exit(1 if bad or not m.KIT_DEDUPE_ITEMS else 0)
PY
then
    echo "ok   no name in the kit-dedupe row is a dedupe-exempt kind (potion, scroll, food, gold, arrow, bolt)"
else
    echo "FAIL the kit-dedupe row names a dedupe-exempt kind"; fail=1
fi
tools/char_convert_map.py causes > "$W/causes.out" 2>&1
RCCAUSE=$?
if [ "$RCCAUSE" -eq 0 ]; then
    echo "ok   every KNOWN_DIFFERENCES row's cause is live"
else
    echo "FAIL KNOWN_DIFFERENCES: $(head -2 "$W/causes.out" | tr '\n' ' ' | cut -c1-300)"; fail=1
fi
cat > "$W/stale.jsonl" <<'JL'
{"id":"inc-tjvn","status":"closed"}
JL
CHAR_CONVERT_BEADS="$W/stale.jsonl" tools/char_convert_map.py causes > "$W/stale.out" 2>&1
if [ $? -eq 1 ] && grep -q 'stale and must be deleted' "$W/stale.out"; then
    echo "ok   a row whose bead is closed makes the cause check fail with a stale-row message"
else
    echo "FAIL the cause check did not fail on a closed bead"; fail=1
fi

[ $fail -eq 0 ] && { echo "PASS: the table restores every kind of decision it converts, and each withheld key shows"; exit 0; }
exit 1
