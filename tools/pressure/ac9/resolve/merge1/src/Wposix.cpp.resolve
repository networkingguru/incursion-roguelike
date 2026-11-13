/* The walk takes the next script key as the key pressed. A script with no keys
   left, or no script at all, reports nothing; the next GetCharCmd ends the run. */
int16 posixTerm::DrainKeys() {
    ScriptKey k;

    if (!keys || keyNext >= keyCount)
        return 0;
    k = NextKey();
    return (k.ch == KY_ESC) ? DK_ESCAPE : DK_OTHER;
}

/* inc-ashd: observe cursor ownership without changing prompt behavior. */
void posixTerm::CursorOn() {
    showCursor = true;
    if (!CursorProbeEnabled()) return;
    void *frames[8];
    int count = backtrace(frames, 8);
    char **names = backtrace_symbols(frames, count);
    cursorCaller = names && count > 1 ? names[1] : "UNRESOLVED";
    free(names);
    cursorReported = false;
    if (!cursorOnSeen) {
        fprintf(stderr, "CURSOR-PROBE-ON caller=%s\n", (const char *)cursorCaller);
        cursorOnSeen = true;
    }
}

int16 posixTerm::GetCharCmdImpl(KeyCmdMode mode) {
    if (CursorProbeEnabled() && mode == KY_CMD_NORMAL_MODE) {
        if (!cursorNormalSeen && cursorOnSeen) {
            fprintf(stderr, "CURSOR-PROBE-NORMAL\n");
            cursorNormalSeen = true;
        }
        if (showCursor && !cursorReported) {
            fprintf(stderr, "CURSOR-LEFT-ON key=%ld next-step=%ld caller=%s\n",
                (long)keysRead, (long)keyNext + 1, (const char *)cursorCaller);
            cursorReported = true;
        }
    }

