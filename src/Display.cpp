/* DISPLAY.CPP -- See the Incursion LICENSE file for copyright information.

     Includes all functions governing the placement of Things
   on a Map, and moving them about once they're placed. Also, 
   miscellaneous Map functions that do not relate to dungeon 
   generation, especially the code to handle animated Overlays.

     Thing::Thing(Glyph img, int8 Type)
     void Thing::PlaceAt(Map *m, int16 x, int16 y)
     int16 Thing::DistFromPlayer()
     int16 Thing::DistFrom(Thing *t)
     void Thing::PlaceNear(int16 x, int16 y)
     Map::Map()
     void Thing::NotifyGone(hObj h)
     void Player::NotifyGone(hObj h)
     void Map::NotifyGone(hObj h)
     Thing* Map::GetAt(int16 x,int16 y)
     bool Map::OpenAt(int16 x, int16 y)
     bool Map::besideWall(int16 x,int16 y)
     bool Creature::isBeside(Thing *t);
     void Map::RegisterPlayer(hObj h)
     void Map::VUpdate(int16 x, int16 y)
     void Map::Load(rID mID)

     void Overlay::Activate()
     void Overlay::DeActivate()
     void Overlay::AddGlyph(int16 x,int16 y, Glyph g)
     void Overlay::RemoveGlyph(int16 x,int16 y)
     bool Overlay::IsGlyphAt(int16 x, int16 y)
     void Overlay::RemoveGlyph(int16 n)
     void Overlay::ShowGlyphs()

     void Thing::DoTurn()
     void Thing::Move(int16 newx,int16 newy, bool is_walk)
     Thing* Thing::ProjectTo(int16 tx, int16 ty, int8 range)
     void Thing::Show()
     EvReturn Thing::Event(EventInfo &e)
     void Thing::Remove(bool isDelete, bool keepMobileFields)
     void Item::Remove(bool isDelete, bool keepMobileFields)

*/ 

#include "Incursion.h"
#include "MapAudit.h"

/* Diagnostic only, for bead inc-6d5 ("Contents list wierdless in
   Thing::Remove!"). Logs every Move/Remove/PlaceAt transition for a
   name-matched creature (default "Volgar,Gell" -- the two specimens a fresh
   40-seed dive.keys sweep produced; override with INC6D5_PROBE_NAMES, a
   comma-separated list) to logs/inc6d5-probe.log, with a call stack, so the
   exact site that leaves m/x/y set while dropping the object from both
   Things[] and the square's Contents chain can be read off directly instead
   of guessed at. Build with:
     EXTRA_CXXFLAGS=-DINC6D5_PROBE OUT=incursion-inc6d5probe BACKEND=posix ./build_macos.sh
   Not wired into any normal build. */
#ifdef INC6D5_PROBE
#include <execinfo.h>
#include <cstring>
static FILE *Inc6d5ProbeLog() {
    static FILE *f = NULL;
    if (!f) {
        char path[1024];
        snprintf(path, sizeof(path), "%slogs/inc6d5-probe.log",
            (const char*)T1->IncursionDirectory);
        f = fopen(path, "a");
    }
    return f;
}
static bool Inc6d5ProbeNameMatch(Thing *t) {
    char buf[256], *tok, *save = NULL;
    const char *names;
    String nm;
    if (!t || !t->isCreature())
        return false;
    names = getenv("INC6D5_PROBE_NAMES");
    if (!names || !*names)
        names = "Volgar,Gell";
    snprintf(buf, sizeof(buf), "%s", names);
    nm = t->Name(0);
    for (tok = strtok_r(buf, ",", &save); tok; tok = strtok_r(NULL, ",", &save))
        if (strstr((const char*)nm, tok))
            return true;
    return false;
}
/* Once a name-matched creature's resting square is known, anyone else who
   touches that exact (map,x,y) also gets logged -- not just the specimen
   itself -- so a second object corrupting the specimen's square shows up
   even though it never matches by name. Updated only from
   Inc6d5ProbeWatchUpdate(), called at confirmed-settled points (not from
   mid-transition states where x/y are transiently -1 or stale). */
static Map *g_watchMap = NULL;
static int16 g_watchX = -1, g_watchY = -1;
static void Inc6d5ProbeWatchUpdate(Thing *t) {
    if (!Inc6d5ProbeNameMatch(t) || !t->m || t->x < 0 || t->y < 0)
        return;
    g_watchMap = t->m;
    g_watchX = t->x;
    g_watchY = t->y;
}
static bool Inc6d5ProbeMatch(Thing *t) {
    if (!t || !t->isCreature())
        return false;
    if (Inc6d5ProbeNameMatch(t))
        return true;
    if (g_watchMap && t->m == g_watchMap && t->x == g_watchX && t->y == g_watchY)
        return true;
    return false;
}
static void Inc6d5Probe(const char *site, Thing *t, const char *extra) {
    FILE *f; void *frames[16]; int n, i; char **syms;
    if (!Inc6d5ProbeMatch(t))
        return;
    f = Inc6d5ProbeLog();
    if (!f)
        return;
    fprintf(f, "turn %u  %-28s %s/%d  m=%p x=%d y=%d  %s\n",
        (unsigned)(theGame ? theGame->Turn : 0), site,
        (const char*)t->Name(0), (int)t->myHandle, (void*)t->m,
        (int)t->x, (int)t->y, extra ? extra : "");
    n = backtrace(frames, 16);
    syms = backtrace_symbols(frames, n);
    if (syms) {
        for (i = 0; i < n; i++)
            fprintf(f, "    %s\n", syms[i]);
        free(syms);
    }
    fflush(f);
}
/* Unconditional (not name-filtered): the MoveDepth followers loop mutates
   m->Things[] while iterating it by index (see the call site) -- log every
   handle it visits, and every Remove(false) it issues, so a skipped index
   shows up as a gap between what MapIterate visited and what actually left
   the map. */
static void Inc6d5ProbeIter(const char *site, int16 idx, hObj h) {
    FILE *f = Inc6d5ProbeLog();
    const char *nm = "?";
    if (!f)
        return;
    if (theRegistry->Exists(h) && oThing(h)->isCreature())
        nm = (const char*)oThing(h)->Name(0);
    fprintf(f, "turn %u  %-28s idx=%d handle=%d %s\n",
        (unsigned)(theGame ? theGame->Turn : 0), site, (int)idx, (int)h, nm);
    fflush(f);
}
#define INC6D5_PROBE_CALL(site,t,extra) Inc6d5Probe(site,t,extra)
#define INC6D5_PROBE_ITER(site,idx,h) Inc6d5ProbeIter(site,idx,h)
#define INC6D5_PROBE_SETTLED(t) Inc6d5ProbeWatchUpdate(t)
#else
#define INC6D5_PROBE_CALL(site,t,extra) ((void)0)
#define INC6D5_PROBE_ITER(site,idx,h) ((void)0)
#define INC6D5_PROBE_SETTLED(t) ((void)0)
#endif

Thing::Thing(Glyph _Image,int16 _Type)
    : Object(_Type)
  {
    x=y=-1;
    Image=_Image;
    m=NULL; 
    Timeout=0;
    Flags=0;
    __Stati.Initialize(); 
  }

