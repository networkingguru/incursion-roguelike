#!/bin/bash
# gate: live
# Does every place that asks "does this damage type take hit points?" still
# answer the same, for every damage type? (bd inc-kx693)
#
# WHAT IT DEFENDS. The sixteen places that ask "does this damage type take hit
# points?" call DTypeTakesHP() (the DTypeHP[] table, src/Tables.cpp): six in
# src/Fight.cpp, four effect slots in Creature::SpellDmgBonus (src/Magic.cpp),
# six script handlers (lib/mon3.irh x2, lib/mon4.irh, lib/pspells.irh x2,
# lib/wspells.irh). The frozen log was written by the build before inc-kx693
# replaced the old `<= 13` number line, so a PASS means every site still answers
# as it did then.
#
# CHANGING AN ANSWER ON PURPOSE. When a bead changes a row of DTypeHP[] on
# purpose (for example setting AD_LAWF to yes), the Spell Fury lines for that
# type change (bonus=4 becomes bonus=8) and this check fails. That bead MUST
# re-freeze with `tools/check_damage_class.sh --freeze` on its own build, check
# that ONLY the lines for the changed type moved (`git diff
# tools/fixtures/damage-class.expected`), and name the change in its commit
# body. When a bead ADDS a damage type, the 77-value manifest in probe_mode and
# the probe's Spell Fury list (src/DamageClassProbe.cpp) MUST both gain the new
# number, then re-freeze the same way.
#
# THE ORACLE. INCURSION_DAMAGE_CLASS_PROBE=1 makes src/DamageClassProbe.cpp
# stage sixteen cases at the start of Game::Play, call the REAL production method
# or script handler for each, read the result at the production site through
# read-only hooks (inc/DamageClassProbe.h), and write logs/damage-class.log:
# 332 `DC case=<id> type=<n> ...` lines (24 for the paired AD_BLUNT 13 / AD_STUK
# 14 cases, 308 for Spell Fury slots 0-3 over the 77 damage types) and an END
# line. This check compares that log byte for byte with the frozen file
# tools/fixtures/damage-class.expected, which was written by the build BEFORE the
# change. The probe holds no copy of the damage-class test.
#
# SAVE COMPARISON (--save). The change must not touch what a save holds. A
# probe-disabled session loads the frozen character, saves, and the engine's own
# character dump (logs/charprobe.txt, through the line before Inventory) is
# compared with tools/fixtures/damage-class-char.expected. The save that session
# wrote is then loaded by a second session and its dump compared again, and the
# fixture's sha256 is checked before and after.
#
# MODES
#   tools/check_damage_class.sh                 probe log against the frozen log
#   tools/check_damage_class.sh --save          write-then-reload save comparison
#   tools/check_damage_class.sh --save-reload <save>
#                                               load a save written by ANOTHER build
#                                               (for example logs/kx693-save/write-
#                                               before/Varag.sav) and compare its dump
#   tools/check_damage_class.sh --freeze        write the frozen log (probe mode) or
#                                               the frozen dump (--save); only on a build
#                                               whose answers are meant to be the new
#                                               truth (see CHANGING AN ANSWER ON PURPOSE)
#   DAMAGE_CLASS_SAVE_DIR=<dir>                 --save keeps both sessions' saves and
#                                               dumps under <dir>/write and <dir>/reload
# Settings for the binary: INCURSION_BIN (default ./incursion-headless). The
# module the run loads is the checkout's mod/Incursion.Mod; build the binary and
# the module together with BACKEND=posix ./build_macos.sh.
#
# fact: loaded character, race, class, attributes, inventory and map -- catalog fixture control: INCURSION_LOAD=tools/fixtures/chars/orc-barbarian-seed1-opt0822.sav
# fact: settings -- frozen INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat
# fact: the seed -- not read; the probe stages every input in process and rolls no die for an asserted value, and the harness seed only has to exist
# fact: clear lit floor, no fields, fixed actor placement, empty neighbouring cells -- probe-built arena in src/DamageClassProbe.cpp (DCCells), readback or SETUP_ERROR
# fact: exact resource identities, actor/target links, no generated gear -- in-process named-instance staging with readback in src/DamageClassProbe.cpp, no GrantGear
# fact: living participants, hit points, BreedCount, no multiplication blockers, child count only -- in-process staging in src/DamageClassProbe.cpp
# fact: feats, ability levels, CON/WIS/CHA modifiers, no armour, sapience, perception -- in-process grants and adjustments with readback in src/DamageClassProbe.cpp
# fact: god, flags, favour, anger, penalty, event eID and critical multiplier -- in-process deity staging with calcFavour readback in src/DamageClassProbe.cpp
# fact: illusion source, flags, real-to relation, victim FFCount -- in-process stati and event staging with readback in src/DamageClassProbe.cpp
# fact: four spell slots, exactly one EA_BLAST, damage type, arcane spell flags -- reversible in-memory Arrow Mind staging in src/DamageClassProbe.cpp
# fact: event phase, actor, target, map, damage inputs, event flags -- explicit EventInfo staging and handler-entry counters in src/DamageClassProbe.cpp
# fact: jovoc's neighbour fails its Fortitude save -- catalog INCURSION_FORCE_SAVE_ROLL=1, asserted in the probe
# fact: no attack roll or damage roll feeds an asserted value -- direct method and handler calls with explicit event amounts
# fact: no AI choice or percent-chance outcome feeds an asserted value -- synchronous staging before any turn
# fact: multiplication child positions and generated values -- not read; only counts and BreedCount
# fact: item quantity, full hit points, transformed link, animation hit points -- in-process item staging with readback in src/DamageClassProbe.cpp
# fact: return codes, damage deltas, call counts, state changes -- read-only hooks at the production methods and the VM entry
# fact: log text and order -- fixed case ids and counters; no names, handles, coordinates, times or random text
# fact: the damage-type domain -- frozen 77-value manifest, compared here with the AD_ defines in inc/Defines.h
# fact: saved character values -- fixture plus tools/keys/load-char-sheet.keys with INCURSION_CHAR_PROBE=1; transient lines (torch timers, messages, level statistics) are cut at the Inventory heading
#
# EXIT. 0 PASS, 1 FAIL (differing lines printed), 2 UNMEASURED (cannot run,
# SETUP_ERROR in the log, wrong line count, no gameplay).
#
# Usage: tools/check_damage_class.sh [--save | --save-reload <save>] [--freeze]

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

