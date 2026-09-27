#!/bin/bash
# gate: live -- it compiles a sandbox module with the built binary, so it needs
# BACKEND=posix ./build_macos.sh first.
# inc-glnx: reach the resource-owner check through case-insensitive FIND.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d "$ROOT/logs/script-var-compile.XXXXXX")"
mkdir -p "$WORK/mod" "$WORK/save" "$WORK/logs"
cp -rf "$ROOT/lib" "$WORK/lib"
ln -s "$ROOT/inc" "$WORK/inc"
printf '\nEffect "owner oracle" : EA_NOTIMP {}\nEffect "OWNER ORACLE" : EA_NOTIMP { int32 ownerProbe; }\n' >> "$WORK/lib/main.irc"
status=0
INCURSIONPATH="$WORK/" "${INCURSION_BIN:-$ROOT/incursion-headless}" -compile main.irc < /dev/null > "$WORK/logs/compile.log" 2>&1 || status=$?
grep -Fq "owner lookup differs from resource" "$WORK/logs/compile.log"
[ "$status" != 0 ] && [ ! -f "$WORK/mod/Incursion.Mod" ]
echo "PASS owner mismatch refused (exit $status); specimens: $WORK"
