/* FEATURE.CPP -- See the Incursion LICENSE file for copyright information.

     All of the member functions of Feature and its derived classes
   Door, Portal and Trap. By thematic extension, this file also
   includes many of the functions governing moving from level to
   level, as stairs permit.

     EvReturn Feature::Event(EventInfo &e)

     Portal::Portal(rID _pID) 
     EvReturn Portal::Event(EventInfo &e)
     EvReturn Portal::Enter(EventInfo &e)
     bool Portal::EnterDir(Dir d)

     Door::Door(rID fID)
     Door::~Door()
     void Door::SetImage()
     EvReturn Door::Event(EventInfo &e)

     void Trap::SetImage()
     Trap::~Trap()
     EvReturn Trap::Event(EventInfo &e)
     EvReturn Trap::TriggerTrap(EventInfo &e)

     void Game::EnterLimbo(hObj h, uint8 x, uint8 y, rID mID, 
            int8 Depth, int8 OldDepth, int32 Arrival, const char* Message)
     void Game::LimboCheck(Map *m)
     void Thing::MoveDepth(int16 NewDepth)
     void Player::MoveDepth(int16 NewDepth)
     Map* Game::GetDungeonMap(rID dID, int16 Depth, Player *pl, Map*TownLevel)

*/

#include "Incursion.h"

/* Door redraw probe. Off unless INCURSION_DOOR_PROBE is set to something other
   than 0; writes logs/doorprobe.log, one line per Door::SetImage call.
     It exists because the door bugs of 2026-08-21 -- inc-8zu, inc-wj8, inc-95d
   -- are all about DoorFlags disagreeing with the map, and a screen dump
   cannot tell you which flag bit is wrong. tools/check_broken_door.sh reads
   this log and is the regression check for all three. Reporting only: it never
   repairs, because a check that quietly fixes what it finds destroys the
   evidence it exists to collect.
     Format, one line per redraw:
       door X,Y before=0xBB after=0xAA N=n S=n W=n E=n vert=n horiz=n occ=n
   before and after are DoorFlags either side of the orientation branch; N S W
   E are m->SolidAt of the four neighbours; vert and horiz say which arm of the
   branch the geometry allows; occ says whether a creature stood in the doorway,
   which is the one case where a stale brand is deliberately kept. */
static bool DoorProbeEnabled() {
    static int on = -1;
    if (on < 0) {
        /* The VALUE decides, not the mere presence of the variable -- the same
           trap MapAuditEnabled() documents (src/MapAudit.cpp:34). */
        const char *s = getenv("INCURSION_DOOR_PROBE");
        on = (s && *s && strcmp(s, "0")) ? 1 : 0;
    }
    return on != 0;
}

static FILE *doorProbeLog() {
    static FILE *f = NULL;
    if (!f) {
        char path[1024];
        snprintf(path, sizeof(path), "%slogs/doorprobe.log",
            (const char*)T1->IncursionDirectory);
        f = fopen(path, "a");
    }
    return f;
}

EvReturn Feature::Event(EventInfo &e) {
    EvReturn res;
    res = TFEAT(fID)->Event(e, fID);
    if (res == DONE || res == ERROR)
        return res;
    if (res == NOMSG)
        e.Terse = true;

    switch (e.Event) {
    case EV_TURN:
        UpdateStati();
        return DONE;
    case EV_PLACE:
        x = e.EXVal;
        y = e.EXVal;
        break;
    case EV_STRIKE:
        if (e.ETarget != this)
            return NOTHING;

        bool is_acting;
        is_acting = e.EActor->HasStati(ACTING);
        if (e.AType == A_KICK) {
            DPrint(e, NULL, "The <EActor> kicks the <Obj>.", this);
        } else if (e.EItem)
            DPrint(e, is_acting ? NULL : "You strike the <Obj> with your <EItem>.", "The <EActor> strikes the <Obj> with his <EItem>.", this);
        else
            DPrint(e, is_acting ? NULL : "You <Str> the door.", "The <EActor> <Str2> the door.", Lookup(AttkVerbs1, e.AType), Lookup(AttkVerbs2, e.AType));

        e.vDmg = e.Dmg.Roll();

        if (e.EActor->HasFeat(FT_SUNDER)) {
            e.vDmg *= 2;
            e.strDmg += " (x2 Sunder)";
        }
        if (e.EItem && e.EItem->isWeapon() &&
            ((Weapon *)e.EItem)->HasQuality(WQ_SUNDERING)) {
            e.vDmg *= 2;
            e.strDmg += " (x2 Sundering)";
        }

        res = ReThrow(EV_DAMAGE, e);
        if (e.EItem2 && e.EItem2->isWeapon()) {
            ((Weapon *)e.EItem2)->DoQualityDmgSingle(e);
        }
        if (e.EItem && e.EItem->isWeapon()) {
            ((Weapon *)e.EItem)->DoQualityDmgSingle(e);
        }
        e.EActor->MakeNoise(max(10 - (e.EActor->SkillLevel(SK_MOVE_SIL) / 2), 1));
        if (isDead())
            e.Died = true;
        if (res != NOTHING)
            return res;
        return DONE;
    case EV_DAMAGE:
        if (e.ETarget != this)
            return NOTHING;
        {
            int16 hard;
            String s;
            if (mHP == 0 || cHP == 0)
                return DONE;

            hard = MaterialHardness(TFEAT(fID)->Material, e.DType);
            if (hard <= -1) {
//Immune:
                e.EActor->IPrint("The <Obj> is immune to <Str>.",
                    this, Lookup(DTypeNames, e.DType));
                return DONE;
            }

            if (e.EActor->isPlayer()) {
                if (e.Dmg.Number == 0 && e.Dmg.Sides == 0 && e.Dmg.Bonus == 0) {
                    s = Format("%c%s:%c %d %s", -MAGENTA, (const char*)(Name(0).Capitalize()),
                        -GREY,
                        e.vDmg,
                        Lookup(DTypeNames, e.DType));
                } else {
                    s = Format("%c%s:%c %s%s %s", -MAGENTA, (const char*)(Name(0).Capitalize()),
                        -GREY,
                        (const char*)e.Dmg.Str(),
                        e.strDmg ? (const char*)e.strDmg : "",
                        Lookup(DTypeNames, e.DType));
                    s += Format(" = %d", e.vDmg);
                }

                s += Format(" vs. %d (%s)", hard, (const char*)Lookup(MaterialDescs, TFEAT(fID)->Material));

                e.aDmg = e.vDmg - hard;

                s += Format(" <%d>[%s]<7>",
                    e.vDmg > hard ? EMERALD : PINK,
                    e.vDmg > hard ? (const char*)Format("%d damage", e.aDmg) : "unhurt");


                if (e.EPActor->Opt(OPT_STORE_ROLLS))
                    e.EPActor->MyTerm->AddMessage(SC(XPrint(s)) + SC("\n"));
                e.EPActor->MyTerm->SetWin(WIN_NUMBERS3);
                e.EPActor->MyTerm->Clear();
                e.EPActor->MyTerm->Write(0, 0, XPrint(s));
            }

            // ww: you can get stuck here if your STR is low kicking a door
            // forever ... no way to interrupt actions
            if (e.aDmg > 0) {
                cHP -= e.aDmg;

                if (cHP <= 0) {
                    cHP = 0;

                    switch (e.DType) {
                    case AD_SONI: VPrint(e, NULL, "The <Obj> shatters!", this); break;
                    case AD_ACID: VPrint(e, NULL, "The <Obj> is eaten away!", this); break;
                    case AD_FIRE: VPrint(e, NULL, "The <Obj> burns down!", this); break;
                    default:      VPrint(e, NULL, "The <Obj> is destroyed!", this); break;
                    }
                    SetImage();
                    Hear(e, 20, "You hear a loud *crack*.");
                    e.EActor->RemoveStati(ACTING);
                    e.Died = true;

                    if (e.EActor && e.EMap->FTrapAt(x, y) && e.EActor->isBeside(this)) {
                        e.EActor->IPrint("The <Obj> was trapped!", this);
                        e.EMap->FTrapAt(x, y)->TriggerTrap(e, false);
                    }
                    Remove(true);
                    return NOTHING;
                }
            }
            VPrint(e, NULL, "The <Obj> holds!", this);
            //Message spam...
            //Hear(e,20,"You hear a muffled *thud*.");                         

            if (e.EActor->isPlayer() && e.EPActor->Opt(OPT_REPEAT_KICK) && e.AType == A_KICK) {
                if (!e.EActor->HasStati(ACTING, EV_SATTACK)) {
                    e.EActor->RemoveStati(ACTING);
                    e.EActor->GainPermStati(ACTING, this, SS_MISC, EV_SATTACK, 20);
                } else {
                    int16 mag = e.EActor->GetStatiMag(ACTING);
                    if (mag <= 0) {
                        e.EActor->HaltAction("not broken after 20 attacks", false);
                        if (e.EActor->HasStati(ACTING)) {
                            e.EActor->RemoveStati(ACTING);
                            e.EActor->GainPermStati(ACTING, this, SS_MISC, EV_SATTACK, 20);
                        } else return ABORT;
                    } else {
                        e.EActor->SetStatiMag(ACTING, -1, NULL, mag - 1);
                    }
                }
            }
            return DONE;
        }
    }
    return NOTHING;
}

