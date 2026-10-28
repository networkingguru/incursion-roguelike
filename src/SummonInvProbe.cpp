/* inc-yj4cz: opt-in real-path reproductions; no defect-site changes.
   Scene construction is explicit, not dependent on generated gear or AI. */
#define protected public
#include "Incursion.h"
#undef protected

static FILE *siLog;

static Monster *siMonster(Map *mp, int x, int y) {
    Monster *mn = new Monster(FIND("ramadeen"));
    mn->CalcValues();
    mn->CalcHP();
    mn->cHP = mn->mHP + mn->Attr[A_THP];
    mn->PlaceAt(mp, x, y, true);
    return mn;
}

static Item *siItem(hObj h) {
    Object *o = theRegistry->GetQuiet(h);
    return o && o->isItem() ? (Item*)o : NULL;
}

static bool siGone(hObj h) {
    Item *it = siItem(h);
    return !it || (it->Flags & F_DELETE);
}

static int siParents(hObj owner) {
    int count = 0;
    for (hObj h = 128; h < theRegistry->LastUsedHandle; ++h) {
        Item *it = siItem(h);
        if (it && it->Parent == owner) {
            ++count;
            fprintf(siLog, "DANGLING item=%d Parent=%d F_DELETE=%d\n",
                (int)h, (int)it->Parent, !!(it->Flags & F_DELETE));
        }
    }
    return count;
}

static void siA(Map *mp, int x, int y, bool control) {
    Monster *summoner = siMonster(mp,x,y);
    Monster *summoned = siMonster(mp,x+1,y);
    Monster *third = siMonster(mp,x+2,y);
    summoned->GainTempStati(SUMMONED,summoner,100,SS_MISC);
    Item *worn = Item::Create(FIND("long sword"));
    Item *later = control ? NULL : Item::Create(FIND("plate mail"));
    // GainItem prepends: insert the later item before the worn item.
    if (later) {
        summoned->GainItem(later,false);
        later->IFlags |= IF_PROPERTY;
        later->GainPermStati(SUMMONED,third,SS_ENCH);
    }
    summoned->GainItem(worn,false);
    worn->IFlags |= IF_PROPERTY | IF_WORN;
    const hObj wh = worn->myHandle, lh = later ? later->myHandle : 0;
    const hObj mh = summoned->myHandle;
    int count = 0;
    bool order = summoned->Inv == wh && worn->Next == lh;
    for (Item *it = summoned->FirstInv(); it; it = summoned->NextInv()) {
        fprintf(siLog,"ORDER control=%d index=%d handle=%d Next=%d Parent=%d worn=%d property=%d summoned_from=%d\n",
            control,count,(int)it->myHandle,(int)it->Next,(int)it->Parent,
            !!(it->IFlags & IF_WORN),!!(it->IFlags & IF_PROPERTY),
            it->GetStatiObj(SUMMONED) ? (int)it->GetStatiObj(SUMMONED)->myHandle : 0);
        ++count;
    }
    fprintf(siLog,"%s a_setup control=%d count=%d expected=%d inv=%d worn=%d later=%d order=%d\n",
        order && count == (control ? 1 : 2) ? "PASS" : "FAIL",
        control,count,control ? 1 : 2,(int)summoned->Inv,(int)wh,(int)lh,order);
    // RemoveStati calls the actual Creature::StatiOff SUMMONED handler.
    // Keep the third creature alive: removing it could trigger the known crash.
    summoned->RemoveStati(SUMMONED);
    const int dangling = siParents(mh);
    const bool dead = !!(summoned->Flags & F_DELETE);
    if (control)
        fprintf(siLog,"%s a_positive_control monster_deleted=%d worn_gone=%d dangling=%d\n",
            dead && siGone(wh) && !dangling ? "PASS" : "FAIL",dead,siGone(wh),dangling);
    else {
        fprintf(siLog,"%s a_all_items_gone monster_deleted=%d worn_gone=%d later_gone=%d expected_gone=2\n",
            dead && siGone(wh) && siGone(lh) ? "PASS" : "FAIL",dead,siGone(wh),siGone(lh));
        fprintf(siLog,"%s a_no_dangling owner=%d registered_items_with_parent=%d expected=0\n",
            !dangling ? "PASS" : "FAIL",(int)mh,dangling);
    }
    fflush(siLog);
    // Post-measurement cleanup while the queued owner is still registered.
    // Never let the later SUMMONED reference fire after owner destruction.
    if (!siGone(wh)) siItem(wh)->Remove(true);
    if (lh && !siGone(lh)) siItem(lh)->Remove(true);
    third->Remove(true);
    summoner->Remove(true);
}