void Thing::PlaceAt(Map*_m,int16 _x,int16 _y, bool share_square)              
  {            
    bool isBig = false;
    Field MyFields[12]; 
    int16 i, fc; Creature *mount;

  const int ox = x;
  const int oy = y; 

  if (!_m) return;

    INC6D5_PROBE_CALL("PlaceAt:entry", this, "");

    if (isCreature())
      {
        /* ASSUMPTION: Templates, magic, et al., won't cause creatures
           to grow more than one size category. This is wrong in a few
           cases (dire animal drinks Potion of Enlargement), but its
           good enough in general. */
        if (thisc->GetAttr(A_SIZ) == 0)
          if (TMON(thisc->mID)->Size >= SZ_LARGE)
            thisc->CalcValues();
        if (thisc->GetAttr(A_SIZ) >= SZ_HUGE)
          isBig = true;
      }

    /* Temporary assumption: mounts don't emit mobile fields.
       This is a very, very shaky assumption (dragons casting
       Spook, etc.) Fix soon. */

    if (HasStati(MOUNTED))
      mount = (Creature*)GetStatiObj(MOUNTED);
    else
      mount = NULL;

    if (isType(T_CREATURE) && thisc->isMType(MA_DRAGON))
      thisc->GetAgeCatagory();

    /* This is a patchup to address the "generic item" bug. */
    if (Type == T_POTION || Type == T_SCROLL || Type == T_RING || Type == T_WAND ||
        Type == T_TOME || Type == T_AMULET || Type == T_CLOAK || Type == T_BRACERS)
      if (!thisi->eID)
        {
          Remove(true);
          return;
        }

    if (m == _m)
      { 
        Move(_x,_y); 
        Monster::AlertNew(this);
        if (this->isCreature()) {
          ((Creature *)this)->ts.Retarget((Creature *)this);
        }
        if (isCreature())
          thisc->TerrainEffects();
        return; 
      }

    if (ThrowXY(EV_PLACE,_x,_y,this) == ABORT)
      { INC6D5_PROBE_CALL("PlaceAt:earlyAbort1(m<-NULL,stillOldLists)", this, ""); m = NULL; return; }
    if (isDead()) {
      INC6D5_PROBE_CALL("PlaceAt:earlyDead1(stillOldLists)", this, "");
      return;
    }

    fc = 0;
    if (isCreature() && m)
      for (i=0;m->Fields[i];i++)
        if (m->Fields[i]->Creator == myHandle || (mount && 
              m->Fields[i]->Creator == mount->myHandle))
          if (m->Fields[i]->FType & FI_MOBILE)
            {
              MyFields[fc++] = *(m->Fields[i]);
              m->RemoveField(m->Fields[i]);
              i--;
            }
    ASSERT(fc < sizeof(MyFields) / sizeof(MyFields[0]));

    Remove(false);
    m  = _m;
    INC6D5_PROBE_CALL("PlaceAt:afterRemoveSetM", this, "");

    if (ThrowXY(EV_PLACE,_x,_y,this) == ABORT)
      { INC6D5_PROBE_CALL("PlaceAt:earlyAbort2(m<-NULL)", this, ""); m = NULL; return; }
    if (mount && ThrowXY(EV_PLACE,_x,_y,mount) == ABORT)
      { INC6D5_PROBE_CALL("PlaceAt:earlyAbort3(m<-NULL)", this, ""); m = NULL; return; }
    if (isDead()) {
      INC6D5_PROBE_CALL("PlaceAt:earlyDead2(m=new,unregistered!)", this, "");
      return;
    }

    if (isPlayer()) {
      if (m->Day != theGame->Day)
        m->DaysPassed();
      m->ResetImages();
      }



    ASSERT(m->InBounds(_x,_y));
    /* Patch to prevent crashes */
    if (!m->InBounds(_x,_y))
      _x = _y = 1;
    
    if (isCreature() && ((m->FCreatureAt(_x,_y) && !share_square) || 
          m->SolidAt(_x,_y) || isBig || m->FieldAt(_x,_y,FI_SIZE)))
        x = y = 1;
      else {
        x = _x;
        y = _y;
        }
    ASSERT(!oThing(myHandle)->isType(T_MAP));
    int where = m->Things.Add(myHandle);

    if (m->At(x,y).Contents)
      if (oThing(m->At(x,y).Contents)->isCreature())
        {
          Next = oThing(m->At(x,y).Contents)->Next;
          oThing(m->At(x,y).Contents)->Next = myHandle;
          goto DoneContentsAdd;
        }

    Next = m->At(x,y).Contents;
    m->At(x,y).Contents = myHandle;
    DoneContentsAdd:
    INC6D5_PROBE_CALL("PlaceAt:registered", this, "");
    INC6D5_PROBE_SETTLED(this);

    if (isPlayer()) {
      m->RegisterPlayer(myHandle);
      thisp->MyTerm->SetMap(m);
			thisp->MyTerm->AdjustMap(_x,_y,true);
      thisp->UpdateMap = true;
      }
    if (isFeature())
      ;
    else if (_x != x || y != _y)
      PlaceNear(_x,_y);
    if (!m)
      return;

    Monster::AlertNew(this);
    if (this->isCreature())
      ((Creature *)this)->ts.Retarget((Creature *)this);

    if (m && m->At(x,y).hasField)
      for(i=0;m && m->Fields[i];i++)
        if (m->Fields[i]->inArea(x,y)) {
          ThrowField(EV_FIELDON,m->Fields[i],this);
          if (isDead())
            return;
          if (mount)
            ThrowField(EV_FIELDON,m->Fields[i],mount);
          }

    if (isCreature() && m) {
      /* upstream: base-code defect, the fix is ours. Tier Traced -- the
         harvest above collects fields created by this creature OR BY ITS
         MOUNT (line 234), and this line re-created every one of them with
         the RIDER as creator. So a steed's aura changed hands at every
         staircase. Three things follow, and all three were reported from
         play: the rider stops being affected, because the spell spares its
         own caster and the caster is now him; the steed starts being
         affected, because it no longer counts as the caster; and the steed
         recasts without end, because the guard that asks "is my aura already
         up?" looks for a field IT created (src/Monster.cpp:2350,
         src/Magic.cpp:2362) and every one of them now names the rider. The
         count grows by one per level, which is where four Spook rows in one
         dismiss menu came from (src/Skills.cpp:398 lists only the player's
         own fields). Upstream's rather than the port's: plain control flow,
         no dependence on integer width, the typedefs or the compiler.
         Tracking inc-izzy. Not sent. */
      for(i=0;i!=fc;i++) {
        Creature *fCreator = (Creature*)this;
        if (MyFields[i].Creator && theRegistry->Exists(MyFields[i].Creator) &&
            oThing(MyFields[i].Creator)->isCreature())
          fCreator = (Creature*)oThing(MyFields[i].Creator);
        m->NewField(MyFields[i].FType,x,y,MyFields[i].rad,MyFields[i].Image,
          MyFields[i].Dur, MyFields[i].eID,fCreator);
      }
      if (thisc->HasAbility(CA_AURA_OF_VALOUR)) {
        rID vID = FIND("Aura of Valour");
        ASSERT(vID);
        for(i=0;m->Fields[i];i++)
          if (m->Fields[i]->Creator == myHandle)
            if (m->Fields[i]->eID == vID)
              goto ValourExists;
        m->NewField(FI_MOBILE|FI_MODIFIER,x,y,3,GLYPH_VALUE(GLYPH_FLOOR2, WHITE),-1,vID,thisc);
        ValourExists:;
        }
      if (m == NULL)
        return;
      thisc->TerrainEffects();
      if (mount)
        mount->TerrainEffects();
      if (isDead())
        return;

    }

    if (!HasStati(HOME_REGION) && !isPlayer()) {
      if (m->InBounds(x,y)) {
        rID rid = m->RegionAt(x,y);
        if (rid) {
          GainPermStati(HOME_REGION,NULL,SS_MISC,x+y*256,0,rid);
          if (isType(T_CHEST)) {
            Item *it = oItem(((Container*)this)->Contents);
            while (it) {
              if (!it->HasStati(HOME_REGION))
                it->GainPermStati(HOME_REGION,NULL,SS_MISC,x+y*256,0,rid);
              it = oItem(it->Next);    
              }
            }
          } 
        }
      }

      
    /* PlaceNear calls Move, which calls AlertNew */
    if (isType(T_DOOR))
      ((Door*)this)->SetImage();

    if (theGame->InPlay() && !isDead())
      m->Update(x,y);
    
  }                              


/*inline*/ int16 Thing::DistFromPlayer()
 	{
    int16 dx,dy;
    
    dx = abs(x - oPlayer(m->pl[0])->GetX());
    dy = abs(y - oPlayer(m->pl[0])->GetY());
    return x==-1?0:(dx > dy ? dx+dy/2 : dy+dx/2);
  }

/*inline*/ int16 Thing::DistFrom(Thing*t)
 	{
    int16 dx,dy;
    dx = abs(x - t->GetX());
    dy = abs(y - t->GetY());
    return x==-1?0:(dx > dy ? dx+dy/2 : dy+dx/2);
  }

void Thing::PlaceNear(int16 x,int16 y)
  {
    static Creature* Displace[64], *cr; 
    bool isBig = false;
    uint8 i, ix, iy, sz, dc = 0;
    int16 r, tx, ty, c, cx[120], cy[120];
    
    ASSERT(m); 

    if (isCreature())
      {
        /* ASSUMPTION: Templates, magic, et al., won't cause creatures
           to grow more than one size category. This is wrong in a few
           cases (dire animal drinks Potion of Enlargement), but its
           good enough in general. */
        if (thisc->GetAttr(A_SIZ) == 0)
          if (TMON(thisc->mID)->Size >= SZ_LARGE)
            thisc->CalcValues();
        if (thisc->GetAttr(A_SIZ) >= SZ_HUGE)
          { isBig = true;
            sz = (uint8)thisc->GetAttr(A_SIZ); }
      }

    bool isRetry = false;
    
    TryAgain:

    for (r=0;r<=(isPlayer() ? 40 : 6);r++) {
      c = 0;
      for (tx=(x-r);tx<=(x+r);tx++)
        for (ty=(y-r);ty<=(y+r);ty++)
          if (abs(x-tx)==r || abs(y-ty)==r)
            {
              PurgeStrings();
              if (!m->InBounds(tx,ty))
                continue;
              if (m->SolidAt(tx,ty))
                  continue;
              if (m->FallAt(tx,ty) && !(isCreature() && thisc->isAerial()))
                continue;
              if (TTER(m->TerrainAt(tx,ty))->HasFlag(TF_WARN)  && 
                  ((!isCreature()) ||
                  TTER(m->TerrainAt(tx,ty))->PEvent(EV_MON_CONSIDER,this,
                  m->TerrainAt(tx,ty)) == ABORT))
                continue;
              if (m->FCreatureAt(tx,ty))
                if (m->FCreatureAt(tx,ty) != this)
                  if (!isRetry || m->FCreatureAt(tx,ty)->GetAttr(A_SIZ) > SZ_LARGE ||
                        isBig)
                    continue;
              if (isBig) {
                dc = 0;
                for (ix = tx - FaceRadius[sz]; ix <= tx + FaceRadius[sz]; ix++)
                  for (iy = ty - FaceRadius[sz]; iy <= ty + FaceRadius[sz]; iy++)
                    if (m->InBounds(ix,iy))  
                      if (dist(ix,iy,tx,ty) <= FaceRadius[sz])
                        {                      
                          /* Can't place here if bulk intersects walls */
                          if (m->SolidAt(ix,iy))
                            goto NotAnOption;
                          /* Can't place here if bulk intersects another size field */
                          /*
                          if (m->FieldAt(ix,iy,FI_SIZE))
                            if (m->FCreatureAt(ix,iy) != this)
                              goto NotAnOption;
                          */
                          for (cr = m->FCreatureAt(ix,iy);cr;cr=m->NCreatureAt(ix,iy))
                            if (cr->GetAttr(A_SIZ) >= SZ_HUGE)
                              if (cr != this)
                                goto NotAnOption;                   
                        }
                }
              /* This spot would be OK */
              cx[c] = tx;
              cy[c] = ty;
              c++;           
              NotAnOption:
              ;
            }
            
        
            
        if (c)
          {
            
            c = random(c);
            tx = cx[c];
            ty = cy[c];
            dc = 0;
            if (isBig)
              for (ix = tx - FaceRadius[sz]; ix <= tx + FaceRadius[sz]; ix++)
                for (iy = ty - FaceRadius[sz]; iy <= ty + FaceRadius[sz]; iy++)
                  if (m->InBounds(ix,iy))  
                    if (dist(ix,iy,tx,ty) <= FaceRadius[sz])
                      for (cr = m->FCreatureAt(ix,iy);cr;cr=m->NCreatureAt(ix,iy))
                        {
                          if (cr == this)
                            continue;
                          ASSERT(cr->GetAttr(A_SIZ) < SZ_HUGE);
                          Displace[dc++] = cr;
                        }
            goto FoundGoodPlace;
          } 
      }
      
    if (!isRetry) { 
        isRetry = true; 
        goto TryAgain;
    }
      
    /* So we've finished the loop and have not found any good
    place to put ourselves. */
    if (isPlayer()) {
        IPrint("[ Deleting obstacles. ]");
        while (m->FirstAt(x,y))
            m->FirstAt(x,y)->Remove(true);
        Move(x,y);
    } else {
        /*
        if (theGame->GetPlayer(0)->WizardMode)
        theGame->GetPlayer(0)->IPrint("You hear a disturbing *crunch*. (<Str> "
        "deleted due to lack of open space to place it.)",(const char *)Name(0));        
        */
        Remove(true);
    }
    return;
      
FoundGoodPlace:
    if (isBig)
        for (i=0;i!=dc;i++)
            Displace[i]->Remove(false);
    Move(tx,ty);
    
    // ww: this can cause a stack overflow when PlaceAt calls
    // PlaceNear calls PlaceAt -> perhaps two big creatures
    // ping-ponging each other? 
    if (isBig && dc) {
        for (i=0;i!=dc;i++) {
            ASSERT(Displace[i]->GetAttr(A_SIZ) < SZ_HUGE);
            Displace[i]->PlaceAt(m,tx,ty);
        }
    }
    
    {
        Thing *il; int16 i;
        for(i=0;backRefs[i];i++)
            if (theRegistry->Exists(backRefs[i]))
                if ((il = oThing(backRefs[i]))->isIllusion())
                    if (il->GetStatiObj(ILLUSION) == this)
                        il->IllusionLOSCheck(false);
    }
}

Map::Map() : Object(T_MAP), ov(myHandle)
	{
          nextAvailableTerraKey = 0; 
	}

void Thing::NotifyGone(hObj h)
  {
    RemoveStatiFrom(oThing(h));
  }

