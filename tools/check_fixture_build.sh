#!/usr/bin/env bash
# gate: live
#
# Does every .char build, and does the cache serve exactly what its .char builds?
#
# WHAT IS BEING PROVED. Spec section 9 C1, section 6 V1-V3, amendments A3, A10
# (bead inc-10v7f, phase 9). For every tools/fixtures/chars/*.char:
#   V1   a fresh build of the file, in a scratch directory, passes;
#   V2   the sheet in the cache entry tools/fixture_cache.sh serves names, in its
#        first lines, the key the lookup computes from the current inputs;
#   AC4  the canonical dump of the cached .sav has the same SHA-256 as the dump of
#        the fresh build, so a cached .sav that is not what its .char builds fails
#        and the line names the fixture;
#   key  a copy of the .char with one decision value changed (its seed: line) gets
#        a different key, and the lookup, in a scratch cache, serves a different
#        entry for it than for the original.
# V3 (a build does not depend on seed:) is tools/check_build_seeds.sh; this
# check calls it and does not repeat it.
#
# RED MUTATIONS (both proved by hand when the check was written):
#   (i)  the key ignores the .char hash (hc="" in tools/fixture_cache.sh): the key
#        of the edited copy equals the original's, and the lookup serves the old
#        .sav.
#   (ii) another character's .sav is put into the cache slot of a fixture: the dump
#        hashes differ and the line names the fixture.
#
# THE CACHE. The V2 and AC4 parts read the worktree's real cache, building an
# entry that is missing (that is the lookup's job), because a stale or swapped
# entry there is exactly what they exist to catch. INCURSION_FIXTURE_PIN is
# removed from the environment: a pin serves the base's entry, not the current
# key's. The edited-copy part uses a scratch cache and never touches the real one.
#
# fact: the character -- every tools/fixtures/chars/*.char, committed; each is built from the file alone, no key script and no walk
# fact: the random stream -- the seed: line of each .char feeds the build; tools/build_fixture.sh removes every other INCURSION_* variable, and every assertion compares two canonical dumps of one file under one seed, so no drawn value is read
# fact: the options -- the options: line of each .char names a committed settings file; the dump is read under that same file
# fact: the cache entry -- the worktree's real logs/fixture-cache entry for the current inputs, built by the lookup when missing; INCURSION_FIXTURE_PIN and INCURSION_FIXTURE_CACHE are removed from this script's environment
#
# Usage: INCURSION_BIN=./incursion-headless tools/check_fixture_build.sh
# Exit: 0 pass; 1 fail; 2 could not run.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2
BIN="${INCURSION_BIN:-./incursion-headless}"
[ -x "$BIN" ] || { echo "INCONCLUSIVE: $BIN is not built"; exit 2; }
export INCURSION_BIN="$BIN"
unset INCURSION_FIXTURE_PIN INCURSION_FIXTURE_CACHE

W="$(mktemp -d "$ROOT/logs/fixture-build-check.XXXXXX")" || exit 2
trap 'rm -rf "$W"' EXIT

