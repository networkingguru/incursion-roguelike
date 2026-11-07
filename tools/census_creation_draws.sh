#!/bin/bash
# Census of the random draws character creation makes (bead inc-10v7f, phase 0).
#
# Walks one character per (race, class) pair through the real creation screens
# under tools/headless.sh, with src/DrawCensus.cpp logging every random(),
# Dice::Roll and srand() made inside Player::Create and Player::AdvanceLevel
# (set INCURSION_DRAW_CENSUS=<file>). Race and class names come from the game's
# own menus, read off a screen dump, not from a list kept here.
#
# Usage: tools/census_creation_draws.sh            (needs BACKEND=posix build)
#   CENSUS_SEED=4242        seed for every walk
#   CENSUS_BIN=<binary>     binary under test (default ./incursion-headless)
#   CENSUS_ONLY=<substring> run only pairs/walks whose name contains it
#
# Writes logs/census/draws.tsv and logs/census/summary.txt. A pair the game
# refuses ("You do not meet the requirements") is counted as refused.
#
# fact: seed -- fixed by CENSUS_SEED (default 4242) passed to tools/headless.sh
# fact: options -- tools/fixtures/options-2026-08-22.dat, set below
# fact: race and class lists -- read from the game's menus at run time
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED="${CENSUS_SEED:-4242}"
OUT="$ROOT/logs/census"
OPT=tools/fixtures/options-2026-08-22.dat
export INCURSION_BIN="${CENSUS_BIN:-./incursion-headless}"
ONLY="${CENSUS_ONLY:-}"
mkdir -p "$OUT/keys" "$OUT/runs"
# A full run starts clean; a CENSUS_ONLY run keeps the other runs and their status.
if [ -z "$ONLY" ]; then rm -rf "$OUT/runs" "$OUT/keys"; mkdir -p "$OUT/keys" "$OUT/runs"; : > "$OUT/status.txt"; fi
touch "$OUT/status.txt"

run_keys() {   # run_keys <name> <keyfile> <options> -> exit status of headless
    local name="$1" keys="$2" opts="$3" rd="$OUT/runs/$1"
    INCURSION_OPTIONS="$opts" INCURSION_RUN_DIR="$rd" \
        INCURSION_DRAW_CENSUS="$rd/draws.raw" \
        tools/headless.sh "$keys" "$SEED" > "$OUT/runs/$name.out" 2>&1
}

# Names of the race and class menus, read off a screen dump of each menu.
menu_names() {   # menu_names <name> <keyfile>; prints one name per line
    run_keys "$1" "$2" "$OPT"
    cat "$OUT/runs/$1/logs/screens/"*.txt \
      | grep -oE '\[[a-zA-Z]\] [A-Za-z][A-Za-z'"'"' -]*[A-Za-z]' \
      | sed -E 's/^\[[a-zA-Z]\] //'
}
printf 'a\nn\ny\n@expect "no such text"\n' > "$OUT/keys/list-races.keys"
RACES=$(menu_names list-races "$OUT/keys/list-races.keys")
FIRSTRACE=$(echo "$RACES" | head -1)
printf 'a\nn\ny\n@choose "%s"\n@while "Subraces provide" a\n@while "Choose a skill:" a\n@expect "no such text"\n' \
    "$FIRSTRACE" > "$OUT/keys/list-classes.keys"
CLASSES=$(menu_names list-classes "$OUT/keys/list-classes.keys")
[ -n "$RACES" ] && [ -n "$CLASSES" ] || { echo "could not read race/class menus"; exit 1; }

# The creation tail. Every screen creation can raise is answered by a @while on
# its title, which does nothing when the screen is not up; the block repeats so
# that screens arriving in a different order for a different class are all met.
tail_block() {
cat <<'EOF'
@while "attribute sets" a
@while "Choose a God:" a
@while "Alignment determines" a
@while "Choose a" a
@while "Choose any" a
@while "entitled to choose" a
@while "Focus on which" a
@while "Allocate Ranks" RIGHT RIGHT RIGHT DOWN
@while "Allocate Ranks" ENTER y
@while "wish to worship" y
@while "personality archetype" a
@while "Gain A Bonus" a
EOF
}
# Starting spells: the game re-asks until every slot is filled, and SPACE
# toggles, so a caster's script marks from the bottom of the list upward
# (UP wraps to the last row first) and confirms. Which pairs are casters is
# found by trying: a pair that ends on the table is run again with this.
learn_seq() { echo '@expect "Learn Spells: Level"'; for _ in 1 2 3 4 5 6 7 8 9 10; do echo UP; echo SPACE; done; echo ENTER; echo '@while "Learn Spells: Level" ENTER'; }
tail_all() {   # tail_all [withlearn]
    for _ in 1 2 3 4 5; do tail_block; done
    [ "${1:-}" = learn ] && learn_seq
    tail_block
}

head_keys() {   # head_keys <race> <class>
    printf 'a\nn\ny\n@choose "%s"\n@while "Subraces provide" a\n@while "Choose a skill:" a\n@choose "%s"\n' "$1" "$2"
}


declare -a WALKS=()
classify() {   # classify <name>: ok | refused | failed
    local name="$1" rd="$OUT/runs/$1" fin
    fin=$(cat "$rd/logs/screens/"*final*.txt 2>/dev/null; cat "$rd/logs/screens/"*.txt 2>/dev/null)
    if grep -q "do not meet the requirements\|Your class describes" <<<"$fin" \
       && ! grep -q "Mov:" <<<"$fin"; then echo refused; return; fi
    # ok: the run reached the map, or (level-up walks) ended on the sheet.
    if { grep -q "Mov:" <<<"$fin" || grep -q "^ Class  .* [2-9]  " <<<"$fin"; } \
       && [ -s "$rd/draws.raw" ]; then echo ok; return; fi
    echo failed
}
record() {   # record <name>
    local r; r=$(classify "$1")
    echo "$r $1" >> "$OUT/status.txt"
}

# 1. One walk per (race, class) pair.
while IFS= read -r race; do
  while IFS= read -r class; do
    name="pair-${race// /_}-${class// /_}"
    [[ -n "$ONLY" && "$name" != *"$ONLY"* ]] && continue
    { head_keys "$race" "$class"; tail_all; echo '@quit'; } > "$OUT/keys/$name.keys"
    run_keys "$name" "$OUT/keys/$name.keys" "$OPT"
    if grep -q "Learn Spells: Level" "$OUT/runs/$name/logs/screens/"*.txt 2>/dev/null; then
        rm -rf "$OUT/runs/$name"
        { head_keys "$race" "$class"; tail_all learn; echo '@quit'; } > "$OUT/keys/$name.keys"
        run_keys "$name" "$OUT/keys/$name.keys" "$OPT"
    fi
    record "$name"
  done <<<"$CLASSES"
done <<<"$RACES"

# 2. Special walks: rerolls, The Multitude (the domain pool), level-ups.
walk() {   # walk <name> <options> <header-keys-file>; tail and quit follow
    local name="$1" opts="$2"
    [[ -n "$ONLY" && "$name" != *"$ONLY"* ]] && return
    { cat "$3"; tail_all; cat "${4:-/dev/null}"; echo '@quit'; } > "$OUT/keys/$name.keys"
    run_keys "$name" "$OUT/keys/$name.keys" "$opts"
    if grep -q "Learn Spells: Level" "$OUT/runs/$name/logs/screens/"*.txt 2>/dev/null; then
        rm -rf "$OUT/runs/$name"
        { cat "$3"; tail_all learn; cat "${4:-/dev/null}"; echo '@quit'; } > "$OUT/keys/$name.keys"
        run_keys "$name" "$OUT/keys/$name.keys" "$opts"
    fi
    record "$name"
}
# Rerolls: three rerolls ('x') of the attribute sets before taking one.
{ head_keys "Orc" "Barbarian"; echo '@while "attribute sets" x'; } > "$OUT/keys/h-reroll.keys"
# (the @while above gives up after 200 passes; the walk keeps rerolling until
#  the loop limit, then the tail takes a set)
walk special-reroll "$OPT" "$OUT/keys/h-reroll.keys"
# The Multitude: a priest who picks the god by name.
{ head_keys "Human" "Priest"; echo '@choose "The Multitude"'; } > "$OUT/keys/h-multi.keys"
walk special-multitude "$OPT" "$OUT/keys/h-multi.keys"
# Default-settings walks. The frozen options file sets OPT_MAX_HP and
# OPT_MAX_MANA to 2, OPT_GENDER to 2 and OPT_BEGINKIT to 0, which switches off
# the per-level hit point and mana draws, the gender draw and the Beginner's
# Kit draws. A copy with those four back at the game's defaults (0, 0, 3 =
# random gender, 1) reaches them. It is a specimen under logs/census, never a
# tracked fixture. Byte N of the file is option N (src/Player.cpp LoadOptions).
python3 -I - "$OPT" "$OUT/options-defaults.dat" <<'PY2'
import sys
b = bytearray(open(sys.argv[1], "rb").read())
b[105] = 0; b[106] = 0; b[107] = 3; b[101] = 1   # MAX_HP, MAX_MANA, GENDER, BEGINKIT
open(sys.argv[2], "wb").write(b)
PY2
for c in Mage Barbarian Priest; do
    head_keys "Human" "$c" > "$OUT/keys/h-def-$c.keys"
    walk "special-defaults-$c" "$OUT/options-defaults.dat" "$OUT/keys/h-def-$c.keys"
