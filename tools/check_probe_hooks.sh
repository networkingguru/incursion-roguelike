#!/bin/bash
# gate: cheap
# Every debugging hook in the shipped game names a bead, and none is deleted
# until the reproduction it carries is preserved somewhere upstream can read it.
#
# Usage: tools/check_probe_hooks.sh              # check
#        tools/check_probe_hooks.sh --baseline   # re-record the known backlog
# Exit:  0 no undeclared hook outside the baseline
#        1 a hook names no bead, or the baseline is stale
#        2 nothing was measured, and the reason is printed
#
# WHY THIS EXISTS. The game reads two dozen INCURSION_* environment variables at
# run time. They are not compiled out for release: they are plain getenv calls,
# live in the binary a stranger downloads, and six of them change how the game
# plays rather than merely logging what it did. Each was added with a comment
# promising it would go when its bead closed. Almost none has gone. Beads close,
# the scaffolding stays, and nothing notices.
#
# THE RULE IT ENFORCES, and it is one rule: a hook must say which bead it serves.
# That is all. It is cheap to obey when you add a hook and impossible to
# reconstruct a year later, which is why the check is worth having at all.
#
# THE RULE IT REFUSES TO ENFORCE. It will not tell you to delete anything. A
# probe is often the only reproduction a defect has -- the state can be
# unreachable from a key script, so the probe IS the evidence -- and several of
# these back claims already made to the original maintainer. Deleting one of
# those destroys our answer to "how do you know?". So a hook whose bead is
# finished is reported as HELD until its reproduction exists as a patch under
# docs/evidence/<bead>/, and only then as RETIRED. docs/evidence/inc-ijs/
# destroy-probe.patch is the pattern: the probe leaves the source and stays
# readable, and the bead and the REPORTING-GATE row point at it.
#
# See docs/REPORTING-GATE.md, "Reconstructing a removed probe".
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
BASELINE="tools/probe_hooks.baseline"

# Documented facilities, not scaffolding. These are how the tools drive the
# game and are meant to stay: the seed, the key budget, the map audit, the
# error prompt, the heap-layout switch, which is compiled out anyway, the
# pad-help override (docs/CONTROLS-ally.md, inc/Term.h) that forces the
# controller ? screen for tools/check_pad_help.sh without a real gamepad, and
# the OOB probe, a compiled-out diagnostic (only under -DINCURSION_OOB_PROBE)
# with documented A/B-build usage at src/Display.cpp:768-780; kept for the same
# reason as the heap-layout switch, not scaffolding waiting to be deleted.
# INCURSION_COSMETIC_BURN and INCURSION_RNG_BURN are the two halves of one
# documented facility, not scaffolding: they spend draws off one random stream
# so tools/check_rng_split.sh can prove the other is unmoved, and the check
# needs them for as long as the two streams exist. Read in SeedCosmeticStream
# (src/Main.cpp); the reasoning is above cosmetic_int32 in src/Base.cpp. Kept
# for the same reason as INCURSION_SEED, which is also only ever set by tools.
KNOBS="INCURSION_SEED INCURSION_MAX_KEYS INCURSION_MAP_AUDIT INCURSION_ERROR_PROMPT INCURSION_LAYOUT INCURSION_PAD_HELP INCURSION_OOB_PROBE INCURSION_COSMETIC_BURN INCURSION_RNG_BURN"

command -v bd > /dev/null || {
    echo "COULD NOT MEASURE: bd is not on PATH, so no bead status can be read."
    exit 2
}

hooks="$(grep -rhoE 'getenv\("INCURSION_[A-Z_]+"' src/ inc/ 2>/dev/null |
         sed 's/getenv("//; s/"//' | sort -u)"

[ -n "$hooks" ] || {
    echo "COULD NOT MEASURE: no getenv(\"INCURSION_...\") found in src/ or inc/."
    echo "  Either the tree moved or this script's pattern is stale."
    exit 2
}

# The bead a hook serves is the nearest tracking id above one of its call
# sites. Forty lines is the window: these hooks sit under a block comment that
# explains them, and the id lives in that comment.
# One scan of src/ and inc/ builds "<hook> <id>" lines, same answer as the old
# per-hook greps: files in grep -r order, first getenv line per file, last id in
# the window; the first file that yields an id wins (inc-b0ziu.4).
HOOK_BEAD="$(grep -rlE 'getenv\("INCURSION_[A-Z_]+"' src/ inc/ 2>/dev/null |
    python3 -c '
import re, sys
seen = {}
for path in sys.stdin.read().split("\n"):
    if not path:
        continue
    lines = open(path, encoding="latin-1").read().split("\n")
    first = {}
    for n, text in enumerate(lines, 1):
        for h in re.findall(r"getenv\(\"(INCURSION_[A-Z_]+)\"", text):
            first.setdefault(h, n)
    for h, n in first.items():
        if h in seen:
            continue
        window = "\n".join(lines[max(n - 40, 1) - 1:n])
        ids = re.findall(r"inc-[a-z0-9]+(?:\.[0-9]+)*", window)
        if ids:
            seen[h] = ids[-1]
for h, i in seen.items():
    print(h, i)
')"

bead_for() {
    printf '%s\n' "$HOOK_BEAD" | awk -v h="$1" '$1 == h { print $2; exit }'
}

# Read every status once: one bd call costs about as much as the whole list,
# and 142 calls cost ~100 s (inc-b0ziu.4). STATUS_MAP holds "<id> <STATUS>" lines.
if ! STATUS_MAP="$(bd list --all --json --limit 0 2>/dev/null | python3 -c '
import json, sys
for b in json.load(sys.stdin):
    print(b["id"], str(b.get("status", "")).upper())
' 2>/dev/null)" || [ -z "$STATUS_MAP" ]; then
    echo "COULD NOT MEASURE: bd list --all --json failed or printed no JSON list of beads."
    exit 2
fi

status_of() {
    printf '%s\n' "$STATUS_MAP" | awk -v id="$1" '$1 == id { print $2; exit }'
}

# One scan per question (inc-b0ziu.4). A hook matches only as a whole word, as
# grep -w did: tokens are maximal [A-Za-z0-9_]+ runs, so INCURSION_X never
# matches INCURSION_X_XX. Output "<hook>TAB<files, space-joined>", files in the
# order grep -r lists them.
WORD_SCAN='
import re, sys
files = [f for f in sys.stdin.read().split("\n") if f]
out = {}
for path in files:
    text = open(path, encoding="latin-1").read()
    for tok in set(re.findall(r"[A-Za-z0-9_]+", text)):
        if tok.startswith("INCURSION_"):
            out.setdefault(tok, []).append(path)
for tok, fs in out.items():
    print(tok + "\t" + " ".join(fs))
'
DRIVEN_MAP="$(grep -rl INCURSION_ tools --include='*.sh' 2>/dev/null |
    grep -v 'check_probe_hooks\.sh$' | python3 -c "$WORD_SCAN")"
CITED_MAP="$( { grep -l INCURSION_ docs/REPORTING-GATE.md 2>/dev/null
                grep -rl INCURSION_ docs/evidence 2>/dev/null; } |
    python3 -c "$WORD_SCAN")"

# Which check script, if any, drives this hook? Prints the scripts, or nothing.
#
# WHY THIS EXISTS. On 2026-08-29 this tool listed twelve hooks as HELD and told
# the reader to delete each one from src/. Six of them are what a regression
# check in tools/ sets to reach the state it measures: INCURSION_ARMOUR_PROBE
# is how tools/check_armour_model.sh reads the armour model, and
# INCURSION_HANDLE_BASE is how tools/check_menu_value.sh gives an ordinary
# character wide object handles from birth. Obeying the instruction would have
# broken six checks in one commit. A hook a check drives is a facility whatever
# its bead says, and the KNOBS list above could not see that because it is a
# hardcoded string of five names.
#
# This is DELIBERATELY NARROW. It changes the verdict only for a hook whose
# bead is already closed. It does not touch the rule this whole file exists for
# -- that a hook must name the bead it serves -- and a hook that names no bead
# is still reported however many scripts drive it. Widening it to skip the
# naming rule, the way KNOBS does, would exempt seven more hooks from the only
# check here that has ever caught anything.
#
# tools/*.sh only, and never this script: a .keys file mentions a hook in a
# comment without setting it, tools/README.md describes one in prose, and this
# file lists them all by construction.
# -w, not -F. A plain substring match says INCURSION_HANDLE_BASE is driven by a
# script that only mentions INCURSION_HANDLE_BASE_XX, which is how the first
# version of this function passed its own break test while measuring nothing.
# -w requires a word boundary, and `_` counts as a word character to grep, so
# the longer name no longer matches the shorter one.
driven_by() {
    printf '%s\n' "$DRIVEN_MAP" | awk -F'\t' -v h="$1" '$1 == h { print $2; exit }'
}

# A hook can be load-bearing with no script driving it, because it IS the
# reproduce command of a claim already written down. Deleting one of those
# leaves the ledger row and the evidence README naming a command that no longer
# exists -- the exact failure this file's header warns about. Ruling, 2026-09-07
# (inc-loa.25): as long as a repro needs it, it stays.
#
# Only COMMITTED claims count: the ledger and the evidence READMEs. src/ is
# deliberately not searched, because the upstream: marker quoting the command
# sits in the same file as the getenv it describes, so a match there would
# prove nothing. -w for the same reason driven_by uses it.
cited_by() {
    printf '%s\n' "$CITED_MAP" | awk -F'\t' -v h="$1" '$1 == h { print $2; exit }'
}

