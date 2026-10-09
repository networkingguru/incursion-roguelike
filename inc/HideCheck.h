/* HIDECHECK.H -- See the Incursion LICENSE file for copyright information.

   inc-u3dp phase 1: the pure functions that a hide/spot check will use, plus
   the TRIED-stati keys that carry a check's state across a turn. NOTHING here
   is wired into play yet: Perceives, Hide and every game behaviour are
   unchanged. The functions are pure (they read the world and never mutate it,
   except the two Hide*Key helpers, which are the only writers here). */

#ifndef HIDECHECK_H
#define HIDECHECK_H

#include "Defines.h"

class Creature;
class Item;
class Map;
class Thing;

/* State keys on the existing TRIED stati. Each (key, source) pair is one
   entry; HideSetKey never leaves two for the same pair. The four keys must
   differ, and each must fit a signed 16-bit Val field (Status::Val :16). */
#define HK_SPOT_RESULT  (SK_SPOT       + 100*EV_SPOT_CHECK)
#define HK_HIDE_BAND    (SK_HIDE       + 100*EV_SPOT_CHECK)
#define HK_DISTRACT     (SK_LISTEN     + 100*EV_SPOT_CHECK)
#define HK_ROAR         (SK_INTIMIDATE + 100*EV_SPOT_CHECK)

/* A check's four keys must be distinct, or two kinds of state would share one
   TRIED entry and overwrite each other. A Val field is signed 16 bits
   (struct Status, inc/Res.h), so every key must stay below 32767. */
#if (HK_SPOT_RESULT == HK_HIDE_BAND) || (HK_SPOT_RESULT == HK_DISTRACT) || \
    (HK_SPOT_RESULT == HK_ROAR) || (HK_HIDE_BAND == HK_DISTRACT) || \
    (HK_HIDE_BAND == HK_ROAR) || (HK_DISTRACT == HK_ROAR)
#error "inc-u3dp: the four hide-check TRIED keys must be distinct"
#endif
#if (HK_SPOT_RESULT >= 32767) || (HK_HIDE_BAND >= 32767) || \
    (HK_DISTRACT >= 32767) || (HK_ROAR >= 32767)
#error "inc-u3dp: a hide-check TRIED key does not fit Status::Val (signed 16-bit)"
#endif

/* The two flat penalties a situation can add to a hide check. */
#define HIDE_DOOR_PENALTY   -10
#define HIDE_SNIPE_PENALTY  -20

/* How many ticks one combat round lasts. theGame->Turn advances one tick per
   play-loop iteration (src/Main.cpp:605) and one EV_TURN fires every 60 ticks
   (src/Main.cpp:587), which is what makes one Stati duration unit; the same
   60 appears in MENACE_DURATION's derivation (inc/Defines.h:134-136). */
#define HIDE_ROUND_TICKS    60
#define HIDE_ROAR_ROUNDS    3
#define HIDE_ROAR_LIFETIME  (HIDE_ROAR_ROUNDS * HIDE_ROUND_TICKS)

/* HideTrigger snapshots watchers into a fixed local array before any roll, so
   an event that deletes a creature cannot corrupt the iteration. The cap is far
   above any real line of sight. */
#define HIDE_WATCH_MAX 256

/* The roar key's Mag is a signed 16-bit Status field (Status::Mag, inc/Res.h),
   but theGame->Turn is 32-bit and already ~198000 in a fresh game, so a raw
   Turn does not fit. A key stores the round number wrapped to 15 bits instead:
   ((Turn / HIDE_ROUND_TICKS) & 0x7FFF). Two stamps compare with a 15-bit wrap,
   so a gap below 32768 rounds reads correctly; an expired stamp reads as old,
   never as live. */
int16 HideRoundStamp(void);

/* Spot check modifiers for watcher w looking for hider h: distance, darkness
   and the watcher's own sight mode, watcher-in-light, distraction and roar.
   Pure. */
int16 SpotModifiers(Creature *w, Creature *h);

/* Test seam for the probe only: the same spot sum, but with the light on the
   hider's and watcher's squares supplied literally, so the probe can drive
   exact levels the map cannot produce. Not called by the game. */
int16 HideSpotModifiersForTest(Creature *w, Creature *h, uint8 Lh, uint8 Lw);

/* Listen check modifiers for watcher w: distraction, a heard song and a roar.
   No light or sight term. Pure. */
int16 ListenModifiers(Creature *w);

/* Hider-side modifiers for hider h. Size is already inside
   SkillLevel(SK_HIDE) and is deliberately not added here. Pure. */
int16 HiderModifiers(Creature *h);

/* A carried or targeted item's size penalty. Pure. */
int16 ItemSizePenalty(Item *it);

/* The light on (x,y), 0..255, from the light map when it owns m and the
   legacy .Bright/.Lit flags otherwise. Pure. */
uint8 HideLightAt(Map *m, int16 x, int16 y);

