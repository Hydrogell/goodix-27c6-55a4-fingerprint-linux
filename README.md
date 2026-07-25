# Goodix 27c6:55a4 fingerprint sensor on Linux

A working libfprint driver for the **Goodix 55a4** fingerprint sensor, as found
in the Lenovo ThinkBook 15 G2 ITL and other machines of that generation.

As of July 2026, no working open-source driver for the 55a4 was publicly
available: both the AUR package `libfprint-goodixtls-55x4` and the Fedora COPR
`d-k-bo/libfprint-goodixtls` support the 55b4 and say that "55a4 will be added
later". This repository is that later. If a maintained driver has appeared since
— check those two first — it is probably the better starting point, and the
protocol notes here still apply.

It is a patch on top of [TheWeirdDev/libfprint][fork] branch
`55b4-experimental`, plus the scripts to build, install and test it.

[fork]: https://github.com/TheWeirdDev/libfprint/tree/55b4-experimental

## Does this apply to me?

Run this:

```sh
lsusb | grep 27c6
```

If you see **`27c6:55a4`**, yes. (`ID 27c6:55a4 Shenzhen Goodix Technology
Co.,Ltd. Goodix FingerPrint Device`)

Machines known to ship this sensor, from
[linux-hardware.org][lhw] and from reports:

- Lenovo **ThinkBook** 13 / 14 / 15 — including 14-IIL (20SL), 14s IWL,
  and 15 G2 ITL (20VE), which is what this was developed on
- Lenovo **ThinkPad** E14 / E15
- Lenovo **IdeaPad 3 14**
- Lenovo **ZHAOYANG K4e**

linux-hardware.org lists **783 machines** carrying this device, and every single
one of them is recorded as *failed* — no working driver. That is the gap this
repository closes.

Distribution does not matter much: this was built on Fedora, but the sensor
reports the same failure on Ubuntu, Mint, Manjaro, Pop!_OS, Zorin and Kali. If
you are here because your Goodix fingerprint reader does not work in Linux and
`fprintd-enroll` says *"No devices available"* or your device never appears in
GNOME/KDE settings — this is the right place.

**Related but different:** if `lsusb` shows `27c6:55b4`, use
[libfprint-goodixtls-55x4][aur] instead; if it shows `27c6:5xxx` something else,
check [goodix-fp-dump][gfd] for whether your model is covered. The
`goodixmoc`-family sensors (match-on-chip) are supported by upstream libfprint
directly and need none of this.

[lhw]: https://linux-hardware.org/?id=usb:27c6-55a4
[aur]: https://aur.archlinux.org/packages/libfprint-goodixtls-55x4

## Status

Enrol and verify work through the stock `fprintd`, including PAM — screen
unlock, login and `sudo`. Measured on one unit, by one person, pressing a real
finger:

| | result |
|---|---|
| true accept, deliberate displacement | 87.5 % (7/8) |
| true accept, rotation up to 90° | 87.5 % (7/8) |
| true accept, cross-finger test run | 100 % (6/6) |
| **false accepts, 38 impostor presses** | **0** |

The impostor figure covers 14 presses with non-enrolled fingers identified
against every enrolled print, 12 against a single print, and 12 cross-finger
trials against a second enrolled finger — the hardest case, since two fingers of
one hand resemble each other more than two different people do.

Read that as "no gross hole was opened", not as a false-accept rate: 0/38 only
bounds it at roughly 8 % with 95 % confidence. A real figure needs hundreds of
trials, which is not reachable by hand.

## Install

Developed and tested on **Fedora 44**, against `fprintd` 1.94.5 and the distro's
own `libfprint` 1.94.10, kernel 7.1, Python 3.14. Nothing here is version-specific
in principle, and other distributions should work — but nobody has tried, so if
you are the first, a report either way is welcome.

Build dependencies first:

```sh
sudo dnf install meson ninja-build gcc gcc-c++ libgusb-devel nss-devel \
    openssl-devel cairo-devel glib2-devel opencv-devel \
    gobject-introspection-devel libgudev-devel pixman-devel doctest-devel cmake
```

Then:

```sh
git clone https://github.com/Hydrogell/goodix-27c6-55a4-fingerprint-linux
cd goodix-27c6-55a4-fingerprint-linux
./install.sh
```

`install.sh` builds in a temporary directory, installs, and **deletes the build
tree**. It asks for your password once, for the install step itself. Nothing is
left in your home directory afterwards, and you can delete the cloned repository
too — it is not needed to run the driver, only to uninstall it.

Then enrol:

```sh
fprintd-enroll          # 16 touches; vary the finger position between them
fprintd-verify
```

That is the whole thing. The rest of this file is for people who want to know
what it did to their system, or who want to work on the driver.

### Working on the driver instead

If you want to read the code, rebuild it, or run the accuracy harness, use the
developer path. It keeps the build tree — two checkouts and a Python virtualenv,
about 300 MB under `work/` — so you can edit and rebuild:

