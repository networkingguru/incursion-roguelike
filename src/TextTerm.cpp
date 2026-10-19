/* TEXTTERM.CPP -- See the Incursion LICENSE file for copyright information.

     Lower-level functions for interacting with a character-based
   terminal.

   Functions better put in Term?
     bool  TextTerm::RunOnCommandLine(int argc, char *argv[], int *retval);
   Window Handling
     void  TextTerm::InitWindows();
     void  TextTerm::SetWin(int16 w)
     void  TextTerm::SizeWin(int16 wn, int16 x1, int16 y1, int16 x2, int16 y2)
     void  TextTerm::SizeWin(int16 wn, int16 sx, int16 sy)
     int16 TextTerm::WinTop();
     int16 TextTerm::WinBottom();
     int16 TextTerm::WinLeft();
     int16 TextTerm::WinRight();
   Tidy Message IO   
     void  TextTerm::Write(int16 x, int16 y, const char *msg)
     void  TextTerm::Write(const char *msg)
     void  TextTerm::CWrite(const char *msg)
     void  TextTerm::Message(String Msg)
     void  TextTerm::AddMessage(const char* msg)
     void  TextTerm::ShowMessages()
     void  TextTerm::DrawBorder(int16 wn, int16 border)
     void  TextTerm::Box(int16 win, int16 flags, int16 cbor, int16 ctxt, const char*text)
     int16 TextTerm::WrapWrite(int16 x,int16 y,String s, int16 x2)
   Scrolling Text
     void  TextTerm::UpdateScrollArea(int16 _offset, int16 wn)
     void  TextTerm::ClearScroll(bool full=false)
     void  TextTerm::SWrite(const char *text, int16 wn)
     int16 TextTerm::SWrapWrite(int16 x, int16 y, String s, int16 x2, int16 wn)
   Formatted Menus
     void  TextTerm::LOption(const char*text,int32 val,const char*desc)
     int32 TextTerm::LMenu(uint16 fl, const char*title,int8 MWin,const char*help)
*/

#include "Incursion.h"

bool TextTerm::RunOnCommandLine(int argc, char *argv[], int *retval) {
    char option_names[10][15];
    char option_values[10][50];
    size_t option_count = 0;

    // Arguments are noted to be -NAME VALUE, but -NAME1 -NAME2 may mean NAME1 is valid if no VALUE1 is expected.
    for (int i = 1; i < argc && option_count < 10; i++) {
        // If it starts with '-' it is the beginning of a named option.
        if (argv[i][0] == '-') {
            option_count++;
            option_names[option_count - 1][0] = '\0';
            option_values[option_count - 1][0] = '\0';
            strncat(option_names[option_count - 1], &argv[i][1], 14);
        } else if (option_count && option_values[option_count - 1][0] == '\0') {
            strncat(option_values[option_count - 1], argv[i], 49);
        }
    }

    for (size_t j = 0; j < option_count; j++) {
        if (stricmp(option_names[j], "compile") == 0) {
#ifdef DEBUG
            if (option_values[j][0] == '\0')
                strncat(option_values[j], "main.irc", 8);
            if (!theGame->ResourceCompiler(option_values[j]))
                *retval = 20; // Error compiling specified module.  At this point, it should be preceded by explanatory text.
#else
            printf("Error: -compile only works in debug builds, and is not compiled into release builds due to GPL licensing constraints.");
            *retval = 19; // -compile argument given for release build.
#endif
            return true;
        } else if (stricmp(option_names[j], "version") == 0) {
            /* Report what this build IS, and what it came from. A bare
               upstream version here would misidentify the binary. */
            printf("%s release %s (fork of %s %s, %s %s)\n",
                   FORK_NAME, FORK_RELEASE, FORK_BASE_REPO, VERSION_STRING,
                   FORK_BASE_HASH, FORK_BASE_DATE);
            return true;
        } else if (stricmp(option_names[j], "formatid") == 0) {
            /* Print the save-layout stamp this binary demands, and exit.
               tools/check_package.sh compares it against the stamp written
               into mod/Incursion.Mod, because a packaged game whose two build
               halves disagree cannot load its own module and says so only
               after the title screen -- which is how networkingguru#6 reached
               an outside user (inc-tm4). This is the smallest question that
               catches it without loading a game. Both backends accept -keys;
               the libtcod build's LoadKeyQueue supports literal and named keys,
               repeats, comments, @include, @pause and @quit, but not the posix
               screen-scrape directives @choose, @expect, @cursorto, @while or
               @until. */
            printf("%s\n", SaveFormatID());
            return true;
        }
    }
    return false;
}

/*****************************************************************************\
*                                 TEXTTERM                                    *
*                              Window Handling                                *
\*****************************************************************************/

void TextTerm::InitWindows()
  {
    ASSERT(sizeX >= 80);
    ASSERT(sizeY >= 48);
    SizeWin(WIN_SCREEN,   0,  0,  sizeX-1,  sizeY-1);
    SizeWin(WIN_BIGMAP,   0,  0,  sizeX-1,  sizeY-1);
    SizeWin(WIN_MAP,      0,  4,  sizeX-17, sizeY-7);
    SizeWin(WIN_DEBUG,    0,  4,  sizeX-17, sizeY-3);
    SizeWin(WIN_INVEN,    0,  4,  sizeX-17, sizeY-3);
    SizeWin(WIN_OPTIONS,  0,  4,  sizeX-17, sizeY-3);
    SizeWin(WIN_STORE,    0,  4,  sizeX-17, sizeY-3);
      
    SizeWin(WIN_CSHEET,   0,  0,  sizeX-1,  sizeY-1);
      
    SizeWin(WIN_CREATION, 0,  0,  sizeX-17, sizeY-3);
    SizeWin(WIN_MESSAGE,  0,  0,  sizeX-17, 2);
    SizeWin(WIN_MESSAGE2, 0,  sizeY-4, sizeX-1,  sizeY-2);
    SizeWin(WIN_INPUT,    0,  3,  sizeX-17, 3);
    SizeWin(WIN_INPUT2,   0,  sizeY-1, sizeX-1,  sizeY-1);
    SizeWin(WIN_LOWER,    5,  30, sizeX-5,  sizeY-1);
    SizeWin(WIN_UPPER,    1,  2,  sizeX-2,  28);
    SizeWin(WIN_TRAITS,   sizeX-15, 0,  sizeX-1,  sizeY-3);
    SizeWin(WIN_VIEWLIST, sizeX-15, 30, sizeX-1,  sizeY-3);
    SizeWin(WIN_STATUS,   0,  sizeY-2, sizeX-17, sizeY-1);
    SizeWin(WIN_SPELLS,   0,  5,  sizeX-1, 30);
    SizeWin(WIN_NUMBERS,  0,  sizeY-4, sizeX-17, sizeY-4);
    SizeWin(WIN_NUMBERS2, 0,  sizeY-3, sizeX-17, sizeY-3);
    SizeWin(WIN_NUMBERS3, 0,  sizeY-4, sizeX-17, sizeY-3);
    SizeWin(WIN_NUMBERS4, 0,  sizeY-6, sizeX-17, sizeY-5);

  }

void TextTerm::SetWin(int16 w)
  {
    if (w == WIN_INPUT && (Mode == MO_CHARVIEW || Mode == MO_SPLASH))
      activeWin = &(Windows[WIN_INPUT2]);
    else if (w == WIN_MESSAGE && (Mode == MO_CHARVIEW || Mode == MO_SPLASH))
      activeWin = &(Windows[WIN_MESSAGE2]);
    else if (w >= 0 && w <= WIN_LAST)
      activeWin = &(Windows[w]);
    else
      Fatal("Illegal window number sent to TextTerm::SetWin.");
    
  }

void TextTerm::SizeWin(int16 wn, int16 x1, int16 y1, int16 x2, int16 y2)
  {
    if (wn == WIN_SCREEN) {
      Windows[wn].Top  = y1;
      Windows[wn].Left = x1;
      Windows[wn].Bottom = y2;
      Windows[wn].Right = x2;
      return;
      }
    ASSERT(y1 >= 0  || y1 == -1)
    ASSERT(x1 >= 0  || x1 == -1)
    ASSERT(x2 <= sizeX || x2 == -1)
    ASSERT(y2 <= sizeY || y2 == -1)
    if (y1 != -1) Windows[wn].Top =    max(0,y1);
    if (x1 != -1) Windows[wn].Left =   max(0,x1);
    if (y2 != -1) Windows[wn].Bottom = min(y2,Windows[WIN_SCREEN].Bottom);
    if (x2 != -1) Windows[wn].Right =  min(x2,Windows[WIN_SCREEN].Right);
  }

void TextTerm::SizeWin(int16 wn, int16 sx, int16 sy)
  {
    if (wn != WIN_SCREEN)
      {
        ASSERT(sy <= Windows[WIN_SCREEN].Bottom)
        ASSERT(sx <= Windows[WIN_SCREEN].Right)
      }
    Windows[wn].Top    = Windows[WIN_SCREEN].Bottom/2 - sy/2;
    Windows[wn].Bottom = Windows[WIN_SCREEN].Bottom/2 + (sy/2 + sy%2);
    Windows[wn].Left   = Windows[WIN_SCREEN].Right/2 - sx/2;
    Windows[wn].Right  = Windows[WIN_SCREEN].Right/2 + (sx/2 + sx%2);
  }


/*****************************************************************************\
*                                 TEXTTERM                                    *
*                              Tidy Message IO                                *
\*****************************************************************************/

void TextTerm::Write(const char*str)
  {
    const char *ch;
    if (!str)
      return;
    ch = str;
    if (cx < activeWin->Left)
      cx = activeWin->Left;
    if (cy > activeWin->Bottom
      || cy < activeWin->Top)
        { cy = activeWin->Top; cx = activeWin->Left; }
    updated = false;
    while(*ch)
      {
        if (*ch == '\n')
          {
            cy++; ch++; cx = activeWin->Left;
            if (cy > activeWin->Bottom)
              return;
            continue;
          }
        // weimer: return, but only if we're not at the beginning of a line
        if (*ch == '\r')
          {
            ch++; 
            if (cx != activeWin->Left) { 
              cy++; cx = activeWin->Left;
              if (cy > activeWin->Bottom)
                return;
            } 
            continue;
          }
        if (cx > activeWin->Right)
          { cy++; cx = activeWin->Left;
            if (cy > activeWin->Bottom)
              return;
          }
        if ((*ch < 0) && (*ch > -16))
          {
            Color(-*ch); ch++;
            continue;
          }
        if (*ch == '~')
          APutChar(cx,cy,GLYPH_VALUE('%', attr));
        else if (*ch == '_' && (activeWin != &Windows[WIN_DEBUG]))
			APutChar(cx, cy, GLYPH_VALUE(' ' ,attr));
		else if (*ch == LITERAL_CHAR) {
			// To understand LITERAL_CHAR mangling, search for it elsewhere.
			uint32 gid;
			ch++;
			gid = ~(*ch) << 8;
			ch++;
			// upstream: Win32/MSVC's signed char sign-extends this low byte too.
			// Traced: 4072 == 0xFE8 from rune 0xE8 (232).
			// inc-ttte; not sent.
			gid |= (uint8)*ch;
			APutChar(cx, cy, GLYPH_VALUE(gid, attr));
		} else if (*ch == WRAP_BREAK) 
          cWrap = cx+1;
        else if (*ch == WRAP_INDENT) 
          cWrap = cx+3;
        else {
			APutChar(cx, cy, GLYPH_VALUE(*ch, attr));
          }
        cx++; ch++;
      }
  }

void TextTerm::CWrite(const char* text)
  {
    uint8 oattr;
    Write(text);
    if (cy >= activeWin->Bottom - 1) {
      GotoXY(0,activeWin->Bottom);
      oattr = (uint8)attr;
      Color(PINK);
      Write("[MORE]");
      GetCharRaw();
      Color(oattr);
      Clear();
      GotoXY(0,0);
      }
  }

void TextTerm::Message(const char* _Msg) {
    String Seg, Msg;
    int16 oldWin = (activeWin - &Windows[0]);
    int16 space, len;
    int16 ch;
    bool isFull;
    bool autoMore = p ? p->Opt(OPT_AUTOMORE) != 0 : false;

    Msg = _Msg;
    { extern void RunToProbe(const char *, ...);
      RunToProbe("msg %s\n", (const char*)Msg); }
    if (!Msg.GetTrueLength())
        return;
    MessageCounter++;
    AddMessage(Msg);

    if (Mode != MO_PLAY && Mode != MO_INV) {
        Box(WIN_SCREEN, 0, PURPLE, GREY, Msg);
        SetWin(oldWin);
        return;
    }

    if (Msg.GetTrueLength() + 4 > (Windows[WIN_MESSAGE].Right - Windows[WIN_MESSAGE].Left) * 2) {
        Box(WIN_SCREEN, 0, PINK, GREY, Msg);
        SetWin(oldWin);
        return;
    }
    SetWin(WIN_MESSAGE);

    if (ClearMsgOK) {
        ClearMsgOK = false;
        linenum = linepos = 0;
        Clear();
    }

    Color(GREY);
    ASSERT(WinSizeX() >= 25)
        ASSERT(WinSizeY() >= 2)

NextSeg:
    space = WinSizeX() - (linepos + 1);

    /* Leave room for -- more -- on the last line. */
    if (linenum == WinSizeY() - 1 && !autoMore)
        space -= 12;
    if (space < 5) {
        if (linenum == WinSizeY() - 1)
            goto DoMore;
        linenum++;
        linepos = 0;
        goto NextSeg;
    }

    /* Find a good place to break off the segment */
    len = max(space, (int16)Msg.TrueLeft(space).GetLength());
    for (; len != max(0, space - 15); len--)
        if (len > Msg.GetLength() || Msg[len] == ' ' || Msg[len] == '\n')
            break;
    /* No good place, so we have to break a word. */
    if (len == 0)
        len = space;

    if (len > Msg.GetLength()) {
        isFull = true;
        Seg = Msg;
        Msg.Empty();
    } else {
        isFull = false;
        Seg = Msg.Left(len);
        Msg = Msg.Right(Msg.GetLength() - len);
        Seg = Seg.Trim();
        Msg = Msg.Trim();
    }

    GotoXY(linepos, linenum);
    Write(Seg);

    if (isFull) {
        linepos += (int8)Seg.GetTrueLength() + 1;
        return;
    } else {
        if (linenum < WinSizeY() - 1) {
            linenum++;
            linepos = 0;
            goto NextSeg;
        }

DoMore:
        if (!autoMore) {
            int32 old_attr;
            GotoXY(WinSizeX() - 11, WinSizeY() - 1);
            old_attr = attr;
            Color(PINK);
            Write("-- more --");
            do
                ch = GetCharCmd();
            while (ch >= KY_CMD_NORTH && ch <= KY_CMD_SOUTHWEST);
            Color((int16)old_attr);
        }
        ClearMsgOK = false;
        Clear();
        linenum = linepos = 0;
        goto NextSeg;
    }
    SetWin(oldWin);
}

void TextTerm::AddMessage(const char* msg) {
    int16 i;
    if ((strlen(MsgHistory) + strlen(msg)) > 10230) {
        i = strlen(msg) + 3;
        while (MsgHistory[i] && (MsgHistory[i] != '.'))
            i++;
        if (!MsgHistory[i]) {
            strcpy(MsgHistory, msg);
            strcat(MsgHistory, " ");
            return;
        }

        i += 2;
        memmove(MsgHistory, &(MsgHistory[i]), 10239 - i);
        MsgHistory[10239 - i] = 0;
    }
    strcat(MsgHistory, msg);
    strcat(MsgHistory, "\n"); /* ww: now that we're scrolling, keeping line breaks is important */
}

void TextTerm::ShowMessages() {
    int16 oldMode;
    oldMode = GetMode();
    SetMode(MO_DIALOG);
    /* ww: we really want to be able to scroll this! */
    SetWin(WIN_SCREEN);
    Save();
    SizeWin(WIN_CUSTOM,WinSizeX()-16,WinSizeY()-8);
    DrawBorder(WIN_CUSTOM,MAGENTA);
    ClearScroll(true);
    SetWin(WIN_CUSTOM); Color(YELLOW);
    SWrite((WinSizeX()/2)-6,0," -- Messages -- ");
    Color(GREY);
    SWrapWrite(1,1,XPrint(MsgHistory),WinSizeX()-2,WIN_CUSTOM);
    Color(GREY);
    UpdateScrollArea(0,WIN_CUSTOM);  
    UpdateScrollArea(4000,WIN_CUSTOM);
    do {
      Color(GREY);
      UpdateScrollArea(offset,WIN_CUSTOM);
      switch(GetCharCmd(KY_CMD_ARROW_MODE)) {
        case KY_CMD_NORTH:
          UpdateScrollArea(offset-1,WIN_CUSTOM); break;
        case KY_CMD_SOUTH:
          UpdateScrollArea(offset+1,WIN_CUSTOM); break;
        case KY_CMD_NORTHEAST:
        case KY_CMD_NORTHWEST:
          UpdateScrollArea(offset-(WinSizeY()-6),WIN_CUSTOM); break;
        case KY_CMD_SOUTHEAST:
        case KY_CMD_SOUTHWEST:
          UpdateScrollArea(offset+(WinSizeY()-6),WIN_CUSTOM); break;

        default: 
          ClearScroll(true);
          Restore();
          SetMode(oldMode);
          return;
        }
    } while(1);
}

void TextTerm::DrawBorder(int16 wn, int16 border) {
	int16 i;
	SetWin(WIN_SCREEN); Color(border);
	for (i = Windows[wn].Left; i != Windows[wn].Right + 1; i++) {
		PutChar(i, Windows[wn].Top - 1, GLYPH_STORE_HWALL);
		PutChar(i, Windows[wn].Bottom + 1, GLYPH_STORE_HWALL);
	}
	for (i = Windows[wn].Top; i != Windows[wn].Bottom + 1; i++) {
		PutChar(Windows[wn].Left - 1, i, GLYPH_STORE_VWALL);
		PutChar(Windows[wn].Right + 1, i, GLYPH_STORE_VWALL);
	}
	PutChar(Windows[wn].Left - 1, Windows[wn].Top - 1, GLYPH_SOLID);
	PutChar(Windows[wn].Right + 1, Windows[wn].Top - 1, GLYPH_SOLID);
	PutChar(Windows[wn].Left - 1, Windows[wn].Bottom + 1, GLYPH_SOLID);
	PutChar(Windows[wn].Right + 1, Windows[wn].Bottom + 1, GLYPH_SOLID);
}

void TextTerm::Box(int16 win, int16 flags, int16 cbor, int16 ctxt, const char*text) {
	int16 LineLength, BoxLength, Avail, Lines, SpaceAt, y, c, i, real_c, in;
	char *ch; int8 saveMode; bool done;
	ASSERT(strlen(text) < sizeof(lbuff) - 20)
		SetWin(win);
	strcpy(lbuff, text);
	strcat(lbuff, "\n");
	ch = lbuff; LineLength = BoxLength = Lines = SpaceAt = 0;
	if (flags & BOX_WIDEBOX)
		Avail = max((activeWin->Right - activeWin->Left) - 10, 20);
	else
		Avail = max(min((activeWin->Right - activeWin->Left) - 10, 50), 20);
	while (*ch) {
		if (*ch >= 0)
			LineLength++;
		if (*ch == '\n') {
			Lines++;
			if (LineLength > BoxLength)
				BoxLength = LineLength;
			LineLength = 0;
			SpaceAt = 0;
		}
		if (LineLength >= Avail) {
			for (i = 0; ch - i > lbuff && i < Avail / 3; i++)
				if (*(ch - i) == ' ') {
					ch = ch - i;
					ASSERT(*ch == ' ');
					*ch = '\n';
					for (int16 j = 0; j != i; j++)
						if (ch[j + 1] > 0)
							LineLength--;
					goto FoundSpace;
				}
			String temp;
			temp = ch;
			*ch = '\n';
			for (i = 0; temp[i]; i++)
				ch[i + 1] = temp[i];
			ch[i + 1] = 0;
			goto FoundSpace;
		}
		ch++;
FoundSpace:;
	}
	Lines++;

	if (!(flags & BOX_NOSAVE))
		Save();

	SetWin(WIN_SCREEN);
	SizeWin(WIN_CUSTOM, BoxLength - 1, min(40, Lines - 2));

	DrawBorder(WIN_CUSTOM, cbor);
	ClearScroll(true);
	Color(ctxt);

	ch = lbuff; c = 1; real_c = 1; buff2[0] = ' '; y = -1;

	while (*ch) {
		if (*ch == '\n') {
			y++;
			while (real_c < BoxLength) {
				buff2[c++] = ' ';
				real_c++;
			}
			buff2[c++] = 0;
			SWrite(0, y, buff2);
			c = 1; real_c = 1;
		} else {
			buff2[c++] = *ch;
			if (*ch > 0)
				real_c++;
		}
		ch++;
	}
	UpdateScrollArea(0, WIN_CUSTOM);
	saveMode = (int8)Mode;
	Mode = MO_SPLASH;
	done = false; in = 0;
	if (!(flags & BOX_NOPAUSE))
		do {
			int16 oldMode;
			oldMode = GetMode();
			SetMode(MO_DIALOG);
			in = GetCharCmd(KY_CMD_ARROW_MODE);
			SetMode(oldMode);
			switch (in) {
			case KY_CMD_NORTH:
			case KY_CMD_NORTHWEST:
			case KY_CMD_NORTHEAST:
				ScrollUp(); break;
				//UpdateScrollArea(offset- WinSizeY() - 6, WIN_CUSTOM); break;

			case KY_CMD_SOUTH:
			case KY_CMD_SOUTHWEST:
			case KY_CMD_SOUTHEAST:
				ScrollDown(); break;
				//UpdateScrollArea(offset + (WinSizeY() - 6), WIN_CUSTOM); break;

			case KY_CMD_EAST:
			case KY_CMD_WEST:
				break;

			case KY_CMD_ENTER:
			case KY_ENTER: done = true; break;

			default:
				if (!(flags & BOX_MUST_PRESS_ENTER))
					done = true;
				break;
			}
		} while (!done);

	if (flags & BOX_SAVECHAR)
		QueuedChar = (uint8)in;
	Mode = saveMode;
	if (!(flags & BOX_NOSAVE))
		Restore();
}

