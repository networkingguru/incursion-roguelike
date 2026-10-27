#!/bin/bash
# gate: live
# Bead inc-qylz: the Seneschal skill does work, so its SkillInfo row MUST carry imp == true. Three things follow from that flag, and each is checked:
#   1 structural: the row in src/Tables.cpp has imp=true
#   2 description: the skill page has no "(NOT IMPLEMENTED!)" (src/Skills.cpp:51)
#   3 menus: Seneschal is listed in the Skill Focus menu, the Natural Aptitude menu and the Ancestral Memory menu (src/Create.cpp:4197-4240, src/Skills.cpp:2504-2512)
#   Not checked: class help gray (src/Help.cpp:96-108). HelpTClass is static and has no caller, so no game path draws it; the in-game class page is the Desc text in lib/classes.irh. A check there could not go red.
# fact: skill row -- parsed from the SK_SENESCHAL row of SkillInfo[] in src/Tables.cpp; field order from struct SkillInfoStruct in inc/Creature.h
# fact: description text -- incursion-headless -wikihelp, which calls DescribeSkill(); no character, map, seed or RNG involved
# fact: settings -- tools/fixtures/options-2026-08-22.dat, named in INCURSION_OPTIONS for every session
# fact: character -- fixture lizardfolk-monk-seed1 (INCURSION_LOAD); a Monk lacks Seneschal as a class skill, so Natural Aptitude may list it, and a Lizardfolk has the Ancestral Memory ability
# fact: level-up feat menu -- wizard "Wizard Mode Switches", Free Advancement set to YES, then G on the character sheet (tools/keys/seneschal-levelup-feat.keys); the feat list comes from the fixture, no roll decides it
# fact: Ancestral Memory menu -- the Use Skill menu entry of the fixture's race ability; opens before any fatigue cost
# fact: binary freshness -- the live parts read the built binary, the structural part reads the source; rebuild after a source change
# Exit 0: every part measured and held; 1: any part measured a failure; 2: no part failed and at least one could not measure.
# Env: SENESCHAL_BIN names the binary the live parts run (default ./incursion-headless); the exit-code proof points it at a missing file.
set -uo pipefail
cd "$(dirname "$0")/.."

BIN="${SENESCHAL_BIN:-./incursion-headless}"
OPTIONS=tools/fixtures/options-2026-08-22.dat
FIXTURE=tools/fixtures/chars/lizardfolk-monk-seed1.sav
SEED="${1:-1}"
fail=0
unmeasured=0
ok() { echo "SENESCHAL ok: $*"; }
bad() { echo "SENESCHAL FAIL $*"; fail=1; }
cant() { echo "SENESCHAL INCONCLUSIVE $*"; unmeasured=1; }

# --- 1. structural: parse the row, never grep one literal line ---------------
python3 -I - <<'PY'
import re, sys
src = open('src/Tables.cpp', errors='replace').read()
decl = open('inc/Creature.h', errors='replace').read()
m = re.search(r'struct\s+SkillInfoStruct\s*\{(.*?)\}', decl, re.S)
fields = re.findall(r'^\s*[\w ]+?[\s*]+(\w+)\s*;', m.group(1), re.M) if m else []
if fields[:4] != ['sk', 'name', 'imp', 'active']:
    print('SENESCHAL INCONCLUSIVE SkillInfoStruct no longer starts sk, name, imp, active'); sys.exit(2)
rows = re.findall(r'\{\s*SK_SENESCHAL\s*,\s*"Seneschal"\s*,\s*(\w+)\s*,\s*(\w+)\s*,', src)
if len(rows) != 1 or rows[0][0] not in ('true', 'false'):
    print('SENESCHAL INCONCLUSIVE cannot find exactly one SK_SENESCHAL row in src/Tables.cpp'); sys.exit(2)
if rows[0][0] != 'true':
    print('SENESCHAL FAIL structural: SkillInfo row has imp=false'); sys.exit(1)
