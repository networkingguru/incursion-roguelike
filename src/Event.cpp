/* EVENT.CPP -- See the Incursion LICENSE file for copyright information.

     Contains all the code that governs the dispatch of events,
   functions for throwing events and sending them to the proper
   handlers according to the rules of Incursion's event-based
   logic.

     EvReturn ThrowEvent(EventInfo &e)
     EvReturn ThrowTo(EventInfo &e, Object *t)
     EvReturn RealThrow(EventInfo &e)
     EvReturn ReThrow(int16 ev,EventInfo &e)
     void SetEvent(EventInfo *e, int16 Ev, Object *p1, Object *p2, Object*p3,Object *p4)
     EvReturn Throw(int16 Ev, Object *p1, Object *p2, Object*p3,Object *p4)
     EvReturn ThrowField(int16 Ev,Field *f,Object *p1, Object *p2, Object*p3,Object *p4)
     EvReturn ThrowDir(int16 Ev,Dir d, Object *p1, Object *p2,Object*p3, Object *p4)
     EvReturn ThrowXY(int16 Ev,int16 x,int16 y,Object *p1, Object *p2, Object*p3, Object *p4)
     EvReturn ThrowVal(int16 Ev,int16 n, Object *p1, Object *p2,Object*p3, Object *p4)
     EvReturn ThrowEff(int16 Ev,rID eID,Object *p1, Object *p2, Object*p3, Object *p4)
     EvReturn ThrowEffDir(int16 Ev,rID eID,Dir d,Object *p1, Object *p2, Object*p3, Object *p4)
     EvReturn ThrowEffXY(int16 Ev,rID eID,int16 x,int16 y,Object *p1, Object *p2, Object*p3, Object *p4)
     EvReturn ThrowLoc(int16 Ev,int16 x,int16 y,Object *p1, Object *p2,Object*p3,Object *p4)
     EvReturn ThrowDmg(int16 Ev,int16 DType,int16 DmgVal, const char*s,Object *p1, Object *p2,Object*p3,Object *p4)

*/


#include "Incursion.h"

/* Diagnostic only, for bead inc-6d5. src/Display.cpp's INC6D5_PROBE catches
   every m/x/y change made through Thing::Move/PlaceAt/Remove for a
   name-matched creature, but a fresh 40-seed dive.keys sweep on seed 21
   showed Volgar/129's x field changing from 38 to 39 on the same map between
   two of those calls, with NONE of them firing in between -- meaning
   something writes x/y directly, bypassing all three. This wraps
   RealThrow(), the single choke point every event (including ones no other
   probe hooks) passes through, and diffs the watched creature's (m,x,y)
   across each call. A jump with no matching Move/PlaceAt/Remove log at the
   same turn is that direct write, and the event id + backtrace here is the
   site. Same opt-in build flag as Display.cpp's probe:
     EXTRA_CXXFLAGS=-DINC6D5_PROBE OUT=incursion-inc6d5probe BACKEND=posix ./build_macos.sh */
