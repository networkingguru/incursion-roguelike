#!/bin/bash
# gate: live
# inc-u69w: a pen-coloured glyph must not be drawn black on black in the
# curses build.
#
# What it protects. posixTerm::APutChar (src/Wposix.cpp:756) gives a glyph an
# explicit pen colour when the glyph has none of its own:
#
#     g = GLYPH_ID_VALUE(g)
#       | GLYPH_FORE(attr & COLOUR_MASK)
#       | GLYPH_BACK((attr >> COLOUR_BITS) & COLOUR_MASK);
#
# inc/Defines.h defines GLYPH_FORE(value) as (value << GLYPH_FORE_SHIFT) with
# no brackets around the parameter, so `GLYPH_FORE(attr & COLOUR_MASK)` was
# really `attr & (COLOUR_MASK << 12)` -- zero for every pen. A glyph meant to
# take the pen therefore stored foreground 0 on background 0 and went to the
# terminal as ESC[30m ESC[40m: black on black, invisible. The fix brackets
# every GLYPH_* macro parameter.
#
# The screen it watches is the skill-rank pool. Managers.cpp:1662 colours the
# unspent-rank star row AZURE (colour 9 = blue, drawn with A_BOLD by
# posixTerm::Update, src/Wposix.cpp:721) and then draws the stars as '*' via
# PutChar (Managers.cpp:1666). Those stars carry no colour of their own, so
# they are exactly the glyphs the defect made invisible. tools/keys/
# assassin-bard.keys opens that screen and this check reads the raw terminal
# capture from the first star after the "Unspent Skill Ranks" heading. It
# PASSES only when that star is sent with foreground 34 (blue) and bold on.
#
# It FAILS -- never passes -- when the heading, the star row or the colour
# state cannot be established, so a run that produced nothing usable is
# reported as a failure and not as a green.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ ! -x ./incursion-headless ]; then
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
fi

KEYS=tools/keys/assassin-bard.keys
OPTIONS=tools/fixtures/options-2026-08-22.dat
RUN_DIR="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-curses_pen_colour"

mkdir -p "$ROOT/logs/runs"

TERM=xterm INCURSION_OPTIONS="$OPTIONS" INCURSION_RUN_DIR="$RUN_DIR" \
    tools/headless.sh --tty "$KEYS" 1 > "$RUN_DIR.outerr" 2>&1
run_status=$?

TERMOUT="$RUN_DIR/logs/terminal.out"

# The capture is raw terminal bytes: the heading and the star arrive with
# escape sequences between them, so the colour state in force AT the star can
# only be read by walking those sequences in order. The walker reports the
# foreground code, whether bold is on, and whether a colour state was ever
# established at all; anything it cannot establish it reports as absent, and
# the caller fails on that.
WORK="$ROOT/logs/runs/$(basename "$RUN_DIR").parser"
mkdir -p "$WORK"
cat > "$WORK/read_star.py" <<'PY'
import sys

path = sys.argv[1]
try:
    data = open(path, "rb").read()
except OSError:
    print("missing - -")
    sys.exit(0)

heading = b"Unspent Skill Ranks"
h = data.find(heading)
if h < 0:
    print("no-heading - -")
    sys.exit(0)

i = h + len(heading)
fg = None          # last foreground colour code (30-37), or None
bold = False
saw_state = False  # any SGR that could set a colour or weight

