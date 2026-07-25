#!/usr/bin/env bash
# Install the Goodix 55a4 fingerprint driver, and leave nothing behind.
#
# Everything is built in a temporary directory and deleted afterwards. When this
# finishes, your home directory is exactly as it was. What stays on the system:
#
#   /opt/libfprint-goodix/lib64/libfprint-2.so.*      the patched library
#   /etc/systemd/system/fprintd.service.d/10-*.conf   points fprintd at it
#   one SELinux policy module (enforcing systems only)
#
# scripts/uninstall-system.sh removes all three.
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
FORK_URL="https://github.com/TheWeirdDev/libfprint.git"
FORK_REV="d1ca62a"          # the patch's context hunks apply only to this
DUMP_URL="https://github.com/goodix-fp-linux-dev/goodix-fp-dump.git"
DUMP_REV="cc43bb3"

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
  rm -rf "$BUILD"
}
trap cleanup EXIT
echo "building in $BUILD (removed when this finishes)"

echo "== 1/3 build the patched libfprint =="
git clone -q --branch 55b4-experimental "$FORK_URL" "$BUILD/libfprint"
( cd "$BUILD/libfprint" && git checkout -q "$FORK_REV" )
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
( cd "$BUILD/goodix-fp-dump" && git checkout -q "$DUMP_REV" )
python3 -m venv "$BUILD/goodix-fp-dump/.venv"
"$BUILD/goodix-fp-dump/.venv/bin/pip" install -q pyusb crcmod python-periphery
printf 'class SpiDev:\n    pass\n' > "$BUILD/goodix-fp-dump/spidev.py"
install -m0644 "$REPO/scripts/provision_psk.py" "$BUILD/goodix-fp-dump/"
echo "   ready"

echo "== 3/3 install (needs sudo) =="
sudo env \
  FP_SO_SRC="$BUILD/libfprint/_build/libfprint" \
  FP_PYDIR="$BUILD/goodix-fp-dump" \
  bash "$REPO/scripts/install-system.sh"
