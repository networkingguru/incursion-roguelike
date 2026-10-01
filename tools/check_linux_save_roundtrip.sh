#!/bin/bash
# gate: none needs Docker and minutes per distro; run it by hand
#
# Does a v1 save still LOAD on x64 Linux? (bd inc-eikp.1)
#
# WHAT IT GUARDS. A Linux tester reported that saves do not load on x64 Linux
# and that a load trips ASSERT(h <= LastUsedHandle) in Registry::GetQuiet. This
# check runs both directions of the round trip on real x86-64 code, in the
# Docker containers tools/linux_run.sh builds:
#   Case A  a character SAVED on Linux (chargen-default-save.keys) is LOADED
#           on Linux (load-char-sheet.keys --load <that .sav>).
#   Case B  a save made on macOS (the frozen lizardfolk-monk-seed1.sav) is
#           LOADED on Linux.
#
# THE ORACLE. A load run must reach play with the saved character on screen,
# not merely exit 0. load-char-sheet.keys dumps arrival, played, sheet and
# saved; this check requires the arrival screen to say "Welcome back to
# Incursion, <name>!" -- the engine's own load greeting -- and the sheet screen
# to show the same name, race and class. Case B reads those from the fixture's
# own sheet.txt (screen spaces for underscores). A run reporting NO GAMEPLAY
# (exit 5) is a FAIL for a load, as is a run whose headless.sh report lacks the
# line "errors:     none" -- the same oracle tools/check_linux_build.sh uses;
# the run's logs/errors.log is printed when it exists.
#
# HOW TO PROVE IT BITES. In src/Registry.cpp, Game::LoadNamedGame, return
# before it opens the named save. Rebuild, run this check: Cases A and B must
# both go red on the missing greeting. Revert exactly; `git diff -- src/` must
# be empty. A temporary mutation is the only src/ change this check authorises.
#
# Usage: tools/check_linux_save_roundtrip.sh [--distro debian11|arch|both]
# Exit 0 pass, 1 fail, 2 could not measure.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DISTROS="both"
while [ $# -gt 0 ]; do
    case "$1" in
        --distro) DISTROS="${2:-}"; shift 2 ;;
        --distro=*) DISTROS="${1#--distro=}"; shift ;;
        -h|--help)
            echo "usage: tools/check_linux_save_roundtrip.sh [--distro debian11|arch|both]"
            exit 0 ;;
        *)
            echo "unknown argument: $1" >&2
            echo "usage: tools/check_linux_save_roundtrip.sh [--distro debian11|arch|both]"
            exit 2 ;;
    esac
done
case "$DISTROS" in
    both)     DISTROS="debian11 arch" ;;
    debian11|arch) ;;
    *) echo "--distro must be debian11, arch or both (got '$DISTROS')" >&2; exit 2 ;;
esac

export INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat
RUNNER="$ROOT/tools/linux_run.sh"

CHARGEN_KEYS=tools/keys/chargen-default-save.keys
LOAD_KEYS=tools/keys/load-char-sheet.keys
MAC_SAV=tools/fixtures/chars/lizardfolk-monk-seed1.sav
MAC_SHEET=tools/fixtures/chars/lizardfolk-monk-seed1.sheet.txt

for f in "$RUNNER" "$CHARGEN_KEYS" "$LOAD_KEYS" "$MAC_SAV" "$MAC_SHEET"; do
    [ -f "$f" ] || { echo "FAIL: needed file is missing: $f"; exit 2; }
done

# A run directory printed by linux_run.sh as its last line.
run_dir_from() { sed -n 's/^linux-run: //p' | tail -1; }

# The name shown in the play-mode status panel the save dumped. Its right-hand
# column is "|<Name>"; the Autosave line is the one the key script pins with
# @dump:saved, so read the field beside it.
name_from_saved_screen() { # <saved screen file>
    awk -F'|' '/Autosave/{gsub(/[[:space:]]+$/,"",$2); sub(/^[[:space:]]+/,"",$2); print $2; exit}' "$1"
}

