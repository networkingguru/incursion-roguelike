/* inc-59lq phase A1: concentration core for maintained spells.

   A caster that casts one of the listed spells gains a CONCENTRATING status.
   Stopping concentration -- from the Cancel menu, or when the status reaches
   its cap -- shortens or ends the spell's effects:

     Phantasmal Force        cap e.vDuration           tail 0
     Improved Phantasmal F.  cap e.vDuration           tail 1 unit
     Spectral Force          cap e.vDuration           tail 2 units
     Improved Spectral F.    cap e.vDuration           tail 2 units
     Advanced Illusion       cap e.vDuration           tail 2 units
     Hypnotic Pattern        cap e.vDuration           tail 1 unit
     Telekinesis             cap max(1,clev/2) units   tail 0
     Wall of Fire            cap e.vDuration           tail max(1,clev/2) units

   Tail 0 ends the spell's effects at once; tail N sets each effect to last
   min(its remaining duration, N). Reaching the cap ends the effects at once
   with no tail. If every effect is already gone, concentration stops with no
   further effect.

   Off unless INCURSION_CONCENT_PROBE is set: one errors.log line per event,
   read the same way the other *_PROBE hooks write theirs.

   This phase does not block casts/attacks, does not run the damage check, and
   does not touch monster behaviour. */

#include "Incursion.h"

static int ConcentProbeOn(void) {
    return getenv("INCURSION_CONCENT_PROBE") ? 1 : 0;
}

/* Matching is by resource name. CapKind names whether the cap is the spell's
   own duration or casterLevel/2 (tri units), the latter floored at 1. */
typedef struct {
    const char *name;
    int8 capCasterLev;   /* 1: cap = max(1, clev/2); 0: cap = e.vDuration */
    int16 tail;          /* tail units after a stop */
} ConcentSpell;

static const ConcentSpell ConcentTable[] = {
    { "Phantasmal Force",        0, 0 },
    { "Improved Phantasmal Force", 0, 1 },
    { "Spectral Force",          0, 2 },
    { "Improved Spectral Force", 0, 2 },
    { "Advanced Illusion",       0, 2 },
    { "Hypnotic Pattern",        0, 1 },
    { "Telekinesis",             1, 0 },
    { "Wall of Fire",            0, 0 }, /* tail overridden to clev/2 below */
    { NULL, 0, 0 }
};

static const ConcentSpell *ConcentLookup(rID eID) {
    int i;
    if (!eID) return NULL;
    /* GetName returns a String by value; NAME() casts it to const char* and
       the buffer dies at the end of the full expression, so hold it. */
    String nm = RES(eID)->GetName(0);
    for (i = 0; ConcentTable[i].name; i++)
        if (!strcmp(ConcentTable[i].name, (const char*)nm))
            return &ConcentTable[i];
    return NULL;
}

/* Wall of Fire's tail, and Telekinesis' cap, scale with caster level. */
static int16 ConcentTailUnits(const ConcentSpell *cs, int16 clev) {
    if (!strcmp(cs->name, "Wall of Fire"))
        return (int16)max(1, clev / 2);
    return cs->tail;
}

/* inc-59lq phase D: the concentration help line shown in a spell's help
   beside the duration line. Empty for spells not in the table. One duration
   unit is 2 rounds, so a fixed tail of N units reads "2*N rounds". Wall of
   Fire's tail scales with caster level, and Telekinesis' cap does too. */
String ConcentHelpLine(rID eID) {
    const ConcentSpell *cs;
    String s;

    cs = ConcentLookup(eID);
    if (!cs)
        return s;

    if (!strcmp(cs->name, "Wall of Fire"))
        s = "Requires concentration; lasts 1 round per caster level after concentration ends. ";
    else if (cs->tail == 0)
        s = "Requires concentration; ends when concentration ends. ";
    else
        s = Format("Requires concentration; lasts %d rounds after concentration ends. ",
            cs->tail * 2);

    if (!strcmp(cs->name, "Telekinesis"))
        s += "Concentration lasts at most 1 round per caster level. ";

    return s;
}

static int16 ConcentCapUnits(const ConcentSpell *cs, EventInfo &e) {
    if (cs->capCasterLev)
        return (int16)max(1, e.vCasterLev / 2);
    return e.vDuration;
}

/* Does the caster currently hold any effect of this spell? Illusion objects
   and victims are found among the caster's backRefs (their ILLUSION/PARALYSIS
   stati name the caster as object), status rows with the spell's eID on the
   caster cover Telekinesis and the illusion link stati, and the map's
   TerraList covers Wall of Fire. */
static bool ConcentSpellHasEffects(Creature *c, rID eID) {
    int32 i;
    Thing *t;

    if (c->HasEffStati(-1, eID))
        return true;

    for (i = 0; c->backRefs[i]; i++) {
        if (!theRegistry->Exists(c->backRefs[i]))
            continue;
        t = oThing(c->backRefs[i]);
        if (t->HasEffStati(-1, eID))
            return true;
    }

    if (c->m)
        for (i = 0; i < c->m->TerraList.Total(); i++)
            if (c->m->TerraList[i]->eID == eID &&
                c->m->TerraList[i]->Creator == c->myHandle)
                return true;

    return false;
}

/* Shorten (tail > 0) or end (tail == 0) one effect holder's rows that carry
   the spell's eID. Illusion objects are removed outright at tail 0. */
static void ConcentApplyToThing(Creature *caster, Thing *t, rID eID, int16 tail) {
    if (!t || t->Flags & F_DELETE)
        return;

    if (t->isIllusion() && t->GetStatiObj(ILLUSION) == caster) {
        if (tail == 0) {
            t->Remove(true);
            return;
        }
        StatiIter(t)
            if (S->eID == eID && S->Nature == ILLUSION &&
                S->Duration > 0 && S->Duration > tail)
                S->Duration = tail;
        StatiIterEnd(t)
        return;
    }

    if (tail == 0) {
        /* butNotNature == CONCENTRATING: the concentration status itself is
           the caller's to clear (Cancel menu removes it; the cap expiry path
           is removed by StatiIter_ElapseCurrent). */
        t->RemoveEffStati(eID, EV_REMOVED, CONCENTRATING);
        return;
    }

    StatiIter(t)
        if (S->eID == eID && S->Nature != INNATE_SPELL &&
            S->Nature != CONCENTRATING &&
            S->Duration > 0 && S->Duration > tail)
            S->Duration = tail;
    StatiIterEnd(t)
}

/* The shared helper: shorten or end all four effect kinds of the spell. */
void Creature::ConcentrationEndEffects(rID eID, int16 tail) {
    int32 i, j;
    Thing *t;

    /* The caster's own rows (Telekinesis' TELEKINETIC, illusion link stati,
       and any other row the spell put on us). */
    ConcentApplyToThing(this, this, eID, tail);

    /* Things that name us as their object: illusory creatures/items and the
       victims of Hypnotic Pattern's PARALYSIS. */
    for (i = 0; backRefs[i]; i++) {
        if (!theRegistry->Exists(backRefs[i]))
            continue;
        t = oThing(backRefs[i]);
        if (t == this)
            continue;
        if (!t->HasEffStati(-1, eID))
            continue;
        ConcentApplyToThing(this, t, eID, tail);
    }

    /* Wall of Fire: the map's terraform records created by us.
       inc-59lq phase A2 Part 3b: collect the matching keys first, then act on
       each once. The old form restarted the scan with a goto after every
       RemoveTerra, which would never terminate if RemoveTerra ever left a
       matching record behind. This form ends unconditionally: the key list is
       fixed before any removal, so each key is visited exactly once. Entry
       Total() bounds the number of matches, since removals only shrink the
       list. */
    if (m) {
        int32 total = m->TerraList.Total();
        int16 *keys;
        int32 nKeys = 0, k;

        keys = (int16*) malloc(sizeof(int16) * (total > 0 ? total : 1));
        if (keys) {
            for (j = 0; j < total; j++)
                if (m->TerraList[j]->eID == eID &&
                    m->TerraList[j]->Creator == myHandle) {
                    int16 key = m->TerraList[j]->key;
                    bool dup = false;
                    for (k = 0; k < nKeys; k++)
                        if (keys[k] == key) { dup = true; break; }
                    if (!dup)
                        keys[nKeys++] = key;
                }

            for (k = 0; k < nKeys; k++) {
                if (tail == 0) {
                    m->RemoveTerra(keys[k]);
                } else {
                    for (j = 0; j < m->TerraList.Total(); j++)
                        if (m->TerraList[j]->key == keys[k] &&
                            m->TerraList[j]->eID == eID &&
                            m->TerraList[j]->Creator == myHandle)
                            if (m->TerraList[j]->Duration > 0 &&
                                m->TerraList[j]->Duration > tail)
                                m->TerraList[j]->Duration = tail;
                }
            }
            free(keys);
        }
    }
}

/* Called from Creature::Cast after the spell's effect has resolved. Grants
   CONCENTRATING for a listed spell whose effect now exists. A prior
   concentration on the same spell is replaced. */
