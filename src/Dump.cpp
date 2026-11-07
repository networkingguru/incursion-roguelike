/* DUMP.CPP -- See the Incursion LICENSE file for copyright information.

     Implements `-dump <save-file>`: load a save read-only, through the
   game's own Registry::LoadGroup, and print a plain-text character report
   to stdout. Exists so a person -- or a read-only oracle session, which is
   forbidden from running the game any other way -- can answer "what is she
   carrying / what stati is she under / what does the game think her weapon
   skill is" about a real save, without playing the game.

     This formats almost nothing of its own. Most of the report is the
   game's own TextTerm::CreateCharDump (src/Sheet.cpp), the same walk that
   already backs INCURSION_CHAR_PROBE (src/Registry.cpp:773) and the in-game
   character sheet, so it cannot drift from what the engine actually thinks.
   Only the fields that dump does not cover -- current HP, position, depth,
   equipped slots, and each object's own stati and raw iID/eID/mID -- are
   walked here directly, with real accessors, never by hand-parsing bytes.

   SAFETY. This path opens the named file and the save's own module
   dependencies for reading ONLY. It never calls OpenWrite, never calls
   Delete, never calls Player::TouchGallery, and never calls Game::SaveGame.
   See bd inc-loa.1 and docs/ENGINE-SERIALISATION.md for the format this
   walks and why an external parser was rejected.

     bool RunSaveDump(const char *path)
*/

#include <vector>
#include <map>
#include <string>
#include <algorithm>
#include "Incursion.h"

extern void InitGodArrays();

/* ---------------------------------------------------------------- output --
   CreateCharDump() (src/Sheet.cpp) and Item::Name() both return a String
   carrying the game's own colour-switch bytes: negative signed chars, one
   per colour (see TextTerm::Write). -dump has no terminal and no HTML
   writer to hand them to, and the acceptance criterion is plain text,
   complete over pretty (bd inc-loa.1), so strip them exactly the way
   TextTerm::DumpCharacter's own plain-text branch does (src/Sheet.cpp:
   1397-1403) rather than inventing a second rule for the same bytes. */
static void PrintPlain(String &s) {
    for (const char *c = (const char*)s; *c; c++) {
        char ch = *c;
        if (ch == '~') ch = '%';
        if (ch <= 0) continue;
        putchar((unsigned char)ch);
    }
}

/* Every Thing -- player, monster, item, corpse -- carries its own
   StatiCollection (Thing::__Stati, inc/Map.h:670), and StatiIter walks it
   with the real macro the rest of the engine uses (inc/Map.h:507), not a
   hand-rolled reimplementation. */
static void DumpStati(Thing *t) {
    bool any = false;
    StatiIter(t)
        any = true;
        printf("      Nature=%-3u Val=%-6d Mag=%-6d Duration=%-6d Source=%u "
               "CLev=%u eID=%d h=%d\n",
            S->Nature, S->Val, S->Mag, S->Duration, S->Source, S->CLev,
            (int)S->eID, (int)S->h);
    StatiIterEnd(t)
    if (!any)
        printf("      (none)\n");
}

/* Recurses into containers regardless of depth: the standard character
   sheet's inventory listing does not (src/Sheet.cpp:1341-1343 passes
   descend=false for the carried list), which would hide a corpse sitting
   inside a backpack. Prints the raw iID/eID/mID fields alongside the
   readable name because that is exactly what inc-52b needs: what a category
   match like Character::Sacrifice (src/Prayer.cpp:311) actually sees. */
static void DumpItem(Item *it, int depth) {
    printf("%*s- ", depth, "");
    PrintPlain(it->Name(NA_LONG | NA_MECH | NA_INSC));
    printf("\n");
    printf("%*s  Type=%d iID=%d eID=%d Plus=%d InherentPlus=%d Charges=%d "
           "Quantity=%u ItemHP=%d IFlags=%u Known=%d Blessed=%d Cursed=%d "
           "Masterwork=%d\n",
        depth, "", it->Type, it->iID, it->eID,
        it->GetPlus(), it->GetInherentPlus(), it->GetCharges(),
        it->Quantity, it->GetHP(), it->IFlags,
        it->isKnown(), it->isBlessed(), it->isCursed(), it->isMaster());

    rID corpseType = it->GetCorpseType();
    if (corpseType)
        printf("%*s  mID=%d (%s)\n", depth, "", corpseType, NAME(corpseType));

    /* Inscrip can itself carry embedded colour-switch bytes (observed: an
       auto-generated flavour inscription like "mundane" stored wrapped in
       -GREY on both sides), so it needs the same stripping as everything
       else routed to stdout -- printing it raw broke a later byte in this
       same line. */
    if (it->Inscrip.GetLength()) {
        printf("%*s  Inscription: ", depth, "");
        PrintPlain(it->Inscrip);
        printf("\n");
    }

    printf("%*s  Stati:\n", depth, "");
    DumpStati(it);

    if (it->isContainer()) {
        Container *c = (Container*)it;
        int shown = 0;
        for (Thing *t = oThing(c->Contents); t; t = oThing(t->Next))
            if (t->isItem()) {
                DumpItem((Item*)t, depth + 4);
                shown++;
            }
        if (!shown)
            printf("%*s  (empty)\n", depth + 2, "");
    }
}

/* A resource name for the flavour report below, with the bounds checked by
   hand. Two reasons NAME() is not used here. First, one purpose of the
   Effect Memory section is to make a MISREAD memory segment visible in the
   dump output (tools/check_flavor_stability.sh diffs it across a module
   rebuild): a shifted or garbage rID must print as text, never crash the
   report, and NAME() dereferences Get(rID) unguarded. Second, NAME()'s
   ternary converts GetName's String& into a String TEMPORARY, so its
   (const char*) is only alive for the full expression it sits in -- fine
   at a printf argument, dangling the moment a helper RETURNS it (observed:
   heap garbage in place of every name). So the name is read straight from
   the module's text segment, into a rotating static buffer, with GetName's
   own ';'-truncation applied by hand. */
static const char* SafeResName(rID xID) {
    static char bufs[4][120];
    static int cyc;
    if (!xID)
        return "-";
    int slot = (int)(xID >> 24) - 1;
    if (slot < 0 || slot >= MAX_MODULES || !Game::Modules[slot])
        return "(invalid module slot)";
    Module *mod = Game::Modules[slot];
    if ((int32)(xID & 0x00FFFFFF) >= (int32)mod->NumResources())
        return "(out of range)";
    Resource *res = theGame->Get(xID);
    if (!res)
        return "(no resource)";
    const char *nm = mod->GetText(res->Name);
    if (!nm)
        return "(unnamed)";
    char *out = bufs[cyc];
    cyc = (cyc + 1) % 4;
    size_t n = 0;
    for (; nm[n] && nm[n] != ';' && n < sizeof(bufs[0]) - 1; n++)
        out[n] = nm[n];
    out[n] = 0;
    return out;
}

/* Why RunTo's tier-3 gate (DF_IGNORE_TRAPS|DF_IGNORE_TERRAIN, memory enforced)
   rejects one square. This mirrors the never-relaxed branches of Map::RunOver
   (src/Djikstra.cpp:268) in the same order; only these four can still block a
   square once traps and hazardous terrain are ignored. ponytail: it is a
   second copy of RunOver's block conditions, kept only to LABEL a square the
   gate walk below has already rejected. It never decides reachability -- the
   walk calls the real RunOver for that -- so if RunOver's gate changes, a
   stale copy here costs a wrong label on a diagnostic line, never a wrong
   route. Keep it in step with RunOver anyway. inc-otz. */
static String GateBlockReason(Map *m, Player *p, int16 x, int16 y) {
    bool Incor = p->HasMFlag(M_INCOR) || p->HasStati(PHASED);
    bool Meld  = p->HasAbility(CA_EARTHMELD);
    if (!Incor && m->SolidAt(x, y) && !Meld)
        return String("solid rock or feature");
    if (!m->At(x, y).Memory)
        return String("unexplored -- no memory of this square");
    Creature *ca;
    for (ca = m->FCreatureAt(x, y); ca; ca = m->NCreatureAt(x, y))
        if (ca && p->Perceives(ca) && ca->isHostileTo(p))
            return Format("perceived hostile: %s (handle %d)",
                          (const char *)ca->Name(0), (int)ca->myHandle);
    Door *dr;
    for (dr = m->FDoorAt(x, y); dr; dr = m->NDoorAt(x, y))
        if (!dr->isPassable())
            return String("impassable door -- locked, stuck or broken shut");
    if (m->RegionAt(x, y) && m->RegionAt(x, y) != m->RegionAt(p->x, p->y)
        && TREG(m->RegionAt(x, y))->Size < p->GetAttr(A_SIZ)
        && p->onPlane() == PHASE_MATERIAL && !p->HasAbility(CA_EARTHMELD))
        return String("region too small for the runner");
    return String("blocked, but by nothing in the never-relaxed set "
                  "-- recheck against RunOver");
}

/* Name for a Map::RunToFailReason code, for the per-portal line below. It lets
   -dump cross-check RunToFailReason against the cut list: a portal the gate
   blocks purely on unexplored ground must report "unexplored ground on the
   route" here. inc-otz. */
static const char *RtfName(int r) {
    switch (r) {
    case RTF_NOROUTE:    return "no open route at all";
    case RTF_UNEXPLORED: return "unexplored ground on the route";
    case RTF_HOSTILE:    return "a perceived hostile on the route";
    case RTF_DOOR:       return "an impassable door on the route";
    case RTF_TOOSMALL:   return "a region too small for the runner on the route";
    default:             return "none (target is reachable)";
    }
}

/* The load-time copy of every module's script data segment prefix.

   docs/SAVE-SCHEMA-SPEC.md (test plan, cases 15-30): the -dump report MUST
   print every variable "as the load placed them, copied before any report
   step runs game logic: the report's own steps (for example DumpStati) run
   scripts that write variables." Recovers that: LoadSaveForReport() copies
   each module's szDataSeg-byte prefix here the instant SaveV1_ResolveNames()
   / SaveV0_RecoverVariables() has placed it, and PrintScriptVariables reads
   the values from the copy, never from the live MDataSeg the report's own
   game-logic steps keep writing. */
static char  *v1ReportVars[MAX_MODULES];
static uint32 v1ReportVarsSize[MAX_MODULES];

static void CaptureScriptVariables()
{
    for (int ms = 0; ms < MAX_MODULES; ++ms) {
        if (v1ReportVars[ms]) { free(v1ReportVars[ms]); v1ReportVars[ms] = 0; }
        v1ReportVarsSize[ms] = 0;
        Module *mod = Game::Modules[ms];
        if (!mod || mod->szDataSeg <= 0)
            continue;
        if (!theGame->MDataSeg[ms] ||
                theGame->MDataSegSize[ms] < (uint32)mod->szDataSeg)
            continue;
        v1ReportVars[ms] = (char*)malloc(mod->szDataSeg);
        if (!v1ReportVars[ms])
            continue;
        memcpy(v1ReportVars[ms], theGame->MDataSeg[ms], mod->szDataSeg);
        v1ReportVarsSize[ms] = (uint32)mod->szDataSeg;
    }
}

/* canon: the canonical mode (INCURSION_DUMP_CANONICAL, CanonDump below) prints
   a handle-typed variable as set or unset and an rID-typed one by resource
   name. The default report passes false and is unchanged. */
static bool PrintScriptVariables(bool values, bool canon = false)
{
    for (int ms = 0; ms < MAX_MODULES; ++ms) {
        Module *mod = Game::Modules[ms];
        if (!mod) continue;
        String reason;
        if (!ValidateScriptVariables(mod, ms, reason)) {
            printf("Validity: FAIL module=%d: %s\n", ms, (const char*)reason);
            return false;
        }
        std::vector<DebugInfo*> rows(mod->szDataSeg / 4);
        for (int i = 0; i < mod->Symbols.Total(); ++i) {
            DebugInfo *d = mod->Symbols[i];
            if (d->BType == GLOB_VAR || d->BType == RES_VAR)
                rows[d->Address] = d;
        }
        /* The load-time copy is the only sound value source: the report's
           own game-logic steps (DumpStati, the equipped-slot walk,
           CreateCharDump) run scripts that write MDataSeg. Fall back to the
           live segment only for -scriptvars, which loads no save and so
           takes no copy. See CaptureScriptVariables. */
        const char *varSeg = v1ReportVars[ms] ? v1ReportVars[ms] : theGame->MDataSeg[ms];
        uint32 varSegSize = v1ReportVars[ms] ? v1ReportVarsSize[ms] : theGame->MDataSegSize[ms];
        if (values && !rows.empty() && (!varSeg ||
                varSegSize < (uint32)mod->szDataSeg)) {
            printf("Validity: FAIL module=%d: script data segment is missing or short\n", ms);
            return false;
        }
        std::map<rID, int> ordinals;
        for (size_t slot = 0; slot < rows.size(); ++slot) {
            DebugInfo *d = rows[slot];
            rID owner = d->BType == GLOB_VAR ? 0 : d->xID;
            int ordinal = ordinals[owner]++;
            const char *name = owner ? mod->GetText(mod->__GetResource(owner)->Name) : "(module)";
            const char *type = d->DataType == DT_RECT ? "Rect" : Lookup(DataTypeNames, d->DataType);
            if (values) {
                int32 value;
                memcpy(&value, varSeg + slot * 4, sizeof(value));
                if (canon && d->DataType == DT_HOBJ)
                    printf("  slot=%u owner=%s ordinal=%d ident=%.*s type=%s value=%s\n",
                           (unsigned)slot, name, ordinal, 31, d->Ident, type,
                           value ? "(handle set)" : "(handle unset)");
                else if (canon && d->DataType == DT_RID)
                    printf("  slot=%u owner=%s ordinal=%d ident=%.*s type=%s value=%s\n",
                           (unsigned)slot, name, ordinal, 31, d->Ident, type,
                           SafeResName((rID)value));
                else
                    printf("  slot=%u owner=%s ordinal=%d ident=%.*s type=%s value=%d\n",
                           (unsigned)slot, name, ordinal, 31, d->Ident, type, (int)value);
            } else {
                int array = -1; int32 position = -1;
                if (owner) ScriptVariableOwner(mod, owner, array, position);
                printf("%d\t%d\t%s\t%d\t%.*s\t%s\t%d\n", array, (int)position,
                       name, ordinal, 31, d->Ident, type, (int)d->Address);
            }
        }
        printf("Validity: OK module=%d variables=%u szDataSeg=%d\n",
               ms, (unsigned)rows.size(), (int)mod->szDataSeg);
    }
    return true;
}

bool RunScriptVariables()
{
    if (!theGame->LoadModules()) return false;
    printf("owner-array\towner-position\towner-name\tordinal\tident\ttype\taddress\n");
    return PrintScriptVariables(false);
}

/* Load a save exactly as RunSaveDump does, through the deferred name
   resolution, and stop. A v1 load recovers an old save's script variables
   here, before any report or gameplay query runs; -recovervars reads them at
   this point so the value it prints is the load-time recovered value, not a
   value a later game-logic pass has overwritten. Returns false (having
   printed) on any refusal. */
static bool LoadSaveForReport(const char *path, fileHeader &fhdr) {
    if (!T1->Exists(path)) {
        fprintf(stderr, "incursion -dump: no such file: %s\n", path);
        return false;
    }

    /* Same call sequence as Game::LoadGame (src/Registry.cpp:908-1040), but
       trimmed to what a static report needs: no file-choice menu, no
       TouchGallery, no SetMode(MO_PLAY), no options load, no welcome
       message -- none of it writes anything and none of it is needed to
       read the fields below. OpenRead only; nothing here ever opens a file
       for writing. */
    /* The FILE's header, kept for the report: the Format line must name the
       stamp the file carries ("IS1." + the file's schema revision for a v1
       save, the SF digest for a v0 one), not this binary's own
       SaveFormatID() or SaveSchemaID(). LoadGroup reads the same bytes
       internally but does not hand them back. */
    memset(&fhdr, 0, sizeof(fhdr));

    try {
        T1->OpenRead(path);
        T1->FRead(&fhdr, sizeof(fhdr));
        T1->Close();
        T1->OpenRead(path);
        MainRegistry.RemoveObject(theGame);
        MainRegistry.LoadGroup(*T1, 0, false);
        T1->Close();
    } catch (int error_number) {
        fprintf(stderr, "incursion -dump: %s: %s\n", path,
            Lookup(FileErrors, error_number));
        if (error_number == EBADVER)
            fprintf(stderr,
                "incursion -dump: this build wants save-format %s\n",
                SaveFormatID());
        return false;
    }

    if (!theGame->p[0] || !theGame->m[0]) {
        fprintf(stderr,
            "incursion -dump: %s has no player/map after load\n", path);
        return false;
    }

    /* Reload every module the save depends on, from the list LoadGroup just
       restored as part of theGame's own serialized state (Game::ModFiles,
       inc/Res.h:1075, :1109). Same loop as Game::LoadGame:994-1015,
       read-only throughout. */
    theRegistry = &ResourceRegistry;
    memset(Game::Modules, 0, sizeof(Module*) * MAX_MODULES);
    for (int i = 0; theGame->ModFiles[i]; i++) {
        try {
            char *filespec = theGame->ModFiles[i]->FName;
            T1->ChangeDirectory(T1->ModuleSubDir());
            T1->OpenRead(filespec);
            ResourceRegistry.LoadGroup(*T1, theGame->ModFiles[i]->hMod, true);
            T1->Close();
            if (!oThing(theGame->ModFiles[i]->hMod))
                throw EHANDLE;
            Game::Modules[theGame->ModFiles[i]->Slot] =
                oModule(theGame->ModFiles[i]->hMod);
            T1->ChangeDirectory(T1->IncursionDirectory);
        } catch (int error_number) {
            fprintf(stderr, "incursion -dump: module '%s': %s\n",
                theGame->ModFiles[i]->FName, Lookup(FileErrors, error_number));
            theRegistry = &MainRegistry;
            T1->ChangeDirectory(T1->IncursionDirectory);
            return false;
        }
    }
    theRegistry = &MainRegistry;

    /* Deferred v1 name resolution, same placement as Game::LoadGame: after
       the module reload loop, before anything touches a resource field. A v0
       load queues nothing and this is a no-op for it. */
    try {
        if (strncmp(fhdr.Version, "IS", 2)) SaveV0_RecoverVariables(*theGame);
        else SaveV1_ResolveNames();
    } catch (int error_number) {
        fprintf(stderr, "incursion -dump: %s: %s\n", path,
            Lookup(FileErrors, error_number));
        return false;
    }

    /* Freeze the values the load just placed, here, before any report step
       (which runs game logic) can write them. The -dump Script Variables
       section prints this copy. docs/SAVE-SCHEMA-SPEC.md, test plan. */
    CaptureScriptVariables();

    return true;
}

bool RunRecoverVars(const char *path) {
    fileHeader fhdr;
    if (!LoadSaveForReport(path, fhdr)) return false;
    return PrintScriptVariables(true);
}

/* The two per-player memory tables, as report lines in module order. Shared by
   the default report (printed in this order, byte for byte as before) and the
   canonical one (sorted by name). */
static void EffectMemoryLines(Player *p, std::vector<std::string> &out) {
    char buf[512];
    for (int ms = 0; ms != MAX_MODULES; ms++) {
        Module *mod = Game::Modules[ms];
        if (!mod)
            continue;
        for (int32 j = 0; j != mod->szEff; j++) {
            rID eID = mod->EffectID((uint16)j);
            EffMem *em = EFFMEM(eID, p);
            if (!em->FlavorID && !em->PFlavorID && !em->Known &&
                    !em->Tried && !em->PKnown && !em->PTried)
                continue;
            std::string nm = SafeResName(eID);
            std::string fl = SafeResName((rID)em->FlavorID);
            std::string pf = SafeResName((rID)em->PFlavorID);
            snprintf(buf, sizeof(buf),
                "  %s: flavor=%s pflavor=%s Known=%d Tried=%d "
                "PKnown=%d PTried=%d",
                nm.c_str(), fl.c_str(), pf.c_str(),
                (int)em->Known, (int)em->Tried,
                (int)em->PKnown, (int)em->PTried);
            out.push_back(buf);
        }
    }
}

static void MonsterMemoryLines(Player *p, std::vector<std::string> &out) {
    char buf[512];
    for (int ms = 0; ms != MAX_MODULES; ms++) {
        Module *mod = Game::Modules[ms];
        if (!mod)
            continue;
        for (int32 j = 0; j != mod->szMon; j++) {
            rID mID = mod->MonsterID((uint16)j);
            MonMem *mm = MONMEM(mID, p);
            if (!mm->Seen && !mm->Fought && !mm->Kills && !mm->Battles &&
                    !mm->Deaths && !mm->pKills && !mm->Attacks &&
                    !mm->Resists && !mm->Immune && !mm->Feats && !mm->Flags)
                continue;
            snprintf(buf, sizeof(buf),
                "  %s: Seen=%d Fought=%d Kills=%d Battles=%d Deaths=%d "
                "pKills=%d Attacks=%d Resists=%d Immune=%d Feats=%d "
                "Flags=%d",
                SafeResName(mID),
                (int)mm->Seen, (int)mm->Fought, (int)mm->Kills,
                (int)mm->Battles, (int)mm->Deaths, (int)mm->pKills,
                (int)mm->Attacks, (int)mm->Resists, (int)mm->Immune,
                (int)mm->Feats, (int)mm->Flags);
            out.push_back(buf);
        }
    }
}

/* ------------------------------------------------------------- canonical --
   INCURSION_DUMP_CANONICAL=1 makes -dump print the character in a form two
   loads of one file, or two builds of one character, can be compared byte for
   byte (bd inc-10v7f phase 3; docs/specs/2026-11-06-fixture-builder-spec.md
   A7). Rules:
     - every rID prints as its resource name (SafeResName), never a number;
     - no handle and no pointer prints: a handle is only "set" or "unset";
     - no wall-clock value prints (GameTimeInfo seconds, the file path);
     - a table the engine keys by resource position (spells, gods, memory,
       dungeons, stati) prints sorted by name, so a module that reorders its
       resources does not change the text;
     - the default report is untouched: this mode is a separate walk.
   A field the walk does not print is not compared, so it reads every saved
   field of Creature, Character and Player and of every kit Item. Not printed:
   Thing::Next, Thing::hm and Thing::backRefs (handles), Item::Parent (handle),
   the map, and RInf (the creation-time perk record is not part of a save; its
   effects arrive as feats, abilities, spells, stati and kit). */
static std::string CNm(rID x) { return std::string(SafeResName(x)); }

static std::string ConstNm(TextVal *tbl, int32 v) {
    const char *s = LookupOnly(tbl, v);
    if (s)
        return std::string(s);
    char b[32];
    snprintf(b, sizeof(b), "#%d", (int)v);
    return std::string(b);
}

static std::string SpellNm(int n) {
    char b[48];
    if (n >= 0 && n < (int)theGame->LastSpell())
        return CNm(theGame->SpellID((uint16)n));
    snprintf(b, sizeof(b), "(no spell %d)", n);
    return std::string(b);
}

/* One line of text with colour bytes stripped and newlines escaped. */
static void PrintPlainLine(const char *s) {
    if (!s)             /* an empty String holds no buffer */
        return;
    for (; *s; s++) {
        char ch = *s;
        if (ch == '~') ch = '%';
        if (ch <= 0) continue;
        if (ch == '\n') { fputs("\\n", stdout); continue; }
        putchar((unsigned char)ch);
    }
}

static void PrintSorted(std::vector<std::string> &v) {
    std::sort(v.begin(), v.end());
    for (size_t i = 0; i != v.size(); i++)
        printf("%s\n", v[i].c_str());
}

struct CanonDump {
    static void Stati(Thing *t, int ind);
    static void Item_(Item *it, int ind);
    static int  InvOrdinal(Player *p, Item *want);
    static bool Run(Player *p, Map *m);
};

void CanonDump::Stati(Thing *t, int ind) {
    std::vector<std::string> v;
    char b[512];
    StatiIter(t)
        std::string nat = ConstNm(STATI_CONSTNAMES, S->Nature);
        std::string src = ConstNm(SS_CONSTNAMES, S->Source);
        std::string eid = CNm((rID)S->eID);
        snprintf(b, sizeof(b),
            "Nature=%s Val=%d Mag=%d Duration=%d Source=%s CLev=%u Dis=%u "
            "Once=%u eID=%s",
            nat.c_str(), (int)S->Val, (int)S->Mag, (int)S->Duration,
            src.c_str(), (unsigned)S->CLev, (unsigned)S->Dis,
            (unsigned)S->Once, eid.c_str());
        v.push_back(b);
    StatiIterEnd(t)
    std::sort(v.begin(), v.end());
    for (size_t i = 0; i != v.size(); i++)
        printf("%*sStati: %s\n", ind, "", v[i].c_str());
    if (v.empty())
        printf("%*sStati: (none)\n", ind, "");
}

