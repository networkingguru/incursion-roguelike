#!/usr/bin/env bash
# Write every missing `.char` line, with its table default, into every `.char`
# in a directory (bead inc-10v7f, spec amendment A5). Run by hand in the bead
# that adds a decision; its output is a reviewed diff.
#
# Usage: tools/fill_chars.sh [dir]        dir defaults to tools/fixtures/chars
#        INCURSION_BIN=<binary>           the binary that builds (default ./incursion-headless)
#
# HOW. The build names the line it lacks: `missing line in <file>; add: <line>`
# (src/CharFile.cpp). For each file this script builds, appends the printed line
# at the end of the file, and builds again, until the build passes or fails for
# another reason. It holds no key list and no per-key branch (spec B18): the
# line comes from the build, with the default the key table gives it.
#
# A file whose build passes is not touched. A file whose build fails for any
# other reason is left as it was (the work is done on a copy, moved over the
# file only when the build passes); the BUILD FAILED line is printed with the
# file name, the other files are done, and the exit status is 1.
#
# LOOP GUARD. A decision asked for N times prints the same line N times, one
# ordinal each, so a repeat alone is not a loop. One line printed more than
# MAX_REPEAT (64) times for one file fails that file.
#
# MUST NOT run inside a check against tracked files. A check may run it on a
# copy under logs/.
#
# Exit: 0 every file builds; 1 some file failed (named above); 2 bad usage.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

DIR="${1:-tools/fixtures/chars}"
BIN="${INCURSION_BIN:-./incursion-headless}"
MAX_REPEAT=64
[ -d "$DIR" ] || { echo "usage: tools/fill_chars.sh [dir]  ($DIR is not a directory)" >&2; exit 2; }
[ -x "$BIN" ] || { echo "$BIN not built. Run: BACKEND=posix ./build_macos.sh" >&2; exit 2; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/fillchars.XXXXXX")" || exit 2
trap 'rm -rf "$WORK"' EXIT

failed=0
filled=0
untouched=0
for f in "$DIR"/*.char; do
    [ -f "$f" ] || continue
    name="$(basename "$f")"
    cp -f "$f" "$WORK/$name"
    added=0
    last=""
    repeat=0
    status=ok
    while :; do
        rm -rf "$WORK/run"
        INCURSION_BIN="$BIN" INCURSION_BUILD_RUN_DIR="$WORK/run" \
            tools/build_fixture.sh "$WORK/$name" "$WORK/out" > "$WORK/build.out" 2> "$WORK/build.err" < /dev/null
        rc=$?
        [ "$rc" -eq 0 ] && break
        miss="$(sed -n 's/^BUILD FAILED: missing line in .*; add: //p' "$WORK/build.err" | head -1)"
        if [ -z "$miss" ]; then
            status="$(grep -m1 'BUILD FAILED' "$WORK/build.err" || echo "BUILD FAILED: exit $rc")"
            break
        fi
        if [ "$miss" = "$last" ]; then repeat=$((repeat + 1)); else repeat=0; last="$miss"; fi
        if [ "$repeat" -ge "$MAX_REPEAT" ]; then
            status="BUILD FAILED: the line \"$miss\" was added $MAX_REPEAT times and the build still asks for it"
            break
        fi
        printf '%s\n' "$miss" >> "$WORK/$name"
        added=$((added + 1))
    done
    if [ "$status" != ok ]; then
        echo "$name: $status"
        failed=$((failed + 1))
    elif [ "$added" -gt 0 ]; then
        mv -f "$WORK/$name" "$f" || { echo "$name: BUILD FAILED: cannot write $f"; failed=$((failed + 1)); continue; }
        echo "$name: added $added line(s)"
        filled=$((filled + 1))
    else
        untouched=$((untouched + 1))
    fi
done
echo "fill_chars: $filled filled, $untouched already complete, $failed failed"
[ "$failed" -eq 0 ]
