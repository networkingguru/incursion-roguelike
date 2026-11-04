/* inc-y2fkq: opt-in probe for the shared inventory walk cursor. Off unless
   INCURSION_INV_CURSOR_PROBE is set. Called from Game::Play (src/Main.cpp);
   graded by tools/check_inv_cursor.sh. FirstInv()/NextInv() keep their cursor
   in function-local statics (Character::GetInv, Monster::GetInv), so a walk
   begun inside another walk of the same class moves the outer cursor. Each
   case runs an outer walk, calls something that walks the same pack, and
   counts the items the outer walk visits against the count of an unnested
   walk. Output goes to errors.log through Error(), one INV_CURSOR_PROBE line
   per fact. */
#include <vector>
#include "Incursion.h"

static bool g_allPass = true;

static void Fact(const char *num, const char *what, bool ok, const char *detail) {
    Error("INV_CURSOR_PROBE: case=%s %s %s -- %s", num, what, ok ? "ok" : "BAD", detail);
    if (!ok) g_allPass = false;
}

enum Body { B_NONE, B_CALC, B_SKILL, B_HANDLER, B_LUCUB };

static rID g_sticks = 0;

struct WalkRes { int visits; int distinct; bool runaway; };

/* The handles of the last walk, in visit order; and an optional action run in
   the body of the visit numbered g_trigVisit (0-based). */
static std::vector<hObj> g_order;
static int g_trigVisit = -1;
static void (*g_hook)(Creature*) = NULL;

static void RunBody(Body b, Creature *c, Item *it) {
    switch (b) {
    case B_NONE: break;
    case B_CALC: c->CalcValues(); break;
    case B_SKILL: c->SkillLevel(SK_INTUITION); break;
    case B_HANDLER: TEFF(g_sticks)->PEvent(EV_ISTARGET, c, g_sticks); break;
    case B_LUCUB: ((Player*)c)->LucubrationPickable(it->iID); break;
    }
}

/* The outer walk. It stops after 4x the true count and says so. */
static WalkRes Walk(Creature *c, int want, Body b) {
    WalkRes r; r.visits = 0; r.distinct = 0; r.runaway = false;
    std::vector<hObj> seen;
    Item *it;
    g_order.clear();
    for (it = c->FirstInv(); it; it = c->NextInv()) {
        r.visits++;
        g_order.push_back(it->myHandle);
        bool dup = false;
        for (size_t i = 0; i < seen.size(); i++)
            if (seen[i] == it->myHandle) { dup = true; break; }
        if (!dup) { seen.push_back(it->myHandle); r.distinct++; }
        if (r.visits > 4 * want) { r.runaway = true; break; }
        RunBody(b, c, it);
        if (g_hook && r.visits - 1 == g_trigVisit) g_hook(c);
    }
    return r;
}

/* Items in a sibling chain plus everything inside containers. */
static int CountChain(Item *it) {
    int n = 0;
    for (; it; it = oItem(it->Next)) {
        n++;
        if (it->isType(T_CONTAIN))
            n += CountChain(oItem(((Container*)it)->Contents));
    }
    return n;
}

/* The player's pack counted without FirstInv/NextInv: every slot's item chain,
   two-handed weapon once (it sits in two slots). */
static int StructuralCount(Player *pl) {
    int n = 0;
    std::vector<hObj> heads;
    for (int sl = 0; sl < SL_LAST; sl++) {
        Item *s = pl->InSlot(sl);
        if (!s) continue;
        bool dup = false;
        for (size_t i = 0; i < heads.size(); i++)
            if (heads[i] == s->myHandle) dup = true;
        if (dup) continue;
        heads.push_back(s->myHandle);
        n += CountChain(s);
    }
    return n;
}