int16 TextTerm::WrapWrite(int16 x, int16 y, const char* _s, int16 x2, int16 maxlines) {
	String l, v, s; s = _s;
	int pos, lines;
	/* Trim Trailing Returns */
	while (s.GetLength() && s[s.GetLength() - 1] == '\n')
		s = s.Left(s.GetLength() - 1);
	GotoXY(x, y); lines = 0; cWrap = 0;
	while (1) {
		int space_left_on_this_line = (x2 ? x2 : WinSizeX()) - max(x, cWrap);
		int trueLength = s.GetTrueLength();
		if (space_left_on_this_line > trueLength) {
			if (trueLength > 0) { lines++; }
			Write(s);
			GotoXY(max(x, cWrap), y + lines);
			return lines;
		}
		pos = (s.TrueLeft(space_left_on_this_line)).GetLength() - 1;

		int good_breakpoint = pos;
		while (good_breakpoint && s[good_breakpoint] != ' ' && s[good_breakpoint] != '\n')
			good_breakpoint--;
		if (!good_breakpoint) {
			// just write out what we have 
			l = s.TrueLeft(pos);
		} else {
			l = s.Left(good_breakpoint);
		}
		if (l.strchr('\n')) {
			pos = l.strchr('\n');
			l = s.Left(pos);
		}
		s = s.Right((s.GetLength() - l.GetLength()));
		lines++; Write(l); GotoXY(max(x, cWrap), y + lines);
		if ((y + lines) >= WinSizeY() || lines >= maxlines)
			return lines;
		while (s.GetLength() && s[0] == ' ')
			s = s.Right(s.GetLength() - 1);
	}
}

/*****************************************************************************\
*                                 TextTerm                                   *
*                              Scrolling Text                                 *
\*****************************************************************************/

void TextTerm::UpdateScrollArea(int16 _offset, int16 wn) {
	int16 y;
	SetWin(wn);
	Clear();
	offset = _offset == -2 ? offset : _offset;
	if (offset > ScrollLines - WinSizeY())
		offset = max(0, ScrollLines - WinSizeY());
	if (offset < 0)
		offset = 0;
	for (y = 0; y != WinSizeY(); y++) {
		if (y + offset > ScrollLines)
			break;
		BlitScrollLine(wn, y + offset, y);
	}
	if (offset)
		PutChar(WinSizeX() - 1, 0, GLYPH_VALUE(GLYPH_ARROW_UP, EMERALD));
	if (offset < ScrollLines - WinSizeY())
		PutChar(WinSizeX() - 1, WinSizeY() - 1, GLYPH_VALUE(GLYPH_ARROW_DOWN, EMERALD));

	updated = false;
}

void TextTerm::HyperTab(int16 wn) {
    int16 CurrLine, i, ln, sx, sy;
    bool isLink;
    /* Assumptions:
       * There is only one hyper-link per line.
       * Each hyperlink fits on a single line.
       * No text in the scrolling win has attr BLACK + BACK_COLOUR(WHITE).
       * All links are attr WHITE + BACK_COLOUR(BLACK)
       * All links are bracketed with '>' and '<'
       * The character '<' does not occur naturally in the
           same line as a hyperlink.
    */
    
    if (!LinkCount)
      return;

    /* Get Scroll Win Dimensions */
    sx = min(SCROLL_WIDTH,Windows[wn].Right - Windows[wn].Left);
    sy = Windows[wn].Bottom - Windows[wn].Top;

    /* Where "are we" on the page? */
    if (SelectedLink == -1)
      CurrLine = 0;
    else 
      CurrLine = HL[SelectedLink].LineNo;

    /* De-highlight the old link */
    if (SelectedLink != -1) {
        for(i=0;i<sx;i++) {
            //SGetChar(i, HL[SelectedLink].LineNo);
			// Invert the colour.
            if (SGetColor(i,HL[SelectedLink].LineNo) == (BLACK | BACK_COLOUR(WHITE)))
                SPutColor(i,HL[SelectedLink].LineNo, WHITE);
        }
    }
        
    /* Find a link further down. */ 
    ln = -1;   
    for (i=0;i!=LinkCount;i++)
      // Is the link currently displayed in WIN_CUSTOM?
      if (HL[i].LineNo >= offset && HL[i].LineNo <= offset+sy)
        // Is the link below the current one?
        if (HL[i].LineNo > CurrLine)
          // Is it the NEAREST below the current one?
          if (ln == -1 || HL[i].LineNo < HL[ln].LineNo)
            // Make this link the current one.
            ln = i;       
    if (ln != -1)
      goto Found;      
    
    /* Ok, so find a link above, starting from the top */
    ln = -1;   
    for (i=0;i!=LinkCount;i++)
      // Is the link currently displayed in WIN_CUSTOM?
      if (HL[i].LineNo >= offset && HL[i].LineNo <= offset+sy)
        // Is the link above the current one?
        if (HL[i].LineNo < CurrLine)
          // Is it the NEAREST TO THE TOP? 
          if (ln == -1 || HL[i].LineNo < HL[ln].LineNo)
            // Make this link the current one.
            ln = i;       
    if (ln != -1)
      goto Found;

    /* No Link, so default to the old one */
    ln = SelectedLink;
    if (ln == -1)
      return;
    goto Found;

    /* Found the Link; Highlight It. */
    Found:
    isLink = false;
    for(i=0;i<sx;i++)
      {
        if (SGetChar(i, HL[ln].LineNo) == '<')
          isLink = true;
        if (isLink)
          SPutColor(i, HL[ln].LineNo, BLACK | BACK_COLOUR(WHITE));
        if (SGetChar(i, HL[ln].LineNo) == '>')
          isLink = false;
      }
    
    /* Now Update the ScrollWin and SelectedLink. */
    SelectedLink = ln;
    UpdateScrollArea(offset,wn);

  }

void TextTerm::ClearScroll(bool full) {
    SClear();
    ScrollLines = 0;
    if (full) {
        offset = 0;
        scx = scy = 0;
    }
    LinkCount = 0;
    SelectedLink = -1;
}

void TextTerm::SWrite(const char *text, int16 wn)
  {
    int32 oColor; bool isLink = false; int16 c;
    const char *ch;
    ScrollLines = max(scy+1,ScrollLines);
    if (scx > min(SCROLL_WIDTH,Windows[wn].Right-Windows[wn].Left))
      { scx = 0; scy++; }
    if (scy >= MAX_SCROLL_LINES)
      return;
    if (scx < 0)
      scx = 0;
    if (scy < 0)
      scy = 0;
    ch = text;
    updated = false;
    while(*ch)
      {
        if (*ch == '\n')
          {
            ASSERT(!isLink)
            scy++; ch++; scx = 0;
            cWrap = 0;
            ScrollLines = max(scy+1,ScrollLines);
            if (scy > MAX_SCROLL_LINES)
              return;
            continue;
          }
        if (scx > min(SCROLL_WIDTH,Windows[wn].Right-Windows[wn].Left))
          { scy++; scx = 0;
            ScrollLines = max(scy+1,ScrollLines);
            /*
            if (scy > activeWin->Bottom)
              return;
              */
          }
        if (*ch == '{' && isHelp)
          {
            oColor = attr;
            Color(WHITE);
            isLink = true;
            HL[LinkCount].LineNo = scy;
            HL[LinkCount].Column = scx;
            HL[LinkCount].Text[0] = 0;
			SPutChar(scx, scy, GLYPH_VALUE('<',attr));
            scx++;
            ASSERT(isalnum(*(ch+1)));
            if (*(ch+1) && *(ch+2) && *(ch+3) && *(ch+4))
              if (*(ch+1)=='B' && *(ch+2)=='K' && *(ch+3)=='S' && *(ch+4)=='P')
                {
                  HL[LinkCount].Link[0] = 9;
                  HL[LinkCount].Link[1] = 0;
                  goto LinkNameRead;
                }
            HL[LinkCount].Link[0] = *(ch+1);
            if (isalnum(*(ch+2)))
              HL[LinkCount].Link[1] = *(ch+2);
            else
              HL[LinkCount].Link[1] = 0;
            LinkNameRead:
            HL[LinkCount].Link[2] = 0;
            isLink = true;
            ch++;
            continue;
          }
        if (*ch == ':' && isLink)
          {
            ch++;
            c = 0;
            while(isalnum(*ch) || isspace(*ch))
              {
                if (c < 38)
                  HL[LinkCount].Text[c] = *ch;
                c++;
                ch++;
              }
            HL[LinkCount].Text[c] = 0;
            continue;
          }
        if (*ch == '}' && isLink)
          {
			  SPutChar(scx, scy, GLYPH_VALUE('>', attr ));
            scx++;
            Color((int16)oColor);
            isLink = false;
            LinkCount++;
            ASSERT(LinkCount < 511);
            ch++;
            continue;
          }
        if ((*ch < 0) && (*ch > -16))
          {
            Color(-*ch); ch++;
            continue;
          }
        if (*ch == '~') {
			SPutChar(scx, scy, GLYPH_VALUE('%', attr));
          }
        else if (*ch == '_' && (activeWin != &Windows[WIN_DEBUG])) {
			SPutChar(scx, scy, GLYPH_VALUE(' ', attr ));
          }
        else if (*ch == LITERAL_CHAR) {
			// To understand LITERAL_CHAR mangling, search for it elsewhere.
			uint32 gid;
			ch++;
			gid = ~(*ch) << 8;
			ch++;
			// upstream: Win32/MSVC's signed char sign-extends this low byte too.
			// Traced: 4072 == 0xFE8 from rune 0xE8 (232).
			// inc-ttte; not sent.
			gid |= (uint8)*ch;
			SPutChar(scx, scy, GLYPH_VALUE(gid, attr));
		}
        else if (*ch == WRAP_BREAK) 
          cWrap = scx+1;
        else if (*ch == WRAP_INDENT) 
          cWrap = scx+3;
        else {
			SPutChar(scx, scy, GLYPH_VALUE(*ch, attr));
          }
        scx++; ch++;
      }

  }

int16 TextTerm::SWrapWrite(int16 x, int16 y, const char* _s, int16 x2, int16 wn)
  {
    String l, v, s; s = _s; bool cr;
    
    int pos, lines;
    
    x2 = min(SCROLL_WIDTH,x2);
    
    /* Trim Trailing Returns */
    while (s.GetLength() && s[s.GetLength()-1] == '\n')
      s = s.Left(s.GetLength()-1);

    SGotoXY(x,y); lines = 0; cWrap = 0;
    while(1) {
      PurgeStrings();
      pos = (x2 ? x2 : min(SCROLL_WIDTH,Windows[wn].Right-Windows[wn].Left)) - max(cWrap,x);
      if (pos > s.GetTrueLength() && !s.strchr('\n'))
        {
          lines++; SWrite(s,wn);
          SGotoXY(max(x,cWrap),y+lines);
          return lines;
        }
      pos = (s.TrueLeft(pos)).GetLength()-1;
      while (pos && s[pos] != ' ' && s[pos] != '\n')
        pos--;
      l = s.Left(pos);
      if (l.strchr('\n') || l[0] == '\n')
        { pos = l.strchr('\n'); 
          l = s.Left(pos); cr = true; }
      else
        cr = false;
        
      s = s.Right((s.GetLength() - l.GetLength())-1);
      if (l[0] == ' ' && l[1] != ' ')
        l = l.Right(l.GetLength()-1);
      lines++; SWrite(l,wn); 
      if (cr) cWrap = 0;
      SGotoXY(max(x,cWrap),y+lines);
      if ((y + lines) >= MAX_SCROLL_LINES)
        return lines;
      }  

  }

