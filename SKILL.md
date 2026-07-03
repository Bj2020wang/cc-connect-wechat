---
name: cc-connect-wechat
description: >-
  Install and configure cc-connect to connect personal WeChat (个人微信) with Claude Code
  as an AI assistant. This skill covers the full setup workflow on Windows: downloading
  cc-connect, binding WeChat via ilink protocol, configuring config.toml, registering as
  a Windows service with NSSM for persistent background operation, and RDP-specific fixes.
  Triggered by requests like "install cc-connect", "connect WeChat to Claude Code",
  "微信接入 Claude", "cc-connect 安装", "微信 AI 助手 setup".
agent_created: true
---

# cc-connect WeChat Setup

## Overview

This skill enables connecting personal WeChat (个人微信) to Claude Code via cc-connect,
allowing users to chat with Claude AI directly from their phone's WeChat app. The full
workflow covers installation, WeChat binding, configuration, and Windows service registration
for persistent background operation (survives RDP disconnection and server restarts).

## Prerequisites

- Windows 10/11 or Windows Server (RDP environments supported)
- Node.js installed (for Claude Code)
- Claude Code installed (`npm install -g @anthropic-ai/claude-code`)
- PowerShell with administrator privileges
- Python 3.x available on the system (for download scripts)

## Workflow

### Step 1: Verify Claude Code Installation

Verify Claude Code is installed and accessible:

```powershell
claude --version
# Expected: 2.x.x (Claude Code)
```

If not installed, run: `npm install -g @anthropic-ai/claude-code`

If `claude` is not found in PATH, locate it manually:
```powershell
where.exe claude
# Typical path: C:\Users\<username>\AppData\Roaming\npm\claude
```

Record the npm global directory for later use in service configuration.

### Step 2: Download and Install cc-connect

**Option A: Direct browser download**

Download from: `https://github.com/chenhg5/cc-connect/releases`

Look for the latest `cc-connect-vX.X.X-windows-amd64.zip` file.

**Option B: Python download script**

Run the bundled download script:
```powershell
python scripts/download_cc_connect.py
```

The script downloads to the system temp directory and prints the file path.

**Install:**

```powershell
# Create install directory
New-Item -ItemType Directory -Force -Path "C:\Program Files\cc-connect" | Out-Null

# Extract (replace <download-path> with actual path)
Expand-Archive -Path "<download-path>\cc-connect-vX.X.X-windows-amd64.zip" `
  -DestinationPath "C:\Program Files\cc-connect" -Force

# Rename to short name
$exe = Get-ChildItem "C:\Program Files\cc-connect\cc-connect-v*-windows-amd64.exe" | Select-Object -First 1
Copy-Item $exe.FullName "C:\Program Files\cc-connect\cc-connect.exe" -Force

# Add to PATH
[Environment]::SetEnvironmentVariable(
  "PATH",
  [Environment]::GetEnvironmentVariable("PATH", "User") + ";C:\Program Files\cc-connect",
  "User"
)

# Verify
& "C:\Program Files\cc-connect\cc-connect.exe" --version
```

### Step 3: Initialize Config and Bind WeChat

```powershell
# Initialize default config (creates ~/.cc-connect/config.toml)
& "C:\Program Files\cc-connect\cc-connect.exe"
# Press Ctrl+C after it creates the config

