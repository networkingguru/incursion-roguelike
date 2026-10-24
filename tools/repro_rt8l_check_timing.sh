#!/bin/bash
# inc-rt8l: photograph early expiry without rebuilding or changing assertions.
# Every specimen lives under a fresh logs/ directory; uses the current binary.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
BASE="$(mktemp -d "$ROOT/logs/rt8l-timing.XXXXXX")"
python3 - "$ROOT" "$BASE" <<'PY'
from pathlib import Path
import re, sys
root, base = map(Path, sys.argv[1:])
for name in ('divine-sacrifice-after', 'dispel-evil-deflection', 'heal-maladies'):
    text = (root / 'tools/keys' / (name + '.keys')).read_text()
    text = re.sub(r'^@include (\S+)', lambda m: '@include ' + str(root / 'tools/keys' / m[1]), text, flags=re.M)
    if name == 'heal-maladies':
        text = text.split('@dump:para-hold')[0] + '@dump:para-hold\n@quit\n'
    else:
        marker = '@dump:cast' if name == 'divine-sacrifice-after' else '@dump:after-cast'
        text = text.replace(marker, marker + '\nw\n@choose "Examine Player Data"\nDOWN*10\n@until "Inventory:" DOWN\n@dump:stati-after-cast\nESC', 1)
    (base / (name + '.keys')).write_text(text)
PY
for scene in divine-sacrifice-after dispel-evil-deflection heal-maladies; do
    rc=0
    INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
        INCURSION_RUN_DIR="$BASE/$scene" \
        tools/headless.sh "$BASE/$scene.keys" 1 > "$BASE/$scene.txt" 2>&1 || rc=$?
    printf '%s: harness exit %s; %s\n' "$scene" "$rc" "$BASE/$scene/logs/screens"
done
printf 'Specimens: %s\n' "$BASE"