void Creature::StartConcentration(EventInfo &e) {
    const ConcentSpell *cs;
    int16 cap, tail;
    rID eID = e.eID;

    cs = ConcentLookup(eID);
    if (!cs)
        return;

    if (!ConcentSpellHasEffects(this, eID))
        return;

    cap = ConcentCapUnits(cs, e);
    tail = ConcentTailUnits(cs, e.vCasterLev);
    if (cap <= 0)
        return;

    /* If we were already concentrating on this spell, replace the old row;
       the effect now holds the freshest durations, so no tail is applied. */
    if (HasStati(CONCENTRATING, -1, NULL)) {
        StatiIterNature(this, CONCENTRATING)
            if (S->eID == eID)
                StatiIter_RemoveCurrent(this);
        StatiIterEnd(this)
    }

    GainTempStati(CONCENTRATING, NULL, cap, SS_ENCH, tail, 0, eID, e.vCasterLev);

    if (ConcentProbeOn())
        Error("CONCENT start spell=%s cap=%d tail=%d", NAME(eID),
            (int)cap, (int)tail);
}

/* Stop concentrating on a spell. tail (the units stored on the status) is
   applied to the spell's effects, then the CONCENTRATING row is removed. */
void Creature::StopConcentration(rID eID, bool applyTail) {
    const ConcentSpell *cs;
    int16 tail = 0;

    cs = ConcentLookup(eID);
    if (!cs)
        return;

    if (HasStati(CONCENTRATING, -1, NULL)) {
        StatiIterNature(this, CONCENTRATING)
            if (S->eID == eID)
                tail = S->Val;
        StatiIterEnd(this)
        if (!applyTail)
            tail = 0;

        /* If nothing of the spell is left (illusion killed, victims
           recovered), the concentration simply ends. */
        if (!ConcentSpellHasEffects(this, eID)) {
            if (ConcentProbeOn())
                Error("CONCENT stop spell=%s reason=gone tail=0", NAME(eID));
        } else {
            ConcentrationEndEffects(eID, tail);

            if (ConcentProbeOn())
                Error("CONCENT stop spell=%s reason=%s tail=%d", NAME(eID),
                    applyTail ? "cancel" : "cap", (int)tail);
        }

        StatiIterNature(this, CONCENTRATING)
            if (S->eID == eID)
                StatiIter_RemoveCurrent(this);
        StatiIterEnd(this)
    }
}

/* Cap expiry: the status ran out its own duration. No tail. The expiring row
   is removed by the caller's StatiIter_ElapseCurrent, which also reaps the
   caster's remaining rows of this eID; here we only end the off-caster
   effects (illusions, victims, terrain) at once. */
void Creature::ConcentrationExpired(rID eID) {
    const ConcentSpell *cs;

    cs = ConcentLookup(eID);
    if (!cs)
        return;

    if (HasStati(CONCENTRATING, -1, NULL)) {
        if (ConcentSpellHasEffects(this, eID))
            ConcentrationEndEffects(eID, 0);

        if (ConcentProbeOn())
            Error("CONCENT stop spell=%s reason=cap tail=0", NAME(eID));
    }
}

/* inc-59lq phase A2 Part 1: a concentrating creature cannot start another
   action that needs its attention. Called from Creature::Event for cast,
   invoke and the five attack events, and from the item handlers for read,
   zap and activate. Returns true (and refuses) when a CONCENTRATING row is
   present; the player is told which spell they hold. Monsters get no message
   but are still refused. */
bool Creature::ConcentrationBlocks(const char *kind) {
    rID eID;
    if (!HasStati(CONCENTRATING, -1, NULL))
        return false;
    eID = GetStatiEID(CONCENTRATING, -1, NULL);
    if (isPlayer())
        IPrint(Format("You cannot do that while concentrating on %s.",
            eID ? (const char*)NAME(eID) : "a spell"));
    if (ConcentProbeOn())
        Error("CONCENT block event=%s spell=%s", kind, eID ? NAME(eID) : "?");
    return true;
}

/* inc-59lq phase A2 Part 2: damage taken while concentrating forces a
   Concentration check. DC = 10 + damage + the spell's level. Hooking the
   POST(EV_DAMAGE) step guarantees one roll per wound: a converted damage
   type is re-delivered as EV_DAMAGE and its POST step runs, and the outer
   event's POST is then skipped (src/Event.cpp DmgPostDelivered, inc-e5ke).
   The amount used is e.aDmg, the damage actually taken, final by the time
   the POST step runs. */