if [ "${1:-}" = "--baseline" ]; then
    : > "$BASELINE"
    for h in $hooks; do
        case " $KNOBS " in *" $h "*) continue ;; esac
        [ -z "$(bead_for "$h")" ] && echo "$h" >> "$BASELINE"
    done
    echo "recorded $(wc -l < "$BASELINE" | tr -d ' ') undeclared hook(s) in $BASELINE"
    exit 0
fi

[ -f "$BASELINE" ] || {
    echo "COULD NOT MEASURE: no $BASELINE."
    echo "  Record the hooks that predate this rule, once:"
    echo "    tools/check_probe_hooks.sh --baseline"
    exit 2
}

orphans=0; stale=0; live=0; held=0; retired=0; knobs=0; inuse=0
declare -a HELD_LIST RETIRED_LIST NEW_LIST INUSE_LIST

for h in $hooks; do
    case " $KNOBS " in *" $h "*) knobs=$((knobs+1)); continue ;; esac
    id="$(bead_for "$h")"

    if [ -z "$id" ]; then
        if grep -qxF "$h" "$BASELINE"; then
            orphans=$((orphans+1))
        else
            NEW_LIST+=("$h")
        fi
        continue
    fi

    # A hook that has since been given a bead must leave the baseline, or the
    # baseline slowly becomes a list of things that are already fixed.
    grep -qxF "$h" "$BASELINE" && { stale=$((stale+1)); NEW_LIST+=("$h names $id but is still in the baseline"); }

    case "$(status_of "$id")" in
        OPEN|IN_PROGRESS|BLOCKED|"")
            live=$((live+1)) ;;
        *)
            drivers="$(driven_by "$h")"
            citers="$(cited_by "$h")"
            if [ -n "$drivers" ]; then
                inuse=$((inuse+1)); INUSE_LIST+=("$h ($id) <- $drivers")
            elif [ -n "$citers" ]; then
                inuse=$((inuse+1)); INUSE_LIST+=("$h ($id) <- reproduce command in $citers")
            elif ls docs/evidence/"$id"/*.patch > /dev/null 2>&1; then
                retired=$((retired+1)); RETIRED_LIST+=("$h ($id)")
            else
                held=$((held+1)); HELD_LIST+=("$h ($id)")
            fi ;;
    esac
done

echo "hooks:    $((knobs + live + held + retired + orphans + inuse)) reading the environment in src/ and inc/"
echo "  knob:      $knobs documented facility, not scaffolding"
echo "  live:      $live serving a bead that is still open"
echo "  in use:    $inuse bead finished, but a check or a committed repro needs it"
echo "  held:      $held bead finished, reproduction NOT yet preserved"
echo "  retired:   $retired bead finished, reproduction preserved -- safe to delete"
echo "  undeclared: $orphans naming no bead, known and baselined"

if [ "$inuse" -gt 0 ]; then
    echo
    echo "IN USE -- the bead is finished, but the hook is still load-bearing:"
    echo "        a check in tools/ sets it to reach the state it measures, or"
    echo "        a committed reproduce command names it. DO NOT DELETE THESE."
    echo "        The reproduction is the check or the command, and it runs:"
    printf '  %s\n' "${INUSE_LIST[@]}"
fi

if [ "$held" -gt 0 ]; then
    echo
    echo "HELD -- these are UNFINISHED CLOSES, not permanent residents. The bead"
    echo "        is done and the probe should have gone with it. Save each one as"
    echo "        a patch under docs/evidence/<bead>/, then delete it from src/:"
    printf '  %s\n' "${HELD_LIST[@]}"
fi

if [ "$retired" -gt 0 ]; then
    echo
    echo "RETIRED -- reproduction is preserved, so the source copy can go:"
    printf '  %s\n' "${RETIRED_LIST[@]}"
fi

if [ ${#NEW_LIST[@]} -gt 0 ]; then
    echo
    echo "FAIL -- a hook must name the bead it serves, in a comment within 40"
    echo "        lines above its getenv:"
    printf '  %s\n' "${NEW_LIST[@]}"
    echo
    echo "  Add the tracking id to the comment. If this hook predates the rule"
    echo "  and you are not fixing it now, re-record the backlog with"
    echo "  tools/check_probe_hooks.sh --baseline and say so in the commit."
    exit 1
fi

echo
echo "PASS -- every hook outside the recorded backlog names its bead."
exit 0
