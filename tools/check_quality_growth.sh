#!/bin/bash
# gate: smoke
# Can an author add a NEW weapon quality (a number above every shipped one) and
# have the game offer it, name it and keep it? (bd inc-mafd8)
#
# WHAT IT DEFENDS. Three places walk every quality number: the Weaponcraft "add
# quality" offer (src/Skills.cpp), item naming (src/Message.cpp) and the Oil of
# Transformation script (lib/m_items.irh). Each used to stop at a fixed number
# (a fixed end number, 81), so a quality numbered 82 was never offered and never named.
# The Oil's own loop never visited it either, but Item::ChangeIID already keeps
# every quality below 100, so the Oil keeps 82 before and after; the check
# guards that. Each now stops at QualityMaxNumber(), the highest
# number in QualityTable[] (src/Tables.cpp).
#
# HOW. The check copies the tracked files, as they are on disk, into a scratch
# directory under logs/quality-growth/, applies tools/fixtures/quality-grow.patch
# there, builds the headless binary there, and runs the quality probe in mode
# `grow` (src/QualityClassProbe.cpp, tools/keys/quality-grow.keys). Your tree is
# not touched. The scratch directory is removed on exit.
#
# WHAT THE PATCH ADDS: all an author must add for a new weapon quality 82:
#   inc/Defines.h   #define WQ_TESTGROW 82, in the `family: wq` block
#   src/Tables.cpp  a QualityTable[] row (weapon yes, armor no)
#                   a PreQualNames[] entry ("growtest"): the name
#                   a QualityDescs[] entry: Weaponcraft offers only a quality
#                   that has a description
#   (inc/ConstNam.h is the script-constant name list; a quality that no script
#   names needs no row there.)
# PASS needs all three: Weaponcraft offers 82, the Oil keeps 82, and the item
# name shows "growtest". A FAIL names each one that is missing.
#
# EXIT. 0 PASS, 1 FAIL, 2 UNMEASURED (the patch does not apply, the copy or the
# build fails, the probe logs a SETUP_ERROR, or the probe offers nothing at all).
#
# fact: the key script -- read from this tree (tools/keys/quality-grow.keys), a fixed answer list
# fact: the files under test -- the tracked files as they are on disk, copied by this check; the patch is committed (tools/fixtures/quality-grow.patch)
# fact: loaded character -- INCURSION_LOAD=tools/fixtures/chars/orc-barbarian-seed1-opt0822.sav, copied into the scratch tree
# fact: settings -- INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat
# fact: the seed -- not read; items are Item::Create from named resources with qualities written directly, no GenItem, no random bane
# fact: item identity, known flags, quality slots -- in-process staging with readback in src/QualityClassProbe.cpp, SETUP_ERROR on mismatch
# fact: the Oil's target form -- key-script @choose "long sword"; a SETUP_ERROR if the choice returns another weapon
# fact: the name text -- Item::Name over the name tables as the patch extends them; identified long sword, plus 0
# fact: the offered list -- the read-only hook at the production site (inc/QualityClassProbe.h), not menu text
# fact: forge present -- GainPermStati(INNATE_KIT, SK_CRAFT), removed after
#
# Usage: tools/check_quality_growth.sh

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

PATCH="$ROOT/tools/fixtures/quality-grow.patch"
unmeasured() { echo "UNMEASURED: $*"; exit 2; }

[ -f "$PATCH" ] || unmeasured "missing $PATCH"
for f in tools/keys/quality-grow.keys tools/fixtures/options-2026-08-22.dat \
         tools/fixtures/chars/orc-barbarian-seed1-opt0822.sav; do
    [ -f "$f" ] || unmeasured "missing $f"
done

mkdir -p "$ROOT/logs/quality-growth" || unmeasured "cannot make logs/quality-growth"
SCR="$ROOT/logs/quality-growth/run-$$"
mkdir -p "$SCR" || unmeasured "cannot make $SCR"
trap 'rm -rf "$SCR"' EXIT