# Bind personal WeChat via ilink protocol
& "C:\Program Files\cc-connect\cc-connect.exe" weixin setup
```

The `weixin setup` command displays a QR code in the terminal. Scan it with the phone's
WeChat app to authenticate. On success, the ilink token is automatically written to
`config.toml`.

### Step 4: Configure config.toml

Edit the config file:
```powershell
notepad "$env:USERPROFILE\.cc-connect\config.toml"
```

Use `references/config_template.toml` as a reference. Key changes required:

1. **Set `work_dir`** to a real Windows path (use double backslashes):
   ```toml
   work_dir = "C:\\Users\\<username>"
   ```

2. **Remove or comment out the Feishu platform** (if not using it) to avoid error spam.

3. **Add `allow_from`** to the weixin platform options to restrict access:
   ```toml
   allow_from = "<your-wechat-id>@im.wechat"
   ```
   To find the WeChat ID: send a message to the bot, then check cc-connect logs for
   `user=<id>@im.wechat`.

4. **Add `admin_from`** to enable privileged commands (/shell, /restart, etc.):
   ```toml
   admin_from = "<your-wechat-id>@im.wechat"
   ```

### Step 5: Test in Foreground Mode

Before setting up the service, test that everything works:

```powershell
& "C:\Program Files\cc-connect\cc-connect.exe"
```

Send a message from WeChat. If Claude responds, the setup is correct. Press Ctrl+C to stop.

**Critical:** Never run multiple cc-connect instances simultaneously. They will conflict
on the `.config.toml.lock` file.

### Step 6: Register as Windows Service (Recommended)

For persistent background operation (survives RDP disconnection, auto-restart on crash,
auto-start on boot), register cc-connect as a Windows service using NSSM.

Run the bundled service setup script in an elevated PowerShell:
```powershell
& "scripts/setup_ccconnect_service.ps1"
```

The script automatically:
1. Stops any running cc-connect process
2. Downloads and installs NSSM (from fightroad/nssm GitHub mirror)
3. Registers cc-connect as a Windows service (LocalSystem, auto-start)
4. Injects the full PATH and user environment variables (critical for LocalSystem to find `claude`)
5. Configures crash auto-restart (5 second delay)
6. Starts the service and verifies

**Key pitfall:** LocalSystem account does not have the user's PATH. Without
`AppEnvironmentExtra` injection, the service starts but immediately crashes because it
cannot find the `claude` command. The script handles this, but for manual setup:

```powershell
$nssm = "C:\Program Files\nssm\nssm.exe"
& $nssm set cc-connect AppEnvironmentExtra "PATH=$env:PATH" "HOME=$env:USERPROFILE" "USERPROFILE=$env:USERPROFILE" "APPDATA=$env:APPDATA"
```

### Step 7: RDP-Specific Fixes (If Applicable)

If the user is on RDP and also wants to use CC Switch (a GUI tool for managing AI provider
configs), WebView2 GPU acceleration causes blank windows. Fix:

```powershell
[Environment]::SetEnvironmentVariable(
  "WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS",
  "--disable-gpu",
  "User"
)
```

Restart CC Switch after setting this.

### Step 8: Verify Service Operation

```powershell
# Check service status
Get-Service cc-connect | Select-Object Name, Status, StartType

# Check logs
Get-Content "$env:USERPROFILE\.cc-connect\service-stderr.log" -Tail 30

# Send a WeChat message and verify response
```

## Service Management Commands

| Command | Description |
|---------|-------------|
| `net start cc-connect` | Start service |
| `net stop cc-connect` | Stop service |
| `net stop cc-connect; net start cc-connect` | Restart service |
| `Get-Service cc-connect` | Check status |
| `Get-Content ~\.cc-connect\service-stderr.log -Tail 50` | View recent logs |

## Troubleshooting

See `references/troubleshooting.md` for detailed solutions to common issues:

- Service status is "Paused" (LocalSystem cannot find claude)
- WeChat shows "暂无法连接" (process died)
- WeChat shows "启动 AGENT 会话失败" (work_dir path issue)
- RDP disconnection kills the process
- Multiple instance lock conflict
- NSSM download failures (nssm.cc 503)

## Resources

- **scripts/download_cc_connect.py** — Python script to download cc-connect zip from GitHub
- **scripts/setup_ccconnect_service.ps1** — PowerShell script to register cc-connect as a Windows service via NSSM
- **references/troubleshooting.md** — Detailed troubleshooting guide for common issues
- **references/config_template.toml** — Example config.toml with WeChat + allow_from configuration