static void Grade(const char *num, const char *what, Creature *c, int want, Body b) {
    WalkRes r = Walk(c, want, b);
    char buf[200];
    snprintf(buf, sizeof buf, "visits=%d distinct=%d want=%d%s", r.visits, r.distinct,
        want, r.runaway ? " RUNAWAY(stopped at 4x)" : "");
    Fact(num, what, !r.runaway && r.visits == want && r.distinct == want, buf);
}

static Item *Make(const char *name) {
    rID r = FIND(name);
    return r ? Item::Create(r) : NULL;
}

static std::vector<hObj> g_mineH;
static hObj g_tgtX = 0, g_tgtY = 0;

static bool IsMine(hObj h) {
    for (size_t i = 0; i < g_mineH.size(); i++)
        if (g_mineH[i] == h) return true;
    return false;
}

/* A function that holds the guard, as CalcValues and the event dispatcher do,
   and whose body destroys the item the outer walk returns next. */
static void DestroyGuarded(Creature *) {
    InvCursorGuard guard;
    Item *x = (Item*)theRegistry->GetQuiet(g_tgtX);
    if (x) x->Remove(true);
}

/* Same, but the body moves the next two items to the floor. */
static void DropGuarded(Creature *c) {
    InvCursorGuard guard;
    hObj h[2] = { g_tgtX, g_tgtY };
    for (int i = 0; i < 2; i++) {
        Item *x = (Item*)theRegistry->GetQuiet(h[i]);
        if (!x) continue;
        x->Remove(false);
        x->PlaceAt(c->m, c->x, c->y);
    }
}

/* Cases 8 and 9: the same visit order as an unnested walk. */
static void GradeOrder(const char *num, const char *what, Creature *c, Body b) {
    g_hook = NULL;
    Walk(c, 1000, B_NONE);
    std::vector<hObj> base = g_order;
    WalkRes r = Walk(c, (int)base.size(), b);
    bool same = !r.runaway && g_order.size() == base.size();
    size_t firstDiff = 0;
    for (size_t i = 0; same && i < base.size(); i++)
        if (g_order[i] != base[i]) { same = false; firstDiff = i + 1; }
    char buf[200];
    snprintf(buf, sizeof buf, "visits=%d want=%d%s%s", r.visits, (int)base.size(),
        r.runaway ? " RUNAWAY(stopped at 4x)" : "",
        firstDiff ? " ORDER-DIFFERS" : (same ? " same order" : ""));
    Fact(num, what, same, buf);
}

/* Cases 7 and 7b. The outer walk's visit idx runs the hook, which removes the
   item(s) the walk returns next. The walk may end or go on, but every item it
   returns afterwards must still be in the player's pack. */
static void GradeRemoval(const char *num, const char *what, Player *pl, bool drop) {
    g_hook = NULL;
    Walk(pl, 1000, B_NONE);
    std::vector<hObj> base = g_order;
    int idx = -1;
    for (size_t i = 0; i + 1 < base.size() && idx < 0; i++) {
        if (!IsMine(base[i + 1])) continue;
        if (drop && !(i + 2 < base.size() && IsMine(base[i + 2]))) continue;
        idx = (int)i;
    }
    if (idx < 0) {
        Error("INV_CURSOR_PROBE: INCONCLUSIVE -- case %s found no consecutive loose items to remove", num);
        return;
    }
    g_tgtX = base[idx + 1];
    g_tgtY = drop ? base[idx + 2] : 0;
    Item *floorMark = Make("medium backpack");
    if (drop) {
        /* Something already on the floor, so a moved item has a chain to follow. */
        if (!floorMark) { Error("INV_CURSOR_PROBE: INCONCLUSIVE -- no floor marker"); return; }
        floorMark->PlaceAt(pl->m, pl->x, pl->y);
    }
    g_trigVisit = idx;
    g_hook = drop ? DropGuarded : DestroyGuarded;
    WalkRes r = Walk(pl, (int)base.size(), B_NONE);
    g_hook = NULL; g_trigVisit = -1;
    int bad = 0;
    for (size_t i = 0; i < g_order.size(); i++) {
        Item *x = (Item*)theRegistry->GetQuiet(g_order[i]);
        if (!x || !x->isItem() || x->Owner() != pl) bad++;
        else if (g_order[i] == g_tgtX || g_order[i] == g_tgtY) bad++;
    }
    char buf[200];
    snprintf(buf, sizeof buf, "removed at visit %d of %d; visits=%d returned-not-in-pack=%d%s",
        idx, (int)base.size(), r.visits, bad, r.runaway ? " RUNAWAY(stopped at 4x)" : "");
    Fact(num, what, !r.runaway && bad == 0, buf);
}

