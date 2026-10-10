/* inc-u3dp: command events on a loaded player, with two visible watchers.
   The shell checker owns the literal penalties and counts SpotCheck log lines.
   This probe never calls HideTrigger or SpotCheck. Scene changes are setup;
   BEGIN/END delimit only the command event, not setup or subsequent turns. */
#include "Incursion.h"
#include "HideCheck.h"

static void htHide(Player *p, bool hiding) {
    p->RemoveStati(HIDING);
    p->RemoveStati(SPRINTING);
    p->Timeout = 0;
    if (hiding) {
        p->GainPermStati(HIDING, NULL, SS_CLAS, HI_SHADOWS, 1);
        HideStarted(p, false);
    }
}

static Item *htItem(Player *p, const char *name, const char *effect = NULL) {
    rID id = FIND(name), eid = effect ? FIND(effect) : 0;
    if (!id || (effect && !eid)) return NULL;
    Item *it = Item::Create(id);
    if (effect) it->MakeMagical(eid);
    it->MakeKnown(0xFF);
    // GainItem merges a unit into a matching stack and frees it; the effects chosen below are not in the loaded pack.
    p->GainItem(it, true);
    return it;
}

void HideTriggerProbe(Player *p) {
    if (!getenv("INCURSION_HIDE_TRIGGER_PROBE")) return;
    if (!p || !p->m) { Error("HIDE_TRIGGER INCONCLUSIVE no player"); return; }
    Map *mp = p->m;
    bool playing = theGame->PlayMode;
    theGame->PlayMode = true;
    const int8 autoMore = p->Options[OPT_AUTOMORE];
    p->Options[OPT_AUTOMORE] = 1;   /* a --more-- prompt would wait for a key */
    int dx = 0, dy = 0;
    static const int dirs[][2] = {{1,0},{-1,0},{0,1},{0,-1}};
    for (int k = 0; k < 4; ++k) {
        int i;
        for (i = -1; i <= 3; ++i) {
            int x = p->x + dirs[k][0]*i, y = p->y + dirs[k][1]*i;
            if (!mp->InBounds(x,y) || mp->SolidAt(x,y) ||
                (i && (mp->FCreatureAt(x,y) || mp->FFeatureAt(x,y)))) break;
        }
        if (i == 4) { dx = dirs[k][0]; dy = dirs[k][1]; break; }
    }
    if (!dx && !dy) { Error("HIDE_TRIGGER INCONCLUSIVE no scene space"); return; }
    Creature *c; int idx;
    MapIterate(mp,c,idx)
        if (c->isCreature() && c != p) c->GainPermStati(ASLEEP,NULL,SS_MISC);
    for (int s = -1; s <= 1; s += 2) {
        int x = p->x-dx+dy*s, y = p->y-dy+dx*s;
        if (!mp->InBounds(x,y) || mp->FCreatureAt(x,y)) {
            Error("HIDE_TRIGGER INCONCLUSIVE door frame obstructed"); return;
        }
        mp->At(x,y).Solid = mp->At(x,y).Opaque = true;
    }
    Door *door = new Door(FIND("oak door"));
    door->PlaceAt(mp,p->x-dx,p->y-dy);
    Monster *watch[2];
    for (int k = 0; k < 2; ++k) {
        watch[k] = new Monster(FIND("giant rat"));
        watch[k]->PlaceAt(mp,p->x+dx*(k+2),p->y+dy*(k+2));
        watch[k]->Initialize(true);
        watch[k]->RemoveStati(ASLEEP);
        watch[k]->RemoveStati(SLEEPING);
        watch[k]->SightRange = 20;
        watch[k]->mHP = watch[k]->cHP = 10000;
        mp->At(watch[k]->x,watch[k]->y).Lit = true;
        if (!HideCanWatch(watch[k],p)) {
            Error("HIDE_TRIGGER INCONCLUSIVE watcher cannot see player"); return;
        }
    }
    Error("HIDE_TRIGGER SCENE player=%d watcher1=%d watcher2=%d",
        (int)p->myHandle,(int)watch[0]->myHandle,(int)watch[1]->myHandle);
    p->GainPermStati(SKILL_BONUS,NULL,SS_MISC,SK_DECIPHER,50);
    p->GainPermStati(SKILL_BONUS,NULL,SS_MISC,SK_USE_MAGIC,50);
    p->GainPermStati(EXTRA_FEAT,NULL,SS_MISC,FT_SHOOT_FROM_COVER);
    p->GainPermStati(EXTRA_ABILITY,NULL,SS_MISC,CA_HIDE_IN_PLAIN_SIGHT,1);
    // AutoLoot uses this same pickup event without opening InventoryManager.
    p->GainPermStati(ACTING,NULL,SS_MISC,EV_PICKUP,0,FIND("AutoLoot"));
    static const char *names[] = {"open","close","pickup_tiny","pickup_medium",
        "drop","drink","read","zap","activate","snipe"};
    for (int hiding = 0; hiding <= 1; ++hiding) {
        for (int k = 0; k < 10; ++k) {
            htHide(p,hiding != 0);
            Item *it = NULL;
            if (k == 0 || k == 1) {
                door->DoorFlags = k == 1 ? DF_OPEN : 0;
                if (k == 0) door->Flags |= F_SOLID;
                else door->Flags &= ~F_SOLID;
                door->SetImage();
            } else {
                if (k == 2) it = htItem(p,"viewing lens");
                if (k == 3 || k == 4) it = htItem(p,"pickaxe");
                if (k == 5) it = htItem(p,"potion","Cure Light Wounds");
                if (k == 6) it = htItem(p,"scroll","Shield");
                if (k == 7) it = htItem(p,"wand","Cure Light Wounds");
                if (k == 8) it = htItem(p,"horn","Plenty");
                if (k == 9) it = htItem(p,"dagger");
                if (!it) { Error("HIDE_TRIGGER INCONCLUSIVE missing item %s",names[k]); return; }
                if (k == 2 || k == 3) { it->Remove(false); it->PlaceAt(mp,p->x,p->y); }
                if (k == 7) it->SetCharges(50);
            }
            Error("HIDE_TRIGGER BEGIN case=%s_%d",names[k],hiding);
            EvReturn r;
            if (k < 2) r = Throw(k == 0 ? EV_OPEN : EV_CLOSE,p,door);
            else if (k < 5) r = Throw(k == 4 ? EV_DROP : EV_PICKUP,p,NULL,it);
            else if (k == 9) r = Throw(EV_RATTACK,p,watch[0],NULL,it);
            else {
                EventInfo e; e.Clear(); e.EActor = p; e.EVictim = p;
                e.EItem = it; e.eID = it->eID;
                r = ReThrow(k == 5 ? EV_DRINK : k == 6 ? EV_READ :
                    k == 7 ? EV_ZAP : EV_ACTIVATE,e);
            }
            bool state = k == 0 ? (door->DoorFlags & DF_OPEN) != 0 :
                         k == 1 ? (door->DoorFlags & DF_OPEN) == 0 : true;
            Error("HIDE_TRIGGER END ret=%d ok=%d hiding=%d",(int)r,
                r != ABORT && state ? 1 : 0,p->HasStati(HIDING) ? 1 : 0);
        }
    }
    htHide(p,true);
    p->GainPermStati(SPRINTING,NULL,SS_MISC);
    door->DoorFlags = 0; door->Flags |= F_SOLID; door->SetImage();
    Error("HIDE_TRIGGER BEGIN case=sprint");
    EvReturn r = Throw(EV_OPEN,p,door);
    Error("HIDE_TRIGGER END ret=%d ok=%d hiding=%d",(int)r,r != ABORT,p->HasStati(HIDING));

    htHide(p,true);
    Error("HIDE_TRIGGER BEGIN case=song");
    p->UseAbility(CA_BARDIC_MUSIC,0); // Same entry as the active-ability command; keys choose Courage.
    Error("HIDE_TRIGGER END ret=0 ok=%d hiding=%d",p->HasStati(SINGING) && !p->HasStati(HIDING),p->HasStati(HIDING));
    p->RemoveStati(HIDING);
    Error("HIDE_TRIGGER BEGIN case=hide_singing");
    r = ThrowVal(EV_HIDE,HI_SHADOWS,p);
    Error("HIDE_TRIGGER END ret=%d ok=%d hiding=%d",(int)r,
        r == ABORT && p->HasStati(SINGING) && !p->HasStati(HIDING),p->HasStati(HIDING));
    p->RemoveStati(SINGING);
    Error("HIDE_TRIGGER BEGIN case=hide_silent");
    r = ThrowVal(EV_HIDE,HI_SHADOWS,p);
    Error("HIDE_TRIGGER END ret=%d ok=%d hiding=%d",(int)r,
        r != ABORT && p->HasStati(HIDING),p->HasStati(HIDING));
    p->RemoveStati(HIDING);
    /* inc-u3dp phase 6: two hard-coded cases. Each verdict is forced with an
       extreme hiderPenalty instead of the dice, so the stored result and the
       name word are exact. Appraise is raised so the aware word is allowed. */
    p->GainPermStati(SKILL_BONUS,NULL,SS_MISC,SK_APPRAISE,100);
    htHide(p,true);
    Error("HIDE_TRIGGER BEGIN case=appraise");
    SpotCheck(watch[0],p,-100);
    String seen = watch[0]->Name(NA_STATI);
    bool aware = strstr(seen.GetData(),"aware ") && !strstr(seen.GetData(),"unaware ");
    SpotCheck(watch[0],p,100);
    String unseen = watch[0]->Name(NA_STATI);
    bool unaware = strstr(unseen.GetData(),"unaware ");
    Error("HIDE_TRIGGER END ret=0 ok=%d aware=%d unaware=%d",
        aware && unaware ? 1 : 0, aware ? 1 : 0, unaware ? 1 : 0);
    p->RemoveStati(HIDING);
    htHide(p,true);
    Error("HIDE_TRIGGER BEGIN case=spot_keeps_hide");
    SpotCheck(watch[0],p,-100);
    Error("HIDE_TRIGGER END ret=0 ok=%d hiding=%d",
        p->HasStati(HIDING) ? 1 : 0, p->HasStati(HIDING) ? 1 : 0);
    p->RemoveStati(HIDING);
    p->Options[OPT_AUTOMORE] = autoMore;
    theGame->PlayMode = playing;
    Error("HIDE_TRIGGER COMPLETE");
}
