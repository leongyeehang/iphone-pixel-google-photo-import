# The Full Workflow: iPhone → Mac → Pixel 1 → Google Photos

**Purpose of this document.** This is the runbook. It exists so that when something goes
wrong — a half-finished import, a batch you can't remember uploading, a phone you wiped too
early — you can find out *what state you are in* and *what to do next* without guessing.

> **Doing an import right now?** Use **[CHECKLIST.md](CHECKLIST.md)** — same steps, same
> gates, no prose. Come back here when a step doesn't behave.

Read [Invariants](#invariants) once. After that, [Per-import runbook](#per-import-runbook)
is the reference behind each checklist step, and
[Recovery](#recovery-i-did-something-wrong) is the part you read when you're worried.

**Verified on:** macOS 26.5.2 · exiftool 13.36 · motionphoto2 (MotionPhoto2) · adb ·
toolkit v1.1.0 · target device Google Pixel 1 (Android 10).

---

## Table of contents

1. [Why this workflow exists](#1-why-this-workflow-exists)
2. [Glossary](#2-glossary)
3. [Invariants](#invariants)
4. [One-time setup](#4-one-time-setup)
5. [Per-import runbook](#per-import-runbook)
6. [Recovery: I did something wrong](#recovery-i-did-something-wrong)
7. [Quirks specific to *this* library](#7-quirks-specific-to-this-library)
8. [Appendix A: current disk state and the backlog](#appendix-a-current-disk-state-and-the-backlog)
9. [Appendix B: quick reference card](#appendix-b-quick-reference-card)

---

## 1. Why this workflow exists

Google gave the **Pixel 1** free, unlimited, permanently-grandfathered backup of photos at
**original quality**. No other device gets this. Every photo that reaches Google Photos
*through a Pixel 1* is stored at full resolution and does not count against your storage
quota, forever.

So the Pixel 1 is not a phone in this workflow. It is a **one-way upload appliance**. Photos
go onto it, Google Photos ingests them at original quality, and they are deleted from it to
make room for the next batch.

Two things make this non-trivial:

- **iPhone Live Photos don't survive the trip.** A Live Photo is two files — `IMG_1234.HEIC`
  plus `IMG_1234.MOV`. Android/Google Photos has no concept of that pairing. Uploaded as-is,
  you get a still photo and an unrelated 3-second video clip. **Muxing** fuses them into a
  single Google Motion Photo (the video embedded inside the image file) so the motion
  survives.
- **The Pixel 1 has 32 GB or 128 GB of storage.** A multi-year camera roll does not fit.
  Hence **batches**: the library is packed into size-capped folders that fit on the device
  one at a time.

---

## 2. Glossary

Precise words, used consistently throughout this document. If you catch yourself using one
of these loosely, come back here.

| Term | Meaning |
|---|---|
| **Roll** | The iPhone's camera roll — the authoritative source. Everything starts here. |
| **Import** | One Image Capture session: a contiguous date range of the Roll copied to the Mac into one dated folder. The unit of work for this entire workflow. |
| **Import folder** | The dated folder on the Mac holding one Import's files, with their **original iPhone names** (`IMG_0001.HEIC`). Never renamed by hand. |
| **Original** | A file exactly as it left the iPhone — untranscoded HEIC/HEVC, full resolution. If it has been re-encoded, it is not an Original. |
| **Live Photo** | An iPhone still + its companion `.MOV`, sharing a base name and a `ContentIdentifier`. Two files, one moment. |
| **Motion Photo** | The Google/Android equivalent: **one** file, video embedded inside the image, marked with an `XMP-GCamera:MotionPhoto` tag. The output of muxing. |
| **Muxing** | Fusing a Live Photo pair into a Motion Photo. Done by `motionphoto2`. Must happen **before** renaming. |
| **Results directory** | `<import folder>/muxed-photo/` — everything the script produces. Originals live outside it and are never touched. |
| **Batch** | One `YYMMDD-YYMMDD-#.#GB/` folder inside the Results directory. The unit of transfer to the Pixel. |
| **Ledger** | `library-ledger.tsv` inside the Results directory. One row per completed script run: date range, counts, size, batch count. |
| **Cut point** | The timestamp separating "already imported" from "not yet imported". Always a **midnight day boundary**. See [Stage 0](#stage-0-decide-the-cut-point). |
| **Upload log** | `upload-log.md` — a hand-maintained file recording which Batches you have *confirmed* landed in Google Photos. The Ledger records what was *processed*; the Upload log records what was *backed up*. These are different facts. |

> **A distinction worth burning in:** the Ledger is written automatically and says *"the
> script finished."* The Upload log is written by you and says *"Google has it."* Never treat
> the first as evidence of the second. Almost every way this workflow can lose a photo lives
> in the gap between those two statements.

---

## Invariants

Break one of these and the workflow stops being trustworthy. They are listed in order of how
badly it hurts.

1. **Never delete from the iPhone until the Upload log says the photos are in Google Photos.**
   The Roll is your only complete copy until Google has it. The Mac copy is a staging area,
   not a backup.
2. **Never rename an Import folder's files by hand.** Mux-before-rename is load-bearing (see
   §7). Hand-renaming breaks Live Photo pairing silently — you don't get an error, you get a
   still photo and an orphan clip.
3. **One Import per folder, named by date.** Two Imports in one folder means two date ranges
   in one Ledger row and no way to reason about what's been uploaded.
4. **Cut points are always midnight day boundaries.** Never mid-day. A mid-day cut splits a
   day across two Imports and makes "have I uploaded 2026-07-14?" unanswerable.
5. **Point the script at the folder that directly contains the files.** The scripts are
   `find -maxdepth 1` — **non-recursive by design**. Point them one level too high and they
   do nothing, silently and successfully.
6. **The Pixel's Google Photos backup quality must be "Original quality".** If it's on
   "Storage saver", you are burning the entire point of this workflow and you won't be told.
7. **Originals stay on the Mac until the Batch is confirmed uploaded.** Delete the Results
   directory freely once confirmed — it's reproducible. Deleting Originals is not reversible.

---

## 4. One-time setup

Do this once. Re-verify §4.1 and §4.3 whenever iOS or the Pixel updates, because updates
reset settings.

### 4.1 iPhone

**A. Turn off transcoding on transfer.**

> Settings → Photos → scroll to **Transfer to Mac or PC** → select **Keep Originals**

`Automatic` silently converts HEIC→JPEG and HEVC→H.264 on the way out. That is a lossy
re-encode of every single file. `Keep Originals` transfers the bytes as they are.

**B. Make sure the originals are actually *on* the phone.**

> Settings → Photos → check the iCloud Photos section

- If **iCloud Photos is OFF** — nothing to do, everything is local.
- If **iCloud Photos is ON** and set to **Optimize iPhone Storage** — ⚠️ **stop.** Full-
  resolution originals are in iCloud, not on the device. Image Capture will either import
  reduced-resolution versions or fail on those files. Switch to **Download and Keep
  Originals** and wait for the download to finish (Settings → Photos shows progress) before
  importing anything.
- If **iCloud Photos is ON** and set to **Download and Keep Originals** — good.

**How to confirm you got Originals** (run after your first Import):

```sh
# A modern iPhone still should be multi-megapixel HEIC, not a small JPEG.
exiftool -s3 -FileType -ImageSize -FileSize "$(ls *.HEIC | head -1)"
# Expect something like:  HEIC   5712x4284   2.2 MB
```

If your `.HEIC` files came through as `.JPG`, `Keep Originals` was not set. Re-import.

### 4.2 Mac

Already installed and verified on this machine:

```sh
exiftool -ver         # 13.36
command -v motionphoto2   # /usr/local/bin/motionphoto2
command -v adb            # /opt/homebrew/bin/adb
```

If you ever need to reinstall:

```sh
brew install exiftool
# motionphoto2: download the release binary from
#   https://github.com/PetrVys/MotionPhoto2/releases
#   chmod +x it and put it on your PATH
brew install --cask android-platform-tools   # provides adb
```

**File transfer to the Pixel.** Google's *Android File Transfer* is abandoned and does not
work on macOS 26. Install **OpenMTP** instead — free, open-source, actively maintained,
native Apple Silicon:

```sh
brew install --cask openmtp
```

`adb` is the scriptable alternative; see [Stage 5](#stage-5-transfer-a-batch-to-the-pixel)
for when to use which.

### 4.3 Pixel 1

**A. Confirm the grandfathered upload quality.**

> Google Photos app → your avatar → **Photos settings** → **Backup** → **Backup quality** →
> must read **Original quality**

On a Pixel 1 this should also indicate the storage is free/unlimited. If it says *Storage
saver*, change it. This is invariant #6 and it is the single most expensive setting in the
whole workflow to get wrong.

**B. Don't update the Google Photos app unnecessarily.** The unlimited-original entitlement
is tied to the device, but a future app version dropping Android 10 support would strand
you. If it works, leave it alone.

**C. Enable USB debugging** (only needed if you use `adb` rather than OpenMTP):

> Settings → About phone → tap **Build number** seven times → back → System →
> **Developer options** → **USB debugging** ON

Then plug in the USB-C cable and run `adb devices` on the Mac; accept the RSA fingerprint
prompt on the phone. You should see the serial listed as `device`, not `unauthorized`.

**D. Find out how much room you actually have:**

```sh
adb shell df -h /sdcard
```

This determines your Batch size. See [Stage 3](#stage-3-run-the-script).

### 4.4 Folder layout on the Mac

Proposed canonical layout. Your existing folders don't match it yet — see
[Appendix A](#appendix-a-current-disk-state-and-the-backlog) — but new Imports should:

```
/Volumes/Aca_WD/media/Import from Image Capture/
├── script/                      ← this toolkit
│   └── docs/WORKFLOW.md         ← this document
├── upload-log.md                ← you maintain this
└── library/
    └── 2026-07-28/              ← ONE Import. Original names.
        ├── IMG_0001.HEIC
        ├── IMG_0001.MOV
        ├── ...
        └── muxed-photo/         ← Results directory (script output)
            ├── workflow.log
            ├── library-ledger.tsv
            ├── 260701-260714-14.8GB/    ← Batch 1
            └── 260714-260728-11.2GB/    ← Batch 2
```

One folder per Import date means files from different Imports can never collide, which is
why no manual renaming is ever needed.

---

## Per-import runbook

Set this once per session so the commands below are copy-pasteable:

```sh
LIB="/Volumes/Aca_WD/media/Import from Image Capture"
SCRIPT="$LIB/script"
IMPORT="$LIB/library/$(date +%Y-%m-%d)"     # today's Import folder
```

---

### Stage 0: Decide the cut point

**Goal:** know the exact date from which to import, with no gap and no overlap.

#### 0a. Read your own record first

```sh
# The most recent completed run, from the newest Ledger:
find "$LIB/library" -name library-ledger.tsv -exec tail -n +2 {} \; | sort | tail -3 | column -t -s $'\t'
```

The `date_to` column of the last row is what the script last *processed*. Then check
`upload-log.md` for what you last *confirmed uploaded*. **The lower of the two is your true
high-water mark.**

#### 0b. Cross-check against Google Photos

Open Google Photos (on the Pixel, or photos.google.com) and scroll to the newest photo.
Note its date.

- **It matches your Upload log** → good, they agree. Proceed.
- **Google Photos is behind your Upload log** → a batch you marked confirmed did not fully
  land. Go to [Recovery §R5](#r5-google-photos-is-missing-photos-i-thought-i-uploaded).
- **Google Photos is ahead** → you uploaded something and forgot to log it. Update
  `upload-log.md` and proceed.

#### 0c. Set the cut point at a midnight boundary

> **Import from 00:00 on the day after your confirmed high-water mark, up to 23:59 on
> *yesterday*. Leave today's photos for the next Import.**

Example: high-water mark is `2026-07-14`, today is `2026-07-28`. Import
**2026-07-15 through 2026-07-27**. Today (the 28th) is still accumulating, so it waits.

**Why day boundaries and not "the exact last photo".** A Batch is cut at a 15 GB size limit,
not at a date. That limit lands wherever it lands — very often in the middle of a day. If
you cut your *next* Import at the last uploaded photo's timestamp, and that timestamp was
14:30 on the 14th, you will either skip the 14th's afternoon or re-import it. Day boundaries
make "have I done the 14th?" a yes/no question.

#### ⚠️ The hole in "just check Google Photos", and what to do about it

You asked to use Google Photos to decide where to start. It works, but understand its
failure mode before you rely on it:

**Google Photos sorts by *capture* date, not *upload* date. The iPhone Roll does too. So a
photo that enters the Roll *later* but was *taken* earlier is invisible to a date-based
cut — forever.**

This happens more than you'd think:

- A friend AirDrops you photos from last month's trip.
- You save an image from WhatsApp/Messages taken weeks ago.
- You restore an old iCloud/iTunes backup.
- You scan a physical photo (which gets a very old capture date).

All of these land *behind* your cut point and will never be picked up by any future Import.

**Mitigation — a quarterly reconciliation.** Every few months, compare totals rather than
dates:

```sh
# Total media the Mac has ever held for this library:
find "$LIB/library" -type f \( -iname '*.heic' -o -iname '*.jpg' -o -iname '*.mov' \
     -o -iname '*.png' -o -iname '*.dng' -o -iname '*.mp4' \) -not -path '*/muxed-photo/*' | wc -l
```

Compare against the iPhone's own count (Photos app → Library → scroll to the bottom, it
shows "N Photos, M Videos"). A widening gap means back-dated arrivals you've missed. When
that happens, do one targeted Import of the specific date range you know the strays came
from.

**The bulletproof alternative, once you trust the pipeline.** Tick **"Delete after import"**
in Image Capture. Then the Roll *is* the queue — anything on the phone is by definition not
yet imported, and there is no cut point to get wrong. This eliminates the entire class of
problem. It is also irreversible if the pipeline fails downstream, so do not enable it until
you have run several Imports end-to-end without incident, and never enable it on an Import
you haven't verified. **Recommendation: leave it off for now.**

---

### Stage 1: Import from the iPhone with Image Capture

1. **Create the Import folder first**, so you never import into the wrong place:
   ```sh
   mkdir -p "$IMPORT" && open "$IMPORT"
   ```
2. Connect the iPhone by USB. **Unlock it** and tap **Trust This Computer** if prompted.
   A locked phone shows up as an empty device.
3. Open **Image Capture** (`/Applications/Image Capture.app`). Select the iPhone under
   **DEVICES** in the sidebar. Let the thumbnail list finish loading — on a large Roll this
   takes several minutes and the window looks frozen while it works. Wait it out.
4. Switch to **list view** (the toggle at the bottom-left of the window). You now get
   sortable **Name / Kind / Date / Size** columns.
5. **Sort by Date** (click the Date column header) so the Roll is in chronological order.
6. Set **Import To:** at the bottom to your Import folder (`$IMPORT`).
7. **Leave "Delete after import" UNCHECKED.** (See invariant #1.)
8. **Select your date range:** click the first file on your cut-point date, scroll to the
   last file of yesterday, **shift-click** it. Verify the selection count shown at the
   bottom looks plausible.
9. Click **Import** — *not* **Import All**. `Import All` ignores your selection.
10. Wait. This is slow: expect roughly 30–60 minutes per 10 GB over USB, more if the phone
    is warm or throttling.

**Notes on Image Capture's behaviour**

- Exact control labels shift slightly between macOS releases; the *functions* above are
  stable. If a label doesn't match, look for the equivalent control.
- If it errors out partway with something like `Could not be imported (error -21345)`, the
  usual causes are a locked phone, a flaky cable, or iCloud "Optimize Storage" (see §4.1B).
  Image Capture **does not resume** — see [Recovery §R1](#r1-image-capture-died-partway-through).
- Selecting by date only works if the Date column is what you think it is. It's the file's
  creation date on the device, which is capture date for camera photos but *not* for
  AirDropped or app-saved files. This is the same hole described in Stage 0c.

---

### Stage 2: Verify the Import — before you touch the script

Do not skip this. Every later stage assumes the Import folder is complete and intact, and
every recovery procedure is far cheaper here than three stages downstream.

```sh
cd "$IMPORT"

# 1. What did you actually get?
echo "Total files: $(find . -maxdepth 1 -type f ! -name '.*' | wc -l | tr -d ' ')"
ls | sed 's/.*\.//' | sort | uniq -c | sort -rn

# 2. Zero-byte files = failed/truncated transfers. Must be empty.
find . -maxdepth 1 -type f -size 0

# 3. Corrupt or unreadable files. Must print nothing.
#    NOTE: this exits with status 2 when nothing matches. Status 2 + no output is the
#    GOOD result — it means "no file met the error condition". Judge by the output, not $?.
exiftool -q -q -p '$FileName' -if '$Error' . 2>/dev/null

# 4. Originals check — HEIC should still be HEIC at full resolution.
exiftool -s3 -FileType -ImageSize "$(ls *.HEIC 2>/dev/null | head -1)"

# 5. Date range actually covered — should match your intended cut window.
exiftool -q -q -d '%Y-%m-%d' -p '$DateTimeOriginal' -ext heic -ext jpg . 2>/dev/null \
  | sort -u | sed -n '1p;$p'

# 6. Live Photo pairs waiting to be muxed:
echo "Pairs: $(ls | sed 's/\.[^.]*$//' | sort | uniq -d | wc -l | tr -d ' ')"
```

**What each result means**

| Check | Expected | If not |
|---|---|---|
| Total files | Roughly the Image Capture selection count | [R1](#r1-image-capture-died-partway-through) |
| Extensions | `HEIC`/`JPG`/`MOV` dominant. Seeing mostly `JPG` where you expected `HEIC` means transcoding | Fix §4.1A, re-import |
| Zero-byte | Empty output | Delete those files, re-import just them |
| `$Error` | Empty output | [R2](#r2-some-files-are-corrupt) |
| FileType | `HEIC`, multi-megapixel | §4.1A/B wrong, re-import |
| Date range | Matches your cut window | Wrong selection in Image Capture; re-select and re-import |
| Pairs | Non-zero if you shoot Live Photos | If zero and you expected pairs, `.MOV` companions didn't transfer |

**Only when all six pass, take a backup of the Originals** (optional but cheap insurance,
and this is the last moment where a single copy exists):

```sh
cp -Rp "$IMPORT" /Volumes/SomeOtherDrive/
```

---

### Stage 3: Run the script

**Always dry-run first.** It writes nothing, creates nothing, and shows you exactly what
would happen:

```sh
"$SCRIPT/masterscript.sh" --dry-run "$IMPORT"
```

Read the output. Confirm the rename previews look like real capture dates and the batch
folders are the sizes you expect. (Muxing can't be previewed — it writes files — so dry-run
skips it and previews rename/group against the input.)

**Pick your Batch size from the Pixel's free space**, not from habit:

```sh
adb shell df -h /sdcard      # with the Pixel connected
```

Rule of thumb: **Batch size ≤ 50% of the Pixel's free space.** Google Photos needs working
room for its upload cache, and a full `/sdcard` fails in confusing ways. On a 32 GB Pixel 1
(~24 GB usable, less whatever's installed) that means **10G**, not the 15G default. On a
128 GB Pixel, 15G–30G is fine.

**Then the real run:**

```sh
"$SCRIPT/masterscript.sh" --size 10G "$IMPORT"
```

What happens, in order:

| Step | Action | Output |
|---|---|---|
| 1 | Mux Live Photos (`motionphoto2 --exif-match --copy-unmuxed`) | `$IMPORT/muxed-photo/` — Originals untouched |
| 2 | Rename everything to `YYYYMMDD_HHMMSS` by EXIF date | in place, inside `muxed-photo/` |
| 3 | Pack into `YYMMDD-YYMMDD-#.#GB/` Batches | subfolders of `muxed-photo/` |
| — | Print a summary, append a Ledger row, save `workflow.log` | `muxed-photo/library-ledger.tsv` |

**Duration:** muxing 4,500 pairs takes a long while — budget an hour or more for a 50 GB
Import. It's safe to leave running.

**If it's interrupted** (Ctrl-C, crash, sleep, drive unmount): just re-run the identical
command. Checkpoints in `$IMPORT/.workflow/` make it skip completed steps and resume. They
are removed automatically on success.

**Useful variations:**

```sh
# Different output folder name
"$SCRIPT/masterscript.sh" --output-name organized "$IMPORT"

# No batching — one flat folder of renamed files
"$SCRIPT/masterscript.sh" --skip-group "$IMPORT"

# Config via environment instead of flags (flag > env > built-in default)
PHOTO_GROUP_SIZE=10G "$SCRIPT/masterscript.sh" "$IMPORT"
```

**Re-batching at a different size** — you don't need to re-mux or re-rename:

```sh
"$SCRIPT/ungroup.sh"        "$IMPORT/muxed-photo"              # flatten the Batches
"$SCRIPT/group_files_size.sh" --size 8G "$IMPORT/muxed-photo"  # re-pack
```

`ungroup.sh` only touches folders matching `YYMMDD-YYMMDD-*GB`, never deletes files, and
skips name collisions with a warning.

---

### Stage 4: Verify the Results directory

```sh
RESULTS="$IMPORT/muxed-photo"

# The run's own summary — date range, counts, size, batch count:
column -t -s $'\t' "$RESULTS/library-ledger.tsv"

# The Batches you're about to transfer:
ls -dlh "$RESULTS"/*GB/

# Did the muxing actually work? Count real Motion Photos:
exiftool -q -q -if '$XMP-GCamera:MotionPhoto' -p '$FileName' -r "$RESULTS" | wc -l

# Nothing left stranded outside a Batch (only logs/ledger should remain at the top level):
find "$RESULTS" -maxdepth 1 -type f ! -name '.*'

# Sanity: no zero-byte output
find "$RESULTS" -type f -size 0
```

**Interpreting the Motion Photo count.** It should be close to the pair count from Stage 2.
Materially lower means muxing skipped files — check `$RESULTS/muxing_errors.log` if it
exists. A count of zero when you had thousands of pairs means muxing didn't run at all; see
[R3](#r3-the-motion-photo-count-is-zero-or-far-too-low).

**Spot-check one Motion Photo visually.** Open a muxed `.HEIC` in Preview — it should look
like a normal photo. The embedded video isn't visible on macOS; it only comes alive in
Google Photos. That's expected, not a failure.

---

### Stage 5: Transfer a Batch to the Pixel

Transfer **one Batch at a time**. Upload it, confirm it, delete it, then the next. Do not
try to fit two.

#### Option A — OpenMTP (recommended)

1. Connect the Pixel by USB. On the phone, the USB notification → set mode to **File
   Transfer / MTP** (it defaults to charging only).
2. Open **OpenMTP**. Mac filesystem on the left, phone on the right.
3. On the phone side, navigate to **`Internal Storage / DCIM /`**.
4. Drag one Batch folder (e.g. `260701-260714-9.8GB/`) from the Mac side into `DCIM/`.
5. Wait for the transfer to complete.

**Why `DCIM/`:** Google Photos treats folders under `DCIM` as camera-ish *device folders*
and offers them for backup. A folder elsewhere on the device may not be offered at all.

**Why MTP over adb:** MTP writes register with Android's MediaStore as they happen, so
Google Photos sees the new files immediately. `adb push` writes straight to the filesystem
and can leave MediaStore unaware of them.

#### Option B — adb push (scriptable, faster, one extra step)

```sh
BATCH="$RESULTS/260701-260714-9.8GB"

adb devices                                   # confirm: <serial>  device
adb push "$BATCH" /sdcard/DCIM/

# Verify the file count landed intact:
adb shell "find /sdcard/DCIM/$(basename "$BATCH") -type f | wc -l"
find "$BATCH" -type f | wc -l                 # must match
```

**Then force a media scan**, or Google Photos may not notice the files. On Android 10 the
old scan broadcasts are restricted, and I have not verified a reliable one-liner for your
device. The dependable method is:

```sh
adb reboot        # a reboot always triggers a full media scan
```

Give it a couple of minutes after boot, then check the Google Photos app. If the folder
still doesn't appear, transfer that Batch with OpenMTP instead — this is exactly the
scenario MTP avoids.

#### Enable backup for the new folder

> Google Photos → avatar → **Photos settings** → **Backup** → **Back up device folders** →
> toggle **ON** for the new `260701-260714-9.8GB` folder

New folders default to **off**. This is the most commonly missed step in the entire
workflow — the files are on the phone, everything looks fine, and nothing uploads.

While you're in there, re-confirm **Backup quality = Original quality** (invariant #6).

---

### Stage 6: Confirm the backup

**Do not proceed to Stage 7 on optimism.** This is the gap between the Ledger and the Upload
log, and it's where photos get lost.

1. Put the Pixel on **Wi-Fi and mains power**. Leave the screen on, or at minimum keep
   Google Photos in the foreground initially — aggressive battery optimisation on Android 10
   will pause background uploads.
2. Google Photos → **Photos** tab. The header shows backup progress
   ("Backing up N items…"). Wait for **"Backup complete"**.
3. A full 10 GB Batch can take **many hours** on domestic upload. Leave it overnight.
4. **Verify from a different device** — open photos.google.com on the Mac and check:
   - the newest photos match the Batch's date range;
   - pick a couple of Motion Photos and confirm they **animate** (Google Photos shows a
     motion badge and plays the clip). This is the real proof muxing worked end to end.
5. **Record it in the Upload log.** Create `$LIB/upload-log.md` if it doesn't exist:

   ```markdown
   | Batch | Import | Files | Pushed | Backup confirmed | Notes |
   |---|---|---|---|---|---|
   | 260701-260714-9.8GB | 2026-07-28 | 3,412 | 2026-07-28 | 2026-07-29 | motion photos verified |
   ```

   Only fill in **Backup confirmed** after step 4 passes. That column is the fact everything
   else in this workflow depends on.

---

### Stage 7: Close the loop

In this order. Each step is safe only because the previous one succeeded.

**1. Free space on the Pixel for the next Batch.**

> Google Photos → avatar → **Free up space** → confirm

This deletes only local copies of files Google has confirmed backed up. If it reports fewer
items than your Batch contained, **some files did not upload** — go back to Stage 6.

Or, if you prefer to be explicit about it:

```sh
adb shell rm -rf "/sdcard/DCIM/260701-260714-9.8GB"
```

Only do this after Stage 6 step 4 passed. `rm -rf` on the device does not check anything.

**2. Next Batch.** Repeat Stages 5–7 for each remaining Batch in the Results directory.

**3. When every Batch of this Import is confirmed:**

- The **Results directory is now disposable** — it's fully reproducible from the Originals
  by re-running the script. Delete it to reclaim space:
  ```sh
  rm -rf "$IMPORT/muxed-photo"
  ```
  Keep `library-ledger.tsv` first if you want the history:
  ```sh
  cp "$IMPORT/muxed-photo/library-ledger.tsv" "$IMPORT/ledger-$(basename "$IMPORT").tsv"
  ```
- The **Originals are not disposable.** Keep them, or move them to long-term archive
  storage. They are your only non-Google copy.
- **Only now** may you delete the corresponding photos from the iPhone Roll, if you want to.
  Invariant #1. There is no rush.

---

## Recovery: I did something wrong

### R1: Image Capture died partway through

Image Capture does not resume, and it will happily re-import files you already have,
creating `IMG_0001 1.HEIC`-style duplicates.

**Do this:** delete the partial Import folder entirely and start Stage 1 again.

```sh
rm -rf "$IMPORT" && mkdir -p "$IMPORT"
```

Nothing has been deleted from the iPhone (invariant #1), so this costs only time. Do **not**
try to "top up" a partial folder by importing the remainder — the boundary is not knowable
from the Mac side and you will get gaps or duplicates.

If it dies repeatedly on large selections, import in smaller date ranges — a week at a time
— as separate Imports. Multiple small Imports are completely fine; that's what the dated
folder convention is for.

### R2: Some files are corrupt

```sh
# List them
exiftool -q -q -p '$FileName' -if '$Error' "$IMPORT" 2>/dev/null

# Move them aside rather than deleting
mkdir -p "$IMPORT/../quarantine"
exiftool -q -q -p '$Directory/$FileName' -if '$Error' "$IMPORT" 2>/dev/null \
  | while IFS= read -r f; do mv "$f" "$IMPORT/../quarantine/"; done
```

Then re-import just those specific files from the iPhone via Image Capture (select them by
name in list view). If they're corrupt on the phone too, they're corrupt in your Roll —
nothing this workflow can do, but now you know.

### R3: The Motion Photo count is zero or far too low

Diagnose in this order:

```sh
# 1. Is the muxer even installed? A missing binary is a WARNING, not an error — the
#    script skips muxing and carries on, which is easy to miss in a long log.
command -v motionphoto2

# 2. Did the log record a skip?
grep -i "motionphoto2\|skipping Live-Photo\|Muxing skipped" "$IMPORT/muxed-photo/workflow.log"

# 3. Did the muxer report failures?
cat "$IMPORT/muxed-photo/muxing_errors.log" 2>/dev/null

# 4. Were there pairs to mux in the first place?
ls "$IMPORT" | sed 's/\.[^.]*$//' | sort | uniq -d | wc -l
```

**If the muxer was missing:** install it, delete `$IMPORT/muxed-photo`, and re-run the
script from scratch. Do not re-run over the existing Results directory — Step 2 already
renamed the files, so the Live Photo base-name pairing is gone (see §7).

**If there were no pairs:** you probably pointed the script at a folder one level too high
(invariant #5). Check that the path you gave it directly contains the files:

```sh
find "$IMPORT" -maxdepth 1 -type f ! -name '.*' | wc -l    # must be non-zero
```

### R4: The script "succeeded" but did nothing

Almost always invariant #5 — a non-recursive script pointed at a parent folder. It finds
zero files, groups zero files, reports success, and exits 0.

```sh
find "$IMPORT" -maxdepth 1 -type f ! -name '.*' | wc -l
```

If that's `0`, your files are in a subfolder. Point the script at the subfolder.

### R5: Google Photos is missing photos I thought I uploaded

Work through these in order:

1. **Is the device folder backup toggle on?** Photos settings → Backup → Back up device
   folders → check the Batch folder is ON. New folders default to OFF.
2. **Is backup finished?** The Photos tab header will say so. "Backup complete" means
   complete; anything else means keep waiting.
3. **Are the files still on the device?** `adb shell ls /sdcard/DCIM/` — if you ran "Free up
   space" prematurely, they're gone from the phone.
4. **Is the phone throttling background upload?** Settings → Apps → Google Photos → Battery
   → set to **Unrestricted**. Plug in, connect to Wi-Fi, open the app and leave it open.
5. **Still missing?** The Batch is still in your Results directory on the Mac (you haven't
   deleted it, per Stage 7). Re-push it. Google Photos deduplicates identical uploads, so
   re-pushing an already-uploaded Batch is safe — you won't get doubles of files that
   already landed.

Then correct `upload-log.md`. A wrong Upload log is more dangerous than no Upload log.

### R6: I deleted from the iPhone too early

Check, in this order:

1. **iPhone → Photos → Albums → Recently Deleted.** Items stay ~30 days and can be
   recovered in full.
2. **The Mac Import folder** — if the Import completed, the Originals are still there.
3. **iCloud Photos**, if it was enabled.

If all three come up empty, those photos are gone. This is why invariant #1 exists and why
"Delete after import" is off by default.

### R7: I have duplicates in Google Photos

Expected, in two specific cases, and mostly harmless:

- **Edited photos.** iOS exports both `IMG_1327` and `IMG_E1327` (the edited version). Both
  mux, both rename to the same second, so one gets a `-1` suffix and both upload. See §7.
- **A re-uploaded Batch.** Google dedupes byte-identical files, but a *re-muxed* Motion
  Photo may not be byte-identical to the first mux, so it can appear twice.

Google Photos has no bulk de-duplicate function. Deal with it manually, or accept it — this
costs you nothing on a Pixel 1, where storage is unlimited.

### R8: I re-ran the script and it skipped everything

Checkpoints in `$IMPORT/.workflow/` are doing their job. If you want a genuinely clean run:

```sh
rm -rf "$IMPORT/.workflow" "$IMPORT/muxed-photo"
"$SCRIPT/masterscript.sh" --size 10G "$IMPORT"
```

This deletes only generated output. Originals are untouched.

---

## 7. Quirks specific to *this* library

These are real properties of your files, verified on disk — not general advice.

### Why muxed Motion Photos don't move like Live Photos in Google Photos

**Symptom:** the still is perfect, but the motion wobbles left-right and the image looks
distorted compared to the same Live Photo on the iPhone.

**This is not a bug in the toolkit, and not something muxing did wrong.** Verified by muxing
a real pair from this library and inspecting the output:

```
Motion Photo                           : 1
Motion Photo Presentation Timestamp Us : 1400000     ← correctly read from Apple's still marker
Directory Item Semantic                : Primary, MotionPhoto
```

The embedded video is the original HEVC stream, not re-encoded (3,186,192 → 3,186,311 bytes;
container padding only). `motionphoto2` is doing its job.

The cause is a **format capability gap**. An Apple Live Photo `.MOV` carries correction data
that is applied *at playback time*, and Google's Motion Photo format has nowhere to store it:

| In the source `.MOV` | What iOS does with it | What Google Photos does |
|---|---|---|
| Track 3/4 `mebx` camera-motion samples | stabilises playback | ignores → **left-right wobble** |
| `CleanApertureDimensions 1744x1308` inside `EncodedPixelsDimensions 1920x1440` | crops off the outer ~9% | plays the full frame → **edge lens distortion becomes visible** |
| `LivePhotoStillImageTransform` (ref. dims 1920×1440) | aligns the video to the still | ignores → slight misalignment |
| Still marker part-way in (e.g. 1.17 s of a 1.64 s clip) | ends playback on the still | plays from t=0 → the framing travels |

Apple's stabilisation is **computed on the fly, not baked into the pixels.** Google's own
Pixel motion photos look clean because they were stabilised *in-camera*. Closing that gap
would mean re-encoding every clip — lossy, slow, and applying generic stabilisation that
doesn't match Apple's transform. That was tried anyway; see the verdict below.

A second, smaller factor: the still is **5712×4284 (24.5 MP)** while the video is
**1920×1440 (2.8 MP)** — 9× fewer pixels. The step down from crisp still to soft motion is
inherent to Live Photos and is very visible on a large screen.

### The baked-in fix was tested, and rejected — 2026-08-26

Re-encoding was not just reasoned about, it was built and compared on the device. A candidate
was made from `IMG_9305` with both correction steps baked into the pixels: crop to the clean
aperture (1744×1308) and `vidstab` stabilisation — keeping the original audio, the `hvc1`
tag, the HDR gain map, and using a **length-preserving byte patch** for the timestamp so the
XMP stayed structurally identical to a known-good mux.

Both were pushed to the Pixel, backed up at Original quality, and viewed in Google Photos
next to the iPhone Live Photo:

| | File | Verdict |
|---|---|---|
| **A** | plain pipeline mux (`muxed-photo/IMG_9305.HEIC`) | **better of the two** |
| **B** | crop + `vidstab` (`FIXED/IMG_9305_FIXED2.HEIC`) | worse |

**Neither matched the iPhone, and the baked-in fix made playback worse — so it is not going
into the pipeline.** Generic stabilisation fights motion that Apple's transform would have
corrected differently, and the crop re-encodes an already-soft 2.8 MP video. The A/B harness
(`tools/motion_ab_test.sh`) has been removed; don't rebuild this experiment.

Two related things were proven along the way and are worth keeping:

- **Google Photos stores Pixel sideloads byte-for-byte.** The muxed file downloaded back out
  of Google Photos had an MD5 identical to the file pushed in. Original quality is confirmed,
  and every remaining playback complaint is **player-side**.
- **Never rewrite a muxed file's XMP with `exiftool`.** Its serialisation shifts offsets and
  Google Photos then can't parse the file at all — the first fix candidate was unviewable for
  exactly this reason. Byte patches only, same length.

**Status: accepted limitation.** The still — the artifact that actually matters — is
byte-perfect at full resolution.

### Mux runs before rename — and why the order still matters

`run_mux_motionphoto.sh` passes `--exif-match`, and in that mode `motionphoto2` pairs Live
Photos **entirely by `ContentIdentifier`** (`motionphoto2.py:363-398`) — filenames are never
consulted. So renaming first would *not*, on its own, break pairing. Verified on real files,
including edited duplicates, which carry distinct identifiers:

```
IMG_1327.HEIC  03CE6CCB-…F54      IMG_E1327.HEIC  92AD97DC-…EBA
IMG_1327.MOV   03CE6CCB-…F54      IMG_E1327.MOV   92AD97DC-…EBA
```

**The order is still correct, because it removes a single point of failure.** Without
`--exif-match`, `motionphoto2` falls back to matching by base name
(`motionphoto2.py:307-322`), and that fallback is only safe if the still and its video rename
to the *same* base name. They now do — both resolve to local time:

```
20260415_194306.HEIC     ← DateTimeOriginal
20260415_194306.MOV      ← Keys:CreationDate
```

Before the video tag chain was fixed (see below) the `.MOV` resolved to `20260415_114306` —
8 hours earlier — so the fallback found **zero pairs** and silently copied every Live Photo
unmuxed with no error or warning. Muxing first keeps *both* matching paths viable, so the
pipeline never depends on one flag staying present.

Don't rename by hand before running the script, and don't re-run the script over an
already-renamed Results directory.

### Videos and stills are both named in local time

Apple stores a video's capture time twice, and the two disagree:

```
CreateDate    : 2026:04:15 11:43:06          ← UTC, no offset
CreationDate  : 2026:04:15 19:43:06+08:00    ← local time with offset
```

`PHOTO_VIDEO_DATE_TAGS` in `lib.sh` therefore **ends with `Keys:CreationDate`**, so videos are
named in local time and line up with their stills. Ending the chain on `QuickTime:CreateDate`
(as it did before) named every video **8 hours early in SGT**, which skewed batch date ranges
and pushed anything shot between 00:00 and 08:00 onto the previous day.

Videos with no `Keys:CreationDate` — non-Apple footage, stripped metadata — still fall back to
the UTC tags, which is better than no date at all.

### `IMG_E####` — you have 111 of them

iOS edits are non-destructive: the original file stays untouched and the edit is stored
separately. On export you therefore get **both**:

```
IMG_1327.AAE      ← the edit instructions (useless outside the Photos app)
IMG_1327.HEIC     ← the pristine original
IMG_1327.MOV      ← its Live Photo companion
IMG_E1327.HEIC    ← the EDITED version
IMG_E1327.MOV     ← its Live Photo companion
```

Both pairs mux into Motion Photos. Both carry the same capture timestamp, so after renaming
you get `20230415_142233.HEIC` and `20230415_142233-1.HEIC`. **This is where the `-1` files
in your `IphonePhotoOriBeforeMux/` archive came from.** Both upload; you see two near-
identical photos in Google Photos.

**Recommendation: leave it alone.** 111 files out of 10,472 is 1%, storage on a Pixel 1 is
free, and keeping both means you have the pristine original *and* the version you actually
edited. If you'd rather not:

```sh
# Keep only the EDITED versions (what the Photos app shows you):
cd "$IMPORT"
for e in IMG_E*; do o="IMG_${e#IMG_E}"; [ -f "$o" ] && rm "$o"; done
```

Run that **before** the script, and be sure it's what you want — it deletes Originals.

### `.AAE` sidecars — you have 100

Plain-text edit instructions, meaningless outside Apple's Photos app. The toolkit's
`is_media_file` doesn't recognise them, so they're never renamed, grouped, or transferred.
They just sit in the Import folder. Harmless. Ignore them.

### `.MOV` outnumbers everything

In your pending Import: 4,780 `MOV`, 3,111 `JPG`, 2,447 `HEIC`. Most of those `.MOV` files
are **not standalone videos** — they're Live Photo companions. 4,558 base names appear
twice, so roughly 4,558 of those `.MOV` files will disappear *into* Motion Photos during
muxing rather than being uploaded separately. Expect the file count to drop by around that
much between the Import folder and the Results directory. **That's the muxer working, not
files going missing.**

### Some files aren't named `IMG_####`

You have files like `APSH7716.MP4` and `AXXU7240.JPG`. iOS assigns those pseudo-random names
to media that entered the Roll from outside the camera — AirDrop, app saves, downloads. They
rename and group normally. They're also precisely the files most likely to be back-dated and
therefore missed by a date-based cut point (Stage 0c).

### The toolkit is non-recursive, everywhere

`masterscript.sh`, `group_files_size.sh` and `run_mux_motionphoto.sh` all use
`find -maxdepth 1`. `rename_media.sh` invokes exiftool on a directory without `-r`. This is
deliberate — it stops a run from wandering into `muxed-photo/` and reprocessing its own
output — but it means pointing at a parent folder silently does nothing. Invariant #5.

---

## Appendix A: current disk state and the backlog

As of 2026-07-28:

| Path | Contents | State |
|---|---|---|
| `Import2here/Leong/iphone_photos/` | 10,472 files · 49 GB · 4,780 MOV, 3,111 JPG, 2,447 HEIC, 100 AAE, 19 PNG, 9 MP4, 6 DNG | **Unprocessed.** 10,424 still `IMG_####`, 0 renamed, 4,558 Live Photo pairs, 111 `IMG_E` edited versions |
| `IphonePhotoOriBeforeMux/` | 22,934 files, flat | **Already renamed** (22,810 in `YYYYMMDD_HHMMSS` form) despite the folder name |

**Two naming problems worth fixing when convenient.** `IphonePhotoOriBeforeMux` claims to
hold pristine pre-mux originals; it holds renamed files. And those files were renamed under
the **old v1 script order** (rename → mux → group), which is the ordering the current
toolkit exists to correct — so their Live Photo pairs may already be broken. Worth an audit
before you assume that archive is a safe fallback. Renaming the folder to something honest,
like `archive-renamed-legacy/`, would stop it from misleading you later.

**Running the backlog.** Once you've read Stages 2–4 above, the pending 49 GB is just an
Import that's already sitting on disk:

```sh
LIB="/Volumes/Aca_WD/media/Import from Image Capture"
SCRIPT="$LIB/script"
IMPORT="$LIB/Import2here/Leong/iphone_photos"      # note: the FILES live here, not in Leong/

"$SCRIPT/masterscript.sh" --dry-run "$IMPORT"      # preview first
"$SCRIPT/masterscript.sh" --size 10G "$IMPORT"     # then commit
```

Disk check: 49 GB in, roughly 2× that during processing, against 873 GB free on `Aca_WD`.
Comfortable. At 10 GB per Batch expect roughly 4–5 Batches, so 4–5 rounds of Stages 5–7.

---

## Appendix B: quick reference card

Once the above is second nature, this is the whole workflow:

```sh
LIB="/Volumes/Aca_WD/media/Import from Image Capture"
SCRIPT="$LIB/script"
IMPORT="$LIB/library/$(date +%Y-%m-%d)"

# 0. Cut point: last confirmed upload in upload-log.md, + 1 day, through YESTERDAY.
find "$LIB/library" -name library-ledger.tsv -exec tail -n +2 {} \; | sort | tail -3

# 1. Import.  Image Capture -> list view -> sort by Date -> select range -> Import To: $IMPORT
mkdir -p "$IMPORT" && open "$IMPORT"

# 2. Verify the Import
cd "$IMPORT"
find . -maxdepth 1 -type f -size 0                          # must be empty
exiftool -q -q -p '$FileName' -if '$Error' . 2>/dev/null    # must be empty
ls | sed 's/.*\.//' | sort | uniq -c | sort -rn             # HEIC should still be HEIC

# 3. Process
"$SCRIPT/masterscript.sh" --dry-run "$IMPORT"
"$SCRIPT/masterscript.sh" --size 10G "$IMPORT"

# 4. Verify the output
column -t -s $'\t' "$IMPORT/muxed-photo/library-ledger.tsv"
exiftool -q -q -if '$XMP-GCamera:MotionPhoto' -p '$FileName' -r "$IMPORT/muxed-photo" | wc -l

# 5. Transfer ONE Batch  (OpenMTP -> Internal Storage/DCIM/, or:)
adb push "$IMPORT/muxed-photo/<BATCH>" /sdcard/DCIM/ && adb reboot
#    -> Google Photos: Back up device folders -> toggle ON for the new folder
#    -> confirm Backup quality = Original quality

# 6. Confirm on photos.google.com, check a Motion Photo animates, then log it in upload-log.md

# 7. Google Photos -> Free up space.  Next Batch.  Repeat 5-7.
#    All Batches confirmed -> rm -rf "$IMPORT/muxed-photo".  KEEP the Originals.
```

**The three that will actually bite you:**

1. Point the script at the folder that **directly contains the files** — it's non-recursive
   and fails silently.
2. **Toggle backup ON** for each new device folder in Google Photos — new folders default to
   off and nothing tells you.
3. **Nothing gets deleted from the iPhone** until `upload-log.md` says Google has it.
