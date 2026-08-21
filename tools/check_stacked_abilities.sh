#!/bin/bash
# Regression check for the stacking rule in Character::CorrectStackedAbilities
# (src/Create.cpp), which covers bd inc-tek.8.3 finding PA-03-F21 and the
# general defect behind it.
#
# WHAT WAS WRONG. Six classes grant Uncanny Dodge and four grant Sneak Attack,
# and their descriptions say that levels of the ability from the other classes
# stack. A Grants: line counts only its own class's levels, so a character who
# split his levels served every class's waiting period instead of one.
#
# THE ORACLE is the sheet's Special Abilities block. src/Sheet.cpp:580-582
# prints "Improved Uncanny Dodge" when the number is 4 or more and plain
# "Uncanny Dodge" below that, so the printed name reads the number out.
# Sneak Attack prints its dice directly.
#
# THE FIVE CHARACTERS, and what each one is for:
#
#   Rogue 6                      INVARIANT. One class, so the rule must land
#     dodge-rogue6.keys          exactly where the old grant lines did:
#                                Uncanny Dodge 4, Sneak Attack +3d6. If this
#                                moves, the rule is wrong for everybody.
#
#   Barbarian 3 / Rogue 3        THE MEASUREMENT. Both classes carry the
#     dodge-barb-rogue.keys      sentence "Levels of this ability from the
#                                barbarian and rogue classes stack"
#                                (lib/classes.irh:118, :2395). He held 3
#                                before -- less than the Rogue 6 above, off
#                                the same six levels -- and holds 5 now.
#
#   Human Bard 7 / Assassin 4    THE OTHER DIRECTION. His class description
#     assassin-bard.keys         gives Uncanny Dodge at the rogue's rate on
#                                the summed level, which is 4 - 2 = 2. He
#                                held 4 before, because nothing withheld the
#                                rogue's first two levels from a character
#                                who was never a rogue.
#
#   Elf Rogue 7 / Assassin 3     THE PARITY CASE. Both level counts are odd,
#     assassin-rogue7.keys       which is the only shape where the double
#                                rounding shows. Seven rogue levels rounded
#                                up to four dice and three assassin levels
#                                rounded up to two, so he held six. Ten
#                                levels at one die per two, with the first
#                                die given once, is five and a half.
#
#   Elf Rogue 5 / Assassin 2     CONTROL. Promised and given 5 either way,
#     prestige-assassin.keys     and Sneak Attack +4d6 either way. Without
#                                him the test would also pass on a build that
#                                had simply broken the abilities.
#
# Measured on builds differing only in src/Create.cpp, inc/Creature.h and
# lib/prestige.irh:
#                          before               after
#   Rogue 6                Improved / +3d6      Improved / +3d6
#   Barbarian 3 / Rogue 3  Uncanny Dodge        Improved Uncanny Dodge
#   Bard 7 / Assassin 4    Improved             Uncanny Dodge
#   Rogue 7 / Assassin 3   +6d6                 +5d6
#   Rogue 5 / Assassin 2   Improved / +4d6      Improved / +4d6
#
# Tracking stacks the same way and is measured by
# tools/check_huntsman_live.sh, because that script already builds the only
# character who holds two classes that grant it.
#
# Usage: tools/check_stacked_abilities.sh      (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

fail=0

# $1 key script, $2 dump basename, $3 guard string, $4 what the sheet must
# say, $5 what it must NOT say ("-" for nothing)
check_sheet () {
    local keys="$1" base="$2" guard="$3" want="$4" deny="$5"
    local out run dump
    out="$(tools/headless.sh "$keys" "$SEED" 2>&1)"
    run="$(echo "$out" | awk '/^run:/ {print $2}')"
    dump="$run/logs/$base.txt"

    if [ ! -f "$dump" ]; then
        echo "FAIL: $guard -- the character dump was never written to $dump"
        echo "$out" | tail -6
        fail=1; return
    fi
    # Guard first. A key script that stops producing the character must read
    # as rotted, not as a passing test.
    if ! grep -q "$guard" "$dump"; then
        echo "INCONCLUSIVE: no \"$guard\" on the sheet, so $keys has rotted."
        echo "              Nothing was measured."
        fail=1; return
    fi
    if [ "$deny" != "-" ] && grep -q "^  $deny\$" "$dump"; then
        echo "FAIL: $guard has \"$deny\" and should not"
        fail=1; return
    fi
    if ! grep -q "^  $want\$" "$dump"; then
        echo "FAIL: $guard does not have \"$want\""
        grep -n -i "uncanny\|sneak" "$dump" | sed 's/^/      /'
        fail=1; return
    fi
    echo "  ok: $guard has \"$want\""
}

# The invariant, first: one class must be untouched by the rule.
check_sheet tools/keys/dodge-rogue6.keys      rg6   "Rogue 6" \
            "Improved Uncanny Dodge" "-"
check_sheet tools/keys/dodge-rogue6.keys      rg6   "Rogue 6" \
            "Sneak Attack +3d6" "-"
# The measurement.
check_sheet tools/keys/dodge-barb-rogue.keys  br3   "Barbarian 3" \
            "Improved Uncanny Dodge" "-"
# The other direction.
check_sheet tools/keys/assassin-bard.keys     assnb "Assassin 4" \
            "Uncanny Dodge" "Improved Uncanny Dodge"
# The parity case: two odd level counts, each rounded up on its own before.
check_sheet tools/keys/assassin-rogue7.keys   assn7 "Assassin 3" \
            "Sneak Attack +5d6" "Sneak Attack +6d6"
# The control.
check_sheet tools/keys/prestige-assassin.keys assn  "Assassin 2" \
            "Improved Uncanny Dodge" "-"
check_sheet tools/keys/prestige-assassin.keys assn  "Assassin 2" \
            "Sneak Attack +4d6" "-"

[ "$fail" = 0 ] && echo "PASS: stacking abilities add across classes and charge one wait" \
                || echo "FAIL: tools/check_stacked_abilities.sh"
exit "$fail"
