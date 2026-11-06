#!/bin/bash
# gate: live
# gate-serial: writes and rm -rf's the fixed scratch path logs/script-loops/
# Does `break;` leave the innermost for, while, do-while or switch, and does
# `continue;` go to the next pass of the innermost loop, in the module script
# language? (bd inc-b0ii)
#
# THE DEFECT. Only `switch` pushed a break target, so `break;` in a loop did
# nothing and `break;` in a loop inside a switch left the switch. Only `for`
# resolved `continue;`, so a bare `while` ignored it and a `while` inside a
# `for` jumped to the `for`'s increment. The fix is in lang/Grammar.acc and
# src/RComp.cpp (VBlock::AddBreakTarget, VBlock::ProcessContinues).
#
# THE ROUTE. One scratch module per case (so one bad case cannot hide another):
# lib/ is copied under logs/script-loops/<case>/, a test god whose EV_BLESSING
# handler runs the case body is appended to the COPY of lib/main.irc, and the
# copy is compiled with ./incursion-headless -compile. A frozen druid joins the
# god through the wizard menu (tools/keys/inc-b0ii-join.keys), the handler runs
# and prints one "B0II <case> ..." line, and the check compares that line with
# the value the language rules give. The tracked lib/ is never touched.
#
# A BROKEN FIX MUST NOT HANG. Every loop body opens with a pass counter that
# prints LOOPGUARD and leaves the handler after 60 passes, a route independent
# of the statement under test. tools/headless.sh also stops a session that
# stops asking for keys (exit 4), which check_run-style handling reports FAIL.
#
# CASES (the value is what a correct compiler prints):
#   a while+break          b for+break           c do-while+break
#   d break in a loop in a switch case; code after the loop in the case runs
#   e continue in a bare while           f continue in a while inside a for
#   g continue in a plain for            h switch in a loop: case break leaves
#   only the switch, a later loop break leaves the loop
#   i nested loops: inner break leaves only the inner loop
#   j continue in a for inside a while
#   k return from inside a loop inside a switch, then the handler runs again
#   l a switch with case 62 inside a while (ProcessContinues must not read the
#   jump table as code)
#   n a for loop whose continue is over 511 words before the body's end: the
#   continue skips the rest, and the padding after it ran intact (an extended
#   jump word; the old memmove moved too few bytes)
#   m continue inside a switch inside a loop leaves no stale break target (a stale
#   entry makes the later `break;` of the enclosing switch land inside the loop)
#
# PROVING IT RED: `tools/check_script_loops.sh --prove-red` makes
# VBlock::AddBreakTarget return at once, rebuilds, and expects this check to
# fail (cases a b c d i h k change). Two further mutations are recorded in bd
# inc-b0ii: while/do without ProcessContinues (e j m change), and ProcessContinues
# without its JTAB skip (l changes).
#
# SEED INDEPENDENCE (docs/VERIFICATION.md, "A check must not depend on the seed"):
# fact: character -- fixture druid-shoulder-metal-seed7-opt0822 (INCURSION_LOAD)
# fact: settings -- CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
# fact: the handler runs once the character is a champion -- wizard "Become Divine Champion" on a scratch god, no roll
# fact: the printed numbers -- loop counters in the scratch script, no random call
# fact: the text matched ("B0II <case> ...") -- the scratch script's own text, not seed-chosen
# The seed argument stays 4 because tools/headless.sh needs one; the check reads no seed.
#
# Usage: tools/check_script_loops.sh [--prove-red] [case letters, default all]
. "$(dirname "$0")/check_lib.sh"
CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
SAV=tools/fixtures/chars/druid-shoulder-metal-seed7-opt0822.sav
check_mutation src/RComp.cpp 'int32 rel = size + 1;' 'return; int32 rel = size + 1;'

[ -x ./incursion-headless ] || _check_die 2 "build ./incursion-headless first (BACKEND=posix ./build_macos.sh)"

G='z++; if (z > 60) { EActor->IPrint("B0II LOOPGUARD"); return NOTHING; }'

