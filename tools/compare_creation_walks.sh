#!/bin/bash
# Walk a fixed set of character creations with a baseline binary and with the
# current binary, dump every saved character, and report whether each pair of
# canonical dumps is byte-identical. This is the standing constraint of the
# fixture builder (docs/specs/2026-11-06-fixture-builder-brief.md): the Live
# creation source MUST make the same random() calls in the same order as the
# code it replaced, so a walk MUST give the same character under both.
#
# Usage: tools/compare_creation_walks.sh [--reincarnate] <baseline-binary> [out-dir]
#        tools/compare_creation_walks.sh logs/phase4/base-incursion-headless logs/phase4/walks
#
# --reincarnate runs ONE pair instead: session 1 makes an orc barbarian
# (tools/keys/chargen-default-save.keys), session 2 reincarnates him from the
# gallery (tools/keys/reincarnate-save.keys), each under both binaries, and the
# second character's canonical dump and the gallery entry are compared. This is
# the gallery path (Player::Reincarnate, the Replay creation source).
#
# Each walk is (name, key script, seed, settings file). Both binaries run each
# walk through tools/headless.sh with the same inputs and their own run
# directory, and tools/char_dump.sh dumps each saved character. The gallery
# entry the walk wrote (save/gallery.dat) is compared too, with the two clock
# fields (the first 16 bytes of each entry) set aside.
#
# Exit: 0 every pair identical, 1 a pair differs or a walk did not finish,
#       2 bad usage.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

REINC=0
if [ "${1:-}" = "--reincarnate" ]; then REINC=1; shift; fi
BASE="${1:-}"
OUT="${2:-logs/phase4/walks}"
NEW="${INCURSION_NEW_BIN:-./incursion-headless}"
[ -n "$BASE" ] && [ -x "$BASE" ] || { echo "usage: $0 <baseline-binary> [out-dir]" >&2; exit 2; }
[ -x "$NEW" ] || { echo "$NEW is not built" >&2; exit 2; }
mkdir -p "$OUT"

O22=tools/fixtures/options-2026-08-22.dat

strip_secs() {
    python3 - "$1" <<'PY'
import sys,re
p=sys.argv[1]
t=open(p).read().split("\n")
if not any("| Secs |" in l for l in t): sys.exit(0)
o=[]
for l in t:
    if l.startswith("Lvl | Act | Key | Turns | Secs |"): l=l.replace(" Secs |","",1)
    elif l.startswith("----+-----+-----+-------+------+"): l=l.replace("+------+","+",1)
    elif re.match(r"^\d+ *\|",l) and l.count("|")==6:
        f=l.split("|"); del f[4]; l="|".join(f)
    o.append(l)
open(p,"w").write("\n".join(o))
PY
}