void Player::NotifyGone(hObj h)
  {
    RemoveStatiFrom(oThing(h));
    MyTerm->NotifyGone(h);
    if (Inv[0] == h)
      Inv[0] = 0;
  }

/* rmt: I think this is to deal with the fallout of a bug when remove(isDelete=true) was called
   and only mobile fields were removed.  That made sense for remove(isDelete=false) of course.
   TODO: Work out if this ever serves a purpose anymore.  It was buggy anyhow, as the creator
   no longer existed which meant that the event could not go out as there was no way to set the
   EActor value to the originating creator object. */
void Map::NotifyGone(hObj h)
  { 
    int16 i;
    StartSearch:
    for(i=0;Fields[i];i++)
      if (Fields[i]->Creator == h)
        { RemoveField(Fields[i]); goto StartSearch; }
  }

#if 0

bool Map::PileAt(int16 x, int16 y)
  {
    Thing *t = oThing(At(x,y).Contents); 
    int16 ic = 0;
    while (t) {
      if (t->isItem())
        ic++;
      if (ic >= 2)
        return true;
      t = oThing(t->Next);
      }
    return false;
  }

bool Map::MultiAt(int16 x, int16 y)
  {
    Thing *t = oThing(At(x,y).Contents); 
    int16 cc = 0;
    while (t) {
      if (t->isCreature())
        cc++;
      if (cc >= 2)
        return true;
      t = oThing(t->Next);
      }
    if (FieldAt(x,y,FI_SIZE))
      if (cc)
        return true;
    return false;
  }


Container* Map::ChestAt(int16 x, int16 y)
  {
    Thing *t = oThing(At(x,y).Contents); 
    int16 ic = 0;
    while (t) {
      if (t->isType(T_CHEST))
        return (Container*)t;
      t = oThing(t->Next);
      }
    return false;
  }

Trap* Map::TrapAt(int16 x, int16 y)
  {
    Thing *t = oThing(At(x,y).Contents); 
    int16 ic = 0;
    while (t) {
      if (t->isType(T_TRAP))
        return (Trap*)t;
      t = oThing(t->Next);
      }
    return false;
  }


Item* Map::ItemAt(int16 x,int16 y)
	{
		Thing *t = oThing(At(x,y).Contents);
    while (t) {
      if (t->isItem())
        return (Item*)t;
      t = oThing(t->Next);
      }
    return NULL;
	}

Feature* Map::FeatureAt(int16 x,int16 y)
	{
		Thing *t = oThing(At(x,y).Contents);
    while (t) {
      if (t->isFeature())
        return (Feature*)t;
      t = oThing(t->Next);
      }
    return NULL;
	}

Door* Map::DoorAt(int16 x,int16 y)
	{
		Thing *t = oThing(At(x,y).Contents);
    while (t) {
      if (t->isType(T_DOOR))
        return (Door*)t;
      t = oThing(t->Next);
      }
    return NULL;
	}


Creature* Map::CreatureAt(int16 x,int16 y)
	{
  if (!InBounds(x,y)) return NULL;
		int16 i;
		Thing *t;

    if (FieldAt(x,y,FI_SIZE)) 
      {
        for(i=0;Fields[i];i++)
          if (Fields[i]->inArea(x,y))
            if (Fields[i]->FType & FI_SIZE)
              return oCreature(Fields[i]->Creator);
        Error("Corrupted data for FI_SIZE field!");
      }
        
    t = oThing(At(x,y).Contents);
    while (t) {
      if (t->isCreature())
        return (Creature*)t;
      t = oThing(t->Next);
      }
    return NULL;
	}


#endif

bool Map::PMultiAt(int16 x, int16 y, Creature *POV)
  {
    Thing *t = oThing(At(x,y).Contents); 
    int16 cc = 0;
    while (t) {
      if (t->isCreature() && POV->Perceives(t))
        cc++;
      if (cc >= 2)
        return true;
      t = oThing(t->Next);
      }
    if (FieldAt(x,y,FI_SIZE))
      if (cc)
        return true;
    return false;
  }


Feature* Map::KnownFeatureAt(int16 x,int16 y)
{
  Thing *t = oThing(At(x,y).Contents);
  while (t) {
    if (t->isFeature()) {
      if (t->Type == T_TRAP && ! (((Trap *)t)->TrapFlags & TS_FOUND))
        ;
      else if (t->Type == T_DOOR && (((Door *)t)->DoorFlags & DF_SECRET))
        ;
      else return (Feature*)t;
    }
    t = oThing(t->Next);
  }
  return NULL;
}

	
/* Diagnostic only, for bead inc-5xn and upstream issue #40. rmtew asked what an
   out-of-bounds lookup actually does to the player -- how the monster behaves
   before with the incorrect lookups, and how it behaves afterwards with the
   failures. The error log cannot answer that. It counts how often the game
   read off the edge of the map; it does not say whether the wrong answer was
   empty or was a real creature standing at (0,0), and it says nothing at all
   about what the caller then did.

   So this probe records two things the log does not:

     1. For every out-of-bounds GetAt, the COUNTERFACTUAL -- the Thing the
        unguarded upstream code would have returned for that same call, which
        is whatever the (0,0) square holds. An out-of-bounds read that would
        have returned NULL changes nothing for the player; one that would have
        returned a creature is the case rmtew is asking about.
     2. What Monster::ChooseAction() did with it (see src/Monster.cpp).

   INCURSION_OOB_PROBE=1 turns it on and writes logs/oobprobe.log. Totals go in
   every 1000 calls and again at exit, so a crashed session still reports its
   count; a full detail line is written only when the counterfactual is
   non-NULL, which keeps a long soak's log small.

   Building with -DINCURSION_OOB_UNGUARDED removes the guard below, restoring
   upstream's behaviour exactly, so the two binaries can be run over the same
   seeds and compared:

     EXTRA_CXXFLAGS=-DINCURSION_OOB_PROBE OUT=incursion-oob-after \
       BACKEND=posix ./build_macos.sh
     EXTRA_CXXFLAGS="-DINCURSION_OOB_PROBE -DINCURSION_OOB_UNGUARDED" \
       OUT=incursion-oob-before BACKEND=posix ./build_macos.sh

   Not wired into any normal build. Delete this, the two call sites and the
   Monster.cpp probe together when inc-5xn closes. */
#ifdef INCURSION_OOB_PROBE
#include <cstdlib>
#include <cstring>
#include <execinfo.h>

static long long OobCalls = 0;         /* out-of-bounds GetAt calls seen        */
static long long OobWouldReturn = 0;   /* ...of which would have yielded a Thing */
static long long OobAmbush = 0;        /* hiding-monster ambushes on such a Thing */

bool OobProbeOn(void)
  {
    static int on = -1;
    const char *e;
    if (on == -1)
      { e = getenv("INCURSION_OOB_PROBE");
        on = (e && *e && *e != '0') ? 1 : 0; }
    return on == 1;
  }

FILE *OobProbeLog(void)
  {
    static FILE *f = NULL;
    char path[1024];
    if (!f)
      { snprintf(path, sizeof(path), "%slogs/oobprobe.log",
            (const char*)T1->IncursionDirectory);
        f = fopen(path, "a");
        if (f)
          setvbuf(f, NULL, _IOLBF, 0); }
    return f;
  }

static void OobProbeCensusDump(FILE *f);
static void OobProbeRectDump(FILE *f);
static void OobProbePwsDump(FILE *f);
static void OobProbePwpDump(FILE *f);
static void OobProbeRmdDump(FILE *f);
static void OobProbeRmoDump(FILE *f);
static void OobProbeGeomDump(FILE *f);
static void OobProbeDoorDump(FILE *f);

void OobProbeTotals(const char *why)
  {
    FILE *f = OobProbeLog();
    if (!f)
      return;
    fprintf(f, "TOTALS %-8s oob_calls=%lld would_return_thing=%lld ambushes=%lld\n",
        why, (long long)OobCalls, (long long)OobWouldReturn,
        (long long)OobAmbush);
    if (why && !strcmp(why, "atexit"))
      { OobProbeDoorDump(f); OobProbeGeomDump(f); OobProbeRmoDump(f); OobProbeRmdDump(f); OobProbePwpDump(f); OobProbePwsDump(f); OobProbeRectDump(f); OobProbeCensusDump(f); }
  }

static void OobProbeAtExit(void)
  { OobProbeTotals("atexit"); }

/* The caller census. The error log keeps one call stack per distinct message,
   so 47,954 out-of-bounds reads in a session are represented by a single
   stack, and that one stack was read as if it spoke for all of them. This
   counts every out-of-bounds Map::At() by its own call stack, so the callers
   can be named and ranked instead of inferred.

   Stacks are hashed and counted at the call site and symbolised only at exit,
   because symbolising 48,000 times would dominate the run. */
void OobProbeTouch(void);

#define OOB_STACK_DEPTH 8
#define OOB_MAX_STACKS   64

static void  *OobStackFrames[OOB_MAX_STACKS][OOB_STACK_DEPTH];
static long long OobStackCount[OOB_MAX_STACKS];
static int    OobStackDepth[OOB_MAX_STACKS];
static int    OobStacksSeen = 0;
static long long OobAtCalls = 0;
static long long OobAtUncounted = 0;

static int  OobStackX[OOB_MAX_STACKS][2];   /* min,max x asked for  */
static int  OobStackY[OOB_MAX_STACKS][2];
static int  OobStackMap[OOB_MAX_STACKS][2]; /* the map size at the time */

static void OobRecordCoord(int i, int x, int y, int sx, int sy, bool first)
  {
    if (first)
      { OobStackX[i][0] = OobStackX[i][1] = x;
        OobStackY[i][0] = OobStackY[i][1] = y;
        OobStackMap[i][0] = sx; OobStackMap[i][1] = sy;
        return; }
    if (x < OobStackX[i][0]) OobStackX[i][0] = x;
    if (x > OobStackX[i][1]) OobStackX[i][1] = x;
    if (y < OobStackY[i][0]) OobStackY[i][0] = y;
    if (y > OobStackY[i][1]) OobStackY[i][1] = y;
  }

void OobProbeAtCensus(int x, int y, int sizeX, int sizeY)
  {
    void *frames[OOB_STACK_DEPTH];
    int n, i, j;
    static bool busy = false;

    if (!OobProbeOn())
      return;
    /* Error() logs the assert that brought us here, and anything it touches
       must not re-enter the census. */
    if (busy)
      return;
    busy = true;
    OobProbeTouch();          /* so a session with no GetAt call still reports */
    OobAtCalls++;

    n = backtrace(frames, OOB_STACK_DEPTH);
    for (i = 0; i < OobStacksSeen; i++)
      {
        if (OobStackDepth[i] != n)
          continue;
        for (j = 1; j < n; j++)          /* frame 0 is this function */
          if (OobStackFrames[i][j] != frames[j])
            break;
        if (j == n)
          { OobStackCount[i]++;
            OobRecordCoord(i,x,y,sizeX,sizeY,false);
            busy = false; return; }
      }
    if (OobStacksSeen < OOB_MAX_STACKS)
      {
        for (j = 0; j < n; j++)
          OobStackFrames[OobStacksSeen][j] = frames[j];
        OobStackDepth[OobStacksSeen] = n;
        OobStackCount[OobStacksSeen] = 1;
        OobRecordCoord(OobStacksSeen,x,y,sizeX,sizeY,true);
        OobStacksSeen++;
      }
    else
      OobAtUncounted++;
    busy = false;
  }

