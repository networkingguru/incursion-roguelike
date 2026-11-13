#       8 a character fixture would not load, or its automatic rebuild failed
#       (inc-zto3q; no session ran).
#       8 a cache-served fixture did not load (FIXTURE LOAD FAILED; see the
#       INCURSION_LOAD block, and tools/fixture_cache.sh).
@@@ next hunk

# inc-zto3q: a fixture under tools/fixtures/chars/ that stops loading because
# resource positions moved (position drift) is rebuilt from the command on its
# sheet. Any other refusal exits 8 at once, with no rebuild. The preflight
# always uses $ROOT/mod, never the run directory's module, so a mutated scratch
# module can never trigger a rebuild of a tracked fixture.
# Position drift = -schemaload exits 22 AND stderr holds one of these lines.
FX_DRIFT_RE='^incursion: (module slot [0-9]+ [^ ]+ array (slid at position|was reordered: )|variable owner .*: (owner list shrank|name moved to another ordinal)$)'

_fx_preflight() { # <sav> -> exit status; stderr kept in $FX_ERR
    local d="$RUN/fixture-preflight" st
    rm -rf "$d"
    mkdir -p "$d/save" "$d/logs"
    ln -sfn "$ROOT/mod" "$d/mod"
    ln -sfn "$ROOT/lib" "$d/lib"
    cp "$OPTIONS" "$d/Options.Dat"
    cp "$1" "$d/save/fx.sav"
    FX_ERR="$d/err"
    INCURSIONPATH="$d/" "$BIN" -schemaload "$d/save/fx.sav" -timeout 120 \
        </dev/null >"$d/out" 2>"$FX_ERR"
    st=$?
    return $st
}

_fx_fail() { echo "$1"; exit 8; }

_fx_check() { # <fixture path>: preflight, rebuild on drift, or exit 8
    local sav="$1" name sheet dir st line w lock
    dir="$(cd "$(dirname "$sav")" && pwd -P)"
    [ "$dir" = "$(cd "$ROOT/tools/fixtures/chars" 2>/dev/null && pwd -P)" ] || return 0
    name="$(basename "$sav" .sav)"
    sheet="$dir/$name.sheet.txt"
    [ "${sav##*.}" = "sav" ] && [ -f "$sheet" ] || return 0
    _fx_preflight "$sav"; st=$?
    [ "$st" -eq 0 ] && return 0
    line="$(grep -m1 -E "$FX_DRIFT_RE" "$FX_ERR")"
    if [ "$st" -ne 22 ] || [ -z "$line" ] || [ -n "${INCURSION_FIXTURE_REBUILDING:-}" ]; then
        _fx_fail "FIXTURE LOAD FAILED: $name: exit $st: $(head -1 "$FX_ERR")"
    fi
    FX_LOCK="$ROOT/logs/fixture-locks/$name"; lock="$FX_LOCK"
    mkdir -p "$ROOT/logs/fixture-locks"
    until mkdir "$lock" 2>/dev/null; do
        if [ -n "$(find "$lock" -maxdepth 0 -mmin +30 2>/dev/null)" ]; then
            echo "fixture: removing stale lock $lock (older than 30 minutes)"
            rmdir "$lock" 2>/dev/null
        else
            sleep 2
        fi
    done
    trap 'rmdir "$FX_LOCK" 2>/dev/null' EXIT
    _fx_preflight "$sav"; st=$?
    if [ "$st" -eq 0 ]; then
        echo "fixture: $name already rebuilt by another run"
        rmdir "$lock" 2>/dev/null; trap - EXIT
        return 0
    fi
    # The sheet's command, validated word by word, then run without eval.
    read -r -a w < <(awk '/^regenerate with$/ {getline; print; exit}' "$sheet")
    if [ "${#w[@]}" -ne 6 ] || [ "${w[0]}" != "tools/make_char_fixture.sh" ] ||
       [ "${w[1]}" != "$name" ] || [ "${w[5]}" != "--force" ]; then
        _fx_fail "FIXTURE REBUILD FAILED: $name: the sheet's regenerate command is not 'tools/make_char_fixture.sh $name <keys> <seed> <options> --force'"
    fi
    echo "fixture: $name drifted ($line); rebuilding"
    # The caller's load, run dir and seed override must not reach the generating run.
    if ! env -u INCURSION_LOAD -u INCURSION_RUN_DIR -u INCURSION_SEED_OVERRIDE INCURSION_FIXTURE_REBUILDING=1 "${w[@]}" >"$RUN/fixture-rebuild.log" 2>&1; then
        _fx_fail "FIXTURE REBUILD FAILED: $name: make_char_fixture.sh failed: $(tail -1 "$RUN/fixture-rebuild.log") (see $RUN/fixture-rebuild.log)"
    fi
    _fx_preflight "$sav" || _fx_fail "FIXTURE REBUILD FAILED: $name: the rebuilt fixture still does not load: $(head -1 "$FX_ERR")"
    echo "$name" >> "$ROOT/logs/fixture-rebuilds.log"
    rmdir "$lock" 2>/dev/null; trap - EXIT
    echo "fixture: $name rebuilt (position drift: $line)"
}

#
# A FIXTURE WITH A .char FILE COMES FROM THE CACHE (bead inc-10v7f, phase 9).
# INCURSION_LOAD=<name> (no '/', no ".sav") and the path form
# tools/fixtures/chars/<name>.char (or the old <name>.sav) both map to <name> when
# tools/fixtures/chars/<name>.char exists. tools/fixture_cache.sh serves the
# cached .sav for the current .char, options file, binary and module, building
# it first on a miss, and the copy below then proceeds as for any other file.
# A fixture with no .char keeps the old behavior: INCURSION_LOAD names a file.
#
# EXIT 8. A cache-served .sav that fails to load is a loader or writer defect,
# not a stale file: the run ends with exit 8 and "FIXTURE LOAD FAILED: <name>
# (<key>)", and the entry is never rebuilt. The signal is the binary's own: a
# failed -load makes main() return 2 (src/Wposix.cpp, the `retval = 2` after
# LoadNamedGame), and LoadNamedGame has logged one of the three lines matched
# below to logs/errors.log (src/Registry.cpp, "Error reading saved game",
# "Null map/player after saved game loaded!", "Error loading module"). Exit 2
# alone is not enough: a key script that fails a directive also exits 2.
@@@ next hunk
    8) echo "FIXTURE LOAD FAILED: $FIX_NAME ($FIX_KEY)"
       echo "ended:      the cached fixture did not load. This is a loader or writer"
       echo "            defect; the entry is kept and is never rebuilt." ;;
