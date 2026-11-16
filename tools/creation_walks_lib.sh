# Sourced, never run: the key scripts of a creation walk, shared by
# tools/census_creation_draws.sh and tools/check_fixture_equivalence.sh
# (bead inc-10v7f). One generator writes the walk of every race-by-class pair,
# reading the race and class names off the game's own menus and selecting them
# with @choose, so neither caller keeps a list of races or classes.
#
# The sourcing script MUST define, before it calls cw_read_menus:
#   OUT        a directory holding keys/ and runs/
#   OPT        the settings file the menu walks run under
#   run_keys <name> <keyfile> <options>   run one key script (headless) in
#                                         $OUT/runs/<name>, exit status of the run

# Names of the race and class menus, read off a screen dump of each menu.
menu_names() {   # menu_names <name> <keyfile>; prints one name per line
    run_keys "$1" "$2" "$OPT"
    cat "$OUT/runs/$1/logs/screens/"*.txt \
      | grep -oE '\[[a-zA-Z]\] [A-Za-z][A-Za-z'"'"' -]*[A-Za-z]' \
      | sed -E 's/^\[[a-zA-Z]\] //'
}

# cw_read_menus: sets RACES, FIRSTRACE and CLASSES (one name per line). Returns 1
# when either menu could not be read.
cw_read_menus() {
    printf 'a\nn\ny\n@expect "no such text"\n' > "$OUT/keys/list-races.keys"
    RACES=$(menu_names list-races "$OUT/keys/list-races.keys")
    FIRSTRACE=$(echo "$RACES" | head -1)
    printf 'a\nn\ny\n@choose "%s"\n@while "Subraces provide" a\n@while "Choose a skill:" a\n@expect "no such text"\n' \
        "$FIRSTRACE" > "$OUT/keys/list-classes.keys"
    CLASSES=$(menu_names list-classes "$OUT/keys/list-classes.keys")
    [ -n "$RACES" ] && [ -n "$CLASSES" ]
}

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

# save_tail: the end of a walk that SAVES the character at the end of creation
# and plays nothing (the tail of tools/keys/p7a-drow-ranger-save.keys).
save_tail() {
cat <<'EOF'
@until "System Menu" ESC
@expect "System Menu"
b
@dump:saved
EOF
}

# round_trip <name> <keys> <seed> <options> <out-dir>: the fixture builder's
# round trip for ONE walk (spec section 9, C2). It walks the key script with the
# recorder on (INCURSION_RECORD_CHAR), builds the .char the walk recorded with
# tools/build_fixture.sh, dumps both characters with tools/char_dump.sh, and
# compares the dumps outside the one allowlist of tools/canon_compare.py. It
# prints one result line and returns 0 only for SAME; RT_KIND holds the word:
#   SAME / DIFF (with the diff path) / BUILDFAIL (with the BUILD FAILED line) /
#   NOWALK (the walk saved no character or recorded no .char; with the exit
#   code) / DUMPFAIL.
# The caller defines ROOT (the repo root, the current directory) and NEW (the
# binary). Specimens land in <out-dir>/<name>-walk (the walk's run directory),
# <name>.char, <name>-walk.canon, <name>-built/, <name>-built.canon, <name>.diff.
round_trip() {
    local name="$1" keys="$2" seed="$3" opts="$4" od="$5" run sav walkexit
    run="$od/$name-walk"
    rm -rf "$run"; rm -f "$od/$name.char" "$od/$name.walk.sav"
    INCURSION_RECORD_CHAR="$ROOT/$od/$name.char" INCURSION_OPTIONS="$opts" \
        INCURSION_BIN="$NEW" INCURSION_RUN_DIR="$ROOT/$run" \
        tools/headless.sh "$keys" "$seed" > "$od/$name-walk.log" 2>&1 </dev/null
    walkexit=$?
    sav="$od/$name.walk.sav"   # the save of the walked character before its first turn (R1)
    if [ ! -f "$sav" ] || [ ! -f "$od/$name.char" ]; then
        RT_KIND=NOWALK; echo "NOWALK   $name (exit $walkexit)"; return 1
    fi
    INCURSION_OPTIONS="$opts" INCURSION_BIN="$NEW" tools/char_dump.sh "$sav" "$od/$name-walk.canon" > /dev/null 2>&1 \
        || { RT_KIND=DUMPFAIL; echo "DUMPFAIL $name (walk)"; return 1; }
    rm -rf "$od/$name-built"
    INCURSION_BIN="$NEW" tools/build_fixture.sh "$od/$name.char" "$od/$name-built" \
        > "$od/$name-build.log" 2>&1
    if [ $? -ne 0 ]; then
        RT_KIND=BUILDFAIL
        echo "BUILDFAIL $name: $(grep -m1 'BUILD FAILED' "$od/$name-build.log" || tail -1 "$od/$name-build.log")"; return 1
    fi
    INCURSION_OPTIONS="$opts" INCURSION_BIN="$NEW" tools/char_dump.sh "$od/$name-built/$name.sav" "$od/$name-built.canon" > /dev/null 2>&1 \
        || { RT_KIND=DUMPFAIL; echo "DUMPFAIL $name (built)"; return 1; }
    if tools/canon_compare.py "$od/$name-walk.canon" "$od/$name-built.canon" > "$od/$name.diff" 2>&1; then
        RT_KIND=SAME; echo "SAME     $name"; return 0
    fi
    RT_KIND=DIFF; echo "DIFF     $name  (see $od/$name.diff)"; return 1
}
