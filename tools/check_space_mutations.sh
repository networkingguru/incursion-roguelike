#!/bin/bash
# gate: none compiles three sandbox modules with the built incursion-headless, then runs 30-odd plants; about 60 s, so it is not a cheap check
# Does every inventoried allocation space catch a planted duplicate? (bead inc-cjos0)
#
# One mutation per space, in a THROWAWAY COPY under a mktemp directory. The
# check never edits a file of the tree. For each row of the inventory it
#   1. plants ONE duplicate (a name twice, a value twice, a mid-list insert,
#      two branches editing one place);
#   2. runs the space's detector and requires it to go RED with the message
#      that names the plant;
#   3. restores the copy and requires the same detector to go GREEN.
# One line per row:  RED-OK <row> <space>: <deciding line>
#                    FAIL   <row> <space>: <why>      (a plant stayed green, or red for the wrong reason)
#                    SKIP   <row> <reason>
#
# Exit 0 every row RED-OK with a passing green control; 1 a plant stayed green
# or went red for another reason; 2 a detector could not run (no build, no
# git, a plant that did not apply).
#
# Rows 5 and 4b: the module compile is the detector (inc-cjos0); it refuses a
# variable name declared twice in one scope.
#
# Needs: BACKEND=posix ./build_macos.sh (incursion-headless), git, python3, clang++ or g++.
# Usage: tools/check_space_mutations.sh      KEEP=1 keeps the scratch directory.
# fact: the saved-name, define, array-limit and resource scopes -- text of inc/, src/ and lib/ copied into a scratch tree; the plants are the check's own edits
# fact: define and enumerator values -- the compiler at the posix flags of build_macos.sh, run by tools/check_stored_values.py; no game session, no seed
# fact: resource and variable positions -- incursion-headless -compile of a scratch copy of lib/, read back with -resorder; no game session, no seed
# fact: the merge outcome of two branches -- git merge in a scratch repo with no global config, no attributes and no hooks; no randomness
# fact: the base tree of a stored-value check -- the scratch repo's own master, committed from the copy before any plant; not the real master
set -uo pipefail
export PYTHONDONTWRITEBYTECODE=1

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

BIN=./incursion-headless
for tool in git python3; do
    command -v "$tool" >/dev/null 2>&1 || { echo "UNMEASURED: $tool is not installed"; exit 2; }
done
[ -x "$BIN" ] || { echo "UNMEASURED: $BIN is not built. Run: BACKEND=posix ./build_macos.sh"; exit 2; }
CXX="${CXX:-clang++}"
command -v "$CXX" >/dev/null 2>&1 || CXX=g++
command -v "$CXX" >/dev/null 2>&1 || { echo "UNMEASURED: no C++ compiler"; exit 2; }

