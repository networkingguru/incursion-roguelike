#!/bin/bash
# regen_yygram.sh -- regenerate src/yygram.cpp and inc/yygram.h from lang/Grammar.acc.
#
# Builds the vendored ACCENT (modaccent/src) in a temporary directory, runs it on
# lang/Grammar.acc, then applies two fixes ACCENT output needs here: renumber the
# self-referencing `# line N "src/yygram.cpp"` directives, and set YYSTYPE to int32.
# Run it after ANY change to lang/Grammar.acc, then rebuild.
#
#   tools/regen_yygram.sh           write src/yygram.cpp and inc/yygram.h
#   tools/regen_yygram.sh --check   write nothing; exit 0 if the tree files match,
#                                   1 with a diff summary if not
#
# Any failing step exits non-zero and leaves both tree files untouched.
# REGEN_GRAMMAR overrides the grammar path (used to test the failure path).
# inc-b0ii.
set -u
cd "$(dirname "$0")/.." || exit 2
ROOT=$PWD
GRAMMAR=${REGEN_GRAMMAR:-lang/Grammar.acc}
MODE=write
case "${1:-}" in
  "") ;;
  --check) MODE=check ;;
  *) echo "usage: $0 [--check]" >&2; exit 2 ;;
esac

T=$(mktemp -d "${TMPDIR:-/tmp}/regen_yygram.XXXXXX") || exit 2
trap '[ -n "${REGEN_KEEP:-}" ] || rm -rf "$T"' EXIT
fail() { echo "regen_yygram: $*" >&2; exit 2; }

[ -f "$GRAMMAR" ] || fail "grammar not found: $GRAMMAR"

# empty malloc.h: ACCENT sources include it, macOS has none
mkdir "$T/stub" "$T/src" "$T/inc" || fail "mkdir"
: > "$T/stub/malloc.h"
cc -std=gnu89 -w -Wno-error -Wno-return-mismatch -Wno-implicit-int -Wno-implicit-function-declaration -Wno-int-conversion -I"$T/stub" -I"$ROOT/modaccent/include" -I"$ROOT/modaccent/src" \
   -o "$T/accent" "$ROOT"/modaccent/src/*.c >"$T/cc.log" 2>&1 \
   || { tail -n 15 "$T/cc.log" >&2; fail "ACCENT build failed"; }

# run inside $T on a copy at lang/Grammar.acc: ACCENT writes both paths into the output
mkdir "$T/lang" && cp "$GRAMMAR" "$T/lang/Grammar.acc" || fail "copy grammar"
( cd "$T" && ./accent lang/Grammar.acc src inc ) >"$T/accent.log" 2>&1 \
   || { tail -n 15 "$T/accent.log" >&2;  fail "ACCENT run failed"; }
[ -s "$T/src/yygram.cpp" ] && [ -s "$T/inc/yygram.h" ] || fail "ACCENT produced no output"

awk '/^# line .* "src\/yygram.cpp"$/ { print "# line " (NR+1) " \"src/yygram.cpp\""; next } { print }' \
   "$T/src/yygram.cpp" > "$T/src/y.new" && mv "$T/src/y.new" "$T/src/yygram.cpp" || fail "line renumber"
sed 's/^#define YYSTYPE long$/#define YYSTYPE int32/' "$T/inc/yygram.h" > "$T/inc/h.new" \
   && mv "$T/inc/h.new" "$T/inc/yygram.h" || fail "YYSTYPE fix"
grep -q '^#define YYSTYPE int32$' "$T/inc/yygram.h" || fail "YYSTYPE fix did not apply"

if [ "$MODE" = check ]; then
  rc=0
  for f in src/yygram.cpp inc/yygram.h; do
    if ! cmp -s "$T/${f%%/*}/yygram.${f##*.}" "$f"; then
      echo "DIFFERS: $f ($(diff "$T/${f%%/*}/yygram.${f##*.}" "$f" | grep -c '^[<>]') changed lines)" >&2
      rc=1
    fi
  done
  [ $rc = 0 ] && echo "regen_yygram --check: tree matches $GRAMMAR"
  exit $rc
fi

cp "$T/src/yygram.cpp" src/yygram.cpp.new && cp "$T/inc/yygram.h" inc/yygram.h.new \
  && mv src/yygram.cpp.new src/yygram.cpp && mv inc/yygram.h.new inc/yygram.h \
  || { rm -f src/yygram.cpp.new inc/yygram.h.new; fail "install"; }
echo "regen_yygram: wrote src/yygram.cpp and inc/yygram.h from $GRAMMAR"
