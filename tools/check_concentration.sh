#!/bin/bash
# gate: live
# Does a maintained spell hold its caster in concentration, and do the rules
# that follow from that hold? (bd inc-59lq)
#
# WHAT IT DEFENDS. A caster who casts a spell on the concentration table
# (src/Concentration.cpp: Phantasmal Force, Improved Phantasmal Force, Spectral
# Force, ..., Hypnotic Pattern, Telekinesis, Wall of Fire) gains a CONCENTRATING
# status. While it holds, the caster cannot cast, invoke or attack. Stopping
# from the Cancel menu ends the spell's effects after the spell's tail. Damage
# forces a Concentration check at DC 10 + damage + spell level. A concentrating
# monster keeps concentrating only while the spell still reaches an enemy and it
# is above half its hit points.
#
# THE ORACLE is two things the game writes: the probe lines that
# INCURSION_CONCENT_PROBE=1 sends to the run's logs/errors.log through Error()
# (the same channel INCURSION_DMGPOST_PROBE uses),
#
#   CONCENT start   spell=<S> cap=<units> tail=<units>
#   CONCENT stop    spell=<S> reason=cancel|cap|gone tail=<units>
#   CONCENT block   event=cast|invoke|attack|item spell=<S>
#   CONCENT check   spell=<S> dc=<DC> result=pass|fail
#   CONCENT monster=<name> spell=<S> decision=keep|stop affects=0|1 hp=<c>/<m>
#
# and the screen dumps (status line "Concentrating", the refusal message, the
# illusory monitor in "Things in View", the HP on the bottom status row).
#
# THE FIXTURE is the frozen elf mage (tools/fixtures/chars/
# elf-mage-illusions-seed1.sav), whose illusion spells are INNATE, so a player
# cast reaches Creature::Invoke and not Creature::Cast. The refused cast
# therefore reports event=invoke; event=cast is the same gate on the other path.
#
# FIVE SESSIONS:
#   core     start, Cancel at tail 0                    (assertions 1, 4)
#   block    a second cast while concentrating          (assertion 2)
#   damage   refused attack, DC against damage taken   (assertions 3, 6)
#   tail     Improved Phantasmal Force's tail           (assertion 5)
#   monster  two concentrating monsters                 (assertion 7)
#
# NO MONSTER CASTS A TABLE SPELL ON CUE. Magic::Illusion returns early for a
# non-player (src/Effects.cpp), and the lillend, chasme, vrock, cornugon and
# efreeti that cast Hypnotic Pattern, Wall of Fire or Telekinesis choose their
# spell by AI, so no seed or key script can wait for one. The monster session
# uses src/ConcentMonsterProbe.cpp (INCURSION_CONCENT_MONSTER_PROBE=1): it
# gives two giant rats Telekinesis and the CONCENTRATING row that
# StartConcentration would have granted, one at 100/100 hit points and one at
# 40/100, and runs each one's REAL Monster::ChooseAction. The decision under
# test is the game's; only the granting of the status is simulated.
#
# Usage: tools/check_concentration.sh [--prove-red]
# Exit: 0 all pass, 1 any fail, 2 could not measure.

. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
export INCURSION_LOAD=tools/fixtures/chars/elf-mage-illusions-seed1.sav
export INCURSION_CONCENT_PROBE=1

# The mutations. --prove-red performs the FIRST; the other two are proved by
# hand the same way (docs/VERIFICATION.md step 2) and are declared here so an
# ordinary run still proves each site exists exactly once.
check_mutation src/Concentration.cpp \
    'dc = 10 + dmg + (eID ? TEFF(eID)->Level : 0);' \
    'dc = 12 + dmg + (eID ? TEFF(eID)->Level : 0);'
