/* Shared by the *_SELFCHECK builds (inc-t4isk). tools/run_capped.py stops a
   game with SIGTERM; each tally writes its line from a SIGTERM handler using
   write() only, then chains to the handler installed before it. Included only
   under a *_SELFCHECK flag, in Djikstra.cpp and Monster.cpp. */
#include <signal.h>
#include <unistd.h>
struct SC_Buf
  {
    char b[160]; int n;
    SC_Buf() : n(0) {}
    void Str(const char *s) { while (*s && n < (int)sizeof(b) - 1) b[n++] = *s++; }
    void Num(unsigned long v)
      {
        char t[24]; int k = 0;
        do { t[k++] = (char)('0' + v % 10); v /= 10; } while (v);
        while (k && n < (int)sizeof(b) - 1) b[n++] = t[--k];
      }
    void Flush() { ssize_t r = write(2, b, (size_t)n); (void)r; }
  };
/* Install h for SIGTERM once; *prev receives the handler it replaced. */
static void SC_Install(void (*h)(int), void (**prev)(int))
  {
    void (*old)(int) = signal(SIGTERM, h);
    *prev = (old == SIG_ERR || old == SIG_DFL || old == SIG_IGN) ? 0 : old;
  }
static void SC_Done(void (*prev)(int), int sig)
  {
    if (prev) prev(sig);
    _exit(143);
  }