W="$(mktemp -d "${TMPDIR:-/tmp}/space-mutations.XXXXXX")" || { echo "UNMEASURED: no scratch directory"; exit 2; }
cleanup() { [ -n "${KEEP:-}" ] && { echo "kept $W"; return; }; rm -rf "$W"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Inherited repository settings must not reach the scratch repos.
for variable in ${!GIT_@}; do unset "$variable"; done
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_ATTR_NOSYSTEM=1 LC_ALL=C
mkdir -p "$W/template"

FAILED=0
UNRUN=0
OUT=""
RC=0
ROW_FAIL=""
ROW_UNRUN=""
ROW_DEC=""

R0="$W/r0"   # the scratch tree: inc, src, a few tools, committed as master of its own repo

die2() { echo "UNMEASURED: $1"; exit 2; }

# subst FILE REGEX NEW -- replace the first match of REGEX (multiline) with NEW; exit 2 when nothing matches.
subst() {
    python3 - "$1" "$2" "$3" <<'PY' || die2 "the plant did not apply: $1 /$2/"
import re, sys
p, rx, new = sys.argv[1:4]
t = open(p, encoding="utf-8", errors="surrogateescape").read()
t2, n = re.subn(rx, lambda m: m.group(0).join(new.replace("\\n", "\n").split("&")), t, count=1, flags=re.M)
if n != 1:
    sys.exit(1)
open(p, "w", encoding="utf-8", errors="surrogateescape").write(t2)
PY
}

restore() { git -C "$R0" checkout -q -- . || die2 "cannot restore the scratch tree"; }
in_r0() { ( cd "$R0" && "$@" ); }

first_line() { printf '%s\n' "${OUT%%$'\n'*}"; }
last_line() { printf '%s\n' "${OUT##*$'\n'}"; }

run() { OUT="$("$@" 2>&1 </dev/null)"; RC=$?; }

begin_row() { ROW_FAIL=""; ROW_UNRUN=""; ROW_DEC=""; }

# expect_red NEEDLE CMD... -- CMD must exit non-zero (not 2) and print NEEDLE.
expect_red() {
    local needle="$1" line; shift
    run "$@"
    if [ "$RC" -eq 2 ]; then
        ROW_UNRUN="the detector could not run: $(first_line)"; return
    fi
    if [ "$RC" -eq 0 ]; then
        ROW_FAIL="$ROW_FAIL plant stayed green (exit 0: $(last_line | cut -c1-90));"; return
    fi
    line="$(grep -F -m1 -- "$needle" <<<"$OUT")"
    if [ -z "$line" ]; then
        ROW_FAIL="$ROW_FAIL red (exit $RC) without \"$needle\": $(first_line | cut -c1-90);"; return
    fi
    [ -n "$ROW_DEC" ] || ROW_DEC="$line"
}

# expect_green CMD... -- the control: the unplanted copy passes.
expect_green() {
    run "$@"
    if [ "$RC" -eq 2 ]; then
        ROW_UNRUN="the green control could not run: $(first_line)"; return
    fi
    [ "$RC" -eq 0 ] || ROW_FAIL="$ROW_FAIL green control failed (exit $RC): $(first_line | cut -c1-90);"
}

end_row() { # row space
    local dec="${ROW_DEC//$W/<tmp>}"
    dec="$(printf '%s' "$dec" | sed 's/^[[:space:]]*//' | cut -c1-170)"
    if [ -n "$ROW_UNRUN" ]; then
        echo "FAIL $1 $2: could not run: ${ROW_UNRUN//$W/<tmp>}"; UNRUN=1
    elif [ -n "$ROW_FAIL" ]; then
        echo "FAIL $1 $2:${ROW_FAIL//$W/<tmp>}"; FAILED=1
    else
        echo "RED-OK $1 $2: $dec"
    fi
}

# --- the scratch tree: a copy of inc/, src/ and the stored-value tools, committed as its own master ----------------
mkdir -p "$R0/tools" "$R0/lib" || die2 "cannot make the scratch tree"
cp -R inc src compat "$R0/" || die2 "cannot copy inc/ src/ compat/"
cp lib/dispatch.h "$R0/lib/" || die2 "cannot copy lib/dispatch.h"
for f in check_define_dups.py check_stored_values.py define_baseline.txt retired_values.txt \
         retired_field_names.txt probe_names.txt check_probe_names.py; do
    cp "tools/$f" "$R0/tools/" || die2 "cannot copy tools/$f"
done
git init -q -b master "$R0" || die2 "git init failed"
git -C "$R0" config user.name "space mutations" && git -C "$R0" config user.email "check@example.invalid" \
    && git -C "$R0" config commit.gpgsign false && git -C "$R0" config core.hooksPath /dev/null \
    || die2 "git config failed"
git -C "$R0" add -A >/dev/null && git -C "$R0" commit -qm base || die2 "cannot commit the scratch tree"

DUPS=(python3 -B tools/check_define_dups.py)
STORED=(python3 -B tools/check_stored_values.py)
NAMES=(python3 -B "$ROOT/tools/check_save_names.py" --fast --root "$R0")

# --- row 1: saved field name ----------------------------------------------------------------------------------------
begin_row
subst "$R0/inc/Creature.h" '^( *)FIELD_I16\("PartyID", PartyID\);' '&\n&'
expect_red 'written at 2 sites with the same spelling' "${NAMES[@]}"
restore
# a numeric tag where a name belongs does not compile
cat > "$W/tag_bad.cpp" <<'EOF'
#include "Incursion.h"
void F(Registry &r, int16 &x) { FIELD_I16(128, x); }
EOF
cat > "$W/tag_ok.cpp" <<'EOF'
#include "Incursion.h"
void F(Registry &r, int16 &x) { FIELD_I16("x", x); }
EOF
CXXF=(-std=c++17 -fsyntax-only -fpermissive -Wno-narrowing -w -DDEBUG -DPOSIX_TERM "-I$ROOT/inc" "-I$ROOT/lib" "-I$ROOT/compat")
expect_red 'V1LiteralName' "$CXX" "${CXXF[@]}" "$W/tag_bad.cpp"
expect_green "${NAMES[@]}"
expect_green "$CXX" "${CXXF[@]}" "$W/tag_ok.cpp"
end_row 1 "saved field name twice in one scope; a numeric tag in a FIELD_ call"

# --- git helpers: two branches, one place -------------------------------------------------------------------------------
# merge_probe ID BASEFN AFN BFN -- prints the conflict lines and returns 1, prints "merged clean" and returns 0, 2 on a setup failure.
PM=same
merge_probe() {
    local id="$1" basefn="$2" afn="$3" bfn="$4" d="$W/g.$1.$PM" log
    git init -q --template="$W/template" "$d" || return 2
    git -C "$d" symbolic-ref HEAD refs/heads/base || return 2
    git -C "$d" config user.name "space mutations"; git -C "$d" config user.email "check@example.invalid"
    git -C "$d" config commit.gpgsign false; git -C "$d" config core.hooksPath /dev/null
    git -C "$d" config core.attributesFile /dev/null
    "$basefn" "$d" || return 2
    git -C "$d" add -A && git -C "$d" commit -qm base || return 2
    git -C "$d" checkout -qb a && "$afn" "$d" && git -C "$d" add -A && git -C "$d" commit -qm a || return 2
    git -C "$d" checkout -q base && git -C "$d" checkout -qb b && "$bfn" "$d" && git -C "$d" add -A \
        && git -C "$d" commit -qm b || return 2
    git -C "$d" checkout -q a || return 2
    log="$(git -C "$d" merge --no-edit b 2>&1)"; local mrc=$?
    if [ "$mrc" -eq 1 ] && grep -q CONFLICT <<< "$log"; then
        printf '%s\n' "$log" | grep CONFLICT; return 1
    elif [ "$mrc" -eq 0 ]; then
        echo "merged clean"; return 0
    fi
    printf '%s\n' "$log"; return 2
}
# probe_row NEEDLE ID BASEFN AFN BFN -- RED when the two branches meet at one place, GREEN when they do not.
probe_row() {
    local needle="$1"; shift
    PM=same; expect_red "$needle" merge_probe "$@"
    PM=apart; expect_green merge_probe "$@"
    PM=same
}

# --- row 2: SCHEMA_REV --------------------------------------------------------------------------------------------------
begin_row
subst "$R0/src/SaveV1.cpp" '^#define SCHEMA_REV 7 /\* rev owner: [^*]*\*/' '#define SCHEMA_REV 7'
expect_red 'the SCHEMA_REV define has no valid owner comment' "${NAMES[@]}"
restore
expect_green "${NAMES[@]}"
bs_rev() { cp "$ROOT/src/SaveV1.cpp" "$1/SaveV1.cpp"; }
a_rev() { subst "$1/SaveV1.cpp" '^#define SCHEMA_REV .*$' '#define SCHEMA_REV 8 /* rev owner: inc-a */'; }
b_rev() {
    if [ "$PM" = same ]; then subst "$1/SaveV1.cpp" '^#define SCHEMA_REV .*$' '#define SCHEMA_REV 8 /* rev owner: inc-b */'
    else printf '\n/* b */\n' >> "$1/SaveV1.cpp"; fi
}
PM=same; expect_red 'CONFLICT (content): Merge conflict in SaveV1.cpp' merge_probe rev bs_rev a_rev b_rev
PM=apart; expect_green merge_probe rev bs_rev a_rev b_rev; PM=same
end_row 2 "SCHEMA_REV: no owner comment; two branches bump it"

# --- the sandbox modules for rows 3, 4 and 5 -------------------------------------------------------------------------------
sandbox() { # name -> $W/sb/<name>, with lib/ copied and inc/ linked
    local sb="$W/sb/$1"
    mkdir -p "$sb/mod" "$sb/logs" && cp -Rf "$ROOT/lib" "$sb/lib" && ln -sfn "$ROOT/inc" "$sb/inc" || die2 "cannot make sandbox $1"
    echo "$sb"
}
compile_sb() {
    INCURSIONPATH="$1/" "$BIN" -compile main.irc </dev/null >"$1/compile.log" 2>&1
    [ $? -eq 0 ] && [ -f "$1/mod/Incursion.Mod" ] || { tail -5 "$1/compile.log"; die2 "the sandbox $(basename "$1") did not compile"; }
}
ORDER=(python3 -B tools/resource_order_check.py)

# --- row 3: a resource inserted mid-list --------------------------------------------------------------------------------
begin_row
SB3="$(sandbox insert)"
subst "$SB3/lib/classes.irh" '^0 Effect "Aura of Valour" : EA_GRANT' '0 Effect "Space Mutation Insert" : EA_GENERIC\n  { }\n\n&'
compile_sb "$SB3"
expect_red 'Aura of Valour' "${ORDER[@]}" --module-root "$SB3"
expect_green "${ORDER[@]}"
end_row 3 "resource-array position: an Effect inserted before an existing one"

# --- row 4: a module-level script variable in two beads ----------------------------------------------------------------
# try_compile SANDBOX -- exit 0 when the module compiles, 1 when the compiler refuses; prints the compiler output.
try_compile() {
    rm -f "$1/mod/Incursion.Mod"
    INCURSIONPATH="$1/" "$BIN" -compile main.irc </dev/null 2>&1 || return 1
    [ -f "$1/mod/Incursion.Mod" ] || return 1
}
SB4="$(sandbox twobeads)"
printf 'int16 space_mut_var;\n' > "$SB4/lib/landed-inc-a.irh"
printf '#include "landed-inc-a.irh"\n' > "$SB4/lib/landed.irc"
compile_sb "$SB4"
INCURSIONPATH="$SB4/" "$BIN" -resorder </dev/null > "$SB4/dump" 2>/dev/null || die2 "-resorder failed on the one-bead sandbox"
LANDED=(python3 -B tools/check_landed_files.py --dump "$SB4/dump" --base-ledger tools/resource_order.ledger --lib "$SB4/lib")
begin_row
# a bead whose module holds a variable that only ANOTHER bead's landed file declares
expect_red "new variable 'space_mut_var'" "${LANDED[@]}" --bead inc-c
expect_green "${LANDED[@]}" --bead inc-a
end_row 4a "module variable in another bead's landed file (bead inc-c owns none)"
begin_row
# the same name in two beads' own landed files: the module compile refuses (inc-cjos0)
SB4B="$(sandbox twobeads2)"
printf 'int16 space_mut_var;\n' > "$SB4B/lib/landed-inc-a.irh"
printf 'int16 space_mut_var;\n' > "$SB4B/lib/landed-inc-b.irh"
printf '#include "landed-inc-a.irh"\n#include "landed-inc-b.irh"\n' > "$SB4B/lib/landed.irc"
expect_red "Variable 'space_mut_var' declared twice in scope module" try_compile "$SB4B"
expect_green try_compile "$SB4"
end_row 4b "module variable declared by two beads, one landed file each (the module compile refuses)"

# --- row 5: a script variable twice in one body ------------------------------------------------------------------------
begin_row
SB5="$(sandbox dupvar)"
subst "$SB5/lib/pspells.irh" 'bool cast_flag, found_flag;' 'bool cast_flag, found_flag, cast_flag;'
expect_red "Variable 'cast_flag' declared twice in scope resource 'Entangle'" try_compile "$SB5"
restore_sb5() { cp "$ROOT/lib/pspells.irh" "$SB5/lib/pspells.irh"; }
restore_sb5
expect_green try_compile "$SB5"
end_row 5 "script variable name twice in one owner body (the module compile refuses)"

# --- rows 6, 7, 9, 10, 11, 12, 14: define families and stored values ---------------------------------------------------
begin_row
subst "$R0/inc/Defines.h" '^#define POISONED      2$' '&\n#define ZZ_PLANT_STATI 2'
expect_red 'ZZ_PLANT_STATI' in_r0 "${DUPS[@]}"
expect_red 'ZZ_PLANT_STATI' in_r0 "${STORED[@]}"
restore
expect_green in_r0 "${DUPS[@]}"
expect_green in_r0 "${STORED[@]}"
end_row 6 "stored ordinal family (stati): a new name takes a master value"

begin_row
subst "$R0/inc/Defines.h" '^#define EV_MOVE         1$' '&\n#define EV_ZZ_PLANT     1'
expect_red 'EV_ZZ_PLANT' in_r0 "${DUPS[@]}"
restore
end_row 7 "internal family (EV_): two names, one value"

begin_row
subst "$R0/inc/Defines.h" '^#define FT_LUCUBRATION         363$' '&\n#define FT_ZZ_PLANT            363'
expect_red 'FT_ZZ_PLANT' in_r0 "${DUPS[@]}"
expect_red 'FT_ZZ_PLANT' in_r0 "${STORED[@]}"
restore
end_row 9 "stored family (FT_ feats): two names, one value"

echo "SKIP 8 epic-only: the MSG_ god message ids exist only on the epic"

begin_row
subst "$R0/inc/Defines.h" '^#define OPT_ALL_ROLLS +812$' '&\n#define OPT_ZZ_PLANT            812'
expect_red 'OPT_ZZ_PLANT' in_r0 "${DUPS[@]}"
restore
subst "$R0/inc/Defines.h" '^#define OPT_LAST +900$' '#define OPT_LAST                899'
expect_red 'OPT_LAST' in_r0 "${STORED[@]}"
restore
expect_green in_r0 "${DUPS[@]}"
end_row 10 "OPT_ options: two names one value; the grows limit OPT_LAST set below master's"

begin_row
subst "$R0/inc/Creature.h" 'FIELD_ARRAY\("SpentSP", SpentSP, sizeof\(uint16\), 6\);' 'FIELD_ARRAY("SpentSP", SpentSP, sizeof(uint16), 5);'
expect_red 'SpentSP' in_r0 "${STORED[@]}"
restore
subst "$R0/inc/Defines.h" '^#define FT_LAST +364$' '#define FT_LAST                363'
expect_red 'FT_LAST' in_r0 "${STORED[@]}"
restore
expect_green in_r0 "${STORED[@]}"
end_row 11 "saved array dimension shrunk: a FIELD_ARRAY count; the grows limit FT_LAST"

begin_row
subst "$R0/inc/Target.h" '^    TargetGreedy,$' '&\n    TargetZzPlant,'
expect_red 'TargetHitMe' in_r0 "${STORED[@]}"
restore
expect_green in_r0 "${STORED[@]}"
end_row 12 "auto-numbered stored enum (TargetWhyType): a mid-list insert moves a master value"

begin_row
subst "$R0/inc/Defines.h" '^#define SK_HIGH_END   800$' '#define SK_ZZ_PLANT   600\n&'
expect_red 'SK_ZZ_PLANT' in_r0 "${STORED[@]}"
restore
subst "$R0/inc/Defines.h" '^#define FT_LUCUBRATION         363$' '&\n#define FT_ZZ_HIGH             800'
expect_red 'FT_ZZ_HIGH' in_r0 "${STORED[@]}"
restore
expect_green in_r0 "${STORED[@]}"
end_row 14 "skill and feat number bands: a new skill below 800; a new feat at 800 or above"

# --- row 13: data migration name ---------------------------------------------------------------------------------------
begin_row
subst "$R0/src/SaveV1.cpp" '^( *)\{ "SpellFlagsRev5", 5, &Player::MigrateSpellFlagsRev5 \},$' '&\n&'
expect_red 'registered twice' "${NAMES[@]}"
restore
expect_green "${NAMES[@]}"
end_row 13 "data migration name registered twice"

# --- row 15: generated lib/dispatch.h -----------------------------------------------------------------------------------
begin_row
run bash tools/check_generated_merge.sh
if [ "$RC" -ne 0 ]; then
    ROW_FAIL=" tools/check_generated_merge.sh exited $RC: $(first_line);"
else
    ROW_DEC="$(grep -F -m1 'PASS: with guard' <<<"$OUT")"
    [ -n "$ROW_DEC" ] || ROW_FAIL=" no 'PASS: with guard' line;"
    grep -qF 'PASS: without guard' <<< "$OUT" || ROW_FAIL="$ROW_FAIL no 'PASS: without guard' control line;"
fi
end_row 15 "generated lib/dispatch.h: two branches edit it (tools/check_generated_merge.sh plants both edits)"

# --- row 16: the wizard-mode menu switch -----------------------------------------------------------------------------------
begin_row
mkdir -p "$W/dbg"; cp src/Debug.cpp "$W/dbg/Debug.cpp" || die2 "cannot copy src/Debug.cpp"
expect_green "$CXX" "${CXXF[@]}" "$W/dbg/Debug.cpp"
subst "$W/dbg/Debug.cpp" '^    case 3:$' '&\n    case 3:'
expect_red 'duplicate case value' "$CXX" "${CXXF[@]}" "$W/dbg/Debug.cpp"
end_row 16 "debug menu: two case labels with one number in the wizard menu switch (one-file compile)"

# --- row 17: saved-class pad rows ---------------------------------------------------------------------------------------
begin_row
subst "$R0/inc/Creature.h" 'int16  TouchDef;' '&\n      int16 SpaceMutProbe;'
expect_red 'Creature' bash tools/check_save_pad_rows.sh --root "$R0"
restore
expect_green bash tools/check_save_pad_rows.sh --root "$R0"
end_row 17 "saved-class pad rows: a Creature member with no FIELD_ line"

echo "SKIP 18 not planted: by construction, not an allocation space"

# --- rows 19, 20, 21, 22: git conflicts ------------------------------------------------------------------------------------
bs_none() { echo base > "$1/README"; }
a_path() { mkdir -p "$1/lib"; echo 'int16 zz_a;' > "$1/lib/landed-inc-zz.irh"; }
b_path() { mkdir -p "$1/lib"; if [ "$PM" = same ]; then echo 'int16 zz_b;' > "$1/lib/landed-inc-zz.irh"; else echo 'int16 zz_b;' > "$1/lib/landed-inc-yy.irh"; fi; }
begin_row
probe_row 'CONFLICT (add/add)' path bs_none a_path b_path
end_row 19 "one file path added on two branches with different content"

bs_fix() { mkdir -p "$1/tools/fixtures/chars"; cp "$ROOT/tools/fixtures/chars/MANIFEST" "$1/tools/fixtures/chars/MANIFEST"; }
a_fix() {
    printf 'A\n' > "$1/tools/fixtures/chars/zz.char"
    printf 'zz tools/keys/a.keys 1 tools/fixtures/options-2026-08-22.dat\n' >> "$1/tools/fixtures/chars/MANIFEST"
}
b_fix() {
    if [ "$PM" = same ]; then
        printf 'B\n' > "$1/tools/fixtures/chars/zz.char"
        printf 'zz tools/keys/b.keys 2 tools/fixtures/options-2026-08-22.dat\n' >> "$1/tools/fixtures/chars/MANIFEST"
    else
        printf 'B\n' > "$1/tools/fixtures/chars/yy.char"
        subst "$1/tools/fixtures/chars/MANIFEST" '^# Every frozen character this repository wants, one per line\.$' '&\n# b'
    fi
}
begin_row
probe_row 'CONFLICT' fixture bs_fix a_fix b_fix
end_row 20 "fixture .char plus its MANIFEST row, added by two branches"

# --- row 21: INCURSION_ probe names ------------------------------------------------------------------------------------------
begin_row
FIRST="$(grep -m1 -v '^#' "$R0/tools/probe_names.txt" | cut -f1)"
[ -n "$FIRST" ] || die2 "tools/probe_names.txt holds no row"
subst "$R0/tools/probe_names.txt" "^$FIRST\t.*\$" '&\n&'
expect_red 'second row' in_r0 python3 -B tools/check_probe_names.py
restore
expect_green in_r0 python3 -B tools/check_probe_names.py
bs_probe() { mkdir -p "$1/tools"; cp "$ROOT/tools/probe_names.txt" "$1/tools/probe_names.txt"; }
a_probe() { subst "$1/tools/probe_names.txt" "^$FIRST\t.*\$" "&\nINCURSION_ZZ_PLANT\tinc-a\tmeaning a"; }
b_probe() {
    if [ "$PM" = same ]; then subst "$1/tools/probe_names.txt" "^$FIRST\t.*\$" "&\nINCURSION_ZZ_PLANT\tinc-b\tmeaning b"
    else printf 'INCURSION_ZZZ_LAST\tinc-b\tmeaning b\n' >> "$1/tools/probe_names.txt"; fi
}
probe_row 'CONFLICT (content)' probe bs_probe a_probe b_probe
end_row 21 "INCURSION_ probe name: a second row for one name; two branches add one name at one sorted place"

# --- row 22: a shared-tail text file ---------------------------------------------------------------------------------------------
bs_tail() { mkdir -p "$1/lib"; cp "$ROOT/lib/main.irc" "$1/lib/main.irc"; }
a_tail() { printf '0 Effect "Zz A" : EA_GENERIC\n  { }\n' >> "$1/lib/main.irc"; }
b_tail() {
    if [ "$PM" = same ]; then printf '0 Effect "Zz B" : EA_GENERIC\n  { }\n' >> "$1/lib/main.irc"
    else subst "$1/lib/main.irc" '\A' '/* b */\n'; fi
}
begin_row
probe_row 'CONFLICT (content)' tail bs_tail a_tail b_tail
end_row 22 "shared-tail text file (lib/main.irc): two branches append at the end"

for r in 23 24 25; do echo "SKIP $r not planted: not an allocation space"; done

if [ "$UNRUN" -ne 0 ]; then exit 2; fi
[ "$FAILED" -eq 0 ] || exit 1
echo "check_space_mutations: PASS (every planted row went red, every green control passed)"
exit 0
