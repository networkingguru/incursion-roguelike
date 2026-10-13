# God implementation — rules history

## god-blockers-versus-landing-requirements

(Named a-god-functionality-defect-is-a-blocker until 2026-10-07.)

2026-09-28. Asked for the blockers to Kysul's implementation (inc-pu6v.5), Claude listed only engine beads that Kysul's dossier named as blockers. It described inc-pu6v.97 (class categories) and inc-pu6v.99 (per-god expulsion, return and jealousy settings) as parts of the design with nothing to connect to, not as blockers. Brian replied:

"Then lket's do t6hiiose. NEW RULE: If it impacts fucntionality of the god, ITS A BLOCKER. I don't want half-implemented junk, I want to be able to playtest"

Bead inc-4ykf.

2026-10-07. Asked whether The Multitude (inc-pu6v.17) was ready to implement, Claude reported engine gaps, unruled tuning numbers and a divisor table to be measured as reasons the build could not start, and filed beads for them. None of them prevented starting. Brian replied:

"OK then you need to fucking update whatev er bullshit you use to define 'ready'. When I fuckign ask if a dosier is ready to start, or if there are blockers, I want to fucking know what things PREVENT us from building the god that we CANNOT or SHOULD NOT build while building the god. A BLOCKER is somethgin that BLOCKS starting the implementation, not asomethign that blocks the thing landing."

The rule was renamed and split into BLOCKER (start) and LANDING REQUIREMENT (land). The 2026-09-28 land-whole requirement is unchanged in substance. Bead inc-k3pe.

2026-10-13. The 2026-10-07 text said an engine bead that can be built alongside the god is a landing requirement, never a blocker. Engine code lives on master or the epic, so building it during a god's implementation forced trips out of the god's branch and extra merges back down. Brian wrote:

"SOmethign is fucked with the whole definition of blocker again, so let's sort it. When starting an implmementaion, I do NOT WANT: To stop to merge fuckign trees, to step out to master and make changes that then hacve to be pergedd to epoc and then have to also be merged to the god branch. I ALSO don't want to solve every single little fucking thing first. Perfect scenario: Anythign needed on master is built first, so master can be merged into epic ONCE PER FUCKING GOD. Then anything needed on epic is built so epic can marge to God branch ONE FUCKIN G time. Then I start god imp and it runs straight through wwith the only other merge happening when it is fuckign doen"

Asked whether engine code used by only one god could live on that god's branch, Brian wrote:

"If it is engine code, by. definition it is outside the god's branch. We do NOT make bespoke shit, we make reusable shit"

The rule now classifies by branch: work outside the god's branch (all engine code) and unsettled core design questions are blockers; work on the god's branch (data, scripts, text) is a landing requirement. Each god gets one master-to-epic merge, one epic-to-god merge and one landing merge. Bead inc-6j7w.
