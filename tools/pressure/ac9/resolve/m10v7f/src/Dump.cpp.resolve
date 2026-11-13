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
