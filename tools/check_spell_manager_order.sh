#!/bin/bash
# gate: live
# inc-o5ga: Spell Manager names must be alphabetical within each spell level.
# fact: character and known spells -- fixture orc-mage-seed4-gate via INCURSION_LOAD
# fact: spell names and levels -- read from the run's Known Spells sheet; fixture fixes their source
# fact: displayed names and order -- read names from the run's Spell Manager; assert the ordering invariant
# No combat, random rolls, or world text contributes to this measurement.
# The sheet supplies levels ONLY; order comes exclusively from manager screens.
# This fixture's seven rows fit on one page; require complete sheet coverage.
# PROVED RED with --prove-red: the mutation skips the sort, so table order returns.
# Usage: tools/check_spell_manager_order.sh [--prove-red]
# Exit 0 ordered, 1 out of order, 2 could not measure.
. "$(dirname "$0")/check_lib.sh"

check_mutation src/Managers.cpp \
'    qsort(&rowOrder[0], rowOrder.size(), sizeof(int16), SpellManagerRowCmp);' \
'    (void)SpellManagerRowCmp;'

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
FIXTURE=tools/fixtures/chars/orc-mage-seed4-gate.sav
[ -f "$FIXTURE" ] || _check_die 2 "no $FIXTURE to load."
export INCURSION_LOAD="$FIXTURE"
export INCURSION_CHAR_PROBE=1
check_run tools/keys/spell-manager-order.keys 4
check_screens '*-spell-manager-order'

python3 - "$CHECK_RUN/logs/charprobe.txt" "${CHECK_SCREENS[@]}" <<'PY'
import collections
import pathlib
import re
import sys


def unmeasured(reason):
    print(f"INCONCLUSIVE: {reason}")
    sys.exit(2)


def read(path):
    try:
        return pathlib.Path(path).read_text()
    except (OSError, UnicodeError) as exc:
        unmeasured(f"cannot read {path}: {exc}")


sheet = read(sys.argv[1])
section = re.search(r"^Known Spells:\s*\n(.*?)(?=^\S|\Z)", sheet,
                    re.MULTILINE | re.DOTALL)
if not section:
    unmeasured("no Known Spells section in the captured sheet")
levels = collections.defaultdict(set)
for line in section.group(1).splitlines():
    if not line.strip():
        continue
    match = re.fullmatch(r"\s+(.+?)\s{2,}([0-9])\s+\d+%\s+.*", line)
    if not match:
        unmeasured(f"unrecognised Known Spells row: {line!r}")
    levels[match[1].strip().casefold()].add(int(match[2]))

rows = []
for path in sys.argv[2:]:
    lines = read(path).splitlines()
    headers = [i for i, line in enumerate(lines)
               if "Key Spell" in line and "Src Mana" in line]
    if len(headers) != 1:
        unmeasured(f"missing or ambiguous Spell Manager header in {path}")
    header = lines[headers[0]]
    start, end = header.index("Spell"), header.index("Src")
    for line in lines[headers[0] + 1:]:
        # Rows have a bracketed selection key before the fixed name column.
        if not re.search(r"\[.\]\s*$", line[:start]):
            break
        name = line[start:end].strip()
        if not name:
            unmeasured(f"empty manager name in {path}")
        rows.append(name)

if not rows:
    unmeasured("no Spell Manager rows captured")
groups = collections.defaultdict(list)
for name in rows:
    choices = levels.get(name.casefold(), set())
    if len(choices) != 1:
        unmeasured(f"manager name {name!r} maps to {len(choices)} sheet levels")
    groups[next(iter(choices))].append(name)
missing = set(levels) - {name.casefold() for name in rows}
if missing:
    unmeasured("incomplete manager capture; missing: " + ", ".join(sorted(missing)))
if not any(len(names) >= 2 for names in groups.values()):
    unmeasured("no spell level has two or more manager rows")

failed = False
for level, names in groups.items():
    expected = sorted(names, key=str.casefold)
    if names != expected:
        failed = True
        print(f"FAIL level {level}:")
        print("  displayed: " + " -> ".join(names))
        print("  expected:  " + " -> ".join(expected))
        for left, right in zip(names, names[1:]):
            if left.casefold() > right.casefold():
                print(f"  out of order: {left} > {right}")
    else:
        print(f"ok level {level}: " + " -> ".join(names))
print(f"Measured {len(rows)} manager rows across {len(groups)} spell levels.")
sys.exit(1 if failed else 0)
PY
status=$?
case "$status" in
    0|1|2) exit "$status" ;;
    *) _check_die 2 "row parser failed (exit $status)." ;;
esac