print('SENESCHAL ok structural: imp=true')
PY
case $? in 0) ;; 1) fail=1 ;; *) unmeasured=1 ;; esac

# --- the live parts need the binary, the settings and the fixture ------------
live=1
[ -x "$BIN" ] || { cant "live parts: no binary at $BIN (build with BACKEND=posix ./build_macos.sh)"; live=0; }
[ -f "$OPTIONS" ] && [ -f "$FIXTURE" ] || { cant "live parts: options or fixture missing"; live=0; }

if [ "$live" -eq 1 ]; then
mkdir -p logs/runs
run=$(mktemp -d "$PWD/logs/runs/seneschal-implemented.XXXXXX") || { echo 'SENESCHAL INCONCLUSIVE no run directory'; exit 2; }
echo "Specimens: $run"

# --- 2. behavioral: the description the game produces ------------------------
d="$run/wiki"
mkdir -p "$d/save" "$d/logs" "$d/out"
ln -sfn "$PWD/mod" "$d/mod"
ln -sfn "$PWD/lib" "$d/lib"
cp "$OPTIONS" "$d/Options.Dat"
if ! INCURSIONPATH="$d/" "$BIN" -wikihelp "$d/out" >"$d/harness.txt" 2>&1; then
    cant "description: -wikihelp failed (see $d/harness.txt)"
elif [ ! -s "$d/out/Seneschal.md" ]; then
    cant "description: no Seneschal.md produced"
else
    text=$(<"$d/out/Seneschal.md")
    if ! grep -q '^# Seneschal' <<<"$text" || ! grep -q 'Passive\|Active' <<<"$text"; then
        cant "description: Seneschal.md has no title or description text"
    elif grep -q 'NOT IMPLEMENTED' <<<"$text"; then
        bad "description: the page says (NOT IMPLEMENTED!)"
    else
        ok "description has no NOT IMPLEMENTED marker"
    fi
fi

# one session of a key script on the frozen character
session() {  # session <name> <keys>
    local name="$1" keys="$2"
    rm -rf "$run/$name"
    INCURSION_BIN="$BIN" INCURSION_OPTIONS="$OPTIONS" INCURSION_LOAD="$FIXTURE" \
    INCURSION_RUN_DIR="$run/$name" TERM=xterm \
        tools/headless.sh "$keys" "$SEED" </dev/null >"$run/$name.out" 2>&1
}

# --- 3. menus ----------------------------------------------------------------
menu() {  # menu <label> <keys> <dump label> <header text>
    local label="$1" keys="$2" dumpname="$3" header="$4" screen
    if ! session "$dumpname" "$keys"; then
        cant "$label menu: session failed (see $run/$dumpname.out)"; return
    fi
    screen=$(cat "$run"/"$dumpname"/logs/screens/*-"$dumpname".txt 2>/dev/null)
    if ! grep -q "$header" <<<"$screen" || ! grep -Eq '\[[a-zA-Z]\] Spellcraft' <<<"$screen"; then
        cant "$label menu: the menu or its Spellcraft control entry is not on the screen (see $run/$dumpname)"
    elif grep -Eq '\[[a-zA-Z]\] Seneschal' <<<"$screen"; then
        ok "$label menu lists Seneschal"
    else
        bad "$label menu: Seneschal is not listed (see $run/$dumpname)"
    fi
}
menu "Skill Focus" tools/keys/seneschal-menu-skill-focus.keys skill-focus "Choose a skill:"
menu "Natural Aptitude" tools/keys/seneschal-menu-natural-aptitude.keys natural-aptitude "Choose a skill:"
menu "Ancestral Memory" tools/keys/seneschal-menu-ancestral-memory.keys ancestral-memory "Choose a skill to augment:"
fi

[ "$fail" -eq 1 ] && { echo 'SENESCHAL FAIL'; exit 1; }
[ "$unmeasured" -eq 1 ] && { echo 'SENESCHAL INCONCLUSIVE'; exit 2; }
echo 'SENESCHAL PASS'
exit 0
