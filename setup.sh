#!/usr/bin/env bash
# Reconstruct the FULL working environment for the Goodix 27c6:55a4 driver work.
# Everything lives under this repo's work/ dir (persistent home, NOT /tmp).
# Re-run any time (idempotent). Needs: meson ninja-build gcc gcc-c++ libgusb-devel
# nss-devel openssl-devel cairo-devel glib2-devel opencv-devel
# gobject-introspection-devel libgudev-devel pixman-devel doctest-devel cmake git
set -e
REPO="$(cd "$(dirname "$0")" && pwd)"
WORK="$REPO/work"
mkdir -p "$WORK"

echo "== 1/2 libfprint 55a4 driver (base 55b4-experimental d1ca62a + our patch) =="
if [ ! -d "$WORK/twd-libfprint/.git" ]; then
  git clone --branch 55b4-experimental \
    https://github.com/TheWeirdDev/libfprint.git "$WORK/twd-libfprint"
  # Pin the base: the patch's context hunks only apply to this revision, and the
  # branch tip moves. Without this, an upstream commit silently breaks setup.
  ( cd "$WORK/twd-libfprint" && git checkout d1ca62a )
fi
cd "$WORK/twd-libfprint"
git checkout -- . 2>/dev/null || true
git apply "$REPO/patches/55a4-driver.patch"
meson setup _build -Ddrivers=goodixtls55x4 -Dintrospection=false -Ddoc=false --wipe >/dev/null
ninja -C _build
echo "   -> $WORK/twd-libfprint/_build/examples/img-capture"

echo "== 2/2 goodix-fp-dump Python reference (known-good, pinned cc43bb3) =="
if [ ! -d "$WORK/goodix-fp-dump/.git" ]; then
  git clone https://github.com/goodix-fp-linux-dev/goodix-fp-dump.git "$WORK/goodix-fp-dump"
  ( cd "$WORK/goodix-fp-dump" && git checkout cc43bb3 )
fi
cd "$WORK/goodix-fp-dump"
[ -d .venv ] || python3 -m venv .venv
.venv/bin/pip install -q pyusb crcmod numpy opencv-python-headless python-periphery
printf 'class SpiDev:\n    pass\n' > spidev.py          # stub: protocol.py imports SPI we don't use
# provisioning + research helpers live alongside the reference tool
cp "$REPO/scripts/"*.py . 2>/dev/null || true
cp "$REPO/scripts/research/"*.py . 2>/dev/null || true
echo "   -> $WORK/goodix-fp-dump  (Python reference tooling)"

echo ""
echo "DONE. Native driver test (needs sensor + udev uaccess, no sudo):"
echo "  G_MESSAGES_DEBUG=all $WORK/twd-libfprint/_build/examples/img-capture /tmp/out.pgm"