static void siB(Map *mp, int x, int y) {
    Monster *summoner = siMonster(mp,x,y);
    Monster *victim = siMonster(mp,x+1,y);
    Monster *thief = siMonster(mp,x+2,y);
    thief->GainTempStati(SUMMONED,summoner,100,SS_MISC);
    Item *item = Item::Create(FIND("long sword"));
    victim->GainItem(item,false);
    item->IFlags |= IF_PROPERTY; // Own gear; unworn, hence one eligible candidate.
    const hObj ih = item->myHandle;
    const int tx = thief->x, ty = thief->y;
    extern int8 LOFGetForcedSaveThrowRoll();
    const int roll = LOFGetForcedSaveThrowRoll();
    fprintf(siLog,"%s b_setup victim_summoned=%d thief_summoned=%d property=%d worn=%d save_roll=%d candidates=1\n",
        !victim->HasStati(SUMMONED) && thief->HasStati(SUMMONED) && roll == 1 ? "PASS" : "FAIL",
        victim->HasStati(SUMMONED),thief->HasStati(SUMMONED),
        !!(item->IFlags & IF_PROPERTY),!!(item->IFlags & IF_WORN),roll);
    // Save-roll mechanism: the existing global hook LOFGetForcedSaveThrowRoll,
    // seeded by INCURSION_FORCE_SAVE_ROLL=1 (natural 1 always fails the save).
    // ThrowDmg runs the real event path (Damage reads EventStack, so a direct
    // Damage() call with EventSP == -1 crashes in getChivalryBreach). One
    // eligible item makes random(c) immaterial; no skirmisher AI involved.
    EvReturn result = ThrowDmg(EV_DAMAGE,AD_STEA,1,"theft probe",thief,victim);
    bool carried = item->Parent == thief->myHandle && thief->Inv == ih;
    fprintf(siLog,"%s b_transfer result=%d parent=%d thief=%d carried=%d\n",
        carried ? "PASS" : "FAIL",(int)result,
        (int)item->Parent,(int)thief->myHandle,carried);
    fprintf(siLog,"%s b_property_cleared carried=%d property=%d expected=0\n",
        carried && !(item->IFlags & IF_PROPERTY) ? "PASS" : "FAIL",
        carried,!!(item->IFlags & IF_PROPERTY));
    thief->RemoveStati(SUMMONED);
    item = siItem(ih);
    const bool floor = item && !(item->Flags & F_DELETE) && !item->Parent &&
        item->m == mp && item->x == tx && item->y == ty;
    fprintf(siLog,"%s b_stolen_item_dropped registered=%d deleted=%d parent=%d on_floor=%d xy=%d,%d expected_xy=%d,%d thief_deleted=%d\n",
        floor && (thief->Flags & F_DELETE) ? "PASS" : "FAIL",item != NULL,
        item ? !!(item->Flags & F_DELETE) : 1,item ? (int)item->Parent : 0,floor,
        item ? item->x : -1,item ? item->y : -1,tx,ty,!!(thief->Flags & F_DELETE));
    fflush(siLog);
    if (!siGone(ih)) siItem(ih)->Remove(true);
    victim->Remove(true);
    summoner->Remove(true);
}

void SummonInvProbe(Player *pl) {
    // inc-yj4cz: INCURSION_SUMMON_INV_PROBE=a|b, driven by tools/check_summoned_inventory.sh.
    const char *mode = getenv("INCURSION_SUMMON_INV_PROBE");
    static bool ran = false;
    if (!mode || ran) return;
    ran = true;
    char path[1024];
    snprintf(path,sizeof(path),"%slogs/summoned-inventory.log",(const char*)T1->IncursionDirectory);
    siLog = fopen(path,"w");
    if (!siLog) return;
    setvbuf(siLog,NULL,_IONBF,0); // every line reaches disk before any later crash
    if (!pl || !pl->m || !pl->m->InBounds(4,2) ||
        (strcmp(mode,"a") && strcmp(mode,"b"))) {
        fprintf(siLog,"FAIL setup valid_player_map_case=0\n");
    } else {
        Map *mp = pl->m;
        // Terrain is explicitly staged; sharing avoids random placement search.
        for (int x = 2; x <= 4; ++x) mp->WriteTerra(x,2,FIND("Floor"));
        fprintf(siLog,"CASE %s vanish=RemoveStati(SUMMONED) cleanup=after_measurements\n",mode);
        if (*mode == 'a') { siA(mp,2,2,true); siA(mp,2,2,false); }
        else siB(mp,2,2);
        fprintf(siLog,"COMPLETE\n");
    }
    fclose(siLog);
    siLog = NULL;
}
