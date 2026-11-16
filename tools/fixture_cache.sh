#!/bin/bash
# The one lookup for a built fixture (bead inc-10v7f, phase 9; spec sections 6,
# 7, amendments A3, A10, A13, B3, B8). Given a fixture name, print the path of
# its cached .sav, building the fixture first when the cache has no entry for
# the current inputs. Every caller (tools/headless.sh, tools/fixture_sheet.sh,
# tools/nightly_verify.sh --record, the checks) uses this script; none repeats
# its logic.
#
# Usage: tools/fixture_cache.sh <name>            print the cached .sav path
#        tools/fixture_cache.sh <path/to/x.char>  the same for a .char file
#        tools/fixture_cache.sh --key <name|path> print the key, build nothing
#
# <name> is tools/fixtures/chars/<name>.char. A path (or an argument ending in
# .char) names the file itself; its base name is the fixture name.
#
# THE KEY is a SHA-256 over four inputs, each hashed first (shasum -a 256):
#     char <hash of the .char>
#     options <hash of the file the .char's options: line names>
#     bin <hash of the incursion-headless binary the run will use>
#     mod <hash of mod/Incursion.Mod>
# one labelled line each, so a change to any one of them is a different key and
# a miss (A3, B3). The binary is $INCURSION_BIN, else ./incursion-headless. The
# options path resolves as the binary resolves it (src/CharFile.cpp): from the
# repository root, else beside the .char.
#
# THE ENTRY is logs/fixture-cache/<key>/<name>.sav and <name>.sheet.txt. The
# sheet starts with three "# " lines that name the key (V2).
#
# A MISS builds through tools/build_fixture.sh (its clean environment), under
# the per-fixture lock logs/fixture-locks/<name> (an atomic mkdir), into a
# temporary directory beside the entries, then renames the sheet and the .sav
# into place. A run that waited on the lock and then finds the entry uses it.
# A lock older than 30 minutes is stale and is taken over (A13). After a build,
# the 3 newest keys of that name stay and older ones go (A13). Every build
# appends `name<TAB>key<TAB>sha256 of the tools/char_dump.sh dump` to
# logs/fixture-builds.tsv (A10).
#
# ENVIRONMENT. INCURSION_BIN (which binary). INCURSION_FIXTURE_CACHE (the cache
# directory; its locks and build log sit in the same parent, so a scratch cache
# has scratch state; used by tools/check_fixture_repair.sh, and removed from the
# environment of the build by tools/build_fixture.sh). INCURSION_FIXTURE_PIN
# (A10, B8): a file of `<name><TAB><key>` lines. For a pinned name the lookup
# serves exactly that key's entry, never builds it, and exits 2 when the entry
# is missing. A name the file does not list is looked up as usual. --key ignores
# the pin: it prints the key the current inputs give.
#
# Exit: 0 printed; 2 bad usage, a missing input, or a pinned entry that is gone;
# 10 and the binary's own codes are tools/build_fixture.sh's (its BUILD FAILED
# line is on stderr); 1 the dump of the built .sav failed.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

KEYONLY=0
if [ "${1:-}" = "--key" ]; then
    KEYONLY=1
    shift
fi
ARG="${1:-}"
if [ -z "$ARG" ]; then
    echo "usage: tools/fixture_cache.sh [--key] <name | file.char>" >&2
    exit 2