void Thing::BoostRetry(int16 sk, Creature *c) {
    if (HasStati(RETRY_BONUS, sk, c))
        SetStatiMag(RETRY_BONUS, sk, c, GetStatiMag(RETRY_BONUS, sk, c) + 2);
    else
        GainPermStati(RETRY_BONUS, c, SS_MISC, sk, +4);
}

Portal::Portal(rID _pID) : Feature(TFEAT(_pID)->Image,_pID,T_PORTAL) { }

EvReturn Portal::Event(EventInfo &e) {
    Creature *c;
    EvReturn res;

    switch (e.Event) {
    case PRE(EV_ENTER):
        res = TFEAT(fID)->Event(e, fID);
        if (res == DONE || res == ERROR)
            return res;
        if (res == NOMSG)
            e.Terse = true;
        if (c = (Creature*)e.EActor->GetStatiObj(DWARVEN_FOCUS))
            if (c->m == e.EActor->m) {
                e.EActor->IPrint("You will not flee while the <Obj> still lives!", c);
                return ABORT;
            }
        return NOTHING;
    case EV_ENTER:
        return Enter(e);
    default:
        return NOTHING;
    }
}

/* Where a creature arriving on new_m will really stand, given the square it
   keeps from the level it is leaving. Player::MoveDepth refuses a square that
   is out of bounds, solid, or part of a vault, and re-rolls a random open one
   instead; a refused square therefore cannot be named in advance, and this
   returns false and leaves nx,ny untouched. A safe arrival then steps off a
   falling square when a neighbour is not one.

   Both the placement in Player::MoveDepth and the descent warning in
   Portal::Enter go through here, so the square the player is warned about is
   the square the player gets. They disagreed before: see the upstream note at
   the warning. */
static bool ArrivalSquare(Map *new_m, int16 &nx, int16 &ny, bool safe) {
    int16 i;

    if (!new_m->InBounds(nx, ny) || new_m->SolidAt(nx, ny) ||
        new_m->At(nx, ny).isVault)
        return false;

    if (safe && new_m->FallAt(nx, ny))
        for (i = 0; i != 8; i++)
            if (!new_m->FallAt(nx + DirX[i], ny + DirY[i])) {
                nx += DirX[i];
                ny += DirY[i];
                break;
            }

    return true;
}

/* Diagnostic for inc-wcf. Set INCURSION_STAIR_WARN_PROBE=1 to record what
   the descent warning in Portal::Enter decided and what it decided it from --
   whether the square the player keeps survives MoveDepth's placement rules,
   what terrain sits there, whether the terrain itself calls the square unsafe,
   and whether the player was asked to confirm. tools/check_stair_warn.sh
   recomputes the rule from these facts, so a warning that fires on a safe square and a
   warning that never fires at all both show up as a disagreement rather than
   as a screen somebody has to read. Writes logs/stairwarn.log. */
static void StairWarnProbe(int16 depth, int16 nx, int16 ny, bool usable,
                           rID terID, bool unsafe, bool asked) {
    if (!getenv("INCURSION_STAIR_WARN_PROBE"))
        return;
    static FILE *log = NULL;
    if (!log) {
        char path[1024];
        snprintf(path, sizeof(path), "%slogs/stairwarn.log",
            (const char*)T1->IncursionDirectory);
        log = fopen(path, "a");
    }
    if (!log)
        return;
    fprintf(log, "descend from_depth=%d at=%d,%d usable=%d terrain=\"%s\" "
        "unsafe=%d asked=%d\n", (int)depth, (int)nx, (int)ny, (int)usable,
        terID ? (const char*)NAME(terID) : "-", (int)unsafe, (int)asked);
    fflush(log);
}

EvReturn Portal::Enter(EventInfo &e) {
    int8 DepthMod;
    Map * new_m;
    EvReturn res;

    res = TFEAT(fID)->Event(e, fID);
    if (res == DONE || res == ERROR)
        return res;
    if (res == NOMSG)
        e.Terse = true;

    e.EActor->Timeout += 30;

    switch (TFEAT(fID)->xval) {
    case POR_DOWN_STAIR:
    case POR_UP_STAIR:
        DepthMod = TFEAT(fID)->xval == POR_DOWN_STAIR ? 1 : -1;
        if (!m->dID) {
            Error("Up/down stairs located outside dungeon!");
            return ABORT;
        }

        if (e.EActor->isPlayer() && DepthMod == 1) {
            new_m = theGame->GetDungeonMap(m->dID, m->Depth + DepthMod, e.EPActor, NULL);
            if (new_m != NULL){
                int16 nx = e.EActor->x, ny = e.EActor->y;
                /* upstream: base-code defect, the fix is ours. Tracked as
                   inc-wcf. NOT SENT to rmtew. Tier Observed: restoring the
                   repro save on a down staircase and pressing '>' printed
                   "The stair leads to Dungeon Wall. Confirm unsafe action?",
                   and the square named is solid (docs/evidence/inc-wcf/).
                   It is upstream's and not a port artefact: the prompt, the
                   commented-out test and MoveDepth's placement are all plain
                   C++ with no dependence on platform, compiler or type width,
                   so a Win32 build with the original typedefs prompts the same
                   way. Run tools/check_stair_warn.sh.

                   The warning asked about every square, and about the wrong
                   square. It tested only InBounds, because the test that
                   decided whether the square was unsafe was commented out
                   above the prompt (rmtew, a731043, 2014-07-15). And the
                   square it named is one Player::MoveDepth throws away:
                   MoveDepth refuses a solid or vault square and re-rolls a
                   random open one, so the one terrain that makes the warning
                   frightening is the one terrain that guarantees the warning
                   is wrong. The square now comes from ArrivalSquare, which is
                   what MoveDepth places with, and the terrain's own
                   EV_MON_CONSIDER -- the test that was commented out, and the
                   same one Move.cpp:477 uses to ask a walking player about
                   deep water -- decides whether to ask at all.

                   A refused square cannot be named: MoveDepth re-rolls it at
                   random, after this point and with this map's RNG, so there
                   is nothing honest to put in the message. Saying nothing is
                   right, because a re-rolled square is never solid. */
                bool usable = ArrivalSquare(new_m, nx, ny, true);
                rID terID = usable ? new_m->TerrainAt(nx, ny) : 0;
                bool unsafe = usable &&
                    TTER(new_m->PTerrainAt(nx, ny, e.EActor))->PEvent(
                        EV_MON_CONSIDER, e.EActor, terID) == ABORT;
                bool asked = false;

                if (unsafe) {
                    asked = true;
                    if (!e.EActor->yn(XPrint("The stair leads to <Res>. "
                            "Confirm unsafe action?", terID), true)) {
                        StairWarnProbe(m->Depth, nx, ny, usable, terID,
                            unsafe, asked);
                        return ABORT;
                    }
                }

                StairWarnProbe(m->Depth, nx, ny, usable, terID, unsafe, asked);
            }
        }

        e.EActor->MoveDepth(m->Depth + DepthMod, true);
        return DONE;
    case POR_DUN_ENTRY:
        if (!e.EActor->isPlayer())
            return ABORT;
        /* Changed TownLevel from m to NULL for Rope Trick; fix later */
        new_m = theGame->GetDungeonMap(TFEAT(fID)->xID, 1, (Player*)e.EActor, NULL);
        //          e.EActor->PlaceAt(new_m,e.EActor->GetX(),e.EActor->GetY());
        e.EActor->RemoveEffStati(fID);
        e.EActor->GainPermStati(ENTERED_AT, this, SS_MISC, 0, 0, fID);
        e.EActor->PlaceAt(new_m, new_m->EnterX, new_m->EnterY);
        return DONE;
    case POR_RETURN:
        Status *S;
        S = e.EActor->GetEffStati(ENTERED_AT, TFEAT(fID)->xID);
        if (S)  {
            Thing * t = oThing(S->h);
            ASSERT(t->m);
            e.EActor->PlaceAt(t->m, t->x, t->y);
            e.EActor->RemoveEffStati(((Feature*)t)->fID);
            return DONE;
        } else {
            /* Later, scan the entire game and place the player at
               the first found Portal object that matches the Portal's
               target. */
            Error("Returning to a portal you never entered!");
            return ABORT;
        }
        break;
    default:
        Error("Strange Portal xval (%d).", (int)TFEAT(fID)->xval);
        return DONE;
    }
}

