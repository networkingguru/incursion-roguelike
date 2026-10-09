You build a complete ruling ledger from one design record. Change NO tracked file. Run NO `bd` command and NO git command. Read ONLY the input file below and write ONLY the output file below; do not open any other file. Use American spelling and plain, short sentences.

Input: `{NOTES}`. It is the design record of the god {GOD} in the Incursion roguelike (the notes of bead {BEAD}): numbered rulings (`Rn`, some written `DOSSIER Rn`), plus unnumbered blocks such as BRAINSTORM, FINDINGS, CORRECTION, PANTHEON NOTE, AUDIT RULING, a CLOSING SECTION, and dated notes. Each ruling usually ends with Brian's words (`Brian: '...'`). Brian is the designer; his words are the authority.

Output: `{LEDGER}`.

THE RULE THAT MATTERS MOST: this is a ledger, not a summary. Every ruling and every unnumbered block gets its own entry. Do not merge rulings into ranges. Do not skip one because it looks minor, repeated, or covered elsewhere. Read the file from start to end in order, in slices; do not jump around.

Entry format, one block per item, in file order:

    ### R108 (2026-09-28) @offset 83579
    - Says: <the decision in one or two sentences, with every number it sets>
    - Brian: <his exact words, verbatim, or "none recorded">
    - Status: LIVE | AMENDED by <id> | SUPERSEDED by <id> | PARTLY SUPERSEDED by <id> (<which part>) | NOT A RULING (<why: e.g. Claude's finding, subagent draft, build note>)
    - Replaces: <ids this item supersedes or amends, or "none">

`@offset` is the byte offset of the item's first character in the input. For an unnumbered block, use an id like `N@<offset>` with its kind, e.g. `### N@164584 (2026-09-30 note)`. A CLOSING SECTION gets one entry per setting line it lists (id `CS:<setting name>`), and each such entry must say whether a numbered ruling with Brian's approval actually supports it, citing the ruling id, or "UNSUPPORTED".

Status needs care: when a later item changes an earlier one, mark BOTH ends (the earlier entry's Status and the later entry's Replaces). Check every later item against earlier ones it touches, including later dated notes and AUDIT RULINGs that change R-rulings without naming them. When a ruling says "provisional", say whether a later item made it final.

At the end, add a section `## Live design by part` that lists, for each part (1 What it demands, 2 How you atone, 3 What it gives, 4 How it punishes, 5 Crowning, Presentation), the ids of LIVE items only.

Reply in under 10 lines: the output path, the count of entries, and any place in the input you could not parse.
