#!/bin/bash
# gate: live
# inc-jw0hw (Phase 1): every effect in the effect reel glows, or not, in the
# color the table says. The probe (INCURSION_EFFECT_LIGHT_TABLE, in
# src/EffectReelProbe.cpp) lists the same effects as the reel, calls the
# engine's one decision function (EffectLightDecide, src/EffectLight.cpp) for
# each, and logs "LIGHT <name> <LIT|UNLIT> <class>". This check compares glow
# and color class with tools/fixtures/effect-light-table.tsv. It FAILs on a
# mismatch, on a reel effect missing from the table, and on a table row that
# matches no reel effect. A name that occurs twice is keyed by its ;tag.
# The table classes crimson and darkred are the COL_CRIMSON and COL_DARKRED
# sets; sunlight-yellow is COL_SUNYELLOW (the probe calls it sunyellow).
# INCURSION_LIGHT_TABLE names another table file (a scratch copy for a RED run).
# RED 1: flip a row's glow in a scratch table; the check FAILs naming that row.
# RED 2: remove the EF_GLOW test or the COL_* precedence from EffectLightDecide,
# rebuild; the check FAILs.
# fact: the effect list -- read from the loaded module by the probe, compared with the table at run time; no fixed number
# fact: character -- fixture xsummon-priest-seed5-opt0822
# fact: settings -- options-2026-08-22.dat
# fact: the decision -- computed from the module's damage types, cvals and EF_GLOW / EF_NO_GLOW flags; no dice
# fact: effect scripts that prompt -- the probe skips the same ones as the reel; the table lists none of them
# Exit 0 PASS, 1 FAIL, 2 INCONCLUSIVE (no build, no fixture, no LIGHT_DONE).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
OPTIONS=tools/fixtures/options-2026-08-22.dat
FIXTURE=xsummon-priest-seed5-opt0822
TABLE="${INCURSION_LIGHT_TABLE:-tools/fixtures/effect-light-table.tsv}"

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless is missing. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}
[ -f "$TABLE" ] || { echo "INCONCLUSIVE: table $TABLE is missing."; exit 2; }

LOAD="$(tools/fixture_cache.sh "$FIXTURE")" || {
    echo "INCONCLUSIVE: tools/fixture_cache.sh could not build $FIXTURE."
    exit 2
}

RUN_DIR="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-effect-light-table"
mkdir -p "$RUN_DIR"
KEYS="$RUN_DIR/scene.keys"
echo "@quit" > "$KEYS"

INCURSION_OPTIONS="$OPTIONS" INCURSION_LOAD="$LOAD" INCURSION_RUN_DIR="$RUN_DIR" \
    INCURSION_EFFECT_LIGHT_TABLE=1 \
    tools/headless.sh "$KEYS" "$SEED" > "$RUN_DIR/run.out" 2>&1

log="$RUN_DIR/logs/errors.log"
echo "Specimen: $RUN_DIR"
if ! grep -aq ' LIGHT_DONE ' "$log" 2>/dev/null; then
    echo "INCONCLUSIVE: no LIGHT_DONE line in $log (the probe did not finish)."
    exit 2
fi

python3 -I - "$TABLE" "$log" <<'PY'
import re, sys

table_path, log = sys.argv[1], sys.argv[2]
alias = {"sunlight-yellow": "sunyellow"}

want = {}
for ln in open(table_path, encoding="utf-8"):
    ln = ln.rstrip("\n")
    if not ln or ln.startswith("#") or ln.startswith("effect\t"):
        continue
    f = ln.split("\t")
    if len(f) < 3:
        print("INCONCLUSIVE: malformed table row: %r" % ln)
        sys.exit(2)
    if f[0] in want:
        print("FAIL: table lists %r twice" % f[0])
        sys.exit(1)
    want[f[0]] = (f[1], alias.get(f[2], f[2]))

got = {}
for ln in open(log, encoding="latin-1"):
    m = re.search(r'  LIGHT (.*?)\t(LIT|UNLIT)\t(\S+)\s*$', ln)
    if m:
        if m.group(1) in got:
            print("FAIL: the probe lists %r twice" % m.group(1))
            sys.exit(1)
        got[m.group(1)] = (m.group(2), m.group(3))
if not got:
    print("INCONCLUSIVE: the probe logged no LIGHT line.")
    sys.exit(2)

bad = []
for name in sorted(got):
    if name not in want:
        bad.append("reel effect missing from the table: %s (engine: %s %s)" % ((name,) + got[name]))
    elif got[name] != want[name]:
        bad.append("%s: engine %s %s, table %s %s" % ((name,) + got[name] + want[name]))
for name in sorted(want):
    if name not in got:
        bad.append("table row matches no reel effect: %s" % name)
print("effects in the reel: %d, rows in the table: %d" % (len(got), len(want)))
if bad:
    for b in bad:
        print("  " + b)
    print("FAIL: %d mismatch(es) between the engine's glow decision and the table." % len(bad))
    sys.exit(1)
print("PASS: the engine's glow and color match the table for every reel effect.")
PY
exit $?
