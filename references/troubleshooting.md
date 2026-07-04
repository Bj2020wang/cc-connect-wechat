# cc-connect Troubleshooting Guide

## Service Status is "Paused"

**Symptom:** `Get-Service cc-connect` shows `Paused` status. Service stderr log shows
repeated "config loaded" entries every 5 seconds with no further output.

**Cause:** The service runs as LocalSystem, which does not have the user's PATH environment
variable. cc-connect cannot find the `claude` command, crashes immediately, and NSSM pauses
the service.

**Fix:** Inject the full PATH and user environment variables into the service:

```powershell
$nssm = "C:\Program Files\nssm\nssm.exe"
net stop cc-connect
& $nssm set cc-connect AppEnvironmentExtra "PATH=$env:PATH" "HOME=$env:USERPROFILE" "USERPROFILE=$env:USERPROFILE" "APPDATA=$env:APPDATA"
net start cc-connect
```

Verify `claude` is in PATH:
```powershell
where.exe claude
# Should output: C:\Users\<username>\AppData\Roaming\npm\claude
```

---

## WeChat Shows "暂无法连接" (Cannot Connect)

**Symptom:** WeChat messages to the bot return "暂无法连接" error.

**Cause:** The cc-connect process is not running. This typically happens after RDP
disconnection (if running in foreground/hidden window mode) or after a server restart.

**Fix (if not using service mode):**
```powershell
# Check if process is running
Get-Process | Where-Object { $_.ProcessName -like "*cc-connect*" }

# If empty, restart:
Remove-Item "$env:USERPROFILE\.cc-connect\.config.toml.lock" -ErrorAction SilentlyContinue
Start-Process -FilePath "C:\Program Files\cc-connect\cc-connect.exe" -WindowStyle Hidden
```

**Permanent fix:** Register as Windows service (see `scripts/setup_ccconnect_service.ps1`).
The service runs in Session 0, independent of RDP sessions.

**Fix (if using service mode):**
```powershell
net stop cc-connect
net start cc-connect
Get-Service cc-connect | Select-Object Name, Status
```

---

## WeChat Shows "启动 AGENT 会话失败" (Agent Session Failed)

**Symptom:** WeChat message returns "错误，启动AGENT会话失败".

**Cause:** The `work_dir` in config.toml points to a non-existent path (e.g., the default
`/path/to/your/project` placeholder, or a Unix-style path on Windows).

**Fix:** Edit config.toml and set `work_dir` to a real Windows directory using double
backslashes:

```toml
[projects.agent.options]
work_dir = "C:\\Users\\<username>"
```

Also verify Claude Code is installed: `claude --version`

---

## RDP Disconnection Kills the Process

**Symptom:** cc-connect process dies when RDP session is disconnected.

**Cause:** When running via `Start-Process -WindowStyle Hidden` or directly in PowerShell,
the process is tied to the user's Windows session. RDP disconnection ends the session and
all associated processes.

**Fix:** Register cc-connect as a Windows service using NSSM. Services run in Session 0,
which is independent of user sessions:

```powershell
& "scripts/setup_ccconnect_service.ps1"
```

---

## Multiple Instance Lock Conflict

**Symptom:** cc-connect fails to start with "acquired instance lock" error, or a second
instance exits immediately.

**Cause:** Another cc-connect process is already running and holding the
`.config.toml.lock` file. Only one instance can run at a time.

**Fix:**
```powershell
# Kill all instances
Get-Process | Where-Object { $_.ProcessName -like "*cc-connect*" } | Stop-Process -Force
# Remove stale lock file
Remove-Item "$env:USERPROFILE\.cc-connect\.config.toml.lock" -ErrorAction SilentlyContinue
# Start fresh
Start-Process -FilePath "C:\Program Files\cc-connect\cc-connect.exe" -WindowStyle Hidden
```

---

## NSSM Download Fails (nssm.cc 503)

**Symptom:** `Invoke-WebRequest` to nssm.cc returns 503 Service Temporarily Unavailable.

**Cause:** The official nssm.cc website is frequently down or rate-limited.

