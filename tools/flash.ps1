param(
    [Parameter(Mandatory = $true)][string]$Bin,
    [string]$Serial = "SHARK8RU0006472",
    [string]$LocalTmp = "/data/local/tmp/logo_flash.bin",
    [switch]$Reboot
)
# Flash a logo.bin to the MTK logo partition on the device.
# Safety: pushes to /data/local/tmp, verifies SHA256 on both sides, writes via
# dd with conv=sync, fsyncs, then reads the partition back and verifies SHA256
# against the zero-padded local reference. Only then (optionally) reboots.
$ErrorActionPreference = 'Stop'

function Invoke-Adb([string]$args) {
    $out = & adb -s $Serial $args 2>&1
    if ($LASTEXITCODE -ne 0) { throw "adb failed: $out" }
    return $out
}

function Sha256-Bytes([byte[]]$data) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    return ([System.BitConverter]::ToString($sha.ComputeHash($data))).Replace('-', '')
}

# resolve logo partition
$part = (Invoke-Adb "shell readlink /dev/block/by-name/logo").Trim()
Write-Output ("logo partition: $part")

# 1. push + hash check
Invoke-Adb "root" | Out-Null
Invoke-Adb "wait-for-device" | Out-Null
Invoke-Adb "push `"$Bin`" $LocalTmp" | Out-Null
$local = [System.IO.File]::ReadAllBytes((Resolve-Path $Bin))
$localHash = Sha256-Bytes $local
$remoteHash = ((Invoke-Adb "shell sha256sum $LocalTmp") -split '\s+')[0]
Write-Output ("local : $localHash")
Write-Output ("remote: $remoteHash")
if ($remoteHash -ne $localHash) { throw "hash mismatch, aborting" }
Write-Output "transfer hash OK"

# 2. write with dd (bs=512, conv=sync pads the tail block)
$blocks = [int]([Math]::Ceiling($local.Length / 512.0))
Invoke-Adb "shell dd if=$LocalTmp of=$part bs=512 conv=sync" | Out-Null
Invoke-Adb "shell sync" | Out-Null
Write-Output "dd write OK ($blocks blocks)"

# 3. read back and verify (zero-padded reference)
$ref = New-Object byte[] ($blocks * 512)
[System.Array]::Copy($local, $ref, [System.Math]::Min($local.Length, $ref.Length))
$refHash = Sha256-Bytes $ref
Invoke-Adb "shell dd if=$part of=/data/local/tmp/logo_readback.bin bs=512 count=$blocks" | Out-Null
$backHash = ((Invoke-Adb "shell sha256sum /data/local/tmp/logo_readback.bin") -split '\s+')[0]
Write-Output ("expect: $refHash")
Write-Output ("actual: $backHash")
if ($backHash -ne $refHash) { throw "readback mismatch, aborting" }
Write-Output "partition readback OK"

if ($Reboot) {
    Invoke-Adb "reboot" | Out-Null
    Write-Output "reboot issued"
}