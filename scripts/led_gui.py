#!/usr/bin/env python3
"""Interactive console for poking the Goodix 55a4 — built to hunt the LED.

Every one-shot probe has the same weakness: each run gives you a single look at
the light, and a brief flicker is easy to miss. This lets you press the same
button ten times in a row and watch.

Buttons cover every candidate command, plus a free-form command field for
anything else. The log shows what went out and what came back.

Run (after ./setup.sh):  cd work/goodix-fp-dump && .venv/bin/python led_gui.py
"""
import threading
import tkinter as tk
from tkinter import scrolledtext

import driver_55x4
import goodix

# Bytes captured from the Windows VM session, where the LED did work.
FDT_MODE_WIN = bytes.fromhex("0d0180aa80bb80b580a180aa80bb80b8809a80a980b480a48098")
FDT_DOWN_WIN = bytes.fromhex("0c0180b680ce80c780b880b480cd80c680bd80b180c680bc80b2")
FDT_UP_WIN = bytes.fromhex("0e0180b680ce80c780b880b480cd80c680bd80b180c680bc80b2")
POV_CONFIG = bytes.fromhex(
    "100f80b680ce80c780b880b480cd80c680bd80b180c680bc80b2"
    "160600000000000000000a020a03")

CMD = {
    "NOP": 0x00, "GET_IMAGE": 0x20, "FDT_DOWN": 0x32, "FDT_UP": 0x34,
    "FDT_MODE": 0x36, "NAV": 0x50, "SLEEP": 0x60, "IDLE": 0x70,
    "UPLOAD_CONFIG": 0x90, "ENABLE_CHIP": 0x96, "RESET": 0xa2,
    "SET_POV_CONFIG": 0xac, "QUERY_MCU_STATE": 0xae, "SET_DRV_STATE": 0xc4,
    "0xc6": 0xc6, "GET_POV_IMG": 0xd2, "POV_IMG_CHECK": 0xd6,
}


