# shark8-custom-bootlogo

<p align="center">
  <img src="custom/artwork.png" alt="Boot logo preview" width="320">
</p>

> **[!] DO NOT FLASH `shark8-bootlogo-flashable.zip` BLINDLY IF YOU ARE NOT
> USING A BLACKVIEW SHARK 8.** This image was built from **this device's
> stock logo partition** and will produce garbage or stall the bootloader on
> any other MTK phone. You have been warned.
>
> **[!] IF YOUR PHONE IS STUCK AFTER FLASHING (bootloop / black screen):**
> 1. **TWRP / OrangeFox still boots?** -> restore the backup that the
>    flashable zip saved to `/tmp/logo_before.bin`, or flash
>    `stock/logo-stock.bin` via `dd` from the same recovery shell.
> 2. **Recovery does not come up?** -> hold **Volume Down + Power** to
>    enter **MTK BROM mode**, then use **SP Flash Tool** on Windows with
>    the Shark 8 scatter file to re-flash the `logo` partition from
>    `stock/logo-stock.bin`.
> 3. **fastboot available?** -> `fastboot flash logo stock/logo-stock.bin`
>    and reboot.
>
> In all cases the boot path (kernel, system) is unaffected — only the
> splash picture is broken. Your data is safe.

Custom boot logo ("splash") for the **Blackview Shark 8** (MediaTek, Android 13
AOSP GSI). Replaces the pre-boot picture shown by the MTK bootloader (lk) by
rewriting the `logo` partition image.

The included `custom/logo-custom.bin` is the partition image currently flashed:
stock Blackview splash with a paint stripe over it and the Google wordmark below
(author's artistic choice, replace with your own via `custom/artwork.png`).

## Device facts (measured, don't trust generic MTK guides blindly)

| Item | Value |
|---|---|
| Device | Blackview Shark 8 (SHARK8RU0006472), MTK Helio G85 |
| ROM | AOSP GSI Android 14 (AP2A.240805.005.F1) on stock vendor |
| Logo partition | `/dev/block/by-name/logo` -> `/dev/block/mmcblk0p41` |
| Partition size | 27,262,976 bytes (26 MiB) |
| Header | 512 bytes, ASCII `logo` at offset 0x08 |
| Pictures | 162 (u32 LE count at offset 512) |
| Block size | u32 LE, offset 516, relative to end of header |
| Offsets map | 162 x u32 LE, relative to end of header (first = 656 = 0x290) |
| Frames | zlib streams (`0x78 0x9C` + deflate + adler32), layout: BGRA, 1080x2460, top-down, alpha = 255, 4 bytes/pixel |
| img00 | the boot splash (the one you see at power-on) |
| img01+ | recovery / factory / charging / battery-drain frames (left untouched) |

The lk bootloader does **not** verify any signature or CRC on this partition
(AVB does not cover `logo`). A structurally valid file boots fine; parsing is
defensive, so a bad image at worst hides the splash (black screen until the
boot animation).

## Repository layout

```
stock/logo-stock.bin        stock partition dump (restore source)
stock/SHA256SUMS            checksums
custom/artwork.png          source artwork (1080x2460 opaque PNG, top-down)
custom/logo-custom.bin      built, verified and currently flashed image
dist/shark8-bootlogo-flashable.zip  TWRP/OrangeFox flashable package
tools/extract.ps1           unpack logo.bin into raw frames + PNG previews
tools/build.ps1             build a new logo.bin from artwork.png + stock dump
tools/verify.ps1            re-parse + inflate every picture of a logo.bin
tools/flash.ps1             double-checked dd flash (hash before + readback)
tools/restore.ps1           restore stock dump (same safety flow)
tools/make_flashable_zip.ps1  repackage custom/logo-custom.bin -> flashable zip
```

## Workflow

```
# see what is inside the stock dump
powershell -ExecutionPolicy Bypass -File tools\extract.ps1

# make your 1080x2460 PNG (any opaque format, alpha forced to 255)
# then rebuild:
powershell -ExecutionPolicy Bypass -File tools\build.ps1 `
    -Artwork custom\artwork.png -StockBin stock\logo-stock.bin `
    -Out custom\logo-custom.bin

# structural sanity check of the result
powershell -ExecutionPolicy Bypass -File tools\verify.ps1 -Bin custom\logo-custom.bin

# flash (rooted adb; resolves the partition by-name itself)
powershell -ExecutionPolicy Bypass -File tools\flash.ps1 -Bin custom\logo-custom.bin -Reboot

# rollback anytime
powershell -ExecutionPolicy Bypass -File tools\restore.ps1 -Reboot
```

## How to make your own artwork

- Size must be **exactly 1080 x 2460** px: lk blits the raw frame 1:1, there is
  no scaling. Rows are top-down (first row = top of screen).
- Use a black background: lk shows this frame while nothing else is rendered
  yet, and the boot animation comes up directly after, so full-bleed black
  gives a seamless transition.
- 4 bytes per pixel in the partition: BGRA order, alpha byte is written as 255
  (lk ignores alpha; keep it opaque like the stock frames).

# roundtrip. If you neither care about image indexes 3..161 nor want the binary
# blob from the dump, `custom/logo-custom.bin` is a valid standalone image.

## Flashable zip (TWRP / OrangeFox)

```
dist/shark8-bootlogo-flashable.zip
```

Flashable from any custom recovery that executes `META-INF` scripted zips
(TWRP 3.x, OrangeFox, PitchBlack). Safety flow built into the installer:

1. resolves `logo` partition by name (`/dev/block/by-name/logo`, falls back to
   `/dev/block/bootdevice/by-name/logo`); no hardcoded `mmcblk0pNN`
2. backs up the current partition to `/tmp/logo_before.bin`
3. writes the image with `dd bs=512 conv=sync`, `sync`
4. reads the partition back, `sha256`-compares against the zero-padded source
5. on mismatch: automatically restores the backup and reports failure

Regenerate after redesigning your splash:

```
powershell -ExecutionPolicy Bypass -File tools\make_flashable_zip.ps1
```

## Compatibility & limitations

The ready-made image and the flashable zip are **device-specific**:

- They were built from **this device's stock `logo` partition** (162 pictures,
  MTK-layout with zlib-blobs, 1080x2460 panel). The `logo` partition is written
  by the MediaTek bootloader (lk) shipped in the **vendor** firmware - the
  Android ROM / GSI version is irrelevant.
- Valid targets: **Blackview Shark 8** (stock or GSI firmware, as long as the
  vendor partition scheme and lk from Blackview firmware are present).
- Do **not** flash on other MTK phones: different picture counts, raster sizes
  and lk parsing make the image at best useless, at worst a garbage splash.
  It cannot brick anything (no signature check), but it will not work either.
- The **tooling is universal**: any MTK device owner can extract their own
  stock dump, drop in their own artwork (their panel resolution), rebuild and
  flash. See the workflow above - only `stock/logo-stock.bin` and the artwork
  PIXEL SIZE need to come from their device.

## Risks & recovery

1. Wrong image -> no splash at worst. The boot path is unaffected.
2. Truncated / corrupt write -> bootloader could stall before the kernel. This
   repo's scripts prevent it (hash checks + readback verify). To repair, fall
   back to the preserved dump via the same dd method, or:
   - `fastboot flash logo stock\logo-stock.bin`
   - **SP Flash Tool** (MTK BROM mode) - flashes any partition regardless of
     device state. You need the device's scatter file from the firmware kit.

## Disclaimer

Flashing partitions can break things. The author is not responsible for any
damage.