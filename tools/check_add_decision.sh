#!/usr/bin/env bash
# gate: live
#
# Does the documented way to add a decision work on the tool side? Spec B18
# (bead inc-10v7f, phase 13): "wrap the draw or prompt in a primitive with a new
# enum name and a default; run tools/fill_chars.sh; commit both"
# (tools/fixtures/README.md, "Adding a decision").
#
# WHAT IS BEING PROVED. The C++ half of the procedure (a new enum name and a
# default in the key table) needs a rebuilt binary, which this check does not
# do. It proves the half that touches the fixtures. A key every .char states
# plays the part of the new decision: a scratch copy of every .char loses all
# the lines of that key, which is what a .char set looks like to a binary that
# has just learned a new key. Then:
#   1. every scratch file fails to build and the failure names the missing
#      line ("missing line in <file>; add: <line>"): the build, not a person,
#      says what the files lack;
#   2. tools/fill_chars.sh on the scratch directory exits 0, and every file
#      builds afterwards, each with as many lines of the key as the original;
#   3. the whole of 1 and 2 holds for a second key too, and neither tool names
#      a key, so there is no per-key branch (B18).
# MUTATION (the check must go red when the procedure is broken): after the
# fill, one .char loses the key's lines again, as if the author had run the
# fill on some files only. The build of the set MUST then fail for exactly that
# file, and the check MUST exit 1 if the build of the set passes.
# The work is on copies under logs/. No tracked file is written.
#
# SIZE. Each build takes about a second, and a full run over all 50 files took
# 28 minutes (measured 2026-11-12). So the check uses every fifth file, in
# name order, by default. ADD_DECISION_STEP=1 uses every file.
#
# fact: the characters -- every ADD_DECISION_STEP-th file of tools/fixtures/chars/*.char (every fifth by default, all of them with ADD_DECISION_STEP=1), committed; each is built from the file alone, no key script and no walk
# fact: the random stream -- the seed: line of each .char feeds the build; tools/build_fixture.sh removes every other INCURSION_* variable, and the check compares only whether a build passes and how many lines a file holds, so no drawn value is read
# fact: the options -- the options: line of each .char names a committed settings file, read by the build
# fact: the two keys that play the new decision -- read from the files at run time (keys every .char states, which the binary reports as missing when removed); this check holds no key name
# fact: the fill default -- the value the key table gives the key; the check never reads it, it counts lines
#
# Usage: INCURSION_BIN=./incursion-headless tools/check_add_decision.sh
# Exit: 0 pass; 1 fail; 2 could not run.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2
BIN="${INCURSION_BIN:-./incursion-headless}"
[ -x "$BIN" ] || { echo "INCONCLUSIVE: $BIN is not built"; exit 2; }
export INCURSION_BIN="$BIN"
SRC=tools/fixtures/chars
ls "$SRC"/*.char > /dev/null 2>&1 || { echo "INCONCLUSIVE: no .char under $SRC"; exit 2; }
STEP="${ADD_DECISION_STEP:-5}"
case "$STEP" in ''|*[!0-9]*|0) echo "INCONCLUSIVE: ADD_DECISION_STEP must be a positive integer"; exit 2 ;; esac

mkdir -p logs
W="$(mktemp -d "$ROOT/logs/add-decision.XXXXXX")" || exit 2
trap 'rm -rf "$W"' EXIT
fails=0
FILES=()
i=0
for f in "$SRC"/*.char; do
    [ $((i % STEP)) -eq 0 ] && FILES+=("$f")
    i=$((i + 1))
done
ok()  { echo "ok   $*"; }
bad() { echo "FAIL $*"; fails=1; }

keys_of() {   # <file>: the key of every decision line, one per line
    sed -E -n 's/^([A-Za-z0-9_]+)([[:space:]]*\[[^]]*\])?:.*/\1/p' "$1" | sort -u
}
strip_key() {   # <key> <in> <out>: the file without any line of the key
    awk -v k="$1" '{ name = $0; sub(/[[:space:]]*(\[[^]]*\])?:.*$/, "", name);
                     if (name == k && $0 ~ /^[A-Za-z0-9_]+[[:space:]]*(\[[^]]*\])?:/) next; print }' "$2" > "$3"
}
count_key() {   # <key> <file>
    awk -v k="$1" '{ name = $0; sub(/[[:space:]]*(\[[^]]*\])?:.*$/, "", name);
                     if (name == k && $0 ~ /^[A-Za-z0-9_]+[[:space:]]*(\[[^]]*\])?:/) n++ } END { print n + 0 }' "$2"
}
build_set() {   # <dir>: builds every .char; prints "FAIL <name>" per failure; returns the failure count
    local d="$1" f n c=0
    for f in "$d"/*.char; do
        n="$(basename "$f" .char)"
        if ! tools/build_fixture.sh "$f" "$W/out-$n" > "$W/$n.build" 2> "$W/$n.err" < /dev/null; then
            echo "FAIL $n"; c=$((c + 1))
        fi
        rm -rf "$W/out-$n"
    done
    return "$c"
}

# The keys every .char states.
ALL="$W/keys.all"
first=1
for f in "${FILES[@]}"; do
    if [ "$first" -eq 1 ]; then keys_of "$f" > "$ALL"; first=0
    else keys_of "$f" > "$W/keys.one"; comm -12 "$ALL" "$W/keys.one" > "$W/keys.next"; mv -f "$W/keys.next" "$ALL"; fi
done
[ -s "$ALL" ] || { echo "INCONCLUSIVE: the .char files share no decision key"; exit 2; }

# The two that play the new decision: the first and the last of the shared keys
# that the binary reports as a missing line when a file loses them. One small
# file is the probe.
PROBE="$(ls -S "$SRC"/*.char | tail -1)"
GOOD=()
while IFS= read -r k; do
    strip_key "$k" "$PROBE" "$W/probe.char"
    [ "$(count_key "$k" "$PROBE")" -gt 0 ] || continue
    if ! tools/build_fixture.sh "$W/probe.char" "$W/probe-out" > /dev/null 2> "$W/probe.err" < /dev/null \
       && grep -q "^BUILD FAILED: missing line in .*; add: " "$W/probe.err"; then
        GOOD+=("$k")
    fi
    rm -rf "$W/probe-out"
done < "$ALL"
[ "${#GOOD[@]}" -ge 2 ] || { echo "INCONCLUSIVE: fewer than two shared keys are reported as a missing line when removed"; exit 2; }
KEYS=("${GOOD[0]}" "${GOOD[$((${#GOOD[@]} - 1))]}")
echo "keys that play the new decision: ${KEYS[0]} and ${KEYS[1]} (of ${#GOOD[@]} candidates)"

N=0
for k in "${KEYS[@]}"; do
    S="$W/set-$k"
    mkdir -p "$S"
    for f in "${FILES[@]}"; do strip_key "$k" "$f" "$S/$(basename "$f")"; done
    N=$(ls "$S"/*.char | wc -l | tr -d ' ')

    # 1. Every file fails, and the failure names the missing line.
    build_set "$S" > "$W/before.txt"; before=$?
    named=0
    for f in "$S"/*.char; do
        n="$(basename "$f" .char)"
        grep -q "^BUILD FAILED: missing line in .*; add: ${k}[ :]" "$W/$n.err" && named=$((named + 1))
    done
    if [ "$before" -eq "$N" ] && [ "$named" -eq "$N" ]; then ok "[$k] $N of $N files fail to build and each failure names a missing $k line"
    else bad "[$k] $before of $N files failed and $named named a missing $k line; the key does not play a new decision"; continue; fi

    # 2. The fill makes every file build, with as many lines of the key as before.
    if ! tools/fill_chars.sh "$S" > "$W/fill.out" 2>&1; then
        bad "[$k] tools/fill_chars.sh failed: $(tail -2 "$W/fill.out" | tr '\n' ' ')"; continue
    fi
    build_set "$S" > "$W/after.txt"; after=$?
    short=0
    for f in "${FILES[@]}"; do
        n="$(basename "$f")"
        [ "$(count_key "$k" "$S/$n")" -ge "$(count_key "$k" "$f")" ] || short=$((short + 1))
    done
    if [ "$after" -eq 0 ] && [ "$short" -eq 0 ]; then ok "[$k] after tools/fill_chars.sh all $N files build and hold every $k line the original held"
    else bad "[$k] after the fill $after files fail to build and $short hold fewer $k lines than the original: $(head -3 "$W/after.txt" | tr '\n' ' ')"; continue; fi

    # 3. Neither tool names the key.
    if grep -qw -- "$k" tools/fill_chars.sh tools/char_rekey.sh; then bad "[$k] a tool names the key: a per-key branch (B18)"
    else ok "[$k] neither tools/fill_chars.sh nor tools/char_rekey.sh names the key"; fi

    # Mutation: one file loses the key again; the set build MUST go red for exactly that file.
    if [ "$k" = "${KEYS[0]}" ]; then
        V="$(ls "$S"/*.char | head -1)"
        VN="$(basename "$V" .char)"
        strip_key "$k" "$V" "$W/mut.char"; cp -f "$W/mut.char" "$V"
        build_set "$S" > "$W/mut.txt"; mut=$?
        if [ "$mut" -eq 1 ] && [ "$(cat "$W/mut.txt")" = "FAIL $VN" ]; then ok "[$k] MUTATION: a .char missing the filled key turns the set build red, for $VN only"
        else bad "[$k] MUTATION NOT DETECTED: the build of a set with one unfilled .char reported $mut failures ($(tr '\n' ' ' < "$W/mut.txt"))"; fi
    fi
done

# The README states the procedure.
for t in "tools/fill_chars.sh" "tools/char_rekey.sh" "Adding a decision"; do
    grep -qF -- "$t" tools/fixtures/README.md && ok "tools/fixtures/README.md names $t" || bad "tools/fixtures/README.md does not name $t"
done

if [ "$fails" -eq 0 ]; then echo "PASS: a decision added by the documented procedure fills into every .char and every build passes"; exit 0; fi
exit 1
