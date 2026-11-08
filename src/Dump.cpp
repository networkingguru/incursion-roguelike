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

static bool PrintScriptVariables(bool values)
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


/* INCURSION_PLANT=<spec> INCURSION_PLANT_OUT=<new save> with -dump: the real reader loads the save, each spec line
   is applied through the game's own calls, the real writer writes a NEW file. Names are symbolic only; a number,
   an unknown name or a refused call exits 2 naming the line. Spec language: tools/pressure/plant.sh header. */
extern const char *V1FamName(const char *fam, long value);
extern bool V1FamValue(const char *fam, const char *name, long &value);

static bool PlantNumber(const char *t, long &v) {
    char *e = NULL;
    v = strtol(t, &e, 10);
    return e && *t && !*e;
}

struct DumpPlanter {
    static bool HasTableEntry(long n) {
        if (IsSkill((int)n)) return SkillInfo[SkillIndex((int)n)].sk == (int)n;
        for (int j = 0; FeatInfo[j].feat; j++) if (FeatInfo[j].feat == n) return true;
        return false;
    }
    static void Feat(Player *p, long ft) { p->Feats[ft / 8] |= (uint16)(1 << (ft % 8)); }
    static void Skill(Player *p, int sk, int ranks) { p->SkillRanks[SkillIndex(sk)] = (int8)ranks; }
    static void BaseAttr(Player *p, long at, int val) { p->BAttr[at] = (int16)val; }
    static bool Roll(Player *p, bool hp, long r, long c, long val) {
        if (r < 0 || r >= 3 || c < 0 || c >= MAX_CHAR_LEVEL || val < -128 || val > 127) return false;
        (hp ? p->hpRolls : p->manaRolls)[r][c] = (int8)val; return true; }
    static bool SacVal(Player *p, long g, long c, long val) {
        if (g < 0 || g >= MAX_GODS || c < 0 || c >= MAX_SAC_CATS + 2) return false;
        p->SacVals[g][c] = (int32)val; return true; }
    static void XP(Player *p, long val) { p->XP = (uint32)val; }
    static rID *CellList(Map *m, bool terrain) { return terrain ? m->TerrainList : m->RegionList; }
    static void God(Player *p, int g, const std::string &f, long v) {
        if (f == "favour") p->FavourLev[g] = (int32)v; else if (f == "anger") p->Anger[g] = (int16)v; else p->godFlags[g] = (uint16)v; }
    static void MaxDepth(Player *p, int i, long d) { p->MaxDepths[i] = (int16)d; }
    static void Ability(Player *p, int i, long v) { p->Abilities[i] = (uint8)v; }
    static void Slot(Player *p, int i, Item *it) { p->Inv[i] = it->myHandle; }
    static void MonKills(Player *p, int i, long v) { p->JournalInfo.numMonOfType[i] = (int)v; }
    static void IFlags(Item *it, long bits) { it->IFlags = (uint16)(it->IFlags | bits); }
    static void Known(Item *it, long bits) { it->Known = (uint16)(it->Known | bits); }
};

/* Items planted by `item` lines of this spec, so a later `known` line finds them by resource. */
static std::vector<std::pair<rID, Item*> > plantedItems;

/* A resource name may hold spaces: everything after the verb. */
static std::string PlantName(const std::vector<std::string> &w) {
    std::string n;
    for (size_t i = 1; i != w.size(); i++) { if (i > 1) n += ' '; n += w[i]; }
    return n;
}


/* Monsters planted by `monster` lines, so `template` and `target` lines find them by resource. */
static std::vector<std::pair<rID, Monster*> > plantedMonsters;

/* A free cell near the player: in bounds, not solid, no creature, no feature, not the player's own. */
static bool PlantCell(Player *p, int &cx, int &cy) {
    Map *mp = p->m;
    if (!mp) return false;
    for (int d = 1; d <= 6; d++)
        for (int dy = -d; dy <= d; dy++)
            for (int dx = -d; dx <= d; dx++) {
                int x = p->x + dx, y = p->y + dy;
                if (!dx && !dy) continue;
                if (!mp->InBounds(x, y) || mp->SolidAt(x, y)) continue;
                if (mp->FCreatureAt(x, y) || mp->FFeatureAt(x, y)) continue;
                cx = x; cy = y; return true;
            }
    return false;
}

