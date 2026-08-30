#!/usr/bin/env bash
# Printed when a build tool is missing. Fedora was the original target;
# Debian/Ubuntu package names are from a ThinkPad E14 Gen 2 bring-up (#2).
cat <<'EOF' >&2
On Fedora:
  sudo dnf install meson ninja-build gcc gcc-c++ libgusb-devel nss-devel \
      openssl-devel cairo-devel glib2-devel opencv-devel \
      gobject-introspection-devel libgudev-devel pixman-devel \
      doctest-devel cmake git

On Debian/Ubuntu:
  sudo apt install meson ninja-build gcc g++ cmake pkg-config git \
      libglib2.0-dev libgusb-dev libusb-1.0-0-dev libnss3-dev libssl-dev \
      libcairo2-dev libpixman-1-dev libgudev-1.0-dev libopencv-dev doctest-dev
EOF
