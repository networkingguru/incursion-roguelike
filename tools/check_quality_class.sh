#!/bin/bash
# gate: live
# Does every place that asks "is this quality a weapon quality?" or "is this
# quality an armor quality?" still answer the same, for every quality number?
# (bd inc-rddai)
#
# WHAT IT DEFENDS. Five places decide a quality's class by a number line
# (a number line for weapons, another for armor) instead of by a table: Weapon::
# ItemLevel and Armour::ItemLevel (src/Item.cpp), QItem::ItemLevel (dead in
# play, reached here by a qualified call), the Augment quality menu in
# Character::CraftItem (src/Skills.cpp), and the Oil of Transformation script
# loop (lib/m_items.irh). The frozen log was written by the build BEFORE the
# table replaced those lines, so a PASS means every site still answers as it
# did then, for every number 1..82.
#
# CHANGING AN ANSWER ON PURPOSE. When a bead changes a quality's class column on
# purpose (for example making one weapon quality armor-legal), the lines for
# that number change and this check fails. That bead MUST re-freeze with
# `tools/check_quality_class.sh --freeze` on its own build, check that ONLY the
# lines for the changed number moved (`git diff tools/fixtures/quality-class.
# expected`), and name the change in its commit body. When a bead ADDS a quality
# (a WQ_, AQ_ or IQ_ define), the name manifest tools/fixtures/quality-names.
# expected fails first (exit 2); that bead MUST re-freeze it, then the log.
#
# THE ORACLE. INCURSION_QUALITY_CLASS_PROBE=1 makes src/QualityClassProbe.cpp
# call the REAL production method or script handler at each site and write
# logs/quality-class.log: `QC s1|s2|s3 q=<n> lvl=<level>` (83 lines each),
# `QC s4 item=weapon|armor n=<q>` (one per quality the Augment menu offers, read
# at the production site through a read-only hook, inc/QualityClassProbe.h),
# two `s4 ... ret=` lines, three `QC s5 case=...` lines (the eight quality slots
# after the real oil handler runs), and an END line. The check compares that
# log byte for byte with tools/fixtures/quality-class.expected. The probe holds
# no copy of the class test.
#
# SAVE COMPARISON, layer A (--save, --save-reload). A probe-disabled session
# loads the frozen character, saves, and the engine's own character dump is
# compared with tools/fixtures/quality-class-char.expected (byte-identical to
# tools/fixtures/damage-class-char.expected: same fixture, same keys). The save
# is then loaded by a second session and compared again.
#
# SAVE COMPARISON, layer B (--pack, --pack-reload). Item quality numbers are in
# the save but the dump above stops before the inventory. --pack runs
# INCURSION_QUALITY_CLASS_PROBE=stage (a light mace with qualities 7, 15, 26, 34,
# 60 and a leather armour with 15, 25 go into the pack, then Save and
# Continue), then reloads that save with =pack, which logs every pack item that
# has a quality (slots and ItemLevel). --pack-reload <save> does the reload
# half for a save another build wrote. The log is compared with tools/fixtures/
# quality-pack.expected. QUALITY_CLASS_SAVE_DIR=<dir> keeps the written save
# (<dir>/write/Varag.sav) and each pack log (<dir>/reload/quality-class.log).
#
# MODES
#   tools/check_quality_class.sh                  probe log against the frozen log
#   tools/check_quality_class.sh --save           layer A, write then reload
#   tools/check_quality_class.sh --save-reload <save>
#   tools/check_quality_class.sh --pack           layer B, stage, save, reload
#   tools/check_quality_class.sh --pack-reload <save>
#   ... --freeze                                  write the frozen file of that mode
#                                                 (see CHANGING AN ANSWER ON PURPOSE)
# Settings for the binary: INCURSION_BIN (default ./incursion-headless). Build the
# binary and mod/Incursion.Mod together with BACKEND=posix ./build_macos.sh.
#
# fact: loaded character, class, level, alignment, ChallengeRating, TotalLevel -- INCURSION_LOAD=tools/fixtures/chars/orc-barbarian-seed1-opt0822.sav (KEEN/VORPAL/SLAYING and the HOLY..BALANCE filters read them)
# fact: settings -- INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat
# fact: the seed -- not read; items are Item::Create from named resources, no GenItem, no die rolled for an asserted value
# fact: item identity, plus, known flags, quality slots -- in-process staging with readback in src/QualityClassProbe.cpp (Item::Create by name, SetInherentPlus, MakeKnown, Qualities[]), SETUP_ERROR on mismatch
# fact: no random bane -- WQ_SLAYING and WQ_BANE are never staged through AddQuality; QItem::AddQuality calls RandomBane only for them (src/Item.cpp), and the probe writes Qualities[] directly for them
# fact: IQ_FEATHERLIGHT's random(20) in Weapon::QualityOK -- never reached: it is not in QualityDescs, and ChangeIID is not given it
# fact: candidate list for CraftItem is one item, entry [a] -- other pack items get Known=0 for the call and are restored (WeaponTypeProbe pattern)
# fact: forge present -- GainPermStati(INNATE_KIT, SK_CRAFT), removed after
# fact: the Oil's target form -- key-script @choose "long sword"; the name is a module resource, fixed by lib/weapons.irh; a SETUP_ERROR if the choice returns another weapon
# fact: menu text is not asserted -- hook list and slot arrays are read, never rendered text; the dumps are specimens
# fact: ItemLevel return values, offered list, slot arrays -- read-only calls and one read-only hook at the production sites, no copied predicate
# fact: log text and order -- fixed case ids; no names, handles, times or random text
# fact: the quality-name domain -- committed manifest tools/fixtures/quality-names.expected compared with the WQ_/AQ_/IQ_ defines in inc/Defines.h
# fact: saved item quality values -- fixture plus the pack mode; the character dump of layer A stops before Inventory and is not used for items
#
# EXIT. 0 PASS, 1 FAIL (differing lines printed), 2 UNMEASURED (cannot run,
# SETUP_ERROR in the log, wrong line count, no gameplay, name manifest differs).
#
# Usage: tools/check_quality_class.sh [--save | --save-reload <save> | --pack | --pack-reload <save>] [--freeze]

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