/*****************************************************************************\
*                                 TextTerm                                   *
*                              Formatted Menus                                *
\*****************************************************************************/
void TextTerm::LOption(const char*text,int32 val,const char*desc,
                        int32 sortkey)
  {
      if (OptionCount >= MAX_MENU_OPTIONS)
      return;
    for (int i=0; i<OptionCount; i++)
      if (Option[i].Val == val)
        return; // ww: no need for duplicates!
    Option[OptionCount].Text = text;
    Option[OptionCount].Val = val;
    Option[OptionCount].Desc = desc;
    Option[OptionCount].SortKey = sortkey;
    Option[OptionCount].isMarked = false;
    Option[OptionCount].Flags = 0;
    Option[OptionCount].Color = 0;
    Option[OptionCount].Cap = -1;
    OptionReason[OptionCount] = "";
    OptionCount++;
  }

void TextTerm::LOptionFlags(uint16 fl, int8 color)
  {
    if (OptionCount <= 0)
      return;
    Option[OptionCount-1].Flags |= fl;
    if (color)
      Option[OptionCount-1].Color = color;
  }

void TextTerm::LOptionMark(bool marked)
  {
    if (OptionCount <= 0)
      return;
    Option[OptionCount-1].isMarked = marked;
  }

void TextTerm::LOptionReason(const char*reason)
  {
    if (OptionCount <= 0)
      return;
    OptionReason[OptionCount-1] = reason;
  }

void TextTerm::LOptionCap(int16 cap)
  {
    if (OptionCount <= 0)
      return;
    Option[OptionCount-1].Cap = cap;
  }

void TextTerm::LOptionClear()
{
        OptionCount=0;
}

int LMenuOptionAlphaSort(const void *a, const void *b) {
    LMenuOption *l = (LMenuOption *)a, *r = (LMenuOption *)b;
    if (l->SortKey == r->SortKey) {
        /* we don't want "3 uncursed potions of levitation" to come before
        *                "uncursed potion of growth" */
        const char * a ;
        const char * b ; 
        a = strstr(l->Text,"cursed"); if (!a) a = l->Text;
        b = strstr(r->Text,"cursed"); if (!b) b = r->Text;
        return (strcmp(a,b));
    } else
        return (l->SortKey - r->SortKey);
}

int32 TextTerm::LMenu(uint16 fl, const char*_title,int8 MWin,const char*help, int8 pos) {
    /* ww: since hijklnm etc are taken by the roguelike keyset, give
    * roguelike players 123... options instead */
    const char* MenuLetters =
        (theGame->Opt(OPT_ROGUELIKE)) ? 
        "acdefgimopqrstvwxzACDEFGIMOPQRSTVWXZ                  " :
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ  ";
    int16 ch, i,c,p,qk, szCol, Rows, Cols, Width, Height, DY;
    char let[5]; int16 vStart, vRows;
    String title = _title;
    /* upstream: a menu longer than the alphabet loses every option past it.
       MenuLetters is 52 letters (36 in the roguelike keyset) padded with
       spaces, and the draw wrote MenuLetters[min(53,i)] while the keypress
       resolved through strchr() into the same string. Every option from the
       53rd on therefore drew "[ ]" and no key could name it: a space is
       caught by `case ' '` before the strchr, so the pad was never a key.
       This is base-code, not a port artefact -- the string, the clamp and
       the strchr are plain C++ with no typedef, no width and no platform
       call in them, so a Win32 build on the original compiler loses the
       same options. Observed: a Wood Elf Druid at seed 7 is offered 88
       feats and cannot take 36 of them -- Natural Aptitude, Skill Focus,
       Quicken Spell and the "(Show All Feats)" escape hatch among them.
       Tracked as inc-ysa. NOT sent upstream.
       Guarded by tools/check_menu_overflow.sh.

       The fix keeps the letters absolute for every menu that fits -- those
       are unchanged to the byte -- and pages a menu that does not, so each
       drawn row always carries the letter that selects it. Paging reuses
       LMenu's own scroll window (vStart/vRows) rather than adding a second
       mechanism; it only quantises vStart to whole pages so a letter does
       not change meaning under the cursor. letterCount is measured from the
       string, so the 36-letter roguelike keyset pages at 36. */
    int16 letterCount = (int16)strcspn(MenuLetters, " ");
    bool  paged = OptionCount > letterCount;
    int16 pageSize;
    if (Mode == MO_RECREATE) {
        ASSERT(strncmp(RInf.Rsp[RInf.cRsp].Question,title,31) == 0);
        LOptionClear();
        return RInf.Rsp[RInf.cRsp++].Answer;
    }

    if (fl & MENU_SORTED)
        qsort(Option,OptionCount,sizeof(Option[0]),LMenuOptionAlphaSort);

    PrePrompt();

Restart:
    c = 0;
    if (pos) {
        for (int i=0; i<OptionCount; i++) 
            if (Option[i].Val == pos) 
                c = i; 
    } 

    Cols = (fl & MENU_4COLS) ? 4 :
        (fl & MENU_3COLS) ? 3 :
        (fl & MENU_2COLS) ? 2 : 1;

    Save();
    Rows = max(1,OptionCount / Cols);
    if (Cols > 1)
        if (OptionCount % Cols)
            Rows++;
    vRows = min((fl & MENU_BORDER) ? 32 : 34,Rows);
    /* A paged menu never draws more rows than it has letters for. */
    if (paged)
        vRows = min(vRows, (int16)max(1, letterCount / Cols));
    pageSize = vRows * Cols;
    vStart = 0;

    DY = 0;
    if (MWin == WIN_MENUBOX) {
        szCol = 0;
        for(i=0;i!=OptionCount;i++)
            if ((int16)strlen(Option[i].Text) > szCol)
                szCol = strlen(Option[i].Text);
        szCol += 6;
        if (szCol > 76 / Cols) szCol = 76 / Cols; 
        for(i=0;title[i];i++)
            if (title[i] == '\n')
                DY++;
        if (fl & MENU_LARGEBOX) {
            SetWin(WIN_SCREEN);
            Width = activeWin->Right - activeWin->Left;
            Width -= 8;
            szCol = Width / Cols;
        } else if (fl & MENU_WIDE) {
            SetWin(WIN_SCREEN);
            Width = activeWin->Right - activeWin->Left;
            Width -= 16;
            szCol = Width / Cols;          
        } else if (!title)
            Width = 4 + szCol * Cols;
        else
            Width = 2 + max(min(45,(int16)strlen(title)),szCol*Cols);
        Height = vRows + (title ? DY+1 : 0) + 1 + (paged ? 1 : 0);
        if (fl & MENU_LARGEBOX) {
            SetWin(WIN_SCREEN);
            Height = WinSizeY() - 8;
        } else if (fl & MENU_DESC)
            Height += 9;

        if (fl & MENU_DESC) {
            SizeWin(WIN_MENUBOX, Width, Height);
            SetWin(WIN_MENUBOX);
            SizeWin(WIN_MENUDESC,WinLeft(),WinTop()+(Height-9),WinRight(),WinBottom());
        } else
            SizeWin(WIN_MENUBOX, Width, Height);
        SetWin(WIN_SCREEN); Color(EMERALD);
    } else {
        SetWin(MWin);
        szCol = ((activeWin->Right - activeWin->Left) / Cols);
    }
    if (fl & MENU_BORDER)
        DrawBorder(MWin,EMERALD);
    for (i=0;i!=OptionCount;i++)
        Option[i].Text = Option[i].Text.Left(szCol - 4); // ww: - "[A] "

    /*
    SetWin(MWin);
    tcol = activeWin->Bottom - activeWin->Top;
    if (fl & MENU_DESC)
    {
    SetWin(WIN_MENUDESC);
    tcol -= (activeWin->Bottom - activeWin->Top)+1;
    ASSERT(tcol>1);
    }
    vRows = min(vRows,tcol);
    */

    do {            
        SetWin(MWin);
        Clear();
        PurgeStrings();
        DY = (MWin == WIN_MENUBOX) ? 1 : 2;
        if (title) {
            Color(WHITE);
            if ((int16)strlen(title) > WinSizeX()-3 || strchr(title,'\n')) {
                if (fl & MENU_SWRAPWRITE) {
                    ClearScroll(); 
                    DY += SWrapWrite(3, 1, (fl & MENU_RAW) ? (const char*)title : XPrint(title), WinSizeX() - 2, MWin);
                    UpdateScrollArea(0,MWin); 
                } else if (MWin == WIN_CREATION) {
                    DY += WrapWrite(3, 1, (fl & MENU_RAW) ? (const char*)title : XPrint(title), WinSizeX() - 2);
                } else
                    DY += WrapWrite(0,0,(fl & MENU_RAW) ? (const char*) title : XPrint(title));
            } else {
                p = ((WinSizeX()/2) - (strlen(title)/2)) /* * (MWin != WIN_MENUBOX)*/; 
                GotoXY(p,(MWin == WIN_MENUBOX) ? 0 : 1);
                if (fl & MENU_RAW)
                    Write(title); 
                else
                    Write(XPrint(title));
                DY++;
            }
        }
        if (fl & MENU_DESC) {
            SetWin(MWin);
            SizeWin(WIN_MENUDESC, WinLeft(),min(WinTop()+vRows+DY+1,WinBottom()-5),WinRight(),WinBottom());
        }

        /* center things nicely */
        if (paged)
            /* Whole pages only, so a letter keeps its meaning while the
               page is up. The cursor is the only page state there is. */
            vStart = (c / pageSize) * pageSize;
        else {
            if (c >= vStart + vRows*Cols)
                vStart = c - (vRows*Cols-1);
            if (c < vStart)
                vStart = c;
        }

        SetWin(MWin);
        for (i = vStart; i != min(OptionCount, vStart + vRows*Cols); i++) {
            GotoXY(((i - vStart) / vRows)*szCol, ((i - vStart) % vRows) + DY);
            /* Absolute while the alphabet reaches, page-relative once it
               does not. Either way the index is inside the letters, so the
               pad at the end of MenuLetters is never drawn as a key. */
            let[0] = MenuLetters[min((int16)(letterCount - 1),
                                     (int16)(paged ? i - vStart : i))];
            let[1] = 0;
            if (fl & MENU_QKEY)
                for (qk=0;qk!=MAX_QKEYS;qk++)
                    if (Option[i].Val == QuickKeys[qk].Value)
                        if (QKeyType == QuickKeys[qk].Type) {
                            let[0] = -EMERALD;
                            let[1] = '0' + qk;
                            let[2] = -((c == i) ? WHITE : GREY);
                            let[3] = 0;
                        }
            if (c == i) {
                /* ww: so that [A] cursed long sword 
                * shows up as <blue>[A] <red>cursed<white>long sword
                * and not <white][A] <red>cursed<white>long sword
                * which makes it impossible to tell where you are 
                * fjm: I fixed this using Decolorize(), so that the
                * entire menu item is blue. */
                Color(WHITE);
                Write(Format("  [%s] ",let));
                Color(AZURE);
                Write(Decolorize(Option[i].Text).Left(szCol - 5));
                Color(GREY);
            } else {
                Color(GREY);
                Write(Format("  [%s] %.*s", let, szCol - 5, (const char*)Option[i].Text));
            }
        }
        /* Say so. A page that hid two thirds of the list without a word
           would read exactly like the defect this replaces. */
        if (paged && DY + vRows < WinSizeY()) {
            GotoXY(0, DY + vRows);
            Color(EMERALD);
            Write(Format("  %d-%d of %d  [TAB] next page",
                vStart + 1, min(OptionCount, vStart + pageSize), OptionCount));
            Color(GREY);
        }
        if (fl & MENU_DESC) {
            ClearScroll();
            Color(BLUE);
            SWrapWrite(3,0,XPrint(Option[c].Desc),WinSizeX()-2,WIN_MENUDESC);
            UpdateScrollArea(0,WIN_MENUDESC);
            SetWin(MWin);
        }

InvalidChar:
        {
            int16 oldMode;
            oldMode = GetMode();
            SetMode(MO_DIALOG);
            if (i < 27)
                ch=tolower(GetCharCmd(KY_CMD_ARROW_MODE));
            else
                ch = GetCharCmd(KY_CMD_ARROW_MODE);
            SetMode(oldMode);
        }
        switch(ch) {
        case KY_REDRAW:
            if (fl & MENU_REDRAW)
                return -2;
            break;
        case KY_CMD_NORTHEAST:
        case KY_CMD_NORTHWEST:
            if (fl & MENU_DESC) { 
                SetWin(MWin);
                ScrollUp(WIN_MENUDESC);
            } 
            goto InvalidChar;
        case KY_CMD_SOUTHEAST:
        case KY_CMD_SOUTHWEST:
            if (fl & MENU_DESC) { 
                SetWin(MWin);
                ScrollDown(WIN_MENUDESC);
            } 
            goto InvalidChar;
        case KY_CMD_NORTH:
            if (c > 0)
                c--;
            else
                c = OptionCount - 1; 
            break;
        case KY_CMD_SOUTH:
            if (c < OptionCount-1)
                c++;
            else  {
                vStart = 0; 
                c = 0; 
            }
            break;
        case KY_CMD_WEST:
            /* Deck: Left moves one column left, or turns the page back when
               already at the left edge (where it used to do nothing), so a
               handheld with only arrow keys can page. inc-7h6s. */
            if (c - vRows >= vStart)
                c -= vRows;
            else if (paged) {
                c = c - (c % pageSize) - pageSize;
                if (c < 0)
                    c = ((OptionCount - 1) / pageSize) * pageSize;
            }
            break;
        case KY_CMD_EAST:
            /* Deck: Right moves one column right, or turns the page forward
               when already at the right edge, mirroring TAB. inc-7h6s. */
            if (c + vRows <= min(OptionCount-1,vStart+(vRows*Cols-1)))
                c += vRows;
            else if (paged) {
                c += pageSize - (c % pageSize);
                if (c >= OptionCount)
                    c = 0;
            }
            break;
        case KY_TAB:
            /* Next page, wrapping. Only a paged menu has one, and TAB is
               free in this switch. PGUP/PGDN are not: they already scroll
               the description pane above (KY_CMD_NORTHEAST/SOUTHEAST). */
            if (paged) {
                c += pageSize - (c % pageSize);
                if (c >= OptionCount)
                    c = 0;
            }
            break;
        case KY_ENTER:
            Restore();
            OptionCount=0;
            if (Mode == MO_CREATE) {
                strncpy(RInf.Rsp[RInf.nRsp].Question,title,31);
                RInf.Rsp[RInf.nRsp].Answer = Option[c].Val;
                RInf.nRsp++;
            }             
            return Option[c].Val;
        case KY_ESC:
            if (fl & MENU_ESC) {
                Restore();
                OptionCount = 0;
                if (Mode == MO_CREATE) {
                    strncpy(RInf.Rsp[RInf.nRsp].Question,title,31);
                    RInf.Rsp[RInf.nRsp].Answer = -1;
                    RInf.nRsp++;
                }
                return -1;
            }
            break;
        case KY_HELP:
            if (help) {
                Restore();
                if (!strchr(help,','))
                    HelpTopic(help);
                else {
                    static String a, b;
                    a = Upto(help,",/");
                    b = Right(help,strlen(help) - (a.GetLength()+1));
                    HelpTopic(a,b);
                }
                goto Restart;
            }
            break;
        case ' ':
            break;
        default:
            if (isdigit(ch)) {
                if (!(fl & MENU_QKEY))
                    break;
                QuickKeys[ch - '0'].Type  = QKeyType;
                QuickKeys[ch - '0'].Value = Option[c].Val;
                QuickKeys[ch - '0'].MM    = 0;
                break; 
            }
            if (ControlKeys & ALT || ControlKeys & CONTROL) {
                if (ControlKeys & SHIFT) ch = toupper(ch); 
                for (i=0;i<OptionCount;i++) 
                    if ((Option[i].Text[0]) == ch) {
                        c = i; 
                        break; 
                    } 
            } else {
                const char *hit = strchr(MenuLetters, ch);
                int16 pick;

                /* The pad at the end of MenuLetters is not a key. Space
                   never gets this far -- `case ' '` above eats it -- but a
                   letter that is not in the roguelike set must not resolve
                   into the pad either. */
                if (hit == NULL || (int16)(hit - MenuLetters) >= letterCount)
                    goto InvalidChar;
                pick = (int16)(hit - MenuLetters);
                /* One page's letters name that page's options, and nothing
                   past its last row. */
                if (paged) {
                    if (pick >= pageSize)
                        goto InvalidChar;
                    pick += vStart;
                }
                if (pick >= OptionCount)
                    goto InvalidChar;

                Restore();
                OptionCount = 0;
                if (Mode == MO_CREATE) {
                    strncpy(RInf.Rsp[RInf.nRsp].Question,title,31);
                    RInf.Rsp[RInf.nRsp].Answer = Option[pick].Val;
                    RInf.nRsp++;
                }
                return Option[pick].Val;
            }
        }
    } while(1);
}

