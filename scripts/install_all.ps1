# ==============================================================================
# cc-connect-wechat One-Click Installer
# ==============================================================================
# This script does EVERYTHING except two things you must do manually:
#   1. Scan QR code with your phone WeChat (script will prompt you)
#   2. Configure API Key in CC Switch GUI (script will open it for you)
#
# Usage (run as Administrator in PowerShell):
#   Set-ExecutionPolicy Bypass -Scope Process -Force
#   .\install_all.ps1
#
# What this script does automatically:
#   [1] Check prerequisites (Claude Code, Node.js, admin rights)
#   [2] Download + install CC Switch (MSI silent install)
#   [3] Download + install cc-connect (latest from GitHub)
#   [4] Generate config.toml with correct paths
#   [5] Run WeChat QR setup (YOU scan with phone)
#   [6] Open CC Switch for API Key config (YOU fill in GUI)
#   [7] Download NSSM + register cc-connect as Windows service
#   [8] Start service + verify
# ==============================================================================

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# --- Helpers ---
function Write-Step($num, $msg) { Write-Host "`n[$num/8] $msg" -ForegroundColor Cyan }
function Write-OK($msg) { Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "  [!] $msg" -ForegroundColor Yellow }
function Write-Err($msg) { Write-Host "  [X] $msg" -ForegroundColor Red }
function Write-Info($msg) { Write-Host "  $msg" -ForegroundColor Gray }

function Download-File($url, $dest) {
    try {
        Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -TimeoutSec 120
        return $true
    } catch {
        # Fallback: Python download
        $py = (Get-Command python -ErrorAction SilentlyContinue).Source
        if (!$py) {
            $candidates = @(
                "$env:USERPROFILE\.workbuddy\binaries\python\versions\3.13.12\python.exe",
                "$env:USERPROFILE\.workbuddy\binaries\python\versions\3.12.8\python.exe",
                "C:\Program Files\Python312\python.exe",
                "python3", "python"
            )
            foreach ($c in $candidates) { if (Test-Path $c) { $py = $c; break } }
        }
        if ($py) {
            & $py -c "import urllib.request; urllib.request.urlretrieve('$url', r'$dest'); print('ok')"
            return (Test-Path $dest)
        }
        return $false
    }
}

Write-Host "========================================" -ForegroundColor Magenta
Write-Host "  cc-connect-wechat One-Click Installer" -ForegroundColor Magenta
Write-Host "========================================" -ForegroundColor Magenta

# --- [1] Check prerequisites ---
Write-Step 1 "Checking prerequisites..."

# Admin check
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (!$isAdmin) {
    Write-Err "Administrator rights required! Right-click PowerShell -> Run as Administrator."
    exit 1
}
Write-OK "Administrator rights confirmed."

# Claude Code check
$claudePath = (Get-Command claude -ErrorAction SilentlyContinue).Source
if (!$claudePath) {
    Write-Err "Claude Code not found! Install it first: npm install -g @anthropic-ai/claude-code"
    Write-Info "If already installed, close and reopen PowerShell, then re-run this script."
    exit 1
}
$claudeVersion = & claude --version 2>&1
Write-OK "Claude Code: $claudeVersion"
Write-Info "Path: $claudePath"

# Node.js check
$nodePath = (Get-Command node -ErrorAction SilentlyContinue).Source
if (!$nodePath) {
    Write-Err "Node.js not found! Install from https://nodejs.org/ (v18+ required)."
    exit 1
}
Write-OK "Node.js: $(& node --version)"

# --- [2] Download + install CC Switch ---
Write-Step 2 "Installing CC Switch..."