OPTS=tools/fixtures/options-2026-08-22.dat
FIX=tools/fixtures/chars/orc-barbarian-seed1-opt0822.sav
EXPECT=tools/fixtures/quality-class.expected
NAMES=tools/fixtures/quality-names.expected
PACK_EXPECT=tools/fixtures/quality-pack.expected
CHAR_EXPECT=tools/fixtures/quality-class-char.expected
DAMAGE_CHAR_EXPECT=tools/fixtures/damage-class-char.expected
BIN="${INCURSION_BIN:-./incursion-headless}"
SEED=1

MODE=probe; FREEZE=0; RELOAD_SAV=""
while [ $# -gt 0 ]; do
    case "$1" in
        --save) MODE=save ;;
        --save-reload) MODE=reload; shift; RELOAD_SAV="${1:-}" ;;
        --pack) MODE=pack ;;
        --pack-reload) MODE=packreload; shift; RELOAD_SAV="${1:-}" ;;
        --freeze) FREEZE=1 ;;
        *) echo "usage: tools/check_quality_class.sh [--save | --save-reload <save> | --pack | --pack-reload <save>] [--freeze]"; exit 2 ;;
    esac
    shift
done

unmeasured() { echo "UNMEASURED: $*"; exit 2; }
fail() { echo "FAIL: $*"; exit 1; }

for f in "$OPTS" "$FIX" tools/keys/quality-class.keys tools/keys/quality-class-stage.keys \
         tools/keys/quality-class-pack.keys tools/keys/load-char-sheet.keys; do
    [ -f "$f" ] || unmeasured "missing $f"
done
[ -x "$BIN" ] || unmeasured "$BIN is not built (BACKEND=posix ./build_macos.sh)"
[ -f mod/Incursion.Mod ] || unmeasured "mod/Incursion.Mod is not built"

# One session through tools/headless.sh, in its own run directory.
# session <label> <keys> <load> [VAR=value ...]  -> sets RUN_DIR and SESSION_OUT
session() {
    local label="$1" keys="$2" load="$3"; shift 3
    local rundir="$ROOT/logs/runs/quality-class-$label-$(date +%Y%m%d-%H%M%S)-$$"
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
             sed -n '/^--- after the session ---/,$p' <<<"$SESSION_OUT"
             unmeasured "the session ended badly (tools/headless.sh exit $rc); see $rundir" ;;
    esac
    [ -d "$rundir/logs" ] || unmeasured "no logs in $rundir"
}

