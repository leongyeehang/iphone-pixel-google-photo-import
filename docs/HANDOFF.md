# Handoff — resume here

**Last worked: 2026-07-31.** Branch `v1.1-refinements-and-ledger`. Everything below is on
disk; nothing is lost if you come back in six months.

---

## TL;DR — what to do next

**One open decision, and it needs your eyes, not more analysis.**

15 test Motion Photos are sitting in `/Volumes/Aca_WD/media/Import from Image Capture/motion-ab-test/upload/`.
Push them to the Pixel, back them up, and look at them next to the iPhone originals. Then
pick a variant (or decide none is worth it) and record the verdict in
[the decision section below](#the-open-decision).

```sh
adb push "/Volumes/Aca_WD/media/Import from Image Capture/motion-ab-test/upload" /sdcard/DCIM/
adb reboot        # forces the media scan
# then: Google Photos -> Photos settings -> Backup -> Back up device folders -> enable "upload"
#       and confirm Backup quality = Original quality
```

Or drag the folder into `Internal Storage/DCIM/` with OpenMTP, which avoids the media-scan
problem entirely.

---

## The question that started this

Muxed Motion Photos play back worse in Google Photos than the same Live Photos on the
iPhone — *"moving left right with distortion on the image"* — while the still is perfect.

## What was proven (don't re-investigate these)

| Hypothesis | Verdict | Evidence |
|---|---|---|
| Renaming before muxing breaks pairing | **Ruled out** | `MotionPhoto2-main/motionphoto2.py:363-398` — under `--exif-match`, pairing is done entirely by `ContentIdentifier`; filenames are never consulted |
| Edited duplicates (`IMG_E####`) get mis-paired | **Ruled out** | Verified on real files: `IMG_1327` = `03CE6CCB…`, `IMG_E1327` = `92AD97DC…` — distinct IDs, each pairs correctly |
| `motionphoto2` is misconfigured | **Ruled out** | Output carries `MotionPhoto:1` and a correct `MotionPhotoPresentationTimestampUs`. Embedded video is the original HEVC stream, not re-encoded (3,186,192 → 3,186,311 bytes, container padding only) |

**Root cause: a format capability gap.** Apple stores playback-time correction data that
Google's Motion Photo format cannot hold — `mebx` camera-motion tracks (stabilisation),
`CleanAperture 1744x1308` inside `EncodedPixels 1920x1440` (a 9% crop margin), and
`LivePhotoStillImageTransform`. iOS applies all three live; Google Photos plays the raw
stream. Full write-up in [WORKFLOW.md §7](WORKFLOW.md#7-quirks-specific-to-this-library).

## The open decision

The experiment built 5 variants of 3 clips. All 15 verified clean: rotation preserved,
presentation timestamps restored through re-encode, all valid Motion Photos.

| Variant | What it does | Targets |
|---|---|---|
| `V0-control` | untouched — current pipeline | baseline |
| `V1-crop` | crop to clean aperture 1744×1308 | edge distortion |
| `V2-stab` | `vidstabdetect` + `vidstabtransform` | left-right wobble |
| `V3-crop-stab` | both | both |
| `V4-trim` | trim to ±0.6 s around the still marker | framing travel |

Measured motion reduction (lower = less frame-to-frame movement):

| Clip | V0 original | V3 crop+stab | Gain |
|---|---|---|---|
| `IMG_0830` (least movement) | 3.071 | 1.938 | **37%** |
| `IMG_0805` | 4.756 | 4.463 | 6% |
| `IMG_0897` (most movement) | 9.955 | 9.550 | 4% |

**Interpretation:** vidstab removes *jitter*, not deliberate camera movement. It helps a lot
on near-static handheld shots and barely at all when you were genuinely panning. No variant
can fix the latter — that motion is what you actually recorded.

### Record your verdict here

```
Date tested   :
Best variant  :
Worth adopting? (y/n) :
Notes         :
```

**If a variant wins:** add an opt-in flag to `run_mux_motionphoto.sh`, document the
quality/size trade-off, and note it is lossy so Originals must be retained. Full-backlog cost
is roughly 4,558 clips × ~2 encodes — budget several hours with `hevc_videotoolbox`.

**If none wins:** delete `tools/motion_ab_test.sh` and `motion-ab-test/`, and mark the
limitation as accepted in WORKFLOW.md §7 (already written up there as such).

---

## What was completed and verified this session

**Working tree is dirty on purpose — nothing is committed yet.** All changes are on disk.

| File | Change |
|---|---|
| `lib.sh` | Appended `Keys:CreationDate` to `PHOTO_VIDEO_DATE_TAGS`. Videos were being named in UTC (8 h early in SGT) because the chain ended on the offset-less `QuickTime:CreateDate`. Now videos and stills both resolve to local time |
| `test/test_rename.bats` | New ffmpeg-gated test: a video with both a UTC and a local-time tag must rename to local time |
| `test/test_lib.bats` | New contract test: both tag chains must end on the most-trusted tag |
| `README.md` | Config table, video tag chain, `Unreleased` changelog entry. Corrected the "why mux before rename" explanation — pairing is by `ContentIdentifier`, not filename |
| `docs/WORKFLOW.md` | **New.** Full end-to-end runbook: invariants, 8 stages with verification gates, R1–R8 recovery, library-specific quirks |
| `docs/CHECKLIST.md` | **New.** One-page tick-list version — same steps and gates, no prose |
| `tools/motion_ab_test.sh` | **New.** The experiment harness. Writes outside the repo (`MOTION_AB_WORK`) because a run produces ~100 MB |

**Verification:** `shellcheck *.sh` clean · `bats test` 35/35 pass. The new timezone test is
not vacuous — forcing the old tag chain makes it fail.

## Settled, don't revisit

- **Filename format stays `YYYYMMDD_HHMMSS`.** It is Google Camera's own convention, sorts
  correctly, and the timestamp is already a unique search key. A `_IMG_1234` suffix was
  considered and rejected — it only helps disambiguate 111 edited duplicates out of 10,472.
- **Timestamps are aligned to local time** (this was originally accepted as UTC, then changed
  on request).
- `DEPRECATEDScript/` no longer exists — it was deleted mid-session. WORKFLOW.md Appendix A
  was corrected accordingly.

## Known state of the library

| Path | State |
|---|---|
| `Import2here/Leong/iphone_photos/` | 10,472 files, 49 GB, **unprocessed**. 10,424 still `IMG_####`, 4,558 Live Photo pairs, 111 `IMG_E` edited versions, 100 `.AAE` sidecars |
| `IphonePhotoOriBeforeMux/` | 22,934 files, **already renamed** (22,810) despite the name — it is not a pristine pre-mux archive. Worth renaming to something honest before it misleads you |
| `motion-ab-test/` | The 15 experiment files + `report.tsv` |

## Two loose ends

1. **Nothing is committed.** Run `git status` to see the six changed/new files. Commit when
   you're happy with them.
2. **The 49 GB backlog has never been run through the pipeline.** When you're ready:
   `./masterscript.sh --dry-run "$LIB/Import2here/Leong/iphone_photos"` first, then drop
   `--dry-run` and add `--size 10G`. See [CHECKLIST.md](CHECKLIST.md).
