# Bead duplicate check — spec (inc-zu0r)

Status: design settled with Brian 2026-09-24; decisions recorded in inc-zu0r notes.

## Problem

Nothing checks for an existing bead when a new one is filed. A defect gets a second bead, the fix lands under the new one, and the old one stays open. The 2026-09-24 sweep closed twelve such beads; inc-upw.29 is a thirteenth, found by the measurement below.

## Measurement that chose the method

`tools/bead_dupe_judge.py` asked Jev (TypeSafe's decision model, `typesafe/jev-1.13` on OpenRouter) "same defect?" for 14 known duplicate pairs and 12 hard non-duplicates (`tools/fixtures/bead-dupe-pairs.tsv`). With full title and description: ranking score (AUC) 0.976; at probability ≥ 0.7, 10 found, 0 false alarms, 4 missed. Title plus first paragraph did worse (0.896). Word overlap on the same pairs: 0.548. One run each; run-to-run variance is not measured. Details in inc-zu0r notes.

Consequences: word overlap only PRESELECTS candidates; Jev judges; Jev sees full text.

## Hard constraints

- MUST NOT call the Anthropic API anywhere.
- The OpenRouter key MUST NOT be printed, logged or written. Source: env `OPENROUTER_API_KEY`, else Keychain `security find-generic-password -a incursion -s incursion-openrouter -w`.
- Python standard library only.
- The account balance (currently $10, no per-key limit) is the hard cap. Each invocation also has a `--max-cost` guard.

## Components

### 1. `tools/bead_dupes.py` — the one engine

Shared by every caller. `tools/bead_dupe_judge.py` MUST import its key, request and parse functions from here instead of keeping its own copies.

**Bead data.** `bd list --all --limit 0 --json` (or `--beads-json PATH` for tests). Epics (`issue_type` epic) are never candidates.

**Preselection.** Tokens: lowercase `[a-z0-9]+`, length ≥ 3, minus a short stoplist. Score: Jaccard over the token sets of title + description. Keep the top K.

**Judgement.** One request per candidate pair, as in `bead_dupe_judge.py`, full title and description, each description cut to 12,000 characters (context is 32,000 tokens). Requests MAY run up to 8 at a time. Threshold constant `BLOCK_AT = 0.7`.

**Already-related pairs are skipped.** A pair already joined by a `duplicates`, `relates-to` or `parent-child` link is never judged or reported. A pair is also skipped when either bead's title or description names the other's id.

**Jev unavailable** means: no key, a network or HTTP error, an unparseable reply, or the `--max-cost` guard reached before every pair was judged. A partial result is still unavailable; it MUST NOT be reported as "no duplicates".

Subcommands:

- `check-draft --title T --description-file F [--parent P]` — candidates: every bead, open and closed, top K=20. Exit 0 no candidate ≥ 0.7; 1 at least one (printed: id, status, title, probability, highest first); 3 Jev unavailable (reason printed); 2 bad input.
- `check-bead ID --against open` — same, for an existing bead, candidates open beads only, top K=20. Same exits.
- `sweep --all` — every open bead against its top K=10 (open and closed). `sweep --since-last` — beads created or updated since the last sweep, plus beads whose notes hold `duplicate check skipped`, top K=10 each. Pairs are deduplicated; a pair whose beads are both closed is dropped. Prints pairs ≥ 0.7, then pairs judged, cost and failures. State file: `logs/bead-dupes-sweep.state` in the SHARED checkout (`$(git rev-parse --git-common-dir)/..`), written only after a complete sweep. Exits as above.
- `--selftest` — tokeniser, ranking, link-skip, parser, and `bead_new.sh` argument extraction on fixed inputs; nonzero on any failure.

`--max-cost` defaults: check-draft and check-bead 0.05; sweep --since-last 0.25; sweep --all 1.00.

### 2. `tools/bead_new.sh` — filing check, blocks

Before `bd create`, the wrapper extracts the draft: title from the first positional argument or `--title`; description from `-d`/`--description`, `--body-file PATH`, or stdin (`--stdin` or `--body-file -`: the wrapper reads stdin into a temp file and passes `--body-file <temp>` to bd instead). `--parent` passes through to the check.

- New wrapper flag `--not-a-duplicate`, removed before bd sees the arguments.
- Exit 1 from the check and no override: print the candidates, file nothing, exit 3 (new code: refused as a likely duplicate). The message names `--not-a-duplicate` and `bd duplicate <id> --of <canonical>`.
- Exit 1 with `--not-a-duplicate`: file, then append a note naming each candidate and its probability.
- Exit 3 (Jev unavailable) or 2: file, append the note `duplicate check skipped: <reason>`, and print this directive:

      DIRECTIVE TO THE FILING AGENT: the duplicate check could not run (<reason>).
      Spawn a subagent with model haiku. Give it bead <id> and the output of
      `bd list --all --json`, and have it name any bead that describes the same
      defect or work. Mark each one you confirm with
      `bd duplicate <id> --of <canonical>`.

- `-f`/`--file` and `--graph` (bulk create): no pre-check; print that the nightly sweep will check these beads.
- The existing `check_bead_publish.py` step, and exit codes 0/1/2, are unchanged.

### 3. `tools/finish_bead.sh` — closing check, reports only

After the landing succeeds, just before the final `bd close` hint, run `tools/bead_dupes.py check-bead "$BEAD" --against open`. Exit 1: print the candidates and the `bd duplicate` command. Exit 3/2: print the same haiku directive, worded for the closer. The check MUST NOT change `finish_bead.sh`'s exit status or run before the merge is proven.

### 4. Nightly sweep

Add one standing item to `~/Scripts/nightly-harness/projects/incursion/prompt.md` (outside this repo): run `tools/bead_dupes.py sweep --since-last`. Pairs ≥ 0.7 go into ONE held-queue bead per night (`needs-brian`), listing each pair with titles and probability, for Brian to confirm. Nothing is marked duplicate automatically. Exit 3: follow the haiku directive for the unchecked beads.

### 5. One-time backfill

After landing, Claude runs `tools/bead_dupes.py sweep --all` once (about 3,000 pairs, about $0.30) and brings the pairs to Brian.

## Fixture correction

`tools/fixtures/bead-dupe-pairs.tsv`: `inc-40oi inc-mjl6` becomes label 1, source `dup-found-by-jev` (same "All Monster Aggravate" segfault).

## The check that must go red

`tools/check_bead_dupes.sh`:
1. `bead_dupes.py --selftest` passes.
2. Live acceptance test from the bead: `check-draft` with inc-056c's own title and description, candidates excluding inc-056c itself, MUST exit 1 and list inc-41kg. No key or no network → the script exits 2 ("could not measure"), never 0.
3. Red proof, recorded in the commit body: set `BLOCK_AT` to 1.01 (step 2 goes red), and break the parser path (selftest goes red); restore both.
