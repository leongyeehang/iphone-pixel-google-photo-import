# Per-Import Checklist

The short version. **Every step is here — only the explanations were removed.**
When a step misbehaves, jump to **[WORKFLOW.md](WORKFLOW.md)** for the why and the fix.

Optional: keep a paper trail by copying this per import —
`cp docs/CHECKLIST.md "library/$(date +%F)/checklist.md"`

```sh
LIB="/Volumes/Aca_WD/media/Import from Image Capture"
SCRIPT="$LIB/script"
IMPORT="$LIB/library/$(date +%Y-%m-%d)"
```

---

## Once (re-check after any iOS or Pixel update)

- [ ] iPhone → Settings → Photos → **Transfer to Mac or PC = Keep Originals**
      ⚠️ `Automatic` silently re-encodes every file. Lossy, no warning.
- [ ] iPhone → Settings → Photos → if iCloud Photos is on, **Download and Keep Originals**
      ⚠️ `Optimize iPhone Storage` means the originals aren't on the phone to import.
- [ ] Pixel → Google Photos → Photos settings → Backup → **Backup quality = Original quality**
      ⚠️ `Storage saver` defeats the entire purpose of using a Pixel 1.
- [ ] Mac → `exiftool -ver` · `command -v motionphoto2` both answer
      (`adb` is optional throughout — OpenMTP does every transfer step without it)
- [ ] Mac → `brew install --cask openmtp` (Android File Transfer is dead on macOS 26)

---

## 0 · Cut point

