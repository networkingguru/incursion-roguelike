/* inc-w6t0: opt-in Stone to Flesh reproduction (INCURSION_STONE_FLESH_PROBE
   = "spell" or "potion"). Caller: Game::Play (src/Main.cpp). Reader:
   tools/check_stone_to_flesh.sh. The player gets STONING, then the spell is
   cast on self through EV_EFFECT, or the potion is drunk through EV_DRINK. */
#include "Incursion.h"

static void StoneToFleshStatueSetup(Player *p);

/* Statue scene (INCURSION_STONE_FLESH_PROBE=statue). The setup puts one statue
   east of the player; INCURSION_STONE_FLESH_STATUE names its monster type, or
   "untyped" leaves it without one. The player then casts Stone to Flesh with
   the real keys. StoneToFleshPoll (Game::Play, once per round) reports the
   first round after the statue is gone. */
static Map *sfMap = NULL;
static int sfX = 0, sfY = 0, sfDone = 0;
static rID sfWant = 0;
static bool sfTyped = false;
static Creature *sfCre = NULL; /* "stoned-<name>": a creature target, not a statue */
static hObj sfCreH = 0;
static int16 sfCreHP = 0;

/* Weapons in a creature's pack (goblin gear always holds exactly one) and its
   INNATE_SPELL stati (only the blue goblin's EV_BIRTH grants them). */
static int sfWeapons(Creature *c) {
    int n = 0;
    for (Item *it = c->FirstInv(); it; it = c->NextInv())
        if (it->isType(T_WEAPON)) n++;
    return n;
}

static int sfCount(Map *m, int x, int y, int type, rID *last) {
    int n = 0;
    for (Thing *t = m->FirstAt(x, y); t; t = m->NextAt(x, y))
        if (t->isItem() && t->isType(type)) { n++; if (last) *last = ((Item*)t)->GetCorpseType(); }
    return n;
}

static void StoneToFleshStatueSetup(Player *p) {
    const char *name = getenv("INCURSION_STONE_FLESH_STATUE");
    if (!name || !p || !p->m || !FIND("statue")) {
        Error("STONE_FLESH INCONCLUSIVE statue setup"); return; }
    if (!strncmp(name, "stoned-", 7)) { /* a petrifying goblin east of the player */
        rID mon = FIND(name + 7);
        int cx = p->x + 1, cy = p->y;
        if (!mon || p->m->SolidAt(cx, cy) || p->m->FCreatureAt(cx, cy)) {
            Error("STONE_FLESH INCONCLUSIVE creature setup"); return; }
        Monster *g = new Monster(mon);
        g->PlaceAt(p->m, cx, cy);
        g->Initialize();
        g->GainTempStati(STONING, NULL, 50, SS_MISC);
        sfMap = p->m; sfX = cx; sfY = cy; sfCre = g; sfCreH = g->myHandle; sfCreHP = g->cHP;
        Error("STONE_FLESH_CRE_BEFORE type=%s stoning=%d hp=%d", (const char*)NAME(mon),
            g->HasStati(STONING) ? 1 : 0, (int)g->cHP);
        return;
    }
    sfTyped = strcmp(name, "untyped") != 0;
    sfWant = sfTyped ? FIND(name) : 0;
    if (sfTyped && !sfWant) { Error("STONE_FLESH INCONCLUSIVE no monster %s", name); return; }
    int x = p->x + 1, y = p->y;
    if (p->m->SolidAt(x, y) || p->m->FCreatureAt(x, y)) {
        Error("STONE_FLESH INCONCLUSIVE east square not free"); return; }
    Item *st = Item::Create(FIND("statue"));
    if (sfTyped) ((Corpse*)st)->SetCorpseType(sfWant);
    st->PlaceAt(p->m, x, y);
    sfMap = p->m; sfX = x; sfY = y;
    Error("STONE_FLESH_BEFORE kind=%s statues=%d creature=none corpses=%d",
        sfTyped ? "typed" : "untyped", sfCount(sfMap, x, y, T_STATUE, NULL),
        sfCount(sfMap, x, y, T_CORPSE, NULL));
}

