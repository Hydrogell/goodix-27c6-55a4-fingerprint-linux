# Security policy

This driver handles biometric data, so it is worth being precise about what is a
vulnerability here and what is a documented property of the hardware.

## Known and not a vulnerability

Please do not open a security report for these. They are real limitations, they
are documented in the README's Security section, and none of them can be fixed
by this project.

- **The USB channel uses a pre-shared key of 32 zero bytes.** The sensor only
  accepts a key wrapped by vendor white-box crypto, and the all-zeros blob is the
  only one that has ever been published. Anyone who knows the protocol can
  decrypt the channel. Every open-source Goodix driver is in this position; the
  alternative is no driver at all.
- **A USB capture of this sensor can be decrypted into fingerprint images.**
  That follows directly from the point above. It is why `CONTRIBUTING.md` tells
  you never to attach one.
- **`fprintd` stores enrolled templates unencrypted** under `/var/lib/fprint`.
  That is upstream `fprintd` behaviour, not something this driver introduces.
- **Matching happens on the host**, because the 55a4 has no on-chip matcher. The
  image crosses the bus and is processed in ordinary memory. No software change
  can alter that; it is a property of the sensor.

The honest summary, also in the README: treat this fingerprint as a convenience
factor, not a security boundary.

## Worth reporting privately

Anything that makes the driver *less safe than the above describes*. For example:

- it writes captured images or templates somewhere not documented here;
- the installer or the scripts do something with root that they should not, or
  create world-readable files holding sensor data;
- a way to make verification succeed against a finger that was not enrolled;
- the key-provisioning path writes to a slot other than `0xbb010003`, or damages
  the sensor.

## How to report

Use GitHub's private vulnerability reporting, on this repository's **Security**
tab → *Report a vulnerability*. That keeps the report invisible until it is
resolved.

**Do not attach a capture, a frame dump, or an image of a fingerprint** — not
even to a private report, and not even your own. If a trace is genuinely needed
to demonstrate the problem, say so and it can be arranged; `CONTRIBUTING.md`
explains how to record one that holds no biometric data.

There is no bounty, and no guaranteed response time — this is one person with one
laptop.

## Scope

This policy covers the patch in `patches/` and the scripts in this repository.

Problems in `libfprint`, `fprintd`, or the sensor firmware itself belong
upstream: [libfprint](https://gitlab.freedesktop.org/libfprint/libfprint) and
[fprintd](https://gitlab.freedesktop.org/libfprint/fprintd). If you are unsure
which applies, report it here and it will be forwarded.
