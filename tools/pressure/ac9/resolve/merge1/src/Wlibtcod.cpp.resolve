int16 libtcodTerm::GetCharCmdImpl(KeyCmdMode mode) {
    if (mode == KY_CMD_NORMAL_MODE && (showCursor || cursorPulse || ocx || ocy)) {
        char msg[900];
        if (showCursor && !cursorReported) {
            snprintf(msg, sizeof(msg), "CURSOR-LEFT-ON caller=%s", cursorCaller);
            cursorReported = true;
            LogGameError(msg);
        } else if (!showCursor && !staleReported) {
            snprintf(msg, sizeof(msg),
                "CURSOR-STALE-BLOCK cx=%d cy=%d ocx=%d ocy=%d pulse=%d lastOn=%s",
                (int)cx, (int)cy, (int)ocx, (int)ocy, (int)cursorPulse, cursorCaller);
            staleReported = true;
            LogGameError(msg);
        }
    }
