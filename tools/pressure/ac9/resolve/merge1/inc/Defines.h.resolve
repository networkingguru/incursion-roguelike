#define FT_CANNIBALISM         362
/* Exclusive upper bound of the feat-id range Player::GainFeat's PERK_FEAT
   case draws a random starting-background feat from (src/Create.cpp,
   random(FT_PERK_LAST - FT_FIRST) + FT_FIRST). A feat at or above this
   boundary is never a candidate for that draw. Every FF_CREATION_ONLY feat
   (inc/Creature.h) MUST sit at or above FT_PERK_LAST -- Player::
   FeatPerkRangeGuard (src/Create.cpp) checks this every creation and is
   Fatal if violated. Kept separate from FT_LAST so a new creation-only feat
   can be added without changing the width of that random() call, which
   would otherwise shift the deterministic background feat every seeded
   race/class draws, for every seed, on every build (inc-z8qn; this is what
   broke tools/check_feat_toggle.sh when FT_RELIGIOUS_NONCONFORMIST first
   landed inside [FT_FIRST, FT_LAST)). Renumbered to +48 when master's
   FT_LUCUBRATION (+47) landed inside the perk draw range (merge inc-pu6v.297). */
#define FT_PERK_LAST           (FT_TUVWXYZ + 48) /* alias of FT_RELIGIOUS_NONCONFORMIST */
/* Creation-only: opens the gods that are open (neither native nor forbidden)
   for the character's race (spec Section 7). docs/specs/2026-09-30-god-race-lists-spec.md
   (inc-z8qn). Lives at FT_PERK_LAST, never below it (see that constant). */
#define FT_RELIGIOUS_NONCONFORMIST (FT_TUVWXYZ + 48)
/* inc-2jd0: Lucubration, appended after FT_CANNIBALISM so existing feat
   numbers stored in saves are unchanged. */
/* inc-2jd0: Lucubration, appended after FT_CANNIBALISM so existing feat
   numbers stored in saves are unchanged. */
#define FT_LUCUBRATION         363
#define FT_LAST                (FT_TUVWXYZ + 49)
@@@ next hunk
// family: msg_band internal


/* inc-pu6v.108: god messages are banded by family, 1000 codes each. A family
   grows inside its band; add a new family as a new band. Codes 1-999 belong
   to monster messages (MSG_BLASTNAME 200 and up) and nothing else. Plain
   literals only: the module compiler reads this header through the C
   preprocessor. */
#define MSG_BAND_SINGLE   1000
#define MSG_BAND_BADSAC   2000
#define MSG_BAND_BLESSING 3000
#define MSG_BAND_CUSTOM   4000
#define MSG_BAND_AID      5000
#define MSG_BAND_FALL     6000
#define MSG_BAND_HATE     7000
#define MSG_BAND_SHEET    8000
#define MSG_BAND_END      9000
// end family: msg_band
// no-family
#define MSG_BAND_SIZE     1000
// end no-family
// family: msg internal
