# Technical account — Goodix 27c6:55a4 driver

How this driver went from matching about one press in three to matching
reliably, and what each defect actually was. Written as a record of evidence:
every claim below was measured on hardware, read out of a USB capture of the
stock driver in operation, or — for the few facts the wire cannot show, such as
the vendor branch strings quoted later — read out of the vendor's Windows driver,
examined for interoperability and re-implemented independently. No vendor code
was copied; see the README for the full provenance account. Protocol facts on
their own are in [PROTOCOL.md](PROTOCOL.md).

Live checkouts go under `work/` (gitignored) and are rebuilt by `./setup.sh`.

## ✅ STATUS (2026-07-25): WORKS, 87.5% match rate under deliberate displacement
The driver captures real fingerprints and drives the **system fprintd 1.94.5**
to a real biometric login (it also authenticates `sudo`). Measured progression
of the verify match rate this session:

| stage | rate |
|---|---|
| baseline (as inherited) | ~33%, worst series 20% |
| per-sensor FDT thresholds (event-driven capture) | 50% — but any displacement failed |
| SIGFM matcher bugfixes | 75% normal / 50% strong displacement |
| trimmed-band normalization + baseline-once + 16 enroll stages | **87.5% strong displacement** |
| absolute angular tolerance in the consistency test | **87.5% under rotation** (was 25%) |
| baseline validated before acceptance (finger-on-plate guard) | **12/12 presses called correctly — 6/6 true accept, 0 false accept in 6 impostor presses** |

### Result timing: announce on lift, not on touch (measured A/B/A)
The result surfaces when the finger is lifted, not while it is still down.
libfprint has the match immediately — it withholds *completion* until the driver
reports finger-off — so the natural idea is to report early and let the *next*
acquisition enforce the lift instead (the calibration guard below already does
exactly that). Conceptually the cleaner split, and it was tried:

| configuration | true accept |
|---|---|
| A — wait for lift before reporting | 6/6 (100%) |
| B — report immediately after capture | 4/6 (66%) |
| A — reverted | 6/6 (100%) |

(One `fp-stress.sh` run at the default 3 rounds is 12 presses: 6 genuine and 6
cross-finger impostors. The column above counts the genuine half.)

Reverting restored the number, so the regression was the change and not sampling
noise. Cause: libfprint deactivates the moment finger-off is reported, tearing
the scan SSM down before it completes its FDT cycle and leaving the sensor in a
worse state for the next run. Snappier feedback is not worth a third of the
accuracy — the experiment is recorded in a comment at the call site so it is not
reinvented. Waiting for lift also has a security property worth keeping: one
press cannot be counted twice.

### The finger-on-plate baseline guard
Reported symptom, and it turned out to be the last significant defect: *"finger
touches the sensor — trigger; finger is removed — second trigger"*. Each
`fprintd-verify` is its own activation, so the device re-captures a background
at the start of it. With the finger still down at that moment the background is
recorded **with the finger in it** — and since every later frame is
`|frame - background|`, lifting the finger then produced a huge difference and
registered as a fresh touch. The same phantom also distorted the working image,
so it was costing accuracy, not just producing spurious events.
Fix: a baseline candidate is only accepted once two frames 150 ms apart agree
(`GOODIX55X4_CAL_STABLE_DIFF`); a resting, settling or lifting finger makes them
disagree, so the candidate is rejected and retried (bounded to 16 attempts, then
it proceeds anyway rather than hanging). This is the driver-side equivalent of
the vendor's `"image base not valid, wait fdt up"` gate. Measured effect:
true-accept went 83% → 100% on the cross-finger matrix.

**False-accept validation** (the tolerances above were loosened, so this had to
be measured, not assumed): **0 false accepts out of 38 impostor presses.**
Breakdown: 14 presses with non-enrolled fingers identified against *all*
enrolled prints (`fprintd-verify -f any`), 12 more against a single print, and
12 cross-finger trials against a second enrolled finger (`right-thumb` next to
`right-index-finger`). Cross-finger is the hardest impostor case, since two
fingers of one hand resemble each other more than two different people do.
True-accept held at 83-100% across displacement, rotation and the two-finger
database, so enrolling a second finger did not dilute accuracy.
Statistical caveat: 0/38 bounds the false-accept rate at roughly 8% (95% upper
bound); a figure like "below 1%" would need hundreds of trials, which is not
reachable by hand.

Test harness: `scripts/fp-stress.sh [rounds]` runs the cross-finger matrix
(press A verify A / press A verify B / …) with desktop prompts telling
the tester which finger to use; `scripts/fp-notify.sh impostor N` runs the
non-enrolled-finger pass with inverted feedback (a rejection is the *correct*
outcome).

Install permanently (no replace/downgrade of the distro libfprint):
```
sudo bash scripts/install-system.sh      # → /opt/libfprint-goodix + systemd drop-in
scripts/fp-notify.sh enroll              # 16 touches, desktop ping per touch
scripts/fp-notify.sh verify 8
```
ABI-compatible: our libfprint is 1.94.6, fprintd needs only stable `fp_*`
symbols (verified present). `scripts/fp-notify.sh` / `scripts/fp-test.sh` fire a
desktop notification + sound the moment the sensor wants a finger — use them
instead of guessing the timing.

## Security: what this does and does not protect (read before deploying)
State this plainly to anyone who installs it, because the defaults invite the
wrong assumption.

**The USB channel is encrypted but not confidential.** The link runs TLS 1.2
(`PSK-AES128-CBC-SHA256`), so the bytes on the wire differ every session and look
like noise — but the pre-shared key is 32 zero bytes, forced by writing a fixed
blob that has been public in goodix-fp-dump for years. Anyone who knows the
protocol can decrypt. Choosing our own key is not possible: keys are written as a
96-byte blob wrapped by vendor white-box crypto, and only the one mapping to
all-zeros is publicly known. Every open-source Goodix driver is in this position.

**The sensor is match-on-host.** It has no on-chip matcher, so the raw image
crosses the bus and is processed in ordinary host memory. Nothing in software
changes that; it is a property of the silicon. Sensors that do match on-chip
exist and are supported by libfprint (`goodixmoc`, `elanmoc`, `fpcmoc`,
`synaptics`) — there the print never leaves the die.

**Enrolled templates are stored unencrypted.** fprintd writes them as plain files
under `/var/lib/fprint`; this is a long-standing upstream complaint, not
something this driver introduces. They are root-only, but on an unencrypted disk
they are readable by anyone who can pull the drive, and a template is enough to
reconstruct an image close to the original finger. `install-system.sh` checks and
warns. Use full-disk encryption, and keep SELinux/AppArmor enforcing — upstream's
own advice is that an LSM is the only thing protecting these files at runtime.

One thing is worth stating precisely, because it is easy to over-claim in either
direction: the stock Windows stack keys its templates from a separate key slot
on the sensor, which this driver does not touch. What happens after that — where
matching runs, how the templates are stored — is not observable from USB traffic,
so this document makes no claim about it.

**Reasonable position:** treat the fingerprint as a convenience factor, not a
security boundary. Keep disk encryption, the account password and anything
valuable on a real secret.

## Root cause #2 — FDT thresholds are per-sensor, not constants
The device reports its measured per-zone base level in the FDT_MODE reply
(4 header bytes, then 12 LE uint16). The vendor sends thresholds back as
**base >> 1** — verified 12/12 byte-exact against the Windows capture and then
live on this unit (`b5 cd c6 b7 b3 cc c5 bc b0 c5 bb b1`). The driver shipped
hardcoded **55b4** constants (`12 af 9a 87 …`), off by ~10x, so device-side
finger detection could never fire — which is why an earlier session concluded
"FDT doesn't block on this fw" and bolted on host-side frame polling.
With correct thresholds `FDT_DOWN`/`FDT_UP` do block (the send path already
passes timeout 0 = infinite), so capture is event-driven again: the frame is
taken from a settled press (diff ~771) instead of the rising edge (~420), and
`FDT_UP` waits for lift-off so the next baseline is not contaminated.
Implemented as `learn_fdt_thresholds()` + `build_fdt_payload()`.

## Real bugs found in the SIGFM matcher (libfprint/sigfm/sigfm.cpp)
- `match::operator<` read `(a.y<b.y) || ((a.y<b.y) && a.x<b.x)`, which is just
  `a.y<b.y` — a strict weak ordering on Y alone, so `std::set` treated every
  pair sharing a Y as duplicates and **silently discarded ~half of all
  matches**. This was the main cause of displacement intolerance.
- The final score is **quartic** in the surviving match count
  (`C(C(m,2),2) ≈ m⁴/8`), so `bz3_threshold = 72` is really a step function at
  `m ≥ 6`. That explains the bimodal "0 or 1451" scores, and why tuning
  `min_match` did nothing: it is read (two early-out guards in `sigfm.cpp`) but
  is never the decisive test, because the quartic score already rejects anything
  below `m = 6` at threshold 72.
- `asin()/acos()` received out-of-domain arguments (rounding) and returned NaN
  exactly in the **zero-rotation** case, i.e. a finger placed identically —
  every later comparison against NaN is false, so the best-aligned pairs were
  thrown away. Now clamped.
- The pairwise rotation-consistency test compared two **angles** with a
  *relative* difference (`1 - min/max <= 0.05`). That is wrong for angles twice
  over: the effective tolerance ranged from ~0.15 deg near zero to ~9 deg near
  pi, and it degenerated exactly at a quarter turn — one field is
  `acos(sin(theta))`, which is 0 at theta = 90 deg, so the test became 0/0 =
  NaN and a perfectly consistent 90-degree rotation was **always** rejected.
  Replaced with an absolute tolerance of 0.10 rad (~5.7 deg), uniform across
  the circle. Rotated presses went from 25% to 87.5% against the *same*
  single-orientation templates — no re-enrollment needed, confirming that
  SIFT's rotation invariance was fine and only this test was broken.

## The status LED — solved
The LED is switched by command **0xae**, which the community protocol notes call
`QUERY_MCU_STATE`. That name is why it went unfound for so long: it reads as a
harmless status poll, so it was never on the suspect list. It is a switch, and
the two payloads simply swap their first two bytes:

    0xae  00 01 32   ->  LED on
    0xae  01 00 32   ->  LED off

Confirmed on hardware. The stock driver sends these in strictly alternating
pairs (identical in both captures), lighting the sensor while it waits for a
finger — which is why the light only ever appeared during Windows' lock screen
and never under our driver.

Ruled out along the way, each tested on hardware: USB reset, USB autosuspend
(the device does suspend after 2 s, but forcing it active changes nothing),
arming via FDT_DOWN, `SET_POV_CONFIG` (0xac), `SET_DRV_STATE` (0xc4),
`GET_POV_IMG` (0xd2), `0xc6`, and the single config byte where we differ from
Windows (offset 192: ours 0x14, theirs 0x16). Also refuted: the theory that the
LED belongs to the power button / laptop EC — `/sys/class/leds` exposes no such
LED, yet Windows lit it from inside a VM whose only channel to the machine was
the passed-through USB sensor.

Wiring it up took two corrections, both of which showed up only on hardware:

1. The transport carries **one command at a time** — anything sent while a
   previous command is still awaiting its ACK is dropped with a warning. Firing
   the LED switch from inside a stage that also sent the next command meant that
   next command (FDT_DOWN) never went out: the scan stalled and the light stayed
   on with nobody left to clear it. The switch now gets SSM stages of its own.
2. The light must not be tied to a single attempt. Every verify attempt is a
   full activate/deactivate cycle driven from above, so clearing it on
   deactivate made it blink between a failed attempt and its retry, and
   re-sending "on" per retry toggled it physically. It is now switched on when
   entering the wait-for-finger state, skipped when already in that state
   (`led_is_on`), and cleared once in `dev_deinit()` — the device stays *open*
   across retries and is closed only when the system is genuinely finished, so
   that is the lifetime the light should track.

Tooling: `scripts/led_gui.py` is an interactive console — connect, then press
buttons for every candidate command and watch the light, with a free-form
command field for anything else. Being able to hit the same button repeatedly is
what settled "did it flicker or did I imagine it", which one-shot probes could
not.

## Image pipeline fixes
- `squash_frame_linear()` derived the whole 8-bit gain from the absolute
  min/max of a background-subtracted frame. The 55a4 has a hard-zero 1-pixel
  border (~4% of the frame) that pins `min` at 0, and `max` is a single pixel —
  so one hot pixel set the contrast of the entire image (SIFT keypoint counts
  swung 62..235 between presses). Replaced with a trimmed band: statistics over
  the interior only, clipped at the 2nd/98th percentile, out-of-band pixels
  clamped. Mirrors the vendor, which computes over a trimmed band too.
- The background frame was re-derived at the head of **every** scan, i.e.
  moments after the previous press with the plate still warm/moist. It is now
  captured once per activation (`empty_img_valid`) and dropped on deactivate,
  together with any frames left over from an aborted scan. The vendor does the
  same and is explicit about it: `"image base not valid, wait fdt up"`,
  `"new base invalid, using existing base"`.
- Enroll stages 10 → **16**: each stage stores one template covering a narrow
  patch of the finger, so wider coverage is what buys tolerance to the finger
  landing off-centre.

## THE root cause of the 0xd0 blocker (found via usbmon A/B)
The 55a4 firmware needs **~10–15 ms of quiet time right after the server's
final TLS flight (ChangeCipherSpec+Finished)** to finalize its TLS session.
The C driver sent the next command ~1 ms after the flight; the fw kept ACKing
all plaintext commands but never marked the TLS session ready, and answered
every GET_IMAGE with REQUEST_TLS_CONNECTION (0xd0). pyusb worked because
`tool.py` sleeps 10 ms there ("Important otherwise an USBTimeout error
occur") plus interpreter overhead. Fix: `g_usleep(15000)` after delivering
the final flight (goodix.c, TLS_HANDSHAKE_STAGE_CHANGE_CIPHER_S).

Proven-irrelevant along the way (each tested & refuted): TLS Finished
delivery (flights byte-identical 95/91), write padding, perpetual read-loop,
stacked IN URBs, SET_CONFIGURATION / port reset, PSK-read encoding, command
sequence (py_probe_cseq), 0xd4, payload bytes. Diagnosis method: usbmon
captures of failing C vs working Python (`scripts/research/usbmon_capture.sh`,
needs sudo) diffed to byte-and-URB level, plus observation of the stock driver
in operation as ground truth.

## Reconstruct everything (one command)
```
git clone https://github.com/Hydrogell/goodix-27c6-55a4-fingerprint-linux
cd goodix-27c6-55a4-fingerprint-linux && ./setup.sh
```
Builds `work/twd-libfprint/_build/examples/img-capture` (native driver) and
`work/goodix-fp-dump` (Python reference).
Build deps (Fedora): meson ninja-build gcc gcc-c++ libgusb-devel nss-devel
openssl-devel cairo-devel glib2-devel opencv-devel gobject-introspection-devel
libgudev-devel pixman-devel doctest-devel cmake.

Test: `G_MESSAGES_DEBUG=all work/twd-libfprint/_build/examples/img-capture /tmp/out.pgm`
(place a finger when it reaches await-finger; ~9.5 KB PGM 108x88 with ridges).

## What the patch (`55a4-driver.patch`) contains
Base = TheWeirdDev/libfprint `55b4-experimental` @ `d1ca62a`. On top:
- **THE FIX: 15 ms post-handshake quiet time** (goodix.c, see above).
- **on-demand single-URB reads**: bulk-IN URB submitted only after a command is
  written and while its ACK/reply is outstanding; `read_pending` guard ensures
  at most one in flight (mirrors pyusb; replaces the perpetual read-loop).
- **zero-padded 64-byte writes** exactly like pyusb (was: heap-garbage tail,
  then exact-length short packets — both wrong).
- **"obey 0xd0" robustness**: if the fw still answers GET_IMAGE with 0xd0,
  tear down TLS, re-handshake, retry the image (2 tries) — the fw actively
  participates in the re-handshake, so this self-heals transient cases.
- **PSK-read byte-exact with Python** (8-byte payload flags+len=0).
- **host-side finger-detect** (poll frames, diff vs `empty_img`) — added by this
  patch; the base revision has none. It backs up the device-side FDT gate rather
  than replacing it, and stops a glancing contact being captured as a print.
- **firmware 10063 + lenient fw check** (`GF32*_RTSEC_APP_100*` — chip
  flip-flops GF3208<->GF3268 across cold boots).
- **cipher `PSK:@SECLEVEL=0`**, TLS1.2 only (OpenSSL 3.5 dropped PSK-CBC).
- **scan_empty post-TLS preamble**: upload_config(0x90) + FDT baseline(0x36)
  before the calibration GET_IMAGE (mirrors the working Python order).

## Packaging status
`scripts/install-system.sh` already makes this permanent: it installs the built
library alongside the distro's own, points fprintd at it with a systemd drop-in,
and enables PAM fingerprint auth. That survives reboot and works at the login
screen. What is still open is proper distribution:
1. **RPM/COPR package** (cleanest): package this libfprint as
   `libfprint-goodix55a4` so dnf manages it; add a udev hwdb entry for
   27c6:55a4 (libfprint already ships one — verify uaccess).
2. **Port to current upstream libfprint** (1.94.10) and carry only the driver
   as a distro patch — the real "upstream-quality" path. This branch is
   1.94.6-era; the driver + sigfm need forward-porting.
3. Quick-and-dirty: `sudo ninja -C _build install` overwrites system libfprint
   — a DOWNGRADE (1.94.6 < 1.94.10), gets clobbered by updates. Not recommended.

The PAM wiring the installer performs is `authselect enable-feature
with-fingerprint` (Fedora), which puts fingerprint into GDM, login and sudo.

Matching quality: SIGFM is position-sensitive on the 88x108 sensor. If real
use is flaky, lower `min_match` (5→4) or `bz3_threshold`, or capture more
enroll frames. Watch false-accept rate if loosening.

## Files
- `../patches/55a4-driver.patch` — the whole driver diff (apply on base d1ca62a).
- `../scripts/research/usbmon_capture.sh` — sudo usbmon A/B capture (C vs Python).
- `../scripts/research/py_relay_probe.py` — Python reference capture.
- `../scripts/research/py_probe_cseq.py` — Python running the C command sequence.
