/* REGISTRY.CPP -- See the Incursion LICENSE file for copyright information.

     Implements the object registry, data block registry and all of
   the functionality of saving and loading related groups of objects.
   Also includes the higher-level functions for saving and loading
   games and modules.

     Registry::Registry()
     void Registry::Empty()
     Registry::~Registry()
     bool Thing::inGroup(hObj h)
     size_t typeSize(int8 Type)
     inline bool hasData(int8 Type)
     void Registry::Block(void **Block, size_t sz)
     Object * Registry::Get(hObj h)
     bool Registry::Exists(hObj h)
     void * Registry::GetData(hData h)
     hObj Registry::RegisterObject(Object *o, bool loaded)
     hData Registry::RegisterBlock(void *o, hObj Owner, size_t sz, hData h)
     void Registry::ClearDataTable()
     void Registry::RemoveObject(Object *o)
     int16 Registry::SaveGroup(Term &t, hObj hGroup,bool newFile)
     int16 Registry::LoadGroup(Term &t, hObj hGroup)
     bool Game::SaveGame(Player &p)
     bool Game::LoadGame()
     void Game::SaveModule(int16 mn)
     bool Game::LoadModules()

*/

#include "Incursion.h"
#include <sys/stat.h>
#include <time.h>

Registry MainRegistry;
Registry ResourceRegistry;

Registry *theRegistry = &MainRegistry;

extern void InitGodArrays();

/* Save maps when we leave them, load maps when we enter them. */

struct fileHeader
  {
    uint32 Sig;
    char Version[12];
    char Name[72];
    int16 numGroups;
    int16 Compression;
    int16 numDependencies;
  };

struct dependHeader
  {
    char Filename[32];
  };

/* Can a file carrying this stamp be read by the layout we compile to?
   SaveFormatID() (src/AbiCheck.cpp) is a digest of every size the save format
   depends on, so it answers that question directly -- unlike VERSION_STRING,
   which used to stand in for it and got it wrong both ways: a cosmetic release
   hid every save, while two builds sharing a version but not a layout misread
   each other's files in silence. */
static bool SaveFormatMatches(const char *stamp)
  {
    if (!stricmp(stamp, SaveFormatID()))
        return true;

    /* MIGRATION ALLOWANCE, AND IT IS MEANT TO BE DELETED. Files written before
       the digest existed carry VERSION_STRING instead. Rejecting them outright
       would have made every character created up to 2026-08-16 vanish from the
       load list -- silently, because src/Registry.cpp:907 skips a mismatch
       without saying anything. Accepting them is a bet that they came from a
       binary built from this source, which was true of every such file in
       existence at the time. It is NOT true in general: a file stamped
       "0.6.9Y19" could have come from any build of any layout, which is exactly
       the weakness the digest replaces. Nothing written from now on takes this
       path, so delete this branch once the old saves are gone. */
    if (!stricmp(stamp, VERSION_STRING))
        return true;

    return false;
  }

struct groupHeader
  {
    uint32 Signature;
    hObj   hGroup;
    int32  groupSize;
    int32  compSize;
    int32  objCount;
    int32  dataCount;
    int32  LastHandle;
  };

/* upstream: LoadGroup and SaveGroup leak their Registry mode flag on every
   throw, and the next load then frees stack garbage. Base-code defect, not a
   port artefact: no typedef, compiler or platform of this port is involved --
   the throw sites, the two flags and the constructors' loading test below are
   all original code, and the same source built for Win32 fails the same way.
   Tracking: inc-w7q. Not sent.

   Evidence: Observed here on 2026-08-19, both directions. A sandboxed copy of
   mod/Incursion.Mod with its fileHeader.Version patched to a stamp this binary
   refuses, driven by a key script that asks the start menu for a new character
   six times (each ask runs Game::LoadModules -> LoadGroup). Before: one "File
   Version Mismatch" line, then exit 134, and under lldb the abort reads
   "pointer being freed was not allocated" with frame #6 in
   Registry::LoadGroup. After: six refusals and exit 0.

   Credit: the fix, the root cause and the first evidence are Eugene
   Archibald's, in commit 7ab1ae8 of the downstream fork
   earchibald/incursion-roguelike. This tree re-derived the change by hand,
   against its own header size checks below, and re-measured it. That fork
   tracks the defect under an id of its own which means something else in this
   tracker, so it is deliberately not repeated.

   THE MECHANISM. Both functions announce what they are doing by setting a
   Registry mode flag, and both clear it only where they succeed. Every throw
   in between -- a version mismatch, a corrupt chunk, a missing group, a failed
   allocation -- leaves the Registry claiming it is still loading or still
   saving, and leaks the memory file with it.

   A stuck loadMode is not a cosmetic leak. Array<>::Array()
   (src/Base.cpp:546) and String::String() (src/Base.cpp:136) both return
   WITHOUT initialising themselves while theRegistry->Loading() is true,
   because an object rebuilt from a file must keep the array and the strings it
   was saved with, not fresh empty ones. So every Array and every String built
   anywhere in the process afterwards is uninitialised. The first casualty is
   the NEXT LoadGroup's own LoadedObjects, which is stack garbage from the
   moment it is declared; unwinding the next throw hands that garbage to
   free(): "pointer being freed was not allocated", abort.

   The flag is restored however the function leaves, which is the only way to
   state the invariant once instead of at every exit. */
class RegistryScope
  {
    bool  &flag;
    CFile **cf;
    public:
      RegistryScope(bool &f, CFile **c) : flag(f), cf(c) { }
      ~RegistryScope()
        { flag = false;
          if (*cf)
            { delete *cf; *cf = NULL; } }
  };

