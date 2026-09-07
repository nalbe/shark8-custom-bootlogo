param(
    [string]$Serial = "SHARK8RU0006472",
    [string]$StockBin = "..\stock\logo-stock.bin",
    [string]$LocalTmp = "/data/local/tmp/logo_stock_restore.bin",
    [switch]$Reboot
)
# Restore the stock logo partition from the preserved stock dump.
# Same safety flow as flash.ps1 (hash check before and after dd).
$ErrorActionPreference = 'Stop'

$part = (adb -s $Serial shell readlink /dev/block/by-name/logo 2>&1).Trim()
Write-Output ("logo partition: $part")
adb -s $Serial root | Out-Null
adb -s $Serial wait-for-device | Out-Null
adb -s $Serial push (Resolve-Path $StockBin) $LocalTmp | Out-Null

$local = [System.IO.File]::ReadAllBytes((Resolve-Path $StockBin))
$sha = [System.Security.Cryptography.SHA256]::Create()
$localHash = ([System.BitConverter]::ToString($sha.ComputeHash($local))).Replace('-', '')
$remoteHash = ((adb -s $Serial shell sha256sum $LocalTmp 2>&1) -split '\s+')[0]
Write-Output ("local : $localHash")
Write-Output ("remote: $remoteHash")
if ($remoteHash -ne $localHash) { throw "hash mismatch, aborting" }

adb -s $Serial shell "dd if=$LocalTmp of=$part bs=512 conv=sync" | Out-Null
adb -s $Serial shell sync | Out-Null
Write-Output "stock dump written"

if ($Reboot) {
    adb -s $Serial reboot | Out-Null
    Write-Output "reboot issued"
}