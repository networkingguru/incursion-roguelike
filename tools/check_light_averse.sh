#!/bin/bash
# Phase-3 behavioral check for inc-jcg4.  It proves the unified light-averse
# penalty and its edge-triggered message together, then builds one red mutation
# for each half and requires the corresponding oracle to disappear.
# Usage: tools/check_light_averse.sh   (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

BIN="./incursion-headless"
SEED=1
WORK="$(mktemp -d "${TMPDIR:-/tmp}/inc-light-averse.XXXXXX")" || exit 2
cp -f src/Fight.cpp "$WORK/Fight.cpp"
cp -f src/Creature.cpp "$WORK/Creature.cpp"

restore() {
    cp -f "$WORK/Fight.cpp" src/Fight.cpp
    cp -f "$WORK/Creature.cpp" src/Creature.cpp
}
cleanup() {
    restore
    rm -rf "$WORK"
}
trap cleanup EXIT HUP INT TERM

build() {
    BACKEND=posix ./build_macos.sh >/dev/null || {
        echo "INCONCLUSIVE: headless build failed for $1"; exit 2; }
}

run_case() { # run_case <keys>; echoes run directory
    local out status run
    out="$(INCURSION_LIGHT_PROBE=1 INCURSION_BIN="$BIN" tools/headless.sh "$1" "$SEED" 2>&1)"
    status=$?
    run="$(printf '%s\n' "$out" | awk '/^run:/ {print $2}')"
    [ "$status" -eq 0 ] || {
        echo "INCONCLUSIVE: $1 exited $status. Run dir: $run" >&2
        echo "$out" >&2
        return 2
    }
    printf '%s\n' "$run"
}

has_squint() { grep -rqF "You squint and stagger in the bright light" "$1/logs/screens"; }
has_penalty() { grep -rqE "Attack:.* -4 light" "$1/logs/screens"; }

check_probe() { # check_probe <run> <kind>
    local line
    line="$(grep '^P ' "$1/logs/light.log" | tail -1)"
    case "$2" in
      bright)
        printf '%s\n' "$line" | grep -Eq 'plight=0 pbright=0 psource=(9[0-9]|[1-9][0-9][0-9]+) punified=1' ;;
      dim)
        printf '%s\n' "$line" | awk '{
          for(i=1;i<=NF;i++){split($i,a,"="); v[a[1]]=a[2]}
          exit !(v["plight"]==0 && v["pbright"]==0 &&
                 v["psource"]>=48 && v["psource"]<90 && v["punified"]==0)}' ;;
    esac
}

build green

bright="$(run_case tools/keys/light-averse-bright.keys)" || exit 2
dim="$(run_case tools/keys/light-averse-dim.keys)" || exit 2
check_probe "$bright" bright || {
    echo "INCONCLUSIVE: bright fixture was not dynamic-only bright. Run dir: $bright"; exit 2; }
check_probe "$dim" dim || {
    echo "INCONCLUSIVE: dim fixture was not in [48,90). Run dir: $dim"; exit 2; }
has_penalty "$bright" && has_squint "$bright" || {
    echo "FAIL: bright fixture did not show both -4 light and the squint. Run dir: $bright"; exit 1; }
if has_penalty "$dim" || has_squint "$dim"; then
    echo "FAIL: dim fixture showed a light penalty or squint. Run dir: $dim"; exit 1
fi
echo "green: dynamic-only bright level 96 produced both oracles; dim level 50 produced neither"

# Red mutation 1: restore the two old FI_LIGHT-only combat predicates.
perl -0pi -e 's/e\.EActor->HasMFlag\(M_LIGHT_AVERSE\) &&\n        e\.EActor->m->BrightAt\(e\.EActor->x,e\.EActor->y\)/e.EActor->HasMFlag(M_LIGHT_AVERSE) \&\& e.EActor->inField(FI_LIGHT)/; s/e\.EVictim->HasMFlag\(M_LIGHT_AVERSE\) &&\n        e\.EVictim->m->BrightAt\(e\.EVictim->x,e\.EVictim->y\)/e.EVictim->HasMFlag(M_LIGHT_AVERSE) \&\& e.EVictim->inField(FI_LIGHT)/' src/Fight.cpp
build penalty-red
red_penalty="$(run_case tools/keys/light-averse-bright.keys)" || exit 2
if has_penalty "$red_penalty" || ! has_squint "$red_penalty"; then
    echo "FAIL: penalty-red mutation did not drop only the -4 label. Run dir: $red_penalty"; exit 1
fi
echo "red penalty: reverting the combat predicates dropped -4 light and retained the squint"

# Red mutation 2: restore green combat, then remove the per-turn edge detector.
cp -f "$WORK/Fight.cpp" src/Fight.cpp
perl -0pi -e 's/\n    \/\* Light aversion follows BrightAt.s cutoff and reports only dim-to-bright edges\. inc-jcg4 \*\/\n    if \(HasMFlag\(M_LIGHT_AVERSE\)\) \{.*?\n    \}\n/\n/s' src/Creature.cpp
build message-red
red_message="$(run_case tools/keys/light-averse-bright.keys)" || exit 2
if ! has_penalty "$red_message" || has_squint "$red_message"; then
    echo "FAIL: message-red mutation did not drop only the squint. Run dir: $red_message"; exit 1
fi
echo "red message: reverting the per-turn edge detector dropped the squint and retained -4 light"

restore
build restored-green
echo "PASS: light aversion shares BrightAt's 90 cutoff; both independent red mutations were detected"