/* upstream: the second half of the same hole, and the half RegistryScope
   cannot close. Restoring the mode flag puts the Registry back; it does not
   put the OBJECTS back. A save that throws part way -- a full disk is the
   ordinary way -- leaves every object it had reached holding a data-block
   HANDLE where a POINTER belongs, and Game::Cleanup then dereferences it.

   The defect is upstream's: the ordering of the two Serialize loops is
   original code, and it depends on no typedef, compiler or platform of this
   port. The codebase argues against itself here, which is the evidence:
   Registry::LoadGroup (src/Registry.cpp:955) restores its objects from a
   recorded list, LoadedObjects, for exactly this reason, while the saving half
   re-walks the table and does it last.
   Evidence: Observed -- an 8 MB HFS+ volume with 76 KB free, save/ symlinked
   onto it, tools/headless.sh tools/keys/smoke.keys 1: EXC_BAD_ACCESS at 0x7f3
   in Game::Cleanup and exit 139 before, the error reported and exit 0 after.
   Tracking: inc-i0r. Not sent.

   THE MECHANISM. Registry::SaveGroup writes each object by first calling
   Serialize(*this,true) on it, which sends every data-block pointer the object
   owns through Registry::Block. With saveMode set, Block REPLACES the pointer
   with the block's handle (a small integer), because that is what has to go on
   disk. The matching Serialize(*this,false) loop that swaps the pointers back
   sits after every write in the function, so any throw from the write path
   skips it. Every object the loop had reached is then left with a handle where
   a pointer belongs, and the first walk over them dereferences it:
   Game::Cleanup, EXC_BAD_ACCESS at 0x7f3, which is the handle 2035 and not an
   address.

   WHY THE OLD LOOP CANNOT SIMPLY BE MOVED OR REPEATED. A throw part way
   through the write loop leaves the objects already visited holding handles
   and the objects not yet reached holding real pointers. Running the fixup
   loop over the whole group would hand a genuine pointer to GetData(), which
   is a fresh corruption on top of the one being repaired. So the objects are
   RECORDED as they are converted and exactly that record is unwound. The
   success path and the failure path both call Restore(), so there is one
   restore and not two that can drift apart.

   saveMode MUST be off while the restore runs -- that is what makes
   Registry::Block take its GetData branch -- so Restore() clears it itself
   rather than depending on the order two guards happen to be destroyed in. */
class SaveFixupScope
  {
    Registry &reg;
    bool     &flag;
    /* <Object*,10,10> is the instantiation src/Base.cpp:667 already provides
       for LoadGroup's LoadedObjects. Array's members are defined there and
       nowhere else, so a different Initial/Delta pair would not link. */
    OArray<Object*,10,10> Converted;
    public:
      SaveFixupScope(Registry &r, bool &f) : reg(r), flag(f) { }
      /* Call immediately after Serialize(reg,true) has run on o. */
      void Record(Object *o)
        { Converted.Add(o); }
      /* Swap the recorded objects' handles back for pointers. Idempotent: the
         record is emptied as it is consumed, so the destructor is a no-op
         after the success path has already called this. */
      void Restore()
        { Object **o;
          flag = false;
          for (int32 i = 0; (o = Converted[i]) != NULL; i++)
            (*o)->Serialize(reg,false);
          Converted.Clear(); }
      ~SaveFixupScope()
        { Restore(); }
  };

/* Diagnostic: set INCURSION_SAVE_FAIL_AT to stage a write failure inside
   Registry::SaveGroup. The value is "<n>" to fail as the n'th object is
   written, or "d<n>" to fail as the n'th data block is written; n starts at 1.
   It throws EWRIERR, the code posixTerm::FWrite (src/Wposix.cpp:1542) raises
   on a short write, and it fires once per process so that the save AFTER the
   failed one still succeeds.

   Why a hook exists at all. A full disk cannot reach the case that matters.
   Every write in SaveGroup's two loops goes into a CFile, which is a memory
   file; the disk is not touched until CFile::CommitCompressed, which runs
   after both loops have finished. So a real full disk always fails with EVERY
   object already converted, and the half-converted group -- the case
   SaveFixupScope above exists for -- has no other way in.
   tools/check_save_fail.sh drives it. inc-i0r. */
static void SaveFailProbe(bool isData, int32 index)
  {
    static const char *want = NULL;
    static bool asked = false, fired = false;
    const char *n;

    if (!asked)
      { want = getenv("INCURSION_SAVE_FAIL_AT"); asked = true; }
    if (!want || !*want || fired)
      return;
    n = want;
    if (*n == 'd' || *n == 'D')
      { if (!isData) return; n++; }
    else if (isData)
      return;
    if (index != atoi(n))
      return;
    fired = true;
    throw EWRIERR;
  }

Registry::Registry()
  {
    memset(ObjTable,0,sizeof(RegNode)*OBJ_TABLE_SIZE);
    memset(DataTable,0,sizeof(DataNode)*DATA_TABLE_SIZE);
    LastUsedHandle = 128;
    reg_log = NULL;
    #ifdef DEBUG_OBJECTS
    String path = T1->IncursionDirectory + "/reglog.txt";
    reg_log = fopen((const char *)path,"wt");
    #endif
  }

void Registry::Empty()
  {
    /* This should tail after Game::Cleanup() */
    memset(ObjTable,0,sizeof(RegNode)*OBJ_TABLE_SIZE);
    memset(DataTable,0,sizeof(DataNode)*DATA_TABLE_SIZE);
    LastUsedHandle = 128;
  }

Registry::~Registry()
  {
    #ifdef DEBUG_OBJECTS
    fclose(reg_log);
    #endif
  }

bool Thing::inGroup(hObj h)
  { return (h == 0) || (h == m->myHandle); }      

size_t typeSize(int8 Type)
  {

    switch(Type)
      {
        /* Core game objects */
        case T_GAME:     return sizeof(Game);
        case T_TERM:     return sizeof(Term);
        case T_MAP:      return sizeof(Map);
        case T_REGISTRY: return sizeof(Registry);
        case T_MONSTER:  return sizeof(Monster);
        case T_PLAYER:   return sizeof(Player);
        //case T_NPC:      return sizeof(NPC);
        case T_MODULE:    return sizeof(Module);
        /* Features */
        case T_PORTAL:   return sizeof(Portal);
        case T_DOOR:     return sizeof(Door);
        case T_TRAP:     return sizeof(Trap);
        case T_FEATURE:  return sizeof(Feature);
        //case T_ALTAR:    return sizeof(Altar);

        /* Containers */
        case T_CHEST:    
        case T_CONTAIN:  return sizeof(Container);

        /* Items */
        case T_FOOD:     return sizeof(Food);

        case T_STATUE:   case T_FIGURE:
        case T_CORPSE:   return sizeof(Corpse);
        
        case T_MISSILE:  case T_BOW:
        case T_WEAPON:   case T_STAFF:
                         return sizeof(Weapon);
        case T_ARMOUR:    case T_SHIELD:
        case T_GAUNTLETS:
        case T_BOOTS:    
                         return sizeof(Armour);

        case T_ANNOT:    return sizeof(Annotation);
        //case T_CONSTRUCT:return sizeof(Construct);
        //case T_ILLUSION: return sizeof(Illusion);
        default:
          if (Type >= T_FIRSTITEM && Type <= T_LASTITEM)
            return sizeof(Item);
      }
    Error("Strange Type ID in typeSize!");
    return 400;
  }
              


inline bool hasData(int16 Type) {
    switch(Type) {
    case T_MODULE:   /* Resource arrays; text/data/code segments */
    case T_PLAYER:  /* Name, Notes, History, other Strings */
    case T_MAP:     /* Map Grid */
        return true;
    default:
        return false;
    }
}