bool Portal::EnterDir(Dir d) {
    switch (TFEAT(fID)->xval) {
    case POR_UP_STAIR:
        return d == UP;
    case POR_DOWN_STAIR:
        return d == DOWN;
    default:
        if ((Image & GLYPH_ID_MASK) == GLYPH_ID(GLYPH_DSTAIRS))
            return d == DOWN;
        if ((Image & GLYPH_ID_MASK) == GLYPH_ID(GLYPH_USTAIRS))
            return d == UP;
        return d == CENTER;
    }
}

Door::Door(rID fID) : Feature(TFEAT(fID)->Image, fID, T_DOOR) {
#ifndef WEIMER
    DoorFlags = 0;
    if (!random(10))
        DoorFlags |= DF_OPEN;
    else {
        Flags |= F_SOLID;
        if (!random(2))
            DoorFlags |= DF_LOCKED;
    }
    if (!random(7)) {
        DoorFlags &= ~DF_OPEN;
        DoorFlags |= DF_SECRET;
        if (!random(2))
            DoorFlags |= DF_LOCKED;
    }
#else
    DoorFlags = DF_LOCKED;
    Flags |= F_SOLID;

    // ww: all doors start out closed and locked
    // fjm: WHY?!

    if(!random(7)) 
        DoorFlags |= DF_SECRET;

#endif
}

Door::~Door() {
}

void Door::SetImage() {
    if (!m || x == -1)
        return;

    Image = TFEAT(fID)->Image;
    Image &= GLYPH_ATTR_MASK;

    if (HasStati(WIZLOCK))
        Image |= GLYPH_BACK(RED);

    if (DoorFlags & DF_OPEN)
        DoorFlags &= ~(DF_LOCKED | DF_SECRET);

    /* upstream: base-code defect. Observed. inc-95d. Not sent.
         This brands a door DF_BROKEN when it can read no doorframe, and the
       brand used to be permanent. SetImage runs during level generation,
       before the walls beside a door exist, so an ordinary door got branded
       and then kept the brand for the rest of the game after its frame was
       built. From that point the engine treated a whole door as a
       hole: At(x,y).Solid went false, EV_CLOSE refused it forever ("That door
       is broken, and no longer closes."), isDead() called it destroyed, and
       the route search would not path through it (inc-8zu).
         Clearing the brand is safe because of an invariant the tree keeps:
       a door that was really smashed always carries DF_OPEN as well. Only two
       places set DF_BROKEN -- this branch, alone, and the damage path below,
       which sets DF_OPEN | DF_BROKEN together (src/Feature.cpp:732). Only two
       places clear DF_OPEN -- the constructor, before any door can be broken,
       and EV_CLOSE, which refuses a broken door before it gets there
       (src/Feature.cpp:630-650). So DF_BROKEN without DF_OPEN can only be this
       branch's own mark, and only that combination is cleared here.
         The doorway must be empty first. Un-branding turns the square solid,
       and doing that under a creature would bury it in a wall. A door whose
       doorway is occupied simply keeps the brand until the square clears,
       which is what a real door does.
         Not a port artefact: the branch, the flag and the stickiness are all
       upstream's, and a Win32 build with the original typedefs brands the same
       doors. The evidence is seed 7 through tools/keys/dive12.keys, 3029
       redraws over 446 doors, against a build differing in nothing else:
       stale brands surviving a readable-frame redraw 42 -> 0, doors ending
       closed and branded broken 6 -> 0, and 14 of the 63 brand events hit a
       LOCKED door and so made a locked door walkable. Guarded by
       tools/check_broken_door.sh. */
    int8 wasFlags = DoorFlags;

    if (m->SolidAt(x, y - 1) && m->SolidAt(x, y + 1)) {
        DoorFlags |= DF_VERTICAL;
        if ((DoorFlags & DF_BROKEN) && !(DoorFlags & DF_OPEN) &&
            !m->MCreatureAt(x, y))
            DoorFlags &= ~DF_BROKEN;
    } else if (m->SolidAt(x - 1, y) && m->SolidAt(x + 1, y)) {
        DoorFlags &= ~DF_VERTICAL;
        if ((DoorFlags & DF_BROKEN) && !(DoorFlags & DF_OPEN) &&
            !m->MCreatureAt(x, y))
            DoorFlags &= ~DF_BROKEN;
    } else
        DoorFlags |= DF_BROKEN;

    if (DoorProbeEnabled()) {
        FILE *pf = doorProbeLog();
        if (pf) {
            bool vert  = m->SolidAt(x, y - 1) && m->SolidAt(x, y + 1);
            bool horiz = m->SolidAt(x - 1, y) && m->SolidAt(x + 1, y);
            fprintf(pf, "door %d,%d before=0x%02x after=0x%02x "
                "N=%d S=%d W=%d E=%d vert=%d horiz=%d occ=%d\n",
                (int)x, (int)y, (unsigned char)wasFlags,
                (unsigned char)DoorFlags,
                (int)m->SolidAt(x, y - 1), (int)m->SolidAt(x, y + 1),
                (int)m->SolidAt(x - 1, y), (int)m->SolidAt(x + 1, y),
                (int)vert, (int)horiz, (int)m->MCreatureAt(x, y));
            fflush(pf);
        }
    }

    if (DoorFlags & DF_SECRET) {
        Flags |= F_INVIS;

        if (DoorFlags & DF_VERTICAL) {
            m->At(x, y).Glyph = m->At(x, y + 1).Glyph;
            m->At(x, y).Shade = m->At(x, y + 1).Shade;
            m->At(x, y).Solid = true;
            m->At(x, y).Opaque = true;
        } else {
            m->At(x, y).Glyph = m->At(x + 1, y).Glyph;
            m->At(x, y).Shade = m->At(x + 1, y).Shade;
            m->At(x, y).Solid = true;
            m->At(x, y).Opaque = true;
        }
    } else {
        Flags &= ~F_INVIS;

        m->At(x, y).Glyph = TTER(m->TerrainAt(x, y))->Image;
        m->At(x, y).Shade = TTER(m->TerrainAt(x, y))->HasFlag(TF_SHADE);
        if (DoorFlags & (DF_OPEN | DF_BROKEN)) {
            /* Used to refer to Terrain -- why not? */
            m->At(x, y).Solid = false;
            m->At(x, y).Opaque = false;
            Flags &= ~F_SOLID;
        } else {
            m->At(x, y).Solid = true;
            m->At(x, y).Opaque = true;
            /* upstream: the passable arm above clears F_SOLID, and nothing
               here put it back, so a door that stopped being passable left the
               map square solid and the feature not. EV_CLOSE sets it by hand
               (src/Feature.cpp:649), which is the tree admitting the two views
               have to agree; this is the same line at the place that decides.
               It matters now because un-branding a stale DF_BROKEN above takes
               exactly this arm. Reasoned from the two views' other users.
               inc-95d. Not sent. */
            Flags |= F_SOLID;
        }

        if (DoorFlags & DF_BROKEN)
            Image += GLYPH_BDOOR;
        else if (DoorFlags & DF_VERTICAL)
            Image += ((DoorFlags & DF_OPEN) ? '+' : GLYPH_VLINE);
        else
            Image += ((DoorFlags & DF_OPEN) ? '+' : GLYPH_HLINE);
    }

    if (theGame->InPlay())
        m->VUpdate(x, y);
}

