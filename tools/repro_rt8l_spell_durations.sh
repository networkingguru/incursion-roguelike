#!/bin/bash
# inc-rt8l: reproduce the unchanged duration check with the kit-on fixture.
# Each game run retains the check's explicit options and unique run directory.
# This is a reproduction, not a replacement check or a seed-dependent oracle.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
SCRATCH="$(mktemp -d "$ROOT/logs/rt8l-spell-durations.XXXXXX")"
python3 - "$ROOT" "$SCRATCH" <<'PYTHON'
from pathlib import Path
import sys
root, scratch = map(Path, sys.argv[1:])
text = (root / 'tools/check_spell_durations.sh').read_text()
text = text.replace('ROOT="$(cd "$(dirname "$0")/.." && pwd)"',
                    'ROOT="' + str(root) + '"')
text = text.replace('options-2026-08-22.dat', 'options-2026-08-22-kit.dat')
(scratch / 'check-kit.sh').write_text(text)
PYTHON
echo "Specimens: $SCRATCH"
bash "$SCRATCH/check-kit.sh" > "$SCRATCH/check.log" 2>&1 || {
    tail -24 "$SCRATCH/check.log"
    exit 1
}
tail -1 "$SCRATCH/check.log"