```sh
./setup.sh                              # keeps ./work/
sudo bash scripts/install-system.sh     # installs whatever is in ./work/
```

`scripts/led_gui.py` additionally needs Tk, which is not pulled in by the build
dependencies above: `sudo dnf install python3-tkinter`.

`scripts/fp-notify.sh` and `scripts/fp-stress.sh` wrap enrol and verify with
desktop notifications that tell you exactly when to press and what the result
was, which makes measuring far less tedious than watching a terminal.

`fp-stress.sh` runs the cross-finger matrix, so it needs **two** fingers
enrolled and refuses to start otherwise:

```sh
fprintd-enroll -f right-index-finger
fprintd-enroll -f right-thumb
scripts/fp-stress.sh          # 3 rounds -> 12 presses
```

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for regenerating the patch after an
edit, and [`docs/`](docs/) for the protocol notes and the full technical
account.

### What the installer does

It does **not** replace or downgrade your distribution's libfprint. The patched
build goes to `/opt/libfprint-goodix`, and a systemd drop-in points *only*
`fprintd` at it. Everything else on the system keeps using the distro library.

It also provisions the sensor key (see below), checks whether your fingerprint
templates land on an encrypted filesystem, and reports whether SELinux is
enforcing.

On an enforcing SELinux system it loads a one-rule policy module,
[`scripts/goodix_fprintd.te`](scripts/goodix_fprintd.te). OpenCV pulls in Intel
TBB, whose allocator probes `/proc/sys/vm/nr_hugepages`; fprintd's domain may
not read that, so Fedora raises an SELinux alert every time fprintd starts. The
rule is a `dontaudit` — it grants fprintd no access, it only stops the denial
being logged. The step is skipped if `checkmodule`/`semodule` are missing.

It enables fingerprint authentication system-wide — `authselect enable-feature
with-fingerprint` on Fedora — so GDM, `login` and `sudo` will all accept a
fingerprint afterwards. If you only want enrolment and testing, comment that
step out before running the installer.

