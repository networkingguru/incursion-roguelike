#!/usr/bin/env bash
# gate: live
#
# Does the fixture cache repair itself, and stop where repair would hide a defect?
#
# WHAT IS BEING PROVED. Spec section 9 C4 as amended by B3, section 7, A13 (bead
# inc-10v7f, phase 9). A fixture is a cache entry keyed on the .char, its options
# file, the binary and mod/Incursion.Mod. In a scratch cache (never the
# worktree's real one):
#   (a) an edited .char, an edited options file and a different file standing in
#       as the binary each MISS: the lookup builds again (one more line in the
#       build log, a different entry), and the rebuilt character's canonical
#       dump equals the original's, because none of the three edits touches the
#       character. The module is in the key like the other three; its miss is not
#       exercised here because the check does not rewrite mod/Incursion.Mod (B3).
#   (b) a truncated cached .sav is served as it is: tools/headless.sh exits 8
#       with "FIXTURE LOAD FAILED: <name> (<key>)", and the entry is not rebuilt
#       (same bytes, no new line in the build log).
#   (c) four concurrent lookups of one fixture build it once (one line in the
#       build log) and all four print the same path.
#   (d) a lock older than 30 minutes is taken over; a fresh lock is not.
# There is no tag-move or module-slide case (B3): the module is in the key, so a
# slide is always a miss, and the epic tag move is proved by AC6.
#
# RED MUTATIONS (both proved by hand when the check was written):
#   (i)  remove the lock (the mkdir test in tools/fixture_cache.sh always
#        succeeds): (c) finds two lines in the build log.
#   (ii) rebuild on a load failure (tools/headless.sh removes the failed entry
#        and calls the lookup again): (b) finds the truncated bytes gone.
#
# fact: the character -- tools/fixtures/chars/orc-barbarian-seed1-opt0822.char, committed; built from the file alone, no key script and no walk
# fact: the random stream -- the seed: line of that .char feeds the build; build_fixture.sh removes every other INCURSION_* variable; part (b) ends at the load error and reads no drawn value, and every other assertion compares dump hashes of one file under one seed
# fact: the options -- the options: line of the .char names tools/fixtures/options-2026-08-22.dat; part (a) uses a scratch copy of it with one byte appended
# fact: the cache, the locks and the build log -- scratch directories made by this script (INCURSION_FIXTURE_CACHE); the worktree's real cache is never read or written, and INCURSION_FIXTURE_PIN is removed from the environment
# fact: the binary -- INCURSION_BIN or ./incursion-headless; part (a) also runs a scratch copy of it with one byte appended
# fact: the clock -- the age of the lock in (d) is set with touch -t (2 hours); the check waits at most a few seconds in all
#
# Usage: INCURSION_BIN=./incursion-headless tools/check_fixture_repair.sh
# Exit: 0 pass; 1 fail; 2 could not run.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2
BIN="${INCURSION_BIN:-./incursion-headless}"
[ -x "$BIN" ] || { echo "INCONCLUSIVE: $BIN is not built"; exit 2; }
export INCURSION_BIN="$BIN"
unset INCURSION_FIXTURE_PIN INCURSION_FIXTURE_CACHE

NAME=orc-barbarian-seed1-opt0822
CHAR=tools/fixtures/chars/$NAME.char
OPT=tools/fixtures/options-2026-08-22.dat
[ -f "$CHAR" ] && [ -f "$OPT" ] || { echo "INCONCLUSIVE: $CHAR or $OPT is missing"; exit 2; }

W="$(mktemp -d "$ROOT/logs/fixture-repair-check.XXXXXX")" || exit 2
PIDS=""
cleanup() {
    local p
    for p in $PIDS; do kill "$p" 2> /dev/null; done
    rm -rf "$W"
}
trap cleanup EXIT

fail=0
ok()   { echo "ok   $1"; }
bad()  { echo "FAIL $1"; fail=1; }
lines() { if [ -f "$1" ]; then wc -l < "$1" | tr -d ' '; else echo 0; fi; }
dumpsha() { # <sav> -> the SHA-256 of its canonical dump, with the BASE binary
    INCURSION_OPTIONS="$OPT" INCURSION_BIN="$BIN" tools/char_dump.sh "$1" "$W/dump.canon" > /dev/null 2>&1 || return 1
    local h; h="$(shasum -a 256 < "$W/dump.canon")"; printf '%s' "${h%% *}"
}
# lookup <state-dir> [char-path]: the scratch cache is <state-dir>/cache; prints the .sav path.
lookup() {
    local st="$1" ch="${2:-$NAME}"
    INCURSION_FIXTURE_CACHE="$st/cache" tools/fixture_cache.sh "$ch" 2> "$st/lookup.err"
}