void Registry::Block(void **Block, size_t sz)
  {
    ASSERT(theRegistry->Get(hCurrent));

    /* The handle is parked in the object's own pointer field while the object
       is written out, then swapped back for the real pointer afterwards.

       These were *((long*)Block) on both sides. That assumed sizeof(long) ==
       sizeof(void*), which holds on LP64 and on Win32 but not on Win64. Going
       through intptr_t drops the assumption without changing a single byte on
       disk: the handle is a small positive int, so it sits in the low half of
       the slot either way. src/AbiCheck.cpp asserts the slot is wide enough. */
    if (saveMode)
      *Block = (void*)(intptr_t)RegisterBlock(*Block,hCurrent,sz);
     else
      *Block = GetData((hData)(intptr_t)*Block);
  }


/* The lookup, with no opinion about whether a missing object is a problem.
   Every branch below is the body Get() used to have; the Error() call moved
   out to Get(), which is now this plus the complaint. Splitting them lets a
   caller that legitimately holds a stale handle avoid the log line without
   paying for a second chain walk. See the header comment on this function in
   inc/Base.h and Target::GetThingOrNULL in src/Target.cpp. inc-upw.39. */
Object * Registry::GetQuiet(hObj h)
  {
    RegNode *r ;
    ASSERT(h <= LastUsedHandle);
    if (h <= 0) // ww: ouch, use to be !h || h<-1 !
      return NULL;
    else if (h < 128) // ww: && h > -1) -> implied by above "if"
      return theGame->VM.GetSystemObject(h);
    r = &(ObjTable[h & OBJ_TABLE_MASK]);
    do {
      if (r->pObj && r->pObj->myHandle == h)
          return r->pObj;
      else
          r = r->Next;
    } while (r);
    //LoadObject(h);
    return NULL;
  }

/* INCURSION_QUIET_PROBE -- the runnable check behind the Get()/GetQuiet()
   split. tools/check_quiet_lookup.sh drives it; read that script for what the
   pass condition is.

   The 40-seed gate already catches the half of this that would change the
   game: if GetQuiet() ever stops resolving a handle the way Get() does,
   screens diverge. Nothing catches the other half. Get() is still what
   oThing(), oCreature() and every ordinary caller use, and if its complaint
   were lost in some later edit the loss would be silent -- diagnostics simply
   stop arriving, and a quiet log reads as a healthy one.

   So this probe asserts both halves against one live handle and one dead one,
   and reports through Error() because errors.log is the channel under test.
   Off unless the variable is set, like the other probes in this codebase. */
void Registry::QuietProbe()
  {
    hObj live = 0, dead = 0, h;
    Object *a, *b;

    if (!getenv("INCURSION_QUIET_PROBE"))
      return;

    for (h = 128; h <= LastUsedHandle; h++)
      { if (!live && Exists(h)) live = h;
        if (!dead && !Exists(h)) dead = h;
        if (live && dead) break;
      }

    /* A registry with no gap in it has nothing dead to look up. Say so rather
       than inventing a handle above LastUsedHandle, which would trip Get()'s
       own ASSERT and muddle the very log line this probe is reading. */
    if (!live || !dead)
      { Error("QUIET_PROBE: INCONCLUSIVE -- live=%d dead=%d of %d handles",
          (int)live,(int)dead,(int)LastUsedHandle);
        return;
      }

    a = Get(live); b = GetQuiet(live);
    Error("QUIET_PROBE: live=%d resolves=%d agree=%d",
      (int)live, a ? 1 : 0, (a == b) ? 1 : 0);

    /* Order matters to the script: GetQuiet() must add nothing between this
       line and the next, and Get() must add exactly one line after it. */
    b = GetQuiet(dead);
    Error("QUIET_PROBE: GetQuiet(%d) resolves=%d, and said nothing above",
      (int)dead, b ? 1 : 0);
    Error("QUIET_PROBE: calling Get(%d) now; one invalid-handle line must follow",
      (int)dead);
    a = Get(dead);
    Error("QUIET_PROBE: Get(%d) resolves=%d, done", (int)dead, a ? 1 : 0);
  }

Object * Registry::Get(hObj h)
  {
    /* If you arrived here from an "invalid object handle" line in
       logs/errors.log, read Target::GetThingOrNULL in src/Target.cpp first.
       Every such line in the 40-seed gate before 2026-08-20 came from there,
       and none of them was a defect -- see inc-upw.39. This function is not
       the right probe for "is this handle still alive". GetQuiet() is, and it
       answers in silence. Get() assumes its caller believes the handle is
       live, and says so when it is not.

       The condition below reproduces exactly when the old single-function
       Get() complained: a handle at or above 128 that reached the end of its
       chain. A handle of 0 or less, and a system-object handle under 128 that
       resolves to nothing, both returned NULL without a word before and still
       do. */
    Object *o = GetQuiet(h);
    if (!o && h >= 128)
      Error("Registry::Get -- invalid object handle (%d)!",h);
    return o;
  }

bool Registry::Exists(hObj h)
  {
    RegNode *r = &(ObjTable[h & OBJ_TABLE_MASK]);
    if (h > LastUsedHandle)
      return false;
    if (!h)
      return false;
    if (h < -1)
      return false;
    if (h < 128)
      return (theGame->VM.GetSystemObject(h) != 0);
    
    while(r) {
      if (r->pObj)
        if (r->pObj->myHandle == h)
          return true;
      r = r->Next;
      }
    return false;
  }


void * Registry::GetData(hData h)
  {
    DataNode *d = &(DataTable[h & DATA_TABLE_MASK]);
    ASSERT(h <= LastUsedHandle);
    if (!h)
      return NULL;
    while(d) {
      if (d->myHandle == h)
        return d->pData;
      d = d->Next;
      }
    //LoadObject(d);
    Fatal("Registry::GetData -- invalid object handle (%d)!",h);
    return NULL; 
  }


hObj Registry::RegisterObject(Object *o, bool loaded)
  {
    
    hObj h; RegNode *r;
    if (loaded) {
      h = o->myHandle;
      LastUsedHandle = max(LastUsedHandle,h+1);
      }
    else
      h = LastUsedHandle++;
    if (o->Type == T_MODULE)
      hModule = h;
    hData hm = h & OBJ_TABLE_MASK;
    r = &(ObjTable[hm]);
    if (!r->pObj) 
      ObjTable[hm].pObj = o;
    else {
      while(r->Next)
        r = r->Next;
      r->Next = new RegNode;
      r = r->Next;
      r->pObj = o;
      r->Next = NULL;
      }
    #ifdef DEBUG_OBJECTS
      fprintf(reg_log,"Object #%d -- %s (%d)\n",h,(const char*)o->Name(0),o->myHandle);
    #endif
    if (h > LastUsedHandle)
      Error("Incorrect handle assigned!");

    return h;
  }