EvReturn Door::Event(EventInfo &e) {
    EvReturn res;
    int16 hard, hardwizlock, diff;
    String s;
    res = TFEAT(fID)->Event(e,fID);
    if (res == DONE || res == ERROR)
        return res;
    if (res == NOMSG)
        e.Terse = true;

    switch(e.Event) {
    case EV_TURN: 
        UpdateStati();
        return DONE; 
    case EV_OPEN:
        if (e.EActor->HasMFlag(M_NOHANDS)) { 
            e.EActor->IPrint("But you have no hands."); return ABORT; 
        } else if (e.EActor->onPlane() != PHASE_MATERIAL) { 
            e.EActor->IPrint("Your hands pass through the <Obj>.",this); 
            return ABORT; 
        } else if (DoorFlags & DF_BROKEN) { 
            e.EActor->IPrint("It's open, permanently.",this); 
            // ww: sanity
            Flags &= ~F_SOLID;
            DoorFlags |= DF_OPEN;
            DoorFlags &= ~DF_SECRET;
            m->At(x,y).Glyph = TTER(m->TerrainAt(x,y))->Image;
            m->At(x,y).Shade = TTER(m->TerrainAt(x,y))->HasFlag(TF_SHADE);
            m->At(x,y).Solid = false; 
            m->At(x,y).Opaque = TTER(m->TerrainAt(x,y))->HasFlag(TF_OPAQUE);
            SetImage();
            return ABORT; 
        } else if (DoorFlags & DF_OPEN) { 
            e.EActor->IPrint("The <Obj> is already open.",this); return ABORT; 
        } else if (DoorFlags & DF_LOCKED && !HasStati(WIZLOCK,-1,e.EActor) &&
            !e.EActor->HasEffStati(HOME_REGION,m->RegionAt(x,y))) {

                if (e.EActor->HasStati(RAGING))
                    goto TryKicking;

                if (HasStati(TRIED, SK_LOCKPICKING, e.EActor)) { 
                    e.EActor->IPrint("You have already tried to pick the lock on the <Obj>.",this);
                    if (e.EActor->isPlayer() && e.EPActor->Opt(OPT_AUTOKICK))
                        return e.EActor->TryToDestroyThing(this);
                    else
                        return DONE;
                } 
                e.EActor->IPrint("The <Obj> is locked.",this);
                /* Players can attempt to pick locks without the skill; monsters
                can not. This avoids players herding around charmed creatures
                as lockpicks, and other abuses. 
                ww: That is not a problem, really! 
                fjm: It may be, once I add the Diplomacy stuff. Also, monsters
                currently move to the player too quickly -- you meet a whole
                bunch, and then you wander through a bunch of empty rooms. This
                might be part of the issue.
                */
                if (e.EActor->isMonster() && !e.EActor->HasSkill(SK_LOCKPICKING))
                    return ABORT;

                if (!((e.EActor->isPlayer() && ((Player *)e.EActor)->Opt(OPT_AUTOOPEN)) || e.EActor->yn("Pick the lock?",true)))
                    return ABORT;
                // ww: trying to pick it takes time: a full-round action, pass or
                // fail


                e.EActor->Timeout += 30;
                diff = 14 + m->Depth;
                if (HasStati(WIZLOCK) && !HasStati(WIZLOCK,-1,e.EActor)) {
                    e.EActor->IPrint("The <Obj> is more difficult to pick.",this);
                    diff += 10; 
                }
                if (e.EActor->SkillCheck(SK_LOCKPICKING,diff,true,
                    GetStatiMag(RETRY_BONUS,SK_LOCKPICKING,e.EActor),"retry")) { 
                        e.EActor->IDPrint("You pick the lock!",
                            "The <Obj> picks the lock on the <Obj>.",
                            e.EActor, this);
                        DoorFlags &= ~DF_LOCKED;
                        RemoveStati(TRIED,SS_MISC,SK_LOCKPICKING); 

                        if (!HasStati(TRIED,DF_LOCKED,this) && 
                            !HasStati(SUMMONED,-1,this)) {
                                // see DisarmTrap() 
                                e.EActor->GainXP(90 + (diff - 14) * 10);
                                GainPermStati(TRIED,this,SS_ATTK,DF_LOCKED);
                        }

                } else { 
                    e.EActor->IDPrint("You fail to pick the lock on the <Obj2>. (You can try again after resting.)",
                        "The <Obj1> tries to pick the lock on the <Obj2>, but fails.",
                        e.EActor, this);
                    BoostRetry(SK_LOCKPICKING,e.EActor);
                    GainTempStati(TRIED,e.EActor,-2,SS_MISC,SK_LOCKPICKING); 

TryKicking:
                    if (e.EActor->isPlayer() && 
                        ((Player *)e.EActor)->Opt(OPT_AUTOKICK)) {
                            return e.EActor->TryToDestroyThing(this); 
                    } 
                    return ABORT; 
                }
        }
        // else: just open it
        if (HasStati(WIZLOCK,-1,e.EActor)) {
            e.EActor->Timeout += 0;
            e.EActor->IPrint("The <Obj> opens at your mental command.",this);
        } else {
            e.EActor->Timeout += 15;
            e.EActor->IPrint("The <Obj> opens.",this);
        }
        e.EActor->IPrint("The door opens.");
        Flags &= ~F_SOLID;
        DoorFlags |= DF_OPEN;
        DoorFlags &= ~DF_SECRET;
        m->At(x,y).Glyph = TTER(m->TerrainAt(x,y))->Image;
        m->At(x,y).Shade = TTER(m->TerrainAt(x,y))->HasFlag(TF_SHADE);
        m->At(x,y).Solid = false; 
        m->At(x,y).Opaque = TTER(m->TerrainAt(x,y))->HasFlag(TF_OPAQUE);

        SetImage();
        /*
        if (e.EActor->isPlayer())
        if (TREG(m->RegionAt(x,y))->HasFlag(RF_AUTODESC))
        if (!REGMEM(m->RegionAt(x,y))->Seen) {
        REGMEM(m->RegionAt(x,y))->Seen = true;
        ((Player*)e.EActor)->MyTerm->Box(WIN_SCREEN,0,AZURE,GREY,
        m->DescribeReg(x,y));
        }*/
        return DONE;
    case EV_CLOSE:
        if (e.EActor->HasMFlag(M_NOHANDS)) {
            e.EActor->IPrint("But you have no hands.");
            return ABORT;
        }
        if (e.EActor->onPlane() != PHASE_MATERIAL) {
            e.EActor->IPrint("Your hands pass through the <Obj>.",this);
            return ABORT;
        }
        if (DoorFlags & DF_BROKEN) {
            e.EActor->IPrint("That door is broken, and no longer closes.");
            return ABORT;
        }
        if (!(DoorFlags & DF_OPEN)) {
            e.EActor->IPrint("It's already closed.");
            return ABORT;
        }
        e.EActor->IPrint("The <Obj> closes.",this);
        e.EActor->Timeout += 15;
        Flags |= F_SOLID;
        DoorFlags &= ~DF_OPEN;
        SetImage();
        return DONE; 
    case EV_DAMAGE:     
        if (e.ETarget != this)
            return NOTHING;

        if (e.EActor->onPlane() != onPlane()) {
            DPrint(e, "Your attack passes through the <ETarget>.",
                "The <EActor>'s attack passes through the <ETarget>.");
            return DONE;
        }
        if ((DoorFlags & (DF_OPEN|DF_BROKEN)) && e.AType == A_KICK)
            return DONE; 
        if (e.AType == A_SWNG && (!e.EItem || !e.EItem->HasIFlag(WT_BLUNT)))
            e.vDmg /= 3;
        if (e.DType == AD_PIERCE && !(e.EItem && e.EItem->HasIFlag(WT_BLUNT))
            && !(e.EItem && e.EItem->HasIFlag(WT_SLASHING)))
            goto Immune;

        hard = MaterialHardness(TFEAT(fID)->Material,e.DType);
        if (hard <= -1) {
Immune:
            e.EActor->IPrint("The <Obj> is immune to <Str>.",
                this,Lookup(DTypeNames,e.DType));
            return DONE; 
        } 

        hardwizlock = 0;
        if (HasStati(WIZLOCK))
            hardwizlock = 2;

        if (e.EActor->isPlayer()) {
            if (e.Dmg.Number == 0 && e.Dmg.Sides == 0 && e.Dmg.Bonus == 0) {
                s = Format("%c%s:%c %d %s", -MAGENTA, (const char*)(Name(0).Capitalize()),
                    -GREY,
                    e.vDmg,
                    Lookup(DTypeNames,e.DType));
            } else { 
                s = Format("%c%s:%c %s%s %s", -MAGENTA, (const char*)(Name(0).Capitalize()),
                    -GREY,
                    (const char*)e.Dmg.Str(),
                    e.strDmg ? (const char*)e.strDmg : "",
                    Lookup(DTypeNames,e.DType));
                s += Format(" = %d",e.vDmg);
            }

            s += Format(" vs. %d (%s)",hard,(const char*)Lookup(MaterialDescs,TFEAT(fID)->Material));

            if (hardwizlock) {
                hard *= hardwizlock;
                s += Format(" x%d (wizlock) = %d",hardwizlock,hard);
            }

            s += Format(" <%d>[%s]<7>",
                e.vDmg > hard ? EMERALD : PINK,
                e.vDmg > hard ? (const char*)Format("%d damage",e.aDmg) : "unhurt");

            if (e.EPActor->Opt(OPT_STORE_ROLLS))
                e.EPActor->MyTerm->AddMessage(SC(XPrint(s)) + SC("\n"));
            e.EPActor->MyTerm->SetWin(WIN_NUMBERS3);
            e.EPActor->MyTerm->Clear();
            e.EPActor->MyTerm->Write(0,0,XPrint(s));
        }

        e.aDmg = e.vDmg - hard; 

        // ww: you can get stuck here if your STR is low kicking a door
        // forever ... no way to interrupt actions
        if (e.aDmg > 0) { 
            cHP -= e.aDmg;

            if (cHP <= 0) { 
                cHP = 0; 

                switch (e.DType) {
                case AD_SONI: VPrint(e,NULL,"The <Obj> shatters!",this); break;
                case AD_ACID: VPrint(e,NULL,"The <Obj> is eaten away!",this); break;
                case AD_FIRE: VPrint(e,NULL,"The <Obj> burns down!",this); break;
                default:      VPrint(e,NULL,"The <Obj> breaks open!",this); break;
                }
                DoorFlags &= (DF_LOCKED | DF_SECRET);
                DoorFlags |= DF_OPEN | DF_BROKEN; 
                SetImage();
                Hear(e,20,"You hear a loud *crack*.");
                e.EActor->RemoveStati(ACTING); 
                e.Died = true; 

                if (e.EActor->isCharacter() && !HasStati(TRIED,945))
                    e.EActor->Exercise(A_STR,random(12)+1,ESTR_DOOR,35);

                if (e.EActor && e.EMap->FTrapAt(x,y) && e.EActor->isBeside(this)) {
                    e.EActor->IPrint("The <Obj> was trapped!",this);
                    e.EMap->FTrapAt(x,y)->TriggerTrap(e,false);
                } 
                return NOTHING; 
            } 
        } 

        if (e.EActor->isCharacter() && !HasStati(TRIED,945))
            GainPermStati(TRIED,e.EActor,SS_MISC,945);

        // fjm: Short, onomatopic messages for repeating strikes
        // to objects avoid annoying message spam when battering
        // on doors in the dungeon.
        e.EActor->IPrint("WHAMM!");
        if (e.EActor->isPlayer() && !e.EPActor->Opt(OPT_REPEAT_KICK))
            e.EActor->IPrint("The <Obj> holds!",this);

        //Hear(e,20,"You hear a muffled *thud*.");                         

        if (e.EActor->isPlayer() && e.EPActor->Opt(OPT_REPEAT_KICK) &&
            e.AType == A_KICK) {
                if (!e.EActor->HasStati(ACTING,EV_SATTACK)) {
                    e.EActor->RemoveStati(ACTING);
                    e.EActor->GainPermStati(ACTING,this,SS_MISC,EV_SATTACK,20);
                } else {
                    int16 mag = e.EActor->GetStatiMag(ACTING);
                    if (mag <= 0) {
                        e.EActor->HaltAction("not broken after 20 attacks", false); 
                        if (e.EActor->HasStati(ACTING)) {
                            e.EActor->RemoveStati(ACTING); 
                            e.EActor->GainPermStati(ACTING,this,SS_MISC,EV_SATTACK,20);
                        } else return ABORT; 
                    } else {
                        e.EActor->SetStatiMag(ACTING,-1,NULL,mag-1);
                    } 
                } 
        }
        return DONE;

    default:
        return NOTHING;
    }
}

