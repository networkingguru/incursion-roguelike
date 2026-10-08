#!/bin/bash
# gate: live -- it compiles a sandbox module with the built binary, so it needs
# BACKEND=posix ./build_macos.sh first.
# inc-xbxf: an ambiguous script must fail the module compile loudly, with no
# silent priority pick and no terminal. The dangling else in an unbraced nested
# if is the classic ambiguity the Earley parser must report, not resolve.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d "$ROOT/logs/grammar-ambiguity.XXXXXX")"
mkdir -p "$WORK/mod" "$WORK/save" "$WORK/logs"
cp -rf "$ROOT/lib" "$WORK/lib"
ln -s "$ROOT/inc" "$WORK/inc"

# Baseline: the same nested if WITHOUT the trailing "else if" is a single parse
# and must compile, so the check knows the test text is otherwise valid.
cat >> "$WORK/lib/main.irc" <<'EOF'

AI_POTION Effect "ambiguity probe" : EA_GENERIC
  {
    On Event EV_HIT {
      if (e.isHit) if (e.isCrit) { EActor->IPrint("crit"); }
      return NOTHING;
      };
  }
EOF

status=0
INCURSIONPATH="$WORK/" "${INCURSION_BIN:-$ROOT/incursion-headless}" -compile main.irc < /dev/null > "$WORK/logs/base.log" 2>&1 || status=$?
if [ "$status" != 0 ] || [ ! -f "$WORK/mod/Incursion.Mod" ]; then
   echo "FAIL baseline nested if should compile (exit $status); specimens: $WORK"
   exit 1
fi

# Ambiguous: the dangling "else if" leaves two parse trees for one phrase.
rm -f "$WORK/mod/Incursion.Mod"
cat >> "$WORK/lib/main.irc" <<'EOF'

AI_POTION Effect "ambiguity probe ambiguous" : EA_GENERIC
  {
    On Event EV_HIT {
      if (e.isHit) if (e.isCrit) { EActor->IPrint("crit"); } else if (e.isHit) { EActor->IPrint("hit"); }
      return NOTHING;
      };
  }
EOF

status=0
INCURSIONPATH="$WORK/" "${INCURSION_BIN:-$ROOT/incursion-headless}" -compile main.irc < /dev/null > "$WORK/logs/ambiguous.log" 2>&1 || status=$?

grep -Fq "source text is ambiguous" "$WORK/logs/ambiguous.log"
[ "$status" != 0 ] && [ ! -f "$WORK/mod/Incursion.Mod" ]
echo "PASS ambiguous script refused (exit $status); specimens: $WORK"
