#!/usr/bin/env python3
# Working-reference probe: capture an image via the proven goodix-fp-dump path,
# but with openssl s_server on a UNIX socket rather than a TCP listener, so no
# local port is opened, and log the TLS handshake flight sizes to compare
# against the C driver's relay.
import socket, subprocess, time, select
import driver_55x4, tool, goodix

PSK = driver_55x4.PSK
FDT_BASELINE = bytes.fromhex("0d0180008000800080008000800080008000800080008000")
SOCK = "/tmp/goodix_ssl.sock"

dev = driver_55x4.init_device(0x55a4)
print("fw:", dev.firmware_version())
if not driver_55x4.check_psk(dev):
    print("writing whitebox PSK..."); driver_55x4.write_psk(dev)

import os
try: os.remove(SOCK)
except FileNotFoundError: pass

_sslerr = open("/tmp/ssl.err", "wb")
srv = subprocess.Popen(
    ["stdbuf","-o0","openssl","s_server","-nocert","-psk",PSK.hex(),
     "-unix",SOCK,"-quiet","-tls1_2","-cipher","PSK:@SECLEVEL=0"],
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=_sslerr)
# wait for the unix socket to appear
for _ in range(50):
    if os.path.exists(SOCK): break
    time.sleep(0.1)
time.sleep(0.3)

def cd_logged(device, cli):
    # inlined tool.connect_device with flight-size logging
    ch = device.request_tls_connection()
    print(f"[PY] dev->ssl ClientHello: {len(ch)}")
    cli.sendall(ch)
    b = cli.recv(4096); print(f"[PY] ssl->dev ServerHello flight: {len(b)} HEX {b.hex()}")
    device.protocol.write(goodix.encode_message_pack(b, goodix.FLAGS_TRANSPORT_LAYER_SECURITY))
    for i in range(3):
        p = goodix.check_message_pack(device.protocol.read(), goodix.FLAGS_TRANSPORT_LAYER_SECURITY)
        print(f"[PY] dev->ssl handshake#{i+1}: {len(p)}")
        cli.sendall(p)
    b = cli.recv(4096); print(f"[PY] ssl->dev server-final flight: {len(b)} HEX {b.hex()}")
    device.protocol.write(goodix.encode_message_pack(b, goodix.FLAGS_TRANSPORT_LAYER_SECURITY))
    time.sleep(0.01)

try:
    dev.reset(True, False, 20)
    dev.read_sensor_register(0x0000, 4)
    dev.read_otp()
    cli = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); cli.connect(SOCK)
    cd_logged(dev, cli)
    print("[PY] TLS channel established")
    dev.upload_config_mcu(driver_55x4.DEVICE_CONFIG)
    print("[PY] config uploaded")
    dev.mcu_switch_to_fdt_mode(FDT_BASELINE, True)
    print("[PY] fdt baseline done")
    img_req = dev.mcu_get_image(b"\x01\x00", goodix.FLAGS_TRANSPORT_LAYER_SECURITY_DATA)
    print(f"[PY] GET_IMAGE reply: {len(img_req)} bytes, head={img_req[:12].hex()}")
    cli.sendall(img_req[9:])
    data = b""; deadline = time.time() + 12
    while len(data) < 14400 and time.time() < deadline:
        r,_,_ = select.select([srv.stdout], [], [], 3)
        if not r: continue
        chunk = srv.stdout.read1(14400-len(data))
        if not chunk: break
        data += chunk
    nz = sum(1 for b in data if b)
    print(f"[PY] DECRYPTED IMAGE BYTES: {len(data)}, non-zero {nz}")
    if len(data) > 9000:
        print("[PY] *** IMAGE CAPTURE SUCCESS ***")
    cli.close()
finally:
    srv.terminate()
print("[PY] done")
