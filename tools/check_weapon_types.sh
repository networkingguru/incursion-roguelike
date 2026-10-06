#!/bin/bash
# gate: live
# Places that decide "is this a weapon?" with an exact isType(T_WEAPON) must
# treat BOWS (T_BOW) and AMMUNITION (T_MISSILE) as weapons. (bd inc-f38k)
#
# isType is an exact type match (inc/Base.h), so a bow or a bolt fell through
# every one of the tests below. T_STAFF stays out. Each site is observed by
# driving the real code that holds the test, with a bow and/or ammunition and a
# T_WEAPON control (a long sword, dagger or spiked chain):
#
#   magicweapon  lib/wspells.irh Magic Weapon: EV_ISTARGET and EV_RATETARG
#   brand        lib/pspells.irh Brand of Hatred: EV_ISTARGET, EV_RATETARG,
#                EV_MAGIC_HIT (a bane quality lands on the item)
#   price        src/Social.cpp Item::getShopCost, the high price bracket
#   purge        src/Item.cpp QItem::PurgeAllQualities clears the bane
#   energy       src/Item.cpp Item::Damage: a WQ_ENERGY item is not harmed
#                (control: the same sword without the quality IS harmed)
#   hezrou       lib/mon4.irh hezrou EVICTIM(EV_DAMAGE): half damage from an
#                arrow (EItem) or a bow (EItem2), as from a sword
#   grant        src/Annot.cpp Resource::GrantGear: a drow with a hand
#                crossbow gains FT_EXOTIC_WEAPON, as a githzerai with a spiked
#                chain does
#   viewlist     src/Term.cpp ViewListPriorityMod: a mundane bow beside the
#                player sorts below a gem 3 squares off, as a sword does
#   kysul        lib/religion.irh Kysul EV_GODPULSE, run 2000 times: no gifted
#                bow or weapon is one the follower is not proficient with
#   augment      src/Skills.cpp Augment: a bow and a bolt are candidates and
#                reach the quality menu (screen dumps, key-driven)
#   showdamage   src/Term.cpp TextTerm::ShowDamage: a known Flaming bow prints
#                "+1d6 Fire" in the sidebar, as a Flaming sword does
#
# NOT OBSERVED, and why (bd inc-f38k):
#   - src/Player.cpp Map::DaysPassed loot weakening: it sits inside the spawn
#     loop, the monsters and their items are random, and a weakened bow is
#     indistinguishable from a mundane one. No real path gives an oracle.
#   - src/Term.cpp ShowDamage super-sneak branch: it reads WT_SUPER_SNEAK, and
#     no bow or missile in lib/ carries that flag, so no real item reaches it.
#
# THE ORACLE is INCURSION_WEAPONTYPE_PROBE (src/WeaponTypeProbe.cpp), run from
# Game::Play() (src/Main.cpp) on the loaded player. Its value picks a mode:
#   1 or unset-by-check  log cases, read from errors.log:
#                        "WEAPONTYPE_PROBE case=<c> item=<name> key=value ..."
#   kysul                the 2000 pulses, with tools/keys/weapon-types-kysul.keys
#   augment              tools/keys/weapon-types-augment.keys answers the menus
#   screen-bow/-sword    tools/keys/weapon-types-screen.keys dumps the sidebar
# A missing or unparsable line is a FAIL, never a pass.
#
# Usage: tools/check_weapon_types.sh                     (0 pass, 1 fail, 2 inconclusive)
#        tools/check_weapon_types.sh --prove-red <site>  (0 when that site goes red)
# A check_mutation proves one site per run, so --prove-red names the site. Each
# mutation puts back the base-code exact-type test at that one site:
#   magicweapon-istarget magicweapon-ratetarg brand-istarget brand-ratetarg
#   brand-magichit price purge energy hezrou grant viewlist kysul
#   augment-filter augment-selector showdamage
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
SEED=1
export INCURSION_LOAD=tools/fixtures/chars/orc-mage-seed4-gate.sav

SITE="${CHECK_ARGS[0]:-}"