void InvCursorProbe(Player *pl) {
    /* inc-y2fkq: off unless INCURSION_INV_CURSOR_PROBE is set; graded by tools/check_inv_cursor.sh. */
    if (!getenv("INCURSION_INV_CURSOR_PROBE"))
        return;
    if (!pl || !pl->m) {
        Error("INV_CURSOR_PROBE: INCONCLUSIVE -- no live player and map");
        return;
    }
    const rID bookA = FIND("spellbook [Book of Glamour]");
    const rID bookB = FIND("spellbook [Book of Shadows]");
    g_sticks = FIND("Sticks to Snakes");
    const rID monID = FIND("goblin");
    if (!bookA || !bookB || !g_sticks || !monID || !FIND("small backpack") ||
        !FIND("medium backpack") || !FIND("dagger") || !FIND("silk rope") ||
        !FIND("sling stone")) {
        Error("INV_CURSOR_PROBE: INCONCLUSIVE -- missing resource");
        return;
    }

    const bool wasInPlay = theGame->PlayMode;
    theGame->PlayMode = true;
    pl->mHP = pl->cHP = 10000;

    if (!pl->InSlot(SL_PACK)) {
        Item *bp = Item::Create(FIND("medium backpack"));
        SetSilence();
        ThrowVal(EV_WIELD, SL_PACK, pl, NULL, bp);
        UnsetSilence();
    }
    Container *pack = (Container*)pl->InSlot(SL_PACK);
    if (!pack || pack->Type != T_CONTAIN) {
        Error("INV_CURSOR_PROBE: INCONCLUSIVE -- no pack container on the player");
        theGame->PlayMode = wasInPlay;
        return;
    }

    /* The player's pack: loose items, one book kind twice (once loose, once in
       a nested small backpack), and a nested container holding more items.
       Different kinds in one container so nothing stacks. */
    Item *mine[8]; int nm = 0;
    Container *nest = (Container*)Make("small backpack");
    Item *loose[4];
    loose[0] = Make("dagger");
    loose[1] = Item::Create(bookA);
    loose[2] = Item::Create(bookB);
    loose[3] = Item::Create(bookA);   /* second copy goes in the nest */
    Item *inNest[2] = { Make("silk rope"), Make("sling stone") };
    if (!nest || !loose[0] || !loose[1] || !loose[2] || !loose[3] || !inNest[0] || !inNest[1]) {
        Error("INV_CURSOR_PROBE: INCONCLUSIVE -- cannot create the test items");
        theGame->PlayMode = wasInPlay;
        return;
    }
    bool ok = pack->XInsert(nest) && pack->XInsert(loose[0]) && pack->XInsert(loose[1]) &&
        pack->XInsert(loose[2]) && nest->XInsert(loose[3]) && nest->XInsert(inNest[0]) &&
        nest->XInsert(inNest[1]);
    if (!ok) {
        Error("INV_CURSOR_PROBE: INCONCLUSIVE -- the pack refused a test item");
        theGame->PlayMode = wasInPlay;
        return;
    }
    mine[nm++] = loose[0]; mine[nm++] = loose[1]; mine[nm++] = loose[2];
    mine[nm++] = loose[3]; mine[nm++] = inNest[0]; mine[nm++] = inNest[1];
    for (int i = 0; i < nm; i++) g_mineH.push_back(mine[i]->myHandle);
    pl->CalcValues();

    /* The true count: an unnested walk, cross-checked against a count that
       does not use FirstInv/NextInv. */
    int want = 0;
    { Item *it; for (it = pl->FirstInv(); it; it = pl->NextInv()) want++; }
    const int structural = StructuralCount(pl);
    char buf[200];
    snprintf(buf, sizeof buf, "unnestedWalk=%d structural=%d", want, structural);
    Error("INV_CURSOR_PROBE: truth player pack -- %s", buf);
    if (want != structural || want < 8) {
        Error("INV_CURSOR_PROBE: INCONCLUSIVE -- unnested walk disagrees with the structure or the pack is too small (%s)", buf);
        theGame->PlayMode = wasInPlay;
        return;
    }

    Grade("1", "player pack: outer walk survives CalcValues() in the body", pl, want, B_CALC);
    Grade("2", "player pack: outer walk survives SkillLevel(SK_INTUITION) in the body", pl, want, B_SKILL);

    /* Case 3: the real handler is "Sticks to Snakes" EV_ISTARGET in
       lib/abilities.irh. It walks EActor's pack and only sets a local; it
       changes no game state. It returns at once when cFP < 0. */
    if (pl->cFP < 0) {
        Error("INV_CURSOR_PROBE: INCONCLUSIVE -- player fatigue %d < 0 makes the handler skip its walk", (int)pl->cFP);
    } else {
        Grade("3", "player pack: outer walk survives an event handler that walks the pack (Sticks to Snakes EV_ISTARGET)", pl, want, B_HANDLER);
    }

    Grade("4", "player pack, two copies of one book: outer walk survives LucubrationPickable()", pl, want, B_LUCUB);

    GradeOrder("8", "player pack: a walk with CalcValues() in the body visits the same items in the same order as an unnested walk", pl, B_CALC);
    GradeOrder("9", "player pack: a walk with LucubrationPickable() (inner walk breaks early) in the body keeps the unnested visit order", pl, B_LUCUB);

    /* Case 5: a monster's pack. */
    Map *mp = pl->m;
    int16 mx = -1, my = -1;
    static const int16 DX[4] = {1,-1,0,0}, DY[4] = {0,0,1,-1};
    for (int k = 0; k < 4 && mx < 0; ++k) {
        const int16 x = pl->x + DX[k], y = pl->y + DY[k];
        if (mp->InBounds(x, y) && !mp->SolidAt(x, y) && !mp->FCreatureAt(x, y)) { mx = x; my = y; }
    }
    if (mx < 0) {
        Error("INV_CURSOR_PROBE: INCONCLUSIVE -- no open square adjacent to the player");
    } else {
        Monster *mon = new Monster(monID);
        mon->PlaceAt(mp, mx, my, true);
        mon->Initialize(true);
        mon->mHP = mon->cHP = 10000;
        Container *mnest = (Container*)Make("small backpack");
        Item *m1 = Make("dagger"), *m2 = Make("silk rope"), *m3 = Make("sling stone");
        Item *m4 = Item::Create(bookA);
        if (!mnest || !m1 || !m2 || !m3 || !m4) {
            Error("INV_CURSOR_PROBE: INCONCLUSIVE -- cannot create the monster's items");
        } else {
            mon->GainItem(m1, true);
            mon->GainItem(m2, true);
            mon->GainItem(mnest, true);
            mnest->XInsert(m3);
            mnest->XInsert(m4);
            mon->CalcValues();
            int mwant = 0;
            { Item *it; for (it = mon->FirstInv(); it; it = mon->NextInv()) mwant++; }
            snprintf(buf, sizeof buf, "unnestedWalk=%d", mwant);
            Error("INV_CURSOR_PROBE: truth monster pack -- %s", buf);
            if (mwant < 5)
                Error("INV_CURSOR_PROBE: INCONCLUSIVE -- monster pack too small (%s)", buf);
            else
                Grade("5", "monster pack: outer walk survives CalcValues() in the body", mon, mwant, B_CALC);
        }
        mon->Remove(true);
    }

    /* Case 6: rest. Every item of mine must be intuited after the rest. An
       item that is already fully known is skipped by IntuitItem, so it is not
       a fact; count how many are eligible. */
    int eligible = 0;
    bool eligibleFlag[8];
    for (int i = 0; i < nm; i++) {
        eligibleFlag[i] = !((mine[i]->isKnown(KN_MAGIC) && mine[i]->isKnown(KN_PLUS)) ||
            (mine[i]->IFlags & IF_INTUITED));
        if (eligibleFlag[i]) eligible++;
    }
    snprintf(buf, sizeof buf, "eligible=%d of %d", eligible, nm);
    Error("INV_CURSOR_PROBE: truth rest items -- %s", buf);
    if (eligible < 4) {
        Error("INV_CURSOR_PROBE: INCONCLUSIVE -- too few unidentified items to rest on (%s)", buf);
    } else {
        const int intuitSkill = pl->SkillLevel(SK_INTUITION);
        /* A plot rest in place: no dungeon prompt, no encounter, no clock. */
        ThrowVal(EV_REST, REST_PLOT | REST_SAFE | REST_INSTANT | REST_NOMSG, pl);
        int done = 0, named = 0;
        for (int i = 0; i < nm; i++)
            if (eligibleFlag[i]) {
                if (mine[i]->IFlags & IF_INTUITED) done++;
                if (mine[i]->Inscrip.GetLength() > 0) named++;
            }
        /* Precision is d20 + skill, and under 5 it leaves no inscription, so
           the inscription is a fact only when the skill alone guarantees 5. */
        const bool inscrFact = intuitSkill >= 4;
        snprintf(buf, sizeof buf, "intuited=%d inscribed=%d of %d eligible, Intuition skill %d (inscription %s)",
            done, named, eligible, intuitSkill, inscrFact ? "is a fact" : "not a fact");
        Fact("6", "rest: intuition attempted on every unidentified item", done == eligible &&
            (!inscrFact || named == eligible), buf);
    }

    /* Case 10: the god identify aid (Character::GiveAid, case AID_IDENTIFY)
       identifies every item of the pack, container contents included. The
       probe calls GiveAid itself with a real god; it copies none of the loop. */
    {
        const char *loneNames[3] = { "dagger", "flask", "torch" };
        const char *boxNames[3]  = { "silk rope", "sling stone", "crossbow bolt" };
        Item *staged[6]; int ns = 0;
        Container *box = (Container*)Make("small backpack");
        bool ready = box && GodIDList[0] && pack->XInsert(box);
        for (int i = 0; ready && i < 3; i++) {
            Item *a = Make(loneNames[i]), *b = Make(boxNames[i]);
            if (!a || !b || !pack->XInsert(a) || !box->XInsert(b)) { ready = false; break; }
            staged[ns++] = a; staged[ns++] = b;
        }
        if (!ready) {
            Error("INV_CURSOR_PROBE: INCONCLUSIVE -- case 10 cannot stage the pack or has no god (box=%d god=%d staged=%d)",
                box != NULL, (int)(GodIDList[0] != 0), ns);
        } else {
            const uint8 AIDBITS = KN_MAGIC|KN_NATURE|KN_PLUS|KN_CURSE|KN_IDENTIFIED;
            int before = 0, after = 0;
            for (int i = 0; i < ns; i++) {
                staged[i]->SetKnown(0);
                if (staged[i]->isKnown(AIDBITS)) before++;
            }
            EventInfo e; e.Clear();
            e.EActor = pl; e.EVictim = pl;
            e.eID = GodIDList[0]; e.godNum = theGame->GodNum(e.eID);
            e.EParam = AID_IDENTIFY; e.EParam2 = T_ITEM;
            pl->GiveAid(e);
            for (int i = 0; i < ns; i++)
                if (staged[i]->isKnown(AIDBITS)) after++;
            snprintf(buf, sizeof buf, "staged=%d (3 loose: %s %s %s; 3 in a container: %s %s %s) known-before=%d known-after=%d",
                ns, loneNames[0], loneNames[1], loneNames[2], boxNames[0], boxNames[1], boxNames[2],
                before, after);
            Fact("10", "god identify aid identifies every item in the pack, container contents included", before == 0 && after == ns, buf);
        }
    }

    /* Case 11: a walk abandoned on a monster that is then removed. The monster
       cursor stays on a freed item; the next guarded call must not read it.
       A Character other than the player cannot be made here, so the Character
       cursor has no removed-owner case. */
    {
        int16 qx = -1, qy = -1;
        static const int16 EX[4] = {1,-1,0,0}, EY[4] = {0,0,1,-1};
        for (int k = 0; k < 4 && qx < 0; ++k) {
            const int16 x = pl->x + EX[k], y = pl->y + EY[k];
            if (pl->m->InBounds(x, y) && !pl->m->SolidAt(x, y) && !pl->m->FCreatureAt(x, y)) { qx = x; qy = y; }
        }
        Item *q1 = Make("dagger"), *q2 = Make("silk rope"), *q3 = Make("sling stone");
        if (qx < 0 || !q1 || !q2 || !q3) {
            Error("INV_CURSOR_PROBE: INCONCLUSIVE -- case 11 cannot stage the monster");
        } else {
            int want11 = 0;
            { Item *it; for (it = pl->FirstInv(); it; it = pl->NextInv()) want11++; }
            Error("INV_CURSOR_PROBE: mark=11-begin");
            Monster *ab = new Monster(monID);
            ab->PlaceAt(pl->m, qx, qy, true);
            ab->Initialize(true);
            ab->GainItem(q1, true);
            ab->GainItem(q2, true);
            ab->GainItem(q3, true);
            int got = 0;
            if (ab->FirstInv()) got++;
            if (ab->NextInv()) got++;
            ab->Remove(true);
            /* Stand in for the game loop's destroy-queue flush, which cannot run
               inside the probe: the monster is freed, its items stay live. */
            for (int i = 0; i < theGame->DestroyCount; i++)
                if (theGame->DestroyQueue[i] == ab) theGame->DestroyQueue[i] = NULL;
            const hObj abH = ab->myHandle;
            delete ab;
            const bool itemsLive = theRegistry->GetQuiet(q1->myHandle) != NULL;
            const bool ownerGone = theRegistry->GetQuiet(abH) == NULL;
            pl->CalcValues();
            Walk(pl, want11, B_NONE);
            const int visits11 = (int)g_order.size();
            Error("INV_CURSOR_PROBE: mark=11-end");
            snprintf(buf, sizeof buf, "abandoned-after=%d visits=%d want=%d ownerGone=%d itemLive=%d", got, visits11, want11, (int)ownerGone, (int)itemsLive);
            Fact("11", "a walk abandoned on a removed monster leaves no stale cursor; the player's walk is whole", got == 2 && ownerGone && itemsLive && visits11 == want11, buf);
        }
    }

    /* Cases 7 and 7b run last: they destroy or move items of the player's pack. */
    GradeRemoval("7", "player pack: the item the outer walk returns next is destroyed inside a guarded call", pl, false);
    GradeRemoval("7b", "player pack: the next items are dropped to the floor inside a guarded call; the walk must not follow the floor chain", pl, true);

    if (g_allPass) Error("INV_CURSOR_PROBE: PASS");
    else Error("INV_CURSOR_PROBE: FAIL -- see BAD lines above");
    theGame->PlayMode = wasInPlay;
}