hData Registry::RegisterBlock(void *o, hObj Owner, size_t sz, hData h)
  {
    if (!o)
      return 0;
    if (!h)
      h = LastUsedHandle++;
    ASSERT(theRegistry->Get(Owner));
    hData hm = h & DATA_TABLE_MASK; 
    DataNode *r = &(DataTable[hm]);
    if (!r->pData)
      {
        DataTable[hm].pData    = o;
        DataTable[hm].Size     = sz;
        DataTable[hm].hOwner   = Owner;
        DataTable[hm].myHandle = h;
      }
    else {
      /* We need to fix this to allow registering the same block
         twice. */
      while(r->Next)
        r = r->Next;
      r->Next = new DataNode;
      r = r->Next;
      r->pData    = o;
      r->Size     = sz;
      r->hOwner   = Owner;
      r->myHandle = h;
      r->Next = NULL;
      }
    return h;
  }

void Registry::ClearDataTable()
  {
    int32 i; DataNode *d, *d2;
    for (i=0;i!=DATA_TABLE_SIZE;i++)
      {
        d = DataTable[i].Next;
        while (d) {
          d2 = d->Next;
          delete d;
          d = d2;
          };
      }
    memset(DataTable,0,sizeof(DataNode)*DATA_TABLE_SIZE);
  } 



void Registry::RemoveObject(Object *o)
  {
    hObj h = o->myHandle; int32 i;
    RegNode *r, *last;
    
    #if 0
    if (TheMainMap)
      for (i=0;TheMainMap->Things[i];i++) {
        if (TheMainMap->Things[i] == o->myHandle)
          Error("Object being deleted before being remove from map!");
        if (oThing(TheMainMap->Things[i])->HasStati(TARGET,TA_POTENTIAL,(Thing*)o))
          Error(Format("Thing %s (%d) has object-in-deletion %s as potential target!",
            (const char*)oThing(TheMainMap->Things[i])->Name(0),TheMainMap->Things[i],
            (const char*)o->Name(0)));
        }
    #endif

    h = o->myHandle;
    r = &(ObjTable[h & OBJ_TABLE_MASK]);
    last = NULL;

    while(r) {
      if (r->pObj && r->pObj->myHandle == h)
        {
          if (!last && !r->Next) 
            r->pObj = NULL;
          else if (!last) {
            last = r->Next;
            r->pObj = r->Next->pObj;
            r->Next = r->Next->Next;
            delete last; }
          else {
            last->Next = r->Next;
            delete r;
            }
          return;
        }
      last = r;
      r = r->Next;
      }

    if (hasData(o->Type))
      {
        DataNode *d;
        for(i=0;i!=DATA_TABLE_SIZE;i++)
          {
            RestartDataRemove:
            d = &(DataTable[i]);
            while(r) {
              if (r->pObj->myHandle == h)
                {
                  if (!last && !r->Next) 
                    r->pObj = NULL;
                  else if (!last) {
                    last = r->Next;
                    r->pObj = r->Next->pObj;
                    r->Next = r->Next->Next;
                    delete last; }
                  else {
                    last->Next = r->Next;
                    delete r;
                    }
                  goto RestartDataRemove;
                }
              last = r;
              r = r->Next;
              }
          }
      }

    //LoadObject(h);
    Error("Registry::UnlinkObject -- invalid object handle!");
  }

int16 Registry::SaveGroup(Term &t, hObj hGroup, bool use_lz, bool newFile) {
    int32 i; uint32 sig;
    groupHeader gh; fileHeader fh;
    RegNode *r; DataNode *d;
    uint32 ghPos;
    /* Declared before the CFile and before RegistryScope, so that it is
       destroyed after them: the objects go back however this function leaves.
       See SaveFixupScope. inc-i0r. */
    SaveFixupScope fixup(*this, saveMode);

    ClearDataTable();

    t.Seek(0,SEEK_SET);   

    if (!newFile) {
        t.FRead(&fh,sizeof(fh));
        if (fh.Sig != SIGNATURE)
            throw ENOTARC;
        if (!SaveFormatMatches(fh.Version))
            throw EBADVER;

        /* Run through a list of group headers. When/if we find the header
        for the block we're about to save, delete the old saved version
        so that it's not saved twice. */
        for(i=0;i!=fh.numGroups;i++) {
            fh.numGroups++;
            t.Seek(0,SEEK_SET);
            t.FWrite(&fh,sizeof(fh));

            t.FRead(&gh,sizeof(gh));
            if (gh.Signature != SIGNATURE)
                throw ECORRUPT;
            if (gh.hGroup == hGroup) {
                // ww: was: t.Seek(-sizeof(gh),SEEK_CUR);
                // unary minus applied to unsigned type still results in 
                // unsigned type! 
                t.Seek(0 - (signed)sizeof(gh),SEEK_CUR);
                /* Remove the old save-image of the group */
                t.Cut(sizeof(gh) + gh.groupSize);
                goto DoneDeletion;
            } else
                t.Seek(gh.groupSize,SEEK_CUR);
        }

DoneDeletion:
        ;
    }
    /* Move us right to the very end of the file, where we're going
    to append the group we're saving right now. */
    t.Seek(0,SEEK_END);

    /* We can't write the real group header yet, because we don't know
    how many objects we are saving. So we'll write an undefined group
    header to fill the space, then go back and write the real one
    later. */ 
    ghPos = t.Tell();

    t.FWrite(&gh,sizeof(gh));

    /* Initialize the Memory File */
    CFile *cf = new CFile(&t);
    /* upstream: the same guard LoadGroup uses, for the same reason. A write
       that fails -- a full disk is the ordinary way -- must not leave the
       Registry stuck in saving mode, where Registry::Block takes the wrong
       branch for every object serialised afterwards. Evidence: Observed for
       the loading half (see RegistryScope above), Traced for this half -- no
       write failure was staged here. Ported from Eugene Archibald's commit
       7ab1ae8 in earchibald/incursion-roguelike. Tracking: inc-w7q. Not
       sent. */
    RegistryScope guard(saveMode, &cf);

    /* Write the objects in sequential order, each with a single byte in
    front of it to tell its type. */
    gh.objCount = 0;
    saveMode = true;
    for(i=0;i!=OBJ_TABLE_SIZE;i++) {
        if (ObjTable[i].pObj) {
            r = &(ObjTable[i]);
            while (r) {
                if (!r->pObj->inGroup(hGroup)) {
                    r = r->Next;
                    continue;
                }

                hCurrent = r->pObj->myHandle;
                r->pObj->Serialize(*this,true);
                /* Recorded the instant it is converted, and never before: the
                   restore must cover exactly the converted objects. inc-i0r. */
                fixup.Record(r->pObj);

                gh.objCount++;
                SaveFailProbe(false, gh.objCount);
                /* Write the object type */
                cf->FWrite(&(r->pObj->Type),1);
                /* Write the object itself */
                cf->FWrite(r->pObj,typeSize((int8)r->pObj->Type));

                r = r->Next;
            }
        }
    }

    /* We write a special signature DWORD inbetween the objects and
    the data in order to assure that we're actually reading a
    valid Incursion data file accurately. This is mostly paranoia,
    but it will likely help versus otherwise-untracable bugs. */
    cf->FWrite(&(sig = SIGNATURE_TWO),4);

    /* Now write the data, in a manner similar to how the objects were
    written, but substituting size value for type index. */
    gh.dataCount = 0;
    for(i=0;i!=DATA_TABLE_SIZE;i++) {
        if (DataTable[i].pData) {
            d = &(DataTable[i]);
            while (d) {
                if (!Exists(d->hOwner)) {
                    d = d->Next;
                    continue;
                }
                if (!Get(d->hOwner)->inGroup(hGroup)) {
                    d = d->Next;
                    continue;
                }
                gh.dataCount++;
                SaveFailProbe(true, gh.dataCount);
                ASSERT(d->hOwner > 127);
                ASSERT(d->myHandle > 127);
                /* Write the handle of the data */
                cf->FWrite(&(d->myHandle),4);
                /* Write the handle of the data's owner */
                cf->FWrite(&(d->hOwner),4);
                /* Write the size in bytes of the data */
                cf->FWrite(&(d->Size),4);
                /* And now write the data proper */
                cf->FWrite(d->pData,d->Size); // ww: segfault here, this=0 (?)

                d = d->Next;
            }
        }
    }

    int32 csz = cf->CommitCompressed(t.Tell(), use_lz);

    /* Now that we have all the needed information, jump back in the file
    and write out the group header. */
    gh.groupSize  = cf->FSize();
    gh.compSize   = csz;
    gh.Signature  = SIGNATURE;
    gh.hGroup     = hGroup;
    gh.LastHandle = LastUsedHandle;
    t.Seek(ghPos,SEEK_SET);
    t.FWrite(&gh,sizeof(gh));

    delete cf;
    cf = NULL;

    /* Fix all the pointers in memory to data blocks, so that they point
    properly again. This used to be a second walk of the whole object table,
    which was right only when nothing had thrown; it is now driven from the
    record of what was actually converted, and the destructor drives the same
    call on every throw above. Restore() clears saveMode itself, because the
    swap-back branch of Registry::Block is the one guarded by that flag.
    inc-i0r. */
    fixup.Restore();

    return 0;
}

