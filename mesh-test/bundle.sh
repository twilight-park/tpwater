#!/bin/sh
# bundle.sh — run on dev machine to package everything needed for a Pi
# into the mesh-test directory. Then scp mesh-test/ to each Pi.
# Usage: bash bundle.sh

set -e
cd "$(dirname "$0")"

echo "=== Bundling critcl ==="
mkdir -p critcl/lib
cp ~/bin/critcl critcl/critcl
cp -r ~/lib/critcl-* critcl/lib/
cp -r ~/lib/critcl_* critcl/lib/
cp -r ~/lib/stubs_*  critcl/lib/

echo "=== Bundling jbr::msg (pure Tcl) ==="
mkdir -p jbr
cp ~/src/jbr.tcl/msg/msg.tcl         jbr/msg.tcl
cp ~/src/jbr.tcl/cron.tcl            jbr/cron.tcl
cp ~/src/jbr.tcl/func.tcl            jbr/func.tcl
cp ~/src/jbr.tcl/unix.tcl            jbr/unix.tcl
cp ~/src/jbr.tcl/with.tcl            jbr/with.tcl
cp ~/src/jbr.tcl/seconds.tcl         jbr/seconds.tcl
cp ~/src/jbr.tcl/print.tcl           jbr/print.tcl

echo "=== Bundling jbr::mesh source ==="
mkdir -p mesh
cp ~/src/jbr.tcl/mesh/mesh.tcl mesh/
cat > mesh/Makefile << 'EOF'
CRITCL = ~/bin/critcl
all:
	$(CRITCL) -pkg mesh.tcl
install: all
	mkdir -p $(HOME)/lib/tcl8/lib
	rm -rf $(HOME)/lib/tcl8/lib/mesh
	cp -r lib/mesh $(HOME)/lib/tcl8/lib/mesh
clean:
	rm -rf lib
EOF

echo ""
echo "=== Bundle ready ==="
echo "Next steps:"
echo "  scp -r $(pwd) listener:~/"
echo "  scp -r $(pwd) office:~/"
echo "  ssh listener 'bash ~/mesh-test/setup.sh'"
echo "  ssh office   'bash ~/mesh-test/setup.sh'"
