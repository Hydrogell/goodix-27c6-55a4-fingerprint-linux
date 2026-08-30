#!/usr/bin/env bash
# Configure and compile patched libfprint into $1/build.
#
# TheWeirdDev ships a stub _build/ (ignore files only). `meson setup --wipe`
# requires a real build tree, and `meson setup _build` fails because that
# directory already exists. A separate `build/` directory avoids both.
set -e
SRC="$1"
if [ ! -d "$SRC" ] || [ ! -f "$SRC/meson.build" ]; then
  echo "meson-build-libfprint: not a libfprint source tree: $SRC" >&2
  exit 1
fi
rm -rf "$SRC/build"
meson setup "$SRC/build" "$SRC" \
  -Ddrivers=goodixtls55x4 -Dintrospection=false -Ddoc=false
ninja -C "$SRC/build"
