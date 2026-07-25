#!/usr/bin/env bash
# Boot the Windows capture VM with the fingerprint sensor passed through, while
# recording host-side usbmon, in order to find what makes the sensor LED light.
#
# Why this works: usbmon records in the host kernel, and QEMU's usb-host
# passthrough still goes through the host USB stack — so we see every byte the
# stock driver sends even though the device belongs to the guest.
#
# Prerequisite: a Windows VM named below, defined in libvirt, with the vendor's
# fingerprint driver installed. Building that VM is your own business and is not
# part of this repository.
#
# WHAT THE OUTPUT CONTAINS: the trace is your fingerprint in a file — the TLS
# session uses a publicly known all-zero pre-shared key, so anyone who obtains
# the .pcapng can decrypt it and recover the images. Keep it local, never attach
# it to a bug report, delete it when done.
#
# The point of the run is a correlation: the moment the LED lights, note the
# time; the command that caused it is in the trace just before that timestamp.
#
# Heads-up: the Windows driver may rewrite the whitebox PSK and re-check the
# firmware, exactly as it did during the original capture. That is how the
# sensor got into its current state, so re-running is not a new risk — but it is
# not a no-op either.
#
# Run as root:  sudo bash scripts/research/led-vm-capture.sh
set -e
VM=win10fp
OUT="${OUT:-/tmp/led-vm.pcapng}"
RUSER="${SUDO_USER:-$USER}"

ID="$(lsusb | grep -i '27c6:55a4' || true)"
[ -n "$ID" ] || { echo "sensor 27c6:55a4 not found" >&2; exit 1; }
BUS=$(sed -E 's/Bus 0*([0-9]+) Device.*/\1/' <<<"$ID")
echo ">> sensor on bus $BUS"

modprobe usbmon
XML=/tmp/goodix-hostdev.xml
cat >"$XML" <<EOF
<hostdev mode='subsystem' type='usb' managed='yes'>
  <source><vendor id='0x27c6'/><product id='0x55a4'/></source>
</hostdev>
EOF

cleanup() {
    echo
    echo ">> stopping the capture and giving the sensor back to the host..."
    kill "${TSHARK_PID:-0}" 2>/dev/null || true
    wait "${TSHARK_PID:-0}" 2>/dev/null || true
    virsh detach-device "$VM" "$XML" --live 2>/dev/null || true
    virsh shutdown "$VM" 2>/dev/null || true
    if [ -f "$OUT" ]; then
        chown "$RUSER":"$RUSER" "$OUT" 2>/dev/null || true
        echo ">> trace: $OUT ($(stat -c%s "$OUT") bytes)"
        echo ">> NOTE: if you enrolled or verified a finger, this trace holds"
        echo ">>       your fingerprint images. The sensor's TLS uses a public"
        echo ">>       all-zero key, so anyone with the file can decrypt them."
        echo ">>       Keep it local; never attach it to a bug report."
    fi
    echo ">> give it ~20 s for the VM to shut down and the device to come back"
}
trap cleanup EXIT

rm -f "$OUT"
tshark -i "usbmon${BUS}" -w "$OUT" -q >/dev/null 2>&1 &
TSHARK_PID=$!
sleep 1
echo ">> usbmon capture is running (pid $TSHARK_PID)"

virsh start "$VM" 2>/dev/null || echo ">> VM is already running"
echo ">> waiting for Windows to boot (60 s)..."
sleep 60

echo ">> handing the sensor over to the VM"
virsh attach-device "$VM" "$XML" --live

cat <<'MSG'

================================================================
  Open the VM window:   virt-viewer --connect qemu:///system win10fp
  (or use virt-manager)

  Inside Windows go to Settings → Accounts → Sign-in options and try
  to enrol or use a fingerprint — that is what makes the Goodix
  driver start talking to the sensor.

  WATCH THE LED. If it lights up, note the moment (what you were
  doing on screen).

  When you have finished, come back here and press Enter.
================================================================

MSG
read -r _
