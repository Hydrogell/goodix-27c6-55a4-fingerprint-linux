# Contributing

## Reporting a bug without sending your fingerprint

Read this first: the obvious way to debug this device is also the one way to leak
biometric data. **A USB trace of this sensor is your fingerprint in a file.** The
TLS channel uses a pre-shared key of 32 zero bytes, public for years (see the
README's Security section), so anyone who obtains the capture can decrypt it into
the images your finger produced. A trace cannot be scrubbed after the fact. So a
bug report is text, not captures. Include:

- distro and version (`cat /etc/os-release`)
- your fprintd and libfprint versions — `rpm -q fprintd libfprint`, or
  `dpkg -l fprintd libfprint-2-2` on Debian and Ubuntu (the fprintd tools
  reject `--version`, and libfprint is a library, so ask the package manager)
- the exact output line from `lsusb -d 27c6:`
- a run of the image-capture test, from the repository root, with debug logging:

```sh
G_MESSAGES_DEBUG=all work/twd-libfprint/_build/examples/img-capture /tmp/out.pgm
```

Paste the **terminal output** of that command — a protocol log of commands, ACKs,
state transitions and timings, which is what diagnoses almost everything.

Do not attach:

- **`.pcapng` / `.pcap` / `.cap` traces** — decryptable into fingerprint images
  by anyone who downloads them.
- **`.pgm` / `.raw` frame dumps**, including the `/tmp/out.pgm` written above —
  that file is the picture of your fingertip, which is the whole point of it;
  delete it when you are done.
- **`otp.bin` or any device snapshot** from `scripts/research/dump_snapshot.py` —
  the OTP block is a unique per-device identifier.
- **Screenshots or photos of the captured image** — a ridge pattern is just as
  usable to an attacker as the file it came from.

`.gitignore` blocks these patterns as a safety net, not as a substitute for care.

## If a maintainer does ask for a trace

Sometimes the log is not enough and someone will ask. Then:

- **Capture without a real finger where possible.** Most protocol-level failures
  — TLS handshake, the `0xd0` loop, config upload, firmware detection — happen
  before any image exists, so a trace taken with nothing on the plate reproduces
  them and holds no biometric data. If a press is required, use a knuckle, a
  fingernail or a rubber eraser, not a finger you authenticate with.
- **Send it privately**, not as an issue attachment: an attachment on a public
  issue stays reachable by its URL after the issue is edited, closed or deleted.
- **Delete it afterwards.** `scripts/research/usbmon_capture.sh` writes outside
  the repository by default for this reason.

## Sending patches

The driver is carried as a single diff, `patches/55a4-driver.patch`, against a
pinned base: **TheWeirdDev/libfprint**, branch `55b4-experimental`, commit
`d1ca62a`. The pin is deliberate — the context hunks apply only to that revision,
and the branch tip moves.

`./setup.sh` clones that base into `work/twd-libfprint` and applies the patch to
the working tree, so the checkout is "base + patch, uncommitted". Edit the source
there, rebuild with `ninja -C _build`, then regenerate the diff:

```sh
cd work/twd-libfprint
git diff > ../../patches/55a4-driver.patch
```

Regenerate **before** re-running `./setup.sh` — it starts with `git checkout -- .`
and discards uncommitted work. The patch touches five existing files and adds
none; if you add a file, `git add -N` it first or `git diff` will miss it.

Send the regenerated patch with a note on what you measured. Behavioural claims
should come with numbers or a log, in the style of `docs/TECHNICAL.md`.

## Scope

This has been tested on exactly one 55a4 unit, by one person; the README's
numbers are indicative, not a characterisation. So the useful contributions are:

- **A report from another 55a4 machine**, working or not. linux-hardware.org
  lists 783 of them; this driver has seen one. If capture is unreliable, try
  `GOODIX55X4_TOUCH_DIFF=200` first and say which value worked.
- **A report from a 55b4.** FDT threshold learning is restricted to the 55a4 by
  device id, because the 55b4 ships different threshold tables; the flag to try
  it anyway is `GOODIX_55X4_FLAG_LEARN_FDT` in `goodix55x4.h`. Nobody has.
- **Forward-porting.** The base is libfprint 1.94.6-era. The SIGFM matcher fixes
  are worth carrying upstream on their own; the driver has no upstream home,
  since freedesktop libfprint has no `goodixtls` tree.

Protocol findings for other sensors in this family belong in `docs/PROTOCOL.md`.

## Licence

Contributions are accepted under **LGPL-2.1-or-later**, matching libfprint and
the base fork; the repository ships the LGPL-2.1 text in `LICENSE`. By sending a
patch you state that you have the right to contribute it under those terms. No
CLA, no copyright assignment. Do not include vendor code, firmware blobs or
material extracted from the Windows driver.