$ccSwitchExe = "$env:LOCALAPPDATA\Programs\CC Switch\cc-switch.exe"
if (Test-Path $ccSwitchExe) {
    Write-OK "CC Switch already installed at $ccSwitchExe"
} else {
    Write-Info "Fetching latest CC Switch release..."
    $ccSwitchVersion = "v3.16.3"
    try {
        $apiUrl = "https://api.github.com/repos/farion1231/cc-switch/releases/latest"
        $release = Invoke-RestMethod -Uri $apiUrl -Headers @{"User-Agent"="installer"} -TimeoutSec 15
        $ccSwitchVersion = $release.tag_name
        Write-Info "Latest version: $ccSwitchVersion"
    } catch {
        Write-Warn "Could not fetch latest version, using $ccSwitchVersion"
    }

    $msiUrl = "https://github.com/farion1231/cc-switch/releases/download/$ccSwitchVersion/CC-Switch-$($ccSwitchVersion -replace '^v','')-Windows.msi"
    $msiDest = "$env:TEMP\cc-switch-installer.msi"
    Write-Info "Downloading: $msiUrl"
    if (!(Download-File $msiUrl $msiDest)) {
        Write-Err "Download failed! Download manually from: https://github.com/farion1231/cc-switch/releases"
        exit 1
    }
    Write-OK "Downloaded $((Get-Item $msiDest).Length / 1MB) MB"

    Write-Info "Installing (silent)..."
    $msiResult = (Start-Process msiexec.exe -ArgumentList "/i `"$msiDest`" /quiet /norestart" -Wait -PassThru).ExitCode
    if ($msiResult -ne 0) {
        Write-Warn "Silent install exit code: $msiResult (may still be OK, trying GUI install)"
        Start-Process msiexec.exe -ArgumentList "/i `"$msiDest`"" -Wait
    }

    if (Test-Path $ccSwitchExe) {
        Write-OK "CC Switch installed."
        Remove-Item $msiDest -Force -ErrorAction SilentlyContinue
    } else {
        Write-Err "CC Switch install failed. Try manually: $msiUrl"
        exit 1
    }
}

# RDP GPU fix (preventive)
[Environment]::SetEnvironmentVariable("WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS", "--disable-gpu", "User")
Write-OK "Set WEBVIEW2 GPU fix (for RDP environments)"

# --- [3] Download + install cc-connect ---
Write-Step 3 "Installing cc-connect..."

$ccConnectDir = "C:\Program Files\cc-connect"
$ccConnectExe = "$ccConnectDir\cc-connect.exe"

if (Test-Path $ccConnectExe) {
    $existingVer = & $ccConnectExe --version 2>&1
    Write-OK "cc-connect already installed: $existingVer"
} else {
    Write-Info "Fetching latest cc-connect release..."
    $ccVer = "v1.3.4"
    try {
        $apiUrl = "https://api.github.com/repos/chenhg5/cc-connect/releases/latest"
        $release = Invoke-RestMethod -Uri $apiUrl -Headers @{"User-Agent"="installer"} -TimeoutSec 15
        $ccVer = $release.tag_name
        Write-Info "Latest version: $ccVer"
    } catch {
        Write-Warn "Could not fetch latest version, using $ccVer"
    }

    $zipUrl = "https://github.com/chenhg5/cc-connect/releases/download/$ccVer/cc-connect-$ccVer-windows-amd64.zip"
    $zipDest = "$env:TEMP\cc-connect.zip"
    Write-Info "Downloading: $zipUrl"
    if (!(Download-File $zipUrl $zipDest)) {
        Write-Err "Download failed! Download manually from: https://github.com/chenhg5/cc-connect/releases"
        exit 1
    }
    Write-OK "Downloaded $((Get-Item $zipDest).Length / 1MB) MB"

    New-Item -ItemType Directory -Force -Path $ccConnectDir | Out-Null
    Expand-Archive -Path $zipDest -DestinationPath $ccConnectDir -Force
    # Rename exe
    $realExe = Get-ChildItem $ccConnectDir -Filter "*.exe" | Select-Object -First 1
    if ($realExe.Name -ne "cc-connect.exe") {
        Copy-Item $realExe.FullName $ccConnectExe -Force
    }
    Remove-Item $zipDest -Force -ErrorAction SilentlyContinue
    Write-OK "cc-connect installed: $(& $ccConnectExe --version 2>&1)"
}

# Add to PATH
$pathDirs = [Environment]::GetEnvironmentVariable("PATH", "User") -split ";"
if ($ccConnectDir -notin $pathDirs) {
    [Environment]::SetEnvironmentVariable("PATH", [Environment]::GetEnvironmentVariable("PATH", "User") + ";$ccConnectDir", "User")
    $env:PATH += ";$ccConnectDir"
    Write-OK "Added to PATH."
}

