/* inc-j5yo phase 2: a fixed checklist that exercises the LMultiSelect
   group caps, refusal messages, live header text and Tab. Phase 2b adds a
   replay of the recorded checklist. Off unless INCURSION_MULTISELECT_PROBE
   is set. See tools/keys/multiselect-probe.keys and
   docs/specs/2026-10-16-spell-loadout-brief.md. */
#include "Incursion.h"

static void MultiSelectProbeBuildRows(Term *T, bool markAlpha) {
    const char *d = "";
    T->LOptionClear();
    T->LOption("Level 1 - %d of %d slots", 100, d);
    T->LOptionFlags(MO_HEADER);
    T->LOptionCap(1);
    T->LOptionReason("Level 1 is full.");
    T->LOption("Alpha", 1, d);
    T->LOptionMark(markAlpha);
    T->LOption("Bravo", 2, d);
    T->LOptionFlags(0, BLUE);
    T->LOption("Charlie", 3, d);
    T->LOptionFlags(MO_LOCKED);
    T->LOptionMark(true);
    T->LOptionReason("Charlie is locked.");
    T->LOption("Level 2 - %d of %d slots", 200, d);
    T->LOptionFlags(MO_HEADER);
    T->LOptionCap(1);
    T->LOption("Delta", 4, d);
    T->LOption("Echo", 5, d);
    T->LOptionFlags(MO_NOMARK);
    T->LOptionReason("Echo has no book.");
}

void MultiSelectProbe() {
    if (!getenv("INCURSION_MULTISELECT_PROBE"))
        return;
    Player *pl = theGame->GetPlayer(0);
    if (!pl || !pl->MyTerm) {
        Error("MULTISELECT_PROBE INCONCLUSIVE no live player terminal");
        return;
    }
    Term *T = pl->MyTerm;

    int16 saveMode = T->GetMode();
    int16 saveNRsp = RInf.nRsp;
    int16 saveCRsp = RInf.cRsp;

    /* Record the interactive menu: mark the rows, then Enter records the
       Response list under MO_CREATE. */
    T->SetMode(MO_CREATE);
    MultiSelectProbeBuildRows(T, true);

    T->LMultiSelect(MENU_ESC | MENU_DESC | MENU_BORDER, "Probe checklist",
        WIN_MENUBOX);

    for (int32 v = T->FirstSelected(); v != 0; v = T->NextSelected())
        Error("MULTISELECT_PROBE marked %d", (int)v);

    /* Replay the recorded list: rebuild the rows with every non-locked row
       unmarked (Charlie stays locked+marked), rewind cRsp to where the
       interactive menu started recording, and replay under MO_RECREATE. */
    {
        int16 recordStart = saveNRsp;

        MultiSelectProbeBuildRows(T, false);

        RInf.cRsp = recordStart;
        T->SetMode(MO_RECREATE);
        T->LMultiSelect(MENU_ESC | MENU_DESC | MENU_BORDER, "Probe checklist",
            WIN_MENUBOX);

        for (int32 v = T->FirstSelected(); v != 0; v = T->NextSelected())
            Error("MULTISELECT_PROBE replay %d", (int)v);
    }

    T->SetMode(saveMode);
    RInf.nRsp = saveNRsp;
    RInf.cRsp = saveCRsp;

    Error("MULTISELECT_PROBE done");
}