`sudo bash scripts/uninstall-system.sh` removes the library, the systemd drop-in
and the policy module. Three things it does not undo: PAM keeps accepting
fingerprints — turn that off with `authselect disable-feature with-fingerprint`;
the key written into the sensor is permanent (it goes in a different slot from
the one the stock Windows driver uses — see [The sensor key](#the-sensor-key));
and any fingerprints you enrolled stay in `/var/lib/fprint`. Remove those with
`fprintd-delete $USER`.

## Security — read this before deploying

The defaults invite the wrong assumption, so plainly:

**The USB channel is encrypted but not confidential.** It runs TLS 1.2
(`PSK-AES128-CBC-SHA256`), so the wire bytes differ every session — but the
pre-shared key is 32 zero bytes, forced by writing a fixed blob that has been
public in [goodix-fp-dump][gfd] for years. Anyone who knows the protocol can
decrypt. Using our own key is not possible: keys are written as a 96-byte blob
wrapped by vendor white-box crypto, and only the all-zeros one is publicly
known. Every open-source Goodix driver is in this position.

**The sensor matches on the host.** It has no on-chip matcher, so the raw image
crosses the bus and is processed in ordinary memory. No software can change
that. Sensors that match on-chip exist and libfprint supports several
(`goodixmoc`, `elanmoc`, `fpcmoc`, `synaptics`) — there the print never leaves
the die.

**Templates are stored unencrypted.** `fprintd` writes them as plain files under
`/var/lib/fprint`; that is a long-standing upstream complaint, not something
this driver introduces. They are root-only, but on an unencrypted disk anyone
who can pull the drive can read them, and a template is enough to reconstruct an
image close to the original finger. Use full-disk encryption and keep an LSM
enforcing — upstream's own answer to this complaint is "run SELinux or AppArmor".

**Reasonable position:** treat the fingerprint as a convenience factor, not a
security boundary. Keep the disk, the account password and anything valuable on
a real secret.

[gfd]: https://github.com/goodix-fp-linux-dev/goodix-fp-dump

## The sensor key

The driver speaks TLS-PSK with an all-zero key, which the sensor only accepts
once the public "whitebox" blob has been written into it. That blob is not
device-specific and is not extracted from anyone's hardware — it ships in
goodix-fp-dump. Writing it is a one-time operation and the installer does it for
you (`scripts/provision_psk.py`, idempotent).

On dual-boot, being precise about what is known, because this is the part you
have to trust:

The slots are distinct, and that half is a code fact rather than an
observation. Windows keeps its key material in `0xbb010002`; the only slot
anything here writes is `0xbb010003` — goodix-fp-dump's `write_psk()`
(`preset_psk_write(0xbb010003, PSK_WHITE_BOX)` in `driver_55x4.py`), which is
what `provision_psk.py` calls. The C driver writes no key at all: it reads the
hash in `0xbb020007` and refuses to activate if it is wrong. No code path here
addresses `0xbb010002`, so provisioning does not touch what Windows keeps
there.

What Windows does afterwards was seen once, not measured. With the sensor
passed through to a Windows VM, after this unit had been provisioned, a Windows
session enrolled a fingerprint, and the USB trace of it shows the vendor driver
writing its own 324-byte DPAPI blob into `0xbb010002` — it provisions that slot
itself. A check afterwards found the whitebox key still in effect on the Linux
side. That is one session on one machine, and passthrough is not a real
dual-boot, so treat "both sides coexist" as an expectation with a single
observation behind it rather than a tested result. If Windows fingerprint login
does misbehave after you install this, re-enrolling under Windows should
restore it; either way please open an issue, because it would mean this section
needs correcting.

## What was actually wrong

The driver did not simply "not exist" — the 55b4 driver ran on this sensor and
matched about one press in three. Getting from there to here meant finding eight
separate defects. The interesting ones generalise well beyond this device:

- **Finger-detect thresholds are per-sensor, not constants.** The device reports
  its own measured per-zone base in the `FDT_MODE` reply and the vendor sends
  back `base >> 1`. The driver shipped hardcoded 55b4 values, off by ~10×, so
  device-side finger detection could never fire on a 55a4.
- **Three real bugs in the SIGFM matcher**, which affect every device using it:
  a comparator that reduced to ordering on `y` alone and silently discarded
  about half of all matches; an angle-consistency test using a *relative*
  difference on angles, which degenerates to `0/0` at exactly a quarter turn so
  a perfectly consistent 90° rotation was always rejected; and `asin`/`acos`
  domain overflow returning `NaN` precisely in the zero-rotation case.
- **The background frame was captured while a finger could still be on the
  plate**, which both produced phantom touches on lift-off and quietly corrupted
  every image, since frames are `|frame − background|`.
- **The status LED is switchable** by command `0xae` — the one the community
  protocol notes call `QUERY_MCU_STATE`, which is why nobody found it.

[`docs/TECHNICAL.md`](docs/TECHNICAL.md) has the full account with the
measurements. [`docs/PROTOCOL.md`](docs/PROTOCOL.md) has the protocol findings on
their own, for anyone working on other sensors in this family.

## Reporting problems and contributing

Reports from other 55a4 machines are the most useful thing anyone can send —
this was tested on exactly one unit. Read [`CONTRIBUTING.md`](CONTRIBUTING.md)
first: it says what to include, and, more importantly, **what never to attach**.
A USB trace of this sensor is your fingerprint in a file, and anyone who has the
file can decrypt it.

## Limitations and caveats

- Tested on exactly **one** 55a4 unit, by one person. Treat the numbers as
  indicative.
- FDT threshold learning is deliberately **restricted to the 55a4** by device
  id: the 55b4 ships three different threshold tables and applying one learned
  set to it would raise its finger-lift threshold by roughly a third, which
  would hang after every capture. If you have a 55b4 and want to try, the flag
  is `GOODIX_55X4_FLAG_LEARN_FDT` in `goodix55x4.h`.
- The touch threshold is calibrated on one finger. If capture is unreliable for
  you, override it: `GOODIX55X4_TOUCH_DIFF=200`.
- The base fork is libfprint 1.94.6-era. The matcher fixes are worth carrying
  upstream on their own; the driver itself has no upstream home, as freedesktop
  libfprint has no `goodixtls` tree at all.

## Credits and licensing

Built on [TheWeirdDev/libfprint][fork] (LGPL-2.1+), which is built on
[freedesktop libfprint](https://gitlab.freedesktop.org/libfprint/libfprint).
Protocol groundwork, the device config and the whitebox PSK come from
[goodix-fp-dump][gfd]. The patch in `patches/` is a derivative of libfprint and
carries LGPL-2.1+; the scripts in this repository are under the same terms.

### How the protocol behaviour was established

**No vendor code is included, and none was copied.** Everything in `patches/` was
written from scratch against libfprint's own API.

Three sources, all on the author's own hardware:

1. **USB traffic**, captured with `usbmon` while the stock Windows driver drove
   the sensor in a VM. This is where the command sequences, the timings and the
   threshold values come from.
2. **The device itself** — values it reports in its own replies, such as the FDT
   baselines that the `base >> 1` rule is derived from.
3. **The vendor's Windows driver, examined for interoperability.** A few facts in
   `docs/PROTOCOL.md` could not have come from the wire — the literal branch
   strings (`"image base not valid, wait fdt up"`) and the frame-selection rule.
   Those were read out of the shipped driver binary in order to work out why the
   sensor behaves as it does, and then re-implemented independently.

That third item is what interoperability reverse engineering is: studying an
interface you must talk to, in order to write something that talks to it. It is
explicitly permitted for this purpose in the EU (Directive 2009/24/EC, Art. 6)
and in the US (17 U.S.C. §1201(f)), and it is how every open driver for
undocumented hardware gets written. The result here is a description of
*behaviour*, not a copy of *expression* — no vendor code, structure or data was
carried across.

Prior open-source work is credited above; where a fact was already published by
[goodix-fp-dump][gfd] or the 55b4 packagers, this repository builds on it rather
than rediscovering it.
