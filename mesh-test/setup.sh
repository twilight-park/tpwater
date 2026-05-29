#!/bin/sh
# setup.sh — install Tcl + jbr packages + build jbr::mesh on a Pi
# Run from the mesh-test directory on the Pi.
# Usage: bash ~/mesh-test/setup.sh

set -e
cd "$(dirname "$0")"

echo "=== Installing tclsh and build tools ==="
sudo apt-get install -y tcl tcl-dev gcc make

echo "=== Installing critcl ==="
mkdir -p ~/bin ~/lib
cp critcl/critcl ~/bin/critcl
chmod +x ~/bin/critcl
cp -r critcl/lib/* ~/lib/
# critcl expects ~/bin/tclsh — symlink system tclsh if not present
if [ ! -f ~/bin/tclsh ]; then
    ln -sf "$(which tclsh)" ~/bin/tclsh
fi

echo "=== Installing jbr Tcl packages ==="
mkdir -p ~/lib/tcl8/site-tcl/jbr
for f in jbr/*.tcl; do
    name=$(basename "$f" .tcl)
    cp "$f" ~/lib/tcl8/site-tcl/jbr/${name}-1.0.tm
done
echo "jbr packages installed"

echo "=== Building jbr::mesh ==="
cd mesh
make install
cd ..

echo ""
echo "=== Setup complete ==="
echo "Run hub on dev machine:  tclsh hub.tcl"
echo "Run on listener Pi:      tclsh listener.tcl <hub-ip>"
echo "Run on office Pi:        tclsh office.tcl <hub-ip>"