OPTS=tools/fixtures/options-2026-08-22.dat
FIX=tools/fixtures/chars/orc-barbarian-seed1-opt0822.sav
EXPECT=tools/fixtures/damage-class.expected
CHAR_EXPECT=tools/fixtures/damage-class-char.expected
BIN="${INCURSION_BIN:-./incursion-headless}"
SEED=1

MODE=probe; FREEZE=0; RELOAD_SAV=""
while [ $# -gt 0 ]; do
    case "$1" in
        --save) MODE=save ;;
        --save-reload) MODE=reload; shift; RELOAD_SAV="${1:-}" ;;
        --freeze) FREEZE=1 ;;
        *) echo "usage: tools/check_damage_class.sh [--save | --save-reload <save>] [--freeze]"; exit 2 ;;
    esac
    shift
done

unmeasured() { echo "UNMEASURED: $*"; exit 2; }
fail() { echo "FAIL: $*"; exit 1; }

for f in "$OPTS" "$FIX" tools/keys/damage-class.keys tools/keys/load-char-sheet.keys; do
    [ -f "$f" ] || unmeasured "missing $f"
done
[ -x "$BIN" ] || unmeasured "$BIN is not built (BACKEND=posix ./build_macos.sh)"
[ -f mod/Incursion.Mod ] || unmeasured "mod/Incursion.Mod is not built"

