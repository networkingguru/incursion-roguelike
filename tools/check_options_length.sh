#!/bin/bash
# gate: smoke
# inc-cjos0 phase 9c C3 (failure-table row C3, case F05): Options.Dat of a length other than OPT_LAST.
#
# WHY THIS EXISTS. OPT_LAST may grow. The reader took exactly OPT_LAST bytes, so a player's
# shorter file was read past its end. The ruling: a SHORT file loads (the bytes it has are kept, every
# later option takes its default); a LONG file (a newer build wrote it) is not read and is never
# overwritten; an EXACT file round-trips. Player::ReadOptionsFile / OptionsFileTooLong (src/Player.cpp).
#
# Drives the real game (tools/headless.sh, loading a frozen character, which reads then rewrites the
# settings file) with a 900-byte settings file whose tail is 0xEE, cut or grown to a chosen length.
# Needs the posix build: BACKEND=posix ./build_macos.sh.
# fact: settings -- tools/fixtures/options-2026-08-22.dat, frozen bytes, 900 of them (the first OPT_LAST bytes)
# fact: character -- tools/fixtures/chars/elf-mage-spotted-seed1.sav, frozen bytes; the run's seed argument cannot change the settings bytes the check compares
# fact: OPT_LAST -- read from inc/Defines.h at run time; the check refuses if it is not 900, the length of the frozen file
#
# Exit 0 pass, 1 behavioural failure, 2 missing or incomplete measurement.
# Mutations confirmed RED on 2026-11-09: read OPT_LAST bytes again (short case); drop the length refusal
# in ReadOptionsFile (long case); drop the OptionsFileTooLong guard in ResetOptions is not driven here.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[ -x ./incursion-headless ] || { echo "INCONCLUSIVE: no incursion-headless; run BACKEND=posix ./build_macos.sh"; exit 2; }
[ ./incursion-headless -nt src/Player.cpp ] || { echo "INCONCLUSIVE: incursion-headless is older than src/Player.cpp; rebuild"; exit 2; }
OL="$(sed -n 's/^#define OPT_LAST[[:space:]]*\([0-9]*\).*/\1/p' inc/Defines.h | head -1)"
[ "$OL" = 900 ] || { echo "INCONCLUSIVE: OPT_LAST is ${OL:-?}, the frozen settings file holds 900"; exit 2; }
FIX=tools/fixtures/options-2026-08-22.dat
SAV=tools/fixtures/chars/elf-mage-spotted-seed1.sav
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

# 900 bytes: the frozen file with its last 7 bytes set to 0xEE (no option default is 0xEE). Only the
# tail changes, so MigrateOptions (which reads bytes before it) treats this and the cut file alike.
head -c 893 "$FIX" > "$WORK/in.base"
head -c 7 /dev/zero | LC_ALL=C tr '\0' '\356' >> "$WORK/in.base"

run() {   # run <name> <settings file> -> $WORK/<name>/Options.Dat after the session
    INCURSION_OPTIONS="$2" INCURSION_LOAD="$SAV" INCURSION_RUN_DIR="$WORK/$1" \
        tools/headless.sh tools/keys/options-roundtrip.keys 1 > "$WORK/$1.out" 2>&1
    echo $? > "$WORK/$1.rc"
}
fail=0
bad() { echo "FAIL: $*"; fail=1; }

run exact "$WORK/in.base"
[ "$(cat "$WORK/exact.rc")" = 0 ] || bad "exact: headless exit $(cat "$WORK/exact.rc")"
# MigrateOptions legitimately restamps the frozen file's older settings; the exact run is the reference.
[ "$(wc -c < "$WORK/exact/Options.Dat")" -eq 900 ] || bad "exact: the file written is not 900 bytes"
cmp -s <(tail -c 7 "$WORK/in.base") <(tail -c 7 "$WORK/exact/Options.Dat") || bad "exact: the last 7 bytes did not round-trip"

K=7; N=$((900 - K))
head -c $N "$WORK/in.base" > "$WORK/in.short"
run short "$WORK/in.short"
[ "$(cat "$WORK/short.rc")" = 0 ] || bad "short: headless exit $(cat "$WORK/short.rc")"
got="$WORK/short/Options.Dat"
[ "$(wc -c < "$got")" -eq 900 ] || bad "short: the file written is $(wc -c < "$got") bytes, not 900"
cmp -s <(head -c $N "$WORK/exact/Options.Dat") <(head -c $N "$got") || bad "short: the bytes the file had were not kept"
kept="$(tail -c $K "$got" | LC_ALL=C tr -d '\356' | wc -c)"
[ $((kept)) -eq $K ] || bad "short: a byte past the file's end was not defaulted"
grep -qiE 'EREADERR|short read|corrupt' "$WORK/short.out" "$WORK/short"/logs/*.log 2>/dev/null && bad "short: a read error was reported"

head -c 900 "$WORK/in.base" > "$WORK/in.long"; head -c 25 /dev/zero | tr '\0' '\001' >> "$WORK/in.long"
run long "$WORK/in.long"
[ "$(cat "$WORK/long.rc")" = 0 ] || bad "long: headless exit $(cat "$WORK/long.rc")"
cmp -s "$WORK/in.long" "$WORK/long/Options.Dat" || bad "long: the longer file was changed"
grep -q "left untouched" "$WORK/long.out" "$WORK/long"/logs/errors.log 2>/dev/null || bad "long: no line named the file and both lengths"

[ $fail -eq 0 ] && echo "PASS: exact round-trips, short loads with defaults after its end, long is untouched"
exit $fail
