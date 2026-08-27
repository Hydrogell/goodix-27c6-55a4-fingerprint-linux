---
name: Bug report
about: The sensor does not work, or works badly
title: ''
labels: ''
assignees: ''
---

<!-- ------------------------------------------------------------------ -->
<!-- READ THIS BEFORE ATTACHING ANYTHING                                 -->
<!-- ------------------------------------------------------------------ -->

**Do not attach a USB trace or a captured image.** A `.pcapng` of this sensor is
your fingerprint in a file: the TLS channel uses a pre-shared key of 32 zero
bytes that has been public for years, so anyone who downloads the attachment can
decrypt it back into the images your finger produced. The same goes for `.pgm` /
`.raw` frame dumps, `otp.bin` (a unique per-device identifier), and screenshots
of a captured ridge pattern.

A GitHub attachment stays reachable by its URL after the issue is edited, closed
or deleted. There is no taking it back.

The terminal log below is plain protocol text — commands, ACKs, timings — and
diagnoses almost everything. See [CONTRIBUTING.md](../../CONTRIBUTING.md) if a
trace really does turn out to be necessary.

<!-- ------------------------------------------------------------------ -->

## What happens

<!-- What did you expect, and what happened instead? -->

## Your system

- Distribution and version:  <!-- cat /etc/os-release -->
- fprintd and libfprint:     <!-- rpm -q fprintd libfprint  |  dpkg -l fprintd libfprint-2-2 -->
- Kernel:                    <!-- uname -r -->
- Laptop model:
- Sensor, exact line:        <!-- lsusb -d 27c6: -->

## How you installed

- [ ] `./install.sh`
- [ ] `./setup.sh` + `scripts/install-system.sh`
- [ ] something else — please describe

## Log

Run this from the repository and paste the **terminal output**:

```sh
G_MESSAGES_DEBUG=all work/twd-libfprint/build/examples/img-capture /tmp/out.pgm
```

(If you used `./install.sh` there is no `work/` directory — run `./setup.sh`
first, which keeps the build tree.)

Delete `/tmp/out.pgm` afterwards: it is a picture of your fingertip.

```
paste the log here
```

## Anything else

<!-- Does it work in Windows? Did it ever work in Linux? Dual boot? -->