fi
case "$ARG" in
    */*|*.char) CHAR="$ARG" ;;
    *)          CHAR="tools/fixtures/chars/$ARG.char" ;;
esac
NAME="$(basename "$CHAR" .char)"
case "$NAME" in
    ''|.*|*[!A-Za-z0-9._-]*)
        echo "fixture_cache: '$NAME' is not a fixture name (letters, digits, . _ - only)" >&2
        exit 2 ;;
esac
if [ ! -f "$CHAR" ]; then
    echo "fixture_cache: no such fixture: $ARG (looked for $CHAR)" >&2
    exit 2
fi

CACHE="${INCURSION_FIXTURE_CACHE:-$ROOT/logs/fixture-cache}"
mkdir -p "$CACHE" || exit 2
CACHE="$(cd "$CACHE" && pwd)"
STATE_DIR="$(dirname "$CACHE")"
LOCKS="$STATE_DIR/fixture-locks"
BUILDLOG="$STATE_DIR/fixture-builds.tsv"

have_entry() { # <key>
    [ -f "$CACHE/$1/$NAME.sav" ] && [ -f "$CACHE/$1/$NAME.sheet.txt" ]
}

# The pin: serve exactly the pinned key's entry, never build it.
if [ "$KEYONLY" -eq 0 ] && [ -n "${INCURSION_FIXTURE_PIN:-}" ]; then
    if [ ! -r "$INCURSION_FIXTURE_PIN" ]; then
        echo "fixture_cache: INCURSION_FIXTURE_PIN names a file that is not there: $INCURSION_FIXTURE_PIN" >&2
        exit 2
    fi
    PINKEY="$(awk -F'\t' -v n="$NAME" '$1 == n { k = $2 } END { print k }' "$INCURSION_FIXTURE_PIN")"
    if [ -n "$PINKEY" ]; then
        if have_entry "$PINKEY"; then
            printf '%s\n' "$CACHE/$PINKEY/$NAME.sav"
            exit 0
        fi
        echo "fixture_cache: the pinned entry for $NAME is missing: $CACHE/$PINKEY (pin record $INCURSION_FIXTURE_PIN); it is never rebuilt" >&2
        exit 2
    fi
fi

sha_of() { # <file> -> the hex digest, or fail
    local out
    out="$(shasum -a 256 -- "$1" 2>/dev/null)" || return 1
    printf '%s' "${out%% *}"
}

BIN="${INCURSION_BIN:-./incursion-headless}"
MOD="$ROOT/mod/Incursion.Mod"
OPT="$(sed -n 's/^options:[[:space:]]*\(.*[^[:space:]]\)[[:space:]]*$/\1/p' "$CHAR" | head -1)"
if [ -z "$OPT" ]; then
    echo "fixture_cache: $CHAR has no options: line" >&2
    exit 2
fi
OPTF="$OPT"
if [ ! -r "$OPTF" ] && [ "${OPTF#/}" = "$OPTF" ]; then
    beside="$(dirname "$CHAR")/$OPT"
    [ -r "$beside" ] && OPTF="$beside"
fi
[ -r "$OPTF" ] || { echo "fixture_cache: the options file $OPT is not readable" >&2; exit 2; }
[ -f "$BIN" ] || { echo "fixture_cache: $BIN is not built. Run: BACKEND=posix ./build_macos.sh" >&2; exit 2; }
[ -f "$MOD" ] || { echo "fixture_cache: $MOD is not there" >&2; exit 2; }
HC="$(sha_of "$CHAR")" && HO="$(sha_of "$OPTF")" && HB="$(sha_of "$BIN")" && HM="$(sha_of "$MOD")" \
    || { echo "fixture_cache: could not hash an input of $NAME" >&2; exit 2; }
KEY="$(printf 'char %s\noptions %s\nbin %s\nmod %s\n' "$HC" "$HO" "$HB" "$HM" | shasum -a 256)"
KEY="${KEY%% *}"

if [ "$KEYONLY" -eq 1 ]; then
    printf '%s\n' "$KEY"
    exit 0
fi

ENTRY="$CACHE/$KEY"
if have_entry "$KEY"; then
    printf '%s\n' "$ENTRY/$NAME.sav"
    exit 0
fi

[ -x "$BIN" ] || { echo "fixture_cache: $BIN is not executable" >&2; exit 2; }
mkdir -p "$LOCKS" || exit 2
LOCK="$LOCKS/$NAME"
HAVE_LOCK=0
TMP=""
cleanup() {
    [ -n "$TMP" ] && rm -rf "$TMP"
    [ "$HAVE_LOCK" -eq 1 ] && rm -rf "$LOCK"
    return 0
}
trap cleanup EXIT

# ponytail: two waiters that see the same stale lock can both remove it, and the
# second removal can take a lock the first just made. Ceiling: a double build of
# one fixture after a crash that left a lock older than 30 minutes, harmless
# because each build renames whole files into place. Upgrade path: rename the
# stale lock aside (mv) so one waiter wins.
while :; do
    if have_entry "$KEY"; then
        printf '%s\n' "$ENTRY/$NAME.sav"
        exit 0
    fi
    if mkdir "$LOCK" 2> /dev/null; then
        HAVE_LOCK=1
        break
    fi
    if [ -n "$(find "$LOCK" -maxdepth 0 -mmin +30 2> /dev/null)" ]; then
        echo "fixture_cache: the lock for $NAME is older than 30 minutes; taking it over" >&2
        rm -rf "$LOCK"
        continue
    fi
    sleep 0.2
done
# Another run may have finished the entry between the check and the mkdir.
if have_entry "$KEY"; then
    printf '%s\n' "$ENTRY/$NAME.sav"
    exit 0
fi

TMP="$CACHE/.tmp-$NAME.$$"
rm -rf "$TMP"
mkdir -p "$TMP" || exit 2
INCURSION_BIN="$BIN" tools/build_fixture.sh "$CHAR" "$TMP" >&2
RC=$?
[ "$RC" -eq 0 ] || exit "$RC"

if ! INCURSION_OPTIONS="$OPTF" INCURSION_BIN="$BIN" tools/char_dump.sh "$TMP/$NAME.sav" "$TMP/dump.canon" > /dev/null 2>&1; then
    echo "fixture_cache: the canonical dump of the built $NAME failed" >&2
    exit 1
fi
DUMPHASH="$(sha_of "$TMP/dump.canon")" || exit 1

{
    printf '# fixture-cache: %s\n' "$NAME"
    printf '# key: %s\n' "$KEY"
    printf '# inputs: char %.12s, options %.12s, binary %.12s, module %.12s\n' "$HC" "$HO" "$HB" "$HM"
    cat "$TMP/$NAME.sheet.txt"
} > "$TMP/$NAME.sheet.new" || exit 2
mv -f "$TMP/$NAME.sheet.new" "$TMP/$NAME.sheet.txt" || exit 2

# The sheet first, the .sav last: a reader that sees the .sav sees both.
mkdir -p "$ENTRY" || exit 2
mv -f "$TMP/$NAME.sheet.txt" "$ENTRY/$NAME.sheet.txt" || exit 2
mv -f "$TMP/$NAME.sav" "$ENTRY/$NAME.sav" || exit 2
printf '%s\t%s\t%s\n' "$NAME" "$KEY" "$DUMPHASH" >> "$BUILDLOG"

# Keep the 3 newest keys of this name (A13).
N=0
while IFS= read -r sav; do
    N=$((N + 1))
    [ "$N" -gt 3 ] || continue
    d="$(dirname "$sav")"
    rm -f "$d/$NAME.sav" "$d/$NAME.sheet.txt"
    rmdir "$d" 2> /dev/null
done < <(ls -t "$CACHE"/*/"$NAME.sav" 2> /dev/null)

printf '%s\n' "$ENTRY/$NAME.sav"
exit 0