body() { case "$1" in
a) echo "while (g < 10) { $G g++; n++; if (n == 3) break; } EActor->IPrint(\"B0II a while-break n=<num> g=<num>\", n, g);" ;;
b) echo "for (i = 0; i < 10; i++) { $G g++; n++; if (n == 3) break; } EActor->IPrint(\"B0II b for-break n=<num> g=<num>\", n, g);" ;;
c) echo "do { $G g++; n++; if (n == 3) break; } while (g < 10); EActor->IPrint(\"B0II c do-break n=<num> g=<num>\", n, g);" ;;
d) echo "switch (1) { case 1: while (g < 10) { $G g++; n++; if (n == 3) break; } after = 1; } EActor->IPrint(\"B0II d switch-while-break n=<num> g=<num> after=<num>\", n, g, after);" ;;
e) echo "while (g < 10) { $G g++; if (g == 2 || g == 4 || g == 6 || g == 8 || g == 10) continue; n++; } EActor->IPrint(\"B0II e while-continue n=<num> g=<num>\", n, g);" ;;
f) echo "for (i = 0; i < 3; i++) { $G g = 0; while (g < 4) { $G g++; if (g == 2) continue; n++; } } EActor->IPrint(\"B0II f for-while-continue n=<num> g=<num>\", n, g);" ;;
g) echo "for (i = 0; i < 10; i++) { $G g++; if (i == 0 || i == 2 || i == 4 || i == 6 || i == 8) continue; n++; } EActor->IPrint(\"B0II g for-continue n=<num> g=<num>\", n, g);" ;;
h) echo "while (g < 10) { $G g++; switch (g) { case 1: n += 1; break; case 2: n += 10; break; default: n += 100; } after++; if (g == 3) break; } EActor->IPrint(\"B0II h loop-switch n=<num> g=<num> after=<num>\", n, g, after);" ;;
i) echo "for (i = 0; i < 3; i++) { $G for (j = 0; j < 10; j++) { $G n++; if (j == 1) break; } m++; } EActor->IPrint(\"B0II i nested-break n=<num> m=<num>\", n, m);" ;;
j) echo "while (g < 3) { $G g++; for (i = 0; i < 4; i++) { $G if (i == 1) continue; n++; } m++; if (g == 2) continue; after++; } EActor->IPrint(\"B0II j while-for-continue n=<num> m=<num> after=<num>\", n, m, after);" ;;
k) echo "calls++; if (calls == 1) { switch (1) { case 1: while (g < 10) { $G g++; if (g == 2) return NOTHING; } n = 99; } n = 98; } if (calls == 2) { while (g < 10) { $G g++; n++; if (n == 3) break; } EActor->IPrint(\"B0II k second-call calls=<num> n=<num> g=<num>\", calls, n, g); }" ;;
l) echo "while (g < 3) { $G g++; switch (g + 61) { case 62: n += 100; break; case 10: n += 1; break; default: n += 10; } if (g == 2) continue; after++; } EActor->IPrint(\"B0II l switch62-in-while n=<num> g=<num> after=<num>\", n, g, after);" ;;
m) echo "switch (2) { case 2: for (i = 0; i < 3; i++) { $G switch (i) { case 0: n++; continue; default: m++; } after++; } n += 1000; break; } x++; EActor->IPrint(\"B0II m continue-in-switch n=<num> m=<num> after=<num> x=<num>\", n, m, after, x);" ;;
n) echo "for (i = 0; i < 6; i++) { $G if (i == 2) continue; $(for k in $(seq 1 160); do printf 'g++; n++; '; done)m++; } EActor->IPrint(\"B0II n long-continue n=<num> g=<num> m=<num>\", n, g, m);" ;;
esac; }