#pragma warning(disable:4291) // no matching operator delete found; memory will not be freed if initialization throws an exception

int16 Registry::LoadGroup(Term &t, hObj hGroup, bool use_lz) {
    fileHeader fh;
    groupHeader gh;
    OArray<Object*,10,10> LoadedObjects;
    Object *o; void *pData;
    int8 oType; int32 i;
    hObj   DataOwner;
    hData  DataHandle;
    uint32 DataSize;
    uint32 Seperator;
    /* Declared here, and NOT at the label below, so that the guard covers the
       throws above it and so that "goto foundGroup" no longer jumps across an
       initialisation. See RegistryScope. inc-w7q. */
    CFile *cf = NULL;
    RegistryScope guard(loadMode, &cf);

    ClearDataTable();

    loadMode = true;

    /* Read Header */
    t.FRead(&fh,sizeof(fh));

    /* Check Version Number */
    if (!SaveFormatMatches(fh.Version))
      throw EBADVER;
    
    /* Scan through the saved groups for the specific one that we're
       looking to restore. */
    for(i=0;i!=fh.numGroups;i++)
      {
        t.FRead(&gh,sizeof(gh));
        if (gh.Signature != SIGNATURE)
          throw ECORRUPT;
        if ((gh.hGroup == hGroup) || !hGroup)
          goto foundGroup;

        /* This is the wrong group, so skip over it. */
        t.Seek(gh.groupSize,SEEK_CUR);
      }
    /* The chunk is missing! */
    throw ENOCHUNK;

foundGroup:
    /* upstream: gh.compSize and gh.groupSize are signed int32 fields read
       straight out of the group header a few lines up (t.FRead(&gh,...))
       with no sanity test in the original code -- a save file or .Mod is
       data the game merely trusts, and both sizes flow straight into
       CFile::LoadCompressed()'s malloc()s below. A corrupt or truncated
       file can make either one zero, negative (both are signed), or larger
       than the file that is supposed to contain it; nothing stopped that
       from reaching malloc(). compSize is bounded here by how many bytes
       are actually left in the file to read it from -- the tightest bound
       available -- and groupSize (the DECOMPRESSED size, which is not and
       should not be bounded by the compressed file's size) by the shared
       CFILE_SANE_MAX_SIZE ceiling in inc/Term.h. CFile::LoadCompressed
       repeats the zero/negative/ceiling half of this check on its own, so
       this file is not the only thing standing between a corrupt header
       and a bad allocation. Evidence: Traced (this function and
       CFile::LoadCompressed read together). Tracking: inc-l0t. Not sent. */
    {
        int32 herePos = t.Tell();
        int32 fileEnd;
        t.Seek(0, SEEK_END);
        fileEnd = t.Tell();
        t.Seek(herePos, SEEK_SET);

        if (gh.compSize <= 0 || gh.groupSize <= 0 ||
            gh.compSize > (fileEnd - herePos) ||
            gh.groupSize > CFILE_SANE_MAX_SIZE)
            throw ECORRUPT;
    }

    cf = new CFile(&t);
    cf->LoadCompressed(t.Tell(), gh.compSize, gh.groupSize, use_lz);

    LastUsedHandle = max(LastUsedHandle, gh.LastHandle);
    for (i=0; i != gh.objCount; i++) {
        /* What type of object is this? */
        cf->FRead(&oType,1);                   

        /* Allocate the object. Account for the
           special case of the (singular) Game
           object, which is not reallocated but
           always overwritten. */
        if (oType == T_GAME)
          o = theGame;
        else
          o = (Object*)malloc(typeSize(oType));
        if (!o)
          throw EMEMORY;
         
        /* ...read in the object... */
        cf->FRead(o,typeSize(oType));

        /* ...reattach its virtual table pointer by calling
              a kludged, overridden new() operator in Object
              that "allocates" the space we've allocated, and
              then goes to a constructor that does nothing. */
        switch(oType)
          {
            /* Core game objects */
            case T_GAME:     new(o) Game(this); break;
            //case T_TERM:     new(o) Term(this); break;
            case T_MAP:      new(o) Map(this); break;
            //case T_REGISTRY: new(o) Registry(this); break;
            case T_MONSTER:  new(o) Monster(this); break;
            case T_PLAYER:   new(o) Player(this); break;
            //case T_NPC:      new(o) NPC(this); break;
            case T_MODULE:   new(o) Module(this); break;
            /* Features */
            case T_PORTAL:   new(o) Portal(this); break;
            case T_DOOR:     new(o) Door(this); break;
            case T_TRAP:     new(o) Trap(this); break;
            case T_FEATURE:  new(o) Feature(this); break;
            //case T_ALTAR:    new(o) Altar(this); break;
        
            /* Containers */
            case T_CHEST:
            case T_CONTAIN:  new(o) Container(this); break;

            /* Items */
            case T_COIN:     new(o) Coin(this); break;
            case T_FOOD:     new(o) Food(this); break;
            case T_STATUE:
            case T_FIGURE:
            case T_CORPSE:   new(o) Corpse(this); break;
            case T_MISSILE:  case T_BOW:
            case T_WEAPON:   new(o) Weapon(this); break;
            case T_ARMOUR:    case T_SHIELD:
            case T_GAUNTLETS:
            case T_BOOTS:    
                             new(o) Armour(this); break;

            //case T_CONSTRUCT:new(o) Construct(this); break;
            //case T_ILLUSION: new(o) Illusion(this); break;
            default:
              if (oType >= T_FIRSTITEM && oType <= T_LASTITEM)
                new(o) Item(this); 
              else
                Fatal("Wrong Type right after call to typeSize?!");
          }

        /* Verify it is in fact the correct type. */
        if (o->Type != oType)
          throw ECORRUPT;

        /* upstream: base-code defect. SaveGroup writes whole C++ objects as
           raw bytes (typeSize() per object, right above), so a Creature's
           embedded TargetSystem (Creature::ts) comes back exactly as it was
           written, including -- for anything saved before c9201dd (inc-zmk's
           Target zero-init fix) -- whatever was on the stack when each
           Target was constructed. That fix only stops NEW Targets from
           carrying garbage; it does nothing for ones already on disk, and
           re-saving doesn't clean them either, since the same bytes just get
           read back into the same fields. Sanitizing here, once, right after
           every Creature is loaded, covers both save files and modules
           (both go through this same loop) without caring which one this
           load is. Evidence: Observed (inc-upw.13 itself measured 1,944 such
           asserts on a soak save; a 20-turn walk on a sandboxed copy of
           Brian's own save/Jaoin.sav, loaded under a binary with c9201dd but
           without this fix, logged 74 -- ASSERT failed:
           '...Get(h)->isCreature()' at inc/Base.h:607, called from
           Target::GetThingOrNULL from Monster::Movement. 0 with this and the
           matching GetThingOrNULL fix in place, same save, same walk).
           Tracking: inc-upw.13. Not sent. */
        if (o->isCreature())
          ((Creature*)o)->ts.SanitizeLoadedTargets();

        /* And register our new object in the Registry. */
        RegisterObject(o,true);

        /* Add it to the serialization list */
        LoadedObjects.Add(o);
      }

    /* Read and confirm the special objects-data seperator to assure
       that the data file is not corrupt. */
    cf->FRead(&Seperator,4);
    if (Seperator != SIGNATURE_TWO)
      throw ECORRUPT;

    for(i=0;i!=gh.dataCount;i++)
      {
        /* Read data handle */
        cf->FRead(&DataHandle,4);
        /* Read data owner's handle */
        cf->FRead(&DataOwner,4);
        /* Read data size */
        cf->FRead(&DataSize,4);

        ASSERT(DataHandle > 127);
        ASSERT(DataOwner  > 127);

        /* Allocate space for data */
        pData = malloc(DataSize);
        if (!pData)
          throw EMEMORY;

        /* Read in the data... */
        cf->FRead(pData,DataSize);

        /* Add it to the Registry */
        RegisterBlock(pData,DataOwner,DataSize,DataHandle);
      }

    /* Restore the objects' pointers to their data. */
    saveMode = false;
    for(i=0;i!=gh.objCount;i++) {
      hCurrent = (*(LoadedObjects[i]))->myHandle;
      (*(LoadedObjects[i]))->Serialize(*this,false);
      }

    /* loadMode and cf are cleared by the guard, on this path and on every
       throw above. Clearing them here as well would only say it twice. */
    return 0;
}