void Creature::ConcentrationDamageCheck(int16 dmg) {
    const ConcentSpell *cs;
    rID eID;
    int dc;
    bool pass;

    if (dmg <= 0)
        return;
    if (!HasStati(CONCENTRATING, -1, NULL))
        return;
    eID = GetStatiEID(CONCENTRATING, -1, NULL);
    cs = ConcentLookup(eID);
    if (!cs)
        return;

    dc = 10 + dmg + (eID ? TEFF(eID)->Level : 0);
    pass = SkillCheck(SK_CONCENT, dc, true);

    if (pass) {
        if (isPlayer())
            IPrint("You maintain your concentration.");
    } else {
        if (isPlayer())
            IPrint(Format("You lose your concentration on %s!",
                (const char*)NAME(eID)));
        StopConcentration(eID, true);
    }

    if (ConcentProbeOn())
        Error("CONCENT check spell=%s dc=%d result=%s", NAME(eID), dc,
            pass ? "pass" : "fail");
}

/* inc-59lq phase C: does the concentrated spell S still reach an enemy?
   Used by Monster::ChooseAction to decide whether a concentrating monster
   keeps concentrating or lets the spell go. Per-spell tests:

     Hypnotic Pattern  a creature hostile to us carries a stati whose eID is S
                       (the PARALYSIS the pattern laid on its victims).
     Wall of Fire      a creature hostile to us stands on, or is adjacent to,
                       a tile whose TerraRecord is our own (eID S, Creator us).
     Telekinesis       a creature hostile to us that we perceive lies within
                       our TELEKINETIC range.
     all other table   a creature hostile to us perceives one of our illusion
     spells            objects whose ILLUSION stati names us and carries eID S.

   The illusion branch reuses the caster's backRefs walk from
   ConcentSpellHasEffects, adding the "a hostile creature perceives it" test. */
bool Creature::ConcentrationStillAffectsEnemy(rID eID) {
    const char *nm;
    String nmHold;
    Creature *c;
    int32 i, j2;

    if (!eID)
        return false;
    nmHold = RES(eID)->GetName(0);   /* held: NAME() would dangle */
    nm = (const char*)nmHold;

    if (!strcmp(nm, "Hypnotic Pattern")) {
        if (!m)
            return false;
        MapIterate(m, c, i) {
            if (!c->isCreature() || c == this)
                continue;
            if (!isHostileTo(c))
                continue;
            if (c->HasEffStati(-1, eID))
                return true;
        }
        return false;
    }

    if (!strcmp(nm, "Wall of Fire")) {
        if (!m)
            return false;
        /* For every terra tile that is ours (eID S, Creator us), test the
           hostile creatures standing on it or next to it. Walking the
           TerraXY grid, matching each occupied square against TerraList by
           key, is the same walk RemoveTerra uses. */
        {
            int32 t, j;
            int16 total = m->TerraList.Total();
            for (t = 0; t < total; t++) {
                if (m->TerraList[t]->eID != eID ||
                    m->TerraList[t]->Creator != myHandle)
                    continue;
                for (j = 0; j < m->TerraXY.Total(); j++) {
                    if (m->TerraXY[j]->key != m->TerraList[t]->key)
                        continue;
                    {
                        int16 tx = m->TerraXY[j]->x, ty = m->TerraXY[j]->y;
                        MapIterate(m, c, i) {
                            if (!c->isCreature() || c == this)
                                continue;
                            if (!isHostileTo(c))
                                continue;
                            if (dist(c->x, c->y, tx, ty) <= 1)
                                return true;
                        }
                    }
                }
            }
        }
        return false;
    }

    if (!strcmp(nm, "Telekinesis")) {
        if (!m || !HasStati(TELEKINETIC))
            return false;
        MapIterate(m, c, i) {
            if (!c->isCreature() || c == this)
                continue;
            if (!isHostileTo(c))
                continue;
            if (!Perceives(c))
                continue;
            if (dist(x, y, c->x, c->y) <= HighStatiMag(TELEKINETIC))
                return true;
        }
        return false;
    }

    /* Illusions (Phantasmal Force through Advanced Illusion): an illusion
       object that names us as its ILLUSION object and carries eID S, seen by
       some creature hostile to us. */
    if (!m)
        return false;
    for (i = 0; backRefs[i]; i++) {
        Thing *il;
        bool namesUs = false;
        if (!theRegistry->Exists(backRefs[i]))
            continue;
        il = oThing(backRefs[i]);
        if (!il->isIllusion())
            continue;

        StatiIter(il)
            if (S->eID == eID && S->Nature == ILLUSION &&
                il->GetStatiObj(ILLUSION) == this)
                namesUs = true;
        StatiIterEnd(il)
        if (!namesUs)
            continue;

        MapIterate(m, c, j2) {
            if (!c->isCreature() || c == this)
                continue;
            if (!isHostileTo(c))
                continue;
            if (c->Perceives(il))
                return true;
        }
    }
    return false;
}
