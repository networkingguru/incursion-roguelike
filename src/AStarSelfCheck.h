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
static void (*AS_Prev)(int);
static void AS_Term(int sig)
  {
    SC_Buf s;
    s.Str("ASTAR_SELFCHECK calls="); s.Num(AS_Calls);
    s.Str(" mismatches="); s.Num(AS_Mismatch); s.Str("\n"); s.Flush();
    SC_Done(AS_Prev, sig);
  }
/* at startup, so a run cut before its first search still writes a tally */
static struct AS_Init { AS_Init() { atexit(AS_Report); SC_Install(AS_Term, &AS_Prev); } } AS_InitOnce;