/* Diagnostic: set INCURSION_SAVE_PROBE=1 to record the player's map position
   on both sides of the save/load boundary. Tells apart "the coordinates were
   never written" from "they were written and not read back". */
static void SaveLoadProbe(const char *what, Player *pl) {
    static FILE *f = NULL;
    if (!getenv("INCURSION_SAVE_PROBE"))
        return;
    if (!f) {
        /* Absolute path: the game chdir()s constantly, so a relative one
           lands wherever it happens to be and usually fails. */
        char path[1024];
        snprintf(path, sizeof(path), "%slogs/saveprobe.log",
            (const char*)T1->IncursionDirectory);
        f = fopen(path, "a");
    }
    if (!f)
        return;
    fprintf(f, "%-20s player=(%d,%d) map=%p size=%dx%d\n", what,
        pl ? (int)pl->x : -999, pl ? (int)pl->y : -999,
        (void*)(pl ? pl->m : NULL),
        (pl && pl->m) ? (int)pl->m->SizeX() : -1,
        (pl && pl->m) ? (int)pl->m->SizeY() : -1);
    fflush(f);
}

/* Diagnostic: set INCURSION_CHAR_PROBE=1 to write a full character sheet
   next to every save, as logs/charprobe.txt and .html. The save file itself
   cannot be read from outside the game -- Registry::SaveGroup writes whole
   C++ objects as raw bytes, vptrs and padding included -- so answering
   "which feats does this character actually have" otherwise means finishing
   the game and reading the end-of-game dump.

   This formats nothing of its own. It calls the game's own dump writer, so
   it shows exactly what the end-of-game dump shows, and cannot drift from
   it. It overwrites, so the file always describes the most recent save.

   DumpCharacter chdir()s to the log directory and does not change back.
   That is safe here: ChangeDirectory rebuilds an absolute path from
   IncursionDirectory (src/Wlibtcod.cpp:307), so the save that follows still
   lands in save/ wherever this leaves the working directory. It still runs
   first, so a failure in the dump cannot land midway through writing a
   save. */
