#!/bin/bash
# inc-trfo: reproduction only. Build first: BACKEND=posix ./build_macos.sh
# At least 20 independent seeded triggers; successful REF saves remain samples.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
N="${1:-30}"
[[ "$N" =~ ^[0-9]+$ ]] && [ "$N" -ge 20 ] || { echo 'usage: tools/repro_light_trap.sh [N>=20]' >&2; exit 2; }
OUT="$ROOT/logs/light-trap/repro-$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$OUT"
for ((seed=1; seed<=N; seed++)); do
    INCURSION_OPTIONS="$ROOT/tools/fixtures/options-2026-08-22.dat" \
    INCURSION_LOAD="$ROOT/tools/fixtures/chars/orc-barbarian-seed1-opt0822.sav" \
    INCURSION_RUN_DIR="$OUT/seed-$seed" INCURSION_LIGHT_TRAP_PROBE=1 \
    tools/headless.sh tools/keys/light-trap.keys "$seed" > "$OUT/seed-$seed.log" 2>&1
done
python3 - "$OUT" "$N" <<'PY' | tee "$OUT/summary.txt"
import pathlib, re, statistics, sys
out, n = pathlib.Path(sys.argv[1]), int(sys.argv[2])
raws, turns, ticks = [], [], []
for seed in range(1, n + 1):
    text = (out / f'seed-{seed}.log').read_text()
    assert len(re.findall(r'LIGHT_TRAP trigger', text)) == 1, (seed, 'missing trigger')
    saves = re.findall(r'LIGHT_TRAP save type=(\w+) dc=(-?\d+) rolls_die=(\d+)', text)
    gain = re.findall(r'LIGHT_TRAP gain raw=(\d+) clock=(\d+)', text)
    expiry = re.findall(r'LIGHT_TRAP expiry clock=(\d+)', text)
    print(f'seed={seed} saves={saves}')
    if not gain:
        assert saves and saves[0] == ('REF', '21', '1') and not expiry, seed
        print('  avoided; no blindness')
        continue
    assert len(gain) == len(expiry) == 1, (seed, 'missing or repeated gain/expiry')
    raw, start = map(int, gain[0]); end = int(expiry[0])
    waits = [(int(c), int(b)) for c, b in re.findall(r'LIGHT_TRAP wait clock=(\d+) blind=(\d+)', text)]
    blinded = [c for c, b in waits if start <= c < end and b]
    seen = next(c for c, b in waits if c >= end and not b)
    assert blinded and all(b-a == 16 for a,b in zip(blinded, blinded[1:])), seed
    elapsed = len(blinded)
    assert seen - blinded[0] == elapsed * 16, seed
    raws.append(raw); turns.append(elapsed); ticks.append(end-start)
    print(f'  raw={raw} gain_clock={start} expiry_clock={end} sight_at_wait_clock={seen} elapsed_ticks={end-start} player_wait_turns={elapsed}')
assert len(raws) >= 20, f'Only {len(raws)} blinded samples; rerun with more seeds (e.g. 60)'
print(f'triggers={n} blinded={len(raws)} avoided={n-len(raws)}')
for name, values in [('raw_duration', raws), ('player_wait_turns', turns), ('elapsed_clock_ticks', ticks)]:
    print(f'{name}: min={min(values)} mean={statistics.mean(values):.3f} max={max(values)}')
print('Wait costs Timeout=15 but measured action spacing is 16 ticks (scheduler re-entry); Duration unit = 60 ticks.')
print(f'Logs, copied saves, and screen dumps: {out}')
PY
