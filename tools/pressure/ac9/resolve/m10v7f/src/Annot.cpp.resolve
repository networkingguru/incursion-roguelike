            CensusEvent censusEvent(e.Event,theGame->Modules[ModNum]->QTextSeg + Name);
            /* Each sourced decision a creation script makes is keyed (resource,
               event, ordinal) (inc-10v7f A2, B6). Outside the creation window
               this pushes nothing. */
            const bool creationEvent = CreationWindowOpen() &&
                (e.Event == EV_BIRTH || e.Event == EV_ADVANCE ||
                 e.Event == EV_PREREQ || e.Event == EV_ISTARGET ||
                 e.Event == EV_STARTING_ITEM || e.Event == EV_GENITEM);
            CreationScope creationScope(creationEvent ? NAME(xID) : NULL, e.Event, creationEvent);
            DamageClassHandler(xID, e); /* inc-kx693 */
