# God implementation

## god-blockers-versus-landing-requirements
Two terms. Use each for one meaning only. The branch where the work lives decides which term applies.
- A BLOCKER is open work a god needs that lives OUTSIDE the god's branch. An unsettled design question that the god's core depends on is also a blocker. Engine code ALWAYS lives outside the god's branch, because engine code is reusable and never bespoke to one god. Engine code that the base game needs without the pantheon lives on master. Pantheon engine code lives on the epic (`inc-pu6v`).
- A LANDING REQUIREMENT is open work the god needs that lives ON the god's branch: its data, scripts and text. The implementation builds it, with no merge.

Order for each god: (1) build every master blocker; (2) merge master into the epic once, through `merge-master-into-an-epic-through-a-bead`; (3) build every epic blocker; (4) branch the god from the epic, or merge the epic into the god's branch, once; (5) implement the god straight through; (6) land it into the epic. A god's implementation MUST NOT need any other merge. If a step would need one, a blocker was missed. STOP and report it to Brian as a readiness defect. Do NOT work around it.

A god lands only when every part of its settled design works and a player can playtest it. Do NOT land a god with part of its design disconnected. Do NOT call a bead "not a landing requirement" because the god's data still compiles without it.

When asked whether a god is ready, or for its blockers, answer with BLOCKERS ONLY first, grouped as master, epic and design. Say "ready to start" only when all three groups are empty and the step-2 merge is done. Then list landing requirements separately. To find both, check every open `inc-pu6v` child and every other open bead the god's design touches (pulse, aid, sacrifice, grants, expulsion, character creation, messages, character sheet) against its settled design.
Why: work built outside the god's branch during implementation forces extra merges across master, the epic and the god's branch.
History: docs/rules-history/god-implementation.md#god-blockers-versus-landing-requirements. Beads inc-4ykf, inc-k3pe, inc-6j7w.
