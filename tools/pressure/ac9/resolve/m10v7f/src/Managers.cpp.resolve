                {
                    int8 kept[SK_LAST];
                    for (i = 0; i != SK_LAST; i++)
                        kept[i] = (int8)(p->SkillRanks[i] + Alloc[i][0] + Alloc[i][1] + Alloc[i][2] + Alloc[i][3] + Alloc[i][4] + Alloc[i][5]);
                    p->CommitSkillRanks(kept, usp);
                }
                for (i = SK_LAST; i != SK_COUNT; i++)
                    p->SkillRanks[i] += Alloc[i][0] + Alloc[i][1] + Alloc[i][2] + Alloc[i][3] + Alloc[i][4] + Alloc[i][5];