class App:
    def __init__(self, root):
        self.dev = None
        root.title("Goodix 55a4 — LED hunt")

        top = tk.Frame(root, padx=8, pady=6)
        top.pack(fill="x")
        self.status = tk.Label(top, text="not connected", fg="#a00",
                               font=("", 11, "bold"))
        self.status.pack(side="left")
        tk.Button(top, text="Connect", command=self.connect,
                  width=14).pack(side="right")

        self.log = scrolledtext.ScrolledText(root, height=16, width=86,
                                             font=("monospace", 9))
        self.log.pack(padx=8, pady=4, fill="both", expand=True)

        # --- candidate buttons -------------------------------------------
        grid = tk.LabelFrame(root, text="Candidates from the Windows trace",
                             padx=6, pady=6)
        grid.pack(fill="x", padx=8, pady=4)

        rows = [
            [("0xc6 = 00", lambda: self.send(0xc6, b"\x00")),
             ("0xc6 = 01", lambda: self.send(0xc6, b"\x01")),
             ("0xc6 = 02", lambda: self.send(0xc6, b"\x02")),
             ("0xc6 = ff", lambda: self.send(0xc6, b"\xff"))],
            [("SET_DRV_STATE", lambda: self.send(0xc4, b"\x01\x00")),
             ("GET_POV_IMG", lambda: self.send(0xd2, b"\x00\x00")),
             ("POV_IMG_CHECK", lambda: self.send(0xd6, b"\x00\x00")),
             ("QUERY_MCU_STATE", lambda: self.send(0xae, b"\x00\x01\x32"))],
            [("SET_POV_CONFIG", lambda: self.send(0xac, POV_CONFIG)),
             ("FDT_MODE (win)", lambda: self.send(0x36, FDT_MODE_WIN)),
             ("FDT_DOWN (win)", lambda: self.send(0x32, FDT_DOWN_WIN)),
             ("FDT_UP (win)", lambda: self.send(0x34, FDT_UP_WIN))],
            [("Config (ours)", lambda: self.upload_cfg(False)),
             ("Config byte192=0x16", lambda: self.upload_cfg(True)),
             ("SLEEP", lambda: self.send(0x60, b"\x01\x00")),
             ("IDLE", lambda: self.send(0x70, b"\x14\x00"))],
            [("NOP", lambda: self.send(0x00, b"\x00\x00\x00\x00")),
             ("ENABLE_CHIP", lambda: self.send(0x96, b"\x01\x00")),
             ("RESET", lambda: self.send(0xa2, b"\x05\x14")),
             ("NAV", lambda: self.send(0x50, b"\x01\x00"))],
        ]
        for r in rows:
            line = tk.Frame(grid)
            line.pack(fill="x", pady=1)
            for label, fn in r:
                tk.Button(line, text=label, command=fn, width=19).pack(
                    side="left", padx=2)

        # --- free-form ----------------------------------------------------
        free = tk.LabelFrame(root, text="Free-form command", padx=6, pady=6)
        free.pack(fill="x", padx=8, pady=(0, 8))
        tk.Label(free, text="command (hex):").pack(side="left")
        self.e_cmd = tk.Entry(free, width=6)
        self.e_cmd.pack(side="left", padx=4)
        self.e_cmd.insert(0, "c6")
        tk.Label(free, text="data (hex):").pack(side="left", padx=(8, 0))
        self.e_pay = tk.Entry(free, width=40)
        self.e_pay.pack(side="left", padx=4)
        self.e_pay.insert(0, "01")
        tk.Button(free, text="Send", command=self.send_free,
                  width=12).pack(side="left", padx=4)
        tk.Button(free, text="Clear log",
                  command=lambda: self.log.delete("1.0", "end")).pack(
                      side="right")

    # ---------------------------------------------------------------- utils
    def say(self, text, tag=None):
        self.log.insert("end", text + "\n")
        self.log.see("end")

    def connect(self):
        def work():
            try:
                self.dev = driver_55x4.init_device(0x55a4)
                fw = self.dev.firmware_version()
                self.status.config(text=f"connected · {fw}", fg="#070")
                self.say(f"[+] connected, firmware {fw}")
            except Exception as e:  # noqa: BLE001
                self.status.config(text="connection failed", fg="#a00")
                self.say(f"[!] could not connect: {e}")
        threading.Thread(target=work, daemon=True).start()

    def send(self, cmd, payload):
        if self.dev is None:
            self.say("[!] press Connect first")
            return

        def work():
            name = next((k for k, v in CMD.items() if v == cmd), f"0x{cmd:02x}")
            try:
                self.dev.protocol.write(goodix.encode_message_pack(
                    goodix.encode_message_protocol(payload, cmd)))
                self.say(f"--> {name:16} 0x{cmd:02x}  data={payload.hex()}")
                try:
                    r = self.dev.protocol.read()
                    self.say(f"<-- {r.hex()[:80]}")
                except Exception as e:  # noqa: BLE001
                    self.say(f"<-- (no reply: {e})")
            except Exception as e:  # noqa: BLE001
                self.say(f"[!] send failed: {e}")
        threading.Thread(target=work, daemon=True).start()

    def upload_cfg(self, windows_variant):
        if self.dev is None:
            self.say("[!] press Connect first")
            return

        def work():
            cfg = bytearray(driver_55x4.DEVICE_CONFIG)
            if windows_variant:
                cfg[192] = 0x16
                cfg[254] = 0x98
                self.say("--> config WINDOWS VARIANT (byte 192 = 0x16)")
            else:
                self.say("--> config, our stock variant (byte 192 = 0x14)")
            try:
                ok = self.dev.upload_config_mcu(bytes(cfg))
                self.say(f"<-- upload_config_mcu = {ok}")
            except Exception as e:  # noqa: BLE001
                self.say(f"[!] failed: {e}")
        threading.Thread(target=work, daemon=True).start()

    def send_free(self):
        try:
            cmd = int(self.e_cmd.get().strip().replace("0x", ""), 16)
            payload = bytes.fromhex(self.e_pay.get().strip().replace(" ", ""))
        except ValueError as e:
            self.say(f"[!] bad hex: {e}")
            return
        self.send(cmd, payload)


if __name__ == "__main__":
    root = tk.Tk()
    App(root)
    root.mainloop()
