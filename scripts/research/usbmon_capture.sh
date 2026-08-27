#!/usr/bin/env bash
# Capture usbmon USB traces of BOTH the failing native C driver run and the
# working Python reference run, on THIS machine, so we can diff the low-level
# USB transaction pattern (libusb/libfprint vs pyusb) around GET_IMAGE.
# The command sequence/crypto/handshake are already proven byte-identical; the
# remaining difference is USB-transaction level, visible only in usbmon.
#
#
# WHAT THE OUTPUT CONTAINS -- READ THIS ONCE:
# A trace of this sensor is your fingerprint in a file. The TLS session uses a
# publicly known all-zero pre-shared key, so anybody who obtains the .pcapng can
# decrypt it and reconstruct the images your finger produced. Treat the output
# like a photograph of your fingertip: keep it on this machine, do not attach it
# to bug reports or pull requests, and delete it when you are done. That is why
# it is written outside the repository by default.
#
# Run with sudo:  sudo scripts/research/usbmon_capture.sh
set -e
# resolve the real user and their home even under sudo
RUSER="${SUDO_USER:-$USER}"
RHOME="$(getent passwd "$RUSER" | cut -d: -f6)"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# deliberately NOT inside $REPO -- see the warning above
OUT="${OUT:-$RHOME/goodix-captures}"
mkdir -p "$OUT"

BUS=$(lsusb | grep -i 27c6:55a4 | sed -E 's/Bus 0*([0-9]+) Device.*/\1/')
echo "[cap] Goodix on bus $BUS"
modprobe usbmon
IFACE="usbmon${BUS}"

run_capture () {  # $1=label  $2...=command (run as RUSER)
  local label="$1"; shift
  # dumpcap drops privileges and cannot write into the user's home — capture
  # to /tmp first, then move the finished file into $OUT.
  local tmp="/tmp/cdiff-${label}.pcapng"
  local pcap="$OUT/cdiff-${label}.pcapng"
  rm -f "$tmp"
  echo "[cap] === $label -> $pcap ==="
  tshark -i "$IFACE" -w "$tmp" -q &
  local tpid=$!
  sleep 1.5
  echo "[cap] running: $*"
  # The redirect is opened by root, not by $RUSER — which is what we want here,
  # since $OUT may not be writable by the user yet; both files are chowned back
  # at the end. shellcheck flags this pattern because it is usually a mistake.
  # shellcheck disable=SC2024
  sudo -u "$RUSER" -- "$@" >"$OUT/cdiff-${label}.log" 2>&1 || true
  sleep 1.0
  kill "$tpid" 2>/dev/null || true
  wait "$tpid" 2>/dev/null || true
  mv "$tmp" "$pcap"
  echo "[cap] $label packets: $(tshark -r "$pcap" -Y 'usb.transfer_type==0x03 && usb.capdata' 2>/dev/null | wc -l)"
}

# 1) failing native C driver
run_capture "c-fail" \
  env G_MESSAGES_DEBUG=all timeout 20 \
  "$REPO/work/twd-libfprint/build/examples/img-capture" /tmp/cdiff_out.pgm

sleep 2

# 2) working Python reference (must run from its own dir: local imports)
run_capture "py-ok" \
  bash -c "cd '$REPO/work/goodix-fp-dump' && timeout 40 .venv/bin/python py_relay_probe.py"

chown "$RUSER":"$RUSER" "$OUT"/cdiff-*.pcapng "$OUT"/cdiff-*.log 2>/dev/null || true
echo "[cap] DONE. Wrote:"
ls -la "$OUT"/cdiff-*.pcapng