# A screen file among a run's dumps whose name matches a glob suffix.
screen_of() { # <run dir> <glob>
    local f
    for f in "$1"/logs/screens/*"$2".txt "$1"/logs/screens/*"$2"; do
        [ -f "$f" ] && { echo "$f"; return 0; }
    done
    return 1
}

# The same oracle tools/check_linux_build.sh uses: headless.sh prints
# "errors:     none" (tools/headless.sh:401) exactly when the run logged
# nothing, and any other line means it did. A load run without that line FAILS,
# and the run's logs/errors.log is printed when it exists.
errors_clean() { # <run dir> <headless output> <label>
    local log="$1/logs/errors.log"
    if printf '%s\n' "$2" | grep -q '^errors:     none'; then
        return 0
    fi
    echo "  FAIL  $3: the run did not report 'errors:     none'"
    if [ -f "$log" ]; then
        echo "  logs/errors.log:"
        sed 's/^/        /' "$log"
    else
        echo "  (no logs/errors.log in $1)"
    fi
    return 1
}

overall=0            # 0 pass, 1 fail, 2 could not measure
note() { # raise the overall result to at least <level>
    local level="$1"
    if [ "$level" -eq 1 ]; then overall=1
    elif [ "$level" -eq 2 ] && [ "$overall" -eq 0 ]; then overall=2
    fi
}

# The desired name/race/class of a load, from its own audit source.
expected_from_sheet() { # <sheet.txt> -> prints "name|race|class"
    local sheet="$1" name race class
    name="$(sed -n 's/^ *\([^ ,][^,]*\), .*(.*Mode).*/\1/p' "$sheet" | head -1 | tr '_' ' ')"
    race="$(sed -n 's/^Race  *//p' "$sheet" | head -1 | sed 's/[[:space:]]*$//')"
    class="$(sed -n 's/^Class  *//p' "$sheet" | head -1 | sed 's/[[:space:]]*$//' | sed 's/[[:space:]]*[0-9][0-9]*$//')"
    printf '%s|%s|%s\n' "$name" "$race" "$class"
}

# One load case: run load-char-sheet.keys against a save, then apply the oracle.
# $1 label, $2 distro, $3 save path (host), $4 expected "name|race|class" or ""
load_case() { # <label> <distro> <save> <expected>
    local label="$1" distro="$2" save="$3" expected="$4"
    local out run status arrival sheet exp_name exp_race exp_class got_name

    out="$("$RUNNER" --distro "$distro" --cc clang --load "$save" "$LOAD_KEYS" 1 2>&1)"
    status=$?
    run="$(printf '%s\n' "$out" | run_dir_from)"

    if [ -z "$run" ] || [ ! -d "$run" ]; then
        echo "  FAIL  $label: the load run produced no run directory"
        printf '%s\n' "$out" | sed 's/^/        /'
        note 1; return 1
    fi

    # "No gameplay is not a pass" for a load. Exit 5 is the explicit shape; a
    # non-zero exit of any kind means the session did not cleanly reach play.
    if [ "$status" -ne 0 ]; then
        echo "  FAIL  $label: the load run exited $status (a load must reach play)"
        printf '%s\n' "$out" | sed 's/^/        /'
        note 1; return 1
    fi

    if ! arrival="$(screen_of "$run" 'arrival')"; then
        echo "  FAIL  $label: the load run dumped no arrival screen"
        note 1; return 1
    fi
    if ! sheet="$(screen_of "$run" 'sheet')"; then
        echo "  FAIL  $label: the load run dumped no character-sheet screen"
        note 1; return 1
    fi

    # The load greeting is the engine's own proof a save was read.
    if ! grep -q 'Welcome back to Incursion,' "$arrival"; then
        echo "  FAIL  $label: no 'Welcome back to Incursion,' on the arrival screen"
        note 1; return 1
    fi

    if [ -n "$expected" ]; then
        exp_name="${expected%%|*}"; expected="${expected#*|}"
        exp_race="${expected%%|*}"; exp_class="${expected#*|}"
        grep -qF "Welcome back to Incursion, $exp_name!" "$arrival" || {
            echo "  FAIL  $label: greeting names a character other than $exp_name"
            grep 'Welcome back' "$arrival" | sed 's/^/        /'
            note 1; return 1; }
        # A loaded character may carry an earned title between the name and the
        # comma ("Shagga the Avenger, ..."), so match the name anywhere on the
        # sheet, not the exact "<name>," heading.
        grep -qF "$exp_name" "$sheet" || {
            echo "  FAIL  $label: sheet screen does not name $exp_name"
            note 1; return 1; }
        grep -qF "Race   $exp_race" "$sheet" || {
            echo "  FAIL  $label: sheet does not show Race   $exp_race"
            note 1; return 1; }
        grep -qF "Class  $exp_class" "$sheet" || {
            echo "  FAIL  $label: sheet does not show Class  $exp_class"
            note 1; return 1; }
        echo "  ok    $label: loaded $exp_name, a $exp_race $exp_class, and reached play"
    else
        # No external sheet: require the greeting's name to match the sheet's
        # own heading, so the sheet screen and the loaded character agree.
        got_name="$(sed -n 's/^.*Welcome back to Incursion, \(.*\)!.*/\1/p' "$arrival" | head -1)"
        if [ -n "$got_name" ] && grep -qF "$got_name" "$sheet"; then
            echo "  ok    $label: loaded $got_name and reached play"
        else
            echo "  FAIL  $label: greeting name ('$got_name') does not match the sheet heading"
            note 1; return 1
        fi
    fi

    if ! errors_clean "$run" "$out" "$label"; then
        note 1; return 1
    fi
    return 0
}