# declare <site> <file>, then the original text, a line holding only "----",
# and the fixed text on stdin. Declared in an ordinary run so every one is
# guarded as appearing exactly once; --prove-red keeps only the named site.
declare_mutation() {
    local site="$1" file="$2" from to
    IFS= read -r -d '' from || true
    to="${from#*$'\n'----$'\n'}"
    from="${from%%$'\n'----$'\n'*}"
    to="${to%$'\n'}"
    [ "$CHECK_PROVE_RED" = 1 ] && [ "$SITE" != "$site" ] && return 0
    # "from" is the text now in the file; "to" is the base-code test.
    check_mutation "$file" "$from" "$to"
}

if [ "$CHECK_PROVE_RED" = 1 ]; then
    case " magicweapon-istarget magicweapon-ratetarg brand-istarget brand-ratetarg brand-magichit price purge energy hezrou grant viewlist kysul augment-filter augment-selector showdamage " in
        *" $SITE "*) ;;
        *) _check_die 2 "--prove-red needs one site name: see the usage in this file's header." ;;
    esac
fi

declare_mutation magicweapon-istarget lib/wspells.irh <<'EOF'
        if (ETarget->isType(T_WEAPON) || ETarget->isType(T_BOW))
----
        if (ETarget->isType(T_WEAPON))
EOF
declare_mutation magicweapon-ratetarg lib/wspells.irh <<'EOF'
        if (EItem->isType(T_WEAPON) || EItem->isType(T_BOW) ||
            EItem->isType(T_MISSILE))
----
        if (EItem->isType(T_WEAPON))
EOF
declare_mutation brand-istarget lib/pspells.irh <<'EOF'
          if (it->isType(T_WEAPON) || it->isType(T_BOW) || it->isType(T_MISSILE))
----
          if (it->isType(T_WEAPON) || it->isType(T_BOW))
EOF
declare_mutation brand-ratetarg lib/pspells.irh <<'EOF'
        if ((EItem->isType(T_WEAPON) || EItem->isType(T_BOW) ||
             EItem->isType(T_MISSILE)) && EItem->QualityOK(WQ_BANE))
----
        if (EItem->isType(T_WEAPON) && EItem->QualityOK(WQ_BANE))
EOF
declare_mutation brand-magichit lib/pspells.irh <<'EOF'
        if ((ETarget->isType(T_WEAPON) || ETarget->isType(T_BOW) ||
             ETarget->isType(T_MISSILE)) && ETarget->QualityOK(WQ_BANE))
----
        if (ETarget->isType(T_WEAPON) && ETarget->QualityOK(WQ_BANE))
EOF
declare_mutation price src/Social.cpp <<'EOF'
                isType(T_SHIELD) || isType(T_BOW) ||
                isType(T_MISSILE))
----
                isType(T_SHIELD) || isType(T_BOW))
EOF
declare_mutation purge src/Item.cpp <<'EOF'
    if (isType(T_WEAPON) || isType(T_BOW) || isType(T_MISSILE))
      SetBane(0);
----
    if (isType(T_WEAPON))
      SetBane(0);
EOF
declare_mutation energy src/Item.cpp <<'EOF'
    if ((isType(T_WEAPON) || isType(T_BOW) || isType(T_MISSILE)) &&
        HasQuality(WQ_ENERGY))
----
    if (isType(T_WEAPON) && HasQuality(WQ_ENERGY))
EOF
declare_mutation hezrou lib/mon4.irh <<'EOF'
        if ((GetHandle(EItem) != NULL &&
             (GetHandle(EItem)->isType(T_WEAPON) ||
              GetHandle(EItem)->isType(T_BOW) ||
              GetHandle(EItem)->isType(T_MISSILE))) ||
            (GetHandle(EItem2) != NULL &&
             (GetHandle(EItem2)->isType(T_WEAPON) ||
              GetHandle(EItem2)->isType(T_BOW) ||
              GetHandle(EItem2)->isType(T_MISSILE))))
----
        if ((GetHandle(EItem) != NULL &&
             GetHandle(EItem)->isType(T_WEAPON)) ||
            (GetHandle(EItem2) != NULL &&
             GetHandle(EItem2)->isType(T_WEAPON)))
