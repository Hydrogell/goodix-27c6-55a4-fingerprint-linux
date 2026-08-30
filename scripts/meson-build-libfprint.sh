#!/usr/bin/env bash
# Configure and compile patched libfprint into $1/build.
#
# setup.sh used to run `meson setup _build --wipe`. On a fresh clone there is
# no build tree yet, and meson 0.61 (Ubuntu 22.04) refuses --wipe when nothing
# exists to wipe; current meson quietly accepts that, which is why the failure
# only ever showed up off the development machine (#3). A dedicated build/
# recreated from scratch needs no --wipe on any meson version.
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
