/* inc-lmw4: opt-in probe for the reach of a globe's and a field's first pulse
   against the lasting Field. Off unless INCURSION_AREA_PROBE is set. Called
   from Game::Play (src/Main.cpp); graded by tools/check_area_radius.sh. Output
   goes to errors.log through Error(), one AREA_PROBE line per fact. The field
   first pulse has no creature effect in the engine (MagicXY only throws
   EV_MAGIC_XY), so a hook in Magic::MagicXY records each pulsed square. */
#include "Incursion.h"

extern void (*AreaProbeXYHook)(int16,int16);
static int16 gHitX[400], gHitY[400];
static int gHits;
static void NoteXY(int16 x, int16 y) {
    if (gHits < 400) { gHitX[gHits] = x; gHitY[gHits] = y; ++gHits; }
}
static bool Pulsed(int16 x, int16 y) {
    for (int i = 0; i < gHits; ++i)
        if (gHitX[i] == x && gHitY[i] == y) return true;
    return false;
}

void AreaRadiusProbe(Player *pl) {
    if (!getenv("INCURSION_AREA_PROBE"))
        return;
    if (!pl || !pl->m) {
        Error("AREA_PROBE: INCONCLUSIVE -- no live player and map");
        return;
    }
    const rID blessID = FIND("Bless"), silenceID = FIND("Silence"),
        koboldID = FIND("kobold");
    if (!blessID || !silenceID || !koboldID) {
        Error("AREA_PROBE: INCONCLUSIVE -- missing Bless, Silence or kobold");
        return;
    }
    Map *mp = pl->m;
    const int16 px = pl->x, py = pl->y;
    const bool wasInPlay = theGame->PlayMode;
    theGame->PlayMode = true;
    bool pass = true, ready = true;

    /* Case 1: Bless (AR_GLOBE, lval 6) on allies at distance 5, 6 and 7. */
    const int distances[3] = {5, 6, 7};
    Monster *allies[3] = {NULL, NULL, NULL};
    for (int i = 0; i < 3; ++i) {
        const int d = distances[i];
        int16 tx = -1, ty = -1;
        for (int dx = -d; dx <= d && tx < 0; ++dx)
            for (int dy = -d; dy <= d && tx < 0; ++dy) {
                const int16 nx = px + dx, ny = py + dy;
                if (dist(px, py, nx, ny) != d) continue;
                if (!mp->InBounds(nx, ny) || mp->SolidAt(nx, ny)) continue;
                if (mp->FCreatureAt(nx, ny)) continue;
                tx = nx; ty = ny;
            }
        if (tx < 0) {
            Error("AREA_PROBE: globe dist=%d INCONCLUSIVE -- no open floor", d);
            ready = false;
            continue;
        }
        Monster *mn = allies[i] = new Monster(koboldID);
        TMON(mn->tmID)->GrantGear(mn, mn->tmID, true);
        TMON(mn->tmID)->PEvent(EV_BIRTH, mn, mn->tmID);
        mn->PlaceAt(mp, tx, ty, true);
        mn->Initialize(true);
        pl->ts.addCreatureTarget(mn, TargetAlly);
        mn->ts.addCreatureTarget(pl, TargetLeader);
        if (mn->m != mp || dist(px, py, mn->x, mn->y) != d ||
            !mn->isFriendlyTo(pl) ||
            mn->HasEffStati(ADJUST_MOR, blessID, A_AID)) {
            Error("AREA_PROBE: globe dist=%d INCONCLUSIVE -- invalid ally", d);
            ready = false;
        }
    }
    if (ready) {
        EventInfo xe; xe.Clear();
        xe.EActor = pl; xe.ETarget = pl; xe.EVictim = pl;
        xe.EMap = mp; xe.eID = blessID; xe.isSpell = true;
        ReThrow(EV_EFFECT, xe);
        for (int i = 0; i < 3; ++i) {
            const bool affected =
                allies[i]->GetEffStatiMag(ADJUST_MOR, blessID, A_AID) == 1;
            Error("AREA_PROBE: globe dist=%d affected=%d", distances[i],
                (int)affected);
            pass = pass && (affected == (distances[i] <= 6));
        }
    } else {
        Error("AREA_PROBE: globe INCONCLUSIVE -- target setup incomplete");
        pass = false;
    }
    for (int i = 0; i < 3; ++i)
        if (allies[i]) allies[i]->Remove(true);

    /* Case 2: Silence (AR_FIELD, lval 4) centred on the caster. Compare the
       square the first pulse reached with the square the Field covers. */
    int rad = -1;
    gHits = 0;
    AreaProbeXYHook = NoteXY;
    EventInfo fe; fe.Clear();
    fe.EActor = pl; fe.ETarget = pl; fe.EVictim = pl;
    fe.EMap = mp; fe.eID = silenceID; fe.isSpell = true;
    ReThrow(EV_EFFECT, fe);
    AreaProbeXYHook = NULL;
    Field *f = NULL;
    for (int i = 0; (f = mp->Fields[i]) != NULL; ++i)
        if (f->eID == silenceID && f->cx == px && f->cy == py) { rad = f->rad; break; }
    if (!f || rad != 4) {
        Error("AREA_PROBE: field INCONCLUSIVE -- Silence field not found "
            "with radius 4 (rad=%d)", rad);
        pass = false;
    } else {
        for (int d = 3; d <= 5; ++d) {
            const bool pulse = Pulsed(px + d, py), lasting = f->inArea(px + d, py);
            Error("AREA_PROBE: field dist=%d pulse=%d lasting=%d", d,
                (int)pulse, (int)lasting);
            pass = pass && (pulse == (d <= 4)) && (lasting == (d <= 4));
        }
    }
    mp->RemoveEffField(silenceID);
    theGame->PlayMode = wasInPlay;
    if (pass)
        Error("AREA_PROBE: PASS");
    else
        Error("AREA_PROBE: FAIL -- expected globe dist 5,6 affected=1 and 7 "
            "affected=0; field dist 3,4 pulse=1 lasting=1 and dist 5 both 0");
}
