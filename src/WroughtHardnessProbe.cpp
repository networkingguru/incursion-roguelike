/* inc-dwfc: opt-in probe. Off unless INCURSION_WROUGHT_HARDNESS_PROBE is set.
   Called from Game::Play (src/Main.cpp); graded by
   tools/check_wrought_hardness.sh. Wrought and orcish iron items must have a
   finite hardness, not the -1 immunity sentinel. One WROUGHT_HARD_PROBE line
   per fact goes to errors.log through Error(). */
#include "Incursion.h"

static const int16 WhTypes[4] = { AD_ACID, AD_FIRE, AD_SONI, AD_SLASH };

/* Read the WIN_NUMBERS row the player's terminal now shows. */
static void WhNumbersLine(Player *pl, char *out, int n) {
    Term *t = pl->MyTerm;
    int i = 0;
    t->SetWin(WIN_NUMBERS);
    for (int x = t->WinLeft(); x <= t->WinRight() && i < n - 1; x++) {
        int c = GLYPH_ID_VALUE(t->AGetChar(x, t->WinTop()));
        out[i++] = (c >= 32 && c < 127) ? (char)c : ' ';
    }
    out[i] = '\0';
}

/* Build one item. quality 0 = none. Returns NULL (after logging) on failure. */
static Item *WhMake(const char *base, int quality) {
    Item *it = Item::Create(FIND(base));
    if (!it) {
        Error("WROUGHT_HARD_PROBE: INCONCLUSIVE -- no item %s", base);
        return NULL;
    }
    if (it->isType(T_WEAPON)) it->SetInherentPlus(0);
    if (quality) it->AddQuality(quality);
    return it;
}

/* Print the four hardnesses; return false when they do not match want. */
static bool WhHardness(const char *role, Item *it, int want, bool *inconclusive) {
    int h[4];
    bool ok = true;
    for (int i = 0; i < 4; i++) {
        h[i] = it->Hardness(WhTypes[i]);
        if (h[i] != want) ok = false;
    }
    Error("WROUGHT_HARD_PROBE: role=%s material=%d acid=%d fire=%d soni=%d slash=%d want=%d",
        role, (int)it->Material(), h[0], h[1], h[2], h[3], want);
    (void)inconclusive;
    return ok;
}

void WroughtHardnessProbe(Player *pl) {
    /* inc-dwfc: off unless INCURSION_WROUGHT_HARDNESS_PROBE is set. */
    if (!getenv("INCURSION_WROUGHT_HARDNESS_PROBE"))
        return;
    if (!pl || !pl->m) {
        Error("WROUGHT_HARD_PROBE: INCONCLUSIVE -- no live player and map");
        return;
    }
    const bool wasInPlay = theGame->PlayMode;
    theGame->PlayMode = true;
    bool fail = false, inconclusive = false;

    /* 1+2: material and hardness. Orcish halves the base 10 (src/Item.cpp
       Item::Hardness), so orcish wrought iron answers 5, wrought answers 10. */
    Item *wr = WhMake("long sword", IQ_WROUGHT);
    Item *oc = WhMake("long sword", IQ_ORCISH);
    Item *plain = WhMake("long sword", 0);
    Item *lens = WhMake("viewing lens", 0);
    if (!wr || !oc || !plain || !lens) { theGame->PlayMode = wasInPlay; return; }
    if (wr->Material() != MAT_WROUGHT || oc->Material() != MAT_WROUGHT ||
        plain->Material() != MAT_IRON) {
        Error("WROUGHT_HARD_PROBE: INCONCLUSIVE -- Material wr=%d oc=%d plain=%d",
            (int)wr->Material(), (int)oc->Material(), (int)plain->Material());
        theGame->PlayMode = wasInPlay;
        return;
    }
    if (!WhHardness("wrought", wr, 10, &inconclusive)) fail = true;
    if (!WhHardness("orcish", oc, 5, &inconclusive)) fail = true;
    /* 5: controls -- plain iron is 10, glass is still immune to acid. */
    if (!WhHardness("iron-control", plain, 10, &inconclusive)) fail = true;
    {
        int g = lens->Hardness(AD_ACID);
        Error("WROUGHT_HARD_PROBE: role=glass-control acid=%d want=-1", g);
        if (g != -1) fail = true;
    }

    /* 3+4: damage the wrought sword with acid, as a non-owner (it lies on the
       floor, so Owner() is NULL and the player is only the actor). */
    const int dmg = 14;
    wr->PlaceAt(pl->m, pl->x, pl->y, true);
    hObj h = wr->myHandle;
    const int hp0 = wr->GetHP();
    if (wr->Owner() || hp0 <= dmg) {
        Error("WROUGHT_HARD_PROBE: INCONCLUSIVE -- owner=%d hp=%d dmg=%d",
            wr->Owner() ? 1 : 0, hp0, dmg);
        inconclusive = true;
    } else {
        ThrowDmg(EV_DAMAGE, AD_ACID, dmg, "wrought hardness probe", pl, wr);
        char line[160];
        WhNumbersLine(pl, line, sizeof(line));
        Item *r = oItem(h);
        const bool gone = !r || (r->Flags & F_DELETE);
        const int hp1 = gone ? 0 : r->GetHP();
        const int lost = hp0 - hp1;
        Error("WROUGHT_HARD_PROBE: role=damage vDmg=%d hp_before=%d hp_after=%d gone=%d lost=%d want_lost=%d",
            dmg, hp0, hp1, gone ? 1 : 0, lost, dmg - 10);
        if (gone || lost != dmg - 10) fail = true;
        Error("WROUGHT_HARD_PROBE: line=[%s]", line);
        const bool vs10 = strstr(line, "vs. 10 (") != NULL;
        const bool dmgTxt = strstr(line, "damage") != NULL;
        const bool immune = strstr(line, "vs. Immune") != NULL;
        Error("WROUGHT_HARD_PROBE: line vs10=%d damage=%d immune=%d", vs10, dmgTxt, immune);
        if (!vs10 || !dmgTxt || immune) fail = true;
        if (r && !(r->Flags & F_DELETE)) r->Remove(true);
    }
    oc->Remove(true);
    plain->Remove(true);
    lens->Remove(true);
    theGame->PlayMode = wasInPlay;
    if (inconclusive) Error("WROUGHT_HARD_PROBE: INCONCLUSIVE");
    else Error("WROUGHT_HARD_PROBE: %s", fail ? "ALL FAIL" : "ALL PASS");
}
