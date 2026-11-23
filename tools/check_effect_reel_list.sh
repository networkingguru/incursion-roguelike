#!/bin/bash
# gate: live
# inc-jw0hw (Review Focus 5): the effect reel misses no effect kind. The probe
# (INCURSION_EFFECT_REEL, src/EffectReelProbe.cpp) lists, from the loaded
# module, every effect whose first component is EA_BLAST, or AR_GLOBE, or an
# AR_FIELD/AR_MFIELD with FI_MODIFIER or FI_BLOCKER, or that carries EF_COLOR_PATTERN
# (a beam or bolt that draws the color pattern), and one Breath Weapon per
# damage type a monster breathes, and one "form" clip per answer of the Pyrotechnics
# prompt (the probe queues the key). This check counts the same things in
# lib/program.i by text, independently of the engine, and compares the two
# counts per kind. The probe logs one REEL line or one REEL_SKIP line per effect
# (a skip names a prompt the reel cannot answer). The posix build runs the probe
# with no recorder: FrameClip does nothing and StopWatch waits 0.
# RED: remove AR_GLOBE from IsReelKind in src/EffectReelProbe.cpp, rebuild; the
# globe counts differ and the check FAILs.
# fact: the effect list -- read from lib/program.i at run time, and from the loaded module by the probe; no fixed number
# fact: character -- fixture xsummon-priest-seed5-opt0822
# fact: settings -- options-2026-08-22.dat
# fact: Pyrotechnics forms -- counted from the RedirectEff(e,$"Pyrotechnics;...") answers in lib/program.i at run time; no fixed number
# fact: breath damage types -- read from the monster attack lines in lib/program.i at run time; no fixed number
# fact: effect scripts that prompt -- the probe skips them by name and logs REEL_SKIP; the check counts each skip as listed
# Exit 0 PASS, 1 FAIL, 2 INCONCLUSIVE (no build, no fixture, no REEL_DONE).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
OPTIONS=tools/fixtures/options-2026-08-22.dat
FIXTURE=xsummon-priest-seed5-opt0822

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless is missing. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}
[ -f lib/program.i ] || { echo "INCONCLUSIVE: lib/program.i is missing. Build first."; exit 2; }

LOAD="$(tools/fixture_cache.sh "$FIXTURE")" || {
    echo "INCONCLUSIVE: tools/fixture_cache.sh could not build $FIXTURE."
    exit 2
}

RUN_DIR="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-effect-reel-list"
mkdir -p "$RUN_DIR"
KEYS="$RUN_DIR/scene.keys"
echo "@quit" > "$KEYS"

INCURSION_OPTIONS="$OPTIONS" INCURSION_LOAD="$LOAD" INCURSION_RUN_DIR="$RUN_DIR" \
    INCURSION_EFFECT_REEL=1 INCURSION_LIGHT_TABLE="$ROOT/tools/fixtures/effect-light-table.tsv" \
    tools/headless.sh "$KEYS" "$SEED" > "$RUN_DIR/run.out" 2>&1

log="$RUN_DIR/logs/errors.log"
echo "Specimen: $RUN_DIR"
if ! grep -aq ' REEL_DONE ' "$log" 2>/dev/null; then
    echo "INCONCLUSIVE: no REEL_DONE line in $log (the probe did not finish)."
    exit 2
fi

python3 -I - "$ROOT/lib/program.i" "$log" <<'PY'
import re, sys, collections

prog, log = sys.argv[1], sys.argv[2]
lines = open(prog, encoding="latin-1").read().split("\n")
hdr = re.compile(r'^(?:\d+ / )*(?:\d+ )?(Spell|Effect|Poison|Disease) "(.*)" : (\d+)')
top = re.compile(r'^(?:\d+ / )*(?:\d+ )?([A-Z][a-z]+) "')
stop_comp = re.compile(r'^(On Event|\}\s*and\s|and\s)')