static void OobProbeCensusDump(FILE *f)
  {
    int i, j, k, best;
    char **syms;
    bool done[OOB_MAX_STACKS];

    fprintf(f, "CENSUS out_of_bounds_At_calls=%lld distinct_stacks=%d "
               "uncounted_over_cap=%lld\n",
        OobAtCalls, OobStacksSeen, OobAtUncounted);
    for (i = 0; i < OobStacksSeen; i++)
      done[i] = false;
    for (k = 0; k < OobStacksSeen; k++)
      {
        best = -1;
        for (i = 0; i < OobStacksSeen; i++)
          if (!done[i] && (best < 0 || OobStackCount[i] > OobStackCount[best]))
            best = i;
        if (best < 0)
          break;
        done[best] = true;
        fprintf(f, "\n  %lld calls  (%.2f%% of %lld)  x=%d..%d y=%d..%d "
                   "map=%dx%d\n", OobStackCount[best],
            OobAtCalls ? (100.0 * OobStackCount[best]) / OobAtCalls : 0.0,
            OobAtCalls, OobStackX[best][0], OobStackX[best][1],
            OobStackY[best][0], OobStackY[best][1],
            OobStackMap[best][0], OobStackMap[best][1]);
        syms = backtrace_symbols(OobStackFrames[best], OobStackDepth[best]);
        if (!syms)
          continue;
        for (j = 1; j < OobStackDepth[best]; j++)
          fprintf(f, "    %s\n", syms[j]);
        free(syms);
      }
  }

/* The rect census. RANDOM_OPEN picks a square with
   y = r.y1 + random(r.y2 - r.y1). random() is genrand_int32() %% mx, so a
   negative mx makes the modulus unsigned and the result an arbitrary int16.
   This counts how often the macro runs with an inverted rect, which is the
   condition that turns a random square into a wild coordinate. */
static long long OobRectCalls = 0, OobRectInverted = 0;
static int OobRectWorstX = 0, OobRectWorstY = 0;
static int OobRectFirstLine = 0, OobRectFirstVals[4];

void OobProbeRect(int line, int x1, int y1, int x2, int y2)
  {
    int dx, dy;
    if (!OobProbeOn())
      return;
    OobRectCalls++;
    if (!x2)                       /* the OpenX/OpenY branch, not this one */
      return;
    dx = x2 - x1;
    dy = y2 - y1;
    if (dx >= 0 && dy >= 0)
      return;
    OobRectInverted++;
    if (dx < OobRectWorstX) OobRectWorstX = dx;
    if (dy < OobRectWorstY) OobRectWorstY = dy;
    if (!OobRectFirstLine)
      { OobRectFirstLine = line;
        OobRectFirstVals[0] = x1; OobRectFirstVals[1] = y1;
        OobRectFirstVals[2] = x2; OobRectFirstVals[3] = y2; }
  }

static long long OobGaveUp = 0;

/* Each give-up is one furnishing the generator wanted to place and did not.
   That is the player-visible cost, and it is countable -- unlike a screen
   diff, which changes anyway once the random stream is consumed differently. */
void OobProbeGaveUp(void)
  {
    if (OobProbeOn())
      OobGaveUp++;
  }

static long long OobPwsCalls = 0, OobPwsInverted = 0;
static int OobPwsFirst[10];
static bool OobPwsHaveFirst = false;

void OobProbePlaceWithin(int x1,int y1,int x2,int y2,int sx,int sy,
                         int rx1,int ry1,int rx2,int ry2)
  {
    if (!OobProbeOn())
      return;
    OobPwsCalls++;
    if (ry1 <= ry2 && rx1 <= rx2)
      return;
    OobPwsInverted++;
    if (!OobPwsHaveFirst)
      { OobPwsHaveFirst = true;
        OobPwsFirst[0]=x1; OobPwsFirst[1]=y1; OobPwsFirst[2]=x2;
        OobPwsFirst[3]=y2; OobPwsFirst[4]=sx; OobPwsFirst[5]=sy;
        OobPwsFirst[6]=rx1; OobPwsFirst[7]=ry1; OobPwsFirst[8]=rx2;
        OobPwsFirst[9]=ry2; }
  }

static long long OobPwpCalls = 0, OobPwpInverted = 0;
static int OobPwpFirst[10];
static bool OobPwpHaveFirst = false;

void OobProbePlaceWithinPlain(int x1,int y1,int x2,int y2,int sx,int sy,
                              int rx1,int ry1,int rx2,int ry2)
  {
    if (!OobProbeOn())
      return;
    OobPwpCalls++;
    if (ry1 <= ry2 && rx1 <= rx2)
      return;
    OobPwpInverted++;
    if (!OobPwpHaveFirst)
      { OobPwpHaveFirst = true;
        OobPwpFirst[0]=x1; OobPwpFirst[1]=y1; OobPwpFirst[2]=x2;
        OobPwpFirst[3]=y2; OobPwpFirst[4]=sx; OobPwpFirst[5]=sy;
        OobPwpFirst[6]=rx1; OobPwpFirst[7]=ry1; OobPwpFirst[8]=rx2;
        OobPwpFirst[9]=ry2; }
  }

static long long OobRmdCalls = 0, OobRmdSqueezed = 0, OobRmdNegSize = 0;
static int OobRmdFirst[6];
static bool OobRmdHaveFirst = false;

/* Called at the RM_DOUBLE inner-room site, after the shrink and after sx/sy
   are reduced, but BEFORE the cast to uint8 that PlaceWithin's signature
   forces. Two separate hazards are counted: an area that the shrink has left
   with no height, and a requested size that has gone negative and will become
   a large positive number when cast. */
void OobProbeRmDouble(int x1,int y1,int x2,int y2,int sx,int sy)
  {
    if (!OobProbeOn())
      return;
    OobRmdCalls++;
    if (y2 - y1 <= 1 || x2 - x1 <= 1)
      OobRmdSqueezed++;
    if (sx < 0 || sy < 0)
      OobRmdNegSize++;
    if (!OobRmdHaveFirst && (y2 - y1 <= 1 || sy < 0))
      { OobRmdHaveFirst = true;
        OobRmdFirst[0]=x1; OobRmdFirst[1]=y1; OobRmdFirst[2]=x2;
        OobRmdFirst[3]=y2; OobRmdFirst[4]=sx; OobRmdFirst[5]=sy; }
  }

static int OobRmoFirst[6];
static bool OobRmoHaveFirst = false;

/* The outer room, as PlaceWithinSafely built it, BEFORE the shrink by two on
   every side. This is what says whether the shrink flattened a healthy room or
   whether the room arrived too small already. */
void OobProbeRmOuter(int x1,int y1,int x2,int y2,int sx,int sy)
  {
    if (!OobProbeOn() || OobRmoHaveFirst)
      return;
    if ((y2 - y1) - 4 > 1 && (x2 - x1) - 4 > 1)
      return;                       /* shrink will leave it usable; not this one */
    OobRmoHaveFirst = true;
    OobRmoFirst[0]=x1; OobRmoFirst[1]=y1; OobRmoFirst[2]=x2;
    OobRmoFirst[3]=y2; OobRmoFirst[4]=sx; OobRmoFirst[5]=sy;
  }

static int OobGeomFirst[10];
static bool OobGeomHaveFirst = false;

/* Records the first PlaceWithinSafely call whose result is shorter or narrower
   than the size requested -- i.e. the first silent partial success. */
/* The inversion condition, recorded at the moment it occurs and BEFORE any
   repair. Written straight to the log rather than counted for the exit
   summary, because a run that segfaults never reaches the summary -- so
   counting from the summary drops exactly the runs under investigation. */
void OobProbePwFired(int x1,int y1,int x2,int y2,int sx,int sy,
                     int rx1,int ry1,int rx2,int ry2)
  {
    FILE *f;
    if (!OobProbeOn())
      return;
    f = OobProbeLog();
    if (!f)
      return;
    fprintf(f, "PW_FIRED area=(%d,%d)-(%d,%d) want=%dx%d would_be=(%d,%d)-(%d,%d)"
               " variant=%s\n",
        x1,y1,x2,y2,sx,sy,rx1,ry1,rx2,ry2,
        /* Was a compile-time choice between "widen", "collapse" and "none"
           while inc-65j was being measured. Widening shipped, so the field is
           now a constant. It is kept, and kept spelled the same, so these logs
           still line up column-for-column with the ones recorded during the
           comparison in docs/evidence/inc-5xn/. */
        "widen");
  }

void OobProbePwsGeom(int px1,int py1,int px2,int py2,int sx,int sy,
                     int rx1,int ry1,int rx2,int ry2)
  {
    int cx1, cy1, cx2, cy2;
    if (!OobProbeOn())
      return;
    /* apply the same four clamps, so we can see what will come out */
    cx1 = (rx1 > px1 + 2) ? rx1 : px1 + 2;
    cy1 = (ry1 > py1 + 2) ? ry1 : py1 + 2;
    cx2 = (rx2 < px2 - 2) ? rx2 : px2 - 2;
    cy2 = (ry2 < py2 - 2) ? ry2 : py2 - 2;
    if ((cx2 - cx1) == sx && (cy2 - cy1) == sy)
      return;                       /* got what it asked for */
    {
      FILE *f = OobProbeLog();
      if (f)
        fprintf(f, "PWS_SHORT panel=(%d,%d)-(%d,%d) %dx%d asked=%dx%d "
                   "placed=(%d,%d)-(%d,%d) %dx%d -> clamped=(%d,%d)-(%d,%d) "
                   "%dx%d  fired: x1=%s y1=%s x2=%s y2=%s\n",
            px1, py1, px2, py2, px2-px1, py2-py1, sx, sy,
            rx1, ry1, rx2, ry2, rx2-rx1, ry2-ry1,
            cx1, cy1, cx2, cy2, cx2-cx1, cy2-cy1,
            (cx1 != rx1) ? "YES" : "no", (cy1 != ry1) ? "YES" : "no",
            (cx2 != rx2) ? "YES" : "no", (cy2 != ry2) ? "YES" : "no");
    }
    if (OobGeomHaveFirst)
      return;
    OobGeomHaveFirst = true;
    OobGeomFirst[0]=px1; OobGeomFirst[1]=py1; OobGeomFirst[2]=px2;
    OobGeomFirst[3]=py2; OobGeomFirst[4]=sx;  OobGeomFirst[5]=sy;
    OobGeomFirst[6]=rx1; OobGeomFirst[7]=ry1; OobGeomFirst[8]=rx2;
    OobGeomFirst[9]=ry2;
  }

static long long OobDoorCalls=0, OobDoorRawOob=0, OobDoorSilent=0;

