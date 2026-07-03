# cc-connect Windows Service Setup Script
# Registers cc-connect as a Windows service via NSSM for persistent background operation.
# Features: auto-start on boot, crash auto-restart, RDP-disconnect survival.
#
# Usage: Run in elevated PowerShell (Admin)
#   .\setup_ccconnect_service.ps1
#
# Prerequisites:
#   - cc-connect installed at C:\Program Files\cc-connect\cc-connect.exe
#   - config.toml configured at ~\.cc-connect\config.toml
#   - Claude Code installed and accessible in user PATH

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "=== cc-connect Service Setup ===" -ForegroundColor Cyan

# --- Config ---
$svcName = "cc-connect"
$exePath = "C:\Program Files\cc-connect\cc-connect.exe"
$nssmDir = "C:\Program Files\nssm"
$configDir = "$env:USERPROFILE\.cc-connect"

# --- Step 1: Stop existing processes ---
Write-Host "`n[1/6] Stopping cc-connect processes..." -ForegroundColor Yellow
Get-Process | Where-Object { $_.ProcessName -like "*cc-connect*" } | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Remove-Item "$configDir\.config.toml.lock" -ErrorAction SilentlyContinue
Write-Host "  Done." -ForegroundColor Green

# --- Step 2: Download and install NSSM ---
Write-Host "`n[2/6] Setting up NSSM..." -ForegroundColor Yellow
if (!(Test-Path "$nssmDir\nssm.exe")) {
    $nssmZip = "$env:TEMP\nssm-win64.zip"
    $nssmUrl = "https://github.com/fightroad/nssm/releases/download/v3.0.0/nssm-win64-Release.zip"

    Write-Host "  Downloading: $nssmUrl"
    $downloaded = $false
    try {
        Invoke-WebRequest -Uri $nssmUrl -OutFile $nssmZip -UseBasicParsing -TimeoutSec 60
        $downloaded = $true
        Write-Host "  Download OK." -ForegroundColor Green
    } catch {
        Write-Host "  PowerShell download failed, trying Python..." -ForegroundColor Yellow
        try {
            $py = (Get-Command python -ErrorAction SilentlyContinue).Source
            if (!$py) { $py = "python3" }
            & $py -c "import urllib.request; urllib.request.urlretrieve('$nssmUrl', r'$nssmZip'); print('done')"
            $downloaded = $true
        } catch {
            Write-Host "  Python download also failed." -ForegroundColor Red
        }
    }

    if (!$downloaded -or !(Test-Path $nssmZip) -or (Get-Item $nssmZip -ErrorAction SilentlyContinue).Length -lt 10000) {
        Write-Host "  ERROR: NSSM download failed." -ForegroundColor Red
        Write-Host "  Please download manually from: https://github.com/fightroad/nssm/releases" -ForegroundColor Gray
        exit 1
    }

    New-Item -ItemType Directory -Force -Path $nssmDir | Out-Null
    Expand-Archive -Path $nssmZip -DestinationPath $nssmDir -Force
    $nssmExe = Get-ChildItem "$nssmDir" -Recurse -Filter "nssm.exe" | Select-Object -First 1
    if ($nssmExe.FullName -ne "$nssmDir\nssm.exe") {
        Copy-Item $nssmExe.FullName "$nssmDir\nssm.exe" -Force
    }
    Remove-Item $nssmZip -Force -ErrorAction SilentlyContinue
}
Write-Host "  NSSM ready: $nssmDir\nssm.exe" -ForegroundColor Green

# --- Step 3: Register Windows service ---
Write-Host "`n[3/6] Registering cc-connect service..." -ForegroundColor Yellow
$nssm = "$nssmDir\nssm.exe"

# Remove old service if exists
& $nssm remove $svcName confirm 2>$null
Start-Sleep -Seconds 1

# Create service
& $nssm install $svcName $exePath

# Working directory
& $nssm set $svcName AppDirectory $configDir

# Auto-start on boot
& $nssm set $svcName Start SERVICE_AUTO_START

# Crash auto-restart (5 second delay)
& $nssm set $svcName AppExit Default Restart
& $nssm set $svcName AppRestartDelay 5000

# Log output to files
& $nssm set $svcName AppStdout "$configDir\service-stdout.log"
& $nssm set $svcName AppStderr "$configDir\service-stderr.log"
& $nssm set $svcName AppStdoutCreationDisposition 4
& $nssm set $svcName AppStderrCreationDisposition 4

# Run as LocalSystem (no password needed, Session 0)
& $nssm set $svcName ObjectName LocalSystem

# CRITICAL: Inject full PATH and user environment variables
# Without this, LocalSystem cannot find 'claude' command and the service immediately crashes
& $nssm set $svcName AppEnvironmentExtra "PATH=$env:PATH" "HOME=$env:USERPROFILE" "USERPROFILE=$env:USERPROFILE" "APPDATA=$env:APPDATA"

Write-Host "  Service registered." -ForegroundColor Green

# --- Step 4: Start service ---
Write-Host "`n[4/6] Starting service..." -ForegroundColor Yellow
& $nssm start $svcName
Start-Sleep -Seconds 5
Write-Host "  Done." -ForegroundColor Green

# --- Step 5: Verify ---
Write-Host "`n[5/6] Verifying..." -ForegroundColor Yellow
$svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
if ($svc) {
    Write-Host "  Name: $($svc.Name)" -ForegroundColor Green
    Write-Host "  Status: $($svc.Status)" -ForegroundColor Green
    Write-Host "  StartType: $($svc.StartType)" -ForegroundColor Green
} else {
    Write-Host "  ERROR: Service not found!" -ForegroundColor Red
}

# --- Step 6: Check process ---
Write-Host "`n[6/6] Checking process..." -ForegroundColor Yellow
$proc = Get-Process | Where-Object { $_.ProcessName -like "*cc-connect*" }
if ($proc) {
    Write-Host "  Running: PID $($proc.Id)" -ForegroundColor Green
} else {
    Write-Host "  WARNING: Process not detected. Check logs:" -ForegroundColor Red
    Write-Host "  $configDir\service-stderr.log" -ForegroundColor Gray
}

Write-Host "`n=== Complete ===" -ForegroundColor Cyan
Write-Host @"
cc-connect is now running as a Windows service:
  - Auto-start on boot
  - Survives RDP disconnection
  - Auto-restart 5s after crash

Management commands:
  Start:   net start cc-connect
  Stop:    net stop cc-connect
  Restart: net stop cc-connect; net start cc-connect
  Status:  Get-Service cc-connect
  Logs:    Get-Content $configDir\service-stderr.log -Tail 50

Send a WeChat message to test!
"@ -ForegroundColor White
