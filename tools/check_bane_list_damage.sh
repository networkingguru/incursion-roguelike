#!/bin/bash
# gate: live
# inc-1mec: identified Sylvan Scimitar, listed orc versus unlisted kobold.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -x ./incursion-headless ] || {
    echo 'FAIL: build with BACKEND=posix ./build_macos.sh first.'
    exit 1
}
base="$PWD/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-bane-list"
for target in orc kobold; do
    run="$base-$target"
    mkdir -p "$run"
    echo "Specimen directory: $run"
    if ! INCURSION_OPTIONS=tools/gates/Options.Dat INCURSION_RUN_DIR="$run" \
        tools/headless.sh "tools/keys/bane-list-$target.keys" 1 > "$run/harness.log" 2>&1; then
        echo "FAIL: $target session did not complete; see $run/harness.log"
        exit 1
    fi
    if grep -q 'gave up after' "$run/harness.log"; then
        echo "FAIL: $target key script exhausted a screen-search loop"
        exit 1
    fi
done
python3 - "$base" <<'PY'
import pathlib, re, sys
base = sys.argv[1]
hits = {}
for target, name in [('orc', 'black orc'), ('kobold', 'kobold')]:
    screens = pathlib.Path(base + '-' + target) / 'logs/screens'
    def screen(label):
        files = list(screens.glob('*-' + label + '.txt'))
        if len(files) != 1:
            raise SystemExit(f'FAIL: expected one {label} screen in {screens}')
        print(f'Specimen: {files[0]}')
        return files[0].read_text()
    wielded = screen('wielded')
    if '>>b)Weapon' not in wielded or not re.search(r'Sylvan Scimitar', wielded, re.I):
        raise SystemExit('FAIL: identified Sylvan Scimitar not in Weapon Hand')
    hits[target] = screen('hit')
    flat = re.sub(r'\s+', ' ', hits[target])
    if f'hitting the {name}' not in flat:
        raise SystemExit(f'FAIL: no landed hit on {name}')
    if not re.search(r'Damage: \d+d\d+', flat):
        raise SystemExit(f'FAIL: no damage breakdown for {name}')
if '+2 bane' not in hits['orc'] or '+2 bane' in hits['kobold']:
    raise SystemExit('FAIL: list membership control (+2 bane) is incorrect')
if '+2d6 bane' in hits['kobold']:
    raise SystemExit('FAIL: unlisted kobold received +2d6 bane')
if '+2d6 bane' not in hits['orc']:
    raise SystemExit('FAIL: listed black orc lacks +2d6 bane; unlisted kobold has none')
print('PASS: listed black orc shows +2d6 bane; unlisted kobold has none')
PY