static void CharacterProbe(void) {
    String base;

    if (!getenv("INCURSION_CHAR_PROBE"))
        return;
    base = "charprobe";
    T1->DumpCharacter(base);
}

bool Game::SaveGame(Player &p) {
      fileHeader fh; int32 i;
      String fn, base, desc;

      p.TouchGallery(true);

      CharacterProbe();

      T1->ChangeDirectory(T1->SaveSubDir());

      memset(p.MessageQueue,0,sizeof(String)*8);

      if (SaveFile.GetLength()) { 
          // ww: I'm still getting that hideous savefile corruption bug, so
          // let's make a backup copy instead of just deleting this!
          FILE *fin = NULL, *fout = NULL;
          char buf[4096]; 
          if (!T1->Exists(SaveFile) || !(fin = fopen((const char*)SaveFile,"rb")))
            { p.MyTerm->Message("Save File Backup: Failed (#1)"); goto failed; }
          fout = fopen((const char*)(SaveFile + BACKUP_SUFFIX),"wb");
          if (!fout)
            { p.MyTerm->Message("Save File Backup: Failed (#2)"); goto failed; }
          struct stat statbuf;
          if (stat(SaveFile,&statbuf)) 
            { p.MyTerm->Message("Save File Backup: Failed (#3)"); goto failed; }
          off_t sofar;
          for (sofar = 0; sofar < statbuf.st_size;) {
              size_t this_read = fread(buf,1,min(sizeof(buf),statbuf.st_size - sofar),fin);
              if (this_read == 0) 
                { p.MyTerm->Message("Save File Backup: Failed (#4)"); goto failed; }
              size_t this_write ;
              this_write = fwrite(buf,1,this_read,fout);
              if (this_write == 0 || this_read != this_write) 
                { p.MyTerm->Message("Save File Backup: Failed (#5)"); goto failed; }
              sofar += this_read; 
          } 
failed: 
          if (fin) fclose(fin);
          if (fout) fclose(fout);
          T1->Delete(SaveFile);
          //unlink(SaveFile);
          SaveFile.Empty(); 
      }

//Retry:
      base = p.Named;
      while (base.strchr(' '))
          base = base.Left(base.strchr(' '));
      if (!base.GetLength())
          base = "Unnamed";
      for(i=0;i!=base.GetLength();i++)
          if (!isalpha(base[i]))
              base.SetAt(i,'_');
      fn = Format("%s.sav",(const char*)base);
      SaveFile = fn; 
      if (T1->Exists(fn)) 
          for(i=2;i!=255;i++) {
              SaveFile = Format("%s_%d.sav", (const char*)base,i);
              fn = SaveFile; 
              if (!T1->Exists(fn))
                  break;
          }

      desc = p.Named + SC(", ");
      desc += NAME(p.RaceID);
      for(i=0;i!=3 && p.ClassID[i];i++)
          desc += Format("%s %s %d", i ? " /" : "",
          NAME(p.ClassID[i]), p.Level[i]);

#if 0
      if (RES(p.m->dID)->Type == T_TDUNGEON)
          desc += Format(" (%s, at %03dm)",
          RES(p.m->dID)->RandMessage(MSG_SHORTNAME), p.m->Depth*10);
      else
          desc += Format(" (%s)",
          RES(p.m->dID)->RandMessage(MSG_SHORTNAME));
#endif

      desc = desc.Left(63);

      // weimer: I'm not sure how to hack this in, but it should happen
      // before we serialize the player
      theGame->GetPlayer(0)->StoreLevelStats((uint8)(theGame->GetPlayer(0)->m->Depth));

      try {  
          T1->OpenWrite(fn);

          memset(&fh,0,sizeof(fh));
          strcpy(fh.Version,SaveFormatID());
          fh.Sig = SIGNATURE;
          fh.numGroups = 1;
          strncpy(fh.Name,desc,71);
          T1->FWrite(&fh,sizeof(fh));
          SaveLoadProbe("save: before write", &p);
          theRegistry->SaveGroup(*T1,0,false,true);
          SaveLoadProbe("save: after write", &p);
          T1->Close();
          T1->ChangeDirectory(T1->IncursionDirectory);
      }
      catch (int error_number) {
          Error("Error writing save file (%s).",
              Lookup(FileErrors,error_number));
          T1->ChangeDirectory(T1->IncursionDirectory);
          return false;

      }
      return true;
}

