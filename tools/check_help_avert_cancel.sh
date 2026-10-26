#!/usr/bin/env bash
# gate: cheap
# gate-fast: static, reads lib/help.irh only, under 1 s
#
# Guards bead inc-ih2.8: the in-game help names the Avert Eyes stance in the
# Combat Options entry, and lists what Cancel Active Power ends (with the
# polymorph-curse limit) in the Cancel Active Power entry.
#
# fact: the help text -- read from lib/help.irh; no game run, no seed
# fact: character, options, map, monsters -- not read; this check starts no session
#
# Exit 0 pass, 1 fail, 2 could not measure.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
F=${HELP_FILE:-lib/help.irh}
[ -r "$F" ] || { echo "UNMEASURED: cannot read $F"; exit 2; }

# Flatten: join every line, squeeze whitespace, so wrapping cannot matter.
ALL=$(tr '\n' ' ' < "$F" | tr -s ' \t' ' ')
[ -n "$ALL" ] || { echo "UNMEASURED: $F is empty"; exit 2; }

# An entry runs from its heading to the next "<15>" heading.
entry() {
    local rest=${ALL#*"$1"}
    [ "$rest" != "$ALL" ] || return 1
    printf '%s' "${rest%%<15>*}"
}

FAIL=0
COMBAT=$(entry "Combat Options ('<13>c<15>')") || { echo "UNMEASURED: no Combat Options entry"; exit 2; }
CANCEL=$(entry "Cancel Active Power ('<13>x<15>')") || { echo "UNMEASURED: no Cancel Active Power entry"; exit 2; }

need() { # entry-text label phrase
    if ! grep -qF -- "$3" <<< "$1"; then
        echo "FAIL: $2 lacks: $3"
        FAIL=1
    fi
}

need "$COMBAT" "Combat Options" "One option, Avert Eyes, makes you look away from your foes."
need "$COMBAT" "Combat Options" "Gaze attacks against you then fail half the time"
need "$COMBAT" "Combat Options" "about one attack in four misses, or one in eight with the Blind-Fight feat."
need "$COMBAT" "Combat Options" "until you stop with the Cancel Active Power ('x') command."
need "$CANCEL" "Cancel Active Power" "The menu lists only what you can stop at that moment."
need "$CANCEL" "Cancel Active Power" "averted or closed eyes, and a polymorph you caused yourself."
need "$CANCEL" "Cancel Active Power" "It cannot end a polymorph caused by a curse, such as a cursed Ring of Polymorphing."

if [ "$FAIL" -ne 0 ]; then exit 1; fi
echo "PASS: Avert Eyes and cancel-list paragraphs present"
exit 0
