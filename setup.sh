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

# Full 40-character commit IDs on purpose — see the note in install.sh.
FORK_REV="d1ca62a801aa565e67d1a2a47aaa7a33232b7990"
DUMP_REV="cc43bb3b3154a0bccc0412ae024013c7e1923139"

pin() {  # pin <dir> <full-sha>
  git -C "$1" checkout -q "$2"
  got="$(git -C "$1" rev-parse HEAD)"
  [ "$got" = "$2" ] || {
    echo "ERROR: $1 is at $got, expected $2 — refusing to build." >&2
    exit 1
  }
}

echo "== 1/2 libfprint 55a4 driver (base 55b4-experimental + our patch) =="
if [ ! -d "$WORK/twd-libfprint/.git" ]; then
  git clone --branch 55b4-experimental \
    https://github.com/TheWeirdDev/libfprint.git "$WORK/twd-libfprint"
  # Pin the base: the patch's context hunks only apply to this revision, and the
  # branch tip moves. Without this, an upstream commit silently breaks setup.
  pin "$WORK/twd-libfprint" "$FORK_REV"
fi
cd "$WORK/twd-libfprint"
git checkout -- . 2>/dev/null || true
git apply "$REPO/patches/55a4-driver.patch"
meson setup _build -Ddrivers=goodixtls55x4 -Dintrospection=false -Ddoc=false --wipe >/dev/null
ninja -C _build
echo "   -> $WORK/twd-libfprint/_build/examples/img-capture"

echo "== 2/2 goodix-fp-dump Python reference (known-good, pinned) =="
if [ ! -d "$WORK/goodix-fp-dump/.git" ]; then
  git clone https://github.com/goodix-fp-linux-dev/goodix-fp-dump.git "$WORK/goodix-fp-dump"
  pin "$WORK/goodix-fp-dump" "$DUMP_REV"
fi
cd "$WORK/goodix-fp-dump"
[ -d .venv ] || python3 -m venv .venv
.venv/bin/pip install -q pyusb crcmod numpy opencv-python-headless python-periphery
# stub: protocol.py imports spidev unconditionally, for the SPI variants of this
# sensor family. Ours is USB, so nothing calls into it — but the import has to
# resolve or driver_55x4 will not load.
printf 'class SpiDev:\n    pass\n' > spidev.py
# Provisioning and research helpers live alongside the reference tool. Listed
# explicitly rather than globbed, so a renamed or missing file fails loudly here
# instead of surfacing as a confusing ImportError later.
install -m0644 "$REPO/scripts/provision_psk.py" "$REPO/scripts/led_gui.py" .
install -m0644 "$REPO/scripts/research/"{probe_psk,py_relay_probe,py_probe_cseq,dump_snapshot,decode_cmds}.py .
echo "   -> $WORK/goodix-fp-dump  (Python reference tooling)"

echo ""
echo "DONE. Native driver test (needs sensor + udev uaccess, no sudo):"
echo "  G_MESSAGES_DEBUG=all $WORK/twd-libfprint/_build/examples/img-capture /tmp/out.pgm"