# ---------------------------------------------------------------- (a) misses ---
A="$W/a"; mkdir -p "$A"
P0="$(lookup "$A")" || { echo "INCONCLUSIVE: the first build failed: $(tail -1 "$A/lookup.err")"; exit 2; }
D0="$(dumpsha "$P0")" || { echo "INCONCLUSIVE: the dump of the first build failed"; exit 2; }
N0="$(lines "$A/fixture-builds.tsv")"
[ "$N0" = 1 ] || { echo "INCONCLUSIVE: expected one build line after the first build, found $N0"; exit 2; }

miss() { # <label> <path-printed-by-the-lookup>
    local label="$1" p="$2" n h
    n="$(lines "$A/fixture-builds.tsv")"
    h="$(dumpsha "$p")" || { bad "(a) $label: the dump of the rebuilt .sav failed"; return; }
    if [ "$n" = "$((MISSN + 1))" ] && [ "$p" != "$PREV" ] && [ "$h" = "$D0" ]; then
        ok "(a) $label: a miss, rebuilt once, same character (${h:0:12})"
    else
        bad "(a) $label: build lines $MISSN -> $n, entry changed: $([ "$p" != "$PREV" ] && echo yes || echo no), dump ${h:0:12} vs original ${D0:0:12}"
    fi
    MISSN="$n"; PREV="$p"
}
MISSN="$N0"; PREV="$P0"

mkdir -p "$W/e1"
{ cat "$CHAR"; echo "# edited by tools/check_fixture_repair.sh"; } > "$W/e1/$NAME.char"
P="$(lookup "$A" "$W/e1/$NAME.char")" || { bad "(a) edited .char: the lookup failed: $(tail -1 "$A/lookup.err")"; P=""; }
[ -n "$P" ] && miss "an edited .char" "$P"

mkdir -p "$W/e2"
cp "$OPT" "$W/e2/options.dat"
sed "s#^options:.*#options: $W/e2/options.dat#" "$CHAR" > "$W/e2/$NAME.char"
P="$(lookup "$A" "$W/e2/$NAME.char")" || { bad "(a) options file: the first lookup failed: $(tail -1 "$A/lookup.err")"; P=""; }
if [ -n "$P" ]; then
    MISSN="$(lines "$A/fixture-builds.tsv")"; PREV="$P"
    printf 'x' >> "$W/e2/options.dat"
    P="$(lookup "$A" "$W/e2/$NAME.char")" || { bad "(a) an edited options file: the lookup failed: $(tail -1 "$A/lookup.err")"; P=""; }
    [ -n "$P" ] && miss "an edited options file" "$P"
fi

mkdir -p "$W/e3"
cp "$BIN" "$W/e3/incursion-headless"
printf 'x' >> "$W/e3/incursion-headless"
# The base binary's entry may have been pruned by now (3 newest keys stay), so
# look it up first; the substitute binary must then miss on top of that.
PREV="$(lookup "$A")" || { echo "INCONCLUSIVE: the lookup with the base binary failed: $(tail -1 "$A/lookup.err")"; exit 2; }
MISSN="$(lines "$A/fixture-builds.tsv")"
P="$(INCURSION_BIN="$W/e3/incursion-headless" lookup "$A")" || { bad "(a) a different binary: the lookup failed: $(tail -1 "$A/lookup.err")"; P=""; }
[ -n "$P" ] && miss "a different binary" "$P"

# ------------------------------------------------- (b) truncated, exit 8 ---
B="$W/b"; mkdir -p "$B"
PB="$(lookup "$B")" || { echo "INCONCLUSIVE: the build for part (b) failed: $(tail -1 "$B/lookup.err")"; exit 2; }
KEYB="$(basename "$(dirname "$PB")")"
head -c 20000 "$PB" > "$B/trunc.sav" && cp -f "$B/trunc.sav" "$PB"
SUMB="$(shasum -a 256 < "$PB")"
NB="$(lines "$B/fixture-builds.tsv")"
INCURSION_FIXTURE_CACHE="$B/cache" INCURSION_OPTIONS="$OPT" INCURSION_RUN_DIR="$B/run" INCURSION_LOAD="$NAME" \
    tools/headless.sh tools/keys/load-char-sheet.keys 1 > "$B/headless.out" 2>&1
