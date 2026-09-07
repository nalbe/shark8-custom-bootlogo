param(
    [string]$Bin = "..\custom\logo-custom.bin",
    [string]$OutZip = "..\dist\shark8-bootlogo-flashable.zip"
)
# Package custom/logo-custom.bin into a TWRP/OrangeFox-flashable zip.
# The recovery script:
#   - resolves the logo partition via /dev/block/by-name/logo
#   - backs up the current partition to /tmp
#   - writes the image (bs=512, conv=sync), fsyncs
#   - reads back and compares sha256 (against the zero-padded reference)
#   - on mismatch: restores the backup and fails with ui_print errors
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$updateBinary = @'
#!/sbin/sh
# shark8-bootlogo - flashable installer for TWRP/OrangeFox
# Safe by design: backup -> write -> readback-verify -> auto-rollback.

OUTFD=""
ZIPFILE=""

if [ -n "$2" ] && [ "$2" -eq "$2" ] 2>/dev/null; then
    OUTFD=$2
    ZIPFILE=$3
else
    OUTFD=$1
    ZIPFILE=$2
fi

ui() {
    if [ -n "$OUTFD" ]; then
        echo "ui_print $1" >&$OUTFD
        echo "ui_print" >&$OUTFD
    fi
    echo "$1"
}

BIN=/tmp/logo-custom.bin

ui "Shark 8 boot logo installer"
ui ""

unzip -o "$ZIPFILE" logo-custom.bin -d /tmp >/dev/null 2>&1 || {
    ui "! cannot extract logo-custom.bin from zip"
    exit 1
}
[ -s "$BIN" ] || { ui "! extracted file is empty"; exit 1; }

# --- locate logo partition ---
PART=""
for cand in /dev/block/by-name/logo /dev/block/bootdevice/by-name/logo; do
    [ -e "$cand" ] && PART=$cand && break
done
[ -z "$PART" ] && PART=$(ls -l /dev/block/by-name/logo 2>/dev/null | awk '{print $NF}')
[ -z "$PART" ] && { ui "! logo partition not found"; exit 1; }
PART=$(readlink -f "$PART" 2>/dev/null || echo "$PART")
ui "logo partition: $PART"

# --- hashing helper ---
HASH() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum
    elif command -v busybox >/dev/null 2>&1; then busybox sha256sum
    else dd 2>/dev/null; fi | cut -d' ' -f1
}

SZ=$(stat -c %s "$BIN" 2>/dev/null || wc -c < "$BIN")
BLOCKS=$(( (SZ + 511) / 512 ))

ui "backing up current logo..."
dd if="$PART" of=/tmp/logo_before.bin bs=512 2>/dev/null || { ui "! backup failed"; exit 1; }

ui "writing custom logo (${SZ} bytes)..."
dd if="$BIN" of="$PART" bs=512 conv=sync 2>/dev/null || {
    ui "! write failed, restoring backup"
    dd if=/tmp/logo_before.bin of="$PART" bs=512 2>/dev/null
    sync
    exit 1
}
sync

ui "verifying readback..."
EXPECT=$(dd if="$BIN" bs=512 conv=sync 2>/dev/null | HASH)
ACTUAL=$(dd if="$PART" bs=512 count=$BLOCKS 2>/dev/null | HASH)

if [ -n "$EXPECT" ] && [ "$EXPECT" = "$ACTUAL" ]; then
    ui "OK: custom boot logo installed"
    ui "stock backup kept at /tmp/logo_before.bin (this session only)"
    exit 0
fi

ui "! verify failed (${ACTUAL}), restoring stock logo..."
dd if=/tmp/logo_before.bin of="$PART" bs=512 2>/dev/null
sync
ui "! stock logo restored, device untouched"
exit 1
'@

$root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$binPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot $Bin))
$outPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot $OutZip))
$outDir = Split-Path $outPath
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

if (-not (Test-Path $binPath)) { throw "missing $binPath" }

$binBytes = [System.IO.File]::ReadAllBytes($binPath)
$scriptBytes = [System.Text.Encoding]::ASCII.GetBytes($updateBinary)
$zipBytes = [System.Text.Encoding]::ASCII.GetBytes('# shark8-bootlogo flashable' + "`n")

$archiveStream = New-Object System.IO.FileStream($outPath, [System.IO.FileMode]::Create)
$archive = New-Object System.IO.Compression.ZipArchive($archiveStream, [System.IO.Compression.ZipArchiveMode]::Create)

function Add-Entry([string]$name, [byte[]]$data, [bool]$store) {
    $level = [System.IO.Compression.CompressionLevel]::Optimal
    if ($store) { $level = [System.IO.Compression.CompressionLevel]::NoCompression }
    $entry = $archive.CreateEntry($name, $level)
    $es = $entry.Open()
    $es.Write($data, 0, $data.Length)
    $es.Close()
}

Add-Entry 'logo-custom.bin' $binBytes $true
Add-Entry 'META-INF/com/google/android/update-binary' $scriptBytes $false
Add-Entry 'META-INF/com/google/android/updater-script' $zipBytes $false
$archive.Dispose()
$archiveStream.Close()

$h = (Get-FileHash $outPath -Algorithm SHA256).Hash
Write-Output ("zip: {0} ({1:N1} MB)" -f $outPath, ((Get-Item $outPath).Length / 1MB))
Write-Output ("sha256: {0}" -f $h)