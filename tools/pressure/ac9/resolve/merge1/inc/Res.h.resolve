      /* inc-cjos0: the names of the data migrations this file holds. A
         stack staging String: it covers no byte of Game. */
      if (r.V1Active())
        {
          String migs;
          /* String() leaves itself uninitialised while the Registry is
             loading (src/Registry.cpp, RegistryScope). */
          memset((void*)&migs, 0, sizeof(migs));
          if (isSave)
            migs = SaveV1_MigrationList();
          r.V1Str("Migrations", migs);
          if (!isSave)
            SaveV1_NoteFileMigrations(migs.GetLength() ? migs.GetData() : "");
        }
