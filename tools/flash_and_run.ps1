# Silvia Lever — flash firmware + launch UI in one shot
# Usage: powershell -NoProfile -File tools\flash_and_run.ps1 [-SketchDir <path>] [-NoUi]
#
# Default sketch: firmware/silvia_lever_main
# Default: closes any running UI and Arduino Serial Monitor holding COM port,
#          compiles, uploads, waits for board re-enumeration, relaunches UI.

param(
    [string]$SketchDir = "L:\PROJECTS\silvia lever\firmware\silvia_lever_main",
    [string]$Fqbn      = "teensy:avr:teensy40",
    [switch]$NoUi,
    [switch]$NoCompile,
    [switch]$NoUpload    # Skip Teensy upload entirely (use for UI-only changes)
)

$ErrorActionPreference = "Continue"
$PSNativeCommandUseErrorActionPreference = $false
$ArduinoCli = "C:\Users\mklod\AppData\Local\Programs\Arduino IDE\resources\app\lib\backend\resources\arduino-cli.exe"
$UiScript   = "L:\PROJECTS\silvia lever\ui\windows\source\main.py"
$UiCwd      = "L:\PROJECTS\silvia lever\ui\windows\source"

function Write-Step($msg) {
    Write-Host ""
    Write-Host "==> $msg" -ForegroundColor Cyan
}

# ── 1. Kill anything holding the serial port ──────────────────────────────
Write-Step "Killing processes that may hold the serial port..."
Get-Process python* -ErrorAction SilentlyContinue | ForEach-Object {
    try {
        $cmd = (Get-CimInstance Win32_Process -Filter "ProcessId = $($_.Id)" -ErrorAction SilentlyContinue).CommandLine
        if ($cmd -match "main\.py") {
            Write-Host "  Stopping UI: PID $($_.Id)"
            Stop-Process -Id $_.Id -Force
        }
    } catch {}
}
# Close Arduino IDE Serial Monitor (holds port)
Get-Process "Arduino IDE" -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host "  Stopping Arduino IDE: PID $($_.Id)"
    Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Milliseconds 500

# ── 2. Find Teensy board ──────────────────────────────────────────────────
Write-Step "Locating Teensy board..."
$boards = & $ArduinoCli board list 2>&1
$teensyLine = $boards | Where-Object { $_ -match "teensy:avr:teensy40" }
if (-not $teensyLine) {
    Write-Host "ERROR: Teensy 4.0 not detected via arduino-cli board list" -ForegroundColor Red
    Write-Host $boards
    exit 1
}
# Extract port (first whitespace-delimited token)
$port = ($teensyLine -split '\s+')[0]
Write-Host "  Teensy at port: $port"

# ── 3. Compile ────────────────────────────────────────────────────────────
if (-not $NoCompile) {
    Write-Step "Compiling $SketchDir ..."
    $compileOutput = (& $ArduinoCli compile --fqbn $Fqbn "$SketchDir" 2>&1 | Out-String)
    $compileExit = $LASTEXITCODE
    if ($compileExit -ne 0) {
        Write-Host "COMPILE FAILED (exit $compileExit):" -ForegroundColor Red
        Write-Host $compileOutput
        exit 1
    }
    Write-Host $compileOutput.TrimEnd()
}

# ── 4. Upload ─────────────────────────────────────────────────────────────
if (-not $NoUpload) {
    Write-Step "Uploading to Teensy ..."
    $uploadOutput = (& $ArduinoCli upload --fqbn $Fqbn --port $port --protocol teensy "$SketchDir" 2>&1 | Out-String)
    $uploadExit = $LASTEXITCODE
    Write-Host $uploadOutput.TrimEnd()
    if ($uploadExit -ne 0) {
        Write-Host "UPLOAD FAILED (exit $uploadExit)" -ForegroundColor Red
        exit 1
    }

    # ── 5. Wait for Teensy re-enumeration ─────────────────────────────────────
    Write-Step "Waiting for Teensy to re-enumerate..."
    Start-Sleep -Seconds 2
} else {
    Write-Step "Skipping Teensy upload (-NoUpload)"
}

# ── 6. Launch UI ──────────────────────────────────────────────────────────
if (-not $NoUi) {
    Write-Step "Launching UI..."
    Start-Process python -ArgumentList "`"$UiScript`"" -WorkingDirectory $UiCwd
    Write-Host "  UI started."
}

Write-Host ""
Write-Host "DONE." -ForegroundColor Green
