# God implementation

## god-blockers-versus-landing-requirements
Two terms. Use each for one meaning only.
- A BLOCKER prevents STARTING a god's implementation. It is something the god cannot or should not be built without, AND that cannot or should not be built while building the god. Example: an unsettled design question that the god's core depends on.
- A LANDING REQUIREMENT is any open bead (defect or missing engine feature) that affects how the god functions in play, and that is not a blocker. A god lands only when every part of its settled design works and a player can playtest it. Do NOT land a god with part of its design disconnected. Do NOT call a bead "not a landing requirement" because the god's data still compiles without it.

When asked whether a god is ready, or for its blockers, answer with BLOCKERS ONLY first: "ready to start" when there are none. Then list landing requirements separately, named as landing requirements. An engine bead, an unruled tuning number or a missing feature that can be built alongside the god is a landing requirement, NEVER a blocker. To find landing requirements, check every open `inc-pu6v` child and every other open bead the god's design touches (pulse, aid, sacrifice, grants, expulsion, character creation, messages, character sheet) against its settled design, and list every one that affects it.
Why: calling a landing requirement a blocker stops a build that could start, and a half-implemented god still cannot land.
History: docs/rules-history/god-implementation.md#god-blockers-versus-landing-requirements. Beads inc-4ykf, inc-k3pe.
