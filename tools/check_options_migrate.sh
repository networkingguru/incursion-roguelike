#!/bin/bash
# inc-4mxm: the options file's version field, OPT_SETTINGS_GEN, and the
# migration that reads it.
#
# WHY THIS EXISTS. The options file is a bare array of one byte per option with
# no header, so an option added later reads 0 from every file written before it
# existed. 0 is a perfectly good menu index, so without a version field a new
# option comes up at its FIRST choice rather than its intended default, and the
# only defence was to promise 0 keeps its old meaning forever -- which forces
# every new option's scale to be ordered around the byte instead of around the
# player reading it. MigrateOptions (src/OptionsGen.cpp) ends that.
#
# The case that matters most is `chosen`: a file in which the player has
# deliberately picked the FIRST choice is byte-for-byte identical to an
# unmigrated file except for the stamp. A migration that looked at the option
# values instead of the stamp would pass every other case here and quietly
# overwrite that player's setting on every load.
#
# Links tools/options_migrate_probe.cpp against the real src/OptionsGen.o,
# which has no undefined symbols at all, so this needs no stubs, no game
# session and no options fixture.
#
# Exit 0 pass, 1 behavioural failure, 2 missing or incomplete measurement.
#
# Mutations confirmed RED here on 2026-10-11 (at OPT_GEN_CURRENT = 2):
#   drop the `gen >= OPT_GEN_CURRENT` guard   (a newer file is stamped backwards)
#   judge by the option values, not the stamp (a chosen Dimmest is overwritten)
#   drop the stamp write                      (nothing ever settles)
#   stamp with OPT_GEN_NONE                   (the same)
#   also write a neighbouring option          (it clobbers an untouched setting)
#   migrate to Dimmer rather than Normal      (an old file lands off default)
#   value-sniff the light branch, guard kept   (a chosen Dimmest is overwritten)
#   drop the generation-2 branch              (312 is left at the zero byte)
#
# Two further mutations remain EQUIVALENT at generation 2, and are deliberately
# not claimed above: `gen >` for `gen >=`, and stamping before the branch
# instead of after. Both are no-ops because `gen` is copied into a local before
# anything is written, and every branch then tests that local with a strict `<`;
# a file stamped exactly at OPT_GEN_CURRENT fires no branch, so raising the
# stamp (the same value) first or falling through the guard both leave the array
# unchanged. Only `gen`-driven value-sniffing becomes real once a second
# generation exists, because a file stamped at the older generation now passes
# the guard and reaches the sniff.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OBJ="${INCURSION_OPTGEN_OBJ:-build/obj-incursion-headless/OptionsGen.o}"
[ -f "$OBJ" ] || {
    echo "INCONCLUSIVE: $OBJ is missing; run BACKEND=posix ./build_macos.sh"
    exit 2
}
[ "$OBJ" -nt src/OptionsGen.cpp ] || {
    echo "INCONCLUSIVE: $OBJ is older than src/OptionsGen.cpp; rebuild first"
    exit 2
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

CXX="${CXX:-clang++}"
$CXX -std=c++17 -O2 -fpermissive -Wno-narrowing -w -DPOSIX_TERM \
     -Iinc -Ilib -Icompat -c tools/options_migrate_probe.cpp \
     -o "$WORK/probe.o" || {
    echo "INCONCLUSIVE: the probe did not compile"
    exit 2
}
$CXX -std=c++17 -o "$WORK/probe" "$WORK/probe.o" "$OBJ" || {
    echo "INCONCLUSIVE: the probe did not link against $OBJ"
    exit 2
}
"$WORK/probe" > "$WORK/out.txt" || {
    echo "INCONCLUSIVE: the probe did not run to completion"
    exit 2
}

python3 - "$WORK/out.txt" <<'PYCODE'
import sys

rows, flags, consts = {}, {}, {}
for line in open(sys.argv[1]).read().splitlines():
    f = line.split()
    if not f:
        continue
    if len(f) == 5:
        rows[f[0]] = tuple(int(x) for x in f[1:])
    elif len(f) == 2:
        if f[0].startswith("GEN_"):
            consts[f[0]] = int(f[1])
        else:
            flags[f[0]] = int(f[1])

WANT_CASES = ["old", "chosen", "future", "twice", "kept",
              "gen1", "off-at-gen2", "gen0"]
missing = [c for c in WANT_CASES if c not in rows] + \
          ([] if "old-neighbours" in flags else ["old-neighbours"])
need_consts = ["GEN_NONE", "GEN_LIGHT_TRIM", "GEN_AUTO_TERMS", "GEN_CURRENT"]
missing += [c for c in need_consts if c not in consts]
if missing:
    print("INCONCLUSIVE: the probe did not report: %s" % ", ".join(missing))
    sys.exit(2)

DIMMEST, DIMMER, NORMAL, BRIGHTER, BRIGHTEST = 0, 1, 2, 3, 4
GEN_NONE = consts["GEN_NONE"]
GEN_LIGHT_TRIM = consts["GEN_LIGHT_TRIM"]
GEN_AUTO_TERMS = consts["GEN_AUTO_TERMS"]
GEN_CURRENT = consts["GEN_CURRENT"]

fails = []
def check(cond, msg):
    if not cond:
        fails.append(msg)

# 1. The case every existing installation is in.
check(rows["old"] == (NORMAL, NORMAL, 1, GEN_CURRENT),
      "an options file written before these options existed migrated to %s; "
      "wanted both lights at Normal (%d), byte %d set to 1, and the stamp at %d"
      % (rows["old"], NORMAL, 312, GEN_CURRENT))

# The whole point: an unmigrated file must NOT be left reading the zero byte.
check(rows["old"][0] != DIMMEST and rows["old"][1] != DIMMEST,
      "an old file came out at the zero byte (%s), which is Dimmest, not "
      "Normal -- the migration did nothing" % (rows["old"],))

# 2. Nothing outside the new generations may be touched.
check(flags["old-neighbours"] == 1,
      "the migration changed a neighbouring option; it may write only the "
      "options belonging to a generation newer than the file's")

# 3. The case a value-sniffing migration would get wrong.
check(rows["chosen"] == (DIMMEST, DIMMEST, 1, GEN_CURRENT),
      "a file already at generation %d, in which the player chose Dimmest on "
      "purpose, came back as %s; a deliberate setting MUST survive, and the "
      "stamp is the only thing that distinguishes it from an old file"
      % (GEN_CURRENT, rows["chosen"]))

# 4. A file from a newer build is left alone, stamp included.
check(rows["future"] == (BRIGHTEST, BRIGHTER, 0, GEN_CURRENT + 7),
      "a file from a newer generation came back as %s; downgrading must lose "
      "nothing and must not stamp the file backwards" % (rows["future"],))

# 5. Idempotent, because every read path calls it.
check(rows["twice"] == rows["old"],
      "running the migration twice gave %s, but once gave %s; it is called on "
      "every load and must settle" % (rows["twice"], rows["old"]))

# 6. The round trip: migrate, player picks a setting, load again.
check(rows["kept"] == (NORMAL, BRIGHTEST, 1, GEN_CURRENT),
      "after migrating and then choosing Brightest, a reload gave %s; the "
      "setting a player changed must survive the next load" % (rows["kept"],))

# 7. A file stamped at the light-trim generation gets byte 312 set to 1,
#    with its light options left exactly as written.
check(rows["gen1"] == (BRIGHTEST, DIMMER, 1, GEN_CURRENT),
      "a file stamped at generation %d came back as %s; its light options "
      "must be untouched and byte %d must be set to 1"
      % (GEN_LIGHT_TRIM, rows["gen1"], 312))

# 8. A file already at generation 2 with byte 312 = 0: the player turned the
#    option off. The stamp is current, so the zero must be left alone.
check(rows["off-at-gen2"] == (DIMMEST, DIMMEST, 0, GEN_AUTO_TERMS),
      "a file stamped at generation %d with byte 312 deliberately 0 came back "
      "as %s; a current-generation setting must not be overwritten"
      % (GEN_AUTO_TERMS, rows["off-at-gen2"]))

# 9. A file stamped at generation 0 gets both the light step and byte 312 = 1.
check(rows["gen0"] == (NORMAL, NORMAL, 1, GEN_CURRENT),
      "a file stamped at generation %d came back as %s; it must get both the "
      "light step and byte %d = 1" % (GEN_NONE, rows["gen0"], 312))

if fails:
    for m in fails:
        print("FAIL: " + m)
    sys.exit(1)
print("PASS: %d cases; an old file lands on Normal, a deliberate setting "
      "survives, and a newer file is untouched." % len(rows))
PYCODE
exit $?