/* x,y are the pre-cast int16 the door loop computed. Three counts:
   every call; those whose raw coordinate is off the map; and the dangerous
   subset -- raw off the map but (uint8) truncation back on it, so MakeDoor
   builds a door at an arbitrary square and nothing complains. */
void OobProbeDoor(int x,int y,int sizeX,int sizeY)
  {
    bool rawIn, truncIn;
    FILE *f;
    if (!OobProbeOn())
      return;
    OobDoorCalls++;
    rawIn   = (x >= 0 && y >= 0 && x < sizeX && y < sizeY);
    truncIn = (((unsigned char)x) < sizeX && ((unsigned char)y) < sizeY);
    if (rawIn)
      return;
    OobDoorRawOob++;
    if (!truncIn)
      return;
    OobDoorSilent++;
    f = OobProbeLog();
    if (f)
      fprintf(f, "DOOR_SILENT raw=(%d,%d) truncated=(%u,%u) map=%dx%d"
                 "  -> door built off-plan, FDoorAt fails on the raw value\n",
          x, y, (unsigned)(unsigned char)x, (unsigned)(unsigned char)y,
          sizeX, sizeY);
  }

/* inc-b5b, round 4. OobProbeDoor above records only the ARGUMENTS the door
   loop handed to MakeDoor. That is not proof that a door exists: Map::MakeDoor
   returns early when a feature already stands on the square. These record what
   the call actually DID -- the square before it and after it -- and keep the
   truncated squares so the finished map can be printed around them. */
static long long OobDoorBuilt=0, OobDoorBlocked=0, OobDoorOutside=0, OobDoorClamped=0;
#define OOB_DOOR_MAX 64
static int OobDoorRawX[OOB_DOOR_MAX], OobDoorRawY[OOB_DOOR_MAX];
static int OobDoorTX[OOB_DOOR_MAX], OobDoorTY[OOB_DOOR_MAX];
static int OobDoorRoom[OOB_DOOR_MAX][4];
static int OobDoorNoted = 0;

void OobProbeDoorPlaced(int rawx,int rawy,int sizeX,int sizeY,
                        int tx,int ty,
                        int featBefore,int doorAfter,
                        int rx1,int ry1,int rx2,int ry2)
  {
    int inRect, clamped;
    FILE *f;
    if (!OobProbeOn())
      return;
    if (rawx >= 0 && rawy >= 0 && rawx < sizeX && rawy < sizeY)
      return;                                  /* the honest case */
    /* tx,ty is where the door really lands: the (uint8) truncation, and then
       Thing::PlaceAt's own repair to (1,1) when even that is off the map. */
    clamped = (tx == 1 && ty == 1 &&
               ((int)(unsigned char)rawx != 1 || (int)(unsigned char)rawy != 1));
    if (clamped)
      OobDoorClamped++;
    if (featBefore)
      OobDoorBlocked++;
    else if (doorAfter)
      OobDoorBuilt++;
    inRect = (tx >= rx1 && tx <= rx2 && ty >= ry1 && ty <= ry2);
    if (!inRect)
      OobDoorOutside++;
    if (!featBefore && doorAfter && OobDoorNoted < OOB_DOOR_MAX)
      { OobDoorRawX[OobDoorNoted] = rawx; OobDoorRawY[OobDoorNoted] = rawy;
        OobDoorTX[OobDoorNoted]   = tx;   OobDoorTY[OobDoorNoted]   = ty;
        OobDoorRoom[OobDoorNoted][0] = rx1; OobDoorRoom[OobDoorNoted][1] = ry1;
        OobDoorRoom[OobDoorNoted][2] = rx2; OobDoorRoom[OobDoorNoted][3] = ry2;
        OobDoorNoted++; }
    f = OobProbeLog();
    if (f)
      fprintf(f, "DOOR_PLACED raw=(%d,%d) lands_at=(%d,%d)%s feature_before=%d "
                 "door_after=%d room=(%d,%d)-(%d,%d) lands_inside_room=%d\n",
          rawx, rawy, tx, ty, clamped ? " (PlaceAt clamped to 1,1)" : "",
          featBefore ? 1 : 0, doorAfter ? 1 : 0,
          rx1, ry1, rx2, ry2, inRect ? 1 : 0);
  }

/* inc-b5b: every inner rectangle the double-room case builds, healthy or
   inverted, so the finished level can be printed around both and compared. */
#define OOB_ROOM_MAX 64
static int OobRoomRect[OOB_ROOM_MAX][4];
static int OobRoomInverted[OOB_ROOM_MAX];
static int OobRoomN = 0;

void OobProbeRoomRecord(int rx1,int ry1,int rx2,int ry2)
  {
    if (!OobProbeOn() || OobRoomN >= OOB_ROOM_MAX)
      return;
    OobRoomRect[OobRoomN][0]=rx1; OobRoomRect[OobRoomN][1]=ry1;
    OobRoomRect[OobRoomN][2]=rx2; OobRoomRect[OobRoomN][3]=ry2;
    OobRoomInverted[OobRoomN] = (rx1 > rx2 || ry1 > ry2) ? 1 : 0;
    OobRoomN++;
  }
int  OobProbeRoomCount(void) { return OobRoomN; }
void OobProbeRoomGet(int i,int *rx1,int *ry1,int *rx2,int *ry2,int *inverted)
  { *rx1=OobRoomRect[i][0]; *ry1=OobRoomRect[i][1];
    *rx2=OobRoomRect[i][2]; *ry2=OobRoomRect[i][3];
    *inverted=OobRoomInverted[i]; }
void OobProbeRoomClear(void) { OobRoomN = 0; }

int  OobProbeDoorNoteCount(void)
  { return OobDoorNoted; }
void OobProbeDoorNoteGet(int i,int *rawx,int *rawy,int *tx,int *ty)
  { *rawx = OobDoorRawX[i]; *rawy = OobDoorRawY[i];
    *tx   = OobDoorTX[i];   *ty   = OobDoorTY[i]; }
void OobProbeDoorNoteRoom(int i,int *rx1,int *ry1,int *rx2,int *ry2)
  { *rx1 = OobDoorRoom[i][0]; *ry1 = OobDoorRoom[i][1];
    *rx2 = OobDoorRoom[i][2]; *ry2 = OobDoorRoom[i][3]; }
void OobProbeDoorNoteClear(void)
  { OobDoorNoted = 0; }
void OobProbeNote(const char *line)
  { FILE *f = OobProbeLog(); if (f) { fprintf(f, "%s\n", line); fflush(f); } }

static void OobProbeDoorDump(FILE *f)
  {
    fprintf(f, "DOORS calls=%lld raw_out_of_bounds=%lld "
               "silently_placed_in_bounds=%lld built=%lld "
               "blocked_by_existing_feature=%lld outside_intended_room=%lld "
               "clamped_to_1_1_by_PlaceAt=%lld\n",
        OobDoorCalls, OobDoorRawOob, OobDoorSilent,
        OobDoorBuilt, OobDoorBlocked, OobDoorOutside, OobDoorClamped);
  }

static void OobProbeGeomDump(FILE *f)
  {
    int px1, py1, px2, py2, rx1, ry1, rx2, ry2, cx1, cy1, cx2, cy2;
    if (!OobGeomHaveFirst)
      { fprintf(f, "PWS_GEOM every call got the size it asked for\n"); return; }
    px1=OobGeomFirst[0]; py1=OobGeomFirst[1]; px2=OobGeomFirst[2];
    py2=OobGeomFirst[3]; rx1=OobGeomFirst[6]; ry1=OobGeomFirst[7];
    rx2=OobGeomFirst[8]; ry2=OobGeomFirst[9];
    cx1 = (rx1 > px1 + 2) ? rx1 : px1 + 2;
    cy1 = (ry1 > py1 + 2) ? ry1 : py1 + 2;
    cx2 = (rx2 < px2 - 2) ? rx2 : px2 - 2;
    cy2 = (ry2 < py2 - 2) ? ry2 : py2 - 2;
    fprintf(f, "PWS_GEOM panel=(%d,%d)-(%d,%d) %dx%d  asked=%dx%d  "
               "before_clamp=(%d,%d)-(%d,%d) %dx%d  after_clamp=(%d,%d)-(%d,%d) %dx%d"
               "  clamps_fired: x1=%s y1=%s x2=%s y2=%s\n",
        px1, py1, px2, py2, px2-px1, py2-py1,
        OobGeomFirst[4], OobGeomFirst[5],
        rx1, ry1, rx2, ry2, rx2-rx1, ry2-ry1,
        cx1, cy1, cx2, cy2, cx2-cx1, cy2-cy1,
        (cx1 != rx1) ? "YES" : "no", (cy1 != ry1) ? "YES" : "no",
        (cx2 != rx2) ? "YES" : "no", (cy2 != ry2) ? "YES" : "no");
  }

static void OobProbeRmoDump(FILE *f)
  {
    if (!OobRmoHaveFirst)
      { fprintf(f, "RM_OUTER none flattened\n"); return; }
    fprintf(f, "RM_OUTER first flattened: outer_room=(%d,%d)-(%d,%d) "
               "%dx%d asked_for=%dx%d -> after shrink %dx%d\n",
        OobRmoFirst[0], OobRmoFirst[1], OobRmoFirst[2], OobRmoFirst[3],
        OobRmoFirst[2]-OobRmoFirst[0], OobRmoFirst[3]-OobRmoFirst[1],
        OobRmoFirst[4], OobRmoFirst[5],
        (OobRmoFirst[2]-OobRmoFirst[0])-4, (OobRmoFirst[3]-OobRmoFirst[1])-4);
  }

static void OobProbeRmdDump(FILE *f)
  {
    fprintf(f, "RM_DOUBLE inner_room_calls=%lld area_squeezed_flat=%lld "
               "requested_size_negative=%lld", OobRmdCalls, OobRmdSqueezed,
        OobRmdNegSize);
    if (OobRmdHaveFirst)
      fprintf(f, "  first: area=(%d,%d)-(%d,%d) want=%dx%d (as uint8: %ux%u)",
          OobRmdFirst[0], OobRmdFirst[1], OobRmdFirst[2], OobRmdFirst[3],
          OobRmdFirst[4], OobRmdFirst[5],
          (unsigned)(unsigned char)OobRmdFirst[4],
          (unsigned)(unsigned char)OobRmdFirst[5]);
    fprintf(f, "\n");
  }

static void OobProbePwpDump(FILE *f)
  {
    fprintf(f, "PLACEWITHIN_PLAIN calls=%lld returned_inverted=%lld",
        OobPwpCalls, OobPwpInverted);
    if (OobPwpHaveFirst)
      fprintf(f, "  first: area=(%d,%d)-(%d,%d) want=%dx%d -> rect=(%d,%d)-(%d,%d)",
          OobPwpFirst[0], OobPwpFirst[1], OobPwpFirst[2], OobPwpFirst[3],
          OobPwpFirst[4], OobPwpFirst[5], OobPwpFirst[6], OobPwpFirst[7],
          OobPwpFirst[8], OobPwpFirst[9]);
    fprintf(f, "\n");
  }

