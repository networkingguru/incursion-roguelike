#!/bin/bash
# Regression check: every Steam Input key_press token avoids known-invalid
# spellings, and tokens not attested in Valve's shipped SteamOS templates are
# made visible for manual verification.
#
# WHY IT EXISTS. Steam Input keyboard bindings have the form
#     "binding"    "key_press <TOKEN>, <human description>"
# but an unrecognised token neither rejects the config nor produces a log: the
# activator silently never fires and looks exactly like a dead button. On
# 2026-08-30 this repository shipped key_press MINUS for the R3-hold
# Exchange-Weapons binding. Steam requires DASH, so MINUS left R3 hold dead for
# everyone who installed that release.
#
# HOW IT PROVES IT. The check extracts the first word after every key_press,
# strips its trailing comma, and reports every line for each distinct token.
# Known near-misses fail; tokens outside the lower-bound allowlist from Valve's
# own SteamOS templates warn without failing. --selftest pins the real config's
# clean pass and proves that the exact MINUS regression fails.
#
# Usage: tools/check_vdf_tokens.sh [vdf-file]
#        tools/check_vdf_tokens.sh --selftest
# Ends:  0 pass, 1 fail, 2 the check could not be run.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/tools/check_vdf_tokens.sh"

# Human-maintained policy lists. The allowlist is deliberately a lower bound.
DENYLIST="MINUS HYPHEN PLUS UNDERSCORE SLASH BACKSPACE_KEY CTRL ALT SHIFT ESC DEL"
ALLOWLIST="1 2 3 4 A B C COMMA D DASH DOWN_ARROW E END ENTER EQUALS ESCAPE F F1 F10 F11 F12 F2 F3 F4 F5 F6 F7 F8 F9 FORWARD_SLASH G H HOME I J K KEYPAD_1 KEYPAD_2 KEYPAD_3 KEYPAD_4 KEYPAD_6 KEYPAD_7 KEYPAD_8 KEYPAD_9 L LEFT_ALT LEFT_ARROW LEFT_CONTROL LEFT_SHIFT LEFT_WINDOWS M N NEXT_TRACK O P PAGE_DOWN PAGE_UP PERIOD PLAY PREV_TRACK Q R RETURN RIGHT_ARROW S SPACE T TAB U UP_ARROW V VOLUME_DOWN VOLUME_UP W X Y Z"

selftest() {
    local fixture real_output real_status bad_output bad_status

    real_output="$("$SCRIPT" "$ROOT/docs/incursion-steam-input-ally.vdf" 2>&1)"
    real_status=$?
    if [ "$real_status" -ne 0 ]; then
        echo "SELFTEST FAIL: real VDF returned $real_status, expected 0"
        echo "$real_output"
        return 1
    fi

    fixture="$(mktemp "${TMPDIR:-/tmp}/check_vdf_tokens.XXXXXX")" || {
        echo "SELFTEST FAIL: could not create temporary fixture"
        return 1
    }
    trap 'rm -f "$fixture"' RETURN
    printf '%s\n' '"binding"  "key_press MINUS, dummy"' > "$fixture" || {
        echo "SELFTEST FAIL: could not write temporary fixture"
        return 1
    }

    bad_output="$("$SCRIPT" "$fixture" 2>&1)"
    bad_status=$?
    if [ "$bad_status" -ne 1 ]; then
        echo "SELFTEST FAIL: MINUS fixture returned $bad_status, expected 1"
        echo "$bad_output"
        return 1
    fi

    echo "SELFTEST PASS"
    return 0
}

if [ "${1:-}" = "--selftest" ]; then
    selftest
    exit $?
fi

TARGET="${1:-$ROOT/docs/incursion-steam-input-ally.vdf}"
[ -e "$TARGET" ] || {
    echo "INCONCLUSIVE: target file does not exist: $TARGET"
    exit 2
}
[ -r "$TARGET" ] || {
    echo "INCONCLUSIVE: target file is not readable: $TARGET"
    exit 2
}

awk -v denylist="$DENYLIST" -v allowlist="$ALLOWLIST" -v target="$TARGET" '
BEGIN {
    split(denylist, words, " ")
    for (i in words)
        denied[words[i]] = 1
    split(allowlist, words, " ")
    for (i in words)
        allowed[words[i]] = 1
}
/key_press/ {
    text = $0
    sub(/^.*key_press[[:space:]]+/, "", text)
    split(text, fields, /[[:space:]]+/)
    token = fields[1]
    sub(/,$/, "", token)
    if (!(token in seen)) {
        seen[token] = 1
        order[++count] = token
        lines[token] = NR
    } else {
        lines[token] = lines[token] ", " NR
    }
}
END {
    failures = 0
    warnings = 0
    for (i = 1; i <= count; i++) {
        token = order[i]
        if (token in denied) {
            printf "FAIL: key_press token \047%s\047 is invalid (line %s)\n", token, lines[token]
            failures++
        } else if (!(token in allowed)) {
            printf "WARN: key_press token \047%s\047 is not attested in Valve\047s templates - verify on a SteamOS box before shipping (line %s)\n", token, lines[token]
            warnings++
        }
    }
    if (failures) {
        printf "FAIL: %s has %d distinct key_press tokens; %d invalid token(s) on the denylist.\n", target, count, failures
        exit 1
    }
    if (warnings) {
        printf "PASS: %s has %d distinct key_press tokens, %d warned, none on the denylist.\n", target, count, warnings
        exit 0
    }
    printf "PASS: %s has %d distinct key_press tokens.\n", target, count
    exit 0
}
' "$TARGET"
exit $?
