#!/bin/bash
# Shared by tools/gate_record.sh and tools/gate_compare.sh. Turns a finished
# soak directory into the handful of numbers the regression gate compares.
#
# WHY THESE NUMBERS. Three metrics were tried on 2026-08-15 and two of them
# were useless:
#
#   Screen dumps. Almost any correct fix shifts game state, so the screens
#   diverge from the first changed decision onward and everything after it is
#   noise. A gate that fails on every correct fix gets switched off.
#
#   Crash seeds. The segfaulting seed moved between 3362 and 3387 depending on
#   which fix was present. Which seed crashes is not a stable identity.
#
#   Error volume and message-set membership. This held still and stayed
#   readable: the Target zero-init fix moved one assertion from 89,545
#   occurrences to none, and the post-fix message set was a strict SUBSET of
#   the pre-fix one. Subset is the shape to test for -- a message that was
#   never seen before is a regression, a message that stopped firing is a fix.
#
# Two logs carry messages. logs/errors.log is what the engine complains about.
# logs/mapaudit.log is what MapAudit.cpp finds when it checks a map against
# itself. Both are per-session, both are deterministic for a given seed, and
# the audit is the only one of the two that says anything on a healthy build,
# so leaving it out would leave the gate with nothing to hold on to today.
#
# KNOWN LIMIT. This detects regressions that produce log output. A defect that
# silently does the wrong thing and logs nothing passes clean. It never
# replaces a play-test.

# Emit the baseline body for a finished soak directory on stdout.
#
#   played    sessions that reached a map. A change that breaks character
#             generation drives every other number toward zero, and without
#             this line that reads as an improvement.
#   exits     the tally by exit code, so a build that starts crashing shows up
#             even if it crashes before it can log anything.
#   lines     total error lines, across sessions that played.
#   message   one line per distinct message: how many sessions hit it, how many
#             times in total, and the text. Sorted by text so two baselines
#             can be read side by side.
gate_collect() { # <soakdir>
    local soak="$1"
    local seen log seed sessions played code n

    [ -f "$soak/exits" ] || { echo "gate_collect: no exits file in $soak" >&2; return 1; }

    sessions="$(wc -l < "$soak/exits" | tr -d ' ')"

    # Exit 5 is NO GAMEPLAY and exit 2 could not start. Neither measured
    # anything, and counting them as sessions would let a broken run report
    # fewer errors than a working one.
    played=$(awk '$2!=5 && $2!=2' "$soak/exits" | wc -l | tr -d ' ')

    printf 'sessions\t%s\n' "$sessions"
    printf 'played\t%s\n' "$played"

    printf 'exits'
    awk '{print $2}' "$soak/exits" | sort -n | uniq -c |
        while read -r n code; do printf '\t%s=%s' "$code" "$n"; done
    printf '\n'

    seen="$(mktemp "${TMPDIR:-/tmp}/gate-seen.XXXXXX")"

    # One line per occurrence, as "<seed><TAB><message>". The timestamp is
    # stripped: it changes on every run and is not part of what went wrong.
    for log in "$soak"/seed-*/logs/errors.log; do
        [ -f "$log" ] || continue
        seed="$(basename "$(dirname "$(dirname "$log")")")"
        grep '^[0-9]' "$log" | sed 's/^[0-9-]* [0-9:]*  //' |
            sed "s|^|$seed\terr: |" >> "$seen"
    done

    printf 'lines\t%s\n' "$(awk -F'\t' '$2 ~ /^err: /' "$seen" | wc -l | tr -d ' ')"

    # Map audit findings. A finding line is indented and reads
    #   "    <kind>       xN     <which thing, where>"
    # so the fields separated by runs of two or more spaces are the kind, the
    # count, and the instance. Only the kind and the count go in: the instance
    # names a creature and a coordinate, which move whenever the dungeon does.
    for log in "$soak"/seed-*/logs/mapaudit.log; do
        [ -f "$log" ] || continue
        seed="$(basename "$(dirname "$(dirname "$log")")")"
        awk -F'  +' -v seed="$seed" '
            /^    / {
                kind = $2
                count = $3
                sub(/^x/, "", count)
                if (count !~ /^[0-9]+$/) count = 1
                for (i = 0; i < count; i++) printf "%s\taudit: %s\n", seed, kind
            }' "$log" >> "$seen"
    done

    printf 'findings\t%s\n' "$(awk -F'\t' '$2 ~ /^audit: /' "$seen" | wc -l | tr -d ' ')"

    awk -F'\t' '
        { total[$2]++; if (!(($1 SUBSEP $2) in hit)) { hit[$1 SUBSEP $2] = 1; sess[$2]++ } }
        END { for (m in total) printf "message\t%d\t%d\t%s\n", sess[m], total[m], m }
    ' "$seen" | sort -t"$(printf '\t')" -k4

    rm -f "$seen"
}

# Read one field out of a baseline file, ignoring comments.
gate_field() { # <file> <name>
    awk -F'\t' -v want="$2" '$1==want { print $2; exit }' "$1"
}
