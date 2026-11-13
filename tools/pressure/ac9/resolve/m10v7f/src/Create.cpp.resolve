    {
        /* The skill screen is one decision: the ranks it keeps. A source that
           holds them replaces the whole screen (its confirm and abort prompts
           included) and commits them through the same function. */
        int32 ranks[SK_LASTSKILL];
        CreationRange rankCap[SK_LASTSKILL];
        bool screenRan = false;
        /* The rank cap the skill screen enforces (Managers.cpp, MaxRanks). */
        for (int16 i = 0; i != SK_LASTSKILL; i++)
            rankCap[i] = CreationRange(0, MaxRanks(i));
        SourcedRoll(CK_SKILL_RANKS, ranks, SK_LASTSKILL, SkillSubName,
            [&]() {
                MyTerm->SkillManager(true);
                screenRan = true;
                for (int16 i = 0; i != SK_LASTSKILL; i++)
                    ranks[i] = SkillRanks[i];
            }, rankCap);
        if (!screenRan) {
            int8 kept[SK_LASTSKILL], none[6] = { 0, 0, 0, 0, 0, 0 };
            for (int16 i = 0; i != SK_LASTSKILL; i++)
                kept[i] = (int8)ranks[i];
            CalcSP();
            CommitSkillRanks(kept, none);
        }
@@@ next hunk
    /* NextSeed is a tick counter: it ticks whether or not a stored seed
       answers (spec A9). The decision is the seed the character keeps. */
    {
        int32 tick = (int32)NextSeed();
        storeSeed = SourcedRoll(CK_STORE_SEED, [&]() { return tick; });
    }
    {
        /* The name is the value after the race and class scripts have run
           (a Monk's birth script sets it), so it is its own decision. */
        CreationPickList mine;
        int32 v; std::string text; bool inList;
        mine.Add((const char*)Named, 0);
        if (CreationAnswerPick(CK_CHARACTER_NAME, NULL, mine, v, text, inList))
            Named = text.c_str();
        else
            CreationNotePick(CK_CHARACTER_NAME, NULL, (const char*)Named);
    }
    WizardMode = SourcedRoll(CK_WIZARD_MODE, [&]() { return (int32)WizardMode; }) != 0;
    ExploreMode = SourcedRoll(CK_EXPLORE_MODE, [&]() { return (int32)ExploreMode; }) != 0;
    rerolledPerks = SourcedRoll(CK_REROLLED_PERKS, [&]() { return (int32)rerolledPerks; }) != 0;
    rerollCount = SourcedRoll(CK_REROLLS, [&]() { return (int32)rerollCount; });
    statMethod = (int16)SourcedRoll(CK_STAT_METHOD, [&]() { return (int32)statMethod; });
    {
        int16 slot = -2;
        src->Finish(this, &slot);
        if (slot != -2)
            GallerySlot = slot;
@@@ next hunk
            pl.Clear();
            for(int k=1;k!=SK_COUNT;k++) {
                i = SkillByIndex(k);
                if (SkillInfo[k].imp) {
@@@ next hunk
                    MyTerm->LOption(SkillInfo[k].name,i,
                        DescribeSkill(SkillInfo[k].sk));
                    pl.Add(SkillInfo[k].name, i);
@@@ next hunk
            pl.Clear();
            for(int k=0;k!=SK_COUNT;k++) {
                i = SkillByIndex(k);
@@@ next hunk
                            MyTerm->LOption(SkillInfo[k].name,i,DescribeSkill(SkillInfo[k].sk));
                            pl.Add(SkillInfo[k].name, i);