static void OobProbePwsDump(FILE *f)
  {
    fprintf(f, "PLACEWITHIN calls=%lld returned_inverted=%lld", OobPwsCalls,
        OobPwsInverted);
    if (OobPwsHaveFirst)
      fprintf(f, "  first: panel=(%d,%d)-(%d,%d) want=%dx%d -> rect=(%d,%d)-(%d,%d)",
          OobPwsFirst[0], OobPwsFirst[1], OobPwsFirst[2], OobPwsFirst[3],
          OobPwsFirst[4], OobPwsFirst[5], OobPwsFirst[6], OobPwsFirst[7],
          OobPwsFirst[8], OobPwsFirst[9]);
    fprintf(f, "\n");
  }

static void OobProbeRectDump(FILE *f)
  {
    fprintf(f, "RECTS random_open_calls=%lld inverted=%lld gave_up=%lld "
               "worst_dx=%d worst_dy=%d first_at_line=%d "
               "first_rect=(%d,%d)-(%d,%d)\n",
        OobRectCalls, OobRectInverted, OobGaveUp, OobRectWorstX,
        OobRectWorstY, OobRectFirstLine, OobRectFirstVals[0],
        OobRectFirstVals[1], OobRectFirstVals[2], OobRectFirstVals[3]);
  }

/* Opening the log on the first GetAt call of any kind, in bounds or not, is
   deliberate. A probe that writes nothing cannot be told apart from a probe
   that never ran, and "no out-of-bounds reads happened" is one of the answers
   this measurement has to be able to give. The file's existence means the
   probe was live; the START line records which build wrote it. */
void OobProbeTouch(void)
  {
    static bool done = false;
    FILE *f;
    if (done || !OobProbeOn())
      return;
    done = true;
    f = OobProbeLog();
    if (f)
      fprintf(f, "START build=%s\n",
#ifdef INCURSION_OOB_UNGUARDED
          "unguarded (upstream behaviour)"
#else
          "guarded (issue #40 fix)"
#endif
          );
    atexit(OobProbeAtExit);
  }

/* The counterfactual. At() answers an out-of-bounds query with Grid[0], the
   (0,0) square, so the unguarded path walks that square's Contents chain
   looking for type t. Read (0,0) directly rather than through At(x,y): the
   answer is identical and it does not fire the ASSERT that this probe exists
   to look past. */
void OobProbeGetAt(Map *m, int16 x, int16 y, int16 t, bool first)
  {
    FILE *f;
    Thing *would;

    if (!OobProbeOn())
      return;

    OobCalls++;

    would = oThing(m->At(0,0).Contents);
    while (would && !would->isType(t))
      would = oThing(would->Next);

    if (would)
      { OobWouldReturn++;
        f = OobProbeLog();
        if (f)
          fprintf(f, "turn %-6u WOULD-RETURN asked=(%d,%d) map=%dx%d type=%d "
                     "first=%d -> %s h=%d at=(%d,%d)\n",
              (unsigned)(theGame ? theGame->Turn : 0), (int)x, (int)y,
              (int)m->SizeX(), (int)m->SizeY(), (int)t, (int)first,
              (const char*)would->Name(0), (int)would->myHandle,
              (int)would->GetX(), (int)would->GetY()); }

    if ((OobCalls % 1000) == 0)
      OobProbeTotals("running");
  }

/* Called from Monster::ChooseAction() when the eight-neighbour ambush scan
   accepts a creature that came back from an out-of-bounds direction. In the
   guarded build this can never fire, which is the point. */
void OobProbeAmbushed(Creature *hider, Creature *victim, int16 askx, int16 asky,
                      const char *act)
  {
    FILE *f;
    int dx, dy, cheb;
    if (!OobProbeOn())
      return;
    dx = abs((int)hider->GetX() - (int)victim->GetX());
    dy = abs((int)hider->GetY() - (int)victim->GetY());
    cheb = (dx > dy) ? dx : dy;
    OobAmbush++;
    f = OobProbeLog();
    if (!f)
      return;
    fprintf(f, "turn %-6u AMBUSH       %s h=%d at=(%d,%d) scanned=(%d,%d) "
               "-> %s h=%d at=(%d,%d) chebyshev=%d act=%s\n",
        (unsigned)(theGame ? theGame->Turn : 0),
        (const char*)hider->Name(0), (int)hider->myHandle,
        (int)hider->GetX(), (int)hider->GetY(), (int)askx, (int)asky,
        (const char*)victim->Name(0), (int)victim->myHandle,
        (int)victim->GetX(), (int)victim->GetY(),
        cheb, act);
  }
#endif /* INCURSION_OOB_PROBE */

Thing* Map::GetAt(int16 x, int16 y, int16 t, bool first)
  {
    static bool doneflag = false;
    static Thing* curr = NULL;
    
    static int32 count = 0;

    //count++;
    //if (count > 1000000L)
    //  __asm int 3;

    /* upstream: base-code defect, the fix is ours. It is upstream's because
       nothing here is platform, compiler or width dependent -- At() returns
       the (0,0) square for an out-of-bounds coordinate on Win32 with the
       original typedefs exactly as it does on POSIX. The codebase argues
       against itself: Map::besideWall() carries a comment about the same trap
       that a neighbour scan could walk into.

       Tier Observed, but far smaller than first reported. Measured 2026-08-18
       (inc-5xn, docs/evidence/inc-5xn/README.md): on the one seed that
       reproduces the fault this guard accounts for 8 out-of-bounds reads out
       of 47,962, and it changes no answer -- the (0,0) square was empty every
       time, and the screen dumps are byte-identical with and without it. The
       other 47,954 reads come from level generation and are inc-6f1. The
       earlier claim here, that the error log went from 444 entries in 13
       seconds to zero across 877 turns, is NOT supported: a soak run after
       this guard landed logged 47,955 of the same assert.

       Tracked as inc-f13. SENT to rmtew as issue #40 and pull request #41.
       rmtew asked on 2026-08-15 what the observed effect on the player is;
       that question is what produced the measurement above.

       Nothing exists outside the map. Callers scan neighbouring squares
       without checking first -- Monster::ChooseAction() does it for all eight
       neighbours of a hiding monster -- and At() answers an out-of-bounds
       query with the (0,0) square instead of failing, so the wrong answer
       looks like a real one. Refuse here: every FCreatureAt/NCreatureAt/
       FTrapAt/FirstAt accessor funnels through this function, so one guard
       covers them all. */
#ifdef INCURSION_OOB_PROBE
    OobProbeTouch();
#endif
    if (!InBounds(x,y)) {
#ifdef INCURSION_OOB_PROBE
        OobProbeGetAt(this,x,y,t,first);
#endif
#ifndef INCURSION_OOB_UNGUARDED
        if (first) {
            doneflag = true;
            curr = NULL;
        }
        return NULL;
#endif
    }

    if (first == true)
      {
        doneflag = false;
        curr = oThing(At(x,y).Contents);
        if (curr)
          while (curr && !curr->isType(t))
            curr = oThing(curr->Next);
        if (curr == NULL) 
          goto SizeFieldCheck;
        return curr;
      }
      
    if (doneflag || curr == NULL)
      return NULL;
      
    
      
    do
      {
        curr = oThing(curr->Next);
      }
    while (curr && !curr->isType(t));
    
    if (curr)
      return curr;

    /* Assumption: only one size field possible in any one
       square of the map. */
    SizeFieldCheck:
    /* Avoid returning a creature with a size field twice when
        asking what is in its center square. */
    if (oThing(At(x,y).Contents) &&
        oThing(At(x,y).Contents)->isCreature() &&
        oCreature(At(x,y).Contents)->GetAttr(A_SIZ) > SZ_LARGE)
      return NULL;
    if ((t == T_THING || t == T_CREATURE || t == T_CHARACTER ||
         t == T_MONSTER || t == T_PLAYER) && FieldAt(x,y,FI_SIZE)) 
      {
        for(int16 i=0;Fields[i];i++)
          if (Fields[i]->inArea(x,y))
            if (Fields[i]->FType & FI_SIZE)
              {
                doneflag = true;
                curr = NULL;
                return oCreature(Fields[i]->Creator);
              }
        Error("Corrupted data for FI_SIZE field!");
      }
      
    return NULL;
  }


bool Map::OpenAt(int16 x, int16 y)
  {
    return !(SolidAt(x,y) || FCreatureAt(x,y));
  }

bool Map::FallAt(int16 x, int16 y)
  {
    return TTER(TerrainAt(x,y))->HasFlag(TF_FALL);
  }

bool Map::besideWall(int16 x,int16 y)
  {
    /* ww: someone at (0,122) will do an out-of-bounds At() check
     * unless we put this here -- yes, this happened to me! */
    return (x == 0 || y == 0 || x >= sizeX-1 || y >= sizeY-1) ||
           At(x,y-1).isWall || At(x,y+1).isWall ||
           At(x-1,y).isWall || At(x+1,y).isWall ||
           At(x-1,y-1).isWall || At(x+1,y+1).isWall ||
           At(x+1,y-1).isWall || At(x-1,y+1).isWall;
  }

bool Creature::isBeside(Thing *t, int extra_dist)
  { 
    int16 k;
    k = extra_dist + 1 + FaceRadius[Attr[A_SIZ]];
    if (t->isItem() && ((Item*)t)->Owner() == this)
      return true;
    if (m != t->m)
      return false;
    if (t->isCreature())
      k += FaceRadius[((Creature*)t)->Attr[A_SIZ]];
    // if (k <= 1) 
      return (abs(x - t->GetX()) <= k) &&
                      (abs(y - t->GetY()) <= k); 
    // else return dist(x,y,t->x,t->y) <= k;
  
  }


void Map::RegisterPlayer(hObj h)
	{
  	if(PlayerCount==4)
    	Fatal("Too Many Players!");
    for(int8 i=0;i!=4;i++)
      if (pl[i] == h)
        return;
  	pl[PlayerCount]=h;
    PlayerCount++;
  }

/* inc-qhux heal for stored saves. Level generation restored a cell's .Solid
   from terrain when it removed a door but never its .Opaque (the marked fix and
   its provenance are at src/MakeLev.cpp), leaving 3 wall cells per level solid
   but see-through. Re-derive .Opaque from terrain for every BARE cell -- no
   feature, no field -- which is exactly a plain wall or floor. A door, another
   feature, or a field keeps its own opacity, so closed doors, statues and fog
   are untouched; and because the value is the terrain's own TF_OPAQUE,
   by-design transparent walls (ice, fences, portcullises) stay transparent.
   Idempotent: a level already correct, including one freshly generated by the
   fixed pass, is unchanged. */
void Map::FixWallOpacity()
  {
    for (int16 x = 0; x < sizeX; x++)
      for (int16 y = 0; y < sizeY; y++)
        if (!FFeatureAt(x, y) && !At(x, y).hasField)
          At(x, y).Opaque = TTER(TerrainAt(x, y))->HasFlag(TF_OPAQUE);
  }