void CanonDump::Item_(Item *it, int ind) {
    std::string iid = CNm(it->iID), eid = CNm(it->eID);
    printf("%*s- Item iID=%s eID=%s Type=%s\n", ind, "", iid.c_str(),
        eid.c_str(), ConstNm(T_CONSTNAMES, it->Type).c_str());
    std::string home = CNm(it->homeID);
    printf("%*s  Known=0x%x Plus=%d Charges=%d DmgType=%d GenNum=%d Flavor=%d "
           "homeID=%s HP=%d Age=%d Swing=%u Quantity=%u IFlags=0x%x\n",
        ind, "", (unsigned)it->Known, (int)it->Plus, (int)it->Charges,
        (int)it->DmgType, (int)it->GenNum, (int)it->Flavor, home.c_str(),
        (int)it->cHP, (int)it->Age, (unsigned)it->swingCount,
        (unsigned)it->Quantity, (unsigned)it->IFlags);
    printf("%*s  Thing: Image=0x%x Timeout=%d StoredMoveTimeout=%d "
           "Flags=0x%x Named=", ind, "", (unsigned)it->Image,
        (int)it->Timeout, (int)it->StoredMovementTimeout,
        (unsigned)it->Flags);
    PrintPlainLine((const char*)it->Named);
    printf("\n");
    printf("%*s  Inscription: ", ind, "");
    PrintPlainLine((const char*)it->Inscrip);
    printf("\n");
    printf("%*s  GenStats: ", ind, "");
    PrintPlainLine((const char*)it->GenStats);
    printf("\n");

    if (it->isQItem()) {
        QItem *q = (QItem*)it;
        TextVal *qt = it->isArmour() ? AQ_CONSTNAMES : WQ_CONSTNAMES;
        printf("%*s  Qualities:", ind, "");
        int any = 0;
        for (int k = 0; k != 8; k++)
            if (q->Qualities[k]) {
                printf(" [%d]=%s", k, ConstNm(qt, q->Qualities[k]).c_str());
                any++;
            }
        if (!any)
            printf(" (none)");
        printf(" Known=0x%x\n", (unsigned)q->KnownQualities);
    }
    if (it->isWeapon())
        printf("%*s  Bane: %s\n", ind, "",
            ConstNm(MA_CONSTNAMES, ((Weapon*)it)->Bane).c_str());
    if (it->Type == T_FOOD || it->Type == T_CORPSE)
        printf("%*s  Eaten: %d\n", ind, "", (int)((Food*)it)->Eaten);
    if (it->Type == T_CORPSE) {
        Corpse *c = (Corpse*)it;
        printf("%*s  Corpse: mID=%s TurnCreated=%u LastDiseaseDCCheck=%d\n",
            ind, "", CNm(c->mID).c_str(), (unsigned)c->TurnCreated,
            (int)c->LastDiseaseDCCheck);
    }
    Stati(it, ind + 2);

    if (it->isContainer()) {
        Container *c = (Container*)it;
        int shown = 0;
        for (Thing *t = oThing(c->Contents); t; t = oThing(t->Next))
            if (t->isItem()) {
                Item_((Item*)t, ind + 4);
                shown++;
            }
        if (!shown)
            printf("%*s  (empty)\n", ind + 2, "");
    }
}

/* Position of `want` in the carried list, or -1. A handle cannot print, and
   two identical daggers differ only by where they sit. */
int CanonDump::InvOrdinal(Player *p, Item *want) {
    int n = 0;
    if (!want)
        return -1;
    for (Item *it = p->FirstInv(); it; it = p->NextInv(), n++)
        if (it == want)
            return n;
    return -1;
}

