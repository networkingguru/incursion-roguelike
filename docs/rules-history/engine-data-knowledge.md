# Archived full text -- not auto-loaded. The loaded rule lives in .claude/rules/engine-data-knowledge.md.

# Engine and save-data knowledge

## incursion-verify-disabled-content-with-program-i
To decide whether a lib/*.irh definition is actually IN the game, grep lib/program.i -- the preprocessed source the compiler consumes. Commented-out and #if 0 content is already gone from it, so presence in program.i is proof and absence is proof.

THE PATTERN MATTERS, AND THE OBVIOUS ONE LIES. program.i does not keep the source's declaration syntax. The class prefix compiles to a numeric source id, so a spell is NOT written `Spell "X"` and usually NOT `Effect "X"`:

    lib/pspells.irh   Priest Spell "Chant"              ->  program.i   52 Spell "Chant" : 46
    lib/wspells.irh   Wizard / Scroll Spell "Rigor Mortis" -> program.i  50 / 2 Spell "Rigor Mortis" : 1
    lib/pspells.irh   Priest Spell "Malignance"         ->  program.i   Effect "Malignance" : 2

So a bare `grep -c 'Spell "X"'` and a bare `grep -c '^Effect "X"'` BOTH return confident nonsense, and they disagree with each other. Use one pattern that accepts either keyword and requires the declaration colon:

    grep -ciE '(Spell|Effect) "<name>" *:' lib/program.i

Sanity-check any zero before believing it: `grep -in '"<name>"' lib/program.i` and look at what the lines actually are. A name appears many times as a list entry (`$"animate dead",`) without being declared, and it appears once as a declaration.

This cost three wrong answers on 2026-09-10 while checking whether Xel's domain spells exist. The first two patterns reported Unholy Blight, Malignance, Armour of Darkness, Pain Touch, Wrack and Spectral Spider as absent from the game. All six are present. Had I stopped there I would have told Brian his domain was half broken and filed a public bead saying so. The correct pattern found all 30 domain spells present.

DO NOT try to work it out by locating comment boundaries in the .irh by hand. On 2026-08-15 I scanned m_items.irh with grep -n '^/\*$\|^\*/$' and concluded that 440 lines and 18 ring effects were commented out. The comment opened at m_items.irh:4295 and closed at 4315 with TRAILING WHITESPACE after the '*/', so the anchored pattern missed the close and I ran the block on to the next bare '*/' at 4735. I then told Brian that an unidentified ring could not be harmful. He was wearing a Ring of Polymorphing at the time. Spell Disruption, Weakness, Ignorance and Aggravate Monster are all live and cursed.

If a hand scan is unavoidable, do not anchor: awk '/\/\*/ || /\*\//' prints every marker including indented and inline ones. But prefer program.i.

The same check confirmed the findings that WERE right, and is how they should have been established in the first place: 'the Mantis' boots absent, the fountain's 'animate objects' dip result absent, the 'hellish rift' placement line absent while Dungeon "The Nine Hells" and Region "Hellish Rift" are both present -- which is exactly why that dungeon compiles but cannot be entered.

General lesson: an empirical check on build output beats reading source structure, and Brian's report from play beats both. But a grep is only empirical about the pattern you actually typed -- confirm the pattern matches a case you KNOW is present before trusting a zero. See [[incursion-game-qa-session-role]] and [[incursion-check-for-a-live-instance]].

## save-schema-append-only-supersedes-name-keys
DECISION 2026-08-25, Brian's, worked out with him in conversation that afternoon. NORMATIVE TEXT LIVES IN docs/SAVE-SCHEMA-SPEC.md, Amendment 1. Read that, not a summary.

CORRECTION TO THE EARLIER VERSION OF THIS MEMORY: it said the save writes '8 bits slot, 5 bits array, 19 bits index'. Brian never said that. He read it back and said 'I did not size anything'. There is NO bit packing. A reference stays a plain rID. It also said thirteen arrays; there are 21.

THE RULE, in his words:
1. Never reorder. Never delete. Append only. No exception, no alphabetising, no moving a declaration between files.
2. Removal is a tombstone -- the line stays and keeps its position.
3. A replaced slot loads as the new resource, and that is KNOWN, EXPECTED and INTENDED. It happens only when it is the desired result. It is never a defect and MUST NOT be reported as one. He had to relitigate this point three times; do not make him do it again.
Array KINDS are append-only on the same terms.

THE FORMAT: the save gains a per-module manifest -- each of the 21 arrays' lengths in the fixed order, plus every entry's name in position order. References stay plain rIDs. The reader converts saved rID -> (array, position) using the manifest's lengths, then back using the loaded module's lengths. Deferred to SaveV1_ResolveNames, because modules reload after the save group is read.

WHY THE MANIFEST CARRIES NAMES, NOT JUST LENGTHS: lengths cannot detect a reorder -- alphabetising an array changes no length. ~3,430 names is about 70 KB against a 2.4 MB real save (save/Dench.sav), roughly 3%, and it makes the save judge the module rather than trust a build check we ran.

DRIFT RULES: refuse only on positive evidence of movement. A SLIDE (a run of 2+ consecutive positions where the current name equals the manifest's name one position earlier or later) or a SHUFFLE (same name set, at least one at a different position). Everything else loads silently -- one rename, ten, or every name in the array. Undetectable case, stated openly: rename everything AND reorder in one change; only the source diff sees that.

WHY THE ENGINE IS NOT TOUCHED: Module::__GetResource (src/Res.cpp:102-215) decodes an rID by subtract-and-walk across 21 arrays, so appending one Effect shifts every later array's ids. Re-slicing inside the engine costs ~70 sites across 11 files; Brian rejected that blast radius. The save layer converts instead.

See [[save-schema-order-ledger-design]] for the build-time half.