void Map::VUpdate(int16 x, int16 y)
 {
   
   for(int i=0;i!=PlayerCount;i++)
     if (abs(x-oPlayer(pl[i])->x)<60 && abs(y-oPlayer(pl[i])->y)<40) 
       oPlayer(pl[i])->UpdateMap = true;
   Update(x,y);
 }

void Map::Load(rID mID)
  {
    Rect r;
    dID = mID;
    sizeX = TREG(mID)->sx;
    sizeY = TREG(mID)->sy;
    Grid  = new LocationInfo[sizeX * sizeY];
    r.Set(0,0,sizeX-1,sizeY-1);
    WriteMap(r,mID);

  }


/////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////
void Overlay::Activate()
	{
		int16 i;
		for(i=0;i!=MAX_OVERLAY_GLYPHS;i++)
			GlyphX[i]=GlyphY[i]=-1;
		GlyphCount=0;
		Active=true;
	}
void Overlay::DeActivate()
	{
		GlyphCount=0;
  	Active=false;
    for(int i=0;i!=MAX_OVERLAY_GLYPHS;i++)
    	if(GlyphX[i]!=-1)
      	oMap(m)->Update(GlyphX[i],GlyphY[i]);
  }

void Overlay::AddGlyph(int16 x,int16 y, Glyph g)
	{
    if (GlyphCount >= MAX_OVERLAY_GLYPHS)
      return;
		GlyphX[GlyphCount]=x;
		GlyphY[GlyphCount]=y;
		GlyphImage[GlyphCount]=g;
		GlyphCount++;
	}
void Overlay::RemoveGlyph(int16 x,int16 y)
	{
		for(int16 i=0;i!=MAX_OVERLAY_GLYPHS;i++)
			if(GlyphX[i]==x && GlyphY[i]==y)
				GlyphX[i]=GlyphY[i]=-1;

	}

bool Overlay::IsGlyphAt(int16 x, int16 y)
  {
		for(int16 i=0;i!=MAX_OVERLAY_GLYPHS;i++)
			if(GlyphX[i]==x && GlyphY[i]==y)
        return true;
    return false;
  }

void Overlay::RemoveGlyph(int16 n)
	{
		GlyphX[n]=GlyphY[n]=0;
	}
void Overlay::ShowGlyphs()
	{
		for(int16 i=0;i!=GlyphCount;i++)
      if (GlyphX[i] != -1)
			  oMap(m)->Update(GlyphX[i],GlyphY[i]);
    T1->Update();
	}

/////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////
void Thing::DoTurn()
	{
	}
	
void Thing::Move(int16 newx,int16 newy, bool is_walk)
	{
		int16 ox,oy,i; Thing *th; Creature *mount;
		ox=x; oy=y;
    Map *M = m;
    INC6D5_PROBE_CALL("Move:entry", this, "");

    if (!m)
      return;
      
    if (HasStati(ENGULFED))
      return;

    if (HasStati(MOUNTED))
      mount = (Creature*)GetStatiObj(MOUNTED);
    else
      mount = NULL;

    if (x == -1 || HasStati(MOUNT))
      goto AddToList;


    if (M->At(x,y).hasField || M->At(newx,newy).hasField || !is_walk)
      {
        /* upstream: a creature carried inside another must get the same field
           events a rider gets. Engulfed creatures sit in m->Things at their
           engulfer's square, so Map::NewField, RemoveField and MoveField all
           reach them through MapIterate; only this hand-written notification
           misses them. Plain control flow, wrong identically on Win32 with the
           original typedefs. Traced, inc-rr0t, not sent. */
        hObj Carried[128]; int16 cc = 0, j;
        if (HasStati(ENGULFER))
          StatiIterNature(this,ENGULFER)
            if (cc != 128)
              Carried[cc++] = S->h;
          StatiIterEnd(this)

        for(i=0;M->Fields[i];i++)
          if (M->Fields[i]->Creator == myHandle || (mount && 
                M->Fields[i]->Creator == mount->myHandle))
            if (M->Fields[i]->FType & FI_MOBILE)
              {
                if (M->MoveField(M->Fields[i],newx,newy,is_walk) == ABORT)
                  return;
              }
        for(i=0;M->Fields[i];i++)
          {
            if (M->Fields[i]->FType && FI_MOBILE)
              if (M->Fields[i]->Creator == myHandle)
                continue;
            if (M->Fields[i] && M->Fields[i]->inArea(x,y) && !M->Fields[i]->inArea(newx,newy))
              {
                ThrowField(EV_FIELDOFF,M->Fields[i],this);
                if (mount && M->Fields[i])
                  ThrowField(EV_FIELDOFF,M->Fields[i],mount);
                for(j=0;j!=cc;j++)
                  if (M->Fields[i] && theRegistry->Exists(Carried[j]))
                    ThrowField(EV_FIELDOFF,M->Fields[i],oThing(Carried[j]));
              }
            if (M->Fields[i] && (!M->Fields[i]->inArea(x,y)) && M->Fields[i]->inArea(newx,newy))
              {
                ThrowField(EV_FIELDON,M->Fields[i],this);
                if (mount && M->Fields[i])
                  ThrowField(EV_FIELDON,M->Fields[i],mount);
                for(j=0;j!=cc;j++)
                  if (M->Fields[i] && theRegistry->Exists(Carried[j]))
                    ThrowField(EV_FIELDON,M->Fields[i],oThing(Carried[j]));
              }
          }
      }

    /* If moving a field caused our death, don't put us back on the map! */
    if (isDead() || !m) {
      INC6D5_PROBE_CALL("Move:deadOrGoneSkip", this, "");
      goto DoneContentsAdd;
    }

		x=newx; y=newy;
    /* Remove this Thing from the old Contents list */
    if (M->At(ox,oy).Contents == myHandle)
      M->At(ox,oy).Contents = Next;
    else
      {
        th = oThing(M->At(ox,oy).Contents);
        while(th && th->Next != myHandle) {
          if (!th->Next) {
            INC6D5_PROBE_CALL("Move:contentsUnlinkFailed(Fatal-next)", this, "");
            Fatal("Contents list wierdless in Thing::Move!");
          }
          th = oThing(th->Next);
          }
    if (th)
        th->Next = Next;
      }
    INC6D5_PROBE_CALL("Move:unlinkedOldList", this, "");
    /* ... and add it to the new one. */
    AddToList:
		x=newx; y=newy;
    if (M->At(x,y).Contents)
      if (oThing(M->At(x,y).Contents)->isCreature())
        {
          Next = oThing(M->At(x,y).Contents)->Next;
          oThing(M->At(x,y).Contents)->Next = myHandle;
          goto DoneContentsAdd;
        }
    Next = M->At(x,y).Contents;
    M->At(x,y).Contents = myHandle;
    DoneContentsAdd:
    INC6D5_PROBE_CALL("Move:doneContentsAdd", this, "");
    INC6D5_PROBE_SETTLED(this);

    if (mount) {
      mount->m = M;
      mount->x = x;
      mount->y = y;
      }

    if (theGame->InPlay()) {
      M->Update(ox,oy);
		  M->Update(x,y);
      }

  /* When we move, any engulfed creatures move with us. */
  if (HasStati(ENGULFER))
    {
      StatiIterNature(this,ENGULFER)
        Thing *t = oThing(S->h);
        t->m = M;
        t->x = x;
        t->y = y;
      StatiIterEnd(this)
    }

  if (Type==T_PLAYER && theGame->InPlay()) 
    thisp->UpdateMap = true;

}

Thing* Thing::ProjectTo(int16 tx, int16 ty, int8 range)
  {
    int8 dirX = (tx >= x) ? 1 : -1,
         dirY = (ty >= y) ? 1 : -1;
    Feature *f;
    Fraction slope, test; int16 sx,sy,ix,iy;
    ASSERT(m)
    bool stop = false;
    if (oPlayer(m->pl[0])) {
      Player * p = oPlayer(m->pl[0]);
      if (m->LineOfSight(p->x,p->y,tx,ty,p))
        stop = true; 
    } 
    if (x == tx)
      for (;;) {
        if (m->At(x,y+dirY).Solid)
          goto HitWall;
        for (f=m->FFeatureAt(x,y+dirY);f;f=m->NFeatureAt(x,y+dirY))
          if (f->Flags & F_SOLID)
            goto HitFeature;
        /*if (m->FieldAt(x,y+dirY,FI_MISSLE)) {
          if (Throw(EV_FIELDON,this) == ABORT)
        */
        if (!m->InBounds(x,y+dirY))
          goto HitWall;
        Move(x,y+dirY);
        if (stop) { 
          T1->StopWatch(5);
          T1->Update();
        } 
        if (m->FCreatureAt(x,y+dirY))
          goto HitCreature;

      }

    sx = x*2; sy = y * 2; tx *= 2; ty *= 2;
    slope.Set(abs(ty - y), abs((tx - dirX) - x));

    for(ix=sx,iy=sy;;) {

      test.Set(abs((iy+dirY)-sy),abs((ix+dirX)-sx));

      if (test > slope)
        ix += 2 * dirX;
      else if (test < slope)
        iy += 2 * dirY;
      else {
        ix += 2 * dirX;
        iy += 2 * dirY;
        }

      if (m->At(ix/2,iy/2).Solid)
        goto HitWall;
      for (f=m->FFeatureAt(ix/2,iy/2);f;f=m->NFeatureAt(ix/2,iy/2))
        if (f->Flags & F_SOLID)
          goto HitFeature;

      if (!m->InBounds(ix/2,iy/2))
        goto HitWall;

      Move(ix/2,iy/2);
      if (stop) { 
        T1->StopWatch(5);
        T1->Update();
      } 
      if (m->FCreatureAt(ix/2,iy/2))
        goto HitCreature;

      }

    HitWall:

      return NULL;

    HitFeature:
      return NULL;

    HitCreature:
      Creature *cr; int16 i;
      for (cr=m->FCreatureAt(x,y),i=0;cr;cr=m->NCreatureAt(x,y))
        Candidates[i] = cr->myHandle;
      return oThing((hObj)Candidates[random(i)]);


  }

void Thing::Show() {
    m->Update(x,y);
}

EvReturn Thing::Event(EventInfo &e) {
    switch(e.Event) {
    case EV_TURN:
        return DONE;
    case EV_PLACE:
        return DONE;
    case PRE(EV_FIELDON):
    case PRE(EV_FIELDOFF):
        /* Catch this case _before_ the field effect resource is
        allowed to override it, avoiding messages like "the
        stairs seem unsettled" from spook. */
        if (e.EField)
            if (e.EField->eID) {
                /* Polymorph / selective target paranoia */
                if (e.Event == PRE(EV_FIELDOFF) && HasEffStati(-1,e.EField->eID))
                    return NOTHING;
                /* If the thing entering the field isn't affected
                by it, abort now. */
                EventInfo e2;
                e2.Clear();

                if (theRegistry->Exists(e.EField->Creator))
                    e2.EActor = oCreature(e.EField->Creator);
                else
                    return NOTHING; 
                e2.ETarget = this;
                e2.eID = e.EField->eID;
                e2.EMagic = TEFF(e.EField->eID)->Vals(0);
                /* Make sure *every segment* ignores this; c.f. MCvsE */
                for (e2.efNum=0;e2.EMagic = TEFF(e2.eID)->Vals(e2.efNum);e2.efNum++)
                    if (thisp->isTarget(e2,this))
                        return NOTHING;
                return ABORT;
            }
            return NOTHING;
    case EV_FIELDON:
        if (e.EActor==this)
            return FieldOn(e);
        break;
    case EV_FIELDOFF:
        if (e.EActor==this)
            return FieldOff(e);
        break;
    default:
        return NOTHING;
    }
    return ERROR;
}