# One session through tools/headless.sh, in its own run directory.
# session <label> <keys> <load> [VAR=value ...]  -> sets RUN_DIR and SESSION_OUT
session() {
    local label="$1" keys="$2" load="$3"; shift 3
    local rundir="$ROOT/logs/runs/damage-class-$label-$(date +%Y%m%d-%H%M%S)-$$"
    local rc
    SESSION_OUT="$(env "$@" INCURSION_BIN="$BIN" INCURSION_OPTIONS="$OPTS" \
        INCURSION_LOAD="$load" INCURSION_RUN_DIR="$rundir" \
        tools/headless.sh "$keys" "$SEED" 2>&1 </dev/null)"
    rc=$?
    RUN_DIR="$rundir"
    case "$rc" in
        0|3) ;;
        1|4) fail "the game died (tools/headless.sh exit $rc); session in $rundir" ;;
        *)   if [ "$rc" -ge 128 ]; then fail "a signal killed the game (exit $rc); session in $rundir"; fi
             printf '%s\n' "$SESSION_OUT" | sed -n '/^--- after the session ---/,$p'
             unmeasured "the session ended badly (tools/headless.sh exit $rc); see $rundir" ;;
    esac
    [ -d "$rundir/logs" ] || unmeasured "no logs in $rundir"
}

# ------------------------------------------------------------------ probe mode
probe_mode() {
    # The damage-type domain: the AD_ defines must be exactly the frozen manifest.
    python3 -I - <<'PY' || unmeasured "the AD_ defines in inc/Defines.h differ from the frozen 77-value manifest; update the oracle explicitly"
import re, sys
want = set(range(0, 15)) | set(range(16, 31)) | set(range(32, 40)) | set(range(41, 75)) | set(range(90, 95))
got = set()
for l in open("inc/Defines.h", errors="replace"):
    m = re.match(r"#define\s+(AD_[A-Z0-9_]+)\s+(\d+)\b", l)
    if m:
        got.add(int(m.group(2)))
if len(want) != 77 or got != want:
    print("manifest %d values; defines give %d values; missing %s; extra %s" %
          (len(want), len(got), sorted(want - got), sorted(got - want)))
    sys.exit(1)
PY
    if [ "$FREEZE" -eq 0 ]; then
        [ -f "$EXPECT" ] || unmeasured "no frozen log $EXPECT"
    fi
    session probe tools/keys/damage-class.keys "$FIX" \
        INCURSION_DAMAGE_CLASS_PROBE=1 INCURSION_FORCE_SAVE_ROLL=1
    local log="$RUN_DIR/logs/damage-class.log"
    [ -s "$log" ] || unmeasured "no damage-class.log in $RUN_DIR: the probe did not run"
    if grep -q "NO GAMEPLAY" <<<"$SESSION_OUT"; then
        unmeasured "the session played no turn (NO GAMEPLAY); see $RUN_DIR"
    fi
    if grep -q '^SETUP_ERROR' "$log"; then
        grep '^SETUP_ERROR' "$log"
        unmeasured "the probe could not stage a case (SETUP_ERROR above); see $log"
    fi
    local n u
    n=$(grep -c '^DC case=' "$log")
    [ "$n" -eq 332 ] || unmeasured "$n DC lines, wanted 332; see $log"
    u=$(grep '^DC case=' "$log" | awk '{print $2, $3}' | sort | uniq -d | wc -l | tr -d ' ')
    [ "$u" -eq 0 ] || unmeasured "$u duplicated (case,type) pairs in $log"
    grep -qx 'END lines=332 errors=0' "$log" || unmeasured "no 'END lines=332 errors=0' line in $log"
    if [ "$FREEZE" -eq 1 ]; then
        cp -f "$log" "$EXPECT" || unmeasured "cannot write $EXPECT"
        echo "FROZEN: $EXPECT written from $log (332 DC lines)"
        exit 0
    fi
    if cmp -s "$log" "$EXPECT"; then
        echo "PASS: 332 DC lines identical to $EXPECT (session $RUN_DIR)"
        exit 0
    fi
    echo "FAIL: damage-class.log differs from $EXPECT (session $RUN_DIR); differing lines:"
    diff "$EXPECT" "$log" | head -60
    exit 1
}

# ------------------------------------------------------------------- save mode
# The character section: from the top of the dump through the line before
# "Inventory:" (the README names the lines after it as transient).
char_section() { # <charprobe.txt> -> stdout
    python3 -I - "$1" <<'PY'
import sys
out = []
for l in open(sys.argv[1], errors="replace").read().splitlines():
    if l.startswith("Inventory:"):
        break
    out.append(l)
else:
    sys.exit(3)
print("\n".join(out))
PY
}

