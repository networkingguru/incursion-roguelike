#!/bin/bash
# gate: live
# inc-u1xj: the undead-rider rule (Map::enUndeadMount) must give an undead
# rider a mount template the mount can take. A mount that refuses every
# candidate must go unmounted; a mount that takes one must keep it and build it.
# Probe: src/UndeadMountProbe.cpp (INCURSION_UNDEAD_MOUNT_PROBE).
# Build: BACKEND=posix ./build_macos.sh
# Run: tools/check_undead_mount.sh
# Exit 0 only when the giant spider case is unmounted or built with its template
# and the pony case keeps and builds its template; anything else exits 1.
# fact: character -- fixture tools/fixtures/chars/xsummon-priest-seed5-opt0822.sav (INCURSION_LOAD)
# fact: settings -- tools/fixtures/options-2026-08-22.dat (INCURSION_OPTIONS)
# fact: map and encounter -- the fixture save pins the dungeon (INCURSION_LOAD); "Vault Monster" is a named encounter, not rolled
# fact: rider goblin, mount giant spider, mount pony -- named resources (FIND), not drawn
# fact: rider becomes undead -- enAddTemp of template zombie, no roll
# fact: template draw order in enUndeadMount -- outcome-invariant: the spider takes none of the three, the pony takes at least one (checks read kept and built only, never which template)
# fact: stream position when the probe runs -- outcome-invariant for the same reason; the probe makes no roll of its own
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p logs/runs
RUN_DIR="$(mktemp -d "$ROOT/logs/runs/undead-mount.XXXXXX")"
echo "Specimens: $RUN_DIR"
status=0
INCURSION_BIN="$ROOT/incursion-headless" \
INCURSION_UNDEAD_MOUNT_PROBE=1 INCURSION_RUN_DIR="$RUN_DIR" \
INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
INCURSION_LOAD=tools/fixtures/chars/xsummon-priest-seed5-opt0822.sav \
    tools/headless.sh tools/keys/template-alignment.keys 1 \
    > "$RUN_DIR/harness.txt" 2>&1 || status=$?
log="$RUN_DIR/logs/undead-mount.log"
if [ ! -s "$log" ]; then
    echo "FAIL: missing probe log (harness exit $status)."
    exit 1
fi
cat "$log"
if [ "$status" -ne 0 ]; then
    echo "FAIL: harness exit $status; see $RUN_DIR/harness.txt"
    exit 1
fi
python3 -I - "$log" <<'PY'
from pathlib import Path
import re, sys
lines = Path(sys.argv[1]).read_text().splitlines()
if len(lines) != 3 or lines[2] != 'DONE':
    sys.exit('FAIL: incomplete probe evidence: %r' % lines)
pat = re.compile(r'mount=(giant spider|pony) kept=([01]) htID=(\S.*?) built=([01])')
rows = {}
for line in lines[:2]:
    m = pat.fullmatch(line)
    if not m:
        sys.exit('FAIL: unparsable probe line: %r' % line)
    rows[m.group(1)] = (int(m.group(2)), m.group(3), int(m.group(4)))
if set(rows) != {'giant spider', 'pony'}:
    sys.exit('FAIL: expected giant spider and pony lines, got %r' % sorted(rows))
kept, htid, built = rows['giant spider']
if kept and (htid == 'none' or not built):
    sys.exit('FAIL: giant spider kept template %s but the build refused it.' % htid)
kept, htid, built = rows['pony']
if not kept or htid == 'none' or not built:
    sys.exit('FAIL: pony did not keep and build its template (kept=%d htID=%s built=%d).' % (kept, htid, built))
print('PASS: giant spider kept=%d; pony kept=%d built=%d.' % (rows['giant spider'][0], kept, built))
PY