void StoneToFleshPoll(Player *p) {
    if (!sfMap || sfDone || p->m != sfMap) return;
    if (sfCre) {
        if (!theRegistry->Exists(sfCreH) || !sfCre->HasStati(STONING)) {
            sfDone = 1;
            bool here = theRegistry->Exists(sfCreH) && sfMap->FCreatureAt(sfX, sfY) == sfCre;
            Error("STONE_FLESH_CRE_AFTER same_creature=%d stoning=%d hp=%d hp_before=%d statues=%d",
                here ? 1 : 0, here && sfCre->HasStati(STONING) ? 1 : 0, here ? (int)sfCre->cHP : -1,
                (int)sfCreHP, sfCount(sfMap, sfX, sfY, T_STATUE, NULL));
        }
        return;
    }
    if (sfCount(sfMap, sfX, sfY, T_STATUE, NULL)) return;
    sfDone = 1;
    Creature *c = sfMap->FCreatureAt(sfX, sfY);
    rID corpseType = 0;
    int corpses = sfCount(sfMap, sfX, sfY, T_CORPSE, &corpseType);
    rID got = c ? c->mID : corpseType;
    extern int16 AdjustCR(int16 BaselineCR);
    int depthcr = (int)AdjustCR((int16)(TDUN(sfMap->dID)->GetConst(INITIAL_CR) +
        (sfMap->Depth * TDUN(sfMap->dID)->GetConst(DUN_SPEED)) / 100 - 1));
    int weapons = -1, rweapons = -1, innate = -1, rinnate = -1;
    int hostile = -1, peaceful = -1, party = -1, rhostile = -1, rpeaceful = -1, rparty = -1;
    if (c) {
        hostile = c->isHostileTo(p); peaceful = (c->StateFlags & MS_PEACEFUL) ? 1 : 0;
        party = c->PartyID; weapons = sfWeapons(c); innate = c->CountStati(INNATE_SPELL);
        /* A fresh one, built the way the level generator builds it. */
        for (int dx = -2; dx <= 2; dx++) for (int dy = -2; dy <= 2; dy++) {
            int x = p->x + dx, y = p->y + dy;
            if (rhostile != -1 || (x == p->x && y == p->y) || (x == sfX && y == sfY)) continue;
            if (!sfMap->InBounds(x, y) || sfMap->SolidAt(x, y) || sfMap->FCreatureAt(x, y)) continue;
            Monster *r = new Monster(got);
            TMON(got)->GrantGear(r, got, true);
            TMON(got)->PEvent(EV_BIRTH, r, got);
            r->PlaceAt(sfMap, x, y);
            r->Initialize();
            rhostile = r->isHostileTo(p); rpeaceful = (r->StateFlags & MS_PEACEFUL) ? 1 : 0;
            rparty = r->PartyID; rweapons = sfWeapons(r); rinnate = r->CountStati(INNATE_SPELL);
            r->Remove(true);
        }
    }
    Error("STONE_FLESH_AFTER kind=%s statues=%d creature=%s alive=%d type=%s want=%s "
          "corpses=%d corpse_type=%s cr=%d depthcr=%d dragon=%d nocorpse=%d "
          "hostile=%d peaceful=%d party=%d ref_hostile=%d ref_peaceful=%d ref_party=%d "
          "weapons=%d ref_weapons=%d innate=%d ref_innate=%d",
        sfTyped ? "typed" : "untyped", sfCount(sfMap, sfX, sfY, T_STATUE, NULL),
        c ? "yes" : "none", c ? 1 : 0, got ? (const char*)NAME(got) : "none",
        sfWant ? (const char*)NAME(sfWant) : "none", corpses,
        corpseType ? (const char*)NAME(corpseType) : "none",
        got ? (int)TMON(got)->CR : -1, depthcr,
        got ? (int)TMON(got)->isMType(got, MA_DRAGON) : -1,
        got ? (int)TMON(got)->HasFlag(M_NO_CORPSE) : -1,
        hostile, peaceful, party, rhostile, rpeaceful, rparty,
        weapons, rweapons, innate, rinnate);
}

/* inc-w6t0: entry point of the Stone to Flesh reproduction probe. */
void StoneToFleshProbe(Player *p) {
    const char *mode = getenv("INCURSION_STONE_FLESH_PROBE");
    if (!mode) return;
    if (!strcmp(mode, "statue")) { StoneToFleshStatueSetup(p); return; }
    rID effect = FIND("stone to flesh"), potion = FIND("potion");
    if (!p || !p->m || !effect || !potion ||
        (strcmp(mode, "spell") && strcmp(mode, "potion"))) {
        Error("STONE_FLESH INCONCLUSIVE missing resource or bad mode"); return;
    }
    bool playing = theGame->PlayMode;
    theGame->PlayMode = true;
    int8 more = p->Options[OPT_AUTOMORE];
    p->Options[OPT_AUTOMORE] = 1;
    p->RemoveStati(STONING);
    p->GainTempStati(STONING, NULL, 50, SS_MISC);
    int hp0 = p->cHP, st0 = p->HasStati(STONING) ? 1 : 0;
    EvReturn r;
    if (!strcmp(mode, "spell")) {
        EventInfo xe; xe.Clear();
        xe.EActor = p; xe.ETarget = p; xe.EVictim = p;
        xe.EMap = p->m; xe.eID = effect; xe.isSpell = true;
        r = ReThrow(EV_EFFECT, xe);
    } else {
        Item *drink = Item::Create(potion);
        drink->MakeMagical(effect);
        drink->MakeKnown(0xFF);
        p->GainItem(drink, true);
        EventInfo de; de.Clear();
        de.EActor = p; de.EVictim = p; de.EItem = drink; de.eID = effect;
        r = ReThrow(EV_DRINK, de);
    }
    Error("STONE_FLESH mode=%s return=%d stoning_before=%d stoning_after=%d hp_before=%d hp_after=%d",
        mode, (int)r, st0, p->HasStati(STONING) ? 1 : 0, hp0, (int)p->cHP);
    p->Options[OPT_AUTOMORE] = more;
    theGame->PlayMode = playing;
}
