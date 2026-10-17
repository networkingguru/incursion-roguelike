#!/bin/bash
# gate: live
# inc-4999 revision 6: loading a pre-revision-6 save gives every spell at most
# one source, and every known spell the pending bit of the source it is held
# from, so the first rest changes nothing.
#
# WHAT IS BEING GUARDED. Before revision 6 a kind bit (SP_ARCANE / SP_DIVINE /
# SP_PRIMAL / SP_BARDIC) meant "this spell is on one of your class lists":
# Character::CalcSpellAccess() stamped every spell of every list, learned or
# not. Revision 6 gives the bit a different meaning ("HELD from that source")
# and tracks pending per source (SP_PENDING arcane, SP_PEND_DIV divine,
# SP_PEND_PRI primal; bardic has none). An old save therefore reads as if every
# list spell were held. Player::MigrateSpellFlagsRev6() runs once on load to
# fix that.
#
# THE ORACLE is INCURSION_SPELLFLAG_PROBE (src/Create.cpp, Player::
# SpellFlagProbe), which reports one errors.log line per spell carrying
# SP_KNOWN or any kind or pending bit:
#
#   SPELLFLAG_PROBE <spell> known=<0|1> pending=<0|1> granted=<0|1> \
#       domain=<0|1> arcane=<0|1> divine=<0|1> primal=<0|1> bardic=<0|1> \
#       pend_div=<0|1> pend_pri=<0|1>
#   SPELLFLAG_PROBE migrated=<0|1> rev=<file revision>
#
# TWO RUNS.
#
#   Mage  tools/fixtures/chars/orc-mage-seed1-opt0822.sav (an IS1.3 save
#         written with the OLD meaning). The migration must leave no spell a
#         kind bit with known=0, and every known, non-granted, non-domain spell
#         must carry exactly one kind bit and the pending bit of its source. A
#         granted spell keeps its one kind bit but is left with no pending bit
#         (it is not re-picked at a rest), and a domain spell is divine with no
#         pending bit either -- the mage fixture has neither, so the check
#         counts them only to exclude them from the pending assertion.
#
#   Priest tools/fixtures/chars/orc-priest-seed4-gate.sav (also IS1.3). Bead
#         inc-4999, owner ruling of 2026-10-17: the class grants a new character
#         gets through GainSpell carry SP_GRANTED, but a pre-revision-5 save
#         never had it, so MigrateSpellFlagsRev6 restores it for a spell the
#         character still holds. Bless and Cure Light Wounds must come back
#         granted=1 divine=1 pend_div=0; every other known, non-granted,
#         non-domain spell keeps exactly one kind bit and its pending bit.
#         (The priest fixture is the one that exercises this: it holds domain
#         spells -- True Strike, Read Magic, Sleep -- which the new domain=
#         field lets the pending assertion exclude.)
#
# PROVED RED with --prove-red (docs/VERIFICATION.md step 2). TWO mutations are
# declared, and --prove-red performs the FIRST, so a flag chooses the order:
#
#   --prove-red            the "clear kind bits on unknown spells" loop of
#                          Player::MigrateSpellFlagsRev6 is removed; spells
#                          nobody learned keep the kind bit the old build
#                          stamped on them, and slice 1's first assertion fails.
#   --prove-red --grants  the class-grant restore added for inc-4999 is
#                          removed; Bless and Cure Light Wounds then load with
#                          granted=0, and the priest case fails. Both are run
#                          and recorded in the report.
#
# Usage: tools/check_spellflag_migrate6.sh [--prove-red] [--grants]
#        (0 pass, 1 fail, 2 inconclusive)
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat

FIXTURE=tools/fixtures/chars/orc-mage-seed1-opt0822.sav
SEED=1
PRIEST=tools/fixtures/chars/orc-priest-seed4-gate.sav
PRIEST_SEED=4

# --grants picks which of the two mutations --prove-red performs first. The
# library removes --prove-red from CHECK_ARGS but leaves this flag, and the
# inner re-run carries CHECK_ARGS, so the inner run reads the same choice.
GRANTS_FIRST=0
for _arg in "$@"; do
    [ "$_arg" = "--grants" ] && GRANTS_FIRST=1
done
unset _arg

# Both mutations this check defends, from Player::MigrateSpellFlagsRev6
# (src/Create.cpp). Declared before any run so --prove-red intercepts here,
# before the (build-needing) measurement runs.
_mut_unknown_clear() {
    check_mutation src/Create.cpp \
'    for (i = 0; i <= MAX_SPELLS; i++) {
        if (Spells[i] & (SP_KNOWN | SP_INHERENT))
            continue;
        Spells[i] &= ~(SP_ARCANE | SP_DIVINE | SP_PRIMAL | SP_BARDIC
            | SP_PENDING | SP_PEND_DIV | SP_PEND_PRI);
    }' \
'    /* mutation: unknown-spell kind-bit clear disabled */'
}
_mut_grant_restore() {
    check_mutation src/Create.cpp \
'        for (g = 0; g < 4; g++) {
            if (!grants[g].grant)
                continue;
            sp = FIND(grants[g].name);
            if (!sp)
                continue;
            sn = theGame->SpellNum(sp);
            if (sn <= 0 || sn > MAX_SPELLS)
                continue;
            if (Spells[sn] & SP_KNOWN)
                Spells[sn] |= SP_GRANTED | grants[g].kind;
        }' \
'        /* mutation: the class-grant restore disabled */'
}
if [ "$GRANTS_FIRST" = 1 ]; then
    _mut_grant_restore
    _mut_unknown_clear