#ifdef INC6D5_PROBE
#include <execinfo.h>
#include <cstring>
#include <cstdio>
static hObj g_inc6d5DriftHandle = 0;
static Map *g_inc6d5DriftM = NULL;
static int16 g_inc6d5DriftX = -999, g_inc6d5DriftY = -999;
static FILE *Inc6d5EventProbeLog() {
    static FILE *f = NULL;
    if (!f) {
        char path[1024];
        snprintf(path, sizeof(path), "%slogs/inc6d5-probe.log",
            (const char*)T1->IncursionDirectory);
        f = fopen(path, "a");
    }
    return f;
}
static void Inc6d5EventDriftCheck(const char *where, EventInfo &e) {
    Thing *t; FILE *f; void *frames[16]; int n, i; char **syms;
    const char *names, *nm2;
    char buf[256], *tok, *save = NULL;
    String nm;
    /* Resolve the watched handle once, the first time any name-matched
       creature is seen anywhere in the registry. Cheap relative to a whole
       diagnostic build: only runs until g_inc6d5DriftHandle is set. */
    if (!g_inc6d5DriftHandle) {
        names = getenv("INC6D5_PROBE_NAMES");
        if (!names || !*names)
            names = "Volgar,Gell";
        for (hObj h = 128; h <= theRegistry->LastUsedHandle; h++) {
            if (!theRegistry->Exists(h))
                continue;
            Object *o = theRegistry->Get(h);
            if (!o || !o->isCreature())
                continue;
            nm2 = (const char*)((Thing*)o)->Name(0);
            snprintf(buf, sizeof(buf), "%s", names);
            for (tok = strtok_r(buf, ",", &save); tok; tok = strtok_r(NULL, ",", &save))
                if (strstr(nm2, tok)) {
                    g_inc6d5DriftHandle = h;
                    break;
                }
            if (g_inc6d5DriftHandle)
                break;
        }
        if (!g_inc6d5DriftHandle)
            return;
        t = (Thing*)theRegistry->Get(g_inc6d5DriftHandle);
        g_inc6d5DriftM = t->m; g_inc6d5DriftX = t->x; g_inc6d5DriftY = t->y;
        return;
    }
    if (!theRegistry->Exists(g_inc6d5DriftHandle))
        return;
    t = (Thing*)theRegistry->Get(g_inc6d5DriftHandle);
    if (t->m == g_inc6d5DriftM && t->x == g_inc6d5DriftX && t->y == g_inc6d5DriftY)
        return;
    f = Inc6d5EventProbeLog();
    if (f) {
        nm = t->Name(0);
        fprintf(f, "turn %u  DRIFT %-8s ev=%d actor=%s (MOUNTED=%d ENGULFER=%d)  %s/%d (MOUNT=%d MOUNTED=%d ENGULFED=%d ENGULFER=%d)  m %p->%p  x %d->%d  y %d->%d\n",
            (unsigned)(theGame ? theGame->Turn : 0), where, (int)e.Event,
            e.EActor ? (const char*)e.EActor->Name(0) : "(none)",
            (e.EActor && e.EActor->isCreature()) ? (int)((Creature*)e.EActor)->HasStati(87) : -1,
            (e.EActor && e.EActor->isCreature()) ? (int)((Creature*)e.EActor)->HasStati(95) : -1,
            (const char*)nm, (int)g_inc6d5DriftHandle,
            (int)((Creature*)t)->HasStati(88), (int)((Creature*)t)->HasStati(87),
            (int)((Creature*)t)->HasStati(94), (int)((Creature*)t)->HasStati(95),
            (void*)g_inc6d5DriftM, (void*)t->m,
            (int)g_inc6d5DriftX, (int)t->x, (int)g_inc6d5DriftY, (int)t->y);
        n = backtrace(frames, 20);
        syms = backtrace_symbols(frames, n);
        if (syms) {
            for (i = 0; i < n; i++)
                fprintf(f, "    %s\n", syms[i]);
            free(syms);
        }
        fflush(f);
    }
    g_inc6d5DriftM = t->m; g_inc6d5DriftX = t->x; g_inc6d5DriftY = t->y;
}
#define INC6D5_EVENT_DRIFT(where,e) Inc6d5EventDriftCheck(where,e)
#else
#define INC6D5_EVENT_DRIFT(where,e) ((void)0)
#endif

// ww: this used to be 32, but I actually went over that in normal gameplay
// @ Thu Feb 19 22:19:43 PST 2004
#define CHECK_OVERFLOW          if (EventSP > EVENT_STACK_SIZE-1) Fatal("Event Stack Overflow!");

EventInfo EventStack[EVENT_STACK_SIZE];
int16     EventSP = -1;

TGod*     GodList[MAX_GODS];
rID       GodIDList[MAX_GODS];
int16     nGods;

void InitGodArrays()
  {
    int16 i;
    for (i=0;i != theGame->LastGod();i++)
      {
        GodIDList[i] = theGame->GodID(i);
        GodList[i]   = TGOD(GodIDList[i]);
        ASSERT(MAX_GODS > i);
      }
    nGods = i;
  }  


EvReturn ThrowTo(EventInfo &e,Object*);

