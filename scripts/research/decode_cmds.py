#!/usr/bin/env python3
# Decode the plaintext a0-framed OUT commands (EP 0x01) Windows sent to the sensor.
# Usage: decode_cmds.py <capture.pcapng>
import subprocess, sys
CMD = {0x00:"NOP",0x20:"GET_IMAGE",0x32:"FDT_DOWN",0x34:"FDT_UP",0x36:"FDT_MODE",
0x50:"NAV",0x60:"MCU_SLEEP",0x70:"MCU_IDLE",0x80:"WRITE_SENSOR_REG",0x82:"READ_SENSOR_REG",
0x90:"UPLOAD_CONFIG",0x92:"SWITCH_SLEEP",0x94:"SET_PWRDN_FREQ",0x96:"ENABLE_CHIP",
0xa2:"RESET",0xa4:"ERASE_APP",0xa6:"READ_OTP",0xa8:"FW_VERSION",0xac:"SET_POV_CFG",
0xae:"QUERY_MCU_STATE",0xb0:"ACK",0xc4:"SET_DRV_STATE",0xd0:"REQ_TLS",0xd2:"GET_POV_IMG",
0xd4:"TLS_OK",0xd6:"POV_CHECK",0xe0:"PSK_WRITE",0xe4:"PSK_READ",0xf0:"WRITE_FW",
0xf2:"READ_FW",0xf4:"CHECK_FW",0xf6:"IAP_VER"}

if len(sys.argv) != 2:
    sys.exit(f"usage: {sys.argv[0]} <capture.pcapng>")

out = subprocess.run(["tshark","-r",sys.argv[1],
  "-Y","usb.endpoint_address==0x01 && usb.data_len>0","-T","fields","-e","usb.capdata"],
  capture_output=True,text=True).stdout

seq=[]
for line in out.splitlines():
    h=line.replace(":","").strip()
    if not h: continue
    b=bytes.fromhex(h)
    if len(b)<5 or b[0]!=0xa0:
        seq.append(("non-a0", h[:24])); continue
    ln=b[1]|(b[2]<<8); cmd=b[4]
    name=CMD.get(cmd,f"UNK_0x{cmd:02x}")
    payload=b[4:4+ln].hex()   # include cmd byte
    seq.append((name, payload))

# collapse consecutive duplicates for readability, but keep register-writes/FDT verbatim
print(f"total OUT commands: {len(seq)}")
print("=== full command sequence (name : payload) ===")
prev=None; cnt=0
for name,pl in seq:
    key=(name, pl)
    if key==prev:
        cnt+=1; continue
    if prev and cnt>1: print(f"    (repeated x{cnt})")
    prev=key; cnt=1
    print(f"{name:18} {pl[:56]}")
if cnt>1: print(f"    (repeated x{cnt})")

print()
print("=== all WRITE_SENSOR_REG (0x80) - LED control candidates ===")
for name,pl in seq:
    if name=="WRITE_SENSOR_REG": print("  ", pl[:60])
print("=== all FDT_MODE / FDT_DOWN / FDT_UP (mode bytes) ===")
for name,pl in seq:
    if name in ("FDT_MODE","FDT_DOWN","FDT_UP"): print(f"  {name}: {pl[:60]}")