# The quality-name domain: the WQ_/AQ_/IQ_ defines, as "NAME value" lines.
names_now() {
    python3 -I - <<'PY'
import re
out = []
for l in open("inc/Defines.h", errors="replace"):
    m = re.match(r"#define\s+((?:WQ|AQ|IQ)_[A-Z0-9_]+)\s+(\d+)\b", l)
    if m:
        out.append("%s %s" % (m.group(1), m.group(2)))
print("\n".join(out))
PY
}

check_names() {
    local now
    now="$(mktemp)" || unmeasured "no temp file"
    names_now > "$now"
    if [ "$FREEZE" -eq 1 ]; then
        cp -f "$now" "$NAMES" || unmeasured "cannot write $NAMES"
        echo "FROZEN: $NAMES written ($(wc -l < "$NAMES" | tr -d ' ') names)"
    else
        [ -f "$NAMES" ] || unmeasured "no name manifest $NAMES"
        if ! cmp -s "$now" "$NAMES"; then
            diff "$NAMES" "$now" | head -20
            rm -f "$now"
            unmeasured "the WQ_/AQ_/IQ_ defines in inc/Defines.h differ from $NAMES; update the oracle explicitly"
        fi
    fi
    rm -f "$now"
}

# Common checks on a probe log. probe_log_ok <log>
probe_log_ok() {
    local log="$1"
    [ -s "$log" ] || unmeasured "no quality-class.log: the probe did not run"
    if grep -q "NO GAMEPLAY" <<<"$SESSION_OUT"; then
        unmeasured "the session played no turn (NO GAMEPLAY); see $RUN_DIR"
    fi
    if grep -q '^SETUP_ERROR' "$log"; then
        grep '^SETUP_ERROR' "$log"
        unmeasured "the probe could not stage a case (SETUP_ERROR above); see $log"
    fi
}