fail=0
ran=0
for CHAR in tools/fixtures/chars/*.char; do
    [ -f "$CHAR" ] || continue
    NAME="$(basename "$CHAR" .char)"
    ran=$((ran + 1))
    OPT="$(sed -n 's/^options:[[:space:]]*\(.*[^[:space:]]\)[[:space:]]*$/\1/p' "$CHAR" | head -1)"
    [ -f "$OPT" ] || { echo "INCONCLUSIVE: $NAME names the options file $OPT, which is not there"; exit 2; }

    # V1: a fresh build, in a scratch directory.
    if ! tools/build_fixture.sh "$CHAR" "$W/fresh-$NAME" > "$W/$NAME.build.log" 2>&1; then
        echo "FAIL $NAME V1: the build failed: $(grep -m1 'BUILD FAILED' "$W/$NAME.build.log" || tail -1 "$W/$NAME.build.log")"
        fail=1
        continue
    fi
    echo "ok   $NAME V1: builds"

    # The cached entry, through the one lookup (it builds on a miss).
    KEY="$(tools/fixture_cache.sh --key "$NAME")" || { echo "INCONCLUSIVE: no key for $NAME"; exit 2; }
    SAV="$(tools/fixture_cache.sh "$NAME" 2> "$W/$NAME.lookup.log")" || {
        echo "FAIL $NAME: the lookup failed: $(tail -1 "$W/$NAME.lookup.log")"
        fail=1
        continue
    }

    # V2: the sheet header names the key.
    SHEET="${SAV%.sav}.sheet.txt"
    if grep -qx "# key: $KEY" <<< "$(head -3 "$SHEET")"; then
        echo "ok   $NAME V2: the cached sheet names key ${KEY:0:12}"
    else
        echo "FAIL $NAME V2: the cached sheet does not name the key the lookup computes now (${KEY:0:12})"
        fail=1
    fi

    # AC4: the cached .sav is what the .char builds.
    INCURSION_OPTIONS="$OPT" tools/char_dump.sh "$SAV" "$W/$NAME.cached.canon" > /dev/null 2>&1 \
        || { echo "FAIL $NAME AC4: the dump of the cached .sav failed"; fail=1; continue; }
    INCURSION_OPTIONS="$OPT" tools/char_dump.sh "$W/fresh-$NAME/$NAME.sav" "$W/$NAME.fresh.canon" > /dev/null 2>&1 \
        || { echo "FAIL $NAME AC4: the dump of the fresh build failed"; fail=1; continue; }
    HC="$(shasum -a 256 < "$W/$NAME.cached.canon")"
    HF="$(shasum -a 256 < "$W/$NAME.fresh.canon")"
    if [ "$HC" = "$HF" ]; then
        echo "ok   $NAME AC4: the cached .sav dumps as the fresh build does (${HC:0:12})"
    else
        echo "FAIL $NAME AC4: the cached .sav is not what $NAME.char builds (cached ${HC:0:12}, fresh ${HF:0:12})"
        diff "$W/$NAME.cached.canon" "$W/$NAME.fresh.canon" | head -6 | cut -c1-160
        fail=1
    fi

    # key: one decision value changed gives a different key and a different entry.
    mkdir -p "$W/edit" "$W/scratch"
    sed 's/^seed: .*/seed: 987654/' "$CHAR" > "$W/edit/$NAME.char"
    if cmp -s "$CHAR" "$W/edit/$NAME.char"; then
        echo "INCONCLUSIVE: the seed edit changed nothing in $CHAR"
        exit 2
    fi
    KEY2="$(tools/fixture_cache.sh --key "$W/edit/$NAME.char")" || { echo "INCONCLUSIVE: no key for the edited copy"; exit 2; }
    P1="$(INCURSION_FIXTURE_CACHE="$W/scratch/cache" tools/fixture_cache.sh "$CHAR" 2> /dev/null)" || { echo "INCONCLUSIVE: the scratch lookup failed"; exit 2; }
    P2="$(INCURSION_FIXTURE_CACHE="$W/scratch/cache" tools/fixture_cache.sh "$W/edit/$NAME.char" 2> /dev/null)" || { echo "INCONCLUSIVE: the scratch lookup of the edited copy failed"; exit 2; }
    if [ "$KEY" != "$KEY2" ] && [ "$P1" != "$P2" ]; then
        echo "ok   $NAME key: an edited .char gets key ${KEY2:0:12}, not ${KEY:0:12}, and its own entry"
    else
        echo "FAIL $NAME key: an edited .char shares the original's key or entry (${KEY:0:12} / ${KEY2:0:12})"
        fail=1
    fi
done

[ "$ran" -gt 0 ] || { echo "INCONCLUSIVE: no .char under tools/fixtures/chars"; exit 2; }

# V3 is its own check.
if tools/check_build_seeds.sh > "$W/seeds.log" 2>&1; then
    echo "ok   V3: $(tail -1 "$W/seeds.log")"
else
    echo "FAIL V3: tools/check_build_seeds.sh failed: $(tail -1 "$W/seeds.log")"
    fail=1
fi

[ "$fail" -eq 0 ] && { echo "PASS: $ran fixture(s) build, and the cache serves what the .char builds"; exit 0; }
exit 1