kinds = collections.Counter()
kinds["form"] = len(re.findall(r'RedirectEff\(e,\s*\$"Pyrotechnics;', "\n".join(lines)))
breath = set()
section = None
mon_lines = []
def flush_monsters():
    # the attack list of each monster: "Attk: <atype> for <dice> <dtype> ..., ...;"
    text = "\n".join(mon_lines)
    del mon_lines[:]
    for blk in re.findall(r'Attk:(.*?);', text, re.S):
        for m in re.finditer(r'(?:^|[,\s])(?:42|48) for (?:\S+ )?(\d+)\b', blk):
            breath.add(int(m.group(1)))
i = 0
while i < len(lines):
    ln = lines[i]
    t = top.match(ln)
    if t:
        section = t.group(1)
    h = hdr.match(ln)
    if h:
        name, eval_ = h.group(2), int(h.group(3))
        comp = []
        for nxt in lines[i + 1:]:
            if top.match(nxt) or stop_comp.match(nxt):
                break
            comp.append(nxt)
        text = "\n".join(comp)
        a = re.search(r'\baval: (\d+);', text)
        aval = int(a.group(1)) if a else 0
        flags = set()
        f = re.search(r'\bFlags: ([0-9, ]+);', text)
        if f:
            flags = set(int(v) for v in f.group(1).split(",") if v.strip())
        rval = 0
        r = re.search(r'\brval: ([^;]*);', text)
        if r and re.fullmatch(r'[0-9a-fx| ]+', r.group(1).strip()):
            for part in r.group(1).split("|"):
                rval |= int(part.strip(), 0)
        if name != "Breath Weapon":
            if eval_ == 1:
                kinds["blast"] += 1
            elif aval == 11:
                kinds["globe"] += 1
            elif aval in (7, 9) and (rval & 0x24):
                kinds["aura"] += 1
            elif aval == 8:      # AR_BARRIER (inc/Defines.h): a wall
                kinds["barrier"] += 1
            elif 117 in flags:   # EF_COLOR_PATTERN (inc/Defines.h): a beam or bolt that draws the color pattern
                kinds["pattern"] += 1
    if section == "Monster":
        mon_lines.append(ln)
    elif mon_lines:
        flush_monsters()
    i += 1
flush_monsters()
kinds["breath"] = len(breath)

probe = collections.Counter()
for ln in open(log, encoding="latin-1"):
    m = re.search(r'  REEL \d+ .* (blast|globe|aura|barrier|breath|pattern|form)$', ln)
    if m:
        probe[m.group(1)] += 1
        continue
    m = re.search(r'  REEL_SKIP (.*?) (?:it |the |shows )', ln)
    if m:
        # a skip is a listed effect that the reel cannot answer; its kind is the
        # kind the text count gives it, so count it under "skipped" and add it below
        probe["skipped"] += 1

total_text = sum(kinds[k] for k in ("blast", "globe", "aura", "barrier", "breath", "pattern", "form"))
total_probe = sum(probe[k] for k in ("blast", "globe", "aura", "barrier", "breath", "pattern", "form")) + probe["skipped"]
print("kind    text-count  probe-reels")
for k in ("blast", "globe", "aura", "barrier", "breath", "pattern", "form"):
    print("%-7s %10d  %11d" % (k, kinds[k], probe[k]))
print("skipped %10s  %11d" % ("-", probe["skipped"]))
print("total   %10d  %11d" % (total_text, total_probe))
bad = []
if kinds["breath"] != probe["breath"]:
    bad.append("breath")
if kinds["form"] != probe["form"]:
    bad.append("form")
deficit = 0
for k in ("blast", "globe", "aura", "barrier", "pattern"):
    if probe[k] > kinds[k]:
        bad.append(k + " (probe lists more than the text)")
    else:
        deficit += kinds[k] - probe[k]
if deficit != probe["skipped"]:
    bad.append("skips (kinds missing from the probe: %d, skips logged: %d)" % (deficit, probe["skipped"]))
if total_text != total_probe:
    bad.append("total")
if bad:
    print("FAIL: the probe's list differs from the text count in: " + ", ".join(bad))
    sys.exit(1)
print("PASS: the reel lists every blast, globe, aura field, wall, color pattern and breath type in lib/program.i.")
PY
exit $?