/***************************************************************\
 *                              TRAPS                          *
\***************************************************************/

void Trap::SetImage() {
    if (TrapFlags & TS_DISARMED)
        Image = GLYPH_VALUE(GLYPH_DISARMED, TEFF(tID)->ef.cval);
    else
        Image = GLYPH_VALUE(GLYPH_TRAP, TEFF(tID)->ef.cval);

    if (TrapFlags & TS_FOUND)
        Flags &= ~F_INVIS;
    else
        Flags |= F_INVIS;

    if (theGame->InPlay() && x != -1)
        m->Update(x, y);
}

Trap::~Trap() {
    TrapFlags |= TS_FOUND;
    SetImage();
}

EvReturn Trap::Event(EventInfo &e) {
    return NOTHING;
}

EvReturn Trap::TriggerTrap(EventInfo &e, bool foundBefore) {
    EvReturn r; Creature *cr;
    // ww: if the trap is not mundane, you get a saving throw vs. magic to
    // dodge it -- otherwise the polymorph trap always works on the drow
    // elf with +6 million magic resistance, which is not expected
    TEffect *te = TEFF(tID);

    if (TrapFlags & TS_DISARMED)
        return NOTHING;

    if (!foundBefore)
        for (int i = 0; i != MAX_PLAYERS; i++)
            if (theGame->GetPlayer(i))
                if (theGame->GetPlayer(i)->Perceives(e.EActor)) {
                    TrapFlags |= TS_FOUND;
                    SetImage();
                }

    uint32 saveType = SA_TRAPS;
    if (!(te->HasFlag(EF_MUNDANE)))
        saveType |= SA_MAGIC;

    int16 trapDC = 15 + te->Level;
    if (!foundBefore)
        trapDC += 5;

    if ((foundBefore && e.EActor->HasFeat(FT_FEATHERFOOT)) ||
        (te->ef.sval != NOSAVE &&
        e.EActor->SavingThrow(te->ef.sval, trapDC, saveType))) {
        e.EActor->IDPrint("You avoid the effects of a <Obj2>!",
            "The <Obj> avoids the effects of a <Obj2>!", e.EActor, this);
        return DONE;
    }
    e.EActor->IDPrint("You fall victim to a <Obj2>!",
        "The <Obj> falls victim to a <Obj2>!", e.EActor, this);

    /* Move this up here so that dispelling traps don't go into an
       infinite loop dispelling themselves! */
    TrapFlags |= TS_DISARMED;
    SetImage();


    e.isTrap = true;
    e.vCasterLev = 12;
    e.eID = tID;

    e.EItem = (Item*)this;
    e.EVictim = e.EActor;

    e.EVictim->Reveal(false);
    e.EVictim->MakeNoise(30);
    if (e.EVictim->HasStati(ACTING))
        e.EVictim->HaltAction("trap triggered");
    r = ReThrow(EV_EFFECT, e);
    if (r != DONE)
        return r;

    if (cr = (Creature*)GetStatiObj(RESET_BY))
        if (e.EActor->isHostileTo(cr)) {
            /* If your trap killed a hostile monster, get kill XP... */
            if (e.EActor->isDead()) {
                cr->KillXP(e.EActor);
                cr->gainFavour(FIND("Semirath"), e.EActor->ChallengeRating() * 50, false, true);
            }
            /* ...but most traps don't kill, they weaken, so give a
               special trap award for using them -- but only give it
               once per trap! */
            if (!HasStati(XP_GAINED, -1, cr)) {
                cr->GainXP(100 + 25 * e.EActor->ChallengeRating());
                cr->gainFavour(FIND("Semirath"), e.EActor->ChallengeRating() * 50, false, true);
                GainPermStati(XP_GAINED, cr, SS_MISC);
            }
        }

    if (m && x != -1)
        m->Update(x, y);
    return r;

}

/***************************************************************
 * Limbo:                                                      *
 *   Limbo is where monsters go when they leave a level. A     *
 * monster who falls into a level-dropping pit enters limbo.   *
 * Monsters that pursue the player across levels enter limbo   *
 * when the player does, and emerge on the player's new level  *
 * a few turns later. When the player climbs the stairs and    *
 * there are monsters nearby that have him as their current    *
 * target, there is a chance each decides to use the stairs,   *
 * and is thus tossed into limbo, following the player to the  *
 * next level. And so forth.                                   *
 ***************************************************************/

void Game::EnterLimbo(hObj h, uint8 x, uint8 y, rID mID, int8 Depth, int8 OldDepth, int32 Arrival, const char* Message) {
    LimboEntry *lr;
    lr = Limbo.NewItem();
    lr->h = h; lr->x = x; lr->y = y;
    lr->mID = mID; lr->Depth = Depth;
    lr->OldDepth = lr->OldDepth;
    lr->Arrival = Arrival;
    lr->Message = Message;
    oThing(h)->Remove(false);
}

void Game::LimboCheck(Map *m) {
    int16 i;
    Player *p;

Restart:
    for (i = 0; Limbo[i]; i++)
        if (Limbo[i]->Arrival >= Turn) {
            if (Limbo[i]->Target)
                if (oThing(Limbo[i]->Target)->isPlayer()) {
                    p = oPlayer(Limbo[i]->Target);
                    if (Limbo[i]->x > 0)
                        oThing(Limbo[i]->h)->PlaceAt(p->m, Limbo[i]->x, Limbo[i]->y);
                    else
                        /* PlaceAt calls PlaceNear automatically. */
                        oThing(Limbo[i]->h)->PlaceAt(p->m, p->x, p->y);
                    //oThing(Limbo[i]->h)->IDPrint(NULL,Limbo[i]->Message);
                    Limbo.Remove(i);
                    goto Restart;
                }

            if (/*m->mID == Limbo[i]->mID ||*/ m->dID == Limbo[i]->mID)
                if (m->Depth == Limbo[i]->Depth) {
                    oThing(Limbo[i]->h)->PlaceAt(p->m, Limbo[i]->x, Limbo[i]->y);
                    //oThing(Limbo[i]->h)->IDPrint(NULL,Limbo[i]->Message);
                    Limbo.Remove(i);
                    goto Restart;
                }
        }
}

void Thing::MoveDepth(int16 NewDepth, bool safe) {
    Remove(true);
}