EvReturn ThrowEvent(EventInfo &e) {
    int16 i, oEv, tx, ty;
    EvReturn res; 
    Thing *sub;
    rID xID;

    sub = (e.Event == EV_DAMAGE || e.Event == EV_DEATH)
        ? e.EVictim : e.EActor;

    if (e.EActor && e.EActor->m)
        e.EMap = e.EActor->m;
    else if (e.EVictim && e.EVictim->m)
        e.EMap = e.EVictim->m;
    else if (e.EActor && e.EActor->isItem() && ((Item*)e.EActor)->Owner())
        e.EMap = ((Item*)e.EActor)->Owner()->m;
    else if (e.EItem && e.EItem->isItem() && e.EItem->Owner())
        e.EMap = e.EItem->Owner()->m;

    if (sub && e.EMap && (sub->x != -1)) {
        /* Give Region a chance to override */
        xID = e.EMap->RegionAt(sub->x,sub->y);
        res = TREG(xID)->Event(e,xID);
        if (res == ERROR) {
            Error(Format("Event %s::%s routine returned ERROR!",
                (const char*) NAME(xID),(const char*)EventName(e.Event)));
            return ABORT;
        }
        if (res == DONE || res == ABORT)
            return res;
        if (res == NOMSG)
            e.Terse = true;

        if (e.isLoc)
        { tx = e.EXVal; ty = e.EYVal; }
        else
        { tx = sub->x; ty = sub->y; }

        if (e.EMap->InBounds(tx,ty) && 
            TTER(e.EMap->TerrainAt(tx,ty))->HasFlag(TF_SPECIAL)) {
                /* Give Terrain a chance to override. */
                xID = e.EMap->TerrainAt(tx,ty);
                res = TTER(xID)->Event(e,xID);
                if (res == ERROR) {
                    Error(Format("Event %s::%s routine returned ERROR!",
                        (const char*) NAME(xID),(const char*) EventName(e.Event)));
                    return ABORT;
                }
                if (res == DONE || res == ABORT)
                    return res;
                if (res == NOMSG)
                    e.Terse = true;
        }
        if (e.EMap->InBounds(tx,ty) && e.EMap->FieldAt(tx,ty,FI_ITERRAIN) && e.EActor) {
            /* Give *illusionary* Terrain a chance to override. */
            xID = e.EMap->PTerrainAt(tx,ty,e.EActor->isCreature() ? e.EActor : NULL);
            res = TTER(xID)->Event(e,xID);
            if (res == ERROR) {
                Error(Format("Event %s::%s routine returned ERROR!",
                    (const char*) NAME(xID),(const char*)EventName(e.Event)));
                return ABORT;
            }
            if (res == DONE || res == ABORT)
                return res;
            if (res == NOMSG)
                e.Terse = true;

        }
    }

    /* Give the map/dungeon a chance to override */
    if (e.EMap && e.EMap->dID) {
        res = RES(e.EMap->dID)->Event(e,e.EMap->dID);
        if (res == ERROR) {
            Error(Format("Event %s::%s routine returned ERROR!",
                (const char*) NAME(e.EActor->m->dID),(const char*)EventName(e.Event)));
            return ABORT;
        }
        if (res == DONE || res == ABORT)
            return res;
        if (res == NOMSG)
            e.Terse = true;
    }

    /* Give the field or effect a chance to override */
    if (e.EField && e.EField->eID) {
        res = RES(e.EField->eID)->Event(e,e.EField->eID);
        if (res == ERROR) {
            Error(Format("Event %s::%s routine returned ERROR!",
                (const char*) NAME(e.EField->eID),(const char*)EventName(e.Event)));
            return ABORT;
        }                                   
        if (res == DONE && e.Event == EV_MAGIC_HIT)
            e.isSomething = true;
        if (res == DONE || res == ABORT)
            return res;
        if (res == NOMSG)
            e.Terse = true;
    } else if (e.eID && e.Event && (e.Event != EV_EFFECT)) {
        res = RES(e.eID)->Event(e,e.eID);
        if (res == ERROR) {
            Error(Format("Event %s::%s routine returned ERROR!",
                (const char*) NAME(e.eID),(const char*)EventName(e.Event)));
            return ABORT;
        }
        if (res == DONE || res == ABORT)
            return res;
        if (res == NOMSG)
            e.Terse = true;
    }

    /* Let the gods evaluate the EActor's conduct*/
    if (e.EActor && e.EActor->isCharacter()) {
        for (i=0;i!=nGods;i++) {
            oEv = e.Event;
            e.Event = GODWATCH(e.Event);
            res = GodList[i]->Event(e,GodIDList[i]);
            e.Event = oEv;
            if (res == ERROR) {
                Error(Format("Event %s::%s routine returned ERROR!",
                    (const char*) NAME(GodIDList[i]),(const char*)EventName(e.Event)));
                return ABORT;
            }                                   
            if (res == DONE && e.Event == EV_MAGIC_HIT)
                e.isSomething = true;
            if (res == DONE || res == ABORT)
                return res;
            if (res == NOMSG)
                e.Terse = true;
        }
    }

    /* Let the gods evaluate the EActor's conduct*/
    if (e.EVictim && e.EVictim->isCharacter()) {
        for (i=0;i!=nGods;i++) {
            oEv = e.Event;
            e.Event = GODWATCH(EVICTIM(e.Event));
            res = GodList[i]->Event(e,GodIDList[i]);
            e.Event = oEv;
            if (res == ERROR) {
                Error(Format("Event %s::%s routine returned ERROR!",
                    (const char*) NAME(GodIDList[i]),(const char*)EventName(e.Event)));
                return ABORT;
            }                                   
            if (res == DONE && e.Event == EV_MAGIC_HIT)
                e.isSomething = true;
            if (res == DONE || res == ABORT)
                return res;
            if (res == NOMSG)
                e.Terse = true;
        }
    }    

    if (e.EMap)
        switch(ThrowTo(e,e.EMap)) {
        case NOMSG:
            e.Terse = true;
            //fall through;
        case NOTHING:
            break;
        case ABORT:
            return ABORT;
        case DONE:
            return DONE;
        case ERROR:
            Error(Format("Event %s::%s routine returned ERROR!",
                e.p[i].o ? (const char*) e.p[i].o->Name(0) : "(null)",
                Lookup(EV_CONSTNAMES,e.Event%500)));
            return ABORT;
        }

    for(i=3;i!=-1;i--) {
        if(e.p[i].o) {
            Thing *t = e.p[i].t;
            StatiIterNature(t, TRAP_EVENT) {
                oEv = e.Event;
                e.Event = (i == 1) ? META(EVICTIM(e.Event)) : META(e.Event);
                if (META(S->Mag) == e.Event) {
                    res = RES(S->eID)->Event(e,S->eID);
                    if (res == ERROR)
                        Error(Format("Stati $\"%s\":EVENT_TRAP returned ERROR!",NAME(S->eID)));
                    if (res == ABORT || res == DONE)
                        StatiIterBreakout(e.p[i].t,return res)
                        if (res == NOMSG)
                            e.Terse = true;
                }
                e.Event = oEv;
            }
            StatiIterEnd(t)

            switch(ThrowTo(e,e.p[i].o)) {
            case NOMSG:
                e.Terse = true;
                //fall through;
            case NOTHING:
                break;
            case ABORT:
                return ABORT;
            case DONE:
                return DONE;
            case ERROR:
                Error(Format("Event %s::%s routine returned ERROR!",
                    e.p[i].o ? (const char*) e.p[i].o->Name(0) : "(null)",
                    Lookup(EV_CONSTNAMES,e.Event%500)));
                return ABORT;
            }
        }
    }
    return NOTHING;
}


