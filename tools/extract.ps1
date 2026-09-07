param(
    [string]$Bin = "..\stock\logo-stock.bin",
    [string]$OutDir = "unpack"
)
# Unpack an MTK logo.bin partition image into raw rasters and PNG previews.
# Structure (measured on Blackview Shark 8, Android 13 stock vendor):
#   512-byte header (ASCII "logo" at offset 0x08)
#   u32 LE picture count
#   u32 LE total block size (relative to end of header)
#   u32 LE x count  -> per-picture offset (relative to end of header)
#   zlib-compressed raw frames (full-screen frames: BGRA, 1080x2460, top-down, alpha=255)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Add-Type -AssemblyName System.Drawing

$fs = [System.IO.File]::OpenRead($Bin)
$br = New-Object System.IO.BinaryReader($fs)
$hdr = $br.ReadBytes(512)
$sig = [System.Text.Encoding]::ASCII.GetString($hdr, 8, 4)
if ($sig -ne 'logo' -and $sig -ne 'LOGO') { Write-Output ("WARN: unexpected signature '" + $sig + "'"); }
$count = $br.ReadUInt32()
$blk = $br.ReadUInt32()
$offs = New-Object System.Collections.Generic.List[uint32]
for ($i = 0; $i -lt $count; $i++) { $offs.Add($br.ReadUInt32()) }
Write-Output ("signature: {0}   pictures: {1}   block size: {2}" -f $sig, $count, $blk)

for ($i = 0; $i -lt $count; $i++) {
    if ($i -lt ($count - 1)) { $sz = $offs[$i + 1] - $offs[$i] } else { $sz = $blk - $offs[$i] }
    $fs.Position = 512 + $offs[$i]
    $z = $br.ReadBytes([int]$sz)
    $zlen = $z.Length
    $zdata = $zlen - 2
    $ms = New-Object System.IO.MemoryStream($z, 2, $zdata)
    $ds = New-Object System.IO.Compression.DeflateStream($ms, [System.IO.Compression.CompressionMode]::Decompress)
    $out = New-Object System.IO.MemoryStream
    $ds.CopyTo($out)
    $raw = $out.ToArray()
    $name = Join-Path $OutDir ("img{0:D2}.raw" -f $i)
    [System.IO.File]::WriteAllBytes($name, $raw)

    # PNG preview for full-screen frames (1080x2460, 4 bpp)
    if ($raw.Length -eq (1080 * 2460 * 4)) {
        $bmp = New-Object System.Drawing.Bitmap(1080, 2460, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
        for ($y = 0; $y -lt 2460; $y++) {
            $row = $y * 1080
            for ($x = 0; $x -lt 1080; $x++) {
                $j = ($row + $x) * 4
                $b = $raw[$j]; $g = $raw[$j + 1]; $r = $raw[$j + 2]
                $bmp.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(255, $r, $g, $b))
            }
        }
        $bmp.Save((Join-Path $OutDir ("img{0:D2}.png" -f $i)), [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
    }
    Write-Output ("img {0:D2}: z={1} raw={2}" -f $i, $zlen, $raw.Length)
}
$br.Close()
$fs.Close()