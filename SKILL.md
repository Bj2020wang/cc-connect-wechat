---
name: cc-connect-wechat
description: |
  One-click install: connect personal WeChat (个人微信) to Claude Code via cc-connect,
  with CC Switch for model/provider management. Triggers on: 微信接入Claude、cc-connect安装、
  cc-connect setup、个人微信连AI、微信机器人Claude、connect wechat to claude code、
  one-click cc-connect install、AI编程微信助手
---

# cc-connect-wechat: One-Click Install

Connect personal WeChat to Claude Code. One script does everything except
two things you must do manually (scan QR + fill API Key).

## Agent Instructions (Read First)

When this skill is triggered, follow these steps IN ORDER:

1. **Check prerequisites** — Ask the user if they have:
   - Claude Code installed (`npm install -g @anthropic-ai/claude-code`)
   - Node.js 18+ installed
   - An API Key ready (DeepSeek recommended: https://platform.deepseek.com/)
   - Phone with WeChat installed
   If any are missing, guide them to install first.

2. **Tell the user to open an Administrator PowerShell window.**
   WorkBuddy's built-in PowerShell may NOT have admin rights, so the user must
   open one themselves. Give them these EXACT instructions:

   > Right-click Start menu → "Windows PowerShell (Admin)" or "Terminal (Admin)"
   > Click "Yes" on the UAC prompt

3. **Tell the user to paste this command in the admin PowerShell:**

   ```powershell
   Set-ExecutionPolicy Bypass -Scope Process -Force
   & "$env:USERPROFILE\.workbuddy\skills\cc-connect-wechat\scripts\install_all.ps1"
   ```

4. **Explain what will happen next:**
   - Script runs automatically for ~2-3 minutes (downloads + installs everything)
   - It will PAUSE and show a QR code → user scans with phone WeChat
   - It will PAUSE again → CC Switch opens, user fills in API Key
   - Then it finishes and starts the service

5. **Stay available for troubleshooting.** If the user reports errors,
   check `references/troubleshooting.md` for solutions.

DO NOT try to run install_all.ps1 from WorkBuddy's built-in PowerShell —
it requires Administrator elevation and will fail without it.

## What Gets Installed

```
WeChat (your phone)  →  cc-connect (Windows service)  →  Claude Code  ←  CC Switch (model picker)
                          ^                                ^
                          |___ forwards messages __________|
                                       service auto-starts on boot,
                                       survives RDP disconnect,
                                       auto-restarts on crash
```

## The 3-Step Flow

### Step 1: Run the installer (automatic, ~2-3 min)

The script `scripts/install_all.ps1` handles:
- Prerequisites check (Claude Code, Node.js, admin rights)
- Download + silent install CC Switch (MSI)
- Download + install cc-connect (latest from GitHub)
- Generate config.toml with correct Windows paths
- Download NSSM + register cc-connect as Windows service
- Inject PATH environment (so service can find `claude`)
- Start service + verify

**Must be run in an Administrator PowerShell window** (see Agent Instructions above).

The script pauses at two points and asks the user to do something — see below.

### Step 2: Scan QR + Configure API Key (manual, ~2 min)

The installer script pauses twice and tells the user exactly what to do:

**Pause A — WeChat QR scan:**
- A QR code appears in the terminal
- User scans it with phone WeChat
- Token auto-writes to config.toml
- Press Enter to continue

**Pause B — CC Switch API Key:**
- CC Switch GUI opens automatically
- User adds a provider (DeepSeek / Anthropic / custom API)
- User enters API Key
- User clicks "Enable"
- Close CC Switch, press Enter to continue

### Step 3: Verify (automatic)

Script starts the service and checks status. User sends a WeChat message to test.
Done.

## What the User Needs Before Starting

1. **Windows 10/11 or Windows Server** with Administrator access
2. **Claude Code installed** (`npm install -g @anthropic-ai/claude-code`)
3. **Node.js 18+** (for Claude Code)
4. **An API Key** from any provider:
   - DeepSeek (recommended, cheap): https://platform.deepseek.com/
   - Anthropic: https://console.anthropic.com/
   - Any OpenAI-compatible API
5. **Phone with WeChat** (for QR scan)

## Post-Install: Changing AI Model

1. Open CC Switch from desktop shortcut
2. Switch to a different provider (or add a new one)
3. Restart the service: `net stop cc-connect; net start cc-connect`
4. New model is now active — send a WeChat message to confirm

## Management Commands

```powershell
# Service status
Get-Service cc-connect

# Restart (after changing model in CC Switch)
net stop cc-connect; net start cc-connect

# View logs
Get-Content "$env:USERPROFILE\.cc-connect\service-stderr.log" -Tail 50

# Re-run WeChat setup (re-bind different WeChat account)
& "C:\Program Files\cc-connect\cc-connect.exe" weixin setup
```

## Troubleshooting

See `references/troubleshooting.md` for solutions to all known issues:
- RDP: CC Switch window blank/white
- Service stuck on Paused
- WeChat shows "暂无法连接"
- WeChat shows "启动AGENT会话失败"
- Model doesn't change after switching in CC Switch
- NSSM download failures
- PowerShell path quoting errors

## Files

```
cc-connect-wechat/
├── SKILL.md                          # This file
├── scripts/
│   └── install_all.ps1               # ONE-CLICK installer (does everything)
└── references/
    ├── troubleshooting.md            # All known issues + fixes
    └── config_template.toml          # Reference config (for manual editing)
```
