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

bool RunSaveDump(const char *path) {
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
    try {
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

    InitGodArrays();

    Player *p = oPlayer(theGame->p[0]);
    Map *m = oMap(theGame->m[0]);
    T1->SetPlayer(p);
    T1->SetMap(m);

    /* ---------------------------------------------------------- report -- */

    printf("=== Incursion save dump ===\n");
    printf("File:      %s\n", path);
    printf("Format:    %s\n", SaveFormatID());
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
        printf("  Map %dx%d, depth %d. Open squares %d, reachable from the "
               "player %d.\n", (int)sx, (int)sy, (int)m->Depth,
               (int)open, (int)qt);
        printf("  Player at (%d,%d).\n\n", (int)p->x, (int)p->y);

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
                printf("\n");
            }
        if (!found)
            printf("  (no portals on this map)\n");

        delete [] dist;
        delete [] queue;
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
