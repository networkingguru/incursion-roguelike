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


/* INCURSION_PLANT=<spec> INCURSION_PLANT_OUT=<new save> with -dump: the real reader loads the save, each spec line
   is applied through the game's own calls, the real writer writes a NEW file. Names are symbolic only; a number,
   an unknown name or a refused call exits 2 naming the line. Spec language: tools/pressure/plant.sh header. */
extern const char *V1FamName(const char *fam, long value);
extern bool V1FamValue(const char *fam, const char *name, long &value);
extern const char *V1StatSlotFam(long stati, bool mag);
extern const char *V1AtFam(const char *key, long idx);
extern std::vector<std::pair<const char*, int> > V1FieldClaims(const char *field);

static bool PlantNumber(const char *t, long &v) {
    char *e = NULL;
    v = strtol(t, &e, 10);
    return e && *t && !*e;
}

/* A status's val or mag in a spec: a number, a name of the family the `val-of` / `mag-of` marks give that status, or
   names joined by `|` (a bits family). inc-cjos0 9f-pre P2. */
static bool PlantSlotValue(long stati, bool mag, const std::string &tok, long &out, std::string &why) {
    if (PlantNumber(tok.c_str(), out)) return true;
    const char *slot = mag ? "mag" : "val";
    const char *fam = V1StatSlotFam(stati, mag);
    if (!fam) { why = std::string("status ") + V1FamName("stati", stati) + " names no family for its " + slot + ", so " + tok + " is not a number"; return false; }
    out = 0;
    size_t at = 0;
    for (;;) {
        size_t bar = tok.find('|', at);
        std::string one = tok.substr(at, bar == std::string::npos ? std::string::npos : bar - at);
        long v;
        if (!V1FamValue(fam, one.c_str(), v)) { why = std::string("no ") + fam + " name " + one + " for the " + slot + " of status " + V1FamName("stati", stati); return false; }
        out |= v;
        if (bar == std::string::npos) return true;
        at = bar + 1;
    }
}

/* A value in a spec: a number, or names of the given families joined by `|` (a bits family takes several, an ordinal
   family one). The first family that has the name wins. */
static bool PlantNamed(const std::vector<const char*> &fams, const std::string &tok, long &out, std::string &why) {
    if (PlantNumber(tok.c_str(), out)) return true;
    out = 0;
    size_t at = 0;
    for (;;) {
        size_t bar = tok.find('|', at);
        std::string one = tok.substr(at, bar == std::string::npos ? std::string::npos : bar - at);
        long v = 0;
        bool found = false;
        for (size_t k = 0; k != fams.size() && !found; k++) found = V1FamValue(fams[k], one.c_str(), v);
        if (!found) { why = "no name " + one + " in the family of this field"; return false; }
        out |= v;
        if (bar == std::string::npos) return true;
        at = bar + 1;
    }
}

/* A glyph word in a spec (inc-cjos0 9f-pre P5a): GLYPH_NAME[/FORE[/BACK]]. FORE and BACK are names of family colour; FORE
   may also be a COL_ name, packed with GLYPH_FORE() as Magic.cpp:2032 packs a field spell's cval, so a COL_ value
   overflows into the back nibble exactly as it does in the game. */
static bool PlantGlyph(const std::string &tok, long &out, std::string &why) {
    std::vector<std::string> part;
    size_t at = 0;
    for (;;) {
        size_t sl = tok.find('/', at);
        part.push_back(tok.substr(at, sl == std::string::npos ? std::string::npos : sl - at));
        if (sl == std::string::npos) break;
        at = sl + 1;
    }
    long id = 0, c = 0;
    if (part.size() > 3 || !V1FamValue("glyph", part[0].c_str(), id)) { why = "glyph <GLYPH_NAME>[/<FORE>[/<BACK>]]: no glyph name " + part[0]; return false; }
    out = GLYPH_ID(id);
    if (part.size() > 1) {
        if (V1FamValue("colour", part[1].c_str(), c) || V1FamValue("col", part[1].c_str(), c)) out |= GLYPH_FORE(c);
        else { why = "no colour or COL_ name " + part[1]; return false; }
    }
    if (part.size() > 2) {
        if (V1FamValue("colour", part[2].c_str(), c)) out |= GLYPH_BACK(c);
        else { why = "no colour name " + part[2]; return false; }
    }
    return true;
}

