#!/bin/bash
# Reproduction for bd inc-b0ii: do `break;` and `continue;` work in loops of the
# module script language? Usage: tools/repro_inc_b0ii.sh [case letters, default a-g]
# Builds one scratch module per case (so an illegal opcode in one case cannot
# hide another), joins a test god in wizard mode, and prints the "B0II" lines.
# Needs ./incursion-headless (BACKEND=posix ./build_macos.sh). Specimens: logs/b0ii/<case>/
. "$(dirname "$0")/check_lib.sh"
CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
SAV=tools/fixtures/chars/druid-shoulder-metal-seed7-opt0822.sav
[ -x ./incursion-headless ] || _check_die 2 "build ./incursion-headless first"

body() { case "$1" in
a) echo '/* while+break; want n=3 */ while (g < 10) { g++; n++; if (n == 3) break; } EActor->IPrint("B0II a while-break n=<num> g=<num>", n, g);' ;;
b) echo '/* for+break; want n=3 */ for (i = 0; i < 10; i++) { g++; n++; if (n == 3) break; } EActor->IPrint("B0II b for-break n=<num> g=<num>", n, g);' ;;
c) echo '/* do-while+break; want n=3 */ do { g++; n++; if (n == 3) break; } while (g < 10); EActor->IPrint("B0II c do-break n=<num> g=<num>", n, g);' ;;
d) echo '/* loop in switch case, code after loop in case; want n=3 after=1 */ switch (1) { case 1: while (g < 10) { g++; n++; if (n == 3) break; } after = 1; } EActor->IPrint("B0II d switch-while-break n=<num> g=<num> after=<num>", n, g, after);' ;;
e) echo '/* continue in bare while; want n=5 */ while (g < 10) { g++; if (g == 2 || g == 4 || g == 6 || g == 8 || g == 10) continue; n++; } EActor->IPrint("B0II e while-continue n=<num> g=<num>", n, g);' ;;
f) echo '/* continue in while inside for; want n=9 */ for (i = 0; i < 3; i++) { g = 0; while (g < 4) { g++; if (g == 2) continue; n++; } } EActor->IPrint("B0II f for-while-continue n=<num> g=<num>", n, g);' ;;
g) echo '/* continue in plain for; want n=5 */ for (i = 0; i < 10; i++) { g++; if (i == 0 || i == 2 || i == 4 || i == 6 || i == 8) continue; n++; } EActor->IPrint("B0II g for-continue n=<num> g=<num>", n, g);' ;;
esac; }

mkdir -p logs/runs logs/b0ii
for c in ${@:-a b c d e f g}; do
  D="logs/b0ii/$c"; rm -rf "$D"; mkdir -p "$D/mod" "$D/save" "$D/logs"
  cp -Rf lib "$D/lib"; ln -sfn "$PWD/inc" "$D/inc"
  {
    echo 'God "Break Continue Test God" {'
    echo '  Lists: * FAVOUR_CHART 1000 50000 60000 70000 80000 90000 100000 110000 120000 130000;'
    echo '  On Event EV_BLESSING {'
    echo '    int16 i, g, n, after; i = 0; g = 0; n = 0; after = 0;'
    echo "    if (EActor->getGodLevel(\$\"Break Continue Test God\") == 1) {"
    echo "      $(body $c)"
    echo '    }'
    echo '    return NOTHING; };'
    echo '}'
  } >> "$D/lib/main.irc"
  INCURSIONPATH="$PWD/$D/" ./incursion-headless -compile main.irc < /dev/null > "$D/compile.log" 2>&1
  [ -f "$D/mod/Incursion.Mod" ] || { echo "case $c: COMPILE FAILED, see $D/compile.log"; tail -5 "$D/compile.log"; continue; }
  RD="$(mktemp -d "$PWD/logs/runs/b0ii-$c.XXXXXX")"; mkdir -p "$RD/mod"
  cp -f "$D/mod/Incursion.Mod" "$RD/mod/Incursion.Mod"
  export INCURSION_LOAD="$SAV" INCURSION_RUN_DIR="$RD"
  INCURSION_OPTIONS="$CHECK_OPTIONS" tools/headless.sh tools/keys/inc-b0ii-join.keys 4 > "$D/headless.out" 2>&1
  echo "case $c: exit $?  run dir $RD"
  grep -rh "B0II" "$RD" 2>/dev/null | sort -u | head -3
  unset INCURSION_LOAD INCURSION_RUN_DIR
done