/* inc-j5yo: the header row that governs option i, or -1 if none. A header
   governs the rows after it up to the next header. */
static int16 MSHeaderOf(LMenuOption *o, int16 n, int16 i)
{
    for (int16 h = i; h >= 0; h--)
        if (o[h].Flags & MO_HEADER)
            return h;
    return -1;
}

/* inc-j5yo: marked rows in the group that are not MO_LOCKED. Locked rows do
   not count against a cap; header rows never mark. */
static int16 MSGroupCount(LMenuOption *o, int16 n, int16 hdr)
{
    int16 count = 0;
    for (int16 k = hdr + 1; k < n && !(o[k].Flags & MO_HEADER); k++)
        if (o[k].isMarked && !(o[k].Flags & MO_LOCKED))
            count++;
    return count;
}

bool TextTerm::LMultiSelect(uint16 fl, const char* _title,int8 MWin,const char*help,
                            int8 pos)
{
    int16 ch, i,j,c,p,szCol, Rows, Cols, Width, Height, DY, barlen;
    int16 vStart, vRows;
    String title;
    String refusal;                 /* inc-j5yo: pending refusal message */
    bool   refused = false;         /* set while refusal holds a message */
    title = _title;

    barlen = 5;
    for (i=0;i!=OptionCount;i++)
        barlen = max(barlen,(int16)Option[i].Text.GetTrueLength()+6);


    /* inc-j5yo: sorting would separate rows from the headers that own them,
       and would also desynchronise Option from the parallel OptionReason
       array. Skip sorting if any row carries a refusal reason. */
    if (fl & MENU_SORTED) {
        bool anyHeader = false, anyReason = false;
        for (i=0;i!=OptionCount;i++) {
            if (Option[i].Flags & MO_HEADER)
                anyHeader = true;
            if (OptionReason[i].GetLength())
                anyReason = true;
        }
        if (!anyHeader && !anyReason)
            qsort(Option,OptionCount,sizeof(Option[0]),LMenuOptionAlphaSort);
    }

    /* inc-j5yo phase 2b: replay. A LMultiSelect recorded under MO_CREATE is
       replayed here from RInf exactly as LMenu replays a pick: the choices
       are Answers terminated by -1, with the menu title as the Question.
       This mirrors LMenu's placement -- before any drawing. */
    if (Mode == MO_RECREATE) {
        /* Clear every mark that replay may set: non-header, non-locked rows. */
        for (i=0;i!=OptionCount;i++)
            if (!(Option[i].Flags & (MO_HEADER | MO_LOCKED)))
                Option[i].isMarked = false;
        while (RInf.Rsp[RInf.cRsp].Answer != -1) {
            ASSERT(strncmp(RInf.Rsp[RInf.cRsp].Question,title,31) == 0);
            int32 ans = RInf.Rsp[RInf.cRsp++].Answer;
            for (i=0;i!=OptionCount;i++)
                if (!(Option[i].Flags & MO_HEADER) && Option[i].Val == ans)
                    Option[i].isMarked = true;
        }
        ASSERT(strncmp(RInf.Rsp[RInf.cRsp].Question,title,31) == 0);
        RInf.cRsp++;   /* consume the terminator */
        return true;
    }

    PrePrompt();

Restart:

    c = 0;
    if (pos) {
        for (int i=0; i<OptionCount; i++) 
            if (Option[i].Val == pos) 
                c = i; 
    } 
    /* inc-j5yo: the cursor never rests on a header row. */
    while (c < OptionCount && (Option[c].Flags & MO_HEADER))
        c++;

    Cols = (fl & MENU_4COLS) ? 4 :
        (fl & MENU_3COLS) ? 3 :
        (fl & MENU_2COLS) ? 2 : 1;
    Save();
    Rows = max(1,OptionCount / Cols);
    if (Cols > 1)
        if (OptionCount % Cols)
            Rows++;
    vRows = min((fl & MENU_BORDER) ? 36 : 38,Rows);
    vStart = 0;


    DY = 0;
    if (MWin == WIN_MENUBOX)
    {
        szCol = 0;
        for(i=0;i!=OptionCount;i++)
            if ((int16)strlen(Option[i].Text) > szCol)
                szCol = strlen(Option[i].Text);
        szCol += 6;
        if (szCol > 76 / Cols) szCol = 76 / Cols; 
        for(i=0;title[i];i++)
            if (title[i] == '\n')
                DY++;
        if (fl & MENU_LARGEBOX)
        {
            SetWin(WIN_SCREEN);
            Width = activeWin->Right - activeWin->Left;
            Width -= 8;
            szCol = Width / Cols;
        }
        else if (fl & MENU_WIDE)
        {
            SetWin(WIN_SCREEN);
            Width = activeWin->Right - activeWin->Left;
            Width -= 16;
            szCol = Width / Cols;          
        }
        else if (!title)
            Width = 4 + szCol * Cols;
        else
            Width = 2 + max(min(45,(int16)strlen(title)),szCol*Cols);
        Height = vRows + (title ? DY+1 : 0) + 1;
        if (fl & MENU_LARGEBOX) {
            SetWin(WIN_SCREEN);
            Height = WinSizeY() - 8;
        }
        else if (fl & MENU_DESC)
            Height += 9;

        if (fl & MENU_DESC) {          
            SizeWin(WIN_MENUBOX, Width, Height);
            SetWin(WIN_MENUBOX);
            SizeWin(WIN_MENUDESC,WinLeft(),WinTop()+(Height-9),WinRight(),WinBottom());
        }
        else
            SizeWin(WIN_MENUBOX, Width, Height);
        SetWin(WIN_SCREEN); Color(EMERALD);
    }
    else
    {
        SetWin(MWin);
        szCol = ((activeWin->Right - activeWin->Left) / Cols);
    }
    if (fl & MENU_BORDER)
        DrawBorder(MWin,EMERALD);
    for (i=0;i!=OptionCount;i++)
        /* inc-j5yo: a capped header keeps its full printf format; the draw
           clips it with %.*s. Truncating here would cut the format. */
        if (!(Option[i].Flags & MO_HEADER))
            Option[i].Text = Option[i].Text.Left(szCol - 4); // ww: - "[A] "

    /*
    SetWin(MWin);
    tcol = activeWin->Bottom - activeWin->Top;
    if (fl & MENU_DESC)
    {
    SetWin(WIN_MENUDESC);
    tcol -= (activeWin->Bottom - activeWin->Top)+1;
    ASSERT(tcol>1);
    }
    vRows = min(vRows,tcol);
    */


    do {            
        SetWin(MWin);
        Clear();
        PurgeStrings();
        DY = (MWin == WIN_MENUBOX) ? 1 : 2;
        if (title) {
            Color(WHITE);
            if ((int16)strlen(title) > WinSizeX()-3 || strchr(title,'\n')) {
                if (fl & MENU_SWRAPWRITE) {
                    ClearScroll(); 
                    DY += SWrapWrite(3,1,(fl & MENU_RAW) ? (const char*) title : XPrint(title),WinSizeX()-2,MWin);
                    UpdateScrollArea(0,MWin); 
                } else if (MWin == WIN_CREATION) {
                    DY += WrapWrite(3,1,(fl & MENU_RAW) ? (const char*) title : XPrint(title),WinSizeX()-2);
                }
                else
                    DY += WrapWrite(0,0,(fl & MENU_RAW) ? (const char*) title : XPrint(title));
            }
            else {
                p = ((WinSizeX()/2) - (strlen(title)/2)) /* * (MWin != WIN_MENUBOX)*/; 
                GotoXY(p,(MWin == WIN_MENUBOX) ? 0 : 1);
                if (fl & MENU_RAW)
                    Write(title); 
                else
                    Write(XPrint(title));
                DY++;
            }
        }
        if (fl & MENU_DESC) {
            SetWin(MWin);
            SizeWin(WIN_MENUDESC, WinLeft(),min(WinTop()+vRows+DY+1,WinBottom()-5),WinRight(),WinBottom());
        }

        /* center things nicely */ 
        if (c >= vStart + vRows*Cols)
            vStart = c - (vRows*Cols-1);
        if (c < vStart) 
            vStart = c; 

        SetWin(MWin);
        for(i=vStart;i!=min(OptionCount,vStart+vRows*Cols);i++) {
            GotoXY(((i-vStart)/vRows)*szCol,((i-vStart)%vRows)+DY);
            if (Option[i].Flags & MO_HEADER) {
                /* inc-j5yo: a header row draws its text with no box, in
                   YELLOW, and is never markable or cursor-selectable. A
                   capped header's Text is a printf format with two %d:
                   the group's marked count and the cap. */
                Color(YELLOW);
                if (Option[i].Cap >= 0)
                    Write(Format("  %.*s",szCol - 5,
                        (const char*) Format((const char*) Option[i].Text,
                            (int) MSGroupCount(Option,OptionCount,i),
                            (int) Option[i].Cap)));
                else
                    Write(Format("  %.*s",szCol - 5,
                        (const char*) Option[i].Text));
                continue;
            }
            Color(Option[i].Color ? (int16)Option[i].Color : WHITE);
            if (Option[i].Flags & MO_LOCKED)
                Write(Format("  [%c%c%c] %.*s",-PINK,
                    Option[i].isMarked ? '#' : ' ',-GREY,
                    szCol - 5, (const char*) Option[i].Text));
            else
                Write(Format("  [%c%c%c] %.*s",-PINK,
                    Option[i].isMarked ? '*' : ' ',-GREY,
                    szCol - 5, (const char*) Option[i].Text));
            for (j=((i-vStart)/vRows)*szCol+1+activeWin->Left;
                j!=((i-vStart)/vRows)*szCol+1+min(barlen,szCol)+activeWin->Left;j++)
                APutChar(j,((i-vStart)%vRows)+DY+activeWin->Top,
                (AGetChar(j,((i-vStart)%vRows)+DY+activeWin->Top) & 0x0FFF) | 
                ((c == i) ? 0x1000 : 0x0000));
        }
        if (fl & MENU_DESC) {
            ClearScroll();
            if (refused) {
                Color(YELLOW);
                SWrapWrite(3,0,XPrint(refusal),WinSizeX()-2,WIN_MENUDESC);
            } else {
                Color(BLUE);
                SWrapWrite(3,0,XPrint(Option[c].Desc),WinSizeX()-2,WIN_MENUDESC);
            }
            UpdateScrollArea(0,WIN_MENUDESC);
            SetWin(MWin);
        } else if (refused) {
            /* inc-j5yo: with no description pane the refusal draws on the
               menu's title line. */
            Color(YELLOW);
            GotoXY(0,(MWin == WIN_MENUBOX) ? 0 : 1);
            Write(Format("  %.*s",WinSizeX()-2,(const char*) refusal));
        }

InvalidChar:
        {
            int16 oldMode;
            oldMode = GetMode();
            SetMode(MO_DIALOG);
            if (i < 27)
                ch=tolower(GetCharCmd(KY_CMD_ARROW_MODE));
            else
                ch = GetCharCmd(KY_CMD_ARROW_MODE);
            SetMode(oldMode);
            /* inc-j5yo: a refusal message stays until the next key. */
            refused = false;
        }

        switch(ch) {
        case KY_CMD_NORTHEAST:
        case KY_CMD_NORTHWEST:
            if (fl & MENU_DESC) { 
                SetWin(MWin);
                ScrollUp(WIN_MENUDESC);
            } 
            goto InvalidChar;
        case KY_CMD_SOUTHEAST:
        case KY_CMD_SOUTHWEST:
            if (fl & MENU_DESC) { 
                SetWin(MWin);
                ScrollDown(WIN_MENUDESC);
            } 
            goto InvalidChar;
        case KY_CMD_NORTH:
            /* inc-j5yo: skip header rows in both directions. */
            {
                int16 start = c;
                do {
                    if (c > 0)
                        c--;
                    else
                        c = OptionCount - 1;
                } while ((Option[c].Flags & MO_HEADER) && c != start);
            }
            break;
        case KY_CMD_SOUTH:
            {
                int16 start = c;
                do {
                    if (c < OptionCount-1)
                        c++;
                    else  {
                        vStart = 0; 
                        c = 0; 
                    }
                } while ((Option[c].Flags & MO_HEADER) && c != start);
            }
            break;
        case KY_CMD_WEST:
            /* inc-j5yo: step over header rows in the same direction. */
            {
                int16 start = c;
                if (c - vRows >= vStart) {
                    c -= vRows;
                    while ((Option[c].Flags & MO_HEADER) && c - vRows >= vStart
                           && c >= 0 && c != start)
                        c -= vRows;
                }
            }
            break;
        case KY_CMD_EAST:
            /* inc-j5yo: step over header rows in the same direction. */
            {
                int16 start = c;
                if (c + vRows <= min(OptionCount-1,vStart+(vRows*Cols-1))) {
                    c += vRows;
                    while ((Option[c].Flags & MO_HEADER) && c + vRows <=
                           min(OptionCount-1,vStart+(vRows*Cols-1))
                           && c != start)
                        c += vRows;
                }
            }
            break;   
        case KY_TAB:
            /* inc-j5yo: jump to the first selectable row after the next
               header, wrapping to the first group. If no other group
               exists, do nothing. */
            {
                int16 h = -1, k;
                for (k = c + 1; k < OptionCount; k++)
                    if (Option[k].Flags & MO_HEADER) { h = k; break; }
                if (h < 0) {
                    for (k = 0; k < OptionCount; k++)
                        if (Option[k].Flags & MO_HEADER) { h = k; break; }
                    if (h >= 0 && h <= c)
                        h = -1;   /* no other group */
                }
                if (h >= 0) {
                    int16 t = h + 1;
                    while (t < OptionCount && (Option[t].Flags & MO_HEADER))
                        t++;
                    if (t < OptionCount && t != c)
                        c = t;
                }
            }
            break;
        case KY_SPACE:
            /* inc-j5yo: a locked or MO_NOMARK row may not be marked, a
               locked row may not be unmarked, and a full group may not
               take another mark. Each refusal sets a message that shows
               until the next key. */
            if (!Option[c].isMarked) {
                if (Option[c].Flags & (MO_LOCKED | MO_NOMARK)) {
                    refused = true;
                    refusal = OptionReason[c].GetLength()
                        ? OptionReason[c] : "That line cannot change.";
                } else {
                    int16 hdr = MSHeaderOf(Option,OptionCount,c);
                    if (hdr >= 0 && Option[hdr].Cap >= 0 &&
                        MSGroupCount(Option,OptionCount,hdr) >= Option[hdr].Cap) {
                        refused = true;
                        refusal = OptionReason[hdr].GetLength()
                            ? OptionReason[hdr] : "That line cannot change.";
                    } else {
                        Option[c].isMarked = true;
                    }
                }
            } else {
                if (Option[c].Flags & MO_LOCKED) {
                    refused = true;
                    refusal = OptionReason[c].GetLength()
                        ? OptionReason[c] : "That line cannot change.";
                } else {
                    Option[c].isMarked = false;
                }
            }
            break;
        case KY_ENTER:
            Restore();
            /* inc-j5yo phase 2b: record the checklist as Responses so a
               reincarnation can replay it. One Response per marked
               non-header option, Question = title as LMenu does, Answer =
               the option's Val, then one terminator with Answer = -1. */
            if (Mode == MO_CREATE) {
                int16 n = 0;
                for (i=0;i!=OptionCount;i++)
                    if (Option[i].isMarked && !(Option[i].Flags & MO_HEADER))
                        n++;
                if (RInf.nRsp + n + 1 > 128)
                    Error("LMultiSelect: replay record full");
                else {
                    for (i=0;i!=OptionCount;i++)
                        if (Option[i].isMarked && !(Option[i].Flags & MO_HEADER)) {
                            strncpy(RInf.Rsp[RInf.nRsp].Question,title,31);
                            RInf.Rsp[RInf.nRsp].Question[31] = 0;
                            RInf.Rsp[RInf.nRsp].Answer = Option[i].Val;
                            RInf.nRsp++;
                        }
                    strncpy(RInf.Rsp[RInf.nRsp].Question,title,31);
                    RInf.Rsp[RInf.nRsp].Question[31] = 0;
                    RInf.Rsp[RInf.nRsp].Answer = -1;
                    RInf.nRsp++;
                }
            }
            return true;
        case KY_ESC:
            if (fl & MENU_ESC)
            {
                Restore();
                OptionCount = 0;
                return false;
            }
            break;
        case KY_HELP:
            if (help) {
                Restore();
                if (!strchr(help,','))
                    HelpTopic(help);
                else
                {
                    static String a, b;
                    a = Upto(help,",/");
                    b = Right(help,strlen(help) - (a.GetLength()+1));
                    HelpTopic(a,b);
                }
                goto Restart;
            }
            break;
        }
    }
    while(1);
}

