| vptr | placement new, src/Registry.cpp:950-992 |
| pointer to an owned heap block | src/Registry.cpp:376, via the 7 direct `r.Block` sites plus every `FIELD_BLOB`/`FIELD_OBJ` line's v0 branch (inc/Base.h:794-799) |
| `Thing::m` from `Thing::hm` | inc/Map.h:981 |
| `Player::MyTerm = T1` | inc/Creature.h:1584 |
| `Module` resource caches zeroed | inc/Res.h:841-842, in `Module::Serialize`, which runs on load as well as save. A load builds the object with the empty `ARCHIVE_CLASS` constructor (inc/Base.h:806), so the zeroing in `Module()` (inc/Res.h:924-925) runs only for the module the resource compiler creates (src/RComp.cpp:141) |
| module text segment un-inverted | inc/Res.h:915-917 |
| garbage payload in a loaded `Target` | src/Registry.cpp:1017-1018, src/Target.cpp:1583 |