want() { case "$1" in
a) echo "B0II a while-break n=3 g=3" ;;
b) echo "B0II b for-break n=3 g=3" ;;
c) echo "B0II c do-break n=3 g=3" ;;
d) echo "B0II d switch-while-break n=3 g=3 after=1" ;;
e) echo "B0II e while-continue n=5 g=10" ;;
f) echo "B0II f for-while-continue n=9 g=4" ;;
g) echo "B0II g for-continue n=5 g=10" ;;
h) echo "B0II h loop-switch n=111 g=3 after=3" ;;
i) echo "B0II i nested-break n=6 m=3" ;;
j) echo "B0II j while-for-continue n=9 m=3 after=2" ;;
k) echo "B0II k second-call calls=2 n=3 g=3" ;;
l) echo "B0II l switch62-in-while n=120 g=3 after=2" ;;
m) echo "B0II m continue-in-switch n=1001 m=2 after=2 x=1" ;;
n) echo "B0II n long-continue n=800 g=800 m=5" ;;
esac; }

# Case k needs the handler to run twice in one session: the wizard menu gains
# favour ten times, and a rung every 1000 points fires EV_BLESSING once per rung.
chart() { if [ "$1" = k ]; then echo "1000 2000 3000 4000 5000 6000 7000 8000 9000 10000"; else echo "1000 50000 60000 70000 80000 90000 100000 110000 120000 130000"; fi; }

CASES="${*:-a b c d e f g h i j k l m n}"
mkdir -p logs/runs logs/script-loops
FAILS=0; PASSES=0
for c in $CASES; do
  D="logs/script-loops/$c"; rm -rf "$D"; mkdir -p "$D/mod" "$D/save" "$D/logs"
  cp -Rf lib "$D/lib"; ln -sfn "$PWD/inc" "$D/inc"
  {
    echo 'God "Break Continue Test God" {'
    echo "  Lists: * FAVOUR_CHART $(chart "$c");"
    echo '  On Event EV_BLESSING {'
    echo '    int16 i, j, g, n, m, after, z, x; static int16 calls;'
    echo '    i = 0; j = 0; g = 0; n = 0; m = 0; after = 0; z = 0; x = 0;'
    echo "    if (EActor->getGodLevel(\$\"Break Continue Test God\") >= 1) {"
    echo "      $(body "$c")"
    echo '    }'
    echo '    return NOTHING; };'
    echo '}'
  } >> "$D/lib/main.irc"
  INCURSIONPATH="$PWD/$D/" ./incursion-headless -compile main.irc < /dev/null > "$D/compile.log" 2>&1
  if [ ! -f "$D/mod/Incursion.Mod" ]; then
    echo "  FAIL  $c: the scratch script did not compile (see $D/compile.log)"; tail -3 "$D/compile.log" | sed 's/^/        /'
    FAILS=$((FAILS+1)); continue
  fi
  RD="$(mktemp -d "$PWD/logs/runs/script-loops-$c.XXXXXX")"; mkdir -p "$RD/mod"
  cp -f "$D/mod/Incursion.Mod" "$RD/mod/Incursion.Mod"
  INCURSION_LOAD="$SAV" INCURSION_RUN_DIR="$RD" INCURSION_OPTIONS="$CHECK_OPTIONS" \
    tools/headless.sh tools/keys/inc-b0ii-join.keys 4 > "$D/headless.out" 2>&1
  st=$?
  case "$st" in 0|3) ;; *) echo "  FAIL  $c: session ended with exit $st (see $D/headless.out, $RD)"; FAILS=$((FAILS+1)); continue ;; esac
  got="$(grep -rhoE "B0II ($c [^|]*|LOOPGUARD)" "$RD" 2>/dev/null | head -1 | sed 's/ *$//')"
  w="$(want "$c")"
  if [ "$got" = "$w" ]; then
    echo "  PASS  $c: $got"; PASSES=$((PASSES+1))
  else
    echo "  FAIL  $c: want '$w', got '${got:-<no B0II line>}'  ($RD)"; FAILS=$((FAILS+1))
  fi
done
echo
if [ "$FAILS" -ne 0 ]; then
  echo "FAIL: $FAILS of $((FAILS+PASSES)) script-loop cases are wrong"
  exit 1
fi
[ "$PASSES" -gt 0 ] || _check_die 2 "no case ran"
echo "PASS: all $PASSES script-loop cases give the value the language rules give"
exit 0
