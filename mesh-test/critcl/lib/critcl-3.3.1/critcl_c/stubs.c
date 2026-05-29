
#line 1 "MyInitTclStubs"

#if USE_TCL_STUBS
#if TCL_MAJOR_VERSION >= 9
  /* Tcl 9+: Use extern declarations - stubs library provides definitions */
  extern const TclStubs *tclStubsPtr;
  extern const TclPlatStubs *tclPlatStubsPtr;
  extern const struct TclIntStubs *tclIntStubsPtr;
  extern const struct TclIntPlatStubs *tclIntPlatStubsPtr;

  static int
  MyInitTclStubs (Tcl_Interp *ip)
  {
    if (Tcl_InitStubs(ip, "$mintcl", 0) == NULL) {
      return 0;
    }
    return 1;
  }
#else
  /* Tcl 8.x: Define stub pointers and use HeadOfInterp approach */
  $stubs
  $platstubs
  const struct TclIntStubs *tclIntStubsPtr;
  const struct TclIntPlatStubs *tclIntPlatStubsPtr;

  static int
  MyInitTclStubs (Tcl_Interp *ip)
  {
    typedef struct {
      char *result;
      Tcl_FreeProc *freeProc;
      int errorLine;
      TclStubs *stubTable;
    } HeadOfInterp;

    HeadOfInterp *hoi = (HeadOfInterp*) ip;

    if (hoi->stubTable == NULL || hoi->stubTable->magic != TCL_STUB_MAGIC) {
      hoi->result = "This extension requires stubs-support.";
      hoi->freeProc = TCL_STATIC;
      return 0;
    }

    tclStubsPtr = hoi->stubTable;

    if (Tcl_PkgRequire(ip, "Tcl", "$mintcl", 0) == NULL) {
      tclStubsPtr = NULL;
      return 0;
    }

    if (tclStubsPtr->hooks != NULL) {
	tclPlatStubsPtr = tclStubsPtr->hooks->tclPlatStubs;
	tclIntStubsPtr = tclStubsPtr->hooks->tclIntStubs;
	tclIntPlatStubsPtr = tclStubsPtr->hooks->tclIntPlatStubs;
    }

    return 1;
  }
#endif
#endif