if [ "$REINC" -eq 1 ]; then
    rf=0
    for side in base new; do
        bin="$BASE"; [ "$side" = new ] && bin="$NEW"
        run="$OUT/reinc-$side"
        rm -rf "$run"
        for keys in tools/keys/chargen-default-save.keys tools/keys/reincarnate-save.keys; do
            INCURSION_OPTIONS="$O22" INCURSION_BIN="$bin" INCURSION_RUN_DIR="$ROOT/$run" \
                tools/headless.sh "$keys" 1 > "$OUT/reinc-$side-$(basename "$keys" .keys).log" 2>&1 </dev/null \
                || { echo "FAIL    $keys under $side"; rf=1; }
        done
        sav=$(ls -t "$run"/save/*.sav 2>/dev/null | head -1)
        [ -n "$sav" ] || { echo "NOSAVE  reinc ($side)"; rf=1; continue; }
        INCURSION_OPTIONS="$O22" INCURSION_BIN="$bin" tools/char_dump.sh "$sav" "$OUT/reinc-$side.canon" > /dev/null 2>&1 || rf=1
        tail -c +17 "$run/save/gallery.dat" > "$OUT/reinc-$side.gallery"
    done
    strip_secs "$OUT/reinc-base.canon"
    if [ -s "$OUT/reinc-base.canon" ] && cmp -s "$OUT/reinc-base.canon" "$OUT/reinc-new.canon" \
        && cmp -s "$OUT/reinc-base.gallery" "$OUT/reinc-new.gallery" && [ $rf -eq 0 ]; then
        echo "SAME    reincarnated character (dump and gallery entry)"; exit 0
    fi
    echo "DIFF    reincarnated character"; exit 1
fi
O18=tools/fixtures/options-2026-08-18.dat
GATE=tools/gates/Options.Dat
KIT=tools/fixtures/options-2026-08-22-kit.dat   # OPT_BEGINKIT on (spec B17)

WALKS=(
  "orc-barbarian-s1-o22   tools/keys/chargen-default-save.keys      1  $O22"
  "orc-mage-s4-o22        tools/keys/chargen-mage-save.keys         4  $O22"
  "human-paladin-s4-o22   tools/keys/chargen-paladin-save.keys      4  $O22"
  "orc-priest-s1-o22      tools/keys/chargen-priest-save.keys       1  $O22"
  "orc-rogue-s6-o22       tools/keys/chargen-rogue-save.keys        6  $O22"
  "wood-elf-rogue-s7-o18  tools/keys/wood-elf-rogue-save.keys       7  $O18"
  "deepgnome-s3-o18       tools/keys/underdark-deepgnome-save.keys  3  $O18"
  "dragonkin-s1-o18       tools/keys/dragonkin-sheet-save.keys      1  $O18"
  "monk-ki-s1-o18         tools/keys/monk-ki-strike-save.keys       1  $O18"
  "gnome-warrior-s1-o22   tools/keys/gnome-warrior-pickaxe-save.keys 1 $O22"
  "xsummon-priest-s5-o22  tools/keys/xsummon-priest-save.keys       5  $O22"
  "earthsinger-s3-o22     tools/keys/prestige-earthsinger-save.keys 3  $O22"
  "orc-mage-s4-gate       tools/keys/chargen-mage-save.keys         4  $GATE"
  "orc-barbarian-s3-gate  tools/keys/chargen-default-save.keys      3  $GATE"
  # Phase 5: gear, kit and missile counts. The Drow ranger reaches the
  # "of random 3 to 4" weapon (lib/races.irh:61-65) and NN% gear lines; the
  # three -kit walks run with the Beginner's Kit on.
  "drow-ranger-twf-s1-o22 tools/keys/ranger-twf-gear-save.keys      1  $O22"
  "drow-priest-s1-o22     tools/keys/command-pools.keys             1  $O22"
  "drow-mage-hunger-s4-o22 tools/keys/hunger-walk.keys              4  $O22"
  "human-ranger-s1-o22    tools/keys/kit-ranger.keys                1  $O22"
  "drow-ranger-twf-s1-kit tools/keys/ranger-twf-gear-save.keys      1  $KIT"
  "human-ranger-s1-kit    tools/keys/kit-ranger.keys                1  $KIT"
  "orc-barbarian-s1-kit   tools/keys/chargen-default-save.keys      1  $KIT"
  # Phase 6a: prompts. Point buy, the feat menu with its toggle row and a
  # rejected feat, the skill, exotic-weapon and weapon sub-menus at creation,
  # and a level-up after creation that takes a feat (outside the window).
  "human-warrior-feats-s1-o22 tools/keys/p6a-human-warrior-feats.keys 1  $O22"
  "human-warrior-levelup-s1-o22 tools/keys/p6a-levelup-feat.keys     1  $O22"
)

fail=0
for row in "${WALKS[@]}"; do
    set -- $row
    name="$1"; keys="$2"; seed="$3"; opts="$4"
    # WALK_FILTER=<regex> runs only the walks whose name matches it.
    if [ -n "${WALK_FILTER:-}" ] && ! [[ "$name" =~ $WALK_FILTER ]]; then continue; fi
    for side in base new; do
        bin="$BASE"; [ "$side" = new ] && bin="$NEW"
        run="$OUT/$name-$side"
        rm -rf "$run"
        INCURSION_OPTIONS="$opts" INCURSION_BIN="$bin" INCURSION_RUN_DIR="$ROOT/$run" \
            tools/headless.sh "$keys" "$seed" > "$OUT/$name-$side.log" 2>&1 </dev/null
        echo "$?" > "$OUT/$name-$side.exit"
        sav=$(ls "$run"/save/*.sav 2>/dev/null | head -1)
        if [ -z "$sav" ]; then
            echo "NOSAVE  $name ($side)"; fail=1; continue
        fi
        INCURSION_OPTIONS="$opts" INCURSION_BIN="$bin" tools/char_dump.sh "$sav" "$OUT/$name-$side.canon" > /dev/null 2>&1 \
            || { echo "DUMPFAIL $name ($side)"; fail=1; }
        if [ -f "$run/save/gallery.dat" ]; then
            # Entry layout: two time_t fields first. Set them aside.
            tail -c +17 "$run/save/gallery.dat" > "$OUT/$name-$side.gallery"
        fi
    done
    # A baseline binary built before the canonical dump dropped the wall-clock
    # Secs column still prints it; strip that column from the baseline dump
    # only, so the pair compares byte for byte. The current binary prints none.
    strip_secs "$OUT/$name-base.canon"
    if [ -s "$OUT/$name-base.canon" ] && cmp -s "$OUT/$name-base.canon" "$OUT/$name-new.canon"; then
        g="gallery-none"
        if [ -f "$OUT/$name-base.gallery" ]; then
            if cmp -s "$OUT/$name-base.gallery" "$OUT/$name-new.gallery"; then g="gallery-same"; else g="GALLERY-DIFF"; fail=1; fi
        fi
        echo "SAME    $name ($g)"
    else
        echo "DIFF    $name"; fail=1
    fi
done
exit $fail