for distro in $DISTROS; do
    echo "=== $distro ==="
    distro_bad=0

    # Case A. Save on Linux, then load that save on Linux.
    SAVE_OUT="$("$RUNNER" --distro "$distro" --cc clang "$CHARGEN_KEYS" 1 2>&1)"
    SAVE_RUN="$(printf '%s\n' "$SAVE_OUT" | run_dir_from)"
    if [ -z "$SAVE_RUN" ] || [ ! -d "$SAVE_RUN" ]; then
        echo "  FAIL  $distro A-save: the save run produced no run directory"
        printf '%s\n' "$SAVE_OUT" | sed 's/^/        /'
        note 1; distro_bad=1
    else
        SAV="$(ls "$SAVE_RUN"/save/*.sav 2>/dev/null | head -1)"
        if [ -z "$SAV" ]; then
            echo "  cannot measure  $distro Case A: the save run wrote no .sav in $SAVE_RUN/save"
            printf '%s\n' "$SAVE_OUT" | sed 's/^/        /'
            note 2; distro_bad=1
        else
            SAVED_SCREEN="$(screen_of "$SAVE_RUN" 'saved' || true)"
            CH_NAME=""
            [ -n "$SAVED_SCREEN" ] && CH_NAME="$(name_from_saved_screen "$SAVED_SCREEN")"
            if [ -z "$CH_NAME" ]; then
                echo "  cannot measure  $distro Case A: no character name on the save screen"
                note 2; distro_bad=1
            else
                # chargen.keys builds a standard orc barbarian; the name is the
                # seed's, so it is read from the save's own status panel.
                CASE_A_EXPECT="$CH_NAME|Orc|Barbarian"
                load_case "$distro Case A" "$distro" "$SAV" "$CASE_A_EXPECT" || distro_bad=1
            fi
        fi
    fi

    # Case B. A macOS-made fixture save, loaded on Linux.
    CASE_B_EXPECT="$(expected_from_sheet "$MAC_SHEET")"
    load_case "$distro Case B" "$distro" "$MAC_SAV" "$CASE_B_EXPECT" || distro_bad=1

    if [ "$distro_bad" -eq 0 ]; then
        echo "PASS  $distro save round trip"
    else
        echo "FAIL  $distro save round trip"
    fi
done

case "$overall" in
    0) echo "RESULT: PASS -- saves round-trip on the tested Linux distro(s)"; exit 0 ;;
    1) echo "RESULT: FAIL -- a save did not load on Linux"; exit 1 ;;
    *) echo "RESULT: UNMEASURED -- no save could be produced to test"; exit 2 ;;
esac
