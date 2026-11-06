/* inc-06ndv: a levitating player over a chasm swaps places with a walking ally.
   Opt-in only: INCURSION_CHASM_SWAP_PROBE=1. tools/check_chasm_swap.sh is the
   only caller. The probe stages the scene and the key script walks east into
   the ally, so the swap runs the real Creature::Walk path. The chasm square lies
   in a region sized for a large creature and the ally's square in a bigger one,
   so the pushed ally has a size change after TerrainEffects. */
#include "Incursion.h"

static hObj csAlly;

/* One line per player action, so the check reads where the swap left the ally. */
void ChasmSwapProbeTick(Player *p) {
    if (!csAlly || !isValidHandle(csAlly)) return;
    Creature *c = oCreature(csAlly);
    Error("CHASM_SWAP tick player=%d,%d ally=%d,%d ally_on_player_map=%d ally_deleted=%d",
        (int)p->x,(int)p->y,(int)c->x,(int)c->y,(int)(c->m == p->m),(int)!!(c->Flags & F_DELETE));
}

void ChasmSwapProbe(Player *p) {
    if (!getenv("INCURSION_CHASM_SWAP_PROBE") || !p || !p->m) return;
    static bool ran = false;
    if (ran) return;
    ran = true;
    Map *m = p->m;
    for (Thing *t = m->FirstThing(); t; ) {
        Thing *next = m->NextThing();
        if (t != p) t->Remove(true);
        t = next;
    }
    int px = m->SizeX()/2, py = m->SizeY()/2;
    rID floor_ = FIND("Floor"), chasm = FIND("chasm"), tight = FIND("Winding Corridor"), roomy = FIND("Twisting Chasm");
    for (int x = px-3; x <= px+3; ++x)
        for (int y = py-2; y <= py+2; ++y) {
            if (!m->InBounds(x,y)) continue;
            m->WriteTerra(x,y,(x == px && y == py) ? chasm : floor_);
            m->SetRegion(Rect(x,y,x,y),(x == px && y == py) ? tight : roomy);
            m->At(x,y).Lit = 1;
            m->At(x,y).Memory = m->At(x,y).Glyph;
        }
    if (!p->HasStati(LEVITATION))
        p->GainPermStati(LEVITATION,NULL,SS_MISC);
    p->CalcValues();
    p->PlaceAt(m,px,py);
    Monster *mn = new Monster(FIND("horse"));
    mn->CalcValues();
    mn->PlaceAt(m,px+1,py,true);
    const bool wasPlay = theGame->PlayMode;
    theGame->PlayMode = true;
    mn->Initialize(true);
    theGame->PlayMode = wasPlay;
    csAlly = mn->myHandle;
    p->ts.addCreatureTarget(mn,TargetAlly);
    mn->ts.addCreatureTarget(p,TargetLeader);
    Error("CHASM_SWAP stage ready=%d player=%d,%d ally=%d,%d fall_here=%d player_aerial=%d ally_aerial=%d ally_friendly=%d",
        (int)(m->TerrainAt(px,py) == chasm && p->isAerial() && !mn->isAerial() &&
              mn->isFriendlyTo(p) &&
              TREG(m->RegionAt(px,py))->Size == mn->GetAttr(A_SIZ) &&
              TREG(m->RegionAt(px+1,py))->Size > mn->GetAttr(A_SIZ)),
        (int)p->x,(int)p->y,(int)mn->x,(int)mn->y,
        (int)TTER(m->TerrainAt(px,py))->HasFlag(TF_FALL),
        (int)p->isAerial(),(int)mn->isAerial(),(int)mn->isFriendlyTo(p));
}