EvReturn ThrowTo(EventInfo&e, Object*t) {
    int16 i;
    EvReturn r=NOTHING;
    i=t->Type;
Again:
    if(!i)
        return r;
    switch(i) {
#define HIER(Type,T_TYPE,T_BASE)                    \
        case T_TYPE:                                \
            r=((Type*)t)->Event(e);                 \
            if(r==DONE || r==ABORT || r==ERROR)     \
                return r;                           \
            if(r==NOMSG)                            \
                e.Terse = true;                     \
            i=T_BASE;                               \
            goto Again;
        HIER(Map,T_MAP,0)
        HIER(Thing,T_THING,0)
        HIER(Creature,T_CREATURE,T_THING)
        HIER(Character,T_CHARACTER,T_CREATURE)
        HIER(Player,T_PLAYER,T_CHARACTER)
        HIER(Monster,T_MONSTER,T_CREATURE)
        case T_POTION: case T_WAND: case T_STAFF: case T_ROD:
        case T_AMULET: case T_BOOK: case T_BRACERS: case T_CLOAK:
        case T_CROWN: case T_DECK: case T_DUST: case T_GEM:
        case T_EYES: case T_GIRDLE: case T_HERB: 
        case T_MUSH: case T_SCROLL: case T_TOOL: case T_RING:
        case T_COIN: case T_LIGHT:  case T_TOME: case T_WONDER:
        case T_FOUNTAIN: case T_SYMBOL: case T_CLOTHES: case T_HELMET:
        HIER(Item,T_ITEM,T_THING)
        case T_FIGURE: case T_STATUE:
        HIER(Corpse,T_CORPSE,T_FOOD)
        HIER(Food,T_FOOD,T_ITEM)
        case T_BOW: case T_MISSILE:
        HIER(Weapon,T_WEAPON,T_ITEM)
        case T_BOOTS:
        case T_GAUNTLETS: case T_SHIELD:
        HIER(Armour,T_ARMOUR,T_ITEM)
        HIER(Door,T_DOOR,T_FEATURE)
        HIER(Portal,T_PORTAL,T_FEATURE)
        HIER(Trap,T_TRAP,T_FEATURE)
        HIER(Feature,T_FEATURE,T_THING)
        case T_CHEST:
        HIER(Container,T_CONTAIN,T_ITEM)
        default:
            T1->Message("Type undefined in ThrowTo!");
    }
    return ERROR;
}