**Fix:** Use the GitHub mirror instead:
- URL: `https://github.com/fightroad/nssm/releases/download/v3.0.0/nssm-win64-Release.zip`
- This is a Chinese-maintained fork with releases on GitHub, more reliable than nssm.cc.

The bundled `setup_ccconnect_service.ps1` script already uses this mirror.

---

## CC Switch GUI Blank in RDP

**Symptom:** CC Switch desktop app opens but shows a blank/white window. No UI renders.

**Cause:** CC Switch uses WebView2 (Tauri). In RDP environments, GPU acceleration causes
rendering failures.

**Fix:** Disable GPU acceleration for WebView2 globally:

```powershell
[Environment]::SetEnvironmentVariable(
  "WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS",
  "--disable-gpu",
  "User"
)
```

Restart CC Switch (right-click tray icon -> Exit, then relaunch).

---

## Feishu Platform Error Spam

**Symptom:** cc-connect logs show repeated Feishu errors: "app_id is invalid",
"failed to get bot open_id".

**Cause:** The default config.toml includes a Feishu platform section with placeholder
credentials. If not using Feishu, this causes error spam.

**Fix:** Comment out or delete the Feishu platform section in config.toml:

```toml
# [[projects.platforms]]
# type = "feishu"
# [projects.platforms.options]
# app_id = "your-feishu-app-id"
# app_secret = "your-feishu-app-secret"
```

---

## Finding Your WeChat ID for allow_from

**Symptom:** Need to set `allow_from` but don't know the WeChat ID format.

**Fix:**
1. Start cc-connect (foreground or service mode)
2. Send any message from WeChat to the bot
3. Check logs for the `user=` field:
   ```
   level=INFO msg="message received" platform=weixin user=o9cq80zbAa1UBQnqzETsDdGeVd6E@im.wechat
   ```
4. Use that value in config.toml:
   ```toml
   allow_from = "o9cq80zbAa1UBQnqzETsDdGeVd6E@im.wechat"
   admin_from = "o9cq80zbAa1UBQnqzETsDdGeVd6E@im.wechat"
   ```

---

## Model Not Switching After CC Switch Change

**Symptom:** Switched provider in CC Switch, but WeChat bot still responds with the old model.

**Cause:** CC Switch updates `~/.claude/settings.json` instantly, but cc-connect's running
Claude Code session has already loaded the old config into memory. The new provider settings
only take effect when Claude Code restarts.

**Fix:** Restart the cc-connect service after switching providers in CC Switch:

```powershell
net stop cc-connect
net start cc-connect
```

Verify the new config is in place:
```powershell
Get-Content "$env:USERPROFILE\.claude\settings.json" | ConvertFrom-Json | Select-Object -ExpandProperty env
```

You should see the new `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, and `ANTHROPIC_MODEL`.

---

## CC Switch Cannot Find Claude Code

**Symptom:** CC Switch shows "Claude Code not found" or provider switching doesn't write
to settings.json.

**Cause:** CC Switch looks for Claude Code's config at `~/.claude/settings.json`. If Claude
Code was never run, this file may not exist.

**Fix:** Run Claude Code once to initialize its config:
```powershell
claude --version
# Then launch claude once and exit
claude
# Press Ctrl+C or type /exit
```

Now check that `~/.claude/settings.json` exists:
```powershell
Test-Path "$env:USERPROFILE\.claude\settings.json"
```

---

## CC Switch Provider List is Empty

**Symptom:** CC Switch opens but shows no providers.

**Cause:** First run — no providers configured yet.

**Fix:** Click "Add Provider" and either:
1. Select from 50+ built-in presets (recommended)
2. Create a custom provider with your API key and base URL

You need at least one provider configured and activated for Claude Code to work.

---

## PowerShell Call Operator Error with Quoted Paths

**Symptom:** Running `& "path1" "path2"` in PowerShell gives "unexpected token" parser error.

**Cause:** PowerShell requires the `&` call operator when executing a command with a quoted
path. Without `&`, PowerShell interprets the quoted string as a string literal, not a command.

**Fix:** Always use `&` before the executable path:
```powershell
# Wrong:
"C:\path\to\python.exe" "C:\path\to\script.py"

# Right:
& "C:\path\to\python.exe" "C:\path\to\script.py"
```
