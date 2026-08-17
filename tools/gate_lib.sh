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

# THE SETTINGS FILE IS AN INPUT, AND IT IS PINNED HERE.
#
# tools/headless.sh copies a settings file into every session. Left alone it
# copies the live one, which the game rewrites every time Brian plays. Settings
# change the game -- proved on 2026-08-15 by building sandboxes by hand for
# seeds 3, 5 and 9 with the old file and the new one: same binary, same seed,
# same keys, different screens in all three. The gate's finding count moved
# 4386 -> 4416 across a play session with no code change at all.
#
# So the gate plays with the committed file below and never the live one. The
# baseline records its checksum, and a comparison stops if the two disagree.
# Change the file when you mean to change it, then record a new baseline.
GATE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE_OPTIONS="${GATE_OPTIONS:-$GATE_LIB_DIR/gates/Options.Dat}"

gate_options_sum() { # <file>
    [ -f "$1" ] || { echo "missing"; return 0; }
    shasum -a 256 "$1" | awk '{print $1}'
}

# Does this baseline describe the settings the run is about to use? Returns 0
# when they match, 1 when the comparison would measure the settings as much as
# the build. Prints the reason either way; the caller decides what to do.
gate_options_check() { # <baseline> <optionsfile>
    local base="$1" opts="$2" want have

    want="$(gate_field "$base" options)"
    have="$(gate_options_sum "$opts")"

    if [ -z "$want" ]; then
        echo "  This baseline records no settings checksum, so it was recorded"
        echo "  before the settings were pinned -- with whatever Brian last"
        echo "  played with. Its numbers cannot be compared against anything."
        echo "  Record it again:  tools/gate_record.sh $(gate_field "$base" keys)"
        return 1
    fi
    if [ "$have" = "missing" ]; then
        echo "  The pinned settings file is gone: $opts"
        echo "  Restore it from git; it is committed for exactly this reason."
        return 1
    fi
    if [ "$want" != "$have" ]; then
        echo "  The pinned settings file has changed since this baseline was"
        echo "  recorded:"
        echo "    baseline: $want"
        echo "    now:      $have"
        echo "  Settings change the game, so the two runs are not comparable."
        echo "  Record a new baseline, or put the old file back."
        return 1
    fi
    return 0
}

# Emit the baseline body for a finished soak directory on stdout.
#
#   played    sessions that reached a map. A change that breaks character
#             generation drives every other number toward zero, and without
#             this line that reads as an improvement.
#   exits     the tally by exit code, so a build that starts crashing shows up
#             even if it crashes before it can log anything.
#   lines     total error lines, across sessions that played.
#   findings  total map-audit findings, across sessions that played.
#   died      sessions where OPT_NODEATH's death prompt decided, or nearly
#             decided, the session's fate by accident (inc-loa.3). These
#             sessions "played" by the metric above but generated no real
#             gameplay from that point on, which is exactly what would make a
#             build LOOK improved in lines/findings without being one.
#   threat_frozen  sessions where the threat-disengage prompt (inc-loa.5,
#             "Abort, Flee or Disengage?", src/Move.cpp:841) froze the
#             session -- same disease as 'died' above, a different unguarded
#             prompt. No settings gate exists for it, so unlike 'died' there
#             is no "confirmed, resolved cleanly" shape to also count: if
#             tools/keys/dive.keys never supplies 'a'/'f'/'d'/'?'/ESC, every
#             session that hits it is stuck by definition.
#   message   one line per distinct message: how many sessions hit it, how many
#             times in total, and the text. Sorted by text so two baselines
#             can be read side by side.
gate_collect() { # <soakdir>
    local soak="$1"
    local seen log seed sessions played died threat_frozen code n scr last

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

    # Sessions the OPT_NODEATH prompt (src/Fight.cpp, "You die... Die? [yn]")
    # decided, or nearly decided, by accident -- see inc-loa.3. Two shapes
    # both count as one 'died' tally, because both mean the session generated
    # no more real gameplay after the prompt appeared and so undercounts its
    # own errors and audit findings, exactly like a healthy quiet run would
    # not:
    #   confirmed  logs/death.log exists: the character genuinely died.
    #   stuck      no death.log, but the session's last screen still shows
    #              the prompt unanswered: it ran out of key budget parked
    #              there. Measured with tools/keys/dive.keys, seed 11
    #              (logs/gate/compare-dive-87655) -- see tools/headless.sh.
    # This is why gate_compare.sh no longer reads a quieter run as a plain
    # improvement without also saying how many of its sessions died.
    died=0
    for log in "$soak"/seed-*/logs/death.log; do
        [ -f "$log" ] || continue
        died=$((died + 1))
    done
    for scr in "$soak"/seed-*/logs/screens; do
        [ -d "$scr" ] || continue
        seed="$(basename "$(dirname "$(dirname "$scr")")")"
        [ -f "$soak/$seed/logs/death.log" ] && continue
        last="$(ls "$scr" 2>/dev/null | sort | tail -1)"
        [ -n "$last" ] || continue
        grep -q 'Die? \[yn\]' "$scr/$last" 2>/dev/null || continue
        died=$((died + 1))
    done
    printf 'died\t%s\n' "$died"

    # inc-loa.5: sessions frozen at the unguarded threat-disengage prompt
    # (src/Move.cpp:841, "Abort, Flee or Disengage?"). Same shape as 'died'
    # above -- checked by the same "text still on the last screen" signal --
    # but this prompt has no settings gate and, given dive.keys' vocabulary,
    # no way to resolve once it fires, so there is only one shape to count.
    threat_frozen=0
    for scr in "$soak"/seed-*/logs/screens; do
        [ -d "$scr" ] || continue
        last="$(ls "$scr" 2>/dev/null | sort | tail -1)"
        [ -n "$last" ] || continue
        grep -q 'threatened area' "$scr/$last" 2>/dev/null || continue
        threat_frozen=$((threat_frozen + 1))
    done
    printf 'threat_frozen\t%s\n' "$threat_frozen"

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