EvReturn RealThrow(EventInfo &e) {
    EvReturn r;
    int16 Ev;

    INC6D5_EVENT_DRIFT("enter", e);

    if (EventSP > 0) {
        int16 ev = EventStack[EventSP-1].Event % 500;
        if (ev == EV_RETRIBUTION || ev == EV_GIVE_AID ||
            ev == EV_GODPULSE || ev == EV_ANGER_PULSE ||
            ev == EV_SACRIFICE)
            e.isActOfGod = true;
    }

    /* This is a kludge for script routines (like that
    found in Holy Avenger) that cannot properly set
    e.EMagic because they can't manipulate the
    EffectValues object directly. See Holy Avenger/
    Flesh Golem interaction. */
    if (e.Event == EV_MAGIC_HIT ||
        e.Event == EV_MAGIC_STRIKE)
        if (e.eID && !e.EMagic)
            e.EMagic = &TEFF(e.eID)->ef;

    Ev = e.Event;
    e.Event=PRE(Ev);
    r=ThrowEvent(e);
    INC6D5_EVENT_DRIFT("afterPRE", e);
    if (r != ABORT && r != DONE) {
        e.Event=Ev;
        r=ThrowEvent(e);
        INC6D5_EVENT_DRIFT("afterMAIN", e);
    }
    if (r != ABORT) {
        e.Event=POST(Ev);
        ThrowEvent(e);
        INC6D5_EVENT_DRIFT("afterPOST", e);
    }
    if(r==NOTHING) {
        /* For now, PRE and POST events don't *need* to be handled. */
        if (e.Event >= 500)
            return r;
        if (e.Event >= 1000)
            Fatal("Error: Unhandled Event:PRE_%s (%d)!",Lookup(EV_CONSTNAMES,e.Event-1000),e.Event);
        else if (e.Event >= 500)
            Fatal("Error: Unhandled Event:POST_%s (%d)!",Lookup(EV_CONSTNAMES,e.Event-500),e.Event);
        else
            Fatal("Error: Unhandled Event:%s (%d)!",Lookup(EV_CONSTNAMES,e.Event),e.Event);
    }
    if (r != NOTHING && e.Event == EV_MAGIC_HIT)
        e.isSomething = true;
    return r;
}