check_mutation src/Concentration.cpp \
    'bool Creature::ConcentrationBlocks(const char *kind) {
    rID eID;' \
    'bool Creature::ConcentrationBlocks(const char *kind) {
    rID eID;
    return false;'
check_mutation src/Skills.cpp \
    'StopConcentration(concSpells[c - 2048], true);' \
    '(void)concSpells;'

# log_expect <label> <ERE> <what it proves>: the session's errors.log has a
# line matching the pattern. Prints the line it found as the evidence.
log_expect() {
    local label="$1" pat="$2" why="$3" log hit
    log="$CHECK_RUN/logs/errors.log"
    hit="$(grep -E -- "$pat" "$log" 2>/dev/null | head -1)"
    if [ -n "$hit" ]; then
        CHECK_EXPECTS=$((CHECK_EXPECTS + 1))
        printf '  ok    %s: %s\n        evidence: %s\n' "$label" "$why" "${hit#* }"
        return 0
    fi
    printf '  FAIL  %s: %s\n        no errors.log line matches: %s\n' \
        "$label" "$why" "$pat"
    CHECK_FAIL=1
    return 1
}

verdict() { # <label> <status> <ok text> <fail text>
    if [ "$2" = 0 ]; then
        CHECK_EXPECTS=$((CHECK_EXPECTS + 1))
        printf '  ok    %s: %s\n' "$1" "$3"
    else
        printf '  FAIL  %s: %s\n' "$1" "$4"
        CHECK_FAIL=1
    fi
}

# ---------------------------------------------------------------------------
echo "== core session"
check_run tools/keys/concentration-core.keys 1

echo "-- 1 START"
log_expect START 'CONCENT start spell=Phantasmal Force cap=[1-9][0-9]* tail=0' \
    "casting Phantasmal Force grants concentration, tail 0"
check_screens '*-started'
check_expect "Concentrating" "the status line says the caster is concentrating"

echo "-- 4 CANCEL+TAIL0"
check_screens '*-cancel-menu'
check_expect "R illusory" "the illusion exists when the Cancel menu opens"
check_expect "Stop concentrating on" "the Cancel menu offers the entry"
log_expect CANCEL 'CONCENT stop spell=Phantasmal Force reason=cancel tail=0' \
    "the entry stops concentration with tail 0"
check_screens '*-cancelled'
check_reject "R illusory" "the illusion is gone at once, not after a tail"
check_reject "Concentrating" "the status line no longer says concentrating"

# ---------------------------------------------------------------------------
echo "== block session"
check_run tools/keys/concentration-block.keys 1

echo "-- 2 BLOCK-CAST"
log_expect BLOCK-CAST 'CONCENT block event=(cast|invoke) spell=Phantasmal Force' \
    "a second cast is refused at the cast/invoke gate"
check_screens '*-block-cast'
check_expect "You cannot do that while concentrating on" \
    "the refusal reaches the player"

# ---------------------------------------------------------------------------
echo "== damage session"
check_run tools/keys/concentration-damage.keys 1

echo "-- 3 BLOCK-ATTACK"
log_expect BLOCK-ATTACK 'CONCENT block event=attack spell=Phantasmal Force' \
    "bumping the adjacent goblin is refused at the attack gate"
check_screens '*-attack'
check_expect "You cannot do that while concentrating on" \
    "the refusal reaches the player"

echo "-- 6 DAMAGE-CHECK"
DMG_VERDICT="$(python3 -I - "$CHECK_RUN" <<'PY'
import glob, re, sys
run = sys.argv[1]
# HP on the bottom status row of every dump, in dump order.
hp = []
for f in sorted(glob.glob(run + "/logs/screens/*.txt")):
    m = None
    for line in open(f, errors="replace"):
        m = re.search(r"HP:(\d+)/(\d+)", line) or m
    if m:
        hp.append((f.rsplit("/", 1)[1], int(m.group(1))))
drop = None
for (a, ha), (b, hb) in zip(hp, hp[1:]):
    if hb < ha:
        drop = (ha - hb, a, b, ha, hb)
        break
checks = [l for l in open(run + "/logs/errors.log", errors="replace")
          if "CONCENT check" in l]
if drop is None:
    print("2 no dump shows the caster losing hit points; the goblin never hit")
elif not checks:
    print("1 the caster lost %d hit points (%s -> %s) and no CONCENT check "
          "line was logged" % (drop[0], drop[1], drop[2]))
else:
    m = re.search(r"spell=(.+?) dc=(\d+) result=(\w+)", checks[0])
    spell, dc, res = m.group(1), int(m.group(2)), m.group(3)
    level = 1   # Phantasmal Force is a level 1 spell (check_illusion_flags.sh)
    want = 10 + drop[0] + level
    line = checks[0].strip().split("  ", 1)[-1]
    if dc == want:
        print("0 %s ; HP %d -> %d between %s and %s = %d damage; "
              "10 + %d + level %d = %d" % (line, drop[3], drop[4], drop[1],
              drop[2], drop[0], drop[0], level, want))
    else:
        print("1 %s ; HP %d -> %d = %d damage, so dc should be 10 + %d + %d "
              "= %d, not %d" % (line, drop[3], drop[4], drop[0], drop[0],
              level, want, dc))
PY
)"
verdict DAMAGE-CHECK "${DMG_VERDICT%% *}" \
    "the first check's dc is 10 + damage taken + spell level: ${DMG_VERDICT#* }" \
    "${DMG_VERDICT#* }"

