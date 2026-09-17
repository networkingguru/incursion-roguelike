#!/usr/bin/env python3
# The SessionStart memory injection, cut down to what a session must be told.
#
# Usage: tools/prime_rules.py            emit the SessionStart hook JSON
#        tools/prime_rules.py --budget   print the token estimate and exit
#
# WHY THIS EXISTS. `bd prime --hook-json` emits 409 KB, about 102,000 tokens.
# The host refuses a payload that size: it injects a 2 KB preview, writes the
# rest to a file, and tells the model to go read it. Sessions read the preview
# and start work, so the rules never arrive.
#
# That is not hypothetical. On 2026-09-17 a session landed three beads and
# stopped after `git commit` to ask, between each step, whether to land and
# whether to close. The memory `commit-means-land-the-bead` forbids exactly
# that, and had been written EARLIER THE SAME DAY after another session did the
# same thing. The rule existed, was correct, and was invisible. There is even a
# memory named `read-the-persisted-bd-prime-output-first`, sitting inside the
# file nobody reads. See bd inc-2e9w.
#
# So the hook was never the problem. The payload has to be small enough to
# survive injection, and that means choosing what goes in.
#
# WHAT GOES IN. Memories that say HOW A SESSION MUST WORK. What stays out is
# session state -- the `resume-*` notes, which are half the corpus and buy
# nothing at startup, because a session that needs one asks for it by name.
#
# THE OUTPUT SAYS WHAT IT WITHHELD. A filter that silently drops things is how
# this defect happened in the first place, one layer up. The tail of the block
# names the count and the command, so a session knows what it has not seen.

import json
import re
import subprocess
import sys

# ---------------------------------------------------------------- the filter --
# EDIT THIS AND NOTHING ELSE when a memory is in the wrong bucket.
#
# A key matching any of these is a RULE and is injected. Everything else is
# reference material a session can fetch on demand. Prefixes, matched at the
# start of the key.
RULE_PREFIXES = (
    "feedback-",       # how Brian wants a session to behave
    "commit-",         # what commit/save/push mean here
    "bead-",           # filing and labelling rules
    "beads-",
    "no-",             # standing prohibitions
    "always-",
    "read-the-",
    "prose-only-",
    "escalated-",
    "epic-children-",
    "agents-md-",
    "nightly-",        # what the unattended run may and may not do
    "probe-",
    "gate-",
    "layout-",
    "character-fixtures-",
    "save-schema-append",
    "incursion-a-",            # a diagnosis needs its falsifier
    "incursion-check",
    "incursion-measure",
    "incursion-never",
    "incursion-one-run",
    "incursion-test",
    "incursion-verif",
    "incursion-worktree",
)

# A hard ceiling, in characters. Roughly four characters to a token, so this is
# about 25,000 tokens. Brian set the budget at 21,000 on 2026-09-17; the slack
# is for the workflow context and for growth. If the corpus grows past this the
# hook says so out loud rather than silently shipping something the host will
# truncate -- which is this bead's whole defect.
BUDGET_CHARS = 100_000

HEADER = """\
[bd prime, filtered] These are the RULE memories, injected whole. Session
notes (`resume-*`) and reference material are NOT here; ask for one by name
with `bd memories <keyword>` when you need it.
"""


def memories():
    """Every memory as {key: text}. Raises if bd cannot be read."""
    out = subprocess.run(
        ["bd", "memories", "--json"],
        capture_output=True, text=True, timeout=120,
    )
    if out.returncode != 0:
        raise RuntimeError(f"bd memories failed: {out.stderr.strip()[:200]}")
    data = json.loads(out.stdout)
    return {k: v for k, v in data.items() if isinstance(v, str)}


def is_rule(key):
    return key.startswith(RULE_PREFIXES)


def build(mem):
    """Return (text, kept, withheld). Deterministic order, so a diff is readable."""
    kept = sorted(k for k in mem if is_rule(k))
    withheld = sorted(k for k in mem if not is_rule(k))

    parts = [HEADER]
    for k in kept:
        parts.append(f"### {k}\n{mem[k].strip()}\n")
    parts.append(
        f"WITHHELD: {len(withheld)} memories are not shown here, of "
        f"{len(mem)} total. They are session notes and reference material.\n"
        f"Read one with: bd memories <keyword>\n"
    )
    return "\n".join(parts), kept, withheld


def main():
    try:
        mem = memories()
    except Exception as e:
        # FAIL LOUD, NEVER SILENT. A hook that shrugs when it cannot read the
        # database leaves the session believing it has been told the rules.
        # Brian's standing rule: a tool must FAIL, not pass, when it cannot
        # establish what it is looking at.
        text = (
            "[bd prime, filtered] COULD NOT READ THE MEMORIES: "
            f"{e}\nYou have NOT been given this project's rules. "
            "Run `bd memories` before doing anything that changes a file.\n"
        )
        emit(text)
        return 0

    text, kept, withheld = build(mem)

    if "--budget" in sys.argv:
        print(f"memories   {len(mem)}")
        print(f"injected   {len(kept)}")
        print(f"withheld   {len(withheld)}")
        print(f"chars      {len(text)}")
        print(f"~tokens    {len(text) // 4}")
        print(f"budget     {BUDGET_CHARS} chars (~{BUDGET_CHARS // 4} tokens)")
        return 0 if len(text) <= BUDGET_CHARS else 1

    if len(text) > BUDGET_CHARS:
        # Say it in the payload itself, where a session will see it, rather
        # than on stderr where the hook runner swallows it.
        text += (
            f"\nWARNING: this block is {len(text) // 4} tokens, over its "
            f"{BUDGET_CHARS // 4} budget. The host may truncate it, and if it "
            "does you are reading a preview and not the rules. See bd inc-2e9w.\n"
        )

    emit(text)
    return 0


def emit(text):
    json.dump(
        {"hookSpecificOutput": {
            "hookEventName": "SessionStart",
            "additionalContext": text,
        }},
        sys.stdout,
    )
    sys.stdout.write("\n")


if __name__ == "__main__":
    sys.exit(main())