EvReturn ReThrow(int16 ev,EventInfo &e)
	{
		EvReturn r; bool ter;
    EventSP++;
    CHECK_OVERFLOW; 
    
    EventStack[EventSP] = e;
    EventStack[EventSP].Event = ev;
    EventStack[EventSP].Terse = false;
    EventStack[EventSP].isVerb = false;
    r = RealThrow(EventStack[EventSP]);
    EventStack[EventSP].Event = e.Event;
    ter = e.Terse;
    e = EventStack[EventSP];
    e.Terse = ter;
    EventSP--;
    return r;
	}

// ww: this used to return a static EventInfo, but that's vastly bad news
// in control loops while processing events (not unlikely) 
void SetEvent(EventInfo &e, int16 Ev, Object *p1, Object *p2,
              Object*p3,Object *p4)
	{
    e.Clear();
    e.Event = Ev;
		e.p[0].o = p1;
    e.p[1].o = p2;
    e.p[2].o = p3;
    e.p[3].o = p4;
		return;
	}


EvReturn Throw(int16 Ev, Object *p1, Object *p2, Object*p3,Object *p4) {
    EvReturn r;
    EventSP++;
    CHECK_OVERFLOW; 
    EventStack[EventSP].Clear();
    EventStack[EventSP].Event = Ev;
    EventStack[EventSP].p[0].o = p1;
    EventStack[EventSP].p[1].o = p2;
    EventStack[EventSP].p[2].o = p3;
    EventStack[EventSP].p[3].o = p4;
    r=RealThrow(EventStack[EventSP]);
    EventSP--;
    return r;
}

EvReturn ThrowField(int16 Ev,Field *f,Object *p1, Object *p2, Object*p3,Object *p4) {
    EvReturn r;
    EventSP++;
    CHECK_OVERFLOW; 
    EventStack[EventSP].Clear();
    EventStack[EventSP].Event = Ev;
    EventStack[EventSP].p[0].o = p1;
    EventStack[EventSP].p[1].o = p2;
    EventStack[EventSP].p[2].o = p3;
    EventStack[EventSP].p[3].o = p4;
    EventStack[EventSP].EField = f;
    r=RealThrow(EventStack[EventSP]);
    EventSP--;
    return r;
}

EvReturn ThrowDir(int16 Ev,Dir d, Object *p1, Object *p2,Object*p3,Object *p4) {
    EvReturn r;
    EventSP++;
    CHECK_OVERFLOW; 
    EventStack[EventSP].Clear();
    EventStack[EventSP].Event = Ev;
    EventStack[EventSP].p[0].o = p1;
    EventStack[EventSP].p[1].o = p2;
    EventStack[EventSP].p[2].o = p3;
    EventStack[EventSP].p[3].o = p4;
    EventStack[EventSP].EDir = d;
    EventStack[EventSP].isDir = true;
    r=RealThrow(EventStack[EventSP]);
    EventSP--;
    return r;
}

EvReturn ThrowXY(int16 Ev,int16 x,int16 y,Object *p1, Object *p2, Object*p3, Object *p4) {
    EvReturn r;
    EventSP++;
    CHECK_OVERFLOW; 
    EventStack[EventSP].Clear();
    EventStack[EventSP].Event = Ev;
    EventStack[EventSP].p[0].o = p1;
    EventStack[EventSP].p[1].o = p2;
    EventStack[EventSP].p[2].o = p3;
    EventStack[EventSP].p[3].o = p4;
    EventStack[EventSP].EXVal = x;
    EventStack[EventSP].EYVal = y;
    EventStack[EventSP].isLoc = true;
    r=RealThrow(EventStack[EventSP]);
    EventSP--;
    return r;
}