/* inc-g045 phase 1: the Learn Spells table widget. A full-width, full-screen
   table with one page per spell level. This phase builds the widget only; the
   caller (Player::LearnSpell) still enters through LMultiSelect. */
bool TextTerm::LearnTable(LearnRow *rows, int16 nRows, const int16 *cap,
                          bool creation, const char *replayKey,
                          const char *help) {
    int16 i, L, p, np, ch, c, vStart, vRows, listBot, descTop, descBot;
    int16 used, nPage;
    int16 pages[10];              /* level of each page, ascending */
    int16 firstRow[10], rowCount[10]; /* page's first index and row count */
    const char *rkey;
    String title, refusal;
    bool refused = false;
    /* inc-g045 phase 3: the summary box shown on Enter. ent holds each
       group's entries in array order; group 0 is "at rest / Learn", 1 is
       "at rest / Forget", 2 is "now, permanently / Learn". */
    String ent[3][64];
    int16 cnt[3];
    String sLines[64];
    int16 nSL, g, e, bleft, btop, bright, bbot, CW;

    rkey = replayKey ? replayKey : "";

    /* Group the flat array into one page per level that has at least one row.
       A page holds the rows of its level in the array's order. */
    np = 0;
    for (L = 1; L <= 9; L++) {
        int16 first = -1, count = 0;
        for (i = 0; i < nRows; i++)
            if (rows[i].Level == L) {
                if (first < 0)
                    first = i;
                count++;
            }
        if (count) {
            pages[np] = L;
            firstRow[np] = first;
            rowCount[np] = count;
            np++;
        }
    }
    if (np == 0)
        return false;

    /* inc-g045: replay. Recorded under MO_CREATE keyed by replayKey; a
       reincarnation replays it here exactly as LMultiSelect/LMenu replay a
       pick. Clear every non-locked mark first, then set the recorded ones. */
    if (Mode == MO_RECREATE) {
        for (i = 0; i < nRows; i++)
            if (!rows[i].Locked)
                rows[i].isMarked = false;
        while (RInf.Rsp[RInf.cRsp].Answer != -1) {
            ASSERT(strncmp(RInf.Rsp[RInf.cRsp].Question,rkey,31) == 0);
            int32 ans = RInf.Rsp[RInf.cRsp++].Answer;
            for (i = 0; i < nRows; i++)
                if (!rows[i].Locked && rows[i].Val == ans)
                    rows[i].isMarked = true;
        }
        ASSERT(strncmp(RInf.Rsp[RInf.cRsp].Question,rkey,31) == 0);
        RInf.cRsp++;   /* consume the terminator */
        return true;
    }

    PrePrompt();

    p = 0;              /* start on the lowest level's page */
    c = 0;              /* cursor on that page's first row */
    vStart = 0;
    Save();
    SetWin(WIN_SCREEN);
    SizeWin(WIN_MENUBOX, 0, 0, WinSizeX() - 1, WinSizeY() - 1);
    SetWin(WIN_MENUBOX);

    /* How many list rows fit above the description pane. */
    descBot = WinSizeY() - 4;             /* last description row */
    descTop = WinSizeY() - 3 - 15;        /* 15 rows tall, clamped below */
    if (descTop < 2 + 2)                  /* keep at least 2 list rows */
        descTop = 2 + 2;
    listBot = descTop - 2;                /* separator sits at descTop-1 */
    vRows = listBot - 1;                  /* list starts at row 2 */

    do {
        SetWin(WIN_MENUBOX);
        Clear();

        /* Outer walls, from the top of the screen. */
        Color(EMERALD);
        for (i = 0; i < WinSizeX(); i++) {
            PutChar(i, 0, GLYPH_STORE_HWALL);
            PutChar(i, WinSizeY() - 1, GLYPH_STORE_HWALL);
        }
        for (i = 1; i < WinSizeY() - 1; i++) {
            PutChar(0, i, GLYPH_STORE_VWALL);
            PutChar(WinSizeX() - 1, i, GLYPH_STORE_VWALL);
        }
        Color(YELLOW);
        PutChar(0, 0, GLYPH_SOLID);
        PutChar(WinSizeX() - 1, 0, GLYPH_SOLID);
        PutChar(0, WinSizeY() - 1, GLYPH_SOLID);
        PutChar(WinSizeX() - 1, WinSizeY() - 1, GLYPH_SOLID);

        /* Title, centered in the top border: level N and its slot count. */
        L = pages[p];
        used = 0;
        for (i = 0; i < nRows; i++)
            if (rows[i].Level == L && rows[i].isMarked && !rows[i].Locked)
                used++;
        title = Format(" == Learn Spells: Level %d (%d of %d slots used) == ",
            (int)L, (int)used, (int)cap[L]);
        Color(WHITE);
        Write(max(1, (WinSizeX() - title.GetLength()) / 2), 0, title);

        /* Column header. */
        Color(WHITE);
        Write(1, 1, Format("%-14s%-18s%-8s%-13s%4s   %s",
            "    Pick Spell", "", "Source", "School", "Mana", "Status"));

        /* List, scrolled with the cursor. */
        SetWin(WIN_MENUBOX);
        nPage = rowCount[p];
        if (c >= vStart + vRows)
            vStart = c - (vRows - 1);
        if (c < vStart || vStart < 0)
            vStart = c;
        for (i = vStart; i < min(nPage, vStart + vRows); i++) {
            int16 ri = firstRow[p] + i;
            LearnRow *r = &rows[ri];
            const char *pick;
            if (r->Locked || (r->NoMark && !r->isMarked))
                pick = "   ";
            else
                pick = r->isMarked ? "[*]" : "[ ]";
            Color(r->Color ? (int16)r->Color : WHITE);
            GotoXY(1, 2 + (i - vStart));
            Write(Format("  %c %s  %-22.22s %-7.7s %-13.13s%4d   %s",
                (c == i) ? '>' : ' ', pick,
                (const char*)r->Spell, (const char*)r->Source,
                (const char*)r->School, (int)r->Mana,
                (const char*)(r->isMarked ? r->StatusMarked
                                          : r->StatusUnmarked)));
        }

        /* Separator above the description pane. */
        Color(EMERALD);
        for (i = 1; i < WinSizeX() - 1; i++)
            PutChar(i, descTop - 1, GLYPH_STORE_HWALL);

        /* Description pane below the list. */
        SetWin(WIN_SCREEN);
        SizeWin(WIN_MENUDESC, 2, descTop, WinSizeX() - 3, descBot);
        ClearScroll();
        if (refused) {
            Color(YELLOW);
            SWrapWrite(3, 0, XPrint(refusal), WinSizeX() - 6, WIN_MENUDESC);
        } else {
            int16 ri = firstRow[p] + c;
            Color(BLUE);
            SWrapWrite(3, 0, XPrint(rows[ri].Desc), WinSizeX() - 6, WIN_MENUDESC);
        }
        UpdateScrollArea(0, WIN_MENUDESC);

        /* inc-g045 phase 3: a horizontal wall between the description pane and
           the bottom key line, drawn like the separator above the pane. The
           pane keeps its 15 rows; the blank row below it holds the wall. */
        SetWin(WIN_MENUBOX);
        Color(EMERALD);
        for (i = 1; i < WinSizeX() - 1; i++)
            PutChar(i, descBot + 1, GLYPH_STORE_HWALL);

        /* Bottom key line. */
        SetWin(WIN_MENUBOX);
        Color(AZURE);
        if (creation)
            Write(1, WinSizeY() - 2,
                "  [Space] Pick  [Tab] Next level  [Enter] Confirm");
        else
            Write(1, WinSizeY() - 2,
                "  [Space] Pick  [Tab] Next level  [Enter] Confirm  [ESC] Cancel");

InvalidChar:
        {
            int16 oldMode;
            oldMode = GetMode();
            SetMode(MO_DIALOG);
            ch = GetCharCmd(KY_CMD_ARROW_MODE);
            SetMode(oldMode);
            /* A refusal message stays until the next key. */
            refused = false;
        }

        switch (ch) {
        case KY_CMD_NORTHEAST:
        case KY_CMD_NORTHWEST:
            SetWin(WIN_MENUBOX);
            ScrollUp(WIN_MENUDESC);
            goto InvalidChar;
        case KY_CMD_SOUTHEAST:
        case KY_CMD_SOUTHWEST:
            SetWin(WIN_MENUBOX);
            ScrollDown(WIN_MENUDESC);
            goto InvalidChar;
        case KY_CMD_NORTH:
            if (nPage) {
                if (c > 0)
                    c--;
                else
                    c = nPage - 1;
            }
            break;
        case KY_CMD_SOUTH:
            if (nPage) {
                if (c < nPage - 1)
                    c++;
                else
                    c = 0;
            }
            break;
        case KY_TAB:
            /* Next page, wrapping to the first. Cursor goes to its first row. */
            p++;
            if (p >= np)
                p = 0;
            c = 0;
            vStart = 0;
            break;
        case KY_SPACE:
            {
                LearnRow *r = &rows[firstRow[p] + c];
                if (!r->isMarked) {
                    if (r->Locked || r->NoMark) {
                        refused = true;
                        refusal = r->Reason.GetLength()
                            ? r->Reason : "That line cannot change.";
                    } else {
                        used = 0;
                        for (i = 0; i < nRows; i++)
                            if (rows[i].Level == pages[p] && rows[i].isMarked
                                && !rows[i].Locked)
                                used++;
                        if (used >= cap[pages[p]]) {
                            refused = true;
                            refusal = Format("Level %d has no free slot.",
                                (int)pages[p]);
                        } else {
                            r->isMarked = true;
                        }
                    }
                } else {
                    if (r->Locked) {
                        refused = true;
                        refusal = r->Reason.GetLength()
                            ? r->Reason : "That line cannot change.";
                    } else {
                        r->isMarked = false;
                    }
                }
            }
            break;
        case KY_ENTER:
            {
                /* inc-g045 phase 3: no box during creation, and none when no
                   non-locked row changed. Those confirm at once. */
                bool changing = false;
                for (i = 0; i < nRows; i++)
                    if (!rows[i].Locked
                        && rows[i].isMarked != rows[i].wasMarked)
                        changing = true;

                if (creation || !changing) {
                    Restore();
                    /* Record the table as Responses so a reincarnation can
                       replay it. One Response per marked non-locked row,
                       Question = replayKey, Answer = the row's Val, then one
                       terminator with Answer = -1. */
                    if (Mode == MO_CREATE) {
                        int16 n = 0;
                        for (i = 0; i < nRows; i++)
                            if (rows[i].isMarked && !rows[i].Locked)
                                n++;
                        if (RInf.nRsp + n + 1 > 128)
                            Error("LearnTable: replay record full");
                        else {
                            for (i = 0; i < nRows; i++)
                                if (rows[i].isMarked && !rows[i].Locked) {
                                    strncpy(RInf.Rsp[RInf.nRsp].Question,
                                        rkey,31);
                                    RInf.Rsp[RInf.nRsp].Question[31] = 0;
                                    RInf.Rsp[RInf.nRsp].Answer = rows[i].Val;
                                    RInf.nRsp++;
                                }
                            strncpy(RInf.Rsp[RInf.nRsp].Question,rkey,31);
                            RInf.Rsp[RInf.nRsp].Question[31] = 0;
                            RInf.Rsp[RInf.nRsp].Answer = -1;
                            RInf.nRsp++;
                        }
                    }
                    return true;
                }

                /* Sort every changed non-locked row into its group, in the
                   array's order (level 1 first). */
                cnt[0] = cnt[1] = cnt[2] = 0;
                for (i = 0; i < nRows; i++) {
                    LearnRow *r = &rows[i];
                    String entry;
                    if (r->Locked || r->isMarked == r->wasMarked)
                        continue;
                    entry = Format("%s (%s, L%d)", (const char*)r->Spell,
                        (const char*)r->Source, (int)r->Level);
                    if (r->isMarked) {
                        g = r->Immediate ? 2 : 0;
                        if (cnt[g] < 64)
                            ent[g][cnt[g]++] = entry;
                    } else {
                        if (cnt[1] < 64)
                            ent[1][cnt[1]++] = entry;
                    }
                }

                /* Build the box's content lines. Empty groups are left out,
                   and a section is left out when it has no line. */
                CW = WinSizeX() - 8;
                if (CW < 20)
                    CW = 20;
                nSL = 0;
                if ((cnt[0] || cnt[1]) && nSL < 64)
                    sLines[nSL++] = "At your next full rest:";
                for (g = 0; g < 3; g++) {
                    const char *pfx;
                    String cur;
                    bool firstEnt;
                    if (!cnt[g])
                        continue;
                    if (g == 2) {
                        if (nSL < 64)
                            sLines[nSL++] = "Now, permanently:";
                        pfx = "  Learn:   ";
                    } else if (g == 0)
                        pfx = "  Learn:   ";
                    else
                        pfx = "  Forget:  ";
                    cur = pfx;
                    firstEnt = true;
                    for (e = 0; e < cnt[g]; e++) {
                        String cand;
                        cand = cur;
                        if (!firstEnt)
                            cand += ", ";
                        cand += (const char*)ent[g][e];
                        if (firstEnt || cand.GetLength() <= CW) {
                            cur = cand;
                            firstEnt = false;
                        } else {
                            if (nSL < 64)
                                sLines[nSL++] = cur;
                            cur = "           ";   /* col after "Learn:   " */
                            cur += (const char*)ent[g][e];
                        }
                    }
                    if (nSL < 64)
                        sLines[nSL++] = cur;
                }
                if (nSL < 64)
                    sLines[nSL++] = "[Enter] Confirm  [ESC] Back to the list";

                /* Size the box to its content, and centre it. */
                CW = 0;
                for (i = 0; i < nSL; i++)
                    if ((int16)sLines[i].GetLength() > CW)
                        CW = (int16)sLines[i].GetLength();
                bleft = (WinSizeX() - (CW + 4)) / 2;
                if (bleft < 1)
                    bleft = 1;
                btop = (WinSizeY() - (nSL + 2)) / 2;
                if (btop < 1)
                    btop = 1;
                bright = bleft + CW + 3;
                bbot = btop + nSL + 1;

                SetWin(WIN_SCREEN);
                Color(EMERALD);
                for (i = bleft; i <= bright; i++) {
                    PutChar(i, btop, GLYPH_STORE_HWALL);
                    PutChar(i, bbot, GLYPH_STORE_HWALL);
                }
                for (i = btop; i <= bbot; i++) {
                    PutChar(bleft, i, GLYPH_STORE_VWALL);
                    PutChar(bright, i, GLYPH_STORE_VWALL);
                }
                Color(YELLOW);
                PutChar(bleft, btop, GLYPH_SOLID);
                PutChar(bright, btop, GLYPH_SOLID);
                PutChar(bleft, bbot, GLYPH_SOLID);
                PutChar(bright, bbot, GLYPH_SOLID);
                /* inc-g045 phase 4: blank every cell inside the walls before
                   writing, so the table underneath cannot show through. One
                   blank column is left after the left wall, where the text
                   lines begin at bleft+2. */
                {
                    int16 bx, by;
                    Color(WHITE);
                    for (by = btop + 1; by <= bbot - 1; by++)
                        for (bx = bleft + 1; bx <= bright - 1; bx++)
                            PutChar(bx, by, ' ');
                }
                Color(WHITE);
                for (i = 0; i < nSL; i++) {
                    GotoXY(bleft + 2, btop + 1 + i);
                    Write((const char*)sLines[i]);
                }

                /* Modal: Enter confirms, ESC returns to the table, anything
                   else is ignored. */
                {
                    int16 bch;
                    bool confirmed = false;
                    do {
                        int16 oldMode;
                        oldMode = GetMode();
                        SetMode(MO_DIALOG);
                        bch = GetCharCmd(KY_CMD_ARROW_MODE);
                        SetMode(oldMode);
                        if (bch == KY_ESC)
                            break;
                        if (bch == KY_ENTER) {
                            confirmed = true;
                            break;
                        }
                    } while (1);

                    if (confirmed) {
                        Restore();
                        if (Mode == MO_CREATE) {
                            int16 n = 0;
                            for (i = 0; i < nRows; i++)
                                if (rows[i].isMarked && !rows[i].Locked)
                                    n++;
                            if (RInf.nRsp + n + 1 > 128)
                                Error("LearnTable: replay record full");
                            else {
                                for (i = 0; i < nRows; i++)
                                    if (rows[i].isMarked && !rows[i].Locked) {
                                        strncpy(RInf.Rsp[RInf.nRsp].Question,
                                            rkey,31);
                                        RInf.Rsp[RInf.nRsp].Question[31] = 0;
                                        RInf.Rsp[RInf.nRsp].Answer = rows[i].Val;
                                        RInf.nRsp++;
                                    }
                                strncpy(RInf.Rsp[RInf.nRsp].Question,rkey,31);
                                RInf.Rsp[RInf.nRsp].Question[31] = 0;
                                RInf.Rsp[RInf.nRsp].Answer = -1;
                                RInf.nRsp++;
                            }
                        }
                        return true;
                    }
                    /* ESC: fall out and let the loop redraw the table on the
                       same page, cursor, scroll and marks. */
                }
            }
            break;
        case KY_ESC:
            if (!creation) {
                Restore();
                return false;
            }
            break;
        case KY_HELP:
            if (help) {
                Restore();
                if (!strchr(help,','))
                    HelpTopic(help);
                else {
                    static String a, b;
                    a = Upto(help,",/");
                    b = Right(help,strlen(help) - (a.GetLength()+1));
                    HelpTopic(a,b);
                }
                /* inc-g045 phase 2: after help, redraw with the page, cursor
                   and list scroll where they were; do not reset to the first
                   row (Restart would). */
            }
            break;
        }
    }
    while(1);
}

