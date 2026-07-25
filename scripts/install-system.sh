#!/usr/bin/env bash
# Make the system's fprintd use our patched libfprint (with the 55a4 driver)
# PERMANENTLY, without replacing or downgrading the distro libfprint package.
#
# Approach (clean + reversible):
#   - install our libfprint-2.so.* into /opt/libfprint-goodix/lib64
#   - a systemd drop-in points ONLY fprintd.service at it via LD_LIBRARY_PATH
#   - the system libfprint (1.94.10) stays the default for every other app
#   - PAM is wired by authselect's `with-fingerprint` feature (enable if absent)
#
# Reverse with: scripts/uninstall-system.sh
set -e
REPO="$(cd "$(dirname "$0")/.." && pwd)"
# Where the build lives. Defaults to the developer tree left by ./setup.sh;
# ./install.sh overrides both to a temporary directory it deletes afterwards.
SO_SRC="${FP_SO_SRC:-$REPO/work/twd-libfprint/_build/libfprint}"
PYDIR="${FP_PYDIR:-$REPO/work/goodix-fp-dump}"
DEST="/opt/libfprint-goodix/lib64"
DROPIN="/etc/systemd/system/fprintd.service.d"

if [ ! -f "$SO_SRC/libfprint-2.so.2.0.0" ]; then
  echo "ERROR: no build found in $SO_SRC" >&2
  echo "Run one of:" >&2
  echo "  cd $REPO && ./install.sh    # build, install, clean up" >&2
  echo "  cd $REPO && ./setup.sh      # keep the build tree, then re-run this" >&2
  exit 1
fi

echo "== 1/6 install our libfprint into $DEST =="
install -d "$DEST"
install -m0755 "$SO_SRC/libfprint-2.so.2.0.0" "$DEST/"
ln -sf libfprint-2.so.2.0.0 "$DEST/libfprint-2.so.2"
ln -sf libfprint-2.so.2     "$DEST/libfprint-2.so"
restorecon -R "$DEST" 2>/dev/null || true   # correct SELinux labels

echo "== 2/6 systemd drop-in: point ONLY fprintd at it =="
install -d "$DROPIN"
cat > "$DROPIN/10-goodix55a4.conf" <<EOF
[Service]
Environment=LD_LIBRARY_PATH=$DEST
EOF

echo "== 3/6 provision the sensor key (one-time) =="
# The driver talks TLS-PSK with an all-zero key, which the sensor only accepts
# once a fixed, publicly known blob has been written into it (it ships in
# goodix-fp-dump and is not device-specific). The C driver deliberately only
# *checks* for it and refuses to activate otherwise — on an untouched sensor
# that looks like an unexplained failure, so provision it here, once.
# This writes slot 0xbb010003 only; Windows keeps its key material in slot
# 0xbb010002, which is left alone. See the dual-boot note in README.
# Stop it politely: SIGKILL denies fprintd the chance to close the device, and
# the driver clears the sensor LED on close — a hard kill leaves the light on
# with nothing left to switch it off.
systemctl stop fprintd.service 2>/dev/null || true
pkill -TERM -x fprintd 2>/dev/null || true
sleep 2
pkill -9 -x fprintd 2>/dev/null || true   # only if it ignored the polite ask
sleep 1
PYBIN="${FP_PYBIN:-$PYDIR/.venv/bin/python}"
if [ -x "$PYBIN" ]; then
  install -m0644 "$REPO/scripts/provision_psk.py" "$PYDIR/"
  ( cd "$PYDIR" && "$PYBIN" provision_psk.py ) || {
      echo "   WARNING: key provisioning failed — the driver may not activate." >&2
      echo "   retry: cd $PYDIR && .venv/bin/python provision_psk.py" >&2
  }
else
  echo "   skipped: no $PYBIN (run ./install.sh or ./setup.sh first)"
fi

echo "== 4/6 SELinux: stop logging the harmless nr_hugepages probe =="
# fprintd now loads our libfprint, which links OpenCV for the SIGFM matcher.
# OpenCV pulls in Intel TBB, whose scalable allocator reads
# /proc/sys/vm/nr_hugepages at init and falls back to normal pages when it
# cannot. fprintd's SELinux domain may not read that file, so every start
# produces a denial and, on Fedora, a setroubleshoot desktop alert. Nothing is
# broken by it. scripts/goodix_fprintd.te is a `dontaudit` rule: it grants
# fprintd no access at all, it only keeps the denial out of the audit log.
# Load it before the restart below, so the first start is already quiet.
if [ "$(getenforce 2>/dev/null)" != "Enforcing" ]; then
  echo "   skipped: SELinux is not enforcing here (permissive still logs the"
  echo "   denial — load it by hand, see scripts/goodix_fprintd.te)"
