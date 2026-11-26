/* inc-ibzyp: opt-in reproduction, enabled by INCURSION_MULTISELECT_COLOR_PROBE
   = a (cursed items on the ground), b (cursed items in a chest) p (the same two items on the floor, left for a keyed "Pick up what?" menu) or s (five
   items of known, hinted and unknown value, for the AutoLoot sort order). Stages a
   known cursed dagger (its name carries a RED "c "/"cursed " span, by the terse option) and a long sword,
   runs the AutoLoot macro, and logs each row LMultiSelect draws:
   MultiSelectColorSnap is called by TextTerm::LMultiSelect after each row.
   See tools/check_multiselect_colors.sh. */
#define protected public
#include "Incursion.h"
#undef protected

static FILE *msLog = NULL;

void MultiSelectColorSnap(Term *T, int16 x0, int16 y, int16 width, int16 row,
                          bool cursor, const char *text, const char *menu)
{
    if (!msLog) return;
    char chars[256];
    int red = 0, back1 = 0, n = 0;
    for (int16 x = x0; x < x0 + width && n < 255; ++x) {
        Glyph g = T->AGetChar(x, y);
        int c = GLYPH_ID_VALUE(g);
        chars[n++] = (c >= 32 && c < 127) ? (char)c : '?';
        if (GLYPH_FORE_VALUE(g) == RED) ++red;
        if (GLYPH_BACK_VALUE(g) == 1) ++back1;
    }
    chars[n] = 0;
    fprintf(msLog, "ROW menu=%s i=%d cursor=%d cursed=%d red=%d back1=%d ground=%d chest=%d text=[%s]\n",
            menu, (int)row, (int)cursor, strchr(text, (char)-RED) != NULL, red, back1,
            strstr(chars, "(on ground)") != NULL, strstr(chars, "(in chest)") != NULL, chars);
    fflush(msLog);
}

static void stageSort(Player *pl, Map *mp, int X, int Y, FILE *lg) {
        /* inc-ibzyp sort order. A known +5 long sword; a +1 handaxe with the
           "good" hint; a +1 club with the "magical" hint; plate mail with the
           "mundane" hint; an unidentified, unhinted +5 warhammer. */
        struct { const char *base; int plus; int hint; bool known; } S[5] = {
            { "long sword", 5, -1, true  },
            { "handaxe",    1,  2, false },
            { "club",       1,  1, false },
            { "plate mail", 0,  0, false },
            { "warhammer",  5, -1, false } };
        pl->PlaceAt(mp, X, Y);
        for (int n = 0; n < 5; ++n) {
            Item *it = Item::Create(FIND(S[n].base));
            it->SetInherentPlus(S[n].plus);
            if (S[n].known) it->MakeKnown(0xff);
            if (S[n].hint >= 0) it->Inscrip = XPrint(IntuitLevels[S[n].hint]);
            it->PlaceAt(mp, X, Y);
            fprintf(lg, "STAGED %s known=%d tier=%d value=%d true=%d\n", S[n].base,
                    (int)S[n].known, it->IntuitTier(),
                    (int)it->KnownValue(pl), (int)it->getShopCost(NULL, NULL));
        }
        mp->At(X,Y).Lit = true;
}

void MultiSelectColorProbe(Player *pl) {
    const char *mode = getenv("INCURSION_MULTISELECT_COLOR_PROBE");
    static bool ran = false;
    if (!mode || ran) return;
    ran = true;
    char path[1024];
    snprintf(path, sizeof(path), "%slogs/multiselect-colors.log", (const char*)T1->IncursionDirectory);
    FILE *lg = fopen(path, "w");
    if (!lg) return;
    const char cs = *mode;
    fprintf(lg, "CASE %c\n", cs);
    if (!pl || !pl->m || (cs != 'a' && cs != 'b' && cs != 's' && cs != 'p')) {
        fprintf(lg, "INCONCLUSIVE invalid setup\n"); fclose(lg); return;
    }
    Map *mp = pl->m;
    int X = -1, Y = -1;
    for (int y = 1; y < mp->SizeY()-1 && X < 0; ++y)
        for (int x = 1; x < mp->SizeX()-1 && X < 0; ++x)
            if (!mp->SolidAt(x,y) && !mp->FFeatureAt(x,y) && !mp->FirstAt(x,y)) {
                bool near = false; Thing *t; int i;
                MapIterate(mp,t,i)
                    if (t->isCreature() && t != pl && abs(t->x-x) <= 8 && abs(t->y-y) <= 8)
                        near = true;
                if (!near) { X = x; Y = y; }
            }
    if (X < 0) { fprintf(lg, "INCONCLUSIVE no isolated floor\n"); fclose(lg); return; }
    if (cs == 's') {
        stageSort(pl, mp, X, Y, lg);
    } else {
        Item *bad = Item::Create(FIND("dagger"));
        Item *ok = Item::Create(FIND("long sword"));
        bad->MakeKnown(0xff); ok->MakeKnown(0xff);
        bad->IFlags |= IF_CURSED;
        ok->IFlags &= ~IF_CURSED;
        String nm = bad->Name(NA_A|NA_LONG|NA_MECH);
        if (!strchr((const char*)nm, (char)-RED)) {
            fprintf(lg, "INCONCLUSIVE staged name has no RED span: [%s]\n", (const char*)nm); fclose(lg); return;
        }
        pl->PlaceAt(mp, X, Y);
        if (cs == 'b') {
            Item *chest = Item::Create(FIND("large oak chest"));
            EventInfo e; e.Clear(); e.EActor = pl; e.EItem = chest; e.EItem2 = bad;
            if (((Container*)chest)->Insert(e, true) != DONE || bad->GetParent() != chest) {
                fprintf(lg, "INCONCLUSIVE chest setup\n"); fclose(lg); return;
            }
            e.Clear(); e.EActor = pl; e.EItem = chest; e.EItem2 = ok;
            if (((Container*)chest)->Insert(e, true) != DONE || ok->GetParent() != chest) {
                fprintf(lg, "INCONCLUSIVE chest setup 2\n"); fclose(lg); return;
            }
            chest->PlaceAt(mp, X, Y);
        } else {
            bad->PlaceAt(mp, X, Y);
            ok->PlaceAt(mp, X, Y);
        }
        mp->At(X,Y).Lit = true;
    }
    mp->At(X,Y).Lit = true;
    if (cs == 'p') {   /* the key script presses g; the log stays open for the menu's rows */
        msLog = lg;
        return;
    }
    pl->Options[OPT_AUTOMORE] = 1;
    const bool wasPlay = theGame->PlayMode;
    theGame->PlayMode = true;
    pl->Timeout = 0;
    msLog = lg;
    RES(FIND("AutoLoot"))->PEvent(EV_INITIALIZE, pl, FIND("AutoLoot"), 0);
    pl->GainPermStati(ACTING, NULL, SS_MISC, EV_MACRO, 0, FIND("AutoLoot"));
    for (int n = 0; n < 6 && pl->HasStati(ACTING); ++n) {
        pl->Timeout = 0;
        if (ThrowEff(EV_MACRO, FIND("AutoLoot"), pl) == ABORT)
            pl->RemoveStati(ACTING);
    }
    pl->RemoveStati(ACTING);
    msLog = NULL;
    fprintf(lg, "COMPLETE\n");
    fclose(lg);
    theGame->PlayMode = wasPlay;
}
