#!/bin/bash
# gate: live
# A converted damage event must run its POST(EV_DAMAGE) step once per
# conversion, not twice. (bd inc-e5ke)
#
# THE DEFECT. Creature::Damage (src/Fight.cpp) turns AD_CHAO, AD_LAWF, AD_EVIL,
# AD_HOLY and similar types into AD_NORM and re-delivers the event with
# ReThrow(EV_DAMAGE,e). The inner event runs its own POST step, then the outer
# event runs POST again for the same victim and amount.
#
# THE ORACLE. The probe in src/DmgPostProbe.cpp writes one line per conversion
# ("DMGPOST convert victim=<h> from=<type> sp=<n>") and one per POST step of an
# EV_DAMAGE event ("DMGPOST post victim=<h> dmg=<n> type=<t> sp=<n>") to the
# run's logs/errors.log. For each convert line, the outer POST has sp = convert
# sp and the inner POST has sp = convert sp + 1. Count the post lines for the
# same victim with either sp that follow the convert, before the next convert
# line or a post line for a different victim. Exactly one per conversion is a
# pass.
#
# Usage: tools/check_dmgpost_once.sh   (0 pass, 1 fail, 2 no run)
set -u
cd "$(dirname "$0")/.." || exit 2

RUN="logs/runs/dmgpost-check-$$"
KEYS=tools/keys/dmgpost-chaos.keys
OPTS=tools/fixtures/options-2026-08-22.dat
CHAR=tools/fixtures/chars/lizardfolk-monk-seed1.sav

INCURSION_DMGPOST_PROBE=1 INCURSION_OPTIONS="$OPTS" INCURSION_LOAD="$CHAR" \
    INCURSION_RUN_DIR="$RUN" tools/headless.sh "$KEYS" 1 >"$RUN.out" 2>&1
echo "run dir: $RUN"

LOG="$RUN/logs/errors.log"
if [ ! -f "$LOG" ]; then
    echo "FAIL: no errors.log in $RUN; the probe wrote nothing"
    exit 1
fi

python3 -I - "$LOG" <<'PY'
import re, sys
lines = open(sys.argv[1], errors="replace").read().splitlines()
conv = re.compile(r"DMGPOST convert victim=(\d+) from=(\S+) sp=(\d+)")
post = re.compile(r"DMGPOST post victim=(\d+) dmg=(\S+) type=(\S+) sp=(\d+)")
events = []
for l in lines:
    m = conv.search(l)
    if m:
        events.append(("convert", m.group(1), int(m.group(3)), m.group(2)))
        continue
    m = post.search(l)
    if m:
        events.append(("post", m.group(1), int(m.group(4)), m.group(3)))
convs = [i for i, e in enumerate(events) if e[0] == "convert"]
if not convs:
    print("FAIL: no DMGPOST convert line in errors.log; no conversion ran")
    sys.exit(1)
bad = []
for i in convs:
    _, victim, sp, frm = events[i]
    n = 0
    for e in events[i + 1:]:
        if e[0] == "convert":
            break
        if e[0] == "post" and e[1] != victim:
            break
        if e[0] == "post" and e[2] in (sp, sp + 1):
            n += 1
    if n != 1:
        bad.append((victim, sp, frm, n))
for victim, sp, frm, n in bad:
    print(f"FAIL: conversion victim={victim} from={frm} sp={sp} had {n} POST lines, want 1")
if bad:
    for l in lines:
        if "DMGPOST" in l:
            print("  " + l)
    sys.exit(1)
print(f"PASS: {len(convs)} conversion(s), each with exactly one POST")
PY