static rID PlantResource(const std::string &nm, int type) {
    rID r = FIND(nm.c_str());
    if (!r || !theGame->Get(r) || !theGame->Get(r)->isType(type)) return 0;
    return r;
}

static bool PlantVarSet(const std::string &ownerName, const std::string &varName, int32 val) {
    for (int ms = 0; ms < MAX_MODULES; ++ms) {
        Module *mod = Game::Modules[ms];
        if (!mod || mod->szDataSeg <= 0 || !theGame->MDataSeg[ms]
            || theGame->MDataSegSize[ms] < (uint32)mod->szDataSeg) continue;
        for (int i = 0; i < mod->Symbols.Total(); ++i) {
            DebugInfo *d = mod->Symbols[i];
            if (d->BType != GLOB_VAR && d->BType != RES_VAR) continue;
            if (strncmp(d->Ident, varName.c_str(), 31) || varName.size() > 31) continue;
            rID owner = d->BType == GLOB_VAR ? 0 : d->xID;
            const char *name = owner ? mod->GetText(mod->__GetResource(owner)->Name) : "(module)";
            if (strcmp(name, ownerName.c_str())) continue;
            memcpy(theGame->MDataSeg[ms] + (size_t)d->Address * 4, &val, sizeof(val));
            return true;
        }
    }
    return false;
}

/* Words [from, to) of a spec line joined by single spaces. */
static std::string PlantJoin(const std::vector<std::string> &w, size_t from, size_t to) {
    std::string n;
    for (size_t i = from; i < to && i < w.size(); i++) { if (i > from) n += ' '; n += w[i]; }
    return n;
}

static size_t PlantAt(const std::vector<std::string> &w) {   /* index of the `@` separator, or 0 */
    for (size_t i = 1; i != w.size(); i++) if (w[i] == "@") return i;
    return 0;
}

