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
# Mutations confirmed RED here on 2026-09-10:
#   drop the `gen >= OPT_GEN_CURRENT` guard   (a newer file is stamped backwards)
#   judge by the option values, not the stamp (a chosen Dimmest is overwritten)
#   drop the stamp write                      (nothing ever settles)
#   stamp with OPT_GEN_NONE                   (the same)
#   also write a neighbouring option          (it clobbers an untouched setting)
#   migrate to Dimmer rather than Normal      (an old file lands off default)
#
# Three further mutations are EQUIVALENT while only one generation exists, and
# are deliberately not claimed above: `gen >` for `gen >=`, stamping before the
# branch instead of after, and value-sniffing with the guard left in place. The
# first two are no-ops because `gen` is read into a local before anything is
# written; the third never reaches its test. Each becomes a real defect the
# moment OPT_GEN_CURRENT reaches 2, so add a case here when that happens.
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

rows, flags = {}, {}
for line in open(sys.argv[1]).read().splitlines():
    f = line.split()
    if not f:
        continue
    if len(f) == 4:
        rows[f[0]] = tuple(int(x) for x in f[1:])
    elif len(f) == 2:
        flags[f[0]] = int(f[1])

WANT_CASES = ["old", "chosen", "future", "twice", "kept"]
missing = [c for c in WANT_CASES if c not in rows] + \
          ([] if "old-neighbours" in flags else ["old-neighbours"])
if missing:
    print("INCONCLUSIVE: the probe did not report: %s" % ", ".join(missing))
    sys.exit(2)

DIMMEST, DIMMER, NORMAL, BRIGHTER, BRIGHTEST = 0, 1, 2, 3, 4
GEN_NONE, GEN_CURRENT = 0, 1

fails = []
def check(cond, msg):
    if not cond:
        fails.append(msg)

# 1. The case every existing installation is in.
check(rows["old"] == (NORMAL, NORMAL, GEN_CURRENT),
      "an options file written before these options existed migrated to %s; "
      "wanted both at Normal (%d) and the stamp at %d"
      % (rows["old"], NORMAL, GEN_CURRENT))

# The whole point: an unmigrated file must NOT be left reading the zero byte.
check(rows["old"][0] != DIMMEST and rows["old"][1] != DIMMEST,
      "an old file came out at the zero byte (%s), which is Dimmest, not "
      "Normal -- the migration did nothing" % (rows["old"],))

# 2. Nothing outside the new generation may be touched.
check(flags["old-neighbours"] == 1,
      "the migration changed a neighbouring display option; it may write only "
      "the options belonging to a generation newer than the file's")

# 3. The case a value-sniffing migration would get wrong.
check(rows["chosen"] == (DIMMEST, DIMMEST, GEN_CURRENT),
      "a file already at generation %d, in which the player chose Dimmest on "
      "purpose, came back as %s; a deliberate setting MUST survive, and the "
      "stamp is the only thing that distinguishes it from an old file"
      % (GEN_CURRENT, rows["chosen"]))

# 4. A file from a newer build is left alone, stamp included.
check(rows["future"] == (BRIGHTEST, BRIGHTER, GEN_CURRENT + 7),
      "a file from a newer generation came back as %s; downgrading must lose "
      "nothing and must not stamp the file backwards" % (rows["future"],))

# 5. Idempotent, because every read path calls it.
check(rows["twice"] == rows["old"],
      "running the migration twice gave %s, but once gave %s; it is called on "
      "every load and must settle" % (rows["twice"], rows["old"]))

# 6. The round trip: migrate, player picks a setting, load again.
check(rows["kept"] == (NORMAL, BRIGHTEST, GEN_CURRENT),
      "after migrating and then choosing Brightest, a reload gave %s; the "
      "setting a player changed must survive the next load" % (rows["kept"],))

if fails:
    for m in fails:
        print("FAIL: " + m)
    sys.exit(1)
print("PASS: %d cases; an old file lands on Normal, a deliberate setting "
      "survives, and a newer file is untouched." % len(rows))
PYCODE
exit $?