# Copy the tracked files that exist on disk (a tracked file a bead deleted is skipped).
LIST="$SCR.list"
python3 -I - "$ROOT" > "$LIST" <<'PY' || unmeasured "cannot list the tracked files"
import os, subprocess, sys
root = sys.argv[1]
out = subprocess.run(["git", "-C", root, "ls-files", "-z"], capture_output=True, check=True).stdout
for p in out.split(b"\0"):
    if p and os.path.lexists(os.path.join(root.encode(), p)):
        sys.stdout.buffer.write(p + b"\0")
PY
tar -cf - --null -T "$LIST" | tar -xf - -C "$SCR" || { rm -f "$LIST"; unmeasured "cannot copy the tree"; }
rm -f "$LIST"

patch -p1 -d "$SCR" --dry-run -s < "$PATCH" >/dev/null 2>&1 ||
    unmeasured "tools/fixtures/quality-grow.patch does not apply to this tree"
patch -p1 -d "$SCR" -s < "$PATCH" >/dev/null 2>&1 || unmeasured "the patch failed to apply"

( cd "$SCR" && BACKEND=posix ./build_macos.sh > "$SCR/build.log" 2>&1 ) || {
    tail -15 "$SCR/build.log"
    unmeasured "the build in the scratch tree failed"
}
[ -x "$SCR/incursion-headless" ] || unmeasured "no binary was built"

RUNDIR="$SCR/run"
( cd "$SCR" && INCURSION_BIN="$SCR/incursion-headless" \
    INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
    INCURSION_LOAD=tools/fixtures/chars/orc-barbarian-seed1-opt0822.sav \
    INCURSION_RUN_DIR="$RUNDIR" INCURSION_QUALITY_CLASS_PROBE=grow \
    tools/headless.sh "$ROOT/tools/keys/quality-grow.keys" 1 > "$SCR/session.out" 2>&1 </dev/null )
rc=$?
case "$rc" in 0|3) ;; *) tail -15 "$SCR/session.out"; unmeasured "the session ended badly (exit $rc)" ;; esac
grep -q "NO GAMEPLAY" "$SCR/session.out" && unmeasured "the session played no turn"
LOG="$RUNDIR/logs/quality-class.log"
[ -s "$LOG" ] || unmeasured "no quality-class.log: the probe did not run"
if grep -q '^SETUP_ERROR' "$LOG"; then grep '^SETUP_ERROR' "$LOG"; unmeasured "the probe could not stage a case"; fi
grep -q '^END lines=[0-9]* errors=0' "$LOG" || unmeasured "no clean END line in the probe log"
# Control: the offer must list the shipped qualities, or the probe saw nothing.
grep -q '^QC s4 item=weapon n=' "$LOG" || unmeasured "the Weaponcraft offer listed nothing at all"

echo "probe lines:"; grep -E '^QC (s5 case=grow|s6 item=weapon q=82)|^QC s4 item=weapon (n=8|ret)' "$LOG" | sed 's/^/  /'
bad=0
if grep -qx 'QC s4 item=weapon n=82' "$LOG"; then echo "ok: Weaponcraft offers quality 82"
else echo "FAIL: Weaponcraft does not offer quality 82 (src/Skills.cpp loop bound)"; bad=1; fi
if grep -qx 'QC s5 case=grow ret=[A-Z]* slots=82,0,0,0,0,0,0,0' "$LOG"; then echo "ok: the Oil keeps quality 82"
else echo "FAIL: the Oil of Transformation drops quality 82 (lib/m_items.irh loop, Item::ChangeIID)"; bad=1; fi
if grep -qx 'QC s6 item=weapon q=82 name=growtest long sword' "$LOG"; then echo "ok: the item name shows quality 82"
else echo "FAIL: the item name does not show quality 82 (src/Message.cpp loop bound)"; bad=1; fi

if [ "$bad" -ne 0 ]; then
    echo "FAIL: a new quality number 82 is not fully supported"
    exit 1
fi
echo "PASS: a new weapon quality 82 is offered, kept by the Oil and named"
exit 0