else
    _mut_unknown_clear
    _mut_grant_restore
fi

[ -f "$FIXTURE" ] || _check_die 2 \
    "no $FIXTURE, so there is no pre-revision-6 save to migrate."

REV="$(dd if="$FIXTURE" bs=1 skip=4 count=5 2>/dev/null | sed 's/^IS1\.//')"
[ -n "$REV" ] || _check_die 2 \
    "$FIXTURE does not carry an IS1.<n> stamp, so its revision is unknown."

export INCURSION_SPELLFLAG_PROBE=1
export INCURSION_LOAD="$FIXTURE"
check_run tools/keys/spellflag-migrate.keys "$SEED"
RUN="$CHECK_RUN"
LOG="$RUN/logs/errors.log"
[ -f "$LOG" ] || _check_die 2 \
    "the run logged nothing. The probe reports through Error(), so an empty" \
    "log means it never ran."

CLEAN="$(grep -v '^    ' "$LOG")"

# The per-spell probe lines, stripped of their timestamp.
spells() { printf '%s\n' "$1" | grep -E 'SPELLFLAG_PROBE [A-Za-z].* known=' \
             | sed 's/^[0-9-]* [0-9:]*  //'; }
# The 0/1 the named field carries.
bit() { printf '%s' "$1" | grep -oE "$2=[01]" | sed "s/$2=//"; }

SUM="$(printf '%s\n' "$CLEAN" | grep 'SPELLFLAG_PROBE migrated=' | head -1)"
FAIL=0
if [ -z "$SUM" ]; then
    echo "FAIL: the run logged no SPELLFLAG_PROBE summary line."
    FAIL=1
elif ! printf '%s\n' "$SUM" | grep -q "migrated=1 rev=$REV\$"; then
    echo "FAIL: the IS1.$REV fixture must migrate; the summary reads:"
    echo "      $SUM"
    FAIL=1
fi

SPELLS="$(spells "$CLEAN")"
if [ -z "$SPELLS" ]; then
    echo "FAIL: the run logged no per-spell SPELLFLAG_PROBE lines."
    FAIL=1
fi

# check_migrated <label> <per-spell lines> -- the invariants every migrated
# fixture must hold. Sets NKNOWN and NBIT.
check_migrated() {
    local label="$1" sp="$2" line
    NKNOWN=0
    NBIT=0
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        local known grant dom arc div pri bar pend pdiv ppri
        known="$(bit "$line" known)"
        grant="$(bit "$line" granted)"
        dom="$(bit "$line" domain)"
        arc="$(bit "$line" arcane)"
        div="$(bit "$line" divine)"
        pri="$(bit "$line" primal)"
        bar="$(bit "$line" bardic)"
        pend="$(bit "$line" pending)"
        pdiv="$(bit "$line" pend_div)"
        ppri="$(bit "$line" pend_pri)"

        local nkindbits=0
        for b in "$arc" "$div" "$pri" "$bar"; do
            [ "$b" = "1" ] && nkindbits=$((nkindbits + 1))
        done

        # (1) A kind bit on a spell the character does not hold is the old
        #     build's writing, un-migrated.
        if [ "$known" = "0" ] && [ "$nkindbits" != "0" ]; then
            echo "FAIL $label: a source bit stands on a spell that is not held:"
            echo "      $line"
            FAIL=1
        fi

        if [ "$known" = "1" ]; then
            NKNOWN=$((NKNOWN + 1))
            # (2) A held spell is held from exactly one source.
            if [ "$nkindbits" != "1" ]; then
                echo "FAIL $label: a known spell does not carry exactly one source bit:"
                echo "      $line"
                FAIL=1
            fi
            # (3) A known, non-granted, non-domain spell is left pending on its
            #     own source, so the first rest changes nothing. A granted spell
            #     takes no slot and re-picks nothing, and a domain spell is
            #     fixed, so neither keeps a pending bit.
            if [ "$grant" != "1" ] && [ "$dom" != "1" ]; then
                NBIT=$((NBIT + 1))
                local npend=0
                for b in "$pend" "$pdiv" "$ppri"; do
                    [ "$b" = "1" ] && npend=$((npend + 1))
                done
                if [ "$npend" != "1" ]; then
                    echo "FAIL $label: a known, non-granted, non-domain spell is"
                    echo "      not pending on exactly one source:"
                    echo "      $line"
                    FAIL=1
                fi
                # The pending bit must match the source, not be arbitrary.
                local want_pend want_div want_pri
                case "$arc$div$pri$bar" in
                    1000) want_pend=1; want_div=0; want_pri=0 ;;
                    0100) want_pend=0; want_div=1; want_pri=0 ;;
                    0010) want_pend=0; want_div=0; want_pri=1 ;;
                    0001) want_pend=0; want_div=0; want_pri=0 ;;
                    *)     want_pend=-1; want_div=-1; want_pri=-1 ;;
                esac
                if [ "$want_pend" = "-1" ]; then
                    echo "FAIL $label: a known spell has no single source to be"
                    echo "      pending on:"
                    echo "      $line"
                    FAIL=1
                elif [ "$pend" != "$want_pend" ] || [ "$pdiv" != "$want_div" ] \
                    || [ "$ppri" != "$want_pri" ]; then
                    echo "FAIL $label: the pending bit does not match the held source:"
                    echo "      $line"
                    FAIL=1
                fi
            fi
        fi
    done <<< "$sp"

    # (4) The run reached the state the assertions are about.
    if [ "$NKNOWN" -eq 0 ]; then
        echo "FAIL $label: the run logged no known spell, so nothing was proven."
        FAIL=1
    fi
}