EOF
declare_mutation grant src/Annot.cpp <<'EOF'
            else if ((TITEM(it->iID)->IType == T_WEAPON ||
                      TITEM(it->iID)->IType == T_BOW ||
                      TITEM(it->iID)->IType == T_MISSILE) &&
                     TITEM(it->iID)->Group & WG_EXOTIC) {
----
            else if (TITEM(it->iID)->IType == T_WEAPON &&
                     TITEM(it->iID)->Group & WG_EXOTIC) {
EOF
declare_mutation viewlist src/Term.cpp <<'EOF'
      if (t->isType(T_WEAPON) || t->isType(T_BOW) || t->isType(T_ARMOUR))
----
      if (t->isType(T_WEAPON) || t->isType(T_ARMOUR))
EOF
declare_mutation kysul lib/religion.irh <<'EOF'
        if (hGift->isType(T_WEAPON) || hGift->isType(T_BOW) ||
            hGift->isType(T_MISSILE) ||
            hGift->isType(T_ARMOUR) ||
----
        if (hGift->isType(T_WEAPON) ||
            hGift->isType(T_ARMOUR) ||
EOF
declare_mutation showdamage src/Term.cpp <<'EOF'
    if (w && (w->isType(T_WEAPON) || w->isType(T_BOW) ||
              w->isType(T_MISSILE))) {
----
    if (w && w->isType(T_WEAPON)) {
EOF
# Skills.cpp indents with tabs.
declare_mutation augment-filter src/Skills.cpp <<'EOF'
		if (weaponsOnly && !(it->isType(T_WEAPON) ||
			it->isType(T_BOW) ||
			it->isType(T_MISSILE) ||
			it->isType(T_ARMOUR) ||
----
		if (weaponsOnly && !(it->isType(T_WEAPON) ||
			it->isType(T_ARMOUR) ||
EOF
declare_mutation augment-selector src/Skills.cpp <<'EOF'
		else if (it->isType(T_WEAPON) || it->isType(T_BOW) ||
			it->isType(T_MISSILE)) {
----
		else if (it->isType(T_WEAPON)) {
EOF

FAIL=0
LOG=""
CLEAN=""
SEEN=""

_load_log() { # after a check_run: read this session's errors.log
    LOG="$CHECK_RUN/logs/errors.log"
    [ -f "$LOG" ] || _check_die 2 \
        "the run logged nothing at all. The probe reports through Error()," \
        "so an empty log means it never ran."
    # Drop indented backtrace blocks; they quote the message text.
    CLEAN="$(grep -v '^    ' "$LOG")"
}
_line() { # <case> <item> -> the probe line, or nothing
    printf '%s\n' "$CLEAN" | grep "WEAPONTYPE_PROBE case=$1 item=$2 " | head -1
}
_field() { # <line> <name> -> value, or nothing
    printf '%s\n' "$1" | grep -oE "(^| )$2=[^ ]+" | head -1 | sed -E "s/^ ?$2=//"
}
_need() { # <case> <item> <field> <wanted> <why>   (wanted ">=N" is a minimum)
    local line v
    line="$(_line "$1" "$2")"
    if [ -z "$line" ]; then
        echo "FAIL: no WEAPONTYPE_PROBE line for case=$1 item=$2."
        echo "      Is WeaponTypeProbe() still called from Game::Play()?"
        FAIL=1; return
    fi
    case "$SEEN" in *"$line"*) ;; *) SEEN="$SEEN$line"$'\n' ;; esac
    v="$(_field "$line" "$3")"
    if [ -z "$v" ]; then
        echo "FAIL: could not parse $3= from: $line"; FAIL=1; return
    fi
    case "$4" in
        '>='*) [ "$v" -ge "${4#>=}" ] 2>/dev/null && return ;;
        *)     [ "$v" = "$4" ] && return ;;
    esac
    echo "FAIL: $5 ($3=$v, wanted $4):"
    echo "      $line"
    FAIL=1
}

# --- run 1: the log cases ----------------------------------------------------
INCURSION_WEAPONTYPE_PROBE=1 check_run tools/keys/load-char-sheet.keys "$SEED"
_load_log
echo "specimen: $LOG"

_need magicweapon "short bow"      istarget 1 "Magic Weapon refuses a single short bow as a target"
_need magicweapon "short bow"      ratetarg 1 "Magic Weapon rates a short bow ABORT"
_need magicweapon "crossbow bolt"  ratetarg 1 "Magic Weapon rates a crossbow bolt ABORT"
_need magicweapon "long sword"     istarget 1 "control: Magic Weapon refuses a long sword"
_need magicweapon "long sword"     ratetarg 1 "control: Magic Weapon rates a long sword ABORT"
for it in "short bow" "crossbow bolt" "long sword"; do
    _need brand "$it" qualok   1 "setup: a bane quality is legal on a $it"
    _need brand "$it" istarget 1 "Brand of Hatred does not rate a $it as a target"
    _need brand "$it" ratetarg 1 "Brand of Hatred rates a $it ABORT"
    _need brand "$it" magichit 1 "Brand of Hatred puts no bane on a $it"
done
_need price "crossbow bolt" bracket hi "a +1 crossbow bolt is priced in the low bracket"
_need price "long sword"    bracket hi "control: a +1 long sword is not in the high bracket"
_need price "dagger"        bracket hi "control: a +1 dagger is not in the high bracket"
for it in "short bow" "crossbow bolt" "long sword"; do
    _need purge "$it" bane_after 0 "PurgeAllQualities leaves a bane on a $it"
    _need energy "$it" unhurt 1 "an energy $it takes damage"
done
_need energy "long sword-plain" unhurt 0 "control: a sword without WQ_ENERGY takes no damage, so the probe measures nothing"
for it in "sheaf arrow" "short bow" "long sword"; do
    _need hezrou "$it" dmg_out 10 "a hezrou does not halve slash/pierce damage from a $it"
done
_need grant "hand crossbow" exotic_feat 1 "an NPC given a hand crossbow gains no exotic proficiency"
_need grant "spiked chain"  exotic_feat 1 "control: an NPC given a spiked chain gains no exotic proficiency"
_need viewlist list listed  ">=3" "the probe offered fewer than 3 items to the view list"
_need viewlist list gem_before_sword 1 "control: a mundane sword does not sort below a gem 3 squares off"
_need viewlist list gem_before_bow   1 "a mundane bow does not sort below a gem 3 squares off"

# --- run 2: Kysul's gift ------------------------------------------------------
INCURSION_WEAPONTYPE_PROBE=kysul check_run tools/keys/weapon-types-kysul.keys "$SEED"
_load_log
_need kysul gift weapon_gifts         ">=1" "setup: Kysul gifted no weapon in 2000 pulses, so the probe measures nothing"
_need kysul gift notprof_weapon_gifts 0     "control: Kysul gifted a weapon its follower cannot use"
_need kysul gift notprof_bow_gifts    0     "Kysul gifted a bow or missile its follower cannot use"

# --- run 3: Augment's menus ---------------------------------------------------
INCURSION_WEAPONTYPE_PROBE=augment check_run tools/keys/weapon-types-augment.keys "$SEED"
check_screens '*augment-1-short-bow'
check_expect "Pick a quality to imbue" "Augment offers a short bow and reaches its quality menu"
check_screens '*augment-2-crossbow-bolt'
check_expect "Pick a quality to imbue" "Augment offers a crossbow bolt and reaches its quality menu"
check_screens '*augment-3-long-sword'
check_expect "Pick a quality to imbue" "control: Augment offers a long sword and reaches its quality menu"

# --- runs 4 and 5: the sidebar's ShowDamage lines -----------------------------
INCURSION_WEAPONTYPE_PROBE=screen-bow check_run tools/keys/weapon-types-screen.keys "$SEED"
_load_log
_need screen "short bow" wielded 1 "setup: the short bow was not wielded"
check_screens '*sidebar'
check_expect "Mod:Archery" "setup: the sidebar shows the bow in archery mode"
check_expect "+1d6 Fire" "the sidebar shows a known Flaming bow's fire damage"
INCURSION_WEAPONTYPE_PROBE=screen-sword check_run tools/keys/weapon-types-screen.keys "$SEED"
_load_log
_need screen "long sword" wielded 1 "setup: the long sword was not wielded"
check_screens '*sidebar'
check_expect "Mod:Melee" "setup: the sidebar shows the sword in melee mode"
check_expect "+1d6 Fire" "control: the sidebar shows a known Flaming sword's fire damage"

echo
echo "--- what the probe logged ---"
printf '%s' "$SEEN"

if [ "$FAIL" -ne 0 ] || [ "$CHECK_FAIL" -ne 0 ]; then
    echo
    echo "FAIL: bows and ammunition are not treated as weapons everywhere."
    exit 1
fi
echo
echo "PASS: bows and ammunition are treated as weapons."
exit 0