/* Temporary diagnostic: set INCURSION_STACK_PROBE=1 to measure what one level
   of the MoveDepth -> PlaceAt -> TerrainEffects -> MoveDepth cycle really
   costs in stack, instead of reading it off the function prologues. Each entry
   to Player::MoveDepth records its own frame address and the distance to the
   frame of the call that is still open above it; that distance IS the cost of
   one level descended, including everything the compiler did that the prologue
   does not show. Writes logs/stackprobe.log.

   READ THE NUMBERS WITH THIS IN MIND. The probe is a local of the function it
   measures, so it inflates that frame by its own size. On arm64 -O2 that is 16
   bytes, and it is visible in the binary: a build carrying this probe allocates
   'sub sp, sp, #0x240' where a build without it allocates '#0x230'. So the
   logged per_level of 2416 means 2400 in a shipping build. Subtract the
   difference between those two immediates before quoting a figure anywhere.

   A per_level of 0 is not a measurement. It means nest=1, an outermost call
   with nothing above it to measure against -- an ordinary stairway descent
   rather than a chained fall. Only nest>=2 lines carry a cost.

   Delete with inc-upw.15. */
struct MoveDepthStackProbe {
    static int16 Nest;
    static char *Frames[64];
    bool On;
    MoveDepthStackProbe(int16 mapDepth, char *frame) {
        On = getenv("INCURSION_STACK_PROBE") != NULL;
        if (!On)
            return;
        static FILE *log = NULL;
        if (!log) {
            char path[1024];
            snprintf(path, sizeof(path), "%slogs/stackprobe.log",
                (const char*)T1->IncursionDirectory);
            log = fopen(path, "a");
        }
        if (log) {
            /* The stack grows downward, so an outer frame sits at a HIGHER
               address than the inner one it called. */
            long delta = (Nest > 0 && Nest <= 64) ?
                (long)(Frames[Nest - 1] - frame) : 0;
            fprintf(log, "MoveDepth nest=%d map_depth=%d frame=%p per_level=%ld\n",
                (int)Nest + 1, (int)mapDepth, (void*)frame, delta);
            fflush(log);
        }
        if (Nest < 64)
            Frames[Nest] = frame;
        Nest++;
    }
    ~MoveDepthStackProbe() {
        if (On)
            Nest--;
    }
};
int16 MoveDepthStackProbe::Nest = 0;
char *MoveDepthStackProbe::Frames[64];

/* Temporary diagnostic: set INCURSION_GOWITH_PROBE=1 to watch the GoWith array
   across a nested MoveDepth. It prints the array's ADDRESS, so a build carrying
   `static Thing *GoWith[64]` shows the same address at every nesting level and
   a build without the static shows a different one per frame. It prints the
   entries twice per call -- once when collection finishes, once immediately
   before the placement loop reads them -- so a value that changed in between
   is visible without any inference.

   The nest counter is separate from MoveDepthStackProbe's, which only counts
   when its own variable is set. Delete with inc-upw.15. */
struct MoveDepthNest {
    static int16 Level;
    MoveDepthNest()  { Level++; }
    ~MoveDepthNest() { Level--; }
};
int16 MoveDepthNest::Level = 0;

static void GoWithProbe(const char *when, int16 mapDepth, Thing **arr, int16 gwc)
{
    if (!getenv("INCURSION_GOWITH_PROBE"))
        return;
    static FILE *log = NULL;
    if (!log) {
        char path[1024];
        snprintf(path, sizeof(path), "%slogs/gowithprobe.log",
            (const char*)T1->IncursionDirectory);
        log = fopen(path, "a");
    }
    if (!log)
        return;
    fprintf(log, "%-9s nest=%d depth=%d array=%p gwc=%d entries=[",
        when, (int)MoveDepthNest::Level, (int)mapDepth, (void*)arr, (int)gwc);
    for (int16 j = 0; j < gwc && j < 8; j++)
        fprintf(log, j ? ",%p" : "%p", (void*)arr[j]);
    fprintf(log, "]\n");
    fflush(log);
}

