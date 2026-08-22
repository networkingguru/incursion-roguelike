#!/bin/bash
# Regression check for bd inc-j6ni: a priest could stack summons from one
# summoning spell, and a wizard could not.
#
# THE DEFECT. Magic::Summon aborts a cast when the caster still holds a live
# creature summoned by the SAME effect, but only for an effect flagged
# EF_XSUMMON (src/Effects.cpp:1371-1379). The wizard line sets that flag, and
# so do Dust Devil, Spiritual Hammer and Flaming Sphere. Holy Summoning I to VI
# and Summon Nature's Ally I to VI carried no Flags clause at all. Brian met
# the result in play on 2026-08-22: a monster priest behind Sanctuary summoned
# without limit while he could not touch it.
#
# THE ORACLE is the spell's own refusal message, thrown as MSG_XSUMMON by the
# abort path and by nothing else. The script casts Holy Summoning I twice on
# consecutive turns and photographs both.
#
#   before the fix   cast 1 "Your protectar appears!"
#                    cast 2 "Your protectar appears!"     <- two of them
#   after  the fix   cast 1 "Your protectar appears!"
#                    cast 2 "The outsider you called before still serves you."
#
# Both sides of that were measured on seed 5 on 2026-08-22, by rebuilding the
# module from the pre-fix lib/pspells.irh and running this same key script.
#
# The static pass below exists because the live pass exercises ONE of the
# twelve spells. Eleven of them could lose the flag and the run would still be
# green.
#
# Usage: tools/check_xsummon_live.sh      (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=5
KEYS=tools/keys/xsummon-priest.keys
fail=0

# ---- static: every rank of both lines still carries the flag -------------
want=12
got=$(awk '
    /^(Priest|Druid) Spell "(Holy Summoning|Summon Nature.s Ally) (I|II|III|IV|V|VI)" : EA_SUMMON/ { inspell=1 }
    inspell && /EF_XSUMMON/ { n++; inspell=0 }
    inspell && /Desc:/ { inspell=0 }
    END { print n+0 }
' lib/pspells.irh)
if [ "$got" = "$want" ]; then
    echo "  ok: all $want ranks of holy summoning and summon nature's ally set EF_XSUMMON"
else
    echo "FAIL: $got of $want summoning spells set EF_XSUMMON in lib/pspells.irh"
    fail=1
fi

# ---- live: the second cast is refused ------------------------------------
[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

OUT="$(tools/headless.sh "$KEYS" "$SEED" 2>&1)"
RUN="$(echo "$OUT" | awk '/^run:/ {print $2}')"
S1="$RUN/logs/screens/0001-cast1.txt"
S2="$RUN/logs/screens/0002-cast2.txt"

if [ ! -f "$S1" ] || [ ! -f "$S2" ]; then
    echo "FAIL: one of the two casts was never reached, so nothing was measured."
    echo "$OUT" | tail -12
    exit 1
fi

# Guard first. If the first cast stopped working -- the priest lost the spell,
# the targeting prompt moved, the module went stale -- the assertion below
# would pass for the wrong reason, because a spell that never fires also never
# summons a second creature.
if grep -q "protectar appears" "$S1"; then
    echo "  ok: the first cast summons an outsider, so the spell works at all"
else
    echo "INCONCLUSIVE: the first cast summoned nothing. Nothing was measured."
    sed -n '2,4p' "$S1"
    exit 1
fi

if grep -q "still serves you" "$S2"; then
    echo "  ok: the second cast is refused while the first outsider lives"
elif grep -q "protectar appears" "$S2"; then
    echo "FAIL: the second cast summoned a SECOND outsider. EF_XSUMMON is not"
    echo "      reaching the spell -- check that the module was rebuilt."
    fail=1
else
    echo "FAIL: the second cast did neither. The screen said:"
    sed -n '2,4p' "$S2"
    fail=1
fi

if [ "$fail" = 0 ]; then
    echo "PASS: one live summon per summoning spell, for priests as for wizards"
    exit 0
fi
exit 1
