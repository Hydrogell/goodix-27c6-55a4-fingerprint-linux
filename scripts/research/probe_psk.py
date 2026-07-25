#!/usr/bin/env python3
# READ-ONLY probe #2: firmware + PSK status. Uses only nop(), firmware_version(),
# preset_psk_read() — all reads. NO write_psk, NO erase, NO flash.
import driver_55x4

dev = driver_55x4.init_device(0x55a4)
fw = dev.firmware_version()
print(f"FIRMWARE : {fw!r}")
print(f"CHIP     : {fw.split('_')[0]}   (community tools target GF3268)")

print(">>> reading PSK status (preset_psk_read) — READ-ONLY...")
try:
    reply = dev.preset_psk_read(0xbb020007)
    ok, flags = reply[0], reply[1]
    print(f"    read ok={ok} flags={hex(flags) if isinstance(flags,int) else flags}")
    if ok and reply[2] == driver_55x4.PMK_HASH:
        print("    PSK ALREADY = known whitebox/zeroed key (PMK_HASH matches).")
        print("    => Secure channel can be established WITHOUT writing PSK (non-destructive!).")
    else:
        got = reply[2].hex() if hasattr(reply[2], 'hex') else reply[2]
        print(f"    PMK hash on device: {got}")
        print("    => Device-unique PSK. Establishing channel would need a PSK write (destructive).")
except Exception as e:
    print(f"    ERROR reading PSK: {type(e).__name__}: {e}")

print(">>> DONE. Read-only: nothing written, erased, or flashed.")
