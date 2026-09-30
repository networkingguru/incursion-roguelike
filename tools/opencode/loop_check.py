#!/usr/bin/env python3
"""loop_check.py -- detect a DeepSeek repetition loop in one opencode step.

    tools/opencode/loop_check.py <events.jsonl>

Reads an opencode events.jsonl (one JSON object per line; a partial last line
and non-JSON lines are tolerated) and inspects each step_finish event. A step's
text is the concatenation of every "text" part carrying the same messageID; the
step_finish arrives after those text parts.

A step is a LOOP STEP when, after removing everything inside ``` code fences,
the stripped non-empty lines shorter than SHORT_LINE characters include
MIN_REPEATED_LINES or more distinct lines each occurring MIN_OCCURRENCES or
more times, AND the step's tokens.output is at least MIN_OUTPUT_TOKENS.

Exit 1 on the first loop step, printing to stdout one line

    loop messageID=<id> output_tokens=<n> repeated_lines=<n>

then the last 600 characters of that step's text. Exit 0 with no output when no
loop step is found. Exit 2 on a usage error or an unreadable file.

Used by tools/watchdog.sh as its --canary: run as
`loop_check.py --out <events.jsonl>` it exits 1 on the first loop step found so
the watchdog stops a looping run the idle limit would never catch.
"""

import json
import sys
from collections import Counter

MIN_REPEATED_LINES = 15
MIN_OUTPUT_TOKENS = 2000
SHORT_LINE = 40
MIN_OCCURRENCES = 3

TAIL_CHARS = 600


def usage_error(message):
    sys.stderr.write("loop_check: %s\n" % message)
    sys.stderr.write("usage: tools/opencode/loop_check.py <events.jsonl>\n")
    sys.exit(2)


def parse_args(argv):
    # Accept both the plain form and the watchdog canary form `<file> --out
    # <path>`, so the same script serves either way.
    path = None
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg == "--out":
            if i + 1 >= len(argv):
                usage_error("--out needs a file")
            path = argv[i + 1]
            i += 2
            continue
        if arg.startswith("-") and arg != "-":
            usage_error("unknown argument: %s" % arg)
        if path is not None:
            usage_error("more than one events file given")
        path = arg
        i += 1
    if path is None:
        usage_error("no events file given")
    return path


def read_events(path):
    try:
        raw = open(path, "r", encoding="utf-8", errors="replace").read()
    except OSError as exc:
        usage_error("cannot read %s: %s" % (path, exc))
    events = []
    for line in raw.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            events.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return events


def strip_code_fences(text):
    out = []
    in_fence = False
    for line in text.splitlines():
        if line.strip().startswith("```"):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        out.append(line)
    return "\n".join(out)


def repeated_line_count(text):
    visible = strip_code_fences(text)
    lines = []
    for line in visible.splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        if len(stripped) < SHORT_LINE:
            lines.append(stripped)
    counts = Counter(lines)
    return sum(1 for count in counts.values() if count >= MIN_OCCURRENCES)


def step_texts_and_finishes(events):
    texts = {}
    finishes = []
    for ev in events:
        if not isinstance(ev, dict):
            continue
        part = ev.get("part") or {}
        if not isinstance(part, dict):
            continue
        mid = part.get("messageID")
        if ev.get("type") == "text":
            chunk = part.get("text")
            if isinstance(chunk, str):
                texts.setdefault(mid, []).append(chunk)
        elif ev.get("type") == "step_finish":
            finishes.append((mid, part))
    return texts, finishes


def output_tokens(part):
    tokens = part.get("tokens") or {}
    if isinstance(tokens, dict):
        value = tokens.get("output")
        if isinstance(value, (int, float)) and not isinstance(value, bool):
            return int(value)
    return None


def main(argv):
    path = parse_args(argv)
    events = read_events(path)
    texts, finishes = step_texts_and_finishes(events)

    for mid, part in finishes:
        tokens = output_tokens(part)
        if tokens is None or tokens < MIN_OUTPUT_TOKENS:
            continue
        text = "".join(texts.get(mid, []))
        repeated = repeated_line_count(text)
        if repeated >= MIN_REPEATED_LINES:
            sys.stdout.write(
                "loop messageID=%s output_tokens=%d repeated_lines=%d\n"
                % (mid, tokens, repeated)
            )
            sys.stdout.write(text[-TAIL_CHARS:])
            sys.stdout.write("\n")
            return 1

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