# ---------------------------------------------------------------------------
echo "== tail session"
check_run tools/keys/concentration-tail.keys 1

echo "-- 5 TAIL"
log_expect TAIL-START 'CONCENT start spell=Improved Phantasmal Force cap=[1-9][0-9]* tail=1' \
    "Improved Phantasmal Force carries a tail of 1 unit"
log_expect TAIL-STOP 'CONCENT stop spell=Improved Phantasmal Force reason=cancel tail=1' \
    "the Cancel applies that tail"
TAIL_VERDICT="$(python3 -I - "$CHECK_RUN" <<'PY'
import glob, re, sys
run = sys.argv[1]
rows = []   # (label, turn, illusion present)
for f in sorted(glob.glob(run + "/logs/screens/*.txt")):
    txt = open(f, errors="replace").read()
    m = re.search(r"=== screen \d+ (\S+)\s+key \d+\s+mode \d+\s+turn (\d+)", txt)
    if m:
        rows.append((m.group(1), int(m.group(2)), "R illusory" in txt))
by = {r[0]: r for r in rows}
if "cancelled" not in by:
    print("1 no dump after the Cancel")
    sys.exit()
t0 = by["cancelled"][1]
if not by["cancelled"][2]:
    print("1 the illusion was already gone at the Cancel (turn %d)" % t0)
    sys.exit()
waits = [r for r in rows if re.fullmatch(r"w\d+", r[0])]
gone = next((r for r in waits if not r[2]), None)
first = waits[0] if waits else None
if first is None or not first[2]:
    print("1 the illusion was gone at the first wait; the tail did nothing")
elif gone is None:
    print("1 the illusion still existed %d ticks after the Cancel" %
          (waits[-1][1] - t0))
elif gone[1] - t0 > 80:
    print("1 the illusion lasted %d ticks after the Cancel, over the 80 "
          "tick margin" % (gone[1] - t0))
else:
    last = [r for r in waits if r[2]][-1]
    print("0 Cancel at turn %d: present at +%d ticks, gone at +%d ticks (%s)"
          % (t0, last[1] - t0, gone[1] - t0, gone[0]))
PY
)"
verdict TAIL "${TAIL_VERDICT%% *}" \
    "the illusion outlives the Cancel, then ends within 80 ticks: ${TAIL_VERDICT#* }" \
    "${TAIL_VERDICT#* }"

# ---------------------------------------------------------------------------
echo "== monster session"
export INCURSION_CONCENT_MONSTER_PROBE=1
check_run tools/keys/concentration-monster.keys 1

echo "-- 7 MONSTER"
log_expect MONSTER-KEEP \
    'CONCENT monster=giant rat spell=Telekinesis decision=keep affects=1 hp=100/100' \
    "a monster above half hit points whose spell reaches an enemy keeps concentrating"
log_expect MONSTER-STOP \
    'CONCENT monster=giant rat spell=Telekinesis decision=stop affects=1 hp=40/100' \
    "the same monster below half hit points lets the spell go"
log_expect MONSTER-STOP-APPLIED \
    'CONCENT stop spell=Telekinesis reason=cancel tail=0' \
    "and the game stops its concentration"

check_done "concentration starts, blocks, cancels, tails, checks and decides as designed"
