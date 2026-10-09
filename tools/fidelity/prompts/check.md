# Check flagged ruling records against the transcripts

Brian is the designer of the game god {GOD}. Over several sessions, Claude
asked him design questions and then wrote his decisions into a design record
(the notes of bead {BEAD}). A judge compared each record entry with the reply
Brian gave, and flagged the entries listed in your batch file. Your job is to
sort each flag, and to find the ones where the record says Brian decided
something he did not decide.

Change NO file except your output file. Run no `bd` or git command. Do not
edit any source. American spelling.

## Files

- Your batch: `{FLAGS}`. One flag per line: `pair_id`, judge `score` and
  `judge_reason`, `r_numbers` (ruling numbers in the entry), `pairing`,
  `brian_reused` (true = this entry was written with no new reply from Brian;
  the reply shown belongs to an earlier entry), `write_ts`, `brian_ts`,
  `question_text` (Claude's message before Brian's reply, last 6000 chars),
  `brian_text` (Brian's reply or replies, separated by `---`), `ruling_text`
  (the record entry).
- Session transcripts (JSONL, Claude Code format), one per session:
  {TRANSCRIPTS}. A `pair_id` starts with its session id (the first 8
  characters of the transcript file name, or the full stem). Use grep with a
  timestamp or a distinctive phrase; do not read whole files. Brian's messages
  are `"type":"user"` events with plain text content.
- The record as it stands today: `{NOTES}`. Later entries can supersede
  earlier ones, including AUDIT RULINGs and other dated rulings.
- The ruling ledger: `{LEDGER}` (one entry per ruling, with LIVE / AMENDED /
  SUPERSEDED / NOT A RULING status). Grep it by ruling id (`### R97 `).

## Already handled: skip

If the flag is about one of these rulings, give verdict `HANDLED` and stop:
{HANDLED}.

## For each flag, give exactly one verdict

- `ADDED_NOTES`: the entry only adds Claude's own material (evidence, file:line
  citations, build notes, VERIFY items, status claims, sim numbers, proposals
  clearly marked as pending/awaiting Brian, or consequences clearly labeled
  as Claude's reasoning), and attributes to Brian no decision beyond what he
  approved.
- `PAIRING`: the reply shown is the wrong one. Find Brian's real reply in the
  transcript (quote it, give its timestamp). If the entry matches the real
  reply, use this verdict.
- `NO_REPLY_OK`: `brian_reused` is true or no reply fits; the entry is
  Claude's correction or finding and does not present itself as a Brian
  decision, or it says it awaits Brian.
- `SETTLED`: the entry did add, drop or change a decision, but a later entry
  or a later Brian message fixed it, so the record today is right. Cite the
  later entry id or the message timestamp, and quote it.
- `SURVIVOR`: the entry records as Brian's decision something he did not
  approve, or drops or changes something he decided, and nothing later fixes
  it. This includes a `brian_reused` entry that records a new decision as
  ruled with no Brian approval anywhere.

Before you give `SURVIVOR`, you MUST: (1) grep the transcript around
`write_ts` to read what Claude actually put to Brian and every reply he gave
in that exchange (a "y" approves what the question showed him, including a
detail inside a longer proposal); (2) grep the notes and the ledger for every
later entry about the same item.

A detail that Claude chose and Brian never addressed (a number, a scope
limit, an exclusion) rests on his silence, and is NOT approved even when
Claude labeled it as its own reading. When a decision in the design depends
on such a detail, give `SURVIVOR` and say it rests on silence.

## Output

Write `{OUT}`, one line per flag:

    {"pair_id": "...", "verdict": "...", "item": "<the specific detail at issue, one short phrase>",
     "record_says": "<short quote from the entry>", "brian_said": "<short quote + timestamp, or 'nothing'>",
     "later": "<later entry id + short quote, or 'none'>", "note": "<one sentence>"}

Every flag in your batch MUST appear. Reply with only the counts per verdict.
