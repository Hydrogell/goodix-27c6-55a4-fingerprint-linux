<!-- Before anything else: do not attach a .pcapng, a .pgm/.raw frame dump, or an
     image of a fingerprint. A capture of this sensor decrypts into fingerprint
     images with a publicly known key. See CONTRIBUTING.md. -->

## What this changes

<!-- One or two sentences. If it fixes an issue, link it. -->

## How it was tested

- Sensor and machine:  <!-- lsusb -d 27c6:  + laptop model -->
- Distribution:
- [ ] built with `./setup.sh`
- [ ] enrolled and verified with a real finger

If the change affects matching or capture, say what you measured and how many
presses it took. Numbers are how everything else in `docs/TECHNICAL.md` is
justified, and a behavioural claim without them cannot be checked.

## If you edited the driver source

The driver ships as one diff against a pinned base, so source edits do not
count until the patch is regenerated:

```sh
cd work/twd-libfprint
git diff > ../../patches/55a4-driver.patch
```

Do this **before** re-running `./setup.sh` — it starts with `git checkout -- .`
and will discard your work.

- [ ] `patches/55a4-driver.patch` regenerated, and CI's "patch applies" job passes

## Attribution

- [ ] If this is based on someone else's branch, patch or reverse-engineering,
      they are credited in the README and at the code site

This matters here: the host-side finger-detect poll in this repository is
sidevesh's work and reached it without credit for a while. Please do not let
that happen again.