EvReturn ThrowVal(int16 Ev,int16 n, Object *p1, Object *p2,Object*p3,Object *p4) {
    EvReturn r;
    EventSP++;
    CHECK_OVERFLOW; 
    EventStack[EventSP].Clear();
    EventStack[EventSP].Event = Ev;
    EventStack[EventSP].p[0].o = p1;
    EventStack[EventSP].p[1].o = p2;
    EventStack[EventSP].p[2].o = p3;
    EventStack[EventSP].p[3].o = p4;
    EventStack[EventSP].EParam = n;
    r=RealThrow(EventStack[EventSP]);
    EventSP--;
    return r;
}

EvReturn ThrowEff(int16 Ev,rID eID,Object *p1, Object *p2, Object*p3, Object *p4) {
    EvReturn r;
    EventSP++;    
    CHECK_OVERFLOW; 
    EventStack[EventSP].Clear();
    EventStack[EventSP].Event = Ev;
    EventStack[EventSP].p[0].o = p1;
    EventStack[EventSP].p[1].o = p2;
    EventStack[EventSP].p[2].o = p3;
    EventStack[EventSP].p[3].o = p4;
    EventStack[EventSP].eID = eID;
    r=RealThrow(EventStack[EventSP]);
    EventSP--;
    return r;
}

EvReturn ThrowEffDir(int16 Ev,rID eID,Dir d,Object *p1, Object *p2, Object*p3, Object *p4) {
    EvReturn r;
    EventSP++;
    CHECK_OVERFLOW; 
    EventStack[EventSP].Clear();
    EventStack[EventSP].Event = Ev;
    EventStack[EventSP].p[0].o = p1;
    EventStack[EventSP].p[1].o = p2;
    EventStack[EventSP].p[2].o = p3;
    EventStack[EventSP].p[3].o = p4;
    EventStack[EventSP].eID = eID;
    EventStack[EventSP].EDir = d;
    EventStack[EventSP].isDir = true;
    r=RealThrow(EventStack[EventSP]);
    EventSP--;
    return r;
}

EvReturn ThrowEffXY(int16 Ev,rID eID,int16 x,int16 y,Object *p1, Object *p2, Object*p3, Object *p4) {
    EvReturn r;
    EventSP++;
    CHECK_OVERFLOW; 
    EventStack[EventSP].Clear();
    EventStack[EventSP].Event = Ev;
    EventStack[EventSP].p[0].o = p1;
    EventStack[EventSP].p[1].o = p2;
    EventStack[EventSP].p[2].o = p3;
    EventStack[EventSP].p[3].o = p4;
    EventStack[EventSP].eID = eID;
    EventStack[EventSP].EXVal = x;
    EventStack[EventSP].EYVal = y;
    EventStack[EventSP].isLoc = true;
    r=RealThrow(EventStack[EventSP]);
    EventSP--;
    return r;
}
	
/*   This if specifically for triggering one effect within another.
   We want the outer event's data to propagate to the inner event,
   but not the other way around -- so that, for example, we don't
   mess up the original event's efNum, EMagic, etc. in the MagicEvent
   loop. In a normal ReThrow, changes to the inner event's data are
   propagated to the outer event. We want to propagate outer->inner,
   but not the reverse, in this case. */
EvReturn RedirectEff(EventInfo &e, rID eID, int16 Ev)
  {
    EvReturn r;
    EventSP++;
    CHECK_OVERFLOW; 
    EventStack[EventSP].Clear();
    EventStack[EventSP] = e;
    EventStack[EventSP].eID = eID;
    EventStack[EventSP].Event = Ev;
    /* Let an activated item call a spell that doesn't
       have EF_ACTIVATE[N] set. */
    EventStack[EventSP].isActivation = false;
  
    if (eID && Ev == EV_EFFECT && TEFF(eID)->Vals(0)->qval && 
         e.EActor->isPlayer() && !e.isTrap && !e.isActOfGod)
      T1->EffectPrompt(EventStack[EventSP], TEFF(e.eID)->Vals(0)->qval);
  
    r = RealThrow(EventStack[EventSP]);
    EventSP--;
    return r;
  }

EvReturn ThrowLoc(int16 Ev,int16 x,int16 y,Object *p1, Object *p2,Object*p3,
	Object *p4)
	{
		EvReturn r;
    EventSP++;
    CHECK_OVERFLOW; 
    EventStack[EventSP].Clear();
    EventStack[EventSP].Event = Ev;
		EventStack[EventSP].p[0].o = p1;
    EventStack[EventSP].p[1].o = p2;
    EventStack[EventSP].p[2].o = p3;
    EventStack[EventSP].p[3].o = p4;
    EventStack[EventSP].EXVal = x;
    EventStack[EventSP].EYVal = y; 
    EventStack[EventSP].isLoc = true;
    r=RealThrow(EventStack[EventSP]);
    EventSP--;
		return r;
	}
  

EvReturn ThrowDmg(int16 Ev,int16 DType,int16 DmgVal, const char*s,Object *p1, Object *p2,Object*p3, Object *p4)
  {
		EvReturn r;
    EventSP++;
    CHECK_OVERFLOW; 
    EventStack[EventSP].Clear();
    EventStack[EventSP].Event = Ev;
		EventStack[EventSP].p[0].o = p1;
    EventStack[EventSP].p[1].o = p2;
    EventStack[EventSP].p[2].o = p3;
    EventStack[EventSP].p[3].o = p4;
    EventStack[EventSP].DType = (int8)DType;
    EventStack[EventSP].vDmg = DmgVal;
    EventStack[EventSP].GraveText = s;
    r=RealThrow(EventStack[EventSP]);
    EventSP--;
		return r;
	}

// ww: only works when the victim is standing on the terrain ...
EvReturn ThrowTerraDmg(int16 Ev, int16 DType, int16 DmgVal, const char*s, Object *victim, rID trID) {
    EvReturn r; Map *m;
    if ( !victim || (!((Thing *)victim)->m) )
        return DONE; 

    ASSERT(victim); 
    EventSP++;
    CHECK_OVERFLOW; 
    EventStack[EventSP].Clear();
    EventStack[EventSP].Event = Ev;
    EventStack[EventSP].EMap = m = ((Thing *)victim)->m;
    EventStack[EventSP].p[0].o = ((Thing *)victim)->m->GetTerraCreator(
        ((Thing *)victim)->x,((Thing *)victim)->y);
    if (!EventStack[EventSP].p[0].o)
        EventStack[EventSP].p[0].o = victim;
    EventStack[EventSP].p[1].o = victim;
    EventStack[EventSP].DType = (int8)DType;
    EventStack[EventSP].vDmg = DmgVal;
    EventStack[EventSP].GraveText = s;

    if (trID != m->TerrainAt(((Thing *)victim)->x,((Thing *)victim)->y)) {
        int16 i;
        if (Ev == EV_DAMAGE)
            EventStack[EventSP].effIllusion = true;
        for (i=0;m->Fields[i];i++)
            if (m->Fields[i]->FType & FI_ITERRAIN)
                if (m->Fields[i]->inArea(((Thing *)victim)->x,((Thing *)victim)->y))
                    EventStack[EventSP].p[0].o = oThing(m->Fields[i]->Creator);           
    }

    r=RealThrow(EventStack[EventSP]);
    EventSP--;
    return r;
}


EvReturn ThrowDmgEff(int16 Ev,int16 DType,int16 DmgVal, const char*s, rID eID, Object *p1, Object *p2,Object*p3, Object *p4) {
	EvReturn r;
    EventSP++;
    CHECK_OVERFLOW; 
    EventStack[EventSP].Clear();
    EventStack[EventSP].Event = Ev;
	EventStack[EventSP].p[0].o = p1;
    EventStack[EventSP].p[1].o = p2;
    EventStack[EventSP].p[2].o = p3;
    EventStack[EventSP].p[3].o = p4;
    EventStack[EventSP].eID = eID;
    EventStack[EventSP].DType = (int8)DType;
    EventStack[EventSP].vDmg = DmgVal;
    EventStack[EventSP].GraveText = s;
    r=RealThrow(EventStack[EventSP]);
    EventSP--;
	return r;
}