# ------------------------------------------------------------------ probe mode
probe_mode() {
    check_names
    if [ "$FREEZE" -eq 0 ]; then
        [ -f "$EXPECT" ] || unmeasured "no frozen log $EXPECT"
    fi
    session probe tools/keys/quality-class.keys "$FIX" INCURSION_QUALITY_CLASS_PROBE=1
    local log="$RUN_DIR/logs/quality-class.log"
    probe_log_ok "$log"
    local n u s want
    n=$(grep -c '^QC ' "$log")
    for s in s1 s2 s3; do
        want=$(grep -c "^QC $s q=" "$log")
        [ "$want" -eq 82 ] || unmeasured "$want numbered $s lines, wanted 82; see $log"
        [ "$(grep -c "^QC $s base " "$log")" -eq 1 ] || unmeasured "no single $s base line; see $log"
    done
    [ "$(grep -c '^QC s5 case=' "$log")" -eq 3 ] || unmeasured "not three s5 lines; see $log"
    [ "$(grep -c '^QC s4 item=.* ret=' "$log")" -eq 2 ] || unmeasured "not two s4 ret lines; see $log"
    u=$(grep '^QC ' "$log" | sort | uniq -d | wc -l | tr -d ' ')
    [ "$u" -eq 0 ] || unmeasured "$u duplicated lines in $log"
    grep -qx "END lines=$n errors=0" "$log" || unmeasured "no 'END lines=$n errors=0' line in $log"
    if [ "$FREEZE" -eq 1 ]; then
        cp -f "$log" "$EXPECT" || unmeasured "cannot write $EXPECT"
        echo "FROZEN: $EXPECT written from $log ($n QC lines)"
        exit 0
    fi
    want=$(grep -c '^QC ' "$EXPECT")
    [ "$n" -eq "$want" ] || echo "note: $n QC lines, the frozen file has $want"
    if cmp -s "$log" "$EXPECT"; then
        echo "PASS: $n QC lines identical to $EXPECT (session $RUN_DIR)"
        exit 0
    fi
    echo "FAIL: quality-class.log differs from $EXPECT (session $RUN_DIR); differing lines:"
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
        [ -f "$DAMAGE_CHAR_EXPECT" ] || unmeasured "no $DAMAGE_CHAR_EXPECT to compare the new dump with"
        cmp -s "$WORK/$1.txt" "$DAMAGE_CHAR_EXPECT" ||
            unmeasured "the $1 dump differs from $DAMAGE_CHAR_EXPECT; layer A reuses that dump"
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
        cmp -s "$WORK/write.txt" "$WORK/reload.txt" || {
            echo "FAIL: the reloaded character differs from the one the first session saved:"
            diff "$WORK/write.txt" "$WORK/reload.txt" | head -40
            exit 1
        }
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

# ------------------------------------------------------------------- pack mode
# pack_reload <save>: load the save with the pack probe, compare its log.
pack_reload() {
    local sav="$1" log
    cp -f "$sav" "$WORK/Varag.sav" || unmeasured "cannot copy $sav"
    session packreload tools/keys/quality-class-pack.keys "$WORK/Varag.sav" INCURSION_QUALITY_CLASS_PROBE=pack
    log="$RUN_DIR/logs/quality-class.log"
    probe_log_ok "$log"
    # Both staged items must be in the log, with the slots that were staged.
    grep -q ' slots=7,15,26,34,60,0,0,0 ' "$log" || unmeasured "the staged light mace is not in $log"
    grep -q ' slots=15,25,0,0,0,0,0,0 ' "$log" || unmeasured "the staged leather armour is not in $log"
    if [ -n "${QUALITY_CLASS_SAVE_DIR:-}" ]; then
        mkdir -p "$QUALITY_CLASS_SAVE_DIR/reload" || unmeasured "cannot make $QUALITY_CLASS_SAVE_DIR"
        cp -f "$log" "$QUALITY_CLASS_SAVE_DIR/reload/quality-class.log"
    fi
    if [ "$FREEZE" -eq 1 ]; then
        cp -f "$log" "$PACK_EXPECT" || unmeasured "cannot write $PACK_EXPECT"
        echo "FROZEN: $PACK_EXPECT written from $log"
        return
    fi
    [ -f "$PACK_EXPECT" ] || unmeasured "no frozen pack log $PACK_EXPECT"
    cmp -s "$log" "$PACK_EXPECT" || {
        echo "FAIL: the pack log differs from $PACK_EXPECT (session $RUN_DIR); differing lines:"
        diff "$PACK_EXPECT" "$log" | head -40
        exit 1
    }
}

pack_mode() {
    WORK="$(mktemp -d)" || unmeasured "no temp dir"
    trap 'rm -rf "$WORK"' EXIT
    local sha0 sha1
    sha0=$(shasum -a 256 "$FIX" | awk '{print $1}')
    if [ "$MODE" = pack ]; then
        session stage tools/keys/quality-class-stage.keys "$FIX" INCURSION_QUALITY_CLASS_PROBE=stage
        probe_log_ok "$RUN_DIR/logs/quality-class.log"
        [ "$(grep -c '^QC stage ' "$RUN_DIR/logs/quality-class.log")" -eq 2 ] ||
            unmeasured "the probe did not stage two items; see $RUN_DIR/logs/quality-class.log"
        [ -s "$RUN_DIR/save/Varag.sav" ] || unmeasured "the stage session wrote no save/Varag.sav"
        cp -f "$RUN_DIR/save/Varag.sav" "$WORK/staged.sav"
        if [ -n "${QUALITY_CLASS_SAVE_DIR:-}" ]; then
            mkdir -p "$QUALITY_CLASS_SAVE_DIR/write" || unmeasured "cannot make $QUALITY_CLASS_SAVE_DIR"
            cp -f "$WORK/staged.sav" "$QUALITY_CLASS_SAVE_DIR/write/Varag.sav"
        fi
        pack_reload "$WORK/staged.sav"
    else
        [ -s "$RELOAD_SAV" ] || unmeasured "--pack-reload needs a save file; got '${RELOAD_SAV}'"
        pack_reload "$RELOAD_SAV"
    fi
    sha1=$(shasum -a 256 "$FIX" | awk '{print $1}')
    [ "$sha0" = "$sha1" ] || fail "the fixture $FIX changed during the run"
    [ "$FREEZE" -eq 1 ] && exit 0
    echo "PASS: the pack log equals $PACK_EXPECT; fixture unchanged"
    exit 0
}

case "$MODE" in
    probe) probe_mode ;;
    save|reload) save_mode ;;
    pack|packreload) pack_mode ;;
esac