void Player::MoveDepth(int16 NewDepth, bool safe) {
    /* upstream: base-code defect, the fix is ours. It is upstream's because a
       static array in a function that re-enters itself is clobbered on Win32
       with the original typedefs exactly as it is here; nothing depends on
       platform, compiler or type width. Tier Reasoned, and deliberately so --
       this was committed as a segfault fix in b3b5351 and that claim was
       RETRACTED in 668043c. A controlled A/B over 250 seeds had the same seed
       crashing identically with and without the change, on the same stack. The
       re-entrancy is real and the stack proves it, so this is kept as
       hardening and nothing more. Tracked as inc-upw.15. SENT to rmtew as pull
       request #43, explicitly as hardening and NOT as a crash fix; still open.

       Not static. This function re-enters itself: PlaceAt below fires the new
       square's terrain, and terrain can move the player another level
       (Feature.cpp:260, Move.cpp:1380). With one shared array the inner call
       refilled it, and the outer call then walked its OWN count over the
       inner call's contents and dereferenced a creature that had already been
       moved -- a NULL dereference inside MoveDepth, with MoveDepth further
       down the same stack, and no log at all because nothing calls Error().
       512 bytes of stack is a small price for re-entrancy. */
    Thing *GoWith[64]; Creature *c;
    rID mID; Map *new_m = NULL; int16 nx, ny, i, gwc;
    MoveDepthStackProbe stackProbe(m->Depth, (char*)__builtin_frame_address(0));
    MoveDepthNest nestTracker;
    StoreLevelStats((uint8)m->Depth);
    theGame->SaveGame(*this);

    RemoveStati(SPRINTING);
    /* upstream: base-code defect, the fix is ours. inc-6d5. Tier Observed:
       tools/soak.sh 24 1 tools/keys/dive.keys, seed 21, turn 198048 -- the
       error below is present before this change and absent after, and the
       40-seed gate loses both its "wierdless" sessions. NOT SENT to rmtew.
       It is upstream's because it is the same two stati, the same Remove and
       the same list on Win32 with the original typedefs. Nothing here depends
       on the port. Reachable without wizard mode: Feature.cpp:296 calls
       MoveDepth for any staircase, so being swallowed and then taking the
       stairs is enough.

       A swallowed creature is NOT an ordinary map object. DoEngulf
       (src/Display.cpp:2145) unlinks it from its square's Contents chain on
       purpose, keeps it in m->Things, and copies the engulfer's x/y onto it;
       its own comment says so. Thing::Remove's engulfed branch
       (src/Display.cpp:1925) is then the only path that unlinks it correctly,
       and Thing::Move's tail (src/Display.cpp:1763) is what carries it along.
       Both read the ENGULFED stati.

       A bare RemoveStati(ENGULFED) dropped the player out of that state while
       leaving him where DoEngulf put him -- in Things, in no Contents chain,
       on the engulfer's square -- and left the matching ENGULFER stati
       standing on the engulfer. The PlaceAt further down then called Remove,
       Remove took the ordinary path because the stati was gone, the Contents
       walk could not find the player, and it printed "Contents list wierdless
       in Thing::Remove!" and abandoned the rest of its work. DropEngulfed
       removes both halves of the pair and puts the victim back on the map
       properly, which is what this line always meant. */
    if (Creature *engulfer = (Creature*)GetStatiObj(ENGULFED))
        engulfer->DropEngulfed(this);
    else
        RemoveStati(ENGULFED);
    RemoveStati(GRAPPLED);
    RemoveStati(GRAPPLING);
    RemoveStati(ELEVATED);

    if (!RES(m->dID) || RES(m->dID)->Type != T_TDUNGEON) {
        IPrint("Apparently, the fall was fatal.");
        ThrowDmg(EV_DEATH, AD_BLUNT, 0, "falling", this, this);
        return;
    }

    if (NewDepth <= 0) {
        mID = RES(m->dID)->GetConst(ABOVE_DUNGEON);
        if (!mID)
            return;

        if (RES(mID)->Type == T_TDUNGEON) {
            NewDepth += (int16)(RES(mID)->GetConst(DUN_DEPTH));
            new_m = theGame->GetDungeonMap(mID, NewDepth, this);
        } else if (RES(mID)->Type == T_TREGION)
            new_m = NULL; /* Map::LoadMap(mID); */
        else
            Error("Strange resource as ABOVE_DUNGEON in MoveDepth!");
    } else if (RES(m->dID)->GetConst(DUN_DEPTH) && (int16)(RES(m->dID)->GetConst(DUN_DEPTH)) < NewDepth) {
        NewDepth -= (int16)(RES(m->dID)->GetConst(DUN_DEPTH));
        mID = RES(m->dID)->GetConst(BELOW_DUNGEON);
        /* upstream: base-code defect, the fix is ours. It is upstream's
           because the missing zero check is plain C++: Game::Get returns NULL
           for a zero id (src/Res.cpp:312), so the RES(mID)->Type below reads
           through NULL on Win32 with the original typedefs exactly as it does
           here, and nothing depends on platform, compiler or type width. The
           codebase argues against itself -- the up path thirteen lines above
           guards the identical case on ABOVE_DUNGEON. Tier Observed:
           INCURSION_STACK_PROBE=1 tools/headless.sh tools/keys/dive.keys 3362
           exits 139 without this guard and 0 with it, one file between the two
           builds, EXC_BAD_ACCESS / KERN_INVALID_ADDRESS at 0x0 faulting in
           Player::MoveDepth (docs/evidence/inc-x9i/crash-seed3362.ips). Three
           further routes crashed real sessions on seeds 111 and 777 --
           walking into a bottom-level chasm, the '>' climb-down, and
           levitating down (docs/evidence/inc-x9i/observed-routes/). Tracked as
           inc-x9i. NOT SENT to rmtew.

           No dungeon in lib/ defines BELOW_DUNGEON, so leaving the bottom
           level of a dungeon downwards always reads RES(0). The climb-down
           route needs no wizard mode, no script and no recursion: Descend
           calls MoveDepth straight (src/Skills.cpp:4181) with safe=true, and
           safe=true does not help. This read happens before the function ever
           looks at safe: the first test of it sits over a hundred lines below,
           inside the if (new_m) block that a null mID never reaches.

           Returning here leaves exactly what the up path's return leaves --
           the stati already removed, the level stats already stored, the game
           already saved -- because both returns sit below that block and above
           every assignment to new_m. */
        if (!mID)
            return;

        if (RES(mID)->Type == T_TDUNGEON)
            new_m = theGame->GetDungeonMap(mID, NewDepth, this);
        else if (RES(mID)->Type == T_TREGION)
            new_m = NULL; /* Map::LoadMap(mID); */
        else
            Error("Strange resource as BELOW_DUNGEON in MoveDepth!");
    } else
        new_m = theGame->GetDungeonMap(m->dID, NewDepth, this);

    if (new_m) {
        /* Later, compensate for dimensions. */
        nx = x;
        ny = y;
        /* Later, allow maps to choose their own entry points from
           any other map, so that, for example, when entering $"Erisia"
           from $"Mines of Moria", the player is always placed at the
           feature $"ancient passage". */

        /* Temporary diagnostic: set INCURSION_FOLLOWER_PROBE=1 to test whether
           the collection loop below actually collects every follower. It walks
           m->Things by index and calls Remove() as it goes; Array::Remove
           memmoves the tail left, so the entry after each removal slides into
           the index the loop has just finished with, and i++ steps over it.
           Two followers adjacent in Things should therefore leave one behind.

           This pre-pass only counts and never removes, so it cannot change the
           outcome it is measuring. The post-pass then asks the old map what is
           still standing on it. Delete with the bead that records this. */
        int16 probeBefore = 0;
        char probeIdx[128];
        probeIdx[0] = '\0';
        if (getenv("INCURSION_FOLLOWER_PROBE")) {
            Creature *pc; int32 pi; size_t pn = 0;
            MapIterate(m, pc, pi)
                if (pc->isMonster())
                    if (pc->ts.isLeader(this)) {
                        probeBefore++;
                        /* The index in m->Things is the whole story: only a
                           follower sitting directly after another one gets
                           skipped, so record where each of them sits. */
                        if (pn < sizeof(probeIdx) - 12)
                            pn += snprintf(probeIdx + pn, sizeof(probeIdx) - pn,
                                pn ? ",%d" : "%d", (int)pi);
                    }
        }

        gwc = 0;
        MapIterate(m, c, i)
            if (c->isMonster())
                if (c->ts.isLeader(this)) {
                    /* A player with more than 64 followers leaves the rest
                       behind rather than writing past the array. */
                    if (gwc >= (int16)(sizeof(GoWith)/sizeof(GoWith[0])))
                        break;
                    GoWith[gwc++] = c;
                    c->Remove(false);
                    /* upstream: base-code defect, the fix is ours. Remove()
                       deletes this creature from m->Things (Display.cpp:1990),
                       Array::Remove memmoves the tail one place left
                       (Base.cpp:595), and MapIterate advances with i++
                       (Base.h:102). So the entry that follows a collected
                       follower slides into the index just finished with, and
                       the loop steps straight over it: a player who changes
                       level with two adjacent followers arrives with one.
                       Stepping back cancels the slide. It is upstream's
                       because it is plain array indexing and a memmove --
                       identical on Win32, with the original typedefs, on the
                       upstream compiler; nothing here depends on the port.
                       Tier Observed: INCURSION_FOLLOWER_PROBE=1 with
                       tools/keys/followers.keys reported
                       "followers_before=3 collected=2 left_behind=1" on three
                       seeds before this line and collects all three after it.
                       Tracked as inc-90u. NOT SENT to rmtew. */
                    i--;
                }

        if (getenv("INCURSION_FOLLOWER_PROBE")) {
            static FILE *folLog = NULL;
            if (!folLog) {
                char path[1024];
                snprintf(path, sizeof(path), "%slogs/followerprobe.log",
                    (const char*)T1->IncursionDirectory);
                folLog = fopen(path, "a");
            }
            if (folLog) {
                int16 leftBehind = 0;
                Creature *pc; int32 pi;
                MapIterate(m, pc, pi)
                    if (pc->isMonster())
                        if (pc->ts.isLeader(this))
                            leftBehind++;
                fprintf(folLog,
                    "MoveDepth depth=%d followers_before=%d at=[%s] "
                    "collected=%d left_behind=%d\n",
                    (int)m->Depth, (int)probeBefore, probeIdx,
                    (int)gwc, (int)leftBehind);
                fflush(folLog);
            }
        }

        GoWithProbe("collected", m->Depth, GoWith, gwc);

        if (c = (Creature*)GetStatiObj(DWARVEN_FOCUS))
            if (c->m == m) {
                LoseXP(TotalLevel() * 200);
                IPrint("You feel your heart grow leaden, as you realize "
                    "true vengeance will forever elude you.");
                SetStatiObj(DWARVEN_FOCUS, -1, NULL);
            }

        /* ArrivalSquare holds both placement rules -- the refusal and the step
           off a falling square -- so that the descent warning in Portal::Enter
           can name the square this places the player on without keeping a
           second copy of them. */
        while (!ArrivalSquare(new_m, nx, ny, safe))  {
            nx = 2 + random(new_m->SizeX() - 4);
            ny = 2 + random(new_m->SizeY() - 4);
        }

        /* Temporary diagnostic: set INCURSION_FALL_CHAIN to a depth, or to
           'all', to steer the arrival square onto a real chasm square already
           present on the arrival level. It creates no terrain and moves nothing
           else; it only chooses where the arriving player lands, which is what
           makes the fall chain reachable on demand instead of by luck. With
           'all' each arrival lands on chasm again, so the recursion runs to the
           bottom of the dungeon. Delete with inc-upw.15. */
        if (const char *fc = getenv("INCURSION_FALL_CHAIN"))
            if (!strcmp(fc, "all") || new_m->Depth == (int16)atoi(fc)) {
                /* INCURSION_FALL_CHAIN_SKIP ignores the first N matching
                   arrivals, so a test can walk a level, leave it, and steer
                   only the RETURN to it. */
                static int seen = 0;
                const char *sk = getenv("INCURSION_FALL_CHAIN_SKIP");
                if (sk && seen++ < atoi(sk))
                    goto no_steer;
                int16 fx, fy; bool found = false;
                for (fy = 1; fy < new_m->SizeY() - 1 && !found; fy++)
                    for (fx = 1; fx < new_m->SizeX() - 1 && !found; fx++)
                        if (new_m->FallAt(fx, fy) && !new_m->SolidAt(fx, fy)) {
                            nx = fx; ny = fy; found = true;
                        }
                static FILE *chainLog = NULL;
                if (!chainLog) {
                    char path[1024];
                    snprintf(path, sizeof(path), "%slogs/fallchain.log",
                        (const char*)T1->IncursionDirectory);
                    chainLog = fopen(path, "a");
                }
                if (chainLog) {
                    fprintf(chainLog, "arrival depth=%d chasm_found=%d at=%d,%d\n",
                        (int)new_m->Depth, (int)found, (int)nx, (int)ny);
                    fflush(chainLog);
                }
            }
        no_steer:

        PlaceAt(new_m, nx, ny, true);

        GoWithProbe("placing", m->Depth, GoWith, gwc);

        for (i = 0; i != gwc; i++)
            GoWith[i]->PlaceAt(new_m, nx, ny);

        /* Temporary diagnostic: set INCURSION_CHASM_WALK=1 to stand the player
           immediately west of a real chasm square on the deepest level of the
           dungeon, so that a key script can walk east into it and the fall,
           the confirmation and MoveDepth all run as they normally would.

           Nothing here manufactures terrain -- it only chooses where the
           player stands, which is what a wizard teleport would do by hand. It
           fires only on the bottom level and only once per arrival. Delete
           with the bead that records this. */
        /* Temporary diagnostic: set INCURSION_LEVITATE_CHASM=1 to grant
           LEVITATION and stand the player ON a chasm square on the deepest
           level, which is what Creature::Descend's levitation branch
           (Skills.cpp:4155-4161) requires. A potion or a spell would produce
           the same state; this only saves the harness from casting one.
           Delete with the bead that records this. */
        if (getenv("INCURSION_LEVITATE_CHASM") &&
            new_m->Depth == (int16)RES(new_m->dID)->GetConst(DUN_DEPTH)) {
            static FILE *levLog = NULL;
            int16 lx, ly;
            if (!levLog) {
                char path[1024];
                snprintf(path, sizeof(path), "%slogs/levitate.log",
                    (const char*)T1->IncursionDirectory);
                levLog = fopen(path, "a");
            }
            if (!HasStati(LEVITATION))
                GainPermStati(LEVITATION, NULL, SS_MISC);
            for (lx = 2; lx < new_m->SizeX() - 2; lx++)
                for (ly = 2; ly < new_m->SizeY() - 2; ly++)
                    if (TTER(new_m->TerrainAt(lx, ly))->HasFlag(TF_FALL)) {
                        if (levLog) {
                            fprintf(levLog,
                                "levitating on chasm at %d,%d, depth %d, "
                                "dun_depth %d\n", (int)lx, (int)ly,
                                (int)new_m->Depth,
                                (int)RES(new_m->dID)->GetConst(DUN_DEPTH));
                            fflush(levLog);
                        }
                        Move(lx, ly, false);
                        lx = new_m->SizeX();
                        break;
                    }
        }

        if (getenv("INCURSION_CHASM_WALK") &&
            new_m->Depth == (int16)RES(new_m->dID)->GetConst(DUN_DEPTH)) {
            static FILE *walkLog = NULL;
            int16 cx, cy;
            if (!walkLog) {
                char path[1024];
                snprintf(path, sizeof(path), "%slogs/chasmwalk.log",
                    (const char*)T1->IncursionDirectory);
                walkLog = fopen(path, "a");
            }
            int32 fallSeen = 0, edgeSeen = 0;
            for (cx = 2; cx < new_m->SizeX() - 2; cx++)
                for (cy = 2; cy < new_m->SizeY() - 2; cy++)
                    if (TTER(new_m->TerrainAt(cx, cy))->HasFlag(TF_FALL)) {
                        fallSeen++;
                        if (!new_m->SolidAt(cx - 1, cy) &&
                            !TTER(new_m->TerrainAt(cx - 1, cy))->HasFlag(TF_FALL)) {
                            edgeSeen++;
                            if (edgeSeen == 1) {
                                if (walkLog) {
                                    fprintf(walkLog,
                                        "chasm at %d,%d; standing player at %d,%d "
                                        "on depth %d (terrain west: %s)\n",
                                        (int)cx, (int)cy, (int)(cx - 1), (int)cy,
                                        (int)new_m->Depth,
                                        (const char*)NAME(new_m->TerrainAt(cx - 1, cy)));
                                    fflush(walkLog);
                                }
                                Move(cx - 1, cy, false);
                            }
                        }
                    }
            if (walkLog) {
                fprintf(walkLog, "scan on depth %d: %d fall squares, %d with a walkable west neighbour\n",
                    (int)new_m->Depth, (int)fallSeen, (int)edgeSeen);
                fflush(walkLog);
            }
        }
    }

    MyTerm->RefreshMap();

    NoteArrival();

    if (safe) {
        MapIterate(m, c, i)
            if (c->isPlayer())
                c->Timeout = 0;
            else if (c->isCreature())
                c->Timeout = max(c->Timeout, 1);
    }
}
  