/* The verbs of the growth cases (G01-G32): content a save can hold, planted by resource name. */
static bool PlantGrowthLine(Player *p, const std::vector<std::string> &w, std::string &why, bool &handled) {
    const std::string &verb = w[0];
    handled = true;
    long v = 0;
    if (verb == "monster") {
        std::string nm = PlantJoin(w, 1, w.size());
        rID r = PlantResource(nm, T_TMONSTER);
        int cx, cy;
        if (!r) { why = "no monster resource named " + nm; return false; }
        if (!PlantCell(p, cx, cy)) { why = "no free cell beside the player"; return false; }
        Monster *mn = new Monster(r);
        mn->PlaceAt(p->m, cx, cy);
        if (!p->m->FCreatureAt(cx, cy)) { why = "the map did not take " + nm; return false; }
        plantedMonsters.push_back(std::make_pair(r, mn));
        return true;
    }
    if (verb == "template" || verb == "target") {
        size_t at = PlantAt(w);
        if (!at || at + 1 >= w.size() || at < 2) { why = verb + " <name> @ <monster resource>"; return false; }
        std::string mname = PlantJoin(w, at + 1, w.size());
        rID mr = PlantResource(mname, T_TMONSTER);
        Monster *mn = NULL;
        for (size_t i = 0; i != plantedMonsters.size(); i++) if (plantedMonsters[i].first == mr) mn = plantedMonsters[i].second;
        if (!mr || !mn) { why = "no monster " + mname + " planted earlier in this spec"; return false; }
        std::string what = PlantJoin(w, 1, at);
        if (verb == "template") {
            rID tr = PlantResource(what, T_TTEMPLATE);
            if (!tr) { why = "no template resource named " + what; return false; }
            mn->AddTemplate(tr);
            return true;
        }
        if (!V1FamValue("target_why_type", what.c_str(), v)) { why = "no target why type named " + what; return false; }
        Target tg = {};
        tg.type = TargetEnemy;
        tg.data.Creature.c = p->myHandle;
        tg.priority = 30;
        tg.why.Set((TargetWhyType)v);
        if (!mn->ts.addTarget(tg)) { why = "the target system refused the target"; return false; }
        return true;
    }
    if (verb == "ability") {
        if (w.size() != 3 || !PlantNumber(w[2].c_str(), v)) { why = "ability <CA_NAME> <value>"; return false; }
        long ca = 0;
        if (!V1FamValue("ca", w[1].c_str(), ca) || ca < 0 || ca >= CA_LAST) { why = "no ability named " + w[1]; return false; }
        if (v < 0 || v > 255) { why = "ability value out of 0..255"; return false; }
        DumpPlanter::Ability(p, (int)ca, v);
        return true;
    }
    if (verb == "monkills") {
        if (w.size() != 3 || !PlantNumber(w[2].c_str(), v) || v < 0) { why = "monkills <MA_NAME> <count>"; return false; }
        long ma = 0;
        if (!V1FamValue("ma", w[1].c_str(), ma) || ma < 0 || ma >= MA_LAST_REAL) { why = "no monster type named " + w[1]; return false; }
        DumpPlanter::MonKills(p, (int)ma, v);
        return true;
    }
    if (verb == "slot") {
        size_t at = PlantAt(w);
        if (!at || at != 2 || at + 1 >= w.size()) { why = "slot <SL_NAME> @ <item resource>"; return false; }
        long sl = 0;
        if (!V1FamValue("sl", w[1].c_str(), sl) || sl < 0 || sl >= NUM_SLOTS) { why = "no slot named " + w[1]; return false; }
        std::string nm = PlantJoin(w, at + 1, w.size());
        rID r = PlantResource(nm, T_TITEM);
        Item *it = NULL;
        for (size_t i = 0; i != plantedItems.size(); i++) if (plantedItems[i].first == r) it = plantedItems[i].second;
        if (!r || !it) { why = "no item " + nm + " planted earlier in this spec"; return false; }
        DumpPlanter::Slot(p, (int)sl, it);
        return true;
    }
    if (verb == "iflags") {
        if (w.size() < 3) { why = "iflags <item resource> <IF_NAME[|IF_NAME]>"; return false; }
        std::string nm = PlantJoin(w, 1, w.size() - 1);
        rID r = PlantResource(nm, T_TITEM);
        Item *it = NULL;
        for (size_t i = 0; i != plantedItems.size(); i++) if (plantedItems[i].first == r) it = plantedItems[i].second;
        if (!r || !it) { why = "no item " + nm + " planted earlier in this spec"; return false; }
        long bits = 0;
        const std::string &names = w[w.size() - 1];
        for (size_t s = 0; s <= names.size(); ) {
            size_t e = names.find('|', s);
            if (e == std::string::npos) e = names.size();
            std::string one = names.substr(s, e - s);
            if (!V1FamValue("if_flag", one.c_str(), v)) { why = "no item-flag named " + one; return false; }
            bits |= v;
            s = e + 1;
        }
        DumpPlanter::IFlags(it, bits);
        return true;
    }
    if (verb == "feature") {
        std::string nm = PlantJoin(w, 1, w.size());
        rID r = PlantResource(nm, T_TFEATURE);
        int cx, cy;
        if (!r) { why = "no feature resource named " + nm; return false; }
        if (!PlantCell(p, cx, cy)) { why = "no free cell beside the player"; return false; }
        Feature *ft = new Feature(r);
        ft->PlaceAt(p->m, cx, cy);
        if (!p->m->FFeatureAt(cx, cy)) { why = "the map did not take " + nm; return false; }
        return true;
    }
    if (verb == "terrain" || verb == "region") {
        bool ter = verb == "terrain";
        std::string nm = PlantJoin(w, 1, w.size());
        rID r = PlantResource(nm, ter ? T_TTERRAIN : T_TREGION);
        int cx, cy;
        if (!r) { why = "no " + verb + " resource named " + nm; return false; }
        if (!PlantCell(p, cx, cy)) { why = "no free cell beside the player"; return false; }
        rID *list = DumpPlanter::CellList(p->m, ter);
        int k = -1;
        for (int i = 0; i != 256; i++) if (list[i] == r) { k = i; break; }
        if (k < 0) for (int i = 1; i != 256; i++) if (!list[i]) { list[i] = r; k = i; break; }
        if (k < 0) { why = "the map's " + verb + " list is full"; return false; }
        if (ter) p->m->At(cx, cy).Terrain = k; else p->m->At(cx, cy).Region = k;
        return true;
    }
    if (verb == "god") {
        if (w.size() < 4 || !PlantNumber(w[w.size() - 1].c_str(), v)) { why = "god <god resource> <favour|anger|flags> <value>"; return false; }
        const std::string &field = w[w.size() - 2];
        std::string nm = PlantJoin(w, 1, w.size() - 2);
        rID r = PlantResource(nm, T_TGOD);
        if (!r) { why = "no god resource named " + nm; return false; }
        int g = theGame->GodNum(r);
        if (g < 0 || g >= MAX_GODS) { why = "god " + nm + " is outside the arrays of this build"; return false; }
        if (field != "favour" && field != "anger" && field != "flags") { why = "god field is favour, anger or flags"; return false; }
        DumpPlanter::God(p, g, field, v);
        return true;
    }
    if (verb == "dungeon") {
        if (w.size() < 3 || !PlantNumber(w[w.size() - 1].c_str(), v) || v < 1) { why = "dungeon <dungeon resource> <depth>"; return false; }
        std::string nm = PlantJoin(w, 1, w.size() - 1);
        rID r = PlantResource(nm, T_TDUNGEON);
        if (!r) { why = "no dungeon resource named " + nm; return false; }
        int i;
        for (i = 1; i != MAX_DUNGEONS && theGame->DungeonID[i]; i++) if (theGame->DungeonID[i] == r) break;
        if (i == MAX_DUNGEONS) { why = "no free dungeon slot"; return false; }
        if (!theGame->DungeonID[i]) {   /* the registration Game::GetDungeonMap makes on the first arrival */
            const uint32 allocated = min(MAX_DUNGEON_LEVELS, RES(r)->GetConst(DUN_DEPTH) + 1);
            theGame->DungeonID[i] = r;
            theGame->DungeonSize[i] = min(MAX_DUNGEON_LEVELS, (int16)(RES(r)->GetConst(DUN_DEPTH)));
            theGame->DungeonLevels[i] = (hObj*)malloc(sizeof(hObj) * allocated);
            memset(theGame->DungeonLevels[i], 0, sizeof(hObj) * allocated);
        }
        DumpPlanter::MaxDepth(p, i, v);
        return true;
    }
    if (verb == "class" || verb == "race") {
        std::string nm = PlantJoin(w, 1, w.size());
        rID r = PlantResource(nm, verb == "class" ? T_TCLASS : T_TRACE);
        if (!r) { why = "no " + verb + " resource named " + nm; return false; }
        if (verb == "class") p->ClassID[0] = r; else p->RaceID = r;
        return true;
    }
    if (verb == "flavor") {
        size_t at = PlantAt(w);
        if (!at || at < 2 || at + 1 >= w.size()) { why = "flavor <effect resource> @ <flavour resource>"; return false; }
        std::string en = PlantJoin(w, 1, at), fn = PlantJoin(w, at + 1, w.size());
        rID er = PlantResource(en, T_TEFFECT), fr = PlantResource(fn, T_TFLAVOR);
        if (!er) { why = "no effect resource named " + en; return false; }
        if (!fr) { why = "no flavour resource named " + fn; return false; }
        EffMem *em = EFFMEM(er, p);
        if (!em) { why = "the effect has no memory record"; return false; }
        if (TFLA(fr)->IType == AI_POTION) em->PFlavorID = fr; else em->FlavorID = fr;
        return true;
    }
    if (verb == "varrid") {
        size_t at = PlantAt(w);
        if (!at || at < 4 || at + 1 >= w.size()) { why = "varrid <owner resource name> <variable name> @ <resource name>"; return false; }
        std::string rn = PlantJoin(w, at + 1, w.size());
        rID r = FIND(rn.c_str());
        if (!r || !theGame->Get(r)) { why = "no resource named " + rn; return false; }
        if (!PlantVarSet(PlantJoin(w, 1, at - 1), w[at - 1], (int32)r)) { why = "no script variable " + w[at - 1] + " owned by " + PlantJoin(w, 1, at - 1); return false; }
        return true;
    }
    handled = false;
    return true;
}

