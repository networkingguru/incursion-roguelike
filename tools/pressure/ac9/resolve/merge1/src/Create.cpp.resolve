/* inc-pu6v.268: one refused menu choice. plain is the engine/god text used to
   group; display is what the footer shows (a god's line voiced, else plain). */
struct CreationRefusalRow {
    std::string name;
    std::string plain;
    std::string display;
};

/* inc-pu6v.268: group refusal rows by distinct PLAIN reason, first-seen order,
   emitting "<names, joined by \", \"> -- <display>\n" once per reason. */
static String GroupCreationRefusals(
    const std::vector<CreationRefusalRow> &rows, const std::string &heading)
{
    String out;
    if (rows.empty())
        return out;
    /* inc-pu6v.121: the first line is the heading; LMenu draws it white. */
    out += Format("%s\n", heading.c_str());
    std::vector<bool> used(rows.size(), false);
    for (size_t i = 0; i < rows.size(); ++i) {
        if (used[i])
            continue;
        std::string names = rows[i].name;
        used[i] = true;
        for (size_t j = i + 1; j < rows.size(); ++j) {
            if (used[j] || rows[j].plain != rows[i].plain)
                continue;
            names += ", ";
            names += rows[j].name;
            used[j] = true;
        }
        out += Format("%s -- %s\n", names.c_str(), rows[i].display.c_str());
    }
    return out;
}

bool Player::Create(bool reincarnate) {
    CensusWindow censusWindow("Create");
    CreationWindow creationWindow;
    CreationSource *src = CreationSourceNow();
    CreationPickList raceList, subraceList, classList, alignList;
@@@ next hunk
                /* inc-pu6v.97 phase 4: the same generated Sacred/Forbidden/
                   Needs-a-god lines HelpClasses shows, spec Sections 5.7
                   and 8 item 3. */
                MyTerm->LOption(NAME(xID),i,DESC(xID) ?
                    (const char*)HelpClassText(xID) :
                    "Description not found.");
                classList.Add(NAME(xID), i);
@@@ next hunk
    {
    String unavailable;
    std::vector<CreationRefusalRow> refusals;
    bool classRefused = false;
    alignList.Clear();
@@@ next hunk
        WIN_CREATION,"help::adventuring,AC",0,unavailable); });
    }
    if (i == -1 && src->CanBackUp()) {
@@@ next hunk
    int16 finalScores[7][5];
    String perkText[5][NUM_PERKS_PER_SET];
    bool setPasses[5];
    /* inc-pu6v.227: the god test and requirement line for the roller screen,
       fetched once per screen and reused by the marker redraws. */
    bool godTest = false;
    String reqLine;

    CreationPickList attrCmds;

    if (AttributesFromSource(BAttr)) {
        attrsRolled = true;
        return true;
    }
@@@ next hunk
        for (i=0;i!=5;i++) {
@@@ next hunk
        /* The command the player chose on this screen. Redraw and help are
           not decisions, so they are not on the list and are not recorded.
           A set the god's entry test refuses is not offered to the source
           either; the keyboard loop below refuses it the same way. */
        attrCmds.Clear();
        for (k = 0; k != 5; k++)
            if (!godTest || setPasses[k])
                attrCmds.Add(Format("%c", 'a' + k), 'a' + k);
        attrCmds.Add("point buy", 'p');
        attrCmds.Add("reroll", 'x');
        attrCmds.Add("reroll without perks", 'w');
        ch = (int16)SourcedPick(CK_ATTR_SET, attrCmds, [&]() -> int32 {
            int16 key;
            for (;;) {
                key = MyTerm->GetCharRaw();
                if (key == KY_UP || key == KY_DOWN) {
                    MyTerm->Write(0, 4 + sel * linesPerSet, " ");
                    sel = (int16)((key == KY_UP ? sel + 4 : sel + 1) % 5);
                    MyTerm->Write(0, 4 + sel * linesPerSet, ">");
                    /* inc-pu6v.227: the line shows only for a failing highlighted set. */
                    DrawRequirementLine(MyTerm, (godTest && !setPasses[sel]) ? reqLine : "",
                        3+linesPerSet*5+4, 4);
                    MyTerm->Update();
                    continue;
                }
                if (key == KY_ENTER) key = 'a' + sel;
                key = tolower(key);
                if (key == KY_REDRAW || (key >= 'a' && key <= 'e') || key == '?' || key == 'p'
                    || ((key == 'x' || key == 'w') && Opt(OPT_REROLL))) {
                    /* inc-pu6v.227: a failing highlighted set cannot be picked,
                       whether chosen by Enter or by its letter. Move the marker to
                       it, redraw the line for it, and keep waiting. */
                    if (key >= 'a' && key <= 'e' && godTest && !setPasses[key - 'a']) {
                        if (getenv("INCURSION_CREATION_ROLLER_PROBE"))
                            Error("CREATION_ROLLER_PROBE refused set=%c", key);
                        MyTerm->Write(0, 4 + sel * linesPerSet, " ");
                        sel = (int16)(key - 'a');
                        for (c = 0; c != 5; c++)
                            MyTerm->Write(0, 4 + c * linesPerSet, c == sel ? ">" : " ");
                        DrawRequirementLine(MyTerm, reqLine, 3+linesPerSet*5+4, 4);
                        MyTerm->Update();
                        continue;
                    }
                    break;
                }
            }
            return key;
        });
@@@ next hunk
    // For almost everyone, choices=nChoices (3).
    for (i=0;i!=choices;i++) {
        CreationPickList domains;
        offered = 0;
@@@ next hunk
                    domains.Add(NAME(god->Domains[j]), j);
                    offered++;
                }

        /* inc-pu6v.118 phase 3: a domain swap can have fewer eligible
           replacements than it lost (MSG-6, not journalled here). Character
           creation's own god content always offers enough, so this is
           unreached there, and so is an ordinary post-chargen first-time
           pick (GainAbility's plain ChooseDomains()): MSG-6 is a SWAP
           shortfall notice, not "no domain found", so it must not fire for
           either. */
        if (!offered) {
            if (isSwap)
                GodlossNotice(6, false, GodID);
            break;
        }

        n = (int16)SourcedPick(CK_DOMAIN, domains, [&]() { return (int32)MyTerm->LMenu(MENU_3COLS|MENU_DESC,title,Win,"help::domains"); });
@@@ next hunk
    unavailable = "";
    std::vector<CreationRefusalRow> refusals;
    int row = offset;
    CreationPickList godPicks;
@@@ next hunk
        MyTerm->LOption(NAME(xID), row, desc);
        godPicks.Add(NAME(xID), row);
        row++;
@@@ next hunk
        WIN_SCREEN, "help::domains",0,unavailable); });
@@@ next hunk
    CensusWindow censusWindow("AdvanceLevel");
    int16 c,i, j; TClass *tc;
    CREATION_TRIPWIRE_PROBE_RANDOM("random-advance");
@@@ next hunk
    if (p->GetAttr(A_SIZ) + 1 + (p->HasStati(WEAPON_SIZE_UP) ? 1 : 0) < TITEM(wID)->Size)
        if (!SourcedPick(CK_WEAPON_UNFIT_CONFIRM, YesNoList(), [&]() {
                return p->yn("That weapon is too large for you normally; you will not be able to wield it. Continue?") ? 1 : 0; }, "size"))
