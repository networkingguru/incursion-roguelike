/* inc-b2wd: opt-in probe for the AD_SOAK rule on a lit light. Off unless
   INCURSION_SOAK_TORCH_PROBE is set. Called from Game::Play (src/Main.cpp);
   graded by tools/check_soak_torch.sh. A soak that HITS (e.isHit) never drains
   or destroys the light: a failed Reflex save (DC 10 + damage) moves the lit
   light to the pack, or to the floor when there is no pack, with its Age
   unchanged. A TERRAIN soak (isHit false) drains Age by dmg*400/Quantity and
   destroys the light at Age <= 1. Output goes to errors.log through Error(),
   one SOAK_TORCH_PROBE line per fact. */
#include "Incursion.h"

extern void LOFSetForcedSaveThrowRoll(int8 r);
extern void LOFClearForcedSaveThrowRoll();
extern void LOFSetForcedRoll(int8 r);

static bool g_allPass = true;

static void Fact(int num, const char *what, bool ok, const char *detail) {
    Error("SOAK_TORCH_PROBE: case=%d %s %s -- %s", num, what, ok ? "ok" : "BAD", detail);
    if (!ok) g_allPass = false;
}

/* Take off and delete whatever is in SL_LIGHT (TakeOff clears the slot first,
   so no dangling slot handle is left behind). */
static void DropLight(Player *pl) {
    Item *old = pl->InSlot(SL_LIGHT);
    if (!old) return;
    EventInfo t; t.Clear(); t.EActor = pl; t.EItem = old; t.EParam = SL_LIGHT;
    SetSilence();
    pl->TakeOff(t);
    UnsetSilence();
    old->Remove(true);
}

/* A fresh torch with a known Age, wielded into SL_LIGHT. Any light already in
   the slot is deleted first. NULL when the slot cannot be set up. */
static Item *LightTorch(Player *pl, int16 age) {
    DropLight(pl);
    if (pl->InSlot(SL_LIGHT))
        return NULL;
    Item *t = Item::Create(FIND("torch"));
    if (!t) return NULL;
    t->Age = age;
    SetSilence();
    ThrowVal(EV_WIELD, SL_LIGHT, pl, NULL, t);
    UnsetSilence();
    if (pl->InSlot(SL_LIGHT) != t) return NULL;
    t->Age = age;
    pl->CalcValues();
    return t;
}

/* The event a creature's landed attack throws: AD_SOAK with isHit true. */
static void HitSoak(Creature *actor, Player *pl, int dmg) {
    EventInfo ev; ev.Clear();
    ev.EActor = actor;
    ev.EVictim = pl;
    ev.DType = AD_SOAK;
    ev.vDmg = dmg;
    ev.isHit = true;
    ReThrow(EV_DAMAGE, ev);
}

/* Remove(true) marks an item deleted (isDead) and reaps it later, so a handle
   that still resolves is not proof the item lives. */
static bool Alive(hObj h) {
    return theRegistry->Exists(h) && !oItem(h)->isDead();
}

static bool InPack(Player *pl, Item *t) {
    Item *pack = pl->InSlot(SL_PACK);
    return pack && t->GetParent() == pack;
}

static bool OnPlayerSquare(Player *pl, Item *t) {
    return t->m == pl->m && t->x == pl->x && t->y == pl->y;
}