static bool PlantLine(Player *p, const std::vector<std::string> &w, std::string &why) {
    const std::string &verb = w[0];
    long v = 0, a = 0, b = 0;
    char buf[160];
    { bool handled; bool ok = PlantGrowthLine(p, w, why, handled); if (handled) return ok; }
    if (verb == "status") {
        std::vector<std::string> sw(w);
        long srcv = SS_MISC;
        if (sw.size() > 2 && sw.back().compare(0, 4, "src=") == 0) {
            if (!V1FamValue("ss", sw.back().c_str() + 4, srcv)) { why = "no status source named " + sw.back().substr(4); return false; }
            sw.pop_back();
        }
        if (sw.size() < 2 || sw.size() > 4) { why = "status <STATI_NAME> [val] [mag] [src=SS_NAME]"; return false; }
        if (!V1FamValue("stati", sw[1].c_str(), v)) { why = "no status named " + sw[1]; return false; }
        long val = -1, mag = -1;
        if (sw.size() > 2 && !PlantNumber(sw[2].c_str(), val)) { why = "val is not a number"; return false; }
        if (sw.size() > 3 && !PlantNumber(sw[3].c_str(), mag)) { why = "mag is not a number"; return false; }
        p->GainPermStati((int16)v, NULL, (int8)srcv, (int16)val, (int16)mag);
        if (!p->HasStati((int16)v)) { why = "the engine did not give the status"; return false; }
        return true;
    }
    if (verb == "item") {
        if (w.size() < 2) { why = "item <resource name>"; return false; }
        std::string nm = PlantName(w);
        rID r = FIND(nm.c_str());
        if (!r || !theGame->Get(r) || !theGame->Get(r)->isType(T_TITEM)) { why = "no item resource named " + nm; return false; }
        Item *it = Item::Create(r);
        if (!it) { why = "Item::Create refused " + nm; return false; }
        /* Character::GainItem runs the wield events, which need a game in play; the pack takes the item directly
           (Container::XInsert, as src/InvCursorProbe.cpp does). */
        Item *pk = p->InSlot(SL_PACK);
        if (!pk || !pk->isType(T_CONTAIN) || !((Container*)pk)->XInsert(it)) { why = "the pack did not take " + nm; return false; }
        plantedItems.push_back(std::make_pair(r, it));
        return true;
    }
    if (verb == "known") {
        /* the last word joins KN_ names with `|`; the words between are the item resource name */
        if (w.size() < 3) { why = "known <item resource name> <KN_NAME[|KN_NAME]>"; return false; }
        std::string nm;
        for (size_t i = 1; i + 1 < w.size(); i++) { if (i > 1) nm += ' '; nm += w[i]; }
        rID r = FIND(nm.c_str());
        Item *it = NULL;
        for (size_t i = 0; i != plantedItems.size(); i++) if (plantedItems[i].first == r) it = plantedItems[i].second;
        if (!r || !it) { why = "no item named " + nm + " planted earlier in this spec"; return false; }
        long bits = 0;
        const std::string &names = w[w.size() - 1];
        for (size_t s = 0; s <= names.size(); ) {
            size_t e = names.find('|', s);
            if (e == std::string::npos) e = names.size();
            std::string one = names.substr(s, e - s);
            if (!V1FamValue("kn", one.c_str(), v)) { why = "no known-flag named " + one; return false; }
            bits |= v;
            s = e + 1;
        }
        DumpPlanter::Known(it, bits);
        return true;
    }
    if (verb == "roll") {
        if (w.size() != 5 || (w[1] != "hp" && w[1] != "mana") || !PlantNumber(w[2].c_str(), a) || !PlantNumber(w[3].c_str(), b)
            || !PlantNumber(w[4].c_str(), v)) { why = "roll <hp|mana> <row> <col> <value>"; return false; }
        if (!DumpPlanter::Roll(p, w[1] == "hp", a, b, v)) { why = "roll cell outside the arrays of this build"; return false; }
        return true;
    }
    if (verb == "sacval") {
        if (w.size() != 4 || !PlantNumber(w[1].c_str(), a) || !PlantNumber(w[2].c_str(), b) || !PlantNumber(w[3].c_str(), v))
            { why = "sacval <god> <col> <value>"; return false; }
        if (!DumpPlanter::SacVal(p, a, b, v)) { why = "sacval cell outside the arrays of this build"; return false; }
        return true;
    }
    if (verb == "xp") {
        if (w.size() != 2 || !PlantNumber(w[1].c_str(), v) || v < 0) { why = "xp <value>"; return false; }
        DumpPlanter::XP(p, v);
        return true;
    }
    if (verb == "resave") {
        if (w.size() != 1) { why = "resave takes no argument"; return false; }
        return true;
    }
    if (verb == "spell") {
        if (w.size() < 2) { why = "spell <spell resource name>"; return false; }
        std::string nm = PlantName(w);
        rID r = FIND(nm.c_str());
        if (!r || !theGame->Get(r) || !theGame->Get(r)->isType(T_TEFFECT) || theGame->SpellNum(r) < 0)
            { why = "no spell resource named " + nm; return false; }
        p->GainSpell(r, SP_KNOWN);
        if (!(p->getSpellFlags(r) & SP_KNOWN)) { why = "the engine did not learn the spell"; return false; }
        return true;
    }
    if (verb == "feat") {
        if (w.size() != 2) { why = "feat <FT_NAME>"; return false; }
        if ((!V1FamValue("ft", w[1].c_str(), v) && !V1FamValue("sk", w[1].c_str(), v)) || v < 0 || v > FEATBITS_LAST) { why = "no feat or skill named " + w[1]; return false; }
        /* A bit with no row in FeatInfo (a feat) or SkillInfo (a skill) has no entry in the game's table: a name
           that only anchors the range (FT_FIRST) plants a save that -dump cannot load. */
        if (!DumpPlanter::HasTableEntry(v)) { why = w[1] + " has no entry in the feat or skill table"; return false; }
        DumpPlanter::Feat(p, v);
        return true;
    }
    if (verb == "skill") {
        if (w.size() != 3 || !PlantNumber(w[2].c_str(), a)) { why = "skill <SK_NAME> <ranks>"; return false; }
        if (!V1FamValue("sk", w[1].c_str(), v) || !IsSkill((int)v) || SkillInfo[SkillIndex((int)v)].sk != (int)v)
            { why = "no skill named " + w[1] + " with an entry in the skill table"; return false; }
        if (a < 0 || a > 127) { why = "ranks out of 0..127"; return false; }
        DumpPlanter::Skill(p, (int)v, (int)a);
        return true;
    }
    if (verb == "attr") {
        if (w.size() != 3 || !PlantNumber(w[2].c_str(), a)) { why = "attr <A_NAME> <value>"; return false; }
        if (!V1FamValue("attr", w[1].c_str(), v) || v < 0 || v >= ATTR_LAST) { why = "no attribute named " + w[1]; return false; }
        p->Attr[v] = (int16)a;
        if (v < 7) DumpPlanter::BaseAttr(p, v, (int)a);
        return true;
    }
    if (verb == "option") {
        if (w.size() != 3) { why = "option <OPT_NAME> <value>"; return false; }
        fprintf(stderr, "incursion -dump: plant: option %s skipped: options live in Options.Dat, not in a save\n", w[1].c_str());
        return true;
    }
    if (verb == "var") {
        /* the owner resource name may hold spaces ("Dance of Ruin"): the last two words are the variable and its value */
        if (w.size() < 4 || !PlantNumber(w[w.size() - 1].c_str(), a)) { why = "var <owner resource name> <variable name> <value>"; return false; }
        std::string ownerName;
        for (size_t i = 1; i + 2 < w.size(); i++) { if (i > 1) ownerName += ' '; ownerName += w[i]; }
        const std::string &varName = w[w.size() - 2];
        for (int ms = 0; ms < MAX_MODULES; ++ms) {
            Module *mod = Game::Modules[ms];
            if (!mod || mod->szDataSeg <= 0 || !theGame->MDataSeg[ms]
                || theGame->MDataSegSize[ms] < (uint32)mod->szDataSeg) continue;
            for (int i = 0; i < mod->Symbols.Total(); ++i) {
                DebugInfo *d = mod->Symbols[i];
                if (d->BType != GLOB_VAR && d->BType != RES_VAR) continue;
                if (strncmp(d->Ident, varName.c_str(), 31) || varName.size() > 31) continue;
                rID owner = d->BType == GLOB_VAR ? 0 : d->xID;
                const char *name = owner ? mod->GetText(mod->__GetResource(owner)->Name) : "(module)";
                if (strcmp(name, ownerName.c_str())) continue;
                int32 val = (int32)a;
                memcpy(theGame->MDataSeg[ms] + (size_t)d->Address * 4, &val, sizeof(val));
                return true;
            }
        }
        why = "no script variable " + varName + " owned by " + ownerName;
        return false;
    }
    if (verb == "field") { why = "this build stages no test field (field <scope> <member> <value>)"; return false; }
    snprintf(buf, sizeof(buf), "unknown verb %s", verb.c_str());
    why = buf;
    (void)b;
    return false;
}

