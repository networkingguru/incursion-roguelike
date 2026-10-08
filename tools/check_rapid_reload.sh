#!/bin/bash
# gate: live
# Rapid Reload must make cranking a crossbow FASTER, not slower. (inc-l59x)
#
# THE DEFECT. Creature::LoadCrossbow (src/Item.cpp) has its two branch bodies
# swapped. With FT_RAPID_RELOAD the character is charged `Timeout += 30` and
# provokes an attack of opportunity; without it, `Timeout += 10` and no
# provocation. The feat text (src/FeatTab.cpp:1154) and the game's own time
# table (lib/help.irh, "Reload a Crossbow ... 30 segments / with Rapid
# Reload ... 10 segments") say the reverse. So the feat that promises a
# quicker reload is the one that takes longer.
#
# THE MEASUREMENT is the game's turn counter, stamped into every screen dump
# header (src/Wposix.cpp, posixTerm::DumpScreen). Two frozen characters each
# crank an uncocked arbalest once between two dumps; the turns that pass
# between the `wielded` and `reloaded` dumps are the crank's Timeout, because
# nothing else between the dump and the next key-read can advance the clock.
#
#   tools/keys/rapid-reload-feat.keys     the Bard with FT_RAPID_RELOAD
#   tools/keys/rapid-reload-no-feat.keys  the Warrior without it
#
# The check passes only when the no-feat crank takes STRICTLY longer than the
# feat crank. On the swapped code they are 30 and 10 and the comparison is
# backwards, so the check fails. It fails too -- never passes -- when either
# run produces no `wielded`/`reloaded` dump pair or an unparsable turn stamp,
# so it cannot pass by never reaching the crank.
#
# Usage: tools/check_rapid_reload.sh   (0 pass, 1 fail, 2 could not measure)
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OPTS=tools/fixtures/options-2026-08-22.dat
FEAT_KEY=tools/keys/rapid-reload-feat.keys
NOFEAT_KEY=tools/keys/rapid-reload-no-feat.keys
FEAT_LOAD=tools/fixtures/chars/prestige-geomancy-seed1-opt0822.sav
NOFEAT_LOAD=tools/fixtures/chars/spook-ally-seed5-opt0822.sav
SEED=1

BIN="${INCURSION_BIN:-./incursion-headless}"
[ -x "$BIN" ] || {
    echo "FAIL: $BIN is missing; build it with BACKEND=posix ./build_macos.sh"
    exit 2
}

STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$ROOT/logs/rapid-reload/$STAMP"
mkdir -p "$OUT"

# run_session <tag> <load> <keys> <run-dir>
# Every session names its own unique run directory under logs/ and the shared
# settings file, as the brief requires.
run_session() {
    local tag="$1" load="$2" keys="$3" run="$4"
    INCURSION_OPTIONS="$OPTS" INCURSION_LOAD="$load" INCURSION_RUN_DIR="$run" \
        tools/headless.sh "$keys" "$SEED" > "$OUT/$tag.out" 2>&1
    local rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "FAIL: the $tag session exited $rc; see $OUT/$tag.out" >&2
        tail -5 "$OUT/$tag.out" >&2
        return 1
    fi
    return 0
}

# crank_turns <run-dir> -> prints "wielded_turn reloaded_turn delta"
# Reads the turn stamp out of the two named dumps. A missing dump or an
# unparsable stamp is a hard measurement failure, not a pass.
crank_turns() {
    local run="$1" w r wt rt
    w="$(ls "$run/logs/screens/"*-wielded.txt 2>/dev/null | head -1)"
    r="$(ls "$run/logs/screens/"*-reloaded.txt 2>/dev/null | head -1)"
    [ -n "$w" ] && [ -n "$r" ] || return 1
    wt="$(sed -n '1s/.*turn \([0-9]*\).*/\1/p' "$w")"
    rt="$(sed -n '1s/.*turn \([0-9]*\).*/\1/p' "$r")"
    [ -n "$wt" ] && [ -n "$rt" ] || return 1
    printf '%s %s %s\n' "$wt" "$rt" "$((rt - wt))"
}

echo "run 1/2: WITH Rapid Reload  ($FEAT_LOAD)"
run_session feat "$FEAT_LOAD" "$FEAT_KEY" "$OUT/feat" || exit 1
echo "run 2/2: WITHOUT Rapid Reload  ($NOFEAT_LOAD)"
run_session nofeat "$NOFEAT_LOAD" "$NOFEAT_KEY" "$OUT/nofeat" || exit 1

FEAT="$(crank_turns "$OUT/feat")" || {
    echo "FAIL: the WITH-feat run wrote no wielded/reloaded dump pair with a"
    echo "      turn stamp; nothing was measured. dumps:"
    ls "$OUT/feat/logs/screens/" 2>/dev/null | sed 's/^/        /'
    exit 1
}
NOFEAT="$(crank_turns "$OUT/nofeat")" || {
    echo "FAIL: the WITHOUT-feat run wrote no wielded/reloaded dump pair with a"
    echo "      turn stamp; nothing was measured. dumps:"
    ls "$OUT/nofeat/logs/screens/" 2>/dev/null | sed 's/^/        /'
    exit 1
}

F_W="$(printf '%s\n' "$FEAT" | cut -d' ' -f1)"
F_R="$(printf '%s\n' "$FEAT" | cut -d' ' -f2)"
F_D="$(printf '%s\n' "$FEAT" | cut -d' ' -f3)"
N_W="$(printf '%s\n' "$NOFEAT" | cut -d' ' -f1)"
N_R="$(printf '%s\n' "$NOFEAT" | cut -d' ' -f2)"
N_D="$(printf '%s\n' "$NOFEAT" | cut -d' ' -f3)"

echo "with Rapid Reload:     wielded turn $F_W -> reloaded turn $F_R = $F_D turns"
echo "without Rapid Reload:  wielded turn $N_W -> reloaded turn $N_R = $N_D turns"
echo "specimen run dir: $OUT"

if [ "$N_D" -gt "$F_D" ]; then
    echo "PASS: cranking without Rapid Reload takes longer ($N_D > $F_D)"
    exit 0
fi
echo "FAIL: Rapid Reload does not make cranking faster (inc-l59x):"
echo "      without the feat $N_D turns, with the feat $F_D turns."
echo "      Creature::LoadCrossbow (src/Item.cpp) has its branches swapped."
exit 1