# Walk explicitly, escape sequence by escape sequence. A '*' inside an escape
# (a parameter byte, a terminfo literal) must never be mistaken for the star.
star = None
while i < len(data):
    b = data[i]
    if b == 0x1b:  # ESC
        # CSI: ESC [ params final
        if i + 1 < len(data) and data[i + 1] == 0x5b:  # '['
            j = i + 2
            params = bytearray()
            while j < len(data) and not (0x40 <= data[j] <= 0x7e):
                params.append(data[j])
                j += 1
            final = data[j] if j < len(data) else None
            if final == 0x6d:  # 'm' = SGR
                saw_state = True
                raw = bytes(params)
                # Empty params ("ESC[m") mean reset, exactly like ESC[0m.
                nums = [0] if raw == b"" else [
                    int(p) if p else 0 for p in raw.split(b";")
                ]
                for n in nums:
                    if n == 0:
                        fg = None
                        bold = False
                    elif n == 1:
                        bold = True
                    elif 30 <= n <= 37:
                        fg = n
            i = j + 1
            continue
        # Non-CSI escape: ESC ( B, ESC ) 0, or a two-byte sequence. Charset
        # selection ESC(B does not touch the SGR state.
        i += 2
        continue
    if b == 0x2a:  # '*'
        star = i
        break
    i += 1

if star is None:
    print("no-star - -")
    sys.exit(0)
if not saw_state or fg is None:
    print("no-state - -")
    sys.exit(0)
print("ok %d %d" % (fg, 1 if bold else 0))
PY

read -r VERDICT FG BOLD < <(python3 -I "$WORK/read_star.py" "$TERMOUT")
rm -rf "$WORK"

case "$VERDICT" in
    ok)
        if [ "$run_status" -ne 0 ]; then
            echo "FAIL: headless --tty exited $run_status; capture is not trustworthy."
            echo "Specimen: $TERMOUT"
            echo "Command: TERM=xterm INCURSION_OPTIONS=$OPTIONS INCURSION_RUN_DIR=$RUN_DIR tools/headless.sh --tty $KEYS 1"
            echo "Output:  $RUN_DIR.outerr"
            exit 1
        fi
        if [ "$FG" = "34" ] && [ "$BOLD" = "1" ]; then
            echo "PASS: the first unspent-rank star is sent blue (34) and bold --"
            echo "      the pen colour reaches the terminal, not black on black."
            rm -rf "$RUN_DIR" "$RUN_DIR.outerr"
            exit 0
        fi
        if [ "$FG" = "30" ]; then
            echo "FAIL: the first unspent-rank star is sent black on black:"
            echo "      foreground $FG, bold $BOLD. The pen colour (AZURE = blue)"
            echo "      never reached the glyph -- GLYPH_FORE/GLYPH_BACK are"
            echo "      dropping it (inc-u69w). Wanted foreground 34, bold 1."
        elif [ "$BOLD" != "1" ]; then
            echo "FAIL: the first unspent-rank star is not bold:"
            echo "      foreground $FG, bold $BOLD. Wanted foreground 34, bold 1."
        else
            echo "FAIL: the first unspent-rank star is not blue:"
            echo "      foreground $FG, bold $BOLD. Wanted foreground 34, bold 1."
        fi
        echo "Specimen: $TERMOUT"
        echo "Command: TERM=xterm INCURSION_OPTIONS=$OPTIONS INCURSION_RUN_DIR=$RUN_DIR tools/headless.sh --tty $KEYS 1"
        echo "Output:  $RUN_DIR.outerr"
        exit 1
        ;;
    no-heading)
        echo "FAIL: 'Unspent Skill Ranks' is not in the terminal capture;"
        echo "      the skill-rank screen was never drawn or was never captured."
        ;;
    no-star)
        echo "FAIL: no '*' follows 'Unspent Skill Ranks' in the terminal capture;"
        echo "      the unspent-rank star row is missing."
        ;;
    no-state)
        echo "FAIL: no SGR colour state could be read between the heading and the"
        echo "      star; cannot tell whether the star is blue. Failing, not passing."
        ;;
    missing|-)
        echo "FAIL: no terminal capture at $TERMOUT; the --tty run produced nothing."
        ;;
    *)
        echo "FAIL: the terminal capture could not be interpreted ($VERDICT)."
        ;;
esac
echo "Specimen: $TERMOUT"
echo "Command: TERM=xterm INCURSION_OPTIONS=$OPTIONS INCURSION_RUN_DIR=$RUN_DIR tools/headless.sh --tty $KEYS 1"
echo "Output:  $RUN_DIR.outerr"
exit 1