check_migrated mage "$SPELLS"
MAGE_KNOWN=$NKNOWN
MAGE_BIT=$NBIT

# ---------------------------------------------------------------------------
# The priest fixture: its class grants must come back as locked grants.
[ -f "$PRIEST" ] || _check_die 2 \
    "no $PRIEST, so there is no pre-revision-6 priest save to migrate."

PREV="$(dd if="$PRIEST" bs=1 skip=4 count=5 2>/dev/null | sed 's/^IS1\.//')"
[ -n "$PREV" ] || _check_die 2 \
    "$PRIEST does not carry an IS1.<n> stamp, so its revision is unknown."

export INCURSION_LOAD="$PRIEST"
check_run tools/keys/spellflag-migrate.keys "$PRIEST_SEED"
RUN_P="$CHECK_RUN"
LOG_P="$RUN_P/logs/errors.log"
[ -f "$LOG_P" ] || _check_die 2 \
    "the priest run logged nothing. The probe reports through Error(), so an" \
    "empty log means it never ran."

CLEAN_P="$(grep -v '^    ' "$LOG_P")"
P_SUM="$(printf '%s\n' "$CLEAN_P" | grep 'SPELLFLAG_PROBE migrated=' | head -1)"
if [ -z "$P_SUM" ]; then
    echo "FAIL: the priest run logged no SPELLFLAG_PROBE summary line."
    FAIL=1
elif ! printf '%s\n' "$P_SUM" | grep -q "migrated=1 rev=$PREV\$"; then
    echo "FAIL: the IS1.$PREV priest fixture must migrate; its summary reads:"
    echo "      $P_SUM"
    FAIL=1
fi

P_SPELLS="$(spells "$CLEAN_P")"
if [ -z "$P_SPELLS" ]; then
    echo "FAIL: the priest run logged no per-spell SPELLFLAG_PROBE lines."
    FAIL=1
fi

check_migrated priest "$P_SPELLS"
PRIEST_KNOWN=$NKNOWN
PRIEST_BIT=$NBIT

# The class grants: Bless and Cure Light Wounds come back locked, divine, and
# using no slot (no pending bit). A mutation that drops the grant-restore code
# leaves granted=0 here, which is what --prove-red --grants proves below.
for grant in Bless Cure_Light_Wounds; do
    gl="$(printf '%s\n' "$P_SPELLS" | grep -E "SPELLFLAG_PROBE $grant known=" | head -1)"
    if [ -z "$gl" ]; then
        echo "FAIL: the priest fixture holds $grant but the probe logged no line."
        FAIL=1
        continue
    fi
    if [ "$(bit "$gl" granted)" != "1" ] \
        || [ "$(bit "$gl" divine)" != "1" ] \
        || [ "$(bit "$gl" pend_div)" != "0" ]; then
        echo "FAIL: $grant must be a locked divine grant with no pending bit:"
        echo "      $gl"
        FAIL=1
    fi
done

echo
echo "--- migrated IS1.$REV mage fixture ---"
printf '%s\n' "$SPELLS"; printf '%s\n' "$SUM"
echo "--- migrated IS1.$PREV priest fixture ---"
printf '%s\n' "$P_SPELLS"; printf '%s\n' "$P_SUM"
echo "specimen mage:   $LOG"
echo "specimen priest: $LOG_P"

if [ "$FAIL" -ne 0 ]; then
    echo
    echo "FAIL: a migrated spell carries a source bit it is not held from, a"
    echo "      held spell carries the wrong number of source or pending bits, or"
    echo "      a class grant did not come back locked (inc-4999 revision 6)."
    exit 1
fi

echo
echo "PASS: both IS1.$REV fixtures migrated once (migrated=1 rev=$REV); no spell"
echo "      carries a source bit without being held, every known non-granted,"
echo "      non-domain spell carries exactly one source bit and that source's"
echo "      pending bit (mage $MAGE_KNOWN known/$MAGE_BIT pending, priest"
echo "      $PRIEST_KNOWN known/$PRIEST_BIT pending), and the priest's Bless and"
echo "      Cure Light Wounds came back as locked divine grants."
exit 0
