
#if USE_TK_STUBS

#if TCL_MAJOR_VERSION >= 9
    /* Tk 9+: Use extern declarations - stubs library provides definitions */
    extern const TkStubs *tkStubsPtr;
    extern const struct TkPlatStubs *tkPlatStubsPtr;
    extern const struct TkIntStubs *tkIntStubsPtr;
    extern const struct TkIntPlatStubs *tkIntPlatStubsPtr;
    extern const struct TkIntXlibStubs *tkIntXlibStubsPtr;

  static int
  MyInitTkStubs (Tcl_Interp *ip)
  {
    if (Tk_InitStubs(ip, "9", 0) == NULL) return 0;
    return 1;
  }
#else
    /* Tk 8.x: Define stub pointers */
    const TkStubs *tkStubsPtr;
    const struct TkPlatStubs *tkPlatStubsPtr;
    const struct TkIntStubs *tkIntStubsPtr;
    const struct TkIntPlatStubs *tkIntPlatStubsPtr;
    const struct TkIntXlibStubs *tkIntXlibStubsPtr;

  static int
  MyInitTkStubs (Tcl_Interp *ip)
  {
    if (Tcl_PkgRequireEx(ip, "Tk", "8.1", 0, (ClientData*) &tkStubsPtr) == NULL)      return 0;
    if (tkStubsPtr == NULL || tkStubsPtr->hooks == NULL) {
      Tcl_SetResult(ip, "This extension requires Tk stubs-support.", TCL_STATIC);
      return 0;
    }
    tkPlatStubsPtr = tkStubsPtr->hooks->tkPlatStubs;
    tkIntStubsPtr = tkStubsPtr->hooks->tkIntStubs;
    tkIntPlatStubsPtr = tkStubsPtr->hooks->tkIntPlatStubs;
    tkIntXlibStubsPtr = tkStubsPtr->hooks->tkIntXlibStubs;
    return 1;
  }
#endif
#endif
