# tools/fidelity: does a god's design record match what Brian approved?

A god dossier's design record is the notes on its bead. Claude writes each
entry after Brian answers a question. An entry can record more, less or other
than Brian approved, and a summary brief made from the notes copies those
faults. This folder checks the record against the conversations that made it.
Bead inc-h5d5; method tested on Maeve (inc-pu6v.9), 2026-10-09.

No script here calls an LLM API. The ledger, judge and check steps run as
Claude Code subagents (`model: "opus"`, description starting `research:`)
from the prompts in `prompts/`. Fill each `{PLACEHOLDER}` before dispatch.

Run the four steps on a dossier before its god's build starts, and again
before it lands. Put every output in a git-ignored folder; below, `F` is that
folder and `B` is the god's bead id.

## 0. Snapshot the notes

    bd show B --json | python3 -c 'import json,sys; d=json.load(sys.stdin); d=d[0] if isinstance(d,list) else d; sys.stdout.write(d["notes"])' > F/notes.txt

Every later step reads this snapshot, so all steps see the same record.

## 1. Ledger

Dispatch one Opus agent with `prompts/ledger.md` (`{NOTES}` = `F/notes.txt`,
`{LEDGER}` = `F/ledger.md`). Then:

    python3 -I tools/fidelity/coverage.py --notes F/notes.txt --ledger F/ledger.md

Exit 0 means every ruling number has an entry. Exit 1 names the missing ones:
send the agent back for them. Copy the finished ledger to
`~/Scripts/Incursion-inc-pu6v/dossier-brief/ledgers/B.md`, where dossier
sessions read it first (`.claude/rules/pantheon-dossier.md`).

## 2. Pairs

    python3 -I tools/fidelity/build_pairs.py --bead B --notes F/notes.txt --out F/pairs.jsonl

It scans every transcript under `~/.claude/projects/-Users-brianhill-Scripts-Incursion*/`
(or `--transcripts <file or dir>`), finds each `bd update B ... --append-notes`,
and pairs it with the Brian reply its quoted words come from and Claude's
question before that reply. It never uses a reply sent after the write. It
MUST end with `missing ruling numbers: none` and `time-order violations: 0`.

## 3. Judge

    python3 -I tools/fidelity/make_batches.py judge --pairs F/pairs.jsonl --batches 8 --outdir F/judge

Dispatch one Opus agent per batch with `prompts/judge.md` (`{BATCH}` =
`F/judge/batch<i>.jsonl`, `{OUT}` = `F/judge/out<i>.jsonl`), in parallel. Each
agent judges its pairs one at a time and gives a probability that the entry
adds, drops or changes what Brian approved. When a pair is rebuilt later,
re-judge only that pair into a new file, and list that file LAST in step 4 so
it supersedes the first score.

## 4. Check

    python3 -I tools/fidelity/make_batches.py flags --pairs F/pairs.jsonl --scores F/judge/out*.jsonl --threshold 0.3 --batches 4 --outdir F/check

Dispatch one Opus agent per batch with `prompts/check.md` (`{FLAGS}`,
`{OUT}`, `{NOTES}` = `F/notes.txt`, `{LEDGER}`, `{TRANSCRIPTS}` = the
transcript files `build_pairs.py` reported, `{HANDLED}` = ruling ids Brian has
already ruled on, or "none"). Each flag gets one verdict: ADDED_NOTES,
PAIRING, NO_REPLY_OK, SETTLED, SURVIVOR or HANDLED.

Then Claude reads EVERY row, not only the SURVIVOR rows. On Maeve the agents
gave zero SURVIVORs, and two items still rested on Claude's choice (a scope
exclusion and a number Brian never gave). Bring each such item to Brian one
at a time: say first what the thing is in play, then what the record says,
then what he said. Record each answer as a new ruling in the bead's notes.

## 5. Mark the ledger

    python3 -I tools/fidelity/mark_ledger.py --ledger F/ledger.md --notes F/notes.txt --pairs F/pairs.jsonl --checks F/check/out*.jsonl --extra F/extra.txt --date YYYY-MM-DD

`F/extra.txt` holds one line per ruling Brian just made: `<ledger id>`, a tab,
then the text. The script backs the ledger up first, and refuses to run when
that backup already exists.

## Evidence (Maeve, 2026-10-09)

- Deleting the R108 entry turned the coverage check red. A fresh agent
  answering from the ledger got 5 of 5 questions right that Claude had
  answered wrong from summaries.
- On an answer key (6 real errors, 12 clean pairs, 10 planted errors, 10
  mismatched pairs), Opus with the 0.3 line gave 6/6, 0/12 false alarms,
  10/10 and 10/10 in each of three runs. Jev raised false alarms on 33–50%
  of clean pairs, Sonnet found 4/6, and a free-form Opus pass found 2/5.
- The full run gave 288 pairs and 71 flags. The check found two items, now
  rulings C9 and C10. A pairing fault had hidden four real flags until the
  pairing was fixed.

## Proving the scripts can fail

Each script has `--selftest`. `red_proof.py --outdir <git-ignored dir>`
breaks one feature at a time in a copy of each script and confirms that its
selftest goes red. It ends with `red-proof: PASS`.

## Limits

- The judge reads only its pair, so it cannot see a decision made in an
  earlier exchange. Step 4 is why.
- Agent cost per dossier has not been measured.
