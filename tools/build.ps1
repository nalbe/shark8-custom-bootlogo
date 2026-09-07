param(
    [string]$Artwork = "..\custom\artwork.png",
    [string]$StockBin = "..\stock\logo-stock.bin",
    [string]$Out = "..\custom\logo-custom.bin"
)
# Build a flashable MTK logo.bin from the original stock dump plus a new
# full-screen artwork frame.
#
# Artwork requirements:
#   - exactly 1080 x 2460 pixels (native splash raster size on Shark 8)
#   - opaque ARGB PNG (alpha is forced to 255 in the output)
#   - top-down row order (first row = top of screen)
#
# Only image index 0 (the boot splash) is replaced. All other 161 pictures
# keep their original compressed blobs byte-for-byte. Offsets and total block
# size are recomputed. The result is verified by re-parsing and re-inflating.

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$W = 1080; $H = 2460

# --- 1. artwork PNG -> BGRA raw (alpha = 255) ---
$bmp = New-Object System.Drawing.Bitmap($Artwork)
if ($bmp.Width -ne $W -or $bmp.Height -ne $H) {
    throw "Artwork must be ${W}x${H}, got $($bmp.Width)x$($bmp.Height)"
}
$raw = New-Object byte[] ($W * $H * 4)
$fi = 0
for ($y = 0; $y -lt $H; $y++) {
    for ($x = 0; $x -lt $W; $x++) {
        $c = $bmp.GetPixel($x, $y)
        $raw[$fi++] = $c.B
        $raw[$fi++] = $c.G
        $raw[$fi++] = $c.R
        $raw[$fi++] = 255
    }
}
$bmp.Dispose()
Write-Output ("raw frame: {0} bytes" -f $raw.Length)

# --- 2. zlib compressor (0x789c header + raw deflate + adler32 trailer) ---
Add-Type -TypeDefinition @"
using System;
using System.IO;
using System.IO.Compression;
public static class Z {
    public static byte[] Compress(byte[] src) {
        var ms = new MemoryStream();
        ms.WriteByte(0x78); ms.WriteByte(0x9C);
        using (var ds = new DeflateStream(ms, CompressionLevel.Optimal, true)) {
            ds.Write(src, 0, src.Length);
        }
        uint a = 1, b = 0;
        foreach (byte x in src) { a = (a + x) % 65521; b = (b + a) % 65521; }
        uint ad = (b << 16) | a;
        ms.WriteByte((byte)(ad >> 24)); ms.WriteByte((byte)(ad >> 16));
        ms.WriteByte((byte)(ad >> 8));  ms.WriteByte((byte)ad);
        return ms.ToArray();
    }
}
"@
$newBlob = [Z]::Compress($raw)
Write-Output ("new img00 blob: {0} bytes" -f $newBlob.Length)

# --- 3. rebuild logo.bin ---
$src = [System.IO.File]::ReadAllBytes($StockBin)
$hdr = New-Object byte[] 512
[System.Array]::Copy($src, 0, $hdr, 0, 512)

$stream = New-Object System.IO.MemoryStream
$bw = New-Object System.IO.BinaryWriter($stream)
$bw.Write($hdr)

$orig = New-Object System.IO.MemoryStream(,$src)
$obr = New-Object System.IO.BinaryReader($orig)
$null = $obr.ReadBytes(512)
$count = $obr.ReadUInt32()
$blk = $obr.ReadUInt32()
$offs = New-Object System.Collections.Generic.List[uint32]
for ($i = 0; $i -lt $count; $i++) { $offs.Add($obr.ReadUInt32()) }

$bw.Write([uint32]$count)

$blobs = New-Object System.Collections.Generic.List[byte[]]
for ($i = 0; $i -lt $count; $i++) {
    if ($i -lt ($count - 1)) { $bSize = $offs[$i + 1] - $offs[$i] } else { $bSize = $blk - $offs[$i] }
    $orig.Position = 512 + $offs[$i]
    $blobs.Add($obr.ReadBytes([int]$bSize))
}
$obr.Close(); $orig.Close()
$blobs[0] = $newBlob

$newOffs = New-Object System.Collections.Generic.List[uint32]
$run = (8 + 4 * $count)
for ($i = 0; $i -lt $count; $i++) {
    $newOffs.Add([uint32]$run)
    $run += $blobs[$i].Length
}
$bw.Write([uint32]$run)
foreach ($o in $newOffs) { $bw.Write([uint32]$o) }
foreach ($b in $blobs) { $bw.Write($b) }
$bw.Flush()
$outBytes = $stream.ToArray()
$bw.Close(); $stream.Close()
Write-Output ("built: {0} bytes" -f $outBytes.Length)
[System.IO.File]::WriteAllBytes($Out, $outBytes)

# --- 4. verify round-trip ---
$vfs = [System.IO.File]::OpenRead($Out)
$vbr = New-Object System.IO.BinaryReader($vfs)
$null = $vbr.ReadBytes(512)
$vc = $vbr.ReadUInt32(); $vb = $vbr.ReadUInt32()
$vo = New-Object System.Collections.Generic.List[uint32]
for ($i = 0; $i -lt $vc; $i++) { $vo.Add($vbr.ReadUInt32()) }
$vfs.Position = 512 + $vo[0]
$vz = $vbr.ReadBytes([int]($vo[1] - $vo[0]))
$vzlen = $vz.Length
$vms = New-Object System.IO.MemoryStream($vz, 2, ($vzlen - 2))
$vds = New-Object System.IO.Compression.DeflateStream($vms, [System.IO.Compression.CompressionMode]::Decompress)
$vout = New-Object System.IO.MemoryStream
$vds.CopyTo($vout)
$vraw = $vout.ToArray()
$vbr.Close(); $vfs.Close()
if ($vraw.Length -ne $raw.Length) { throw "verify mismatch: $($vraw.Length) vs $($raw.Length)" }
Write-Output ("verify OK: {0} pictures, img00 inflates to {1} bytes, match" -f $vc, $vraw.Length)