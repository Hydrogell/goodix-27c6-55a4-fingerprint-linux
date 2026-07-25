# Goodix 55x4 protocol notes

Protocol behaviour of the 27c6:55a4, established by observing USB traffic on the
author's own hardware and verified against the device itself. Written separately
from the driver because these are protocol facts, useful to anyone working on
this sensor family regardless of what they are building.

The framing itself (`a0`-packets, command/ACK structure, TLS-PSK setup) is
already documented by [goodix-fp-dump][gfd] and [goodix-wireshark][gws]; only
the corrections and additions are here.

[gfd]: https://github.com/goodix-fp-linux-dev/goodix-fp-dump
[gws]: https://github.com/goodix-fp-linux-dev/goodix-wireshark

## `0xae` is a switch, not a status query

Both the dissector and the Python tooling call this command `QUERY_MCU_STATE`,
which reads as a harmless poll. It is not: it drives the sensor's **status LED**.
The two payloads differ only by swapping their first two bytes.

| command | payload | effect |
|---|---|---|
| `0xae` | `00 01 32` | LED on |
| `0xae` | `01 00 32` | LED off |

The device replies with a plain ACK. The vendor driver sends these in strictly
alternating pairs — identical in two independent captures taken months apart —
and lights the sensor while it waits for a finger. That is why the light only
ever appeared during Windows' lock screen and never under an open-source driver:
nobody was sending the command, and the name gave no reason to try.

Verified by direct experiment on hardware, with everything else ruled out first:
USB reset, USB autosuspend, arming via `FDT_DOWN`, `SET_POV_CONFIG` (`0xac`),
`SET_DRV_STATE` (`0xc4`), `GET_POV_IMG` (`0xd2`), `0xc6`, and the single config
byte where our upload differed from the vendor's (offset 192).

## Finger-detect thresholds are per-sensor

The FDT commands — `FDT_MODE` (`0x36`), `FDT_DOWN` (`0x32`), `FDT_UP` (`0x34`) —
carry one threshold byte per detection zone, twelve zones on this part:

```
0x0d 0x01  80 t0  80 t1  …  80 t11      (FDT_MODE; 0x0c = DOWN, 0x0e = UP)
```

**These are not constants.** The device reports its own measured per-zone base
level in the reply to `FDT_MODE`:

```
82 01 ff 07   <12 × uint16 little-endian base values>
```

(the first four bytes vary — `80 01 00 00` also occurs — so skip four and read
twelve 16-bit values), and the vendor derives each threshold as:

```
threshold[i] = base[i] >> 1
```

Verified **12/12 byte-exact** against the Windows capture and then live on the
device: base 364 → `0xb6`, 410 → `0xcd`, 396 → `0xc6`, 360 → `0xb4`, 356 →
`0xb2`. Bases drift by ±1–2 between reads, which is why the vendor's bytes
occasionally differ by one from a base sampled a moment earlier.

Consequences for anyone porting this driver:

- Hardcoded threshold tables are **unit-specific**. The tables that ship for the
  55b4 put `0x12` where a 55a4 needs `0xb5` — off by a factor of ten. With
  wrong thresholds the device-side gate never fires, `FDT_DOWN` returns
  immediately, and it looks exactly as though the firmware does not support
  blocking finger detection. It does: with correct thresholds `FDT_DOWN` blocks
  until a real touch (4.1 s in one capture) and `FDT_UP` blocks until lift-off
  (0.7–1.0 s typical).
- The vendor uses **different** threshold sets for `FDT_MODE` and `FDT_DOWN` —
  e.g. `aa bb b5 a1 …` against `b6 ce c7 b8 …` in the same session. Deriving one
  set and sending it to all three commands is what this driver does for the
  55a4, and it works, but it is not what the vendor does. Do not assume it is
  safe on another part.
- The threshold field is one byte, so a base of 512 or more wraps. Bases
  observed here are 352–410; clamp rather than mask.

## `0xf6` is the bootloader version

Not previously labelled. Sends an empty request, replies with the IAP version
string — `MILAN_RTSEC_IAP` on this part.

## Key slots

`preset_psk_read`/`preset_psk_write` take a slot in their flags word, and the
vendor and the open-source tooling use **different** slots:

| slot | contents |
|---|---|
| `0xbb010002` | vendor's key material — a 324-byte Windows DPAPI blob (`01 00 00 00 d0 8c 9d df …`) |
| `0xbb010003` | where goodix-fp-dump writes the whitebox PSK blob |
| `0xbb020007` | the PMK hash, i.e. which key is currently in effect |

Note where the first row comes from: the contents of `0xbb010002` were decoded
out of a Windows USB trace, not read back from the sensor here — and that same
trace shows the vendor driver writing the blob into the slot itself.

Practical consequence: provisioning the whitebox key for Linux writes
`0xbb010003` and nothing else. No code path here addresses `0xbb010002`, so the
vendor's material is not overwritten.

Whether dual-boot then keeps working indefinitely was not exercised. It follows
from the slots being separate, and one traced Windows session (sensor passed
through to a VM, after this unit had been provisioned) enrolled a fingerprint,
with the whitebox key still in effect on the Linux side afterwards — but that is
a single observation, not a measurement. Do not quote it as a tested result.

## Firmware string is not stable

The same physical part reports its family as `GF3208_RTSEC_APP_10063` or
`GF3268_RTSEC_APP_10063` across cold boots — the version is stable, the family
digits are not. An exact string comparison will fail intermittently; match
`GF32[0-9]{2}_RTSEC_APP_100[0-9]{2}` instead.

## Timing: the firmware needs quiet after the TLS handshake

After the server's final flight (ChangeCipherSpec + Finished) is delivered, the
firmware needs roughly **10–15 ms of silence** to finalise its TLS session. Send
the next command sooner and it will ACK everything normally but never mark the
session ready, answering every `GET_IMAGE` with `0xd0`
(`REQUEST_TLS_CONNECTION`) indefinitely.

The Python reference happens to satisfy this with a `sleep(0.01)` whose comment
only mentions avoiding a USB timeout; a C driver without that delay hits the
failure every time. This cost a great deal of debugging before it was found by
diffing usbmon traces of a working Python run against a failing C one.

## Vendor behaviours worth imitating

Inferred from the stock driver's observable behaviour:

- The image **background is captured once**, at device start, and refreshed only
  after a confirmed finger-up. The driver contains the literal branch
  `"image base not valid, wait fdt up"` — on a press with an invalid base it
  aborts and waits for the finger to leave rather than recalibrating under it.
  New baselines are validity-gated (`"new base invalid, using existing base"`)
  and persisted to file.
- Frames are **best-picked, not averaged**: if the coverage of two candidates
  differs by 20 or more take the higher coverage, otherwise take the higher
  quality.
- Image statistics are computed over a **trimmed band**, with out-of-band pixels
  treated as broken — not over the absolute min/max of the frame.
- The per-touch loop is `FDT_DOWN → GET_IMAGE → FDT_MODE → 0xc6 → FDT_UP`, i.e.
  the background is recalibrated *after* the capture, not before it.
