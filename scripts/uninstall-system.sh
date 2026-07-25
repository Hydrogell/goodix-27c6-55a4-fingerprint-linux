#!/usr/bin/env bash
# Revert scripts/install-system.sh: system fprintd goes back to the stock
# distro libfprint. Enrolled prints in /var/lib/fprint are left untouched
# (delete with `fprintd-delete $USER` if wanted).
set -e
DROPIN="/etc/systemd/system/fprintd.service.d/10-goodix55a4.conf"

echo "== remove systemd drop-in =="
rm -f "$DROPIN"
rmdir --ignore-fail-on-non-empty /etc/systemd/system/fprintd.service.d 2>/dev/null || true

echo "== remove installed lib =="
rm -rf /opt/libfprint-goodix

echo "== remove SELinux policy module =="
# install-system.sh loads scripts/goodix_fprintd.te on enforcing systems, to
# keep OpenCV/TBB's nr_hugepages probe out of the audit log.
if ! command -v semodule >/dev/null 2>&1; then
  echo "   skipped: semodule not available"
elif ! semodule -l 2>/dev/null | grep -qE '^goodix_fprintd([[:space:]]|$)'; then
  echo "   not loaded, nothing to do"
elif semodule -r goodix_fprintd >/dev/null 2>&1; then
  echo "   removed goodix_fprintd"
else
  echo "   WARNING: could not remove it; try: semodule -r goodix_fprintd" >&2
fi

echo "== restart fprintd on stock libfprint =="
# Stop it politely, for the same reason install-system.sh does: SIGKILL denies
# fprintd the chance to close the device, and the driver clears the sensor LED
# on close — a hard kill leaves the light on with nothing left to switch it off.
systemctl stop fprintd.service 2>/dev/null || true
pkill -TERM -x fprintd 2>/dev/null || true
sleep 1
systemctl daemon-reload
systemctl restart fprintd.service 2>/dev/null || true

echo "DONE. fprintd now uses the stock distro libfprint again."
echo "(PAM with-fingerprint left as-is; disable with: authselect disable-feature with-fingerprint)"
