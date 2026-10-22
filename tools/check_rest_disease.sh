#!/bin/bash
# gate: live
# gate-serial: writes fixed scratch dirs logs/rest-disease-scratch-* and rm -rf's them
# Does a full rest recover hit points while DISEASED, and what does it do to
# ability damage? (bd inc-d8i7, ruling inc-g69h row 2)
#
# THE RULE. Disease blocks only the ability-damage half of a rest's recovery
# (src/Player.cpp Rest handler: j starts at 1, or 2 with Strong Soul, and
# DISEASED takes one off). It MUST NOT block hit-point recovery. Before the
# fix, j reaching 0 jumped past the hit-point heal as well.
#
# THE ROUTE. tools/fixtures/rest-disease-god.irh stages each case with no dice:
# the god's blessing sets the disease / Strong Soul (or neither), halves cHP and
# puts 3 points of ability damage on A_STR and A_DEX. tools/keys/rest-disease.keys
# dumps "Examine Player Data" before and after a 100% rest. Three cases:
#   nosoul   DISEASED:           HP must rise; ability damage must NOT drop
#   soul     DISEASED+Strong Soul: HP must rise; each ability damage drops by 1
#   healthy  neither:            HP must rise; each ability damage drops by 1
# (A healthy character without Strong Soul has j == 1, so also 1 per rest.)
# The ability damage and HP are read from the dump's own numbers, not a message.
#
# --PROVE-RED reinserts the old block: DISEASED with j == 0 skips the heal.
#
# Usage: tools/check_rest_disease.sh [--prove-red]
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
SEED=1

# Pin the DISEASED pulse's FORT save to a success (INCURSION_FORCE_SAVE_ROLL,
# src/Fight.cpp:415 -> Creature::SavingThrow, src/Creature.cpp:3936). The rest
# calls DiseasePulse once (src/Player.cpp:2584); on a FAILED save the disease
# rolls its own damage -- devil chills is pval 1d2 STR (lib/threats.irh:69) --
# and that unrelated 1d2 moves the STR total under the check's feet whenever an
# appended resource shifts the random stream. Forcing the save keeps the
# character DISEASED (S->Mag only reaches 1 of its 3) while isolating the
# question the check asks: how much ability damage does the REST restore.
export INCURSION_FORCE_SAVE_ROLL=20

[ -x ./incursion-headless ] || _check_die 2 \
    "./incursion-headless is not built. Run: BACKEND=posix ./build_macos.sh"

check_mutation src/Player.cpp 'if (t->HasStati(DISEASED))' \
    'if (t->HasStati(DISEASED) && (t->HasAbility(CA_STRONG_SOUL) ? (j--, 0) : 1)) continue; if (t->HasStati(DISEASED))'

# <case> <statement for the god's handler>
_rd_stage() {
    local name="$1" stmt="$2"
    RD_DIR="$CHECK_ROOT/logs/rest-disease-scratch-$name"
    rm -rf "$RD_DIR"
    mkdir -p "$RD_DIR/mod" "$RD_DIR/save" "$RD_DIR/logs"
    cp -Rf "$CHECK_ROOT/lib" "$RD_DIR/lib" || _check_die 2 "could not copy lib/"
    ln -sfn "$CHECK_ROOT/inc" "$RD_DIR/inc"
    sed "s|@@CASE@@|$stmt|" "$CHECK_ROOT/tools/fixtures/rest-disease-god.irh" \
        >> "$RD_DIR/lib/main.irc"
    INCURSIONPATH="$RD_DIR/" ./incursion-headless -compile main.irc \
        < /dev/null > "$RD_DIR/compile.log" 2>&1
    if [ ! -f "$RD_DIR/mod/Incursion.Mod" ]; then
        tail -30 "$RD_DIR/compile.log"
        _check_die 2 "the scratch module for case $name did not compile"
    fi
}

# <screen file> -> current HP
_rd_hp() { sed -n 's/.*HP:[^0-9]*\([0-9][0-9]*\)\/[0-9].*/\1/p' "$1" | head -1; }
# <screen file> <ability const> -> total ability damage magnitude, summing
# every ADJUST_DMG row for that ability (0 when absent). A single ability can
# carry more than one damage stati (e.g. the disease's own pulse), so reading
# only the first row would misreport the total.
_rd_dmg() {
    local total=0 m
    while IFS= read -r m; do
        [ -n "$m" ] && total=$((total + m))
    done < <(grep "ADJUST DMG" "$1" | grep "Val:$2 " \
        | sed -n 's/.*Mag:\(-[0-9]*\).*/\1/p')
    echo "$total"
}

_rd_case() { # <name> <statement> <expect HP rise: 1> <expected damage drop per ability>
    local name="$1" stmt="$2" drop="$3" hb ha sb sa db da
    _rd_stage "$name" "$stmt"
    INCURSION_RUN_DIR="$RD_DIR" check_run tools/keys/rest-disease.keys "$SEED"
    local before after
    before=$(ls "$CHECK_RUN"/logs/screens/*before*.txt 2>/dev/null | head -1)
    after=$(ls "$CHECK_RUN"/logs/screens/*after*.txt 2>/dev/null | head -1)
    [ -f "$before" ] && [ -f "$after" ] || _check_die 2 "case $name: no before/after dump"
    hb=$(_rd_hp "$before"); ha=$(_rd_hp "$after")
    sb=$(_rd_dmg "$before" "A STR"); sa=$(_rd_dmg "$after" "A STR")
    db=$(_rd_dmg "$before" "A DEX"); da=$(_rd_dmg "$after" "A DEX")
    echo "  [$name] HP $hb -> $ha; STR dmg $sb -> $sa; DEX dmg $db -> $da"
    [ -n "$hb" ] && [ -n "$ha" ] && [ "$sb" = "-3" ] && [ "$db" = "-3" ] || \
        _check_die 2 "case $name: staging did not land (HP/dmg before)"
    if [ "$name" != healthy ]; then
        grep -q "DISEASED" "$before" || _check_die 2 "case $name: not DISEASED before rest"
    fi
    if [ "$ha" -gt "$hb" ]; then echo "  ok: [$name] HP rose"
    else echo "  FAIL: [$name] HP did not rise"; RD_FAIL=1; fi
    local want=$((-3 + drop))
    if [ "$sa" = "$want" ] && [ "$da" = "$want" ]; then echo "  ok: [$name] ability damage now $want"
    else echo "  FAIL: [$name] ability damage not $want"; RD_FAIL=1; fi
}

RD_FAIL=0
_rd_case nosoul  'EActor->GainPermStati(DISEASED,NULL,SS_MISC,0,0,$"devil chills");' 0
_rd_case soul    'EActor->GainPermStati(DISEASED,NULL,SS_MISC,0,0,$"devil chills"); EActor->GainPermStati(EXTRA_ABILITY,NULL,SS_MISC,CA_STRONG_SOUL,1);' 1
_rd_case healthy 'EActor->cHP = EActor->mHP / 2;' 1

[ "$RD_FAIL" = 0 ] || _check_die 1 "rest while diseased does not match the ruling"
echo "PASS: rest while diseased heals HP; ability damage follows the ruling"
exit 0