/* The band a hide check reads from a light level: 0 dark (< LIGHT_SEE_MIN),
   1 dim (< LIGHT_HIDE_MIN), 2 bright. Pure. */
int16 HideLightBand(uint8 L);

/* Write (key, src) -> mag on c, replacing the mag in place if the pair is
   already present, so there is never more than one entry per (key, src). */
void HideSetKey(Creature *c, int16 key, Thing *src, int16 mag);
void HideClearKey(Creature *c, int16 key, Thing *src);

/* True while the HK_ROAR TRIED key is still live. Its Mag is HideRoundStamp()
   at the roar; the elapsed rounds are (HideRoundStamp() - Mag) & 0x7FFF and it
   lasts HIDE_ROAR_ROUNDS rounds. Pure. */
bool HideRoarLive(Creature *c);

/* inc-u3dp phase 2a-1: the opposed hide/spot check and its trigger loop.
   NOT yet wired into play: Perceives, Creature::Hide and every caller are
   unchanged in this run. SpotCheck is the one writer here besides the two
   Hide*Key helpers; the read-only predicates are pure. */

/* The SRD 3.5 opposed check: watcher rolls d20 + (SkillLevel(SK_SPOT) +
   SpotModifiers(w,h)), hider rolls d20 + (SkillLevel(SK_HIDE) +
   HiderModifiers(h) + hiderPenalty). Higher roll wins; on a tie the higher
   modifier wins; if the modifiers also tie, both roll again (bounded at 20
   rounds, then not spotted). Stores the verdict in the watcher's HK_SPOT_RESULT
   key and throws EV_SPOT_CHECK (ThrowVal, EActor = w, EVictim = h, result as
   the event's integer value) before returning; the throw may run scripts that
   delete either creature, so neither w nor h is touched after it. Returns
   spotted. */
bool SpotCheck(Creature *w, Creature *h, int16 hiderPenalty);

/* True only when w's HK_SPOT_RESULT key names h as its source, the key's epoch
   bits (Mag >> 1) & 0xFF equal h->HideVal & 0xFF, and the verdict bit (Mag &
   1) is set. Pure, no RNG. */
bool IsSpotted(Creature *w, Creature *h);

/* True when w can watch h at all: distinct, both placed on the same map,
   watcher awake and not blind, neither the other's leader, and visual line of
   sight within the watcher's sight range. Pure. */
bool HideCanWatch(Creature *w, Creature *h);

/* If h is HIDING, snapshot every watcher that can see it, then for each still
   live one run SpotCheck(w, h, hiderPenalty). Re-checks the world between the
   snapshot and each check, because a SpotCheck's event can delete creatures. */
void HideTrigger(Creature *h, int16 hiderPenalty);

/* inc-u3dp phase 5: a deliberate search by w for hidden creatures. Snapshot
   the handles of every HIDING creature h on w's map with HideCanWatch(w, h),
   then for each still-live one call SpotCheck(w, h, 0) -- a deliberate search is
   a normal terrain-free check with the usual modifiers, so the penalty is 0.
   Re-checks the world between the snapshot and each check, because a
   SpotCheck's event can delete w or h. */
void HideSearch(Creature *w);

/* Begin a hide: bump h->HideVal (the epoch the stored HK_SPOT_RESULT keys are
   compared against), record the current light band under HK_HIDE_BAND, and, if
   rollNow, run HideTrigger(h, 0). */
void HideStarted(Creature *h, bool rollNow);

/* inc-u3dp phase 2b: run checks when line of sight or light changes. The
   per-action hook HideTurnStart is the only entry; it checks the hider against
   watchers it can newly see and re-rolls when the hider's light band changed.
   All are writers (SpotCheck, the Hide*Key helpers). */

/* True when w's HK_SPOT_RESULT key names h as its source and its epoch bits
   ((Mag >> 1) & 0xFF) still equal h->HideVal & 0xFF -- i.e. the stored verdict
   belongs to h's current hide. Pure. */
bool HasCurrentResult(Creature *w, Creature *h);

/* One watcher against one hider. If h is not HIDING, nothing. If HideCanWatch
   (w,h): roll only when w holds no current result for h, so a watcher that
   keeps sight never re-rolls and one that loses then regains sight does. If w
   cannot watch, drop w's stale result key for h. */
void HideUpdatePair(Creature *w, Creature *h);

/* Re-check every creature that shares x's map after x's line of sight or light
   may have changed: snapshot the others' handles, then for each still-live pair
   run HideUpdatePair in both directions. Re-fetches x and the other creature
   across each SpotCheck, whose event can delete either. */
void HidePairsFor(Creature *x);

/* The per-action hook. (a) If x is HIDING and the light band on x's square
   differs from the band stored under HK_HIDE_BAND, re-stamp it and re-run the
   trigger (light changed on the hider). (b) HidePairsFor(x) (x may gain or
   regain line of sight). (c) Clear x's HK_DISTRACT key. Re-fetches x across
   every call that can delete it. */
void HideTurnStart(Creature *x);

#endif
