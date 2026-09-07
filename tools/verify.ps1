param(
    [string]$Bin = "..\custom\logo-custom.bin",
    [string]$OutImg = $null
)
# Structural verification of a logo.bin: parse the header, make sure every
# zlib blob inflates, print the picture table. Optionally dump img00 to a raw
# file (-OutImg).
$ErrorActionPreference = 'Stop'

$fs = [System.IO.File]::OpenRead($Bin)
$br = New-Object System.IO.BinaryReader($fs)
$null = $br.ReadBytes(512)
$count = $br.ReadUInt32()
$blk = $br.ReadUInt32()
$offs = New-Object System.Collections.Generic.List[uint32]
for ($i = 0; $i -lt $count; $i++) { $offs.Add($br.ReadUInt32()) }
Write-Output ("pictures: {0}   block size: {1}" -f $count, $blk)

for ($i = 0; $i -lt $count; $i++) {
    if ($i -lt ($count - 1)) { $sz = $offs[$i + 1] - $offs[$i] } else { $sz = $blk - $offs[$i] }
    $fs.Position = 512 + $offs[$i]
    $z = $br.ReadBytes([int]$sz)
    $zlen = $z.Length
    $ok = 'N/A'
    if ($zlen -ge 2 -and $z[0] -eq 0x78) {
        try {
            $zdata = $zlen - 2
            $ms = New-Object System.IO.MemoryStream($z, 2, $zdata)
            $ds = New-Object System.IO.Compression.DeflateStream($ms, [System.IO.Compression.CompressionMode]::Decompress)
            $out = New-Object System.IO.MemoryStream
            $ds.CopyTo($out)
            $ok = $out.Length
            if ($i -eq 0 -and -not [string]::IsNullOrEmpty($OutImg)) {
                [System.IO.File]::WriteAllBytes($OutImg, $out.ToArray())
            }
        } catch { $ok = 'BROKEN: ' + $_.Exception.Message }
    }
    Write-Output ("img {0:D2}: z={1} inflate={2}" -f $i, $zlen, $ok)
}
$br.Close(); $fs.Close()