#!/usr/bin/env python3
"""Decide whether `sonnet` goes first in the coding route (bead inc-cfnm).

THE RULE. Claude Code saves its status line input to a JSON file that carries
the seven-day rate-limit window:

    {"rate_limits": {"seven_day": {"used_percentage": 54,
                                   "resets_at": 1792436400}}, ...}

Only `rate_limits.seven_day` is read. The window is seven days long and ends
at `resets_at` (Unix seconds). The threshold paces about 10% of the window a
day, and day 7 allows up to 90% so spare usage is not lost at the reset:

  * If now >= resets_at the window has reset: used = 0, day = 1.
  * Otherwise start = resets_at - 604800 and
    day = clamp(floor((now - start) / 86400) + 1, 1, 7).
  * threshold = 90 when day == 7, else 10 * day - 5 (5, 15, ... 55).

`sonnet` goes first when the weekly used percentage is STRICTLY BELOW the
threshold for the current day. The verdict is UNKNOWN (exit 2) when the file
is missing or unreadable, is not JSON, lacks a numeric
`used_percentage`/`resets_at`, or is stale (mtime more than 3600s before now).

ENV VARS.
  INCURSION_CLAUDE_USAGE        override the status line path.
                                Default: ~/.claude/usage/statusline.json
  INCURSION_CLAUDE_BUDGET_NOW   override "now" (Unix seconds, for tests).
                                Default: time.time()

Exit 0 when sonnet goes first, 1 otherwise, 2 on UNKNOWN. Standard library only.
"""

import json
import math
import os
import sys
import time
from pathlib import Path

DEFAULT_USAGE = "~/.claude/usage/statusline.json"
STALE_SECONDS = 3600
WEEK_SECONDS = 604800
DAY_SECONDS = 86400


def resolve_path(env_name, default):
    override = os.environ.get(env_name)
    return Path(override).expanduser() if override else Path(default).expanduser()


def _unknown(reason):
    return {"state": "unknown", "day": None, "used": None,
            "threshold": None, "reason": reason}


def verdict(path=None, now=None):
    """Return the coding-route verdict as a dict.

    Keys: state ("sonnet-first"|"normal"|"unknown"), day (int|None),
    used (float|None), threshold (int|None), reason (str|None).
    """
    if path is None:
        path = resolve_path("INCURSION_CLAUDE_USAGE", DEFAULT_USAGE)
    else:
        path = Path(path).expanduser()

    if now is None:
        env_now = os.environ.get("INCURSION_CLAUDE_BUDGET_NOW")
        if env_now is not None:
            try:
                now = float(env_now)
            except ValueError:
                return _unknown(f"INCURSION_CLAUDE_BUDGET_NOW is not a number: {env_now}")
        else:
            now = time.time()
    else:
        now = float(now)

    try:
        mtime = os.stat(path).st_mtime
    except OSError as exc:
        return _unknown(f"cannot read usage file {path}: {exc}")

    if now - mtime > STALE_SECONDS:
        return _unknown(
            f"usage file {path} is stale (mtime {now - mtime:.0f}s before now)")

    try:
        text = path.read_text()
    except (OSError, UnicodeDecodeError) as exc:
        return _unknown(f"usage file {path} is not readable text: {exc}")

    try:
        data = json.loads(text)
    except Exception:
        return _unknown(f"usage file {path} is not JSON")

    if not isinstance(data, dict):
        return _unknown(f"usage file {path} is not a JSON object")

    limits = data.get("rate_limits")
    if not isinstance(limits, dict):
        return _unknown("usage file has no rate_limits object")
    seven = limits.get("seven_day")
    if not isinstance(seven, dict):
        return _unknown("usage file has no rate_limits.seven_day object")

    used = seven.get("used_percentage")
    resets_at = seven.get("resets_at")
    if isinstance(used, bool) or not isinstance(used, (int, float)):
        return _unknown("rate_limits.seven_day.used_percentage is missing or not a number")
    if isinstance(resets_at, bool) or not isinstance(resets_at, (int, float)):
        return _unknown("rate_limits.seven_day.resets_at is missing or not a number")

    used = float(used)
    resets_at = float(resets_at)

    if not math.isfinite(used) or used < 0 or used > 100:
        return _unknown("rate_limits.seven_day.used_percentage is not a sane percentage")
    if not math.isfinite(resets_at) or resets_at <= 0:
        return _unknown("rate_limits.seven_day.resets_at is not a sane timestamp")

    if now >= resets_at:
        day = 1
        used = 0.0
    else:
        start = resets_at - WEEK_SECONDS
        day = int(math.floor((now - start) / DAY_SECONDS)) + 1
        day = max(1, min(7, day))

    threshold = 90 if day == 7 else 10 * day - 5
    state = "sonnet-first" if used < threshold else "normal"
    return {"state": state, "day": day, "used": used,
            "threshold": threshold, "reason": None}


def main():
    result = verdict()
    if result["state"] == "unknown":
        print(f"claude-budget: {result['reason']}", file=sys.stderr)
        sys.exit(2)

    word = "sonnet-first" if result["state"] == "sonnet-first" else "normal"
    print(
        f"claude-budget: day {result['day']}, weekly used "
        f"{result['used']:g}%, threshold {result['threshold']}% -> {word}"
    )
    sys.exit(0 if result["state"] == "sonnet-first" else 1)


if __name__ == "__main__":
    main()