bool Game::LoadGame(bool backup) {
    int32 i;
    String Filenames[128], Filedescs[128], fn;
    fileHeader fh; bool found;
    int patternsize = backup ? strlen(SAVE_BACKUP_PATTERN) : strlen(SAVE_PATTERN);
    char *pattern = (char *)alloca(patternsize + 1);
    strncpy(pattern, backup ? SAVE_BACKUP_PATTERN : SAVE_PATTERN, patternsize);
    pattern[patternsize] = '\0';

    T1->ChangeDirectory(T1->SaveSubDir());

    try {
        if (!T1->FirstFile(pattern)) {
NoSaved:
            T1->LOptionClear();
            T1->Box(Format("There are currently no %s available to load.",
                backup ? "backup files" : "saved games"));
            return false;
        }

        T1->SetWin(WIN_SCREEN);
        T1->Clear(); T1->GotoXY(0, 0);
        i = 0;
        found = false;
        do {
            T1->FRead(&fh, sizeof(fh));
            T1->Close();
            if (!SaveFormatMatches(fh.Version))
                continue;

            Filenames[i] = T1->GetFileName();
            Filedescs[i] = fh.Name;
            if (backup) {
                struct stat statbuf;
                stat(Filenames[i], &statbuf);
                Filedescs[i] += Format(" (BACKUP at %s)", ctime(&statbuf.st_ctime));
            }
            T1->LOption(Filedescs[i], i);
            found = true;

            i++;
        } while (T1->NextFile() && i < 128);

        if (!found)
            goto NoSaved;

        T1->Clear();
        if (!i)
            goto NoSaved;

        i = T1->LMenu(MENU_SORTED | MENU_ESC, "Choose a character:\n\n", WIN_SCREEN);
        if (i < 0) {
            T1->ChangeDirectory(T1->IncursionDirectory);
            return false;
        }

        fn = Filenames[i];
        T1->Clear();
        T1->GotoXY(0, 0);
        T1->Color(WHITE);
        T1->Write("Loading... ");

        T1->OpenRead(fn);
        /* The central Game object gets overwritten. */
        MainRegistry.RemoveObject(theGame);
        MainRegistry.LoadGroup(*T1, 0, false);
        T1->Close();
        SaveFile = fn;
        T1->ChangeDirectory(T1->IncursionDirectory);
    } catch (int error_number) {
        Error("Error reading saved game (%s).", Lookup(FileErrors, error_number));
        T1->ChangeDirectory(T1->IncursionDirectory);
        return false;
    }

    /* LoadGroup should have overwritten theGame with the
    restored version from disk; thus, p[0] points to the
    player and m[0] points to the current map. The dungeon
    is described by the arrays in theGame as well. Rather
    than crash horribly, however, let us just confirm this. */

    if (!p[0] || !m[0]) {
        Error("Null map/player after saved game loaded!");
        return false;
    }
    SaveLoadProbe("load: after read", oPlayer(p[0]));
    /* Here, we look what resource files this saved game depends
    on, and restore them each in order. */
    theRegistry = &ResourceRegistry;
    memset(Modules, 0, sizeof(Module*)*MAX_MODULES);
    for (i = 0; ModFiles[i]; i++) {
        try {
            char * filespec = ModFiles[i]->FName;
            T1->ChangeDirectory(T1->ModuleSubDir());
            //T1->Scour(ModFiles[i]->FName,true);
            T1->OpenRead(filespec);
            ResourceRegistry.LoadGroup(*T1, ModFiles[i]->hMod, true);
            T1->Close();
            if (!oThing(ModFiles[i]->hMod))
                throw EHANDLE;

            Modules[ModFiles[i]->Slot] = oModule(ModFiles[i]->hMod);
            T1->ChangeDirectory(T1->IncursionDirectory);
        } catch (int error_number) {
            Error("Error loading module '%s' (%s).", ModFiles[i]->FName, Lookup(FileErrors, error_number));
            T1->ChangeDirectory(T1->IncursionDirectory);
        }
    }

    theRegistry = &MainRegistry;
    memset(oPlayer(p[0])->MessageQueue, 0, sizeof(String) * 8);
    InitGodArrays();

    oPlayer(p[0])->MyTerm = T1;
    T1->SetPlayer(oPlayer(p[0]));
    T1->SetMap(oMap(m[0]));
    T1->SetMode(MO_PLAY);
    oPlayer(p[0])->CalcValues();
    oPlayer(p[0])->CalcVision();
    SaveLoadProbe("load: after modules", oPlayer(p[0]));
    T1->AdjustMap(oPlayer(p[0])->x, oPlayer(p[0])->y, true);
    T1->ShowStatus();
    T1->ShowTraits();
    oPlayer(p[0])->LoadOptions(false);
    oPlayer(p[0])->ResetLevelStats();
    oPlayer(p[0])->TouchGallery(true);
    oPlayer(p[0])->IPrint("Welcome back to Incursion, <Str>!", (const char*)oPlayer(p[0])->Name(0));
    if (oPlayer(p[0])->GodID)
        oPlayer(p[0])->GodMessage(oPlayer(p[0])->GodID, MSG_SALUTATION);
    doQuit = false;

    return true;
}

void Game::SaveModule(int16 mn) {
    fileHeader fh;
    if (!Modules[mn]) {
        Error("Attempt to save non-existent module!");
        return;
    }
    if (!Modules[mn]->FName) {
        Error("Module has no filename!");
        return;
    }

    try {
        const char * filespec = Modules[mn]->GetText(Modules[mn]->FName);
        T1->ChangeDirectory(T1->ModuleSubDir());
        T1->OpenWrite(filespec);
        memset(&fh, 0, sizeof(fh));
        strcpy(fh.Version, SaveFormatID());
        fh.Sig = SIGNATURE;
        fh.numGroups = 1;
        strncpy(fh.Name, Modules[mn]->GetText(Modules[mn]->Name), 71);
        T1->FWrite(&fh, sizeof(fh));
        theRegistry = &ResourceRegistry;
        theRegistry->SaveGroup(*T1, Modules[mn]->myHandle, true, true);
        theRegistry = &MainRegistry;
        T1->Close();
        T1->ChangeDirectory(T1->IncursionDirectory);
    } catch (int error_number) {
        Error("Error writing module (%s).", Lookup(FileErrors, error_number));
        T1->ChangeDirectory(T1->IncursionDirectory);
        return;
    }

    return;
}

bool Game::LoadModules() {
    String fn;
    ModuleRecord mr;
    ModuleRecord mrBacklog[MAX_MODULES];
    uint8 sl, i, backlogCount = 0, moduleCount = 0;

    Cleanup();

    T1->ChangeDirectory(T1->ModuleSubDir());

    theRegistry = &ResourceRegistry;
    try {
        if (!T1->FirstFile("*.Mod")) {
            Fatal(Format("%s\nCan't find any game data modules!", (const char*)T1->ModuleSubDir()));
        }

        do {
            strcpy(mr.FName, T1->GetFileName());
            ResourceRegistry.LoadGroup(*T1, 0, true);
            T1->Close();
            mr.hMod = ResourceRegistry.GetModuleHandle();
            if (!oModule(mr.hMod))
                throw EHANDLE;

            if ((backlogCount + moduleCount) == MAX_MODULES) {
                Error("Only %d modules can be loaded at once!", MAX_MODULES);
                delete oModule(mr.hMod);
                break;
            }

            if (oModule(mr.hMod)->Slot == -1) {
                mrBacklog[backlogCount++] = mr;
            } else {
                sl = (uint8)oModule(mr.hMod)->Slot;
                if (Modules[sl]) {
                    Error("Two fixed-slot modules (%s and %s) conflict over slot %d!",
                        oModule(mr.hMod)->GetText(oModule(mr.hMod)->Name),
                        Modules[sl]->GetText(Modules[sl]->Name), sl);
                    delete oModule(mr.hMod);
                    continue;
                }

                Modules[sl] = oModule(mr.hMod);
                mr.Slot = sl;
                ModFiles.Add(mr);

                moduleCount++;
            }
        } while (T1->NextFile());

        // Fill in the empty module slots with the backlog of floating slot modules.
        sl = 0;
        for (i = 0; i < backlogCount; i++) {
            while (Modules[sl])
                sl++;
            ASSERT(sl < MAX_MODULES);
            mr = mrBacklog[i];
            Modules[sl] = oModule(mr.hMod);
            mr.Slot = sl;
            ModFiles.Add(mr);
        }
    } catch (int error_number) {
        Error("Error loading module '%s' (%s).", mr.FName, Lookup(FileErrors, error_number));
        theRegistry = &MainRegistry;
        T1->ChangeDirectory(T1->IncursionDirectory);
        return false;
    }

    theRegistry = &MainRegistry;
    T1->ChangeDirectory(T1->IncursionDirectory);
    InitGodArrays();

    return true;
}
