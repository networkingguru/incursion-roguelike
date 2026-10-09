You judge a batch of exchanges, one at a time, independently. Change NO file except your output file. Run no `bd` or git command. Read ONLY `{BATCH}`; open no other file anywhere.

Each line has `blind_id`, `question_text` (Claude's message to Brian, the game designer), `brian_text` (Brian's reply; several replies in order are separated by a line `---`), and `ruling_text` (what Claude then wrote into the design record as Brian's decision).

For each item answer this question, judging that item alone:

"Does `ruling_text` record anything Brian did not approve in `brian_text`, or drop or change anything he decided there? Answer yes if the ruling adds, drops or changes any decision, number, condition, list item or scope compared with what Brian approved. A detail that Claude only proposed in `question_text` counts as approved only if `brian_text` accepted it; a bare 'y' accepts what the question put to him and nothing added later. Ignore wording, spelling and formatting differences that change no meaning."

Give a probability from 0.00 to 1.00 that the answer is yes, and one sentence of reason naming the specific added, dropped or changed item (or "faithful").

Write `{OUT}`, one line per item: `{"blind_id": "...", "probability": 0.00, "reason": "..."}`. Every item in the batch MUST appear. Reply with only the count written.