elif ! command -v checkmodule >/dev/null 2>&1 \
  || ! command -v semodule_package >/dev/null 2>&1 \
  || ! command -v semodule >/dev/null 2>&1; then
  echo "   skipped: needs checkmodule (checkpolicy) and semodule (policycoreutils)."
  echo "   The driver works without it; you just get an SELinux alert about"
  echo "   nr_hugepages whenever fprintd starts. To silence it later:"
  echo "     sudo dnf install checkpolicy policycoreutils"
  echo "     sudo bash $REPO/scripts/install-system.sh"
else
  SEDIR=$(mktemp -d 2>/dev/null) || SEDIR=
  if [ -z "$SEDIR" ]; then
    echo "   skipped: could not create a working directory"
  else
    if checkmodule -M -m -o "$SEDIR/goodix_fprintd.mod" "$REPO/scripts/goodix_fprintd.te" \
       && semodule_package -o "$SEDIR/goodix_fprintd.pp" -m "$SEDIR/goodix_fprintd.mod" \
       && semodule -i "$SEDIR/goodix_fprintd.pp"; then
      echo "   loaded policy module goodix_fprintd (undo: semodule -r goodix_fprintd)"
    else
      echo "   WARNING: could not load goodix_fprintd.te — continuing without it." >&2
      echo "   Harmless: fprintd still works, it will just log a denial about" >&2
      echo "   nr_hugepages on every start." >&2
    fi
    rm -rf "$SEDIR"
  fi
fi

echo "== 5/6 restart fprintd =="
systemctl stop fprintd.service 2>/dev/null || true
pkill -TERM -x fprintd 2>/dev/null || true
sleep 1
systemctl daemon-reload
systemctl restart fprintd.service 2>/dev/null || true   # dbus-activated; ok if not running

echo "== 6/6 PAM (authselect with-fingerprint) =="
if authselect current 2>/dev/null | grep -q with-fingerprint; then
  echo "   with-fingerprint already enabled"
else
  authselect enable-feature with-fingerprint && echo "   enabled with-fingerprint"
fi

echo "== template protection check =="
# fprintd stores enrolled fingerprints as plain files under /var/lib/fprint —
# it does not encrypt them (a long-standing upstream complaint). They are
# root-only, but on an unencrypted disk anyone who can pull the drive can read
# them, and a fingerprint template is enough to reconstruct an image close to
# the original. Say so plainly rather than letting the user assume otherwise.
FP_SRC=$(findmnt -no SOURCE --target /var/lib/fprint 2>/dev/null | sed 's/\[.*//')
[ -n "$FP_SRC" ] || FP_SRC=$(findmnt -no SOURCE --target /var 2>/dev/null | sed 's/\[.*//')
FP_ENC=no
probe="$FP_SRC"
for _ in 1 2 3 4; do
    t=$(lsblk -no TYPE "$probe" 2>/dev/null | head -1)
    [ "$t" = "crypt" ] && { FP_ENC=yes; break; }
    pk=$(lsblk -no PKNAME "$probe" 2>/dev/null | head -1)
    [ -n "$pk" ] || break
    probe="/dev/$pk"
done
if [ "$FP_ENC" = yes ]; then
    echo "   templates are on an encrypted volume — good"
else
    echo "   WARNING: /var/lib/fprint is on an UNENCRYPTED partition ($FP_SRC)."
    echo "   fprintd stores templates as plain files. They are root-only, but on"
    echo "   an unencrypted disk anyone who can pull the drive can read them, and"
    echo "   a template is enough to reconstruct an image close to the original."
    echo "   Use full-disk encryption (LUKS) and keep SELinux/AppArmor enforcing."
fi
if [ "$(getenforce 2>/dev/null)" = "Enforcing" ]; then
    echo "   SELinux: enforcing — good"
else
    echo "   WARNING: SELinux is not enforcing; it is the only protection"
    echo "   upstream libfprint recommends for templates against other processes."
fi

echo ""
echo "DONE. Verify:  fprintd-list \$USER   (should show the Goodix 55X4 device)"
echo "               fprintd-verify        (place finger)"
echo "Undo:          sudo $REPO/scripts/uninstall-system.sh"