void Player::NoteArrival() {
    int16 dn, i;

    dn = -1;
    for (i = 0; i != MAX_DUNGEONS; i++)
        if (m && m->dID && m->dID == theGame->DungeonID[i])
            dn = i;

    if (dn != -1)
        if (MaxDepths[dn] < m->Depth) {
            MaxDepths[dn] = m->Depth;
            AddJournalEntry(XPrint("You arrive at <Num>' in the <Res>.", m->Depth * 10, m->dID));
        }
}

Map* Game::GetDungeonMap(rID dID, int16 Depth, Player *pl, Map*TownLevel) {
    int16 i, n;
    Map *m;
    bool ip;

    ip = PlayMode;
    PlayMode = false;

    for (i = 1; i != MAX_DUNGEONS && DungeonID[i]; i++)
        if (DungeonID[i] == dID)
            goto Found;

    if (i == MAX_DUNGEONS)
        Fatal("Too many dungeons; max specified by MAX_DUNGEONS is %d.", MAX_DUNGEONS);
    if (Depth > MAX_DUNGEON_LEVELS)
        Fatal("Too deep in dungeon; MAX_DUNGEON_LEVELS is %d.", MAX_DUNGEON_LEVELS);

    DungeonID[i] = dID;
    DungeonSize[i] = min(MAX_DUNGEON_LEVELS, (int16)(RES(dID)->GetConst(DUN_DEPTH)));
    DungeonLevels[i] = (hObj*)malloc(sizeof(hObj)*min(MAX_DUNGEON_LEVELS, RES(dID)->GetConst(DUN_DEPTH) + 1));
    memset(DungeonLevels[i], 0, sizeof(hObj)*(RES(dID)->GetConst(DUN_DEPTH) + 1));
Found:
    n = i;

    /* Temporary diagnostic: set INCURSION_DUNGEONMAP_PROBE=1 to report a request
       for a level outside the array this function allocated. DungeonLevels[n]
       holds min(MAX_DUNGEON_LEVELS, DUN_DEPTH + 1) handles, so the last valid
       index is DUN_DEPTH -- but the loop below runs i <= Depth and the return
       reads [Depth]. The levitation guard in Creature::Descend asks for
       DUN_DEPTH + 1 while standing on the bottom level. Delete with inc-tos. */
    if (getenv("INCURSION_DUNGEONMAP_PROBE")) {
        int32 allocated = min((int32)MAX_DUNGEON_LEVELS,
            (int32)(RES(dID)->GetConst(DUN_DEPTH)) + 1);
        if ((int32)Depth >= allocated) {
            static FILE *dmLog = NULL;
            if (!dmLog) {
                char path[1024];
                snprintf(path, sizeof(path), "%slogs/dungeonmapprobe.log",
                    (const char*)T1->IncursionDirectory);
                dmLog = fopen(path, "a");
            }
            if (dmLog) {
                fprintf(dmLog,
                    "GetDungeonMap depth=%d allocated=%d last_valid_index=%d "
                    "reads_index=%d\n",
                    (int)Depth, (int)allocated, (int)allocated - 1, (int)Depth);
                fflush(dmLog);
            }
        }
    }

    /* Set DungeonLevels[n][0] to whatever is directly, geographically
       above the first dungeon level. This will allow us to match up stair
       locations with the city (or whatever) above the dungeon. */
    if (TownLevel)
        DungeonLevels[n][0] = TownLevel->myHandle;


    /* If we jump straight from dungeon level 4 to level 15, we have to
       generate (and then save) all the levels between, in order to match
       up stair locations, chasms, and other cross-level features. */

    for (i = 1; i <= Depth; i++)
        if (!DungeonLevels[n][i]) {
            m = new Map();
            DungeonLevels[n][i] = m->myHandle;
            m->Generate(dID, i, oMap(DungeonLevels[n][i - 1]), (int8)pl->GetAttr(A_LUC));
        }

    /*
    for(i=1;i!=Depth;i++)
    theGame->Detach(DungeonLevels[n][i]);
    */

    PlayMode = ip;
    /* inc-qhux: heal the level the player is about to enter. A freshly
       generated level is already correct (the fix is in Map::Generate) and the
       call is idempotent; a level restored from a pre-fix save is healed here. */
    Map *ready = oMap(DungeonLevels[n][Depth]);
    if (ready)
        ready->FixWallOpacity();
    return ready;
}

void Feature::StatiOn(Status s) {
    int16 col;
    if (s.Nature == MY_GOD && (Flags & F_ALTAR))
        if (col = (int16)TGOD(s.eID)->GetConst(ALTAR_COLOUR)) {
            Image &= GLYPH_ID_MASK;
            Image |= GLYPH_FORE(col);
            if (m)
                m->Update(x, y);
        }
}

void Feature::StatiOff(Status s) {
    EventInfo xe;
    switch (s.Nature) {
    case SUMMONED:
        IDPrint(NULL, "The <Obj> winks out of existence.", this);
        if (m && m->InBounds(x, y)) {
            m->At(x, y).Glyph = TTER(m->TerrainAt(x, y))->Image;
            m->At(x, y).Shade = TTER(m->TerrainAt(x, y))->HasFlag(TF_SHADE);
            m->At(x, y).Solid = TTER(m->TerrainAt(x, y))->HasFlag(TF_SOLID);
            m->At(x, y).Opaque = TTER(m->TerrainAt(x, y))->HasFlag(TF_OPAQUE);
        }
        Remove(true);
        break;

    }
    if (theGame->InPlay()) {
        SetImage();
    }
}
