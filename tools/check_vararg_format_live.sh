#!/bin/bash
# gate: live -- it compiles a scratch module and plays a loaded character, so it needs
# BACKEND=posix ./build_macos.sh first.
# inc-ac0l: a script IPrint/Format with a pointer-reading tag crashed the game.
# A script passes int32 handles, never C++ pointers, so <Str> read a handle as
# a pointer (SIGSEGV, exit 139). The guard must log "Bad format in ..." and skip
# the call; the handle-safe <hText> must still print.
#
# Each case is its own run, so one crash cannot mask another. The handler sits
# on the corpse item: the fixture stands among corpses, and every map thing
# gets EV_TURN once per 60 game turns (src/Main.cpp, the Turn%60 loop).
# INCURSION_BIN points the same check at an unfixed binary (it must go red).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
BIN="${INCURSION_BIN:-$ROOT/incursion-headless}"
[ -x "$BIN" ] || { echo "FAIL: $BIN not built. Run: BACKEND=posix ./build_macos.sh"; exit 1; }
case "$BIN" in /*) ;; *) BIN="$ROOT/$BIN" ;; esac
FIX="$ROOT/tools/fixtures/chars/lizardfolk-monk-seed1.sav"
OPTS="$ROOT/tools/fixtures/options-2026-08-22.dat"
KEYS="$ROOT/tools/keys/script-format-live.keys"
BASE="$(mktemp -d "$ROOT/logs/vararg-format-live.XXXXXX")"
fail=0

# name | handler body | marker expected on screen | needle expected in errors.log
cases=(
 "positive|s = \"zzmarkerword\"; pl->IPrint(\"Tithe <hText> end.\", s);|zzmarkerword|"
 "str_tag|pl->IPrint(\"tithe of <Str> gold\", \"gold\");||Bad format in IPrint"
 "runtime_fmt|f = \"tithe of <Str> gold\"; pl->IPrint(f, \"gold\");||Bad format in IPrint"
 "format_s|s = Format(\"%s\", \"gold\"); pl->IPrint(\"made <hText>\", s);||Bad format in Format"
)

for c in "${cases[@]}"; do
    IFS='|' read -r name body marker needle <<< "$c"
    W="$BASE/$name"
    mkdir -p "$W/mod" "$W/save" "$W/logs"
    cp -rf "$ROOT/lib" "$W/lib"
    ln -s "$ROOT/inc" "$W/inc"
    handler="    On Event EV_TURN { hObj pl; String s, f; pl = theGame->GetPlayer(0); if (pl == NULL_OBJ) return NOTHING; $body return NOTHING; };"
    # Insert the handler into the corpse item, after its Desc.
    awk -v h="$handler" '
        /^Item "corpse"/ { inq=1 }
        { print }
        inq && /vulnerable to carried diseases\.";/ { print h; inq=0; done=1 }
        END { exit done ? 0 : 3 }' "$ROOT/lib/mundane.irh" > "$W/lib/mundane.irh" || {
        echo "FAIL[$name]: corpse anchor not found in lib/mundane.irh"; fail=1; continue; }
    INCURSIONPATH="$W/" "$BIN" -compile main.irc < /dev/null > "$W/logs/compile.log" 2>&1 || {
        echo "FAIL[$name]: scratch module did not compile (see $W/logs/compile.log)"; fail=1; continue; }
    [ -f "$W/mod/Incursion.Mod" ] || { echo "FAIL[$name]: no module produced"; fail=1; continue; }
    cp "$FIX" "$W/save/"; chmod u+w "$W/save/$(basename "$FIX")"
    cp "$OPTS" "$W/Options.Dat"
    ( cd "$W" && INCURSIONPATH="$W/" INCURSION_SEED=1 "$BIN" -keys "$KEYS" -load "$(basename "$FIX")" < /dev/null > "$W/logs/run.out" 2>&1 )
    st=$?
    if [ "$st" -ge 128 ] || [ "$st" -eq 1 ]; then
        echo "FAIL[$name]: session died, exit $st (see $W/logs/run.out)"; fail=1; continue
    fi
    if [ ! -f "$W/logs/session.log" ]; then
        echo "FAIL[$name]: no gameplay, so the handler never had a turn (exit $st)"; fail=1; continue
    fi
    if [ -n "$needle" ] && ! grep -Fq "$needle" "$W/logs/errors.log" 2>/dev/null; then
        echo "FAIL[$name]: errors.log lacks \"$needle\""; fail=1; continue
    fi
    if [ -n "$marker" ] && ! grep -rFq "$marker" "$W/logs" --include='*.txt' --include='*.log' 2>/dev/null; then
        echo "FAIL[$name]: marker \"$marker\" never reached the screen dumps or logs"; fail=1; continue
    fi
    echo "  ok: $name (exit $st)"
done

if [ "$fail" -eq 0 ]; then
    echo "PASS script format guard (specimens: $BASE)"
else
    echo "FAIL script format guard (specimens: $BASE)"
fi
exit "$fail"