/* Returns only on success (the new save is written); on any refusal it names the line and exits 2. */
static void RunPlant(Player *p, const char *specPath, const char *outPath) {
    FILE *f = fopen(specPath, "r");
    if (!f) { fprintf(stderr, "incursion -dump: plant: cannot read %s\n", specPath); exit(2); }
    char line[512];
    int no = 0;
    while (fgets(line, sizeof(line), f)) {
        no++;
        std::vector<std::string> w;
        for (char *t = strtok(line, " \t\r\n"); t; t = strtok(NULL, " \t\r\n")) {
            if (t[0] == '#') break;
            w.push_back(t);
        }
        if (w.empty()) continue;
        std::string why;
        if (!PlantLine(p, w, why)) {
            fprintf(stderr, "incursion -dump: plant: line %d (%s): %s\n", no, w[0].c_str(), why.c_str());
            exit(2);
        }
    }
    fclose(f);
    extern bool SaveV1_FieldValuesResave(const char *out);
    if (!SaveV1_FieldValuesResave(outPath)) { fprintf(stderr, "incursion -dump: plant: the writer refused\n"); exit(2); }
    printf("plant: wrote %s\n", outPath);
}

bool RunRecoverVars(const char *path) {
    fileHeader fhdr;
    if (!LoadSaveForReport(path, fhdr)) return false;
    return PrintScriptVariables(true);
}