void SoakTorchProbe(Player *pl) {
    /* inc-b2wd: opt-in hook for tools/check_soak_torch.sh. */
    if (!getenv("INCURSION_SOAK_TORCH_PROBE"))
        return;
    if (!pl || !pl->m) {
        Error("SOAK_TORCH_PROBE: INCONCLUSIVE -- no live player and map");
        return;
    }
    const rID elemID = FIND("tiny water elemental");
    if (!elemID || !FIND("torch") || !FIND("medium backpack")) {
        Error("SOAK_TORCH_PROBE: INCONCLUSIVE -- missing resource");
        return;
    }
    static const int16 DX[4] = {1,-1,0,0}, DY[4] = {0,0,1,-1};
    Map *mp = pl->m;
    int dir = -1;
    for (int k = 0; k < 4 && dir < 0; ++k) {
        const int16 x = pl->x + DX[k], y = pl->y + DY[k];
        if (mp->InBounds(x, y) && !mp->SolidAt(x, y) && !mp->FCreatureAt(x, y))
            dir = k;
    }
    if (dir < 0) {
        Error("SOAK_TORCH_PROBE: INCONCLUSIVE -- no open square adjacent to the player");
        return;
    }

    const bool wasInPlay = theGame->PlayMode;
    theGame->PlayMode = true;
    pl->mHP = pl->cHP = 10000;

    /* The pack: the fixture carries one; make one when it does not. */
    if (!pl->InSlot(SL_PACK)) {
        Item *bp = Item::Create(FIND("medium backpack"));
        SetSilence();
        ThrowVal(EV_WIELD, SL_PACK, pl, NULL, bp);
        UnsetSilence();
    }
    Item *pack = pl->InSlot(SL_PACK);
    if (!pack || pack->Type != T_CONTAIN) {
        Error("SOAK_TORCH_PROBE: INCONCLUSIVE -- no pack container on the player");
        theGame->PlayMode = wasInPlay;
        return;
    }

    /* The attacker: a tiny water elemental beside the player. */
    mp->At(pl->x + DX[dir], pl->y + DY[dir]).Lit = 1;
    Monster *elem = new Monster(elemID);
    TMON(elem->tmID)->GrantGear(elem, elem->tmID, true);
    TMON(elem->tmID)->PEvent(EV_BIRTH, elem, elem->tmID);
    elem->PlaceAt(mp, pl->x + DX[dir], pl->y + DY[dir], true);
    elem->Initialize(true);
    elem->mHP = elem->cHP = 10000;
    elem->ts.addCreatureTarget(pl, TargetEnemy);
    pl->ts.addCreatureTarget(elem, TargetEnemy);

    char buf[160];
    const int16 AGE = 2500;
    Item *t;

    /* Case 1: hit soak, save fails, pack present. */
    t = LightTorch(pl, AGE);
    if (!t) { Error("SOAK_TORCH_PROBE: INCONCLUSIVE -- cannot light a torch"); goto Done; }
    {
        const int lr0 = pl->LightRange;
        LOFSetForcedSaveThrowRoll(1);
        HitSoak(elem, pl, 3);
        LOFClearForcedSaveThrowRoll();
        pl->CalcValues();
        snprintf(buf, sizeof buf, "inSlot=%d inPack=%d age=%d want=%d lightRange %d->%d",
            pl->InSlot(SL_LIGHT) == t, InPack(pl, t), t->Age, AGE, lr0, (int)pl->LightRange);
        Fact(1, "failed save moves the lit torch into the pack, Age unchanged",
            pl->InSlot(SL_LIGHT) != t && InPack(pl, t) && t->Age == AGE &&
            (int)pl->LightRange < lr0, buf);
    }

    /* Case 5: re-light that torch (one action), against a normal wield. */
    {
        /* The inventory takes the item out of the pack before it wields it
           (Inv.cpp, via SL_INAIR); do the same, so no dead handle stays in
           the pack's contents. */
        t->Remove(false);
        const int16 t0 = pl->Timeout;
        SetSilence();
        ThrowVal(EV_WIELD, SL_LIGHT, pl, NULL, t);
        UnsetSilence();
        const int relightCost = pl->Timeout - t0;
        const bool relit = pl->InSlot(SL_LIGHT) == t;
        const int ageAfter = t->Age;
        /* Baseline: an ordinary wield of a different light into an empty slot. */
        DropLight(pl);
        Item *t2 = Item::Create(FIND("torch"));
        const int16 b0 = pl->Timeout;
        SetSilence();
        ThrowVal(EV_WIELD, SL_LIGHT, pl, NULL, t2);
        UnsetSilence();
        const int baseCost = pl->Timeout - b0;
        snprintf(buf, sizeof buf, "relit=%d age=%d relightCost=%d normalWieldCost=%d",
            relit, ageAfter, relightCost, baseCost);
        Fact(5, "re-lighting the dropped torch costs one wield action", relit &&
            ageAfter == AGE && relightCost > 0 && relightCost == baseCost, buf);
    }

    /* Case 3: hit soak, save succeeds. */
    t = LightTorch(pl, AGE);
    if (!t) { Error("SOAK_TORCH_PROBE: INCONCLUSIVE -- cannot light a torch"); goto Done; }
    LOFSetForcedSaveThrowRoll(20);
    HitSoak(elem, pl, 3);
    LOFClearForcedSaveThrowRoll();
    snprintf(buf, sizeof buf, "inSlot=%d age=%d want=%d", pl->InSlot(SL_LIGHT) == t, t->Age, AGE);
    Fact(3, "passed save leaves the torch lit, Age unchanged",
        pl->InSlot(SL_LIGHT) == t && t->Age == AGE, buf);

    /* Case 4: the DC is 10 + damage. With Reflex bonus B and damage D the
       save succeeds on roll R exactly when B + R >= 10 + D. D = max(1, B)
       puts R at 10 (or 11 - B when B < 1); roll R passes, roll R-1 fails. */
    {
        const int bonus = ((Creature*)pl)->SaveBonus(REF, 0);
        const int dmg = bonus > 1 ? bonus : 1;
        const int rStar = 10 + dmg - bonus;
        if (rStar - 1 < 2 || rStar > 19) {
            Error("SOAK_TORCH_PROBE: INCONCLUSIVE -- Reflex bonus %d puts the boundary roll at %d", bonus, rStar);
            goto Done;
        }
        t = LightTorch(pl, AGE);
        if (!t) { Error("SOAK_TORCH_PROBE: INCONCLUSIVE -- cannot light a torch"); goto Done; }
        LOFSetForcedSaveThrowRoll((int8)rStar);
        HitSoak(elem, pl, dmg);
        LOFClearForcedSaveThrowRoll();
        const bool heldAtDC = pl->InSlot(SL_LIGHT) == t;
        LOFSetForcedSaveThrowRoll((int8)(rStar - 1));
        HitSoak(elem, pl, dmg);
        LOFClearForcedSaveThrowRoll();
        const bool lostBelowDC = pl->InSlot(SL_LIGHT) != t;
        snprintf(buf, sizeof buf, "reflexBonus=%d dmg=%d DC=%d roll %d saves=%d roll %d fails=%d",
            bonus, dmg, 10 + dmg, rStar, heldAtDC, rStar - 1, lostBelowDC);
        Fact(4, "save DC is 10 + damage", heldAtDC && lostBelowDC, buf);
    }

    /* Case 6: a 10d6-sized hit soak (A_CRUS rider), save fails: torch lives. */
    t = LightTorch(pl, AGE);
    if (!t) { Error("SOAK_TORCH_PROBE: INCONCLUSIVE -- cannot light a torch"); goto Done; }
    {
        const hObj h = t->myHandle;
        LOFSetForcedSaveThrowRoll(1);
        HitSoak(elem, pl, 35);
        LOFClearForcedSaveThrowRoll();
        const bool exists = Alive(h);
        snprintf(buf, sizeof buf, "exists=%d inPack=%d age=%d want=%d", exists,
            exists && InPack(pl, t), exists ? t->Age : -1, AGE);
        Fact(6, "a 35-point hit soak never destroys the torch", exists &&
            InPack(pl, t) && t->Age == AGE, buf);
    }

    /* Case 8: the real path. The elemental's own slam, forced to land, with
       its AD_SOAK rider; the save is forced to fail. */
    t = LightTorch(pl, AGE);
    if (!t) { Error("SOAK_TORCH_PROBE: INCONCLUSIVE -- cannot light a torch"); goto Done; }
    {
        const hObj h = t->myHandle;
        LOFSetForcedRoll(20);
        LOFSetForcedSaveThrowRoll(1);
        Throw(EV_NATTACK, elem, pl);
        LOFClearForcedSaveThrowRoll();
        LOFSetForcedRoll(0);
        const bool exists = Alive(h);
        snprintf(buf, sizeof buf, "exists=%d inSlot=%d inPack=%d age=%d want=%d", exists,
            exists && pl->InSlot(SL_LIGHT) == t, exists && InPack(pl, t),
            exists ? t->Age : -1, AGE);
        Fact(8, "elemental slam rider (real attack path) moves the torch, Age unchanged",
            exists && pl->InSlot(SL_LIGHT) != t && InPack(pl, t) && t->Age == AGE, buf);
    }

    /* Case 7: terrain soak (isHit false), as a fountain throws it. */
    t = LightTorch(pl, AGE);
    if (!t) { Error("SOAK_TORCH_PROBE: INCONCLUSIVE -- cannot light a torch"); goto Done; }
    {
        const hObj h = t->myHandle;
        ThrowDmg(EV_DAMAGE, AD_SOAK, 3, "soak probe", pl, pl);
        const int want = AGE - (3 * 400) / 1;
        const bool exists = Alive(h);
        const int age1 = exists ? t->Age : -1;
        const bool lit1 = exists && pl->InSlot(SL_LIGHT) == t;
        snprintf(buf, sizeof buf, "exists=%d inSlot=%d age=%d want=%d", exists, lit1, age1, want);
        Fact(7, "terrain soak drains Age by dmg*400/Quantity", exists && lit1 && age1 == want, buf);
        ThrowDmg(EV_DAMAGE, AD_SOAK, 10, "soak probe", pl, pl);
        const bool gone = !Alive(h);
        snprintf(buf, sizeof buf, "destroyed=%d", gone);
        Fact(7, "terrain soak past Age 1 destroys the torch", gone, buf);
    }

    /* Case 2: hit soak, save fails, NO pack: the torch lands on the player's
       square. Last, because it takes the pack off. */
    t = LightTorch(pl, AGE);
    if (!t) { Error("SOAK_TORCH_PROBE: INCONCLUSIVE -- cannot light a torch"); goto Done; }
    pack->Remove(false);
    if (pl->InSlot(SL_PACK)) {
        Error("SOAK_TORCH_PROBE: INCONCLUSIVE -- cannot take the pack off");
        goto Done;
    }
    {
        const hObj h = t->myHandle;
        LOFSetForcedSaveThrowRoll(1);
        HitSoak(elem, pl, 3);
        LOFClearForcedSaveThrowRoll();
        const bool exists = Alive(h);
        snprintf(buf, sizeof buf, "exists=%d inSlot=%d onSquare=%d age=%d want=%d", exists,
            exists && pl->InSlot(SL_LIGHT) == t, exists && OnPlayerSquare(pl, t),
            exists ? t->Age : -1, AGE);
        Fact(2, "no pack: failed save drops the torch on the player's square, Age unchanged",
            exists && pl->InSlot(SL_LIGHT) != t && OnPlayerSquare(pl, t) && t->Age == AGE, buf);
    }

    if (g_allPass) Error("SOAK_TORCH_PROBE: PASS");
    else Error("SOAK_TORCH_PROBE: FAIL -- see BAD lines above");

Done:
    LOFClearForcedSaveThrowRoll();
    LOFSetForcedRoll(0);
    elem->Remove(true);
    theGame->PlayMode = wasInPlay;
}
