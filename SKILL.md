---
name: cc-connect-wechat
description: >-
  Install and configure cc-connect to connect personal WeChat (个人微信) with Claude Code
  as an AI assistant. This skill covers the full setup workflow on Windows: downloading
  cc-connect, binding WeChat via ilink protocol, configuring config.toml, registering as
  a Windows service with NSSM for persistent background operation, and RDP-specific fixes.
  Also covers CC Switch installation and model/provider switching (Anthropic, DeepSeek,
  and 50+ other providers). Triggered by requests like "install cc-connect", "connect
  WeChat to Claude Code", "微信接入 Claude", "cc-connect 安装", "微信 AI 助手 setup",
  "切换模型", "CC Switch 配置".
agent_created: true
---

# cc-connect WeChat Setup

## Overview

This skill enables connecting personal WeChat (个人微信) to Claude Code via cc-connect,
allowing users to chat with Claude AI directly from their phone's WeChat app. The full
workflow covers CC Switch (model/provider management), cc-connect installation, WeChat
binding, configuration, and Windows service registration for persistent background
operation (survives RDP disconnection and server restarts).

### Architecture

```
┌──────────────┐     writes     ┌──────────────────────┐     reads      ┌──────────────┐
│   CC Switch   │ ────────────── │ ~/.claude/settings.json│ ────────────── │ Claude Code  │
│  (GUI/Tary)  │   ANTHROPIC_*  │  env vars + API key   │   on launch    │   (agent)    │
└──────────────┘                └──────────────────────┘                └──────┬───────┘
       ▲                                                                        │
       │ switch model/provider                                         spawns    │
       │                                                                        ▼
┌──────┴────────┐  WeChat msg   ┌──────────────┐  forward   ┌──────────────────────┐
│  Your phone   │ ───────────── │   WeChat     │ ────────── │     cc-connect       │
│  (WeChat app) │               │   (ilink)    │            │  (Windows service)   │
└───────────────┘               └──────────────┘            └──────────────────────┘
```

**How it works:**
1. **CC Switch** manages which AI provider/model Claude Code uses. It writes the active
   provider's config (API key, base URL, model name) to `~/.claude/settings.json`.
2. **cc-connect** spawns Claude Code as its agent and connects to WeChat via ilink protocol.
3. When you send a WeChat message, cc-connect forwards it to Claude Code, which uses the
   provider configured by CC Switch to generate a response.
4. **Switching models:** Change provider in CC Switch → restart cc-connect service →
   new model takes effect on all subsequent WeChat messages.

## Prerequisites

- Windows 10/11 or Windows Server (RDP environments supported)
- Node.js 18+ installed (for Claude Code)
- Claude Code installed (`npm install -g @anthropic-ai/claude-code`)
- PowerShell with administrator privileges
- Python 3.x available on the system (for download scripts)
- A valid API key for at least one AI provider (Anthropic, DeepSeek, or any
  Anthropic-compatible API)

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

### Step 2: Install and Configure CC Switch (Model/Provider Management)

CC Switch is a desktop GUI tool that manages which AI provider and model Claude Code uses.
It supports 50+ built-in providers (Anthropic official, DeepSeek, Kimi, SiliconFlow, etc.)
and lets you switch between them with one click.

#### 2a. Download and Install CC Switch

Download the latest Windows MSI from: `https://github.com/farion1231/cc-switch/releases`

Look for `CC-Switch-vX.X.X-Windows.msi`.

Install silently:
```powershell
msiexec /i "<download-path>\CC-Switch-vX.X.X-Windows.msi" /quiet
```

Or double-click the MSI for graphical installation.

**RDP users:** CC Switch uses WebView2 (Tauri). In RDP environments, GPU acceleration
causes blank windows. Fix this BEFORE first launch:

```powershell
[Environment]::SetEnvironmentVariable(
  "WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS",
  "--disable-gpu",
  "User"
)
```

Restart CC Switch after setting this (or set it before first launch).

The app installs to: `C:\Users\<username>\AppData\Local\Programs\CC Switch\cc-switch.exe`

**Note:** CC Switch is a tray application. After launching, look for its icon in the
system tray (bottom-right corner, may be in the hidden icons area — click the `^` arrow).

#### 2b. Add a Provider Configuration

1. **Open CC Switch** (click tray icon or launch from Start Menu)
2. Click **"Add Provider"** (添加供应商)
3. Choose from 50+ built-in presets, or create a custom provider

**For DeepSeek (example):**
- Name: `DeepSeek`
- Base URL: `https://api.deepseek.com/anthropic`
- API Key: `sk-xxxxxxxxxxxx` (your DeepSeek API key)
- Model: `deepseek-v4-pro` (or `deepseek-v4-flash` for faster/cheaper)