# --- [4] Generate config.toml ---
Write-Step 4 "Generating configuration..."

$configDir = "$env:USERPROFILE\.cc-connect"
New-Item -ItemType Directory -Force -Path $configDir | Out-Null

# Run cc-connect once to create default config
& $ccConnectExe 2>&1 | Out-Null
Start-Sleep -Seconds 2

$configPath = "$configDir\config.toml"
if (!(Test-Path $configPath)) {
    Write-Err "Config not created. Running cc-connect manually..."
    & $ccConnectExe
}

# Rewrite config with correct settings
$configContent = @"
# cc-connect configuration (auto-generated)
# Model/provider is managed by CC Switch -> ~/.claude/settings.json

[log]
level = "info"

[[projects]]
name = "my-project"

[projects.agent]
type = "claudecode"

[projects.agent.options]
work_dir = "$($env:USERPROFILE -replace '\\','\\')"
mode = "default"

[[projects.platforms]]
type = "weixin"

[projects.platforms.options]
# Auto-filled by weixin setup in next step
token = ""
base_url = "https://ilinkai.weixin.qq.com"
account_id = ""
"@

# Preserve token if already set (from previous run)
$existingConfig = Get-Content $configPath -Raw -ErrorAction SilentlyContinue
if ($existingConfig -match 'token\s*=\s*"([^"]+)"') {
    $token = $matches[1]
    $configContent = $configContent -replace 'token = ""', "token = `"$token`""
    Write-Info "Preserved existing WeChat token."
}
if ($existingConfig -match 'account_id\s*=\s*"([^"]+)"') {
    $accountId = $matches[1]
    $configContent = $configContent -replace 'account_id = ""', "account_id = `"$accountId`""
    Write-Info "Preserved existing account_id."
}

Set-Content -Path $configPath -Value $configContent -Encoding UTF8
Write-OK "Config written to $configPath"
Write-Info "work_dir = $env:USERPROFILE"

# --- [5] WeChat QR setup ---
Write-Step 5 "WeChat binding (scan QR code)..."

$hasToken = $false
if ($existingConfig -and $existingConfig -match 'token\s*=\s*"([^"]+)"' -and $matches[1]) {
    $hasToken = $true
    Write-OK "WeChat token already configured. Skipping QR scan."
}

if (!$hasToken) {
    Write-Host "`n  >>> ACTION REQUIRED <<<" -ForegroundColor Yellow
    Write-Host "  A QR code will appear. Scan it with your phone WeChat." -ForegroundColor Yellow
    Write-Host "  Wait for the confirmation on your phone, then press Enter here.`n" -ForegroundColor Yellow
    Read-Host "  Press Enter to show QR code"

    # Run weixin setup - this shows QR code in terminal
    & $ccConnectExe weixin setup
    Start-Sleep -Seconds 2

    # Re-read config to get the token
    $updatedConfig = Get-Content $configPath -Raw
    if ($updatedConfig -match 'token\s*=\s*"([^"]+)"' -and $matches[1]) {
        Write-OK "WeChat token configured successfully!"
    } else {
        Write-Warn "Token not detected in config. You may need to run: cc-connect weixin setup"
    }
}

# --- [6] Open CC Switch for API Key ---
Write-Step 6 "CC Switch - configure your API provider..."

Write-Host "`n  >>> ACTION REQUIRED <<<" -ForegroundColor Yellow
Write-Host "  CC Switch will open. In the GUI:" -ForegroundColor Yellow
Write-Host "  1. Add a provider (e.g., DeepSeek, Anthropic)" -ForegroundColor Yellow
Write-Host "  2. Enter your API Key" -ForegroundColor Yellow
Write-Host "  3. Click Enable to activate it" -ForegroundColor Yellow
Write-Host "  4. Close CC Switch when done`n" -ForegroundColor Yellow
    Read-Host "  Press Enter to open CC Switch"

Start-Process $ccSwitchExe
Write-Info "CC Switch opened. Configure your API provider, then come back."
Read-Host "  Press Enter after you've configured API Key in CC Switch"