bool CanonDump::Run(Player *p, Map *m) {
    int i, j, c;
    std::vector<std::string> v;
    char b[1024];
    printf("=== Canonical character dump ===\n");

    printf("=== Identity ===\n");
    printf("Name: ");
    PrintPlainLine((const char*)p->Named);
    printf("\n");
    printf("Type: %s\n", ConstNm(T_CONSTNAMES, p->Type).c_str());
    printf("mID: %s\n", CNm(p->mID).c_str());
    printf("tmID: %s\n", CNm(p->tmID).c_str());
    printf("Race: %s\n", CNm(p->RaceID).c_str());
    printf("God: %s\n", CNm(p->GodID).c_str());
    for (i = 0; i != 6; i++)
        printf("Class[%d]: %s\n", i, CNm(p->ClassID[i]).c_str());
    for (i = 0; i != 3; i++)
        printf("Level[%d]: %d\n", i, (int)p->Level[i]);
    printf("XP: %u  XP_Drained: %u  xpTicks: %d  NotifiedLevel: %d\n",
        (unsigned)p->XP, (unsigned)p->XP_Drained, (int)p->xpTicks,
        (int)p->NotifiedLevel);
    printf("PartyID: %d\n", (int)p->PartyID);
    {
        Creature *mt = oCreature(p->Mount);
        printf("Mount: %s\n", mt ? CNm(mt->mID).c_str() : "-");
    }
    printf("\n");

    printf("=== Level Rolls (hit points and mana, per class and level) ===\n");
    for (c = 0; c != 3; c++) {
        printf("HitRolls[%d:%s]:", c, CNm(p->ClassID[c]).c_str());
        for (j = 0; j != MAX_CHAR_LEVEL; j++)
            printf(" %d", (int)p->hpRolls[c][j]);
        printf("\n");
        printf("ManaRolls[%d:%s]:", c, CNm(p->ClassID[c]).c_str());
        for (j = 0; j != MAX_CHAR_LEVEL; j++)
            printf(" %d", (int)p->manaRolls[c][j]);
        printf("\n");
    }
    printf("\n");

    printf("=== Skill Ranks (per skill, and the skill-point pool per class) ===\n");
    for (i = 0; i != SK_LASTSKILL; i++)
        if (p->SkillRanks[i])
            printf("Skill %s: %d\n", ConstNm(SK_CONSTNAMES, i).c_str(),
                (int)p->SkillRanks[i]);
    for (c = 0; c != 6; c++)
        printf("SkillPool[%d:%s]: spent=%d bonus=%d total=%d\n", c,
            CNm(p->ClassID[c]).c_str(), (int)p->SpentSP[c],
            (int)p->BonusSP[c], (int)p->TotalSP[c]);
    for (i = 0; i != STUDY_LAST; i++)
        if (p->IntStudy[i])
            printf("IntStudy %s: %d\n", ConstNm(StudyNames, i).c_str(),
                (int)p->IntStudy[i]);
    printf("\n");

    printf("=== Perk Block (the creation record a save keeps) ===\n");
    printf("statMethod: %d\n", (int)p->statMethod);
    printf("rerollCount: %d\n", (int)p->rerollCount);
    printf("rerolledPerks: %d\n", (int)p->rerolledPerks);
    printf("formulaSeed: %d\n", (int)p->formulaSeed);
    printf("storeSeed: %d\n", (int)p->storeSeed);
    printf("deathCount: %d\n", (int)p->deathCount);
    printf("Personality: 0x%x\n", (unsigned)p->Personality);
    printf("Proficiencies: 0x%x\n", (unsigned)p->Proficiencies);
    printf("\n");

    printf("=== Feats ===\n");
    {
        static bool named[FT_LAST + 1];
        memset(named, 0, sizeof(named));
        v.clear();
        for (j = 0; FeatInfo[j].feat; j++) {
            int ft = FeatInfo[j].feat;
            if (ft < 0 || ft > FT_LAST)
                continue;
            named[ft] = true;
            if (p->Feats[ft / 8] & (1 << (ft % 8)))
                v.push_back(std::string("Feat ") + FeatInfo[j].name);
        }
        for (int ft = 0; ft <= FT_LAST; ft++)
            if (!named[ft] && (p->Feats[ft / 8] & (1 << (ft % 8)))) {
                /* Bits below FT_FIRST are skill numbers: the engine keeps a
                   per-skill flag in the same array. */
                if (ft < FT_FIRST)
                    snprintf(b, sizeof(b), "SkillFlag %s",
                        ConstNm(SK_CONSTNAMES, ft).c_str());
                else
                    snprintf(b, sizeof(b), "Feat (unnamed bit %d)", ft);
                v.push_back(b);
            }
        PrintSorted(v);
    }
    printf("\n");

    printf("=== Abilities ===\n");
    for (i = 0; i != CA_LAST; i++)
        if (p->Abilities[i])
            printf("Ability %s: %d\n", ConstNm(CA_CONSTNAMES, i).c_str(),
                (int)p->Abilities[i]);
    for (i = 0; i != 4; i++)
        if (p->TurnTypes[i] || p->TurnLevels[i])
            printf("Turn[%d]: type=%s level=%d\n", i,
                ConstNm(MA_CONSTNAMES, p->TurnTypes[i]).c_str(),
                (int)p->TurnLevels[i]);
    for (i = 0; i != 12; i++)
        if (p->FavTypes[i] || p->FavLevels[i])
            printf("FavoredEnemy[%d]: type=%s level=%d\n", i,
                ConstNm(MA_CONSTNAMES, p->FavTypes[i]).c_str(),
                (int)p->FavLevels[i]);
    printf("FocusWCount: %d  FocusSCount: %d  ExoticCount: %d\n",
        (int)p->FocusWCount, (int)p->FocusSCount, (int)p->ExoticCount);
    printf("aStoryPluses: %d  tStoryPluses: %d  RageCount: %d\n",
        (int)p->aStoryPluses, (int)p->tStoryPluses, (int)p->RageCount);
    printf("\n");

    printf("=== Attributes ===\n");
    for (i = 0; i != 7; i++)
        printf("BaseAttr %s: %d\n", ConstNm(ATTR_CONSTNAMES, i).c_str(),
            (int)p->BAttr[i]);
    for (i = 0; i != ATTR_LAST; i++)
        printf("KnownAttr %s: %d\n", ConstNm(ATTR_CONSTNAMES, i).c_str(),
            (int)p->KAttr[i]);
    for (i = 0; i != ATTR_LAST; i++)
        printf("Attr %s: %d\n", ConstNm(ATTR_CONSTNAMES, i).c_str(),
            (int)p->Attr[i]);
    printf("TouchDef: %d\n", (int)p->TouchDef);
    for (i = 0; i != 7; i++)
        for (j = 0; j != 15; j++)
            if (p->GainAttr[i][j])
                printf("GainAttr %s[%d]: %d\n",
                    ConstNm(ATTR_CONSTNAMES, i).c_str(), j,
                    (int)p->GainAttr[i][j]);
    for (i = 0; i != 16; i++)
        if (p->SaveBonus[i])
            printf("SaveBonus[%d]: %d\n", i, (int)p->SaveBonus[i]);
    printf("\n");

    printf("=== Creature State ===\n");
    printf("HP: %d / %d  Subdual: %d  cFP: %d\n", (int)p->cHP, (int)p->mHP,
        (int)p->Subdual, (int)p->cFP);
    printf("Mana: spent=%d max=%d held=%d pulse=%d\n", (int)p->uMana,
        (int)p->mMana, (int)p->hMana, (int)p->ManaPulse);
    printf("concentUsed: %d  LastMoveDir: %d  AoO: %d  FFCount: %d  "
           "HideVal: %d  AttrDeath: %d\n", (int)p->concentUsed,
        (int)p->LastMoveDir, (int)p->AoO, (int)p->FFCount, (int)p->HideVal,
        (int)p->AttrDeath);
    printf("StateFlags: 0x%x\n", (unsigned)p->StateFlags);
    printf("Ranges: tremor=%u sight=%u light=%u blind=%u infra=%u percep=%u "
           "telep=%u scent=%u shadow=%u nature=%u\n",
        (unsigned)p->TremorRange, (unsigned)p->SightRange,
        (unsigned)p->LightRange, (unsigned)p->BlindRange,
        (unsigned)p->InfraRange, (unsigned)p->PercepRange,
        (unsigned)p->TelepRange, (unsigned)p->ScentRange,
        (unsigned)p->ShadowRange, (unsigned)p->NatureSight);
    printf("Targets: count=%u retarget=%d\n", (unsigned)p->ts.tCount,
        (int)p->ts.shouldRetarget);
    for (i = 0; i < (int)p->ts.tCount && i < NUM_TARGETS; i++)
        printf("Target[%d]: type=%d priority=%u vis=%u\n", i,
            (int)p->ts.t[i].type, (unsigned)p->ts.t[i].priority,
            (unsigned)p->ts.t[i].vis);
    printf("Thing: Image=0x%x Timeout=%d StoredMoveTimeout=%d Flags=0x%x\n",
        (unsigned)p->Image, (int)p->Timeout, (int)p->StoredMovementTimeout,
        (unsigned)p->Flags);
    printf("Alignment: GE=%d LC=%d desired=0x%x  polyTicks=%d LastRest=%d "
           "fracFatigue=%d fallenPaladin=%d resChance=%d\n",
        (int)p->alignGE, (int)p->alignLC, (unsigned)p->desiredAlign,
        (int)p->polyTicks, (int)p->LastRest, (int)p->fracFatigue,
        (int)p->isFallenPaladin, (int)p->resChance);
    printf("\n");

    printf("=== Player Stati ===\n");
    Stati(p, 0);
    printf("\n");

    printf("=== Equipped Slots (Inv# is the kit ordinal below) ===\n");
    {
        int shown = 0;
        for (int8 slot = 0; slot < NUM_SLOTS; slot++) {
            Item *it = p->InSlot(slot);
            if (!it)
                continue;
            printf("  %s: Inv#%d iID=%s eID=%s\n", SlotNames[slot],
                InvOrdinal(p, it), CNm(it->iID).c_str(),
                CNm(it->eID).c_str());
            shown++;
        }
        if (!shown)
            printf("  (nothing equipped)\n");
    }
    printf("\n");

    printf("=== Weapon Sets ===\n");
    {
        static const char *const label[8] = { "M main", "M off-hand",
            "R main", "ammo", "X main", "X off-hand", "S main", "S off-hand" };
        for (int k = 0; k != 8; k++) {
            Item *it = oItem(p->DefaultItem(k));
            if (it)
                printf("  %s: Inv#%d iID=%s\n", label[k],
                    InvOrdinal(p, it), CNm(it->iID).c_str());
            else
                printf("  %s: (none)\n", label[k]);
        }
    }
    printf("\n");

    printf("=== Kit (every carried item, recursive into containers) ===\n");
    {
        int n = 0;
        for (Item *it = p->FirstInv(); it; it = p->NextInv()) {
            printf("Inv#%d\n", n++);
            Item_(it, 2);
        }
        if (!n)
            printf("  (empty)\n");
    }
    printf("\n");

    printf("=== Spells ===\n");
    v.clear();
    for (i = 0; i != MAX_SPELLS + 1; i++)
        if (p->Spells[i]) {
            snprintf(b, sizeof(b), "Spell %s: flags=0x%x",
                SpellNm(i).c_str(), (unsigned)p->Spells[i]);
            v.push_back(b);
        }
    PrintSorted(v);
    v.clear();
    for (i = 0; i != MAX_SPELLS; i++)
        if (p->MMArray[i]) {
            snprintf(b, sizeof(b), "MetaMagic %s: 0x%x", SpellNm(i).c_str(),
                (unsigned)p->MMArray[i]);
            v.push_back(b);
        }
    PrintSorted(v);
    for (i = 0; i != 10; i++)
        if (p->SpellsLearned[i] || p->SpellSlots[i] || p->BonusSlots[i])
            printf("SpellLevel[%d]: learned=%d slots=%d bonus=%d\n", i,
                (int)p->SpellsLearned[i], (int)p->SpellSlots[i],
                (int)p->BonusSlots[i]);
    for (i = 0; i != 10; i++)
        if (p->RecentSpells[i])
            printf("RecentSpell[%d]: %s\n", i,
                SpellNm(p->RecentSpells[i]).c_str());
    for (i = 0; i != 5; i++)
        if (p->RecentSkills[i])
            printf("RecentSkill[%d]: %s\n", i,
                ConstNm(SK_CONSTNAMES, p->RecentSkills[i]).c_str());
    for (i = 0; i != 5; i++)
        if (p->RecentItems[i])
            printf("RecentItem[%d]: %u\n", i, (unsigned)p->RecentItems[i]);
    for (i = 0; i != 10; i++)
        if (p->Tattoos[i])
            printf("Tattoo[%d]: %s\n", i, CNm(p->Tattoos[i]).c_str());
    for (i = 0; i != 12; i++)
        if (p->SpellKeys[i] >= 0)       /* -1 is the empty key */
            printf("SpellKey[%d]: %s\n", i, SpellNm(p->SpellKeys[i]).c_str());
    printf("AutoBuffs:");
    for (i = 0; i != 64 && p->AutoBuffs[i]; i++)
        printf(" %s", SpellNm(p->AutoBuffs[i]).c_str());
    printf("\n");
    printf("\n");

    printf("=== Religion ===\n");
    v.clear();
    for (i = 0; i != MAX_GODS; i++) {
        bool any = p->FavourLev[i] || p->TempFavour[i] || p->Anger[i] ||
                   p->FavPenalty[i] || p->PrayerTimeout[i] ||
                   p->AngerThisTurn[i] || p->lastPulse[i] || p->godFlags[i];
        for (j = 0; j != MAX_SAC_CATS + 2; j++)
            if (p->SacVals[i][j])
                any = true;
        if (!any)
            continue;
        std::string gn;
        if (i < (int)theGame->LastGod())
            gn = CNm(theGame->GodID((uint16)i));
        else {
            snprintf(b, sizeof(b), "(no god %d)", i);
            gn = b;
        }
        std::string sv;
        for (j = 0; j != MAX_SAC_CATS + 2; j++) {
            snprintf(b, sizeof(b), "%s%d", j ? "," : "", (int)p->SacVals[i][j]);
            sv += b;
        }
        snprintf(b, sizeof(b), "God %s: FavourLev=%d TempFavour=%d Anger=%d "
                 "FavPenalty=%d PrayerTimeout=%d AngerThisTurn=%d "
                 "lastPulse=%d godFlags=0x%x SacVals=%s", gn.c_str(),
            (int)p->FavourLev[i], (int)p->TempFavour[i], (int)p->Anger[i],
            (int)p->FavPenalty[i], (int)p->PrayerTimeout[i],
            (int)p->AngerThisTurn[i], (int)p->lastPulse[i],
            (unsigned)p->godFlags[i], sv.c_str());
        v.push_back(b);
    }
    PrintSorted(v);
    printf("\n");

    printf("=== Player State ===\n");
    printf("MapMemoryMask: %d  GallerySlot: %d  MapSP: %d  HungerShown: %d\n",
        (int)p->MapMemoryMask, (int)p->GallerySlot, (int)p->MapSP,
        (int)p->HungerShown);
    printf("Flags: statiChanged=%d shownFF=%d Victory=%d Quit=%d UpdateMap=%d "
           "Dig=%d Wizard=%d Explore=%d\n", (int)p->statiChanged,
        (int)p->shownFF, (int)p->VictoryFlag, (int)p->QuitFlag,
        (int)p->UpdateMap, (int)p->DigMode, (int)p->WizardMode,
        (int)p->ExploreMode);
    v.clear();
    for (i = 0; i != MAX_DUNGEONS; i++)
        if (p->MaxDepths[i]) {
            std::string dn;
            if (i < (int)Game::Modules[0]->szDgn)
                dn = CNm(Game::Modules[0]->DungeonID((uint16)i));
            else {
                snprintf(b, sizeof(b), "(no dungeon %d)", i);
                dn = b;
            }
            snprintf(b, sizeof(b), "MaxDepth %s: %d", dn.c_str(),
                (int)p->MaxDepths[i]);
            v.push_back(b);
        }
    PrintSorted(v);
    for (i = 0; i != MAX_MACROS; i++)
        if (p->Macros[i])
            printf("Macro[%d]: %s\n", i, CNm(p->Macros[i]).c_str());
    for (i = 0; i != MAX_QKEYS; i++) {
        QuickKey &qk = p->QuickKeys[i];
        if (!qk.Value && !qk.Type && !qk.hItem && !qk.MM)
            continue;
        Item *qi = oItem(qk.hItem);
        std::string what;
        if (qk.Type == QKY_SPELL) {
            what = SpellNm(SpellVersionSpell((int32)qk.Value));
            snprintf(b, sizeof(b), " src=%d", (int)SpellVersionSrcCode((int32)qk.Value));
            what += b;
        } else {
            snprintf(b, sizeof(b), "0x%x", (unsigned)qk.Value);
            what = b;
        }
        printf("QuickKey[%d]: Type=%d Value=%s MM=0x%x item=%s\n", i,
            (int)qk.Type, what.c_str(), (unsigned)qk.MM,
            qi ? CNm(qi->iID).c_str() : (qk.hItem ? "(dead handle)" : "-"));
    }
    for (i = 0; i != 5; i++)
        if (p->RecentVerbs[i] != -1)
            printf("RecentVerb[%d]: %d\n", i, (int)p->RecentVerbs[i]);
    printf("Options:");
    for (i = 0; i != OPT_LAST; i++)
        if (p->Options[i])
            printf(" %d=%d", i, (int)p->Options[i]);
    printf("\n");
    printf("\n");

    printf("=== Journal and Time ===\n");
    printf("Journal: ");
    PrintPlainLine((const char*)p->Journal);
    printf("\n");
    printf("GraveText: ");
    PrintPlainLine((const char*)p->GraveText);
    printf("\n");
    for (i = 0; i != 8; i++) {
        printf("MessageQueue[%d]: ", i);
        PrintPlainLine((const char*)p->MessageQueue[i]);
        printf("\n");
    }
    printf("JournalInfo: bestItem=");
    PrintPlainLine((const char*)p->JournalInfo.bestItem);
    printf(" (%d) bestMonster=", (int)p->JournalInfo.bestItemVal);
    PrintPlainLine((const char*)p->JournalInfo.bestMonster);
    printf(" (%d) numMonSeen=%d\n", (int)p->JournalInfo.bestMonsterVal,
        (int)p->JournalInfo.numMonSeen);
    for (i = 0; i != MA_LAST_REAL; i++)
        if (p->JournalInfo.numMonOfType[i])
            printf("MonOfType %s: %d\n", ConstNm(MA_CONSTNAMES, i).c_str(),
                (int)p->JournalInfo.numMonOfType[i]);
    /* LTI.seconds and start_second are wall-clock time: they differ between a
       character and its rebuild, so they do not print. */
    for (i = 0; i != 11; i++) {
        LevelTimeInfo &l = p->GameTimeInfo.LTI[i];
        if (l.turns || l.actions || l.keystrokes || l.xp)
            printf("LevelTime[%d]: turns=%u actions=%u keystrokes=%u xp=%d\n",
                i, (unsigned)l.turns, (unsigned)l.actions,
                (unsigned)l.keystrokes, (int)l.xp);
    }
    printf("GameTime: start_turn=%u actions=%u keystrokes=%u start_xp=%d\n",
        (unsigned)p->GameTimeInfo.start_turn,
        (unsigned)p->GameTimeInfo.actions,
        (unsigned)p->GameTimeInfo.keystrokes,
        (int)p->GameTimeInfo.start_xp);
    printf("\n");

    printf("=== Location ===\n");
    printf("Position: (%d,%d)\n", (int)p->x, (int)p->y);
    if (m)
        printf("Map: dID=%s depth=%d\n", CNm((rID)m->dID).c_str(),
            (int)m->Depth);
    printf("\n");

    printf("=== Effect Memory (flavours and Known/Tried) ===\n");
    v.clear();
    EffectMemoryLines(p, v);
    PrintSorted(v);
    if (v.empty())
        printf("  (no effect memory)\n");
    printf("\n");

    printf("=== Script Variables ===\n");
    if (!PrintScriptVariables(true, true))
        return false;
    printf("\n");

    printf("=== Monster Memory (Seen/Fought/Kills) ===\n");
    v.clear();
    MonsterMemoryLines(p, v);
    PrintSorted(v);
    if (v.empty())
        printf("  (no monster memory)\n");
    printf("\n");

    printf("=== Derived Sheet ===\n");
    {
        String cd;
        T1->CreateCharDump(cd);
        PrintPlain(cd);
    }
    printf("\n=== end of canonical dump ===\n");
    return true;
}