**For Anthropic official:**
- Name: `Anthropic`
- Base URL: `https://api.anthropic.com`
- API Key: `sk-ant-xxxxxxxxxxxx` (your Anthropic API key)
- Model: `claude-sonnet-4-20250514` (or other Claude models)

**For any Anthropic-compatible API:**
- Name: custom name
- Base URL: the provider's Anthropic-compatible endpoint
- API Key: your key

4. Click **Save** (保存)

#### 2c. Activate a Provider

1. In CC Switch's provider list, click the provider you want to use
2. Click **"Enable"** (启用) — this writes the config to `~/.claude/settings.json`
3. Claude Code supports **hot-swap** — new config takes effect on next session

**Verify the config was written:**
```powershell
Get-Content "$env:USERPROFILE\.claude\settings.json"
```

You should see `env` section with `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, and
`ANTHROPIC_MODEL` set to your chosen provider's values.

Example (DeepSeek):
```json
{
  "env": {
    "ANTHROPIC_AUTH_TOKEN": "sk-xxxxxxxxxxxx",
    "ANTHROPIC_BASE_URL": "https://api.deepseek.com/anthropic",
    "ANTHROPIC_MODEL": "deepseek-v4-pro",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "deepseek-v4-pro",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "deepseek-v4-pro",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "deepseek-v4-flash"
  }
}
```

#### 2d. Switching Models Later

To change the AI model/provider at any time:

**Via CC Switch GUI:**
1. Open CC Switch (click tray icon)
2. Click a different provider
3. Click "Enable"
4. Restart cc-connect service (see Step 8): `net stop cc-connect; net start cc-connect`

**Via system tray:**
1. Right-click CC Switch tray icon
2. Select a provider from the menu
3. Restart cc-connect service

**Why restart cc-connect?** CC Switch updates Claude Code's config file instantly, but
cc-connect's running Claude Code session has already loaded the old config. Restarting
cc-connect spawns a fresh Claude Code session that picks up the new provider settings.

### Step 3: Download and Install cc-connect

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

### Step 4: Initialize Config and Bind WeChat

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

### Step 5: Configure config.toml

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

### Step 6: Test in Foreground Mode

Before setting up the service, test that everything works:

```powershell
& "C:\Program Files\cc-connect\cc-connect.exe"
```

Send a message from WeChat. If Claude responds, the setup is correct. Press Ctrl+C to stop.

**Critical:** Never run multiple cc-connect instances simultaneously. They will conflict
on the `.config.toml.lock` file.

### Step 7: Register as Windows Service (Recommended)

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

## Switching AI Models (CC Switch + cc-connect)

After changing the provider in CC Switch, restart cc-connect to apply the new model:

```powershell
# 1. Switch provider in CC Switch GUI (or tray icon)

# 2. Restart cc-connect service
net stop cc-connect
net start cc-connect

# 3. Test with a WeChat message
```

The WeChat bot response will now use the newly selected model. You can verify which model
is active by checking:
```powershell
# Check which model Claude Code is configured to use
Get-Content "$env:USERPROFILE\.claude\settings.json" | ConvertFrom-Json | Select-Object -ExpandProperty env
```

**Supported providers (50+ built-in):**
- Anthropic (official) — Claude Sonnet, Opus, Haiku
- DeepSeek — deepseek-v4-pro, deepseek-v4-flash
- Kimi K2.7 Code (Moonshot AI)
- SiliconFlow
- PackyCode, AIGoCode, NekoCode, DMXAPI, and many more
- Any custom Anthropic-compatible API endpoint

## Troubleshooting

See `references/troubleshooting.md` for detailed solutions to common issues:

- Service status is "Paused" (LocalSystem cannot find claude)
- WeChat shows "暂无法连接" (process died)
- WeChat shows "启动 AGENT 会话失败" (work_dir path issue)
- RDP disconnection kills the process
- Multiple instance lock conflict
- NSSM download failures (nssm.cc 503)
- CC Switch GUI blank in RDP (GPU acceleration)
- Model not switching after CC Switch change (forgot to restart cc-connect)

## Resources

- **scripts/download_cc_connect.py** — Python script to download cc-connect zip from GitHub
- **scripts/setup_ccconnect_service.ps1** — PowerShell script to register cc-connect as a Windows service via NSSM
- **references/troubleshooting.md** — Detailed troubleshooting guide for common issues
- **references/config_template.toml** — Example config.toml with WeChat + allow_from configuration
