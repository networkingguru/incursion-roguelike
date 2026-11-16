/* DrawCensus.cpp -- log-only census of random draws during character creation
   (bead inc-10v7f, phase 0). Active only when INCURSION_DRAW_CENSUS=<path> is
   set; unset, it makes no draw, opens no file and prints nothing. It logs and
   never answers a draw. random() and srand() sites come from macros in
   inc/Inline.h (__FILE__/__LINE__/__func__); Dice::Roll sites come from the
   return address (function+offset via dladdr). */
#include "Incursion.h"
#ifndef _WIN32
#include <dlfcn.h>
#endif

bool g_censusActive = false;
static int  cWin = 0, cEv = 0, cSuppress = 0;
static const char *winName[8];
static int  evNum[8]; static const char *evRes[8];
static FILE *cFile = NULL; static bool cInit = false, cOn = false;

static const char *base(const char *f)
  { const char *s = strrchr(f,'/'); return s ? s+1 : f; }

static void CensusLine(const char *kind, const char *site, const char *fn)
  {
    const char *w = cWin ? winName[cWin-1] : "none";
    const char *en = "none", *rn = "none"; char buf[64];
    if (cEv) {
      int e = evNum[cEv-1], pfx = e >= 1000 ? 1000 : e >= 500 ? 500 : 0;
      snprintf(buf,sizeof buf,"%s%s",pfx==1000?"POST_":pfx==500?"PRE_":"",
               Lookup(EV_CONSTNAMES,e-pfx));
      en = buf; rn = evRes[cEv-1];
    }
    fprintf(cFile,"%s\t%s\t%s\t%s\t%s\t%s\t%s\n",w,en,rn,kind,site,fn,
            CreationInsideLive() ? "sourced" : "unsourced");
    fflush(cFile);
  }

CensusWindow::CensusWindow(const char *n)
  {
    on = false;
    if (!cInit) {
      cInit = true; const char *p = getenv("INCURSION_DRAW_CENSUS");
      if (p && *p && (cFile = fopen(p,"a"))) cOn = true;
    }
    if (!cOn || cWin >= 8) return;
    on = true; winName[cWin++] = n; g_censusActive = true;
  }
CensusWindow::~CensusWindow()
  { if (on) { cWin--; g_censusActive = cWin > 0; } }

CensusEvent::CensusEvent(int ev, const char *res)
  {
    on = false;
    if (!g_censusActive || cEv >= 8) return;
    on = true; evNum[cEv] = ev; evRes[cEv++] = res;
  }
CensusEvent::~CensusEvent() { if (on) cEv--; }

CensusDice::CensusDice(void *ra)
  {
    on = false;
    if (!g_censusActive) return;
    on = true; cSuppress++;
    char site[96], fn[256];
#ifndef _WIN32
    Dl_info di;
    if (dladdr(ra,&di) && di.dli_sname) {
      snprintf(fn,sizeof fn,"%s",di.dli_sname);
      snprintf(site,sizeof site,"+0x%lx",(long)((char*)ra-(char*)di.dli_saddr));
    } else
#endif
    { snprintf(fn,sizeof fn,"?"); snprintf(site,sizeof site,"?"); }
    cSuppress--; CensusLine("dice",site,fn); cSuppress++;
  }
CensusDice::~CensusDice() { if (on) cSuppress--; }

void census_log_random(const char *f, int l, const char *fn)
  {
    if (cSuppress) return;
    char site[128]; snprintf(site,sizeof site,"%s:%d",base(f),l);
    CensusLine("random",site,fn);
  }
void census_log_srand(const char *f, int l, const char *fn)
  {
    if (!g_censusActive) return;
    char site[128]; snprintf(site,sizeof site,"%s:%d",base(f),l);
    CensusLine("srand",site,fn);
  }