- [ ] Read the last confirmed upload from `$LIB/upload-log.md`
- [ ] Cross-check the newest photo in Google Photos — they should agree
      → disagree? [WORKFLOW.md § R5](WORKFLOW.md#r5-google-photos-is-missing-photos-i-thought-i-uploaded)
- [ ] Import window = **day after that**, through **yesterday**. Midnight boundaries only.
      ⚠️ Never cut mid-day — batches are cut by size, not date, so mid-day cuts create gaps.

```sh
find "$LIB/library" -name library-ledger.tsv -exec tail -n +2 {} \; | sort | tail -3
```

---

## 1 · Import

- [ ] `mkdir -p "$IMPORT" && open "$IMPORT"`
- [ ] Connect iPhone by USB, **unlock it**, tap Trust
- [ ] Image Capture → select iPhone → wait for the list to fully load (slow, looks frozen)
- [ ] Switch to **list view**, click **Date** to sort
- [ ] Set **Import To:** → `$IMPORT`
- [ ] ⚠️ **"Delete after import" stays UNCHECKED**
- [ ] Click first file of the range, shift-click last, press **Import** (not *Import All*)

---

## 2 · Verify the import ▸ GATE

```sh
cd "$IMPORT"
find . -maxdepth 1 -type f ! -name '.*' | wc -l          # ~= your selection count
ls | sed 's/.*\.//' | sort | uniq -c | sort -rn          # HEIC must still be HEIC
find . -maxdepth 1 -type f -size 0                       # must print nothing
exiftool -q -q -p '$FileName' -if '$Error' . 2>/dev/null # must print nothing (exit 2 = clean)
exiftool -s3 -FileType -ImageSize "$(ls *.HEIC | head -1)"
```

- [ ] Count plausible · no zero-byte files · no errors · HEIC full-resolution
      → any failure: [WORKFLOW.md § R1–R2](WORKFLOW.md#r1-image-capture-died-partway-through)
- [ ] *(optional, cheap)* back up the originals: `cp -Rp "$IMPORT" /Volumes/OtherDrive/`

---

## 3 · Process

- [ ] Check the Pixel's free space → batch size **≤ 50%** of it (`10G` on a 32 GB Pixel 1)
      (no `adb`? Settings → Storage on the phone, or read it in OpenMTP)

```sh
adb shell df -h /sdcard   # optional; the phone's Settings → Storage says the same
"$SCRIPT/masterscript.sh" --dry-run "$IMPORT"     # preview — changes nothing
"$SCRIPT/masterscript.sh" --size 10G "$IMPORT"    # commit
```

- [ ] ⚠️ `$IMPORT` must be the folder that **directly contains the files** — the scripts are
      non-recursive and a wrong path succeeds silently having done nothing
- [ ] Interrupted? Re-run the identical command; it resumes from checkpoints

---

## 4 · Verify the output ▸ GATE

```sh
RESULTS="$IMPORT/muxed-photo"
column -t -s $'\t' "$RESULTS/library-ledger.tsv"
ls -dlh "$RESULTS"/*GB/
exiftool -q -q -if '$XMP-GCamera:MotionPhoto' -p '$FileName' -r "$RESULTS" | wc -l
find "$RESULTS" -type f -size 0
```

- [ ] ⚠️ **Motion Photo count > 0** and roughly matches your Live Photo pair count
      → zero or far too low: [WORKFLOW.md § R3](WORKFLOW.md#r3-the-motion-photo-count-is-zero-or-far-too-low)
      (a missing `motionphoto2` is a *warning*, not an error — easy to miss in the log)
- [ ] File count dropped a lot vs the import? Normal — each Live Photo pair became one file

---

## 5 · Push ONE batch

- [ ] Connect Pixel, set USB mode to **File Transfer** on the phone
- [ ] **OpenMTP** → drag one `YYMMDD-YYMMDD-#.#GB/` folder into `Internal Storage/DCIM/`

<details><summary>or via adb</summary>

```sh
BATCH="$RESULTS/260701-260714-9.8GB"
adb push "$BATCH" /sdcard/DCIM/
adb shell "find /sdcard/DCIM/$(basename "$BATCH") -type f | wc -l"   # must match:
find "$BATCH" -type f | wc -l
adb reboot     # forces the media scan; otherwise Google Photos may not see the files
```
</details>

- [ ] ⚠️ Google Photos → Photos settings → Backup → **Back up device folders** →
      **toggle ON the new folder**. New folders default to OFF and nothing tells you.
- [ ] Re-confirm **Backup quality = Original quality**
- [ ] One batch at a time. Don't push the next until this one is confirmed.

---

## 6 · Confirm the backup ▸ GATE — nothing below here is reversible

- [ ] Pixel on Wi-Fi **and** mains power, Google Photos open
- [ ] Wait for **"Backup complete"** (a 10 GB batch can take overnight)
- [ ] Verify on **photos.google.com** from the Mac: date range matches, and a
      Motion Photo actually **animates**
- [ ] Record it in `$LIB/upload-log.md` — **before** you free up space below

```sh
"$SCRIPT/tools/log_upload.sh" "$RESULTS/260701-260714-9.8GB" "motion verified"
```

The batch name, import folder and file count are read from the folder; dates default to
today (`--pushed` / `--confirmed` to override). The note is optional. Or type the row
yourself — the script only saves the typing, it confirms nothing:

```markdown
| Batch | Import | Files | Pushed | Backup confirmed | Notes |
|---|---|---|---|---|---|
| 260701-260714-9.8GB | 2026July28 | 3412 | 2026-07-28 | 2026-07-29 | motion verified |
```

---

## 7 · Close the loop

- [ ] Google Photos → **Free up space** (or delete the folder in OpenMTP)
      ⚠️ If it frees fewer items than the batch held, some files never uploaded → back to 6
      This is the strongest check you have: it only removes what is genuinely backed up.
- [ ] Repeat 5–7 for each remaining batch
- [ ] All batches confirmed → `rm -rf "$IMPORT/muxed-photo"` (reproducible, disposable)
- [ ] ⚠️ **Keep the originals.** They are your only non-Google copy.
- [ ] Only now, if you want to, delete these photos from the iPhone

---

## The three that actually bite

1. **Point the script at the folder that directly contains the files** — non-recursive, fails silently.
2. **Toggle backup ON for each new device folder** — defaults to off, nothing tells you.
3. **Nothing leaves the iPhone** until `upload-log.md` says Google has it.

---

<sub>Maintenance: this file duplicates commands from [WORKFLOW.md](WORKFLOW.md). If the two
ever disagree, WORKFLOW.md is authoritative and this file is the bug. Change both together.</sub>
