#!/bin/bash
# gate: live
# Regression check for wondrous kinds that identification never taught, bd inc-dd5m.
#
# THE RULING. Every AI_WONDER effect is learnable by kind, flavour or not. The
# plus and the blessed/cursed state stay unknown per item. Item::MakeKnown and
# Item::Name (src/Item.cpp, src/Message.cpp) both took the "kind is learned" fact
# only for effects with a FlavorID, and a wondrous item has none, so every
# Mandolin of Musical Defense needed its own Identify.
#
# THE ORACLE is the name the game gives the second Mandolin of Musical Defense
# when it joins the pack, after the first was identified with Identify Whole
# Pack: the "AutoStowing: <name>." message (the second item joins its stack, so
# no In-the-Air line exists for it). Unlearned: "? mandolin". Learned:
# "? Mandolin of Musical Defense". The '?' is the unknown blessed/cursed
# marker and MUST stay, and no "+N" may appear: both prove the plus and the
# curse state are not taught by kind.
#
# The ring is the control, as in check_item_type_id.sh: a flavoured kind that
# always learned. If it did not change across the identify, the run measured
# nothing and this script says INCONCLUSIVE.
#
# fact: character -- chargen.keys under tools/gates/Options.Dat, seed 1; the check reads no stat
# fact: the wondrous item -- wizard "Acquire Unknown Item", Wonderous Items, the effect named by text
# fact: the control ring -- wizard "Acquire Unknown Item", Rings, "Fire Resistance" by text
# fact: settings -- INCURSION_OPTIONS=tools/gates/Options.Dat
# fact: item names -- asserted as read-a-name vs read-a-flavour, never the flavour word
#
# Usage: tools/check_wonder_type_id.sh    (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

KEYS=tools/keys/wonder-idtype.keys
SEED=1
KIND="Mandolin of Musical Defense"

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

OUT="$(INCURSION_OPTIONS=tools/gates/Options.Dat tools/headless.sh "$KEYS" "$SEED" 2>&1)"
RUN="$(echo "$OUT" | awk '/^run:/ {print $2}')"

if grep -q "NO GAMEPLAY" <<< "$OUT"; then
    echo "INCONCLUSIVE: the run never entered a map, so it measured nothing."
    exit 2
fi

screen() { LC_ALL=C tr -cd '\40-\176\n' < "$RUN/logs/screens/$1" 2>/dev/null; }

airline() {
    local f="$RUN/logs/screens/$1"
    [ -f "$f" ] || return 1
    LC_ALL=C grep -a -m1 "In the Air" "$f" |
        LC_ALL=C tr -cd '\40-\176\n' |
        sed -e "s/.*'In the Air'[[:space:]]*:[[:space:]]*//" \
            -e 's/[[:space:]][[:space:]].*$//' \
            -e 's/[[:space:]]*$//'
}

# The "AutoStowing: <name>." line at the top of the screen.
stowline() {
    screen "$1" | grep -a -m1 'AutoStowing:' |
        sed -e 's/.*AutoStowing:[[:space:]]*//' -e 's/\.[[:space:]]*|.*$//' -e 's/\.[[:space:]]*$//'
}

W1="$(airline 0002-wonder-1-in-air.txt)" || true
R1="$(airline 0003-ring-1-in-air.txt)"   || true
W2="$(stowline 0004-wonder-2-in-air.txt)" || true
R2="$(airline 0005-ring-2-in-air.txt)"   || true

for pair in "wonder-1:$W1" "ring-1:$R1" "wonder-2:$W2" "ring-2:$R2"; do
    if [ -z "${pair#*:}" ]; then
        echo "INCONCLUSIVE: no item name for ${pair%%:*}. Screens: $RUN/logs/screens"
        exit 2
    fi
done

echo "first wonder:  $W1"
echo "first ring:    $R1"
echo "second wonder: $W2"
echo "second ring:   $R2"
echo

case "$W1" in *"$KIND"*)
    echo "INCONCLUSIVE: the first wonder arrived already named."; exit 2 ;; esac
case "$R1" in *"Ring of"*)
    echo "INCONCLUSIVE: the first ring arrived already named."; exit 2 ;; esac
case "$R2" in *"Ring of"*) ;;
    *) echo "INCONCLUSIVE: the control ring did not learn its kind ($R2); the identify did not run."
       exit 2 ;; esac

case "$W2" in
    *"$KIND"*) ;;
    *) echo "FAIL: the second $KIND still reads '$W2' after an identical one was"
       echo "      identified, while the ring control learned its kind. Item::MakeKnown /"
       echo "      Item::Name take the kind only from a flavour. Screens: $RUN/logs/screens"
       exit 1 ;;
esac

case "$W2" in
    "? "*) ;;
    *) echo "FAIL: the second wonder reads '$W2'. The leading '?' (blessed/cursed unknown) is gone: the kind taught the curse state."
       exit 1 ;;
esac
case "$W2" in
    *[+-][0-9]*) echo "FAIL: the second wonder reads '$W2'. A plus shows: the kind taught the plus."
       exit 1 ;;
esac

echo "PASS: the second $KIND arrives named ('$W2') with plus and"
echo "      blessed/cursed state still unknown; the ring control learned too."
echo "      seed $SEED, $RUN/logs/screens"
exit 0
