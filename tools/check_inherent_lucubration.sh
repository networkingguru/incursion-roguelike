#!/bin/bash
# gate: live
# inc-2jd0: observe Inherent Spell and Lucubration through real level-up menus.
# Frozen Mage/Priest fixtures, seed 1, options-2026-08-22.dat. Wizard Free
# Advancement reaches GainFeat; no probe grants spells or changes spell flags.
# Mage Armour starts unmemorized and casts immediately (no rest, mana -8).
# Studied Elemental Covenant supplies Endure Cold at rest after all books drop;
# Alarm from unstudied Adventurers' Arts cannot be memorized at that same rest.
# A symbol-less Priest picks Bless and casts it (mana -5); Call Light refuses.
# Red proof: copy this check and its five key scripts into a scratch archive
# of master under logs/, build there with BACKEND=posix ./build_macos.sh, run
# there. Use that tree's module AND executable. No git state changes required.
# Any missing screen, failed harness directive, or assertion is FAIL (exit 1).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
OPTIONS=tools/fixtures/options-2026-08-22.dat
MAGE=tools/fixtures/chars/orc-mage-seed1-opt0822.sav
PRIEST=tools/fixtures/chars/xsummon-priest-seed5-opt0822.sav
FAIL=0
RUN=
result() {
    if [ "$1" -eq 0 ]; then echo "PASS: $2";
    else echo "FAIL: $2"; FAIL=1; fi
}
# Also replay the assertion oracle against a preserved run:
#   tools/check_inherent_lucubration.sh --check-logs logs/runs/<run>
check_assertions() {
    local dir="$1" log bad=0
    [ -d "$dir/logs" ] || { result 1 "missing run logs: $dir"; return 1; }
    for log in "$dir/logs/errors.log" "$dir/errors.log"; do
        if [ -f "$log" ] && grep -Ei 'assert' "$log"; then bad=1; fi
    done
    result "$bad" "$dir has no assertion in its error logs"
    return "$bad"
}
if [ "${1:-}" = --check-logs ]; then
    check_assertions "${2:-}"
    exit "$?"
fi
run() {
    local out status
    out=$(INCURSION_OPTIONS="$OPTIONS" INCURSION_LOAD="$2" tools/headless.sh "tools/keys/$1.keys" 1 2>&1 </dev/null)
    status=$?
    RUN=$(printf '%s\n' "$out" | awk '/^run:/ {print $2}')
    echo "session: $RUN"
    if [ -z "$RUN" ] || [ ! -d "$RUN/logs/screens" ]; then
        printf '%s\n' "$out"
        result 1 "$1 produced no session screens"
        return 1
    fi
    printf '%s\n' "$out" > "$RUN/harness.txt"
    # Check even known assertions: the harness may otherwise tolerate them.
    check_assertions "$RUN"
    if [ "$status" -ne 0 ] && [ "$status" -ne 3 ]; then
        result 1 "$1 harness exit $status (see $RUN/harness.txt)"
        return 1
    fi
    return 0
}
# A negative observation also needs a real, nonempty labelled screen.
observe() {
    local label="$1" text="$2" why="$3" want="${4:-present}" found=1
    local files=("$RUN"/logs/screens/*-"$label".txt)
    if [ ! -s "${files[0]}" ]; then result 1 "$why (missing $label screen)"; return; fi
    grep -qF -- "$text" "${files[@]}" && found=0
    if [ "$want" = absent ]; then
        if [ "$found" -eq 0 ]; then found=1; else found=0; fi
    fi
    result "$found" "$why"
}
mana() {
    local before="$1" after="$2" cost="$3"
    python3 - "$RUN" "$before" "$after" "$cost" <<'PY'
import pathlib, re, sys
root = pathlib.Path(sys.argv[1]) / 'logs/screens'
def read(label):
    files = list(root.glob('*-' + label + '.txt'))
    if len(files) != 1:
        raise ValueError('missing or ambiguous mana screen: ' + label)
    values = re.findall(r'HP:\d+/\d+ Mana:(\d+)/(\d+)', files[0].read_text())
    if len(values) != 1:
        raise ValueError('missing or ambiguous mana status: ' + label)
    return tuple(map(int, values[0]))
try:
    before, after = read(sys.argv[2]), read(sys.argv[3])
    print('  mana: %d/%d -> %d/%d' % (*before, *after))
    assert before[1] == after[1] and before[0] - after[0] == int(sys.argv[4])
except (ValueError, AssertionError) as e:
    print('  mana observation failed:', e)
    sys.exit(1)
PY
    result "$?" "mana falls by $cost between $before and $after"
}
if run inherent-mage "$MAGE"; then
    observe baseline-checklist '[ ] Mage Armour' 'Mage Armour starts unmemorized'
    observe baseline-cast '] Shield' 'baseline cast menu was reached'
    observe baseline-cast '] Mage Armour' 'Mage Armour starts uncastable' absent
    observe baseline-inventory "spellbook [Adventurers' Arts]" 'Mage carries the source book'
    observe feat-pick 'Choose an inherent spell:' 'GainFeat opens the inherent pick menu'
    observe checklist 'Mage Armour (locked) (inherent)' 'Mage Armour is inherent and locked'
    observe cast-menu '] Mage Armour' 'Mage Armour becomes castable without resting'
    observe after-cast 'You feel safe.' 'Mage Armour takes effect'
    mana before-cast after-cast 8
fi
if run lucubration-mage "$MAGE"; then
    observe book-pick 'Choose a spellbook to study:' 'GainFeat opens the book pick menu'
    observe book-pick '[e] spellbook [Elemental Covenant]' 'the selected book kind is carried'
    observe selected '[*] Endure Cold' 'Endure Cold is selected for the next rest'
    observe cast-before '] Alarm' 'unpicked-book control starts memorized'
    observe cast-before '] Endure Cold' 'Endure Cold is not yet memorized' absent
    observe books-before "spellbook [Adventurers' Arts]" 'the control book is carried before dropping'
    observe books-gone 'Wand of Identify' 'post-drop inventory was reached'
    observe books-gone 'spellbook [' 'all six books have left the pack' absent
    observe pending-nobook '[*] Alarm (memorized) (no book)' 'Alarm remains selected with its unstudied book absent'
    observe pending-nobook '[*] Endure Cold' 'studied-book selection survives dropping its book'
    observe rest-msgs 'You awaken feeling well rested and recovered.' 'a full rest completed'
    observe rest-msgs 'could not memorize: Alarm,' 'rest refuses the unstudied-book control'
    observe cast-after '] Endure Cold' 'studied-book spell is memorized after rest'
    observe cast-after '] Alarm' 'unstudied-book spell is not memorized after rest' absent
fi
if run inherent-priest "$PRIEST"; then
    observe symbol-gone ')Neck         :Empty' 'Priest drops the holy symbol before taking the feat'
    observe feat-pick 'Choose an inherent spell:' 'Priest reaches the inherent pick menu'
    observe freed-slot 'Bless (locked) (inherent)' 'Bless is the inherent pick'
    observe cast-menu '] Bless' 'Bless remains castable'
    observe after-cast 'You feel righteous.' 'Bless casts without the holy symbol'
    mana cast-menu after-cast 5
    observe control-refused 'You need to have a holy symbol equipped to cast divine spells.' 'non-inherent Call Light is refused without the symbol'
    mana after-cast control-refused 0
fi
result "$FAIL" 'Inherent Spell and Lucubration observations'
exit "$FAIL"