# --- [7] Download NSSM + register service ---
Write-Step 7 "Registering as Windows service..."

# Stop any existing processes
Get-Process | Where-Object { $_.ProcessName -like "*cc-connect*" } | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Remove-Item "$configDir\.config.toml.lock" -ErrorAction SilentlyContinue

# NSSM
$nssmDir = "C:\Program Files\nssm"
$nssmExe = "$nssmDir\nssm.exe"

if (!(Test-Path $nssmExe)) {
    Write-Info "Downloading NSSM..."
    $nssmUrl = "https://github.com/fightroad/nssm/releases/download/v3.0.0/nssm-win64-Release.zip"
    $nssmZip = "$env:TEMP\nssm.zip"
    if (!(Download-File $nssmUrl $nssmZip)) {
        Write-Err "NSSM download failed! Download manually from: https://github.com/fightroad/nssm/releases"
        exit 1
    }
    New-Item -ItemType Directory -Force -Path $nssmDir | Out-Null
    Expand-Archive -Path $nssmZip -DestinationPath $nssmDir -Force
    $found = Get-ChildItem $nssmDir -Recurse -Filter "nssm.exe" | Select-Object -First 1
    if ($found.FullName -ne $nssmExe) { Copy-Item $found.FullName $nssmExe -Force }
    Remove-Item $nssmZip -Force -ErrorAction SilentlyContinue
}
Write-OK "NSSM ready."

# Remove old service
& $nssmExe remove cc-connect confirm 2>$null
Start-Sleep -Seconds 1

# Create service
& $nssmExe install cc-connect $ccConnectExe
& $nssmExe set cc-connect AppDirectory $configDir
& $nssmExe set cc-connect Start SERVICE_AUTO_START
& $nssmExe set cc-connect AppExit Default Restart
& $nssmExe set cc-connect AppRestartDelay 5000
& $nssmExe set cc-connect AppStdout "$configDir\service-stdout.log"
& $nssmExe set cc-connect AppStderr "$configDir\service-stderr.log"
& $nssmExe set cc-connect AppStdoutCreationDisposition 4
& $nssmExe set cc-connect AppStderrCreationDisposition 4
& $nssmExe set cc-connect ObjectName LocalSystem

# CRITICAL: Inject PATH so LocalSystem can find 'claude'
& $nssmExe set cc-connect AppEnvironmentExtra "PATH=$env:PATH" "HOME=$env:USERPROFILE" "USERPROFILE=$env:USERPROFILE" "APPDATA=$env:APPDATA"

Write-OK "Service registered with PATH injection."

# --- [8] Start + verify ---
Write-Step 8 "Starting service + verification..."

& $nssmExe start cc-connect
Start-Sleep -Seconds 5

$svc = Get-Service cc-connect -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -eq "Running") {
    Write-OK "Service is RUNNING! (PID: $((Get-Process cc-connect -ErrorAction SilentlyContinue).Id))")
} elseif ($svc -and $svc.Status -eq "Paused") {
    Write-Warn "Service is Paused - likely can't find 'claude'. Check logs:"
    Write-Info "Get-Content `"$configDir\service-stderr.log`" -Tail 30"
    Write-Info "Common fix: ensure Claude Code is in PATH and restart: net stop cc-connect; net start cc-connect"
} else {
    Write-Warn "Service status: $($svc.Status). Check logs."
}

# --- Done ---
Write-Host "`n========================================" -ForegroundColor Magenta
Write-Host "  Installation Complete!" -ForegroundColor Magenta
Write-Host "========================================" -ForegroundColor Magenta

Write-Host @"
`nWhat was installed:
  - CC Switch: $ccSwitchExe
  - cc-connect: $ccConnectExe
  - Config: $configPath
  - Service: cc-connect (auto-start, crash-restart)

Test now:
  Send a message to your WeChat bot!

Management commands:
  Status:  Get-Service cc-connect
  Restart: net stop cc-connect; net start cc-connect
  Logs:    Get-Content "$configDir\service-stderr.log" -Tail 50

To change AI model:
  1. Open CC Switch from desktop
  2. Switch provider
  3. Restart service: net stop cc-connect; net start cc-connect
"@ -ForegroundColor White
