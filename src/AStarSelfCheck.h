/* ASTAR_SELFCHECK support for Map::ShortestPath (inc-vhkei). Included only
   under #ifdef ASTAR_SELFCHECK. After each A* search the caller reruns plain
   Dijkstra into AS_D and compares reachability and cost to the target. */
static int16 AS_D[256][256];
static unsigned long AS_Calls, AS_Mismatch;
static void AS_Report()
  {
    fprintf(stderr, "ASTAR_SELFCHECK calls=%lu mismatches=%lu\n",
            AS_Calls, AS_Mismatch);
    fflush(stderr);
  }