done

# Level-ups: create, dismiss the arrival text, then raise four levels with G on
# the character sheet, after the wizard menu turns Free Advancement on.
levelup='ESC
s
w
y
w
DOWN
DOWN
SPACE
ESC
d
G
@while "Gain A Bonus" a
@while "Choose a" a
@while "Allocate Ranks" RIGHT RIGHT RIGHT DOWN
@while "Allocate Ranks" ENTER y
@while "Learn Spells: Level" ENTER
G
@while "Gain A Bonus" a
@while "Choose a" a
@while "Allocate Ranks" RIGHT RIGHT RIGHT DOWN
@while "Allocate Ranks" ENTER y
@while "Learn Spells: Level" ENTER
G
@while "Gain A Bonus" a
@while "Choose a" a
@while "Allocate Ranks" RIGHT RIGHT RIGHT DOWN
@while "Allocate Ranks" ENTER y
@while "Learn Spells: Level" ENTER
G
@while "Gain A Bonus" a
@while "Choose a" a
@while "Allocate Ranks" RIGHT RIGHT RIGHT DOWN
@while "Allocate Ranks" ENTER y
@while "Learn Spells: Level" ENTER'
printf '%s\n' "$levelup" > "$OUT/keys/t-levelup.keys"
for c in Barbarian Mage Priest Rogue; do
    head_keys "Human" "$c" > "$OUT/keys/h-lvl-$c.keys"
    walk "special-levelup-$c" "$OPT" "$OUT/keys/h-lvl-$c.keys" "$OUT/keys/t-levelup.keys"
done

# 3. Aggregate. Each raw line: window event resource kind site function.
python3 -I - "$OUT" <<'PY'
import sys, os, glob, subprocess, collections
out = sys.argv[1]
cnt = collections.Counter(); runs = collections.defaultdict(set)
funcs = set()
for f in glob.glob(os.path.join(out, "runs", "*", "draws.raw")):
    run = os.path.basename(os.path.dirname(f))
    for line in open(f, errors="replace"):
        p = line.rstrip("\n").split("\t")
        if len(p) != 6: continue
        w, ev, res, kind, site, fn = p
        k = (w, ev, res, kind, site, fn)
        cnt[k] += 1; runs[k].add(run); funcs.add(fn)
dem = {}
if funcs:
    try:
        r = subprocess.run(["c++filt"], input="\n".join(sorted(funcs)) + "\n",
                           capture_output=True, text=True)
        for a, b in zip(sorted(funcs), r.stdout.splitlines()): dem[a] = b
    except Exception: pass
rows = []
for (w, ev, res, kind, site, fn), n in cnt.items():
    fn2 = dem.get(fn, fn)
    fn2 = fn2.split("(")[0]
    rows.append((w, ev, res, (kind + "@" + site) if kind != "random" else site,
                 fn2, n, len(runs[(w, ev, res, kind, site, fn)]), kind))
rows.sort(key=lambda r: (r[0], -r[5]))
with open(os.path.join(out, "draws.tsv"), "w") as o:
    o.write("window\tevent\tresource\tcall_site\tfunction\tcount\truns\tkind\n")
    for r in rows: o.write("\t".join(map(str, r)) + "\n")
print("distinct call sites:", len({(r[3], r[4]) for r in rows}))
PY

{
  # last status per walk name
  awk '{st[$2]=$1} END {for (n in st) c[st[n]]++; printf "runs ok=%d refused=%d failed=%d\n", c["ok"], c["refused"], c["failed"]; for (n in st) if (st[n]=="failed") print "failed " n}' "$OUT/status.txt" | sort
} | tee "$OUT/summary.txt"
