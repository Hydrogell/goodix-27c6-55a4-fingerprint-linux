#!/usr/bin/env python3
# Replicate the C driver's EXACT command sequence in the (working) Python path.
# If this breaks image capture -> a command is the culprit. If it still captures
# -> the C driver's implementation (async reads etc.) is the culprit.
import socket, subprocess, time, select, os
import driver_55x4, tool, goodix

PSK = driver_55x4.PSK
FDT_BASELINE = bytes.fromhex("0d0180008000800080008000800080008000800080008000")
SOCK = "/tmp/goodix_ssl.sock"

dev = driver_55x4.init_device(0x55a4)
if not driver_55x4.check_psk(dev):
    print("writing whitebox PSK..."); driver_55x4.write_psk(dev)

try: os.remove(SOCK)
except FileNotFoundError: pass
_e = open("/tmp/ssl.err","wb")
srv = subprocess.Popen(
    ["stdbuf","-o0","openssl","s_server","-nocert","-psk",PSK.hex(),
     "-unix",SOCK,"-quiet","-tls1_2","-cipher","PSK:@SECLEVEL=0"],
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=_e)
for _ in range(50):
    if os.path.exists(SOCK): break
    time.sleep(0.1)
time.sleep(0.3)

def connect(device, cli):
    cli.sendall(device.request_tls_connection())
    device.protocol.write(goodix.encode_message_pack(cli.recv(4096), goodix.FLAGS_TRANSPORT_LAYER_SECURITY))
    for _ in range(3):
        cli.sendall(goodix.check_message_pack(device.protocol.read(), goodix.FLAGS_TRANSPORT_LAYER_SECURITY))
    device.protocol.write(goodix.encode_message_pack(cli.recv(4096), goodix.FLAGS_TRANSPORT_LAYER_SECURITY))
    time.sleep(0.01)

try:
    # ---- C-style ACTIVATE ----
    print(">> nop"); dev.nop()
    print(">> enable_chip(True)"); dev.enable_chip(True)
    print(">> nop"); dev.nop()
    print(">> firmware:", dev.firmware_version())
    print(">> reset(True,False,20)"); dev.reset(True, False, 20)
    print(">> mcu_switch_to_idle_mode(20)"); dev.mcu_switch_to_idle_mode(20)
    print(">> upload_config PRE-TLS"); dev.upload_config_mcu(driver_55x4.DEVICE_CONFIG)
    # ---- handshake ----
    cli = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); cli.connect(SOCK)
    connect(dev, cli); print(">> TLS established")
    # ---- C-style post-handshake ----
    print(">> tls_successfully_established (0xd4)"); dev.tls_successfully_established()
    print(">> upload_config POST-TLS"); dev.upload_config_mcu(driver_55x4.DEVICE_CONFIG)
    print(">> fdt baseline")
    _fdt = dev.mcu_switch_to_fdt_mode(FDT_BASELINE, True)
    print(f">> FDT reply: {bytes(_fdt).hex() if _fdt else None}")
    print(">> GET_IMAGE")
    img = dev.mcu_get_image(b"\x01\x00", goodix.FLAGS_TRANSPORT_LAYER_SECURITY_DATA)
    print(f">> GET_IMAGE reply: {len(img)} bytes head={img[:12].hex()}")
    if img[9:11].hex() == "1703" or len(img) > 9000:
        cli.sendall(img[9:])
        data=b""; dl=time.time()+10
        while len(data)<14400 and time.time()<dl:
            r,_,_=select.select([srv.stdout],[],[],3)
            if not r: continue
            c=srv.stdout.read1(14400-len(data))
            if not c: break
            data+=c
        print(f">> DECRYPTED: {len(data)} bytes  ==> {'*** C-SEQUENCE STILL WORKS ***' if len(data)>9000 else 'no image'}")
    cli.close()
except Exception as e:
    print(f">> EXCEPTION (C-sequence broke it): {type(e).__name__}: {e}")
finally:
    srv.terminate()
print(">> done")