bool RunSaveDump(const char *path) {
    fileHeader fhdr;
    if (!LoadSaveForReport(path, fhdr)) return false;

    InitGodArrays();

    Player *p = oPlayer(theGame->p[0]);
    Map *m = oMap(theGame->m[0]);
    T1->SetPlayer(p);
    T1->SetMap(m);

    /* Canonical mode: a separate walk, so the default report below stays
       byte for byte what 26 tools and key scripts parse. */
    {
        const char *canon = getenv("INCURSION_DUMP_CANONICAL");
        if (canon && *canon && strcmp(canon, "0")) {
            return CanonDump::Run(p, m);
        }
    }

    /* ---------------------------------------------------------- report -- */

    printf("=== Incursion save dump ===\n");
    printf("File:      %s\n", path);
    /* Bounded print: Version is char[12] straight off the file with no NUL
       guarantee (same reasoning as LoadGroupV1's revision check). */
    printf("Format:    %.12s\n", fhdr.Version);
    printf("Name:      %s\n", (const char*)p->Named);
    printf("HP:        %d / %d", p->cHP, p->mHP);
    if (p->Subdual)
        printf("  (Subdual %d)", p->Subdual);
    printf("\n");
    /* The status line prints cMana()/tMana() and so hides WHY mana is
       missing. uMana is mana spent, and it regenerates. hMana is mana held,
       and only rest returns it (src/Player.cpp:2186-2188). A mana potion
       refills the spent half alone (src/Effects.cpp:2266-2271), so this split
       is the first thing to read when a potion appears to do nothing. */
    printf("Mana:      %d / %d  (spent %d, held %d)\n",
        (int)p->cMana(), (int)p->tMana(), (int)p->uMana, (int)p->hMana);
    printf("Position:  (%d,%d)", p->x, p->y);
    if (m) {
        printf(" on ");
        PrintPlain(m->Name());
        printf(" (dID=%d), depth %d\n", m->dID, m->Depth);
    } else
        printf(" -- no map!\n");
    printf("\n");

    printf("=== Equipped Slots ===\n");
    {
        int shown = 0;
        for (int8 slot = 0; slot < NUM_SLOTS; slot++) {
            Item *it = p->InSlot(slot);
            if (!it)
                continue;
            printf("  %s: ", SlotNames[slot]);
            PrintPlain(it->Name(NA_LONG | NA_MECH | NA_INSC));
            printf("  [Type=%d iID=%d]\n", it->Type, it->iID);
            shown++;
        }
        if (!shown)
            printf("  (nothing equipped)\n");
    }
    printf("\n");

    printf("=== Weapon Sets ===\n");
    {
        static const char *const label[8] = { "M main", "M off-hand",
            "R main", "ammo", "X main", "X off-hand", "S main", "S off-hand" };
        for (int k = 0; k != 8; k++) {
            Item *it = oItem(p->DefaultItem(k));
            printf("  %s: ", label[k]);
            if (it)
                PrintPlain(it->Name(NA_LONG));
            else
                printf("(none)");
            printf("\n");
        }
    }
    printf("\n");

    printf("=== Player Stati ===\n");
    DumpStati(p);
    printf("\n");

    printf("=== Inventory (recursive into containers) ===\n");
    {
        int shown = 0;
        for (Item *it = p->FirstInv(); it; it = p->NextInv()) {
            DumpItem(it, 2);
            shown++;
        }
        if (!shown)
            printf("  (empty)\n");
    }
    printf("\n");

    /* What is at the player's own feet, with the same raw fields as the
       carried inventory above. This is not the same walk as the "On The
       Ground:" list inside CreateCharDump below -- that one only prints a
       readable name (src/Sheet.cpp:1345-1350) -- and it is the one that
       actually answers inc-52b: the corpse a rejected sacrifice leaves
       behind (Character::Sacrifice's Uninterested path, src/Prayer.cpp:
       392-395) lands here, on the ground, not in the pack. */
    printf("=== On The Ground (at player position, recursive) ===\n");
    if (m->InBounds(p->x, p->y)) {
        int shown = 0;
        for (Thing *t = oThing(m->At(p->x, p->y).Contents); t; t = oThing(t->Next))
            if (t->isItem()) {
                DumpItem((Item*)t, 2);
                shown++;
            }
        if (!shown)
            printf("  (nothing here)\n");
    } else
        printf("  (player position is out of map bounds)\n");
    printf("\n");

    /* Per-player resource memory for every Effect: the flavour appearance(s)
       the game rolled at NewGame (Game::SetFlavors, src/Item.cpp) and the
       Known/Tried identification flags, straight from EffMem through the
       real EFFMEM accessor. This is the lens tools/check_flavor_stability.sh
       compares across a module rebuild: these lines must be IDENTICAL when
       the same save is read against a module with one Effect added, because
       the memory rows are keyed by their position in the Effect array and
       the flavour rIDs convert through the save's own module manifest
       (docs/SAVE-SCHEMA-SPEC.md, "The resource memory segment"). Effects
       whose whole row is zero are omitted: a save carries no row for them
       and a new game gives them zeroed memory. */
    printf("=== Effect Memory (flavours and Known/Tried) ===\n");
    {
        std::vector<std::string> lines;
        EffectMemoryLines(p, lines);
        for (size_t li = 0; li != lines.size(); li++)
            printf("%s\n", lines[li].c_str());
        if (lines.empty())
            printf("  (no effect memory)\n");
    }
    printf("\n");

    printf("=== Script Variables ===\n");
    if (!PrintScriptVariables(true)) return false;
    printf("\n");

    /* Per-player resource memory for every Monster, in the same shape and for
       the same reason as the Effect block above: straight from MonMem through
       the real MONMEM accessor, so the report cannot drift from what the
       engine thinks. Seen, Fought and Kills are the three fields gameplay
       writes (bd inc-q98a); the other eight are still always zero and are
       printed so that the day one of them gains a writer, this says so.
       Kinds whose whole row is zero are omitted, exactly as above: a save
       carries no row for a kind the player has never met. */
    printf("=== Monster Memory (Seen/Fought/Kills) ===\n");
    {
        std::vector<std::string> lines;
        MonsterMemoryLines(p, lines);
        for (size_t li = 0; li != lines.size(); li++)
            printf("%s\n", lines[li].c_str());
        if (lines.empty())
            printf("  (no monster memory)\n");
    }
    printf("\n");

    /* Temporary diagnostic (inc-otz): report every portal on the player's map,
       the solidity of its own square and of the eight around it, and whether
       the player can walk to it at all.

       Brian reported a staircase that looks like it sits inside a wall and
       that he cannot enter from the square directly south of it. Three
       explanations fitted that description and only a reading of the map
       separates them: the stair square is solid; the stair square is walkable
       but no open path reaches it; or the stair glyph is drawn on a square
       that is really rock. Delete with inc-otz. */
    printf("=== Map Portals ===\n");
    if (!m)
        printf("  (no map)\n");
    else {
        int16 sx = m->SizeX(), sy = m->SizeY();
        int32 cells = (int32)sx * (int32)sy;

        /* Reachability from the player, over squares that Map::SolidAt calls
           open. SolidAt (src/MakeLev.cpp:3971) is the same test MoveDepth uses
           to reject an arrival square: it counts solid terrain and any feature
           flagged F_SOLID or F_XSOLID. A closed door is NOT solid by that test,
           so this walk passes through doors the player would first have to
           open. It therefore OVERSTATES reachability, which is the safe
           direction here: a portal this walk cannot reach is unreachable by
           any route the player has. */
        int16 *dist = new int16[cells];
        int32 *queue = new int32[cells];
        int32 qh = 0, qt = 0, k;
        for (k = 0; k < cells; k++)
            dist[k] = -1;
        if (m->InBounds(p->x, p->y) && !m->SolidAt(p->x, p->y)) {
            dist[(int32)p->y * sx + p->x] = 0;
            queue[qt++] = (int32)p->y * sx + p->x;
        }
        while (qh < qt) {
            int32 cur = queue[qh++];
            int16 cx = (int16)(cur % sx), cy = (int16)(cur / sx);
            for (int16 d = 0; d != 8; d++) {
                int16 ax = cx + DirX[d], ay = cy + DirY[d];
                if (!m->InBounds(ax, ay))
                    continue;
                int32 ai = (int32)ay * sx + ax;
                if (dist[ai] != -1)
                    continue;
                if (m->SolidAt(ax, ay))
                    continue;
                dist[ai] = (int16)(dist[cur] + 1);
                queue[qt++] = ai;
            }
        }

        int32 open = 0;
        for (k = 0; k < cells; k++) {
            int16 cx = (int16)(k % sx), cy = (int16)(k / sx);
            if (m->InBounds(cx, cy) && !m->SolidAt(cx, cy))
                open++;
        }

        /* Second reachability walk: the gate Player::RunTo actually applies.
           The walk above counts a square open when Map::SolidAt calls it open.
           RunTo demands more of every step -- the square must be remembered,
           hold no perceived hostile, and lie behind no impassable door -- and
           it never relaxes those three, however dangerous a route it accepts
           (only traps and hazardous terrain relax, at its second and third
           tries). So this walk scores each step with the real Map::RunOver at
           RunTo's most permissive tier, DF_IGNORE_TRAPS|DF_IGNORE_TERRAIN.
           That tier is a superset of the other two, so a portal it cannot
           reach is one 'R' refuses outright with "no clear, safe and explored
           route", and the cut list further down names the squares where the
           gate says no. This is the instrument for the bug where a staircase
           the player has walked to, and can see a clear path to on the
           overview map, still will not auto-travel: the overview draws
           remembered terrain but not the creature or shut door on the route.
           inc-otz. */
        bool Incor = p->HasMFlag(M_INCOR) || p->HasStati(PHASED);
        bool Meld  = p->HasAbility(CA_EARTHMELD);
        const int32 GATE_TIER = DF_IGNORE_TRAPS | DF_IGNORE_TERRAIN;
        int16 *gdist  = new int16[cells];
        int32 *gqueue = new int32[cells];
        int32 gqh = 0, gqt = 0;
        for (k = 0; k < cells; k++)
            gdist[k] = -1;
        /* Seed the player's own square unconditionally, exactly as
           Map::ShortestPath does -- it never gates the start square. */
        if (m->InBounds(p->x, p->y)) {
            gdist[(int32)p->y * sx + p->x] = 0;
            gqueue[gqt++] = (int32)p->y * sx + p->x;
        }
        while (gqh < gqt) {
            int32 gcur = gqueue[gqh++];
            int16 gx = (int16)(gcur % sx), gy = (int16)(gcur / sx);
            for (int16 gd = 0; gd != 8; gd++) {
                int16 nx = gx + DirX[gd], ny = gy + DirY[gd];
                if (!m->InBounds(nx, ny))
                    continue;
                int32 ni = (int32)ny * sx + nx;
                if (gdist[ni] != -1)
                    continue;
                if (!m->RunOver((uint8)(nx & 0xFF), (uint8)(ny & 0xFF), true, p,
                                GATE_TIER, Incor, Meld))
                    continue;
                gdist[ni] = (int16)(gdist[gcur] + 1);
                gqueue[gqt++] = ni;
            }
        }
        int32 gopen = 0;
        for (k = 0; k < cells; k++)
            if (gdist[k] >= 0)
                gopen++;
        printf("  Map %dx%d, depth %d. Open squares %d, reachable from the "
               "player %d.\n", (int)sx, (int)sy, (int)m->Depth,
               (int)open, (int)qt);
        printf("  Player at (%d,%d).\n", (int)p->x, (int)p->y);
        printf("  Under RunTo's gate (square remembered, no perceived hostile, "
               "no impassable door; traps and terrain ignored): %d of those "
               "%d reachable squares stay reachable.\n\n",
               (int)gopen, (int)qt);

        Thing *t; int32 i;
        int found = 0;
        MapIterate(m, t, i)
            if (t->Type == T_PORTAL) {
                Portal *po = (Portal*)t;
                int16 px = t->x, py = t->y;
                found++;
                printf("  Portal %d: \"%s\" at (%d,%d)%s\n", found,
                    NAME(po->fID), (int)px, (int)py,
                    po->isDownStairs() ? "  [down stairs]" : "");
                if (!m->InBounds(px, py)) {
                    printf("    OUT OF BOUNDS.\n\n");
                    continue;
                }
                printf("    terrain      : \"%s\"\n", NAME(m->TerrainAt(px, py)));
                printf("    At().Solid   : %s\n", m->At(px, py).Solid ? "TRUE" : "false");
                printf("    SolidAt()    : %s\n", m->SolidAt(px, py) ? "TRUE" : "false");
                printf("    isVault      : %s\n", m->At(px, py).isVault ? "TRUE" : "false");
                printf("    portal Flags : 0x%lx%s\n", (unsigned long)t->Flags,
                    (t->Flags & (F_SOLID | F_XSOLID)) ? "  [F_SOLID or F_XSOLID]" : "");

                /* The 3x3 around the portal. '#' is SolidAt, '.' is open,
                   '@' is the player, 'P' is the portal itself. */
                printf("    neighbourhood ('#' solid, '.' open, '@' player):\n");
                for (int16 ny2 = py - 1; ny2 <= py + 1; ny2++) {
                    printf("      ");
                    for (int16 nx2 = px - 1; nx2 <= px + 1; nx2++) {
                        char ch;
                        if (!m->InBounds(nx2, ny2))
                            ch = '?';
                        else if (nx2 == p->x && ny2 == p->y)
                            ch = '@';
                        else if (nx2 == px && ny2 == py)
                            ch = 'P';
                        else
                            ch = m->SolidAt(nx2, ny2) ? '#' : '.';
                        putchar(ch);
                    }
                    printf("\n");
                }

                int32 pi = (int32)py * sx + px;
                if (dist[pi] >= 0)
                    printf("    reachable    : yes, %d steps from the player\n",
                        (int)dist[pi]);
                else
                    printf("    reachable    : NO -- no open path from the player\n");
                int32 gpi = (int32)py * sx + px;
                if (gdist[gpi] >= 0)
                    printf("    RunTo gate   : reachable, %d steps -- 'R' can "
                        "auto-travel here\n", (int)gdist[gpi]);
                else {
                    printf("    RunTo gate   : BLOCKED -- 'R' refuses this "
                        "portal (see the cut list below)\n");
                    printf("    RunTo reason : %s\n",
                        RtfName(m->RunToFailReason(p, px, py)));
                }
                printf("\n");
            }
        if (!found)
            printf("  (no portals on this map)\n");

        /* Where RunTo's gate seals off ground the player can physically reach:
           squares the first walk reached, that the gate walk did not, that
           border the gate-reachable region. The creature or shut door that
           traps the player sits on one of these. A physically-reached square
           is open (SolidAt false), so the reason is never "solid" here. */
        int cutshown = 0, cuttotal = 0;
        for (k = 0; k < cells; k++) {
            if (dist[k] < 0 || gdist[k] >= 0)
                continue;
            int16 cx = (int16)(k % sx), cy = (int16)(k / sx);
            bool border = false;
            for (int16 d = 0; d != 8 && !border; d++) {
                int16 ax = cx + DirX[d], ay = cy + DirY[d];
                if (m->InBounds(ax, ay) && gdist[(int32)ay * sx + ax] >= 0)
                    border = true;
            }
            if (!border)
                continue;
            cuttotal++;
            if (cutshown == 0)
                printf("\n  RunTo cut -- walkable squares the gate rejects, on "
                       "the border of where 'R' can still reach:\n");
            if (cutshown < 40) {
                String why = GateBlockReason(m, p, cx, cy);
                printf("    (%d,%d): %s\n", (int)cx, (int)cy,
                       (const char *)why);
                cutshown++;
            }
        }
        if (cuttotal > cutshown)
            printf("    ... and %d more.\n", cuttotal - cutshown);
        if (!cuttotal)
            printf("\n  RunTo cut: none -- the gate reaches every square the "
                   "player can physically walk to.\n");

        delete [] dist;
        delete [] queue;
        delete [] gdist;
        delete [] gqueue;
    }
    printf("\n");

    printf("=== Full Character Sheet ===\n");
    printf("(the engine's own dump: attributes, saves, combat stats, feats, "
           "skills, resistances, specials, known spells, top-level "
           "inventory, journal, monsters encountered, level stats, message "
           "history -- see TextTerm::CreateCharDump, src/Sheet.cpp:1287)\n");
    {
        String cd;
        T1->CreateCharDump(cd);
        PrintPlain(cd);
    }
    printf("\n=== end of dump ===\n");

    return true;
}