void Thing::Remove(bool isDelete, bool keepMobileFields) {
    int16 ox = x, oy = y,i; Thing *th;
    Creature *mount;

    if (isCreature() && isDelete)
        thisc->FocusCheck(NULL);

    if (HasStati(ENGULFED)) {
        Thing *en = GetStatiObj(ENGULFED);
        en->RemoveStati(ENGULFER,-1,-1,-1,this);
        RemoveStati(ENGULFED);
        for (i=0;m->Things[i];i++)
            if (m->Things[i] == myHandle)
            {
                m->Things.Remove(i);
                goto FoundAndRemoved2;
            }
        Error("Cannot remove engulfed creature from Things!");
FoundAndRemoved2:
        m = NULL;
        x = -1;
        y = -1;
    }

    if (HasStati(ENGULFER)) {
        ASSERT(isCreature());
        /* Later, some Remove(false) calls should *not* drop our
        engulfed creatures; for example, if a dragon swallows
        an adventurer, the adventurer shouldn't pop out if the
        dragon casts /teleport/, or even /teleport level/. But
        that involves going through the code to verify that
        each individual Revove(false) call won't potentially
        end with the Player having m==NULL, so for now any
        remove drops engulfed creatures. */
        if (isDelete || 1)
            thisc->DropEngulfed();
    } 

    if (HasStati(MOUNTED))
        mount = (Creature*)GetStatiObj(MOUNTED);
    else
        mount = NULL;

    if (isType(T_DOOR) && m) {
        ((Door*)this)->DoorFlags &= ~DF_SECRET;
        ((Door*)this)->DoorFlags |= DF_OPEN;
        SetImage();
    }

    /* upstream: base-code defect, the fix is ours. Tier Observed -- a creature
       that is taken up as a mount leaves the map through this function, so its
       aura is destroyed the moment you climb on. Creature::Mount calls
       Remove(false) to unlink the animal from the map's lists
       (src/Skills.cpp:4310), and this sweep cannot tell that from a creature
       walking off the level. Measured on seed 5: a tamed night hunter holds
       its rider at Hit 4 on foot and Hit 7 once ridden, and the dismiss menu
       loses its Spook row. The engine's own intent is the other way -- both
       Thing::Move (line 1685) and Thing::PlaceAt (line 234) deliberately carry
       a field created by the mover OR ITS MOUNT, and the comment at line 307
       admits the gap: "Temporary assumption: mounts don't emit mobile fields.
       This is a very, very shaky assumption (dragons casting Spook, etc.)".
       Upstream's rather than the port's: plain control flow, no dependence on
       integer width, the typedefs or the compiler. Tracking inc-izzy. Not
       sent.
       A size field is never spared. It marks the squares a body fills, and a
       body being carried fills none of its own; keeping one would make
       Map::MoveField try to fit a Huge mount's footprint around its rider. */
    if (m)
        for (i=0;m->Fields[i];i++)
            if (m->Fields[i]->Creator == myHandle || (mount && m->Fields[i]->Creator == mount->myHandle))
                if (isDelete || m->Fields[i]->FType & FI_MOBILE) {
                    if (keepMobileFields && !isDelete &&
                        (m->Fields[i]->FType & FI_MOBILE) &&
                        !(m->Fields[i]->FType & FI_SIZE))
                        continue;
                    m->RemoveField(m->Fields[i]);
                    i--;
                }

    if (m && m->At(x,y).hasField)
        for(i=0;m->Fields[i];i++)
            if (m->Fields[i]->inArea(x,y)) {
                ThrowField(EV_FIELDOFF,m->Fields[i],this);
                if (mount)
                    ThrowField(EV_FIELDOFF,m->Fields[i],mount);
            }

    if (ox > -1 && m != NULL && !HasStati(MOUNT)) {
        for(i=0;m->Things[i];i++)
            if(m->Things[i]==myHandle) {
                m->Things.Remove(i);
                goto FoundAndRemoved;
            }
        Fatal("Could not find & remove Thing from m->Things!");

FoundAndRemoved:
        if (m->At(ox,oy).Contents == myHandle)
            m->At(ox,oy).Contents = Next;
        else {
            th = oThing(m->At(ox,oy).Contents);
            while(th && th->Next != myHandle) {
                if (!th->Next) {
                    // I'm getting this on vampire spawn vs. blue jelly every
                    // time, and I don't know why. I'm changing it to Error so
                    // it doesn't kill the game. -- Julian
                    Error("Contents list wierdless in Thing::Remove!");
                    /* Audit here, before the early return leaves this Thing in
                       neither list while it still holds m/x/y. Catching the map
                       at the moment of failure says far more than sampling it
                       later. Set INCURSION_MAP_AUDIT=1. See bead inc-6d5. */
                    if (MapAuditEnabled())
                        AuditMap(m, "Thing::Remove, contents unlink failed");
                    return;
                }
                th = oThing(th->Next);
            }
            if (th) 
                th->Next = Next;
        }
        if (theGame->InPlay())
            m->Update(ox,oy);
    }
    m = NULL; x = y = -1; Next = 0;
    if (mount) {
        mount->m = NULL;
        mount->x = -1;
        mount->y = -1;
        mount->Next = 0;
    }

    /* Catch the case where a Creature is killed but we
    keep its Creature object to attach to the corpse
    in case of resurrection, i.e., for players and
    player companions. */
    if (isDelete || (isCreature() && thisc->isDead()))
        CleanupRefedStati();

    if (isDelete) {
        Flags |= F_DELETE;
        if (Type != T_PLAYER) {
            if (theGame->DestroyCount)
                for (i=0;i!=theGame->DestroyCount;i++)
                    if (theGame->DestroyQueue[i] == this)
                    {
                        /* Error("Object being destroyed twice!"); */
                        goto SkipQueueAdd;
                    }
            theGame->DestroyQueue[theGame->DestroyCount++] = this;
SkipQueueAdd:;
        }
        if (theGame->DestroyCount > 20450)
            Error("Too many objects being destroyed at once!");
    }
}

  void Item::Remove(bool isDelete, bool keepMobileFields) {
      int16 i; Character *c; Monster *m; String str;
      if (Parent) {
          if (oThing(Parent)->isCreature()) {
              if (IFlags & IF_WORN) {
                  EventInfo e;
                  e.Clear();
                  e.eID = eID;
                  e.EActor = Owner();
                  e.EItem = this;
                  e.isRemove = true;
                  e.isItem = true;
                  e.efNum = 0;
                  if (e.eID)
                      ReThrow(EV_EFFECT,e);

                  if (isType(T_ARMOUR)) {
                      int16 q;
                      for (i=0;i!=8;i++)
                          if (q = GetQuality(i)) {
                              str = "quality::";
                              if (LookupOnly(APreQualNames,q))
                                  str += Lookup(APreQualNames,q);
                              else
                                  str += Lookup(APostQualNames,q);
                              e.eID = FIND(str);
                              if (!e.eID)
                                  continue;
                              e.isRemove = true;  
                              e.isItem = true;
                              e.efNum = 0;
                              ReThrow(EV_EFFECT,e);
                          }
                  }
                  /* If you get disarmed, lose the parry bonus! */
                  e.EActor->CalcValues();                    
              }
              if (!Parent)
                  goto NoMoreParent;
              if (oThing(Parent)->isCharacter()) {
                  c = (Character*) (Owner());
                  for (i=0;i!=SL_LAST;i++)
                      if (c->Inv[i] == myHandle) {
                          c->Inv[i] = 0;
                      }
              } else {
                  IFlags &= ~IF_WORN;
                  m = (Monster*)Owner();
                  if (m->Inv == myHandle)
                      m->Inv = Next;
                  else {
                      Item *it = oItem(m->Inv);
                      while(it && it->Next != myHandle)
                          it = oItem(it->Next);
                      if (!it)
                          Error("Can't find item to remove in monster inv list!");
                      it->Next = Next;
                  }
              }
          }
          else if (oThing(Parent)->isItem())
              ((Container*)oItem(Parent))->Unlist(this);
          Parent = Next = 0;    
      }
NoMoreParent:
      IFlags &= ~IF_WORN;
      RemoveEffStati(FIND("soulblade"));
      Thing::Remove(isDelete, keepMobileFields);
  }

void Creature::DoEngulf(Creature *engulfer)
  {
    if (!engulfer->m)
      return;
    /* Can't be engulfed by two creatures. */
    ASSERT(!HasStati(ENGULFED))
    
    /* Let's not complicate this with nested engulfs. */
    if(HasStati(ENGULFER))
      return;
      
    if (HasStati(MOUNT))
      return;
  
    /* Remove us from the map, so that we are pulled out
       of the relevant Contents lists, fields cease to
       have an effect on us, etc. */
    Remove(false);
    
    /* Now, manually reset m, x and y so that we are in
       the same map position as the engulfer -- but we
       are NOT in the contents list for that map position.
       This actually makes sense -- we WANT the map to
       show up when people read our locals, but we don't
       want to show up to calls like m->FirstAt(x,y),
       which is why we aren't in Contents. We ARE on the
       map, but nothing can interact with us. */
    x = engulfer->x;
    y = engulfer->y;
    m = engulfer->m;
    m->Things.Add(myHandle);
    if (isPlayer()) {
      m->RegisterPlayer(myHandle);
      thisp->MyTerm->SetMap(m);
			thisp->MyTerm->AdjustMap(x,y,true);
      thisp->UpdateMap = true;
      }
    
    engulfer->GainPermStati(ENGULFER,this,SS_ATTK,EG_ENGULF);
    GainPermStati(ENGULFED,engulfer,SS_ATTK,EG_ENGULF);
  
  }

void Creature::DropEngulfed(Creature *droponly)
  {
    int32 i; Thing *t;
    while (t = GetStatiObj(ENGULFER,-1,droponly)) 
      {
        t->RemoveStati(ENGULFED);
        RemoveStati(ENGULFER,-1,-1,-1,t);
        if (t->m) {
          for (i=0;i!=t->m->Things.Total();i++)
            if (t->m->Things[i] == t->myHandle)
              {
                t->m->Things.Remove(i);
                goto RemovedFromThings;
              }
          Error("Cannot find engulfed creature in t->m!");
          RemovedFromThings:
          t->m = NULL;
          }
        t->x = 0;
        t->y = 0;
       
        t->PlaceAt(m,x,y);
      }  
  }