int32 TextTerm::FirstSelected()
  {
    cOption = 0;
    do {
      if (cOption >= OptionCount)
        return 0;
      /* inc-j5yo: header rows are never returned. */
      if (!(Option[cOption].Flags & MO_HEADER) && Option[cOption].isMarked)
        return Option[cOption].Val;
      cOption++;
      }
    while(1);
  }
      
int32 TextTerm::NextSelected()
  {
    cOption++;
    do {
      if (cOption >= OptionCount)
        return 0;
      /* inc-j5yo: header rows are never returned. */
      if (!(Option[cOption].Flags & MO_HEADER) && Option[cOption].isMarked)
        return Option[cOption].Val;
      cOption++;
      }
    while(1);
  }


/*****************************************************************************\
*                                 TEXTTERM                                    *
*                              DumpContainers                                 *
\*****************************************************************************/

int16 TextTerm::DumpContainers()
{
  Thing *t; Item *it; 
  /* find all sources */ 
  bool anyGroundItems = false; 

  for (t = p->m->FirstAt(p->x,p->y) ; t ; t = p->m->NextAt(p->x,p->y)) {
    if (t->isItem()) {
      anyGroundItems = true; 
      if (t->isType(T_CHEST) || t->isType(T_CONTAIN) ) 
        LOption(Format("(on ground) %s",(const char*)t->Name(0)),t->myHandle,NULL,0);
    } 
  } 

  if (anyGroundItems)
    LOption("(All Items On Ground)",-2,0,0);

  for (it = p->FirstInv(); it; it = p->NextInv()) {
    if (it->isType(T_CONTAIN) || it->isType(T_CHEST))
      LOption(it->Name(0),it->myHandle,NULL,0);
  } 

  int32 c1 = LMenu(MENU_ESC|MENU_BORDER,"Dump What?",WIN_MENUBOX,0,0);
  if (c1 == -1) 
    return -1; 
  Thing * ct1 = NULL; 
  Container * cc1 = NULL;
  if (c1 != -2) {
    ct1 = oThing(c1);
    ASSERT(ct1);
    ASSERT(ct1->isType(T_CONTAIN) || ct1->isType(T_CHEST));
    cc1 = (Container *)ct1; 
  } 

  LOption("(Onto The Ground)",-2,0,0);
  for (it = p->FirstInv(); it; it = p->NextInv()) {
    if (it == ct1) continue; 
    if (it->isType(T_CONTAIN) || it->isType(T_CHEST))
      LOption(it->Name(0),it->myHandle,NULL,0);
  } 
  for (t = p->m->FirstAt(p->x,p->y) ; t ; t = p->m->NextAt(p->x,p->y)) {
    if (t->isItem() && t != ct1) {
      if (t->isType(T_CHEST) || t->isType(T_CONTAIN) ) 
        LOption(Format("(on ground) %s",(const char*)t->Name(0)),t->myHandle,NULL,0);
    } 
  } 

  int32 c2 = LMenu(MENU_ESC|MENU_BORDER,"Place Them Where?",WIN_MENUBOX,0,0);
  if (c2 == -1) return -1; 
  if (c2 == -2 && c1 == -2) return -1; 

  EventInfo e;
  e.Clear();
  e.EPActor = p; 
  if (c2 == -2) { 
    return cc1->DumpOutContents(e);
  } else {
    /* put things from ct1 into ct2 */
    Thing * ct2 = oThing(c2);
    ASSERT(ct2);
    ASSERT(ct2->isType(T_CONTAIN) || ct2->isType(T_CHEST));
    Container * cc2 = (Container *)ct2; 
    e.EItem = cc2; 

    if (!ct1) {
      /* put things from ground into ct2 */
      e.EItem2 = (Item *)p->m->FirstAt(p->x,p->y);
    } else {
      /* put things from container ct1 into ct2 */
      e.EItem2 = (Item *)oThing(cc1->Contents); 
    } 
    return cc2->PourInContents(e);
  } 
} 