bool RunSaveDump(const char *path) {
    fileHeader fhdr;
    if (!LoadSaveForReport(path, fhdr)) return false;

    /* inc-cjos0: INCURSION_FIELD_VALUES makes the real writer run once over the loaded game, so the
       probe logs what each member holds. The re-save goes to <that file>.resave, never over the input. */
    if (const char *fv = getenv("INCURSION_FIELD_VALUES")) {
        extern bool SaveV1_FieldValuesResave(const char *out);
        if (!SaveV1_FieldValuesResave((std::string(fv) + ".resave").c_str())) return false;
    }

    InitGodArrays();

    Player *p = oPlayer(theGame->p[0]);
    Map *m = oMap(theGame->m[0]);
    T1->SetPlayer(p);
    T1->SetMap(m);

    if (const char *spec = getenv("INCURSION_PLANT")) {
        const char *out = getenv("INCURSION_PLANT_OUT");
        if (!out || !*out) { fprintf(stderr, "incursion -dump: plant: INCURSION_PLANT_OUT is unset\n"); exit(2); }
        if (!strcmp(out, path)) { fprintf(stderr, "incursion -dump: plant: the output is the input\n"); exit(2); }
        RunPlant(p, spec, out);
        return true;
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
        int shown = 0;
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
                printf("  %s: flavor=%s pflavor=%s Known=%d Tried=%d "
                       "PKnown=%d PTried=%d\n",
                    SafeResName(eID),
                    SafeResName((rID)em->FlavorID),
                    SafeResName((rID)em->PFlavorID),
                    (int)em->Known, (int)em->Tried,
                    (int)em->PKnown, (int)em->PTried);
                shown++;
            }
        }
        if (!shown)
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
        int shown = 0;
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
                printf("  %s: Seen=%d Fought=%d Kills=%d Battles=%d Deaths=%d "
                       "pKills=%d Attacks=%d Resists=%d Immune=%d Feats=%d "
                       "Flags=%d\n",
                    SafeResName(mID),
                    (int)mm->Seen, (int)mm->Fought, (int)mm->Kills,
                    (int)mm->Battles, (int)mm->Deaths, (int)mm->pKills,
                    (int)mm->Attacks, (int)mm->Resists, (int)mm->Immune,
                    (int)mm->Feats, (int)mm->Flags);
                shown++;
            }
        }
        if (!shown)
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