RCB=$?
SUMB2="$(shasum -a 256 < "$PB" 2> /dev/null)"
NB2="$(lines "$B/fixture-builds.tsv")"
if [ "$RCB" = 8 ] && grep -qx "FIXTURE LOAD FAILED: $NAME ($KEYB)" "$B/headless.out" && [ "$SUMB" = "$SUMB2" ] && [ "$NB" = "$NB2" ]; then
    ok "(b) a truncated cached .sav exits 8 with the FIXTURE LOAD FAILED line, and is not rebuilt"
else
    bad "(b) truncated .sav: exit $RCB (want 8), message $(grep -c "FIXTURE LOAD FAILED: $NAME ($KEYB)" "$B/headless.out") line(s), entry bytes $([ "$SUMB" = "$SUMB2" ] && echo kept || echo CHANGED), build lines $NB -> $NB2"
fi

# ------------------------------------------------------ (c) concurrency ---
C="$W/c"; mkdir -p "$C"
for i in 1 2 3 4; do
    ( INCURSION_FIXTURE_CACHE="$C/cache" tools/fixture_cache.sh "$NAME" > "$C/out.$i" 2> "$C/err.$i"; echo $? > "$C/rc.$i" ) &
    PIDS="$PIDS $!"
done
wait
PIDS=""
NC="$(lines "$C/fixture-builds.tsv")"
SAME=1
for i in 2 3 4; do cmp -s "$C/out.1" "$C/out.$i" || SAME=0; done
RCS="$(cat "$C"/rc.* | sort -u | tr '\n' ' ')"
if [ "$NC" = 1 ] && [ "$SAME" = 1 ] && [ "$RCS" = "0 " ] && [ -f "$(cat "$C/out.1")" ]; then
    ok "(c) four concurrent lookups built the fixture once and agree on the path"
else
    bad "(c) four concurrent lookups: $NC build line(s) (want 1), same path: $SAME, exit codes: $RCS"
fi

# ------------------------------------------------------------ (d) the lock ---
D="$W/d"; mkdir -p "$D/fixture-locks/$NAME"
OLD="$(date -v-2H +%Y%m%d%H%M 2> /dev/null || date -d '2 hours ago' +%Y%m%d%H%M)"
touch -t "$OLD" "$D/fixture-locks/$NAME"
( INCURSION_FIXTURE_CACHE="$D/cache" tools/fixture_cache.sh "$NAME" > "$D/out" 2> "$D/err"; echo $? > "$D/rc" ) &
PIDS="$!"
for _ in $(seq 1 100); do [ -f "$D/rc" ] && break; sleep 0.1; done
if [ -f "$D/rc" ] && [ "$(cat "$D/rc")" = 0 ] && [ -f "$(cat "$D/out")" ] && grep -q "older than 30 minutes" "$D/err" && [ "$(lines "$D/fixture-builds.tsv")" = 1 ]; then
    ok "(d) a lock older than 30 minutes was taken over, and the fixture built"
else
    bad "(d) a stale lock was not taken over (exit $(cat "$D/rc" 2> /dev/null || echo none); $(tail -1 "$D/err" 2> /dev/null))"
fi
PIDS=""

F="$W/f"; mkdir -p "$F/fixture-locks/$NAME"
( INCURSION_FIXTURE_CACHE="$F/cache" tools/fixture_cache.sh "$NAME" > "$F/out" 2> "$F/err"; echo $? > "$F/rc" ) &
PIDS="$!"
sleep 1.5
if [ ! -f "$F/rc" ]; then
    rmdir "$F/fixture-locks/$NAME"
    for _ in $(seq 1 100); do [ -f "$F/rc" ] && break; sleep 0.1; done
    if [ "$(cat "$F/rc" 2> /dev/null)" = 0 ] && [ "$(lines "$F/fixture-builds.tsv")" = 1 ]; then
        ok "(d) a fresh lock held the lookup back until it was released"
    else
        bad "(d) a fresh lock: after release the lookup did not finish cleanly (exit $(cat "$F/rc" 2> /dev/null || echo none))"
    fi
else
    bad "(d) a fresh lock did not hold the lookup back (it finished with exit $(cat "$F/rc"))"
fi
PIDS=""

[ "$fail" -eq 0 ] && { echo "PASS: the cache misses on a changed input, keeps a broken entry, builds once and takes over a stale lock"; exit 0; }
exit 1
