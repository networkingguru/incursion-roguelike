/* inc-30ur: opt-in oracle for the WQ_SLEEP weapon quality. Each case runs in
   a fresh fixture sandbox. Cases 3-8 are real melee attacks: Throw(EV_WATTACK)
   reaches Creature::Strike and Creature::Hit, where sleep is applied last. The
   d20 comes from INCURSION_LOF_FORCE_ROLL, the Fortitude die from
   INCURSION_FORCE_SAVE_ROLL, damage from INCURSION_FORCE_DAMAGE_ROLL. Case 5
   gives the target +2 deflection, which the fixture's margin of 6 turns into 4;
   setup=0 unless the finished event shows exactly 4. */
// Diagnostic message access, as in MountSizeProbe.cpp.
#define protected public
#include "Incursion.h"
#undef protected

extern int8 LOFGetForcedSaveThrowRoll();

void SleepQualityProbe(Player *p)
{
    const char *mode = getenv("INCURSION_SLEEP_QUALITY_PROBE");
    if (!mode) return;
    const int n = atoi(mode);
    char path[1024];
    snprintf(path, sizeof(path), "%slogs/sleep-quality.log", (const char*)T1->IncursionDirectory);
    FILE *log = fopen(path, "w");
    if (!log) return;
    rID trident = FIND("trident"), sword = FIND("long sword"), kysul = FIND("Kysul"),
        floor = FIND("floor"), region = FIND("Winding Corridor"),
        orc = FIND("cave orc"), skel = FIND("cellar dwellar"), rat = FIND("giant rat");
    if (!p || !p->m || n < 1 || n > 8 || !trident || !sword || !kysul || !floor ||
        !region || !orc || !skel || !rat || p->m->SizeX() <= 26 || p->m->SizeY() <= 26) {
        fprintf(log, "INCONCLUSIVE: missing player/map/resource or invalid case\n");
        fclose(log); return;
    }
    Map *mp = p->m;
    TextTerm *term = (TextTerm*)p->MyTerm;
    if (n <= 2) {
        Item *t = Item::Create(trident);
        if (n == 1) {
            Item *s = Item::Create(sword);
            const bool a = t->QualityOK(WQ_SLEEP), b = s->QualityOK(WQ_SLEEP);
            fprintf(log, "case=1 trident_ok=%d sword_ok=%d setup=%d\n",
                (int)a, (int)b, (int)(t->isType(T_WEAPON) && s->isType(T_WEAPON)));
            fclose(log); return;
        }
        t->SetInherentPlus(1);
        const rID oldGod = p->GodID;
        const int16 gn = theGame->GodNum(kysul);
        const int16 oldFav = p->FavourLev[gn];
        p->GodID = kysul;
        p->FavourLev[gn] = 20;
        EventInfo e; e.Clear();
        e.EActor = p; e.EItem = t; e.eID = kysul; e.isItem = true; e.EMap = p->m;
        term->MsgHistory[0] = 0;
        p->IBlessing(e);
        const bool glow = strstr(term->MsgHistory, "deep silvery light") != NULL;
        const bool setup = (int8)TGOD(kysul)->GetConst(CHOSEN_WEAPON_QUALITY) == WQ_SLEEP &&
            t->GetInherentPlus() == 1 && t->iID == (rID)TGOD(kysul)->GetConst(CHOSEN_WEAPON);
        fprintf(log, "case=2 has_sleep=%d glow=%d setup=%d\n",
            (int)t->HasQuality(WQ_SLEEP), (int)glow, (int)setup);
        p->GodID = oldGod; p->FavourLev[gn] = oldFav;
        fclose(log); return;
    }
    // Cases 3-8: clear the map and build a floor arena, as MountSizeProbe does.
    Thing *obj; int index;
    for (;;) {
        Thing *remove = NULL;
        MapIterate(mp, obj, index)
            if (obj != p) { remove = obj; break; }
        if (!remove) break;
        remove->Remove(true);
    }
    Rect rect(0, 0, mp->SizeX()-1, mp->SizeY()-1);
    for (int y = 5; y <= 25; ++y)
        for (int x = 5; x <= 25; ++x) {
            mp->RemoveTerraXY(x,y);
            mp->WriteAt(rect,x,y,floor,region,PRIO_MAX,true);
        }
    REGMEM(region,p)->Seen = true;
    p->PlaceAt(mp,15,15);
    // 3 trident on a rat; 4 as 3 but the save succeeds; 5 margin exactly 4;
    // 6 sleep-immune cellar dwellar; 7 trident on a rat; 8 trident on an evil
    // cave orc, so the paladin's holy pass deals damage after the quality loop.
    Monster *mt = new Monster(n == 6 ? skel : n == 8 ? orc : rat);
    mt->PlaceAt(mp,16,15);
    mt->mHP = mt->cHP = 1000;
    mt->CalcValues();
    mp->At(15,15).Lit = 1; mp->At(16,15).Lit = 1;
    const bool wasInPlay = theGame->PlayMode;
    Weapon *w = (Weapon*)Item::Create(trident);
    w->SetInherentPlus(1);
    if (n == 5) {
        mt->GainPermStati(ADJUST_DEFL,NULL,SS_MISC,A_DEF,2);
        mt->CalcValues();
    }
    w->AddQuality(WQ_SLEEP);
    p->GainItem(w, true);
    p->Inv[SL_WEAPON] = w->myHandle;
    p->Inv[SL_READY] = 0;
    w->SetOwner(p->myHandle);
    w->IFlags |= IF_WORN;
    const int8 wantSave = (n == 4) ? 20 : 1;
    const bool immune = mt->ResistLevel(AD_SLEE) == -1;
    const bool evil = mt->isMType(MA_EVIL) || mt->isMType(MA_UNDEAD);
    const bool pre = LOFGetForcedSaveThrowRoll() == wantSave && p->InSlot(SL_WEAPON) == w &&
        w->HasQuality(WQ_SLEEP) && immune == (n == 6) && (n == 8 ? evil : (n == 6 || !evil)) &&
        mt->m == mp && !mt->HasStati(ASLEEP) && !mt->isDead() && p->isBeside(mt) &&
        mp->At(16,15).Lit && p->isMType(MA_GOOD);
    term->MsgHistory[0] = 0;
    theGame->PlayMode = true;
    Throw(EV_WATTACK, p, mt);
    theGame->PlayMode = wasInPlay;
    // Throw leaves the finished event in the slot above EventSP.
    const EventInfo &r = EventStack[EventSP+1];
    const int margin = r.vRoll + r.vHit - r.vDef;
    const bool asleep = mt->HasStati(ASLEEP);
    const int dur = asleep ? mt->GetStatiDur(ASLEEP) : 0;
    const bool said = strstr(term->MsgHistory, "falls asleep.") != NULL;
    // Case 8: the holy pass ran if the finished event lists its "+2d6 holy" damage.
    const bool holy = strstr(((EventInfo&)r).strXDmg.GetData(), "holy") != NULL;
    const bool setup = pre && r.Event % 500 == EV_WATTACK && r.isHit && !r.isCrit &&
        !r.isWildMiss && r.vRoll == 19 && r.vRoll < r.vThreat &&
        (n == 5 ? margin == 4 : margin >= 5) && (n == 8 ? holy : true) &&
        !mt->isDead() && mt->cHP < 1000 && !p->isDead();
    fprintf(log, "case=%d asleep=%d dur=%d said=%d resist=%d immune=%d margin=%d setup=%d "
        "vRoll=%d vHit=%d vDef=%d vThreat=%d isHit=%d isCrit=%d hurt=%d holy=%d\n",
        n, (int)asleep, dur, (int)said, (int)r.Resist, (int)r.Immune, margin, (int)setup,
        (int)r.vRoll, (int)r.vHit, (int)r.vDef, (int)r.vThreat, (int)r.isHit,
        (int)r.isCrit, (int)(mt->cHP < 1000), (int)holy);
    fclose(log);
}