/* The Field the last `set field FType` line planted. */
static Field *plantedField = NULL;

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
    static void MonKills(Player *p, int i, long v) { p->JournalInfo.numMonOfType[MaIndex(i)] = (int)v; }
    /* `set player`: false when the player has no such member or the index is out of range (9f-pre P3) */
    static bool PlayerField(Player *p, const std::string &f, long idx, long val) {
        if (f == "Personality") p->Personality = (uint32)val;
        else if (f == "Proficiencies") p->Proficiencies |= (uint32)val;
        else if (f == "QuickKeys_Type" && idx < MAX_QKEYS) p->QuickKeys[idx].Type = (int16)val;
        else if (f == "QuickKeys_MM" && idx < MAX_QKEYS) p->QuickKeys[idx].MM |= (uint32)val;
        else if (f == "MMArray" && idx < MAX_SPELLS) p->MMArray[idx] |= (uint32)val;
        else if (f == "IntStudy" && idx < STUDY_LAST) p->IntStudy[idx] = (uint8)val;
        else return false;
        return true;
    }
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
/* Features, doors and traps planted by this spec, so a `set` line finds the last. */
static std::vector<Feature*> plantedFeatures;

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
        std::string hostOpt[3];   /* quality=, quantity=, hostility= of a `target` line (9f-pre P5a) */
        if (verb == "target") {
            size_t sp = what.find(' ');
            std::string rest = sp == std::string::npos ? "" : what.substr(sp + 1);
            what = what.substr(0, sp);
            while (!rest.empty()) {
                size_t nx = rest.find(' ');
                std::string o = rest.substr(0, nx);
                rest = nx == std::string::npos ? "" : rest.substr(nx + 1);
                size_t eq = o.find('=');
                std::string key = o.substr(0, eq);
                int k = key == "quality" ? 0 : key == "quantity" ? 1 : key == "hostility" ? 2 : -1;
                if (eq == std::string::npos || k < 0) { why = "target <TYPE> [quality=NAME] [quantity=NAME] [hostility=NAME] @ <monster>"; return false; }
                hostOpt[k] = o.substr(eq + 1);
            }
        }
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
        if (hostOpt[0].size() || hostOpt[1].size() || hostOpt[2].size()) {
            /* WasSeenAndHostile.h and IsAllyOfEnemy.hAlly are the same Hostility, first in the union */
            if (tg.why.type != TargetWasSeenAndHostile && tg.why.type != TargetIsAllyOfEnemy) { why = "quality= quantity= hostility= need TargetWasSeenAndHostile or TargetIsAllyOfEnemy"; return false; }
            Hostility &h = tg.why.type == TargetWasSeenAndHostile ? tg.why.data.WasSeenAndHostile.h : tg.why.data.IsAllyOfEnemy.hAlly;
            long hv;
            if (hostOpt[0].size()) { if (!V1FamValue("hostility_qual", hostOpt[0].c_str(), hv)) { why = "no hostility quality " + hostOpt[0]; return false; } h.quality = (HostilityQual)hv; }
            if (hostOpt[1].size()) { if (!V1FamValue("hostility_quant", hostOpt[1].c_str(), hv)) { why = "no hostility quantity " + hostOpt[1]; return false; } h.quantity = (HostilityQuant)hv; }
            if (hostOpt[2].size()) { if (!V1FamValue("hostility_why_type", hostOpt[2].c_str(), hv)) { why = "no hostility why type " + hostOpt[2]; return false; } h.why.type = (HostilityWhyType)hv; }
        }
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
        if (!V1FamValue("ma", w[1].c_str(), ma) || !IsRealMonType((int)ma)) { why = "no monster type named " + w[1]; return false; }
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
        plantedFeatures.push_back(ft);
        return true;
    }
    if (verb == "door" || verb == "trap") {
        /* the game's own constructors, as Effects.cpp:2119 and :2145 call them: a Door has DoorFlags, a Trap TrapFlags */
        std::string nm = PlantJoin(w, 1, w.size());
        int cx, cy;
        if (verb == "door") {
            rID r = PlantResource(nm, T_TFEATURE);
            if (!r || TFEAT(r)->FType != T_DOOR) { why = "no door feature resource named " + nm; return false; }
            if (!PlantCell(p, cx, cy)) { why = "no free cell beside the player"; return false; }
            Door *d = new Door(r);
            d->PlaceAt(p->m, cx, cy);
            if (!p->m->FFeatureAt(cx, cy)) { why = "the map did not take " + nm; return false; }
            plantedFeatures.push_back(d);
            return true;
        }
        rID r = PlantResource(nm, T_TEFFECT);
        if (!r) { why = "no effect resource named " + nm + " for a trap"; return false; }
        if (!PlantCell(p, cx, cy)) { why = "no free cell beside the player"; return false; }
        Trap *tr = new Trap(FIND("trap"), r);
        tr->PlaceAt(p->m, cx, cy);
        if (!p->m->FFeatureAt(cx, cy)) { why = "the map did not take " + nm; return false; }
        plantedFeatures.push_back(tr);
        return true;
    }
    if (verb == "set") {
        /* set <player|monster|item|feature|door|trap|field> <Field>[<index>] <value|NAME|A|B>: a saved member that a
           family mark claims (`field-of`, `index-of`, `elem-of`), set by name. A bits family is ORed in, an ordinal
           family assigned. The object is the player, or the last one of that kind this spec planted. */
        if (w.size() != 4) { why = "set <player|monster|item|feature|door|trap|field> <Field>[<index>] <value>"; return false; }
        const std::string &kind = w[1];
        std::string field = w[2], idxTok;
        size_t br = field.find('[');
        if (br != std::string::npos) {
            if (field[field.size() - 1] != ']') { why = "bad index in " + w[2]; return false; }
            idxTok = field.substr(br + 1, field.size() - br - 2);
            field = field.substr(0, br);
        }
        std::vector<std::pair<const char*, int> > claims = V1FieldClaims(field.c_str());
        if (claims.empty()) { why = "no family claims a saved field named " + field; return false; }
        std::vector<const char*> fams;
        int mode = claims[0].second;
        if (mode >= 100) { why = field + " is part of a Target: use the target verb (quality=, quantity=, hostility=)"; return false; }
        if (field == "ov_GlyphImage") { why = "ov_GlyphImage is an effect overlay: no verb draws one"; return false; }
        for (size_t k = 0; k != claims.size(); k++) if (claims[k].second == mode) fams.push_back(claims[k].first);
        long idx = 0;
        if (mode == 0 && !idxTok.empty()) {
            /* a scalar of an array of records (QuickKeys_Type[3]): the index is a number */
            if (!PlantNumber(idxTok.c_str(), idx) || idx < 0) { why = "bad index " + idxTok; return false; }
        } else if (mode != 0 && mode != 3) {
            if (idxTok.empty() && field != "Qualities") { why = field + " is an array: " + field + "[<index>]"; return false; }   /* AddQuality picks the slot */
            std::string iw;
            if (mode == 1 && !PlantNamed(fams, idxTok, idx, iw)) { why = "index " + iw; return false; }
            if (mode == 2 && !idxTok.empty() && !PlantNumber(idxTok.c_str(), idx)) {
                rID sr = FIND(idxTok.c_str());   /* MMArray and Spells are indexed by spell number: a spell name is that */
                if (!sr || !theGame->Get(sr) || !theGame->Get(sr)->isType(T_TEFFECT) || theGame->SpellNum(sr) < 0)
                    { why = "bad index " + idxTok; return false; }
                idx = theGame->SpellNum(sr);
            }
            if (idx < 0) { why = "bad index " + idxTok; return false; }
        }
        long val = 0;
        if (mode == 3) { if (!PlantGlyph(w[3], val, why)) return false; }
        else if (mode == 1) { if (!PlantNumber(w[3].c_str(), val) || val < 0 || val > 255) { why = "an index-of field takes a count 0..255"; return false; } }
        else if (!PlantNamed(fams, w[3], val, why)) return false;
        Thing *th = NULL;
        if (kind == "monster") { if (plantedMonsters.empty()) { why = "no monster planted earlier in this spec"; return false; } th = plantedMonsters.back().second; }
        else if (kind == "item") { if (plantedItems.empty()) { why = "no item planted earlier in this spec"; return false; } th = plantedItems.back().second; }
        else if (kind == "feature" || kind == "door" || kind == "trap") {
            for (size_t k = plantedFeatures.size(); k-- && !th; )
                if (kind == "feature" || (kind == "door" ? plantedFeatures[k]->Type == T_DOOR : plantedFeatures[k]->Type == T_TRAP)) th = plantedFeatures[k];
            if (!th) { why = "no " + kind + " planted earlier in this spec"; return false; }
        }
        else if (kind != "player" && kind != "field") { why = "set kind is player, monster, item, feature, door, trap or field"; return false; }
        if (kind == "field") {
            if (field == "Image" || field == "Color") {   /* the field the last FType line planted (NewField sets no Color) */
                bool live = false;
                for (int i = 0; p->m->Fields[i]; i++) if (p->m->Fields[i] == plantedField) live = true;
                if (!live) { why = "no field planted earlier in this spec: set field FType first"; return false; }
                if (field == "Image") plantedField->Image = (Glyph)val; else plantedField->Color = (int8)val;
                return true;
            }
            if (field != "FType") { why = "the kind field has the members FType, Image and Color only"; return false; }
            int cx, cy;
            if (!PlantCell(p, cx, cy)) { why = "no free cell beside the player"; return false; }
            p->m->NewField((int32)val, cx, cy, 1, GLYPH_VALUE(GLYPH_FLOOR2, WHITE), -1, 0, NULL);   /* the game's own call, as RemoveProbe.cpp:66 */
            for (int i = 0; p->m->Fields[i]; i++) plantedField = p->m->Fields[i];
            return true;
        }
        if (kind == "player") {
            if (DumpPlanter::PlayerField(p, field, idx, val)) return true;
            if (field == "Spells") { why = "Spells: use `spell <spell resource name> <SP_A|SP_B>`"; return false; }
            else if (field == "godFlags") { why = "godFlags: use `god <god resource> flags <GS_A|GS_B>`"; return false; }
            why = "the player has no plantable member " + field + " (or the index is out of range)";
            return false;
        }
        if (field == "Image") th->Image = (Glyph)val;
        else if (field == "SecretSavedGlyph" && kind == "door") ((Door*)th)->SecretSavedGlyph = (Glyph)val;
        else if (field == "Flags") th->Flags |= (uint32)val;
        else if (field == "LastMoveDir" && kind == "monster") ((Monster*)th)->LastMoveDir = (int8)val;
        else if (field == "StateFlags" && kind == "monster") ((Monster*)th)->StateFlags |= (int16)val;
        else if (field == "DoorFlags" && kind == "door") ((Door*)th)->DoorFlags |= (int8)val;
        else if (field == "TrapFlags" && kind == "trap") ((Trap*)th)->TrapFlags |= (uint8)val;
        else if (field == "Qualities" && kind == "item") {
            Item *it = (Item*)th;
            if (!it->isQItem()) { why = "the item is not a QItem: it holds no qualities"; return false; }
            it->AddQuality((int8)val);   /* the game's own call */
        }
        else { why = "the " + kind + " has no plantable member " + field; return false; }
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
        if (w.size() < 4) { why = "god <god resource> <favour|anger|flags> <value|GS_NAME[|GS_NAME]>"; return false; }
        const std::string &field = w[w.size() - 2];
        bool gsNames = field == "flags" && !PlantNumber(w[w.size() - 1].c_str(), v);
        if (gsNames) {   /* names of family gs: the game's own setGodFlags, which ORs the bits in */
            std::vector<const char*> gf(1, "gs");
            if (!PlantNamed(gf, w[w.size() - 1], v, why)) return false;
        } else if (!PlantNumber(w[w.size() - 1].c_str(), v)) { why = "god <god resource> <favour|anger|flags> <value|GS_NAME[|GS_NAME]>"; return false; }
        std::string nm = PlantJoin(w, 1, w.size() - 2);
        rID r = PlantResource(nm, T_TGOD);
        if (!r) { why = "no god resource named " + nm; return false; }
        int g = theGame->GodNum(r);
        if (g < 0 || g >= MAX_GODS) { why = "god " + nm + " is outside the arrays of this build"; return false; }
        if (field != "favour" && field != "anger" && field != "flags") { why = "god field is favour, anger or flags"; return false; }
        if (gsNames) p->setGodFlags(r, (uint16)v);
        else DumpPlanter::God(p, g, field, v);
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
        rID eidv = 0;
        for (size_t k = 2; k < sw.size(); k++)
            if (sw[k].compare(0, 4, "eid=") == 0) {   /* the resource name is the rest of the line: it may hold spaces */
                std::string nm = sw[k].substr(4);
                for (size_t j = k + 1; j < sw.size(); j++) nm += " " + sw[j];
                eidv = FIND(nm.c_str());
                if (!eidv || !theGame->Get(eidv)) { why = "no resource named " + nm; return false; }
                sw.resize(k);
                break;
            }
        if (sw.size() > 2 && sw.back().compare(0, 4, "src=") == 0) {
            if (!V1FamValue("ss", sw.back().c_str() + 4, srcv)) { why = "no status source named " + sw.back().substr(4); return false; }
            sw.pop_back();
        }
        if (sw.size() < 2 || sw.size() > 4) { why = "status <STATI_NAME> [val] [mag] [src=SS_NAME] [eid=<resource name>]"; return false; }
        if (!V1FamValue("stati", sw[1].c_str(), v)) { why = "no status named " + sw[1]; return false; }
        long val = -1, mag = -1;
        if (sw.size() > 2 && !PlantSlotValue(v, false, sw[2], val, why)) return false;
        if (sw.size() > 3 && !PlantSlotValue(v, true, sw[3], mag, why)) return false;
        SetSilence();   /* StatiOn of BLINDNESS, SLEEPING and others prints a message that waits for a key; a planter has none */
        p->GainPermStati((int16)v, NULL, (int8)srcv, (int16)val, (int16)mag, eidv);
        UnsetSilence();
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
        if (w.size() < 2) { why = "spell <spell resource name> [SP_NAME[|SP_NAME]]"; return false; }
        long spf = SP_KNOWN;
        std::vector<std::string> sw(w);
        if (sw.size() > 2 && sw.back().compare(0, 3, "SP_") == 0) {   /* names of family sp_flag: GainSpell takes the flags */
            std::vector<const char*> sf(1, "sp_flag");
            if (!PlantNamed(sf, sw.back(), spf, why)) return false;
            sw.pop_back();
        }
        std::string nm = PlantName(sw);
        rID r = FIND(nm.c_str());
        if (!r || !theGame->Get(r) || !theGame->Get(r)->isType(T_TEFFECT) || theGame->SpellNum(r) < 0)
            { why = "no spell resource named " + nm; return false; }
        p->GainSpell(r, (int16)spf);
        if ((p->getSpellFlags(r) & spf) != spf) { why = "the engine did not learn the spell"; return false; }
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
        /* inc-cjos0 9f-pre P5b: only the blocks a save carries come back on load (Player.cpp LoadOptions); every other
           option is decided by Options.Dat, so a value planted there would never reach the game */
        if (w.size() != 3) { why = "option <OPT_NAME> <value|NAME>"; return false; }
        if (strncmp(w[1].c_str(), "OPT_", 4) || !V1FamValue("opt", w[1].c_str(), v) || v < 0 || v >= OPT_LAST)
            { why = "no option named " + w[1]; return false; }
        if (v / 100 != 1 && v / 100 != 5 && v / 100 != 8)
            { why = "option " + w[1] + " is in block " + std::to_string((long)(v / 100 * 100)) + ": Options.Dat decides this option on load, so a save cannot carry it"; return false; }
        const char *vf = V1AtFam("Player.Options", v);
        std::vector<const char*> vfams;
        if (vf) vfams.push_back(vf);
        if (!PlantNamed(vfams, w[2], a, why)) { if (!vf) why = "option " + w[1] + " names no value family, so " + w[2] + " is not a number"; return false; }
        if (a < -128 || a > 127) { why = "an option holds one signed byte, -128..127"; return false; }
        p->Options[v] = (int8)a;
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

    /* Canonical mode: a separate walk, so the default report below stays
       byte for byte what 26 tools and key scripts parse. */
    {
        const char *canon = getenv("INCURSION_DUMP_CANONICAL");
        if (canon && *canon && strcmp(canon, "0")) {
            return CanonDump::Run(p, m);
        }
    }
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
