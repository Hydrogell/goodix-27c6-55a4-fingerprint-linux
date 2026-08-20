#!/usr/bin/env bash
# Install the Goodix 55a4 fingerprint driver, and leave nothing behind.
#
# Everything is built in a temporary directory and deleted afterwards. When this
# finishes, your home directory is exactly as it was. What stays on the system:
#
#   /opt/libfprint-goodix/lib64/libfprint-2.so.*      the patched library
#   /etc/systemd/system/fprintd.service.d/10-*.conf   points fprintd at it
#   /etc/systemd/system/fprintd-sleep-fix.service     restarts fprintd around suspend
#   /etc/udev/rules.d/61-goodix-no-autosuspend.rules  keeps the sensor powered
#   one SELinux policy module (enforcing systems only)
#
# scripts/uninstall-system.sh removes all five.
#
# Your distribution's own libfprint is neither replaced nor downgraded — only
# fprintd is redirected, every other program keeps using the system library.
#
# If you want to read the code, run the test harness, or work on the driver,
# use ./setup.sh instead: it keeps the build tree so you can rebuild and hack.
#
#   ./install.sh          install and clean up
#   ./setup.sh            developer path, keeps ./work/
set -e

REPO="$(cd "$(dirname "$0")" && pwd)"
# Full 40-character commit IDs on purpose, not abbreviations. A 7-character
# prefix is 28 bits: anyone able to push to those repositories could add a commit
# sharing it and make the checkout ambiguous. The libfprint pin matters for a
# second reason too — the patch's context hunks apply only to that revision, and
# a branch tip moves.
FORK_URL="https://github.com/TheWeirdDev/libfprint.git"
FORK_REV="d1ca62a801aa565e67d1a2a47aaa7a33232b7990"
DUMP_URL="https://github.com/goodix-fp-linux-dev/goodix-fp-dump.git"
DUMP_REV="cc43bb3b3154a0bccc0412ae024013c7e1923139"

# Check out an exact commit and refuse to continue if we did not land on it.
pin() {  # pin <dir> <full-sha>
  git -C "$1" checkout -q "$2"
  got="$(git -C "$1" rev-parse HEAD)"
  [ "$got" = "$2" ] || {
    echo "ERROR: $1 is at $got, expected $2 — refusing to build." >&2
    exit 1
  }
}

if [ "$(id -u)" -eq 0 ]; then
  echo "Run this as your normal user, not with sudo." >&2
  echo "It builds unprivileged and asks for sudo only for the install step." >&2
  exit 1
fi

for c in git meson ninja python3 gcc; do
  command -v "$c" >/dev/null 2>&1 || {
    echo "missing: $c" >&2
    echo "On Fedora:" >&2
    echo "  sudo dnf install meson ninja-build gcc gcc-c++ libgusb-devel \\" >&2
    echo "      nss-devel openssl-devel cairo-devel glib2-devel opencv-devel \\" >&2
    echo "      gobject-introspection-devel libgudev-devel pixman-devel \\" >&2
    echo "      doctest-devel cmake git" >&2
    exit 1
  }
done

# /var/tmp rather than /tmp: the build is ~200 MB and /tmp is often a tmpfs,
# i.e. RAM. Overridable for anyone who wants it elsewhere.
BUILD="$(mktemp -d -p "${GOODIX_BUILD_DIR:-/var/tmp}" goodix55a4.XXXXXXXX)"
cleanup() {
  echo "== cleaning up the build tree =="
  rm -rf "$BUILD" 2>/dev/null
  # Verify rather than assume: the install step runs as root inside $BUILD, so a
  # root-owned file left behind would defeat the whole point of building here.
  if [ -e "$BUILD" ]; then
    echo "WARNING: $BUILD could not be removed completely." >&2
    echo "         Remove it with:  sudo rm -rf $BUILD" >&2
  fi
}
trap cleanup EXIT
echo "building in $BUILD (removed when this finishes)"

echo "== 1/3 build the patched libfprint =="
git clone -q --branch 55b4-experimental "$FORK_URL" "$BUILD/libfprint"
pin "$BUILD/libfprint" "$FORK_REV"
git -C "$BUILD/libfprint" apply "$REPO/patches/55a4-driver.patch"
( cd "$BUILD/libfprint" \
  && meson setup _build -Ddrivers=goodixtls55x4 -Dintrospection=false \
       -Ddoc=false >/dev/null \
  && ninja -C _build >/dev/null )
echo "   built"

# The sensor only accepts the all-zero TLS key once a fixed public blob has been
# written to it, and that write lives in goodix-fp-dump's Python driver. It is
# needed exactly once, so it gets a throwaway venv holding only what the write
# path imports — no OpenCV, no numpy, which is the difference between ~15 MB and
# ~250 MB. The research tooling in ./setup.sh does pull those in.
echo "== 2/3 prepare one-time key provisioning =="
git clone -q "$DUMP_URL" "$BUILD/goodix-fp-dump"
pin "$BUILD/goodix-fp-dump" "$DUMP_REV"
python3 -m venv "$BUILD/goodix-fp-dump/.venv"
"$BUILD/goodix-fp-dump/.venv/bin/pip" install -q pyusb crcmod python-periphery
# stub: protocol.py imports spidev unconditionally, for the SPI variants of this
# sensor family. Ours is USB, so nothing ever calls into it — but the import has
# to resolve or driver_55x4 will not load.
printf 'class SpiDev:\n    pass\n' > "$BUILD/goodix-fp-dump/spidev.py"
install -m0644 "$REPO/scripts/provision_psk.py" "$BUILD/goodix-fp-dump/"
echo "   ready"

echo "== 3/3 install (needs sudo) =="
sudo env \
  FP_SO_SRC="$BUILD/libfprint/_build/libfprint" \
  FP_PYDIR="$BUILD/goodix-fp-dump" \
  bash "$REPO/scripts/install-system.sh"