dump_session() { # <label> <load> -> writes $WORK/<label>.txt
    local label="$1" load="$2"
    session "$label" tools/keys/load-char-sheet.keys "$load" INCURSION_CHAR_PROBE=1
    grep -q "NO GAMEPLAY" <<<"$SESSION_OUT" && unmeasured "$label: no gameplay"
    [ -s "$RUN_DIR/logs/charprobe.txt" ] || unmeasured "$label: no logs/charprobe.txt"
    char_section "$RUN_DIR/logs/charprobe.txt" > "$WORK/$label.txt" ||
        unmeasured "$label: no Inventory heading in charprobe.txt"
    [ -s "$WORK/$label.txt" ] || unmeasured "$label: empty character section"
    grep -q '^Gender' "$WORK/$label.txt" || unmeasured "$label: no Gender line"
    grep -q '^STR:' "$WORK/$label.txt" || unmeasured "$label: no attribute lines"
    [ -s "$RUN_DIR/save/Varag.sav" ] || unmeasured "$label: the session wrote no save/Varag.sav"
}

compare_expected() { # <label>
    if [ "$FREEZE" -eq 1 ]; then
        cp -f "$WORK/$1.txt" "$CHAR_EXPECT" || unmeasured "cannot write $CHAR_EXPECT"
        echo "FROZEN: $CHAR_EXPECT written from the $1 dump"
        return
    fi
    [ -f "$CHAR_EXPECT" ] || unmeasured "no frozen dump $CHAR_EXPECT"
    cmp -s "$WORK/$1.txt" "$CHAR_EXPECT" || {
        echo "FAIL: the $1 character dump differs from $CHAR_EXPECT; differing lines:"
        diff "$CHAR_EXPECT" "$WORK/$1.txt" | head -40
        exit 1
    }
}

save_mode() {
    WORK="$(mktemp -d)" || unmeasured "no temp dir"
    trap 'rm -rf "$WORK"' EXIT
    local sha0 sha1
    sha0=$(shasum -a 256 "$FIX" | awk '{print $1}')
    if [ "$MODE" = save ]; then
        dump_session write "$FIX"
        local wdir="$RUN_DIR"
        compare_expected write
        cp -f "$wdir/save/Varag.sav" "$WORK/Varag.sav"
        dump_session reload "$WORK/Varag.sav"
        local rdir="$RUN_DIR"
        cmp -s "$WORK/write.txt" "$WORK/reload.txt" || {
            echo "FAIL: the reloaded character differs from the one the first session saved:"
            diff "$WORK/write.txt" "$WORK/reload.txt" | head -40
            exit 1
        }
        if [ -n "${DAMAGE_CLASS_SAVE_DIR:-}" ]; then
            mkdir -p "$DAMAGE_CLASS_SAVE_DIR/write" "$DAMAGE_CLASS_SAVE_DIR/reload" || unmeasured "cannot make $DAMAGE_CLASS_SAVE_DIR"
            cp -f "$wdir/save/Varag.sav" "$wdir/logs/charprobe.txt" "$DAMAGE_CLASS_SAVE_DIR/write/"
            cp -f "$rdir/save/Varag.sav" "$rdir/logs/charprobe.txt" "$DAMAGE_CLASS_SAVE_DIR/reload/"
        fi
    else
        [ -s "$RELOAD_SAV" ] || unmeasured "--save-reload needs a save file; got '${RELOAD_SAV}'"
        cp -f "$RELOAD_SAV" "$WORK/Varag.sav"
        dump_session reload "$WORK/Varag.sav"
        compare_expected reload
    fi
    sha1=$(shasum -a 256 "$FIX" | awk '{print $1}')
    [ "$sha0" = "$sha1" ] || fail "the fixture $FIX changed during the run"
    [ "$FREEZE" -eq 1 ] && exit 0
    echo "PASS: character dump equals $CHAR_EXPECT$([ "$MODE" = save ] && echo ", and the saved character reloads identically"); fixture unchanged"
    exit 0
}

case "$MODE" in
    probe) probe_mode ;;
    *)     save_mode ;;
esac
