#!/usr/bin/env python3
# RESTORE-POINT snapshot for Goodix 55a4. READ-ONLY: firmware_version, read_sensor_register,
# read_otp, preset_psk_read, get_iap_version, read_firmware. No write/erase/flash.
#
# WARNING: the output is specific to your sensor. otp.bin / otp_hex is a unique
# per-device identifier. Keep the snapshot local — do not attach it to bug
# reports, pull requests or anything public.
import os, sys, struct
import driver_55x4

OUT = os.path.expanduser("~/goodix-fp-backup")
os.makedirs(OUT, exist_ok=True)
manifest = []
def rec(k, v):
    manifest.append(f"{k}: {v}")
    print(f"  {k}: {v}")

dev = driver_55x4.init_device(0x55a4)

# 1. firmware version
try:
    fw = dev.firmware_version(); rec("firmware_version", fw)
except Exception as e: rec("firmware_version", f"ERROR {e}")

# 2. chip id
try:
    cid = dev.read_sensor_register(0x0000, 4)
    rec("chip_id_reg_0x0000", cid.hex() if hasattr(cid,'hex') else cid)
except Exception as e: rec("chip_id_reg_0x0000", f"ERROR {e}")

# 3. OTP
try:
    otp = dev.read_otp()
    otp_b = bytes(otp) if not isinstance(otp,(bytes,bytearray)) else otp
    open(os.path.join(OUT,"otp.bin"),"wb").write(otp_b)
    rec("otp_hex", otp_b.hex()); rec("otp_len", len(otp_b))
except Exception as e: rec("otp", f"ERROR {e}")

# 4. PSK PMK hash (device-unique, NOT the key itself)
try:
    reply = dev.preset_psk_read(0xbb020007)
    h = reply[2]
    rec("psk_pmk_hash", h.hex() if hasattr(h,'hex') else h)
    rec("psk_is_whitebox_default", reply[2] == driver_55x4.PMK_HASH)
except Exception as e: rec("psk", f"ERROR {e}")

# 5. IAP version
try:
    iap = dev.get_iap_version(25); rec("iap_version", iap)
except Exception as e: rec("iap_version", f"ERROR {e}")

# 6. firmware image dump (chunked, read-only). Try offset 0 upward until it stops.
fw_path = os.path.join(OUT,"firmware.bin")
data = bytearray()
CHUNK = 1024; MAX = 512*1024
try:
    off = 0
    while off < MAX:
        try:
            block = dev.read_firmware(off, CHUNK)
        except Exception as e:
            rec("firmware_read_stop", f"at offset {off}: {type(e).__name__}: {e}")
            break
        if not block or len(block) < CHUNK:
            data += bytes(block or b"")
            rec("firmware_read_stop", f"short block at offset {off} (len {len(block or b'')})")
            break
        data += bytes(block); off += CHUNK
    if data:
        open(fw_path,"wb").write(data)
        rec("firmware_dumped_bytes", len(data))
except Exception as e:
    rec("firmware_dump", f"ERROR {e}")

open(os.path.join(OUT,"manifest.txt"),"w").write("\n".join(manifest)+"\n")
print(f"\n>>> snapshot saved to {OUT} (READ-ONLY, nothing modified)")
