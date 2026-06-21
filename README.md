
```
                    ╔══════════════════════════════════════════════╗
                    ║         OpenCode Discord Logger             ║
                    ║     Automatically log AI chats to Discord   ║
                    ╚══════════════════════════════════════════════╝
                              │                                   
                    ┌─────────┴─────────┐                        
                    │   PowerShell      │                        
                    │   Zero deps       │                        
                    └───────────────────┘                        
```

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?style=flat&logo=powershell&logoColor=white)](https://github.com/PowerShell/PowerShell)
[![Platform](https://img.shields.io/badge/Platform-Windows-0078D6?style=flat&logo=windows&logoColor=white)]()
[![License](https://img.shields.io/badge/License-MIT-4CAF50?style=flat)](LICENSE)
[![GitHub Stars](https://img.shields.io/github/stars/sarthhkkk/opencode-discord-logger?style=flat&logo=github)](https://github.com/sarthhkkk/opencode-discord-logger)
[![PRs Welcome](https://img.shields.io/badge/PRs-Welcome-FF6D00?style=flat)]()

---

##   Architecture

```
┌────────────────────────────────────────────────────────────────────┐
│                        YOUR MACHINE                                │
│                                                                    │
│  ┌──────────────┐    ┌────────────────────┐    ┌────────────────┐  │
│  │              │    │                    │    │                │  │
│  │   OpenCode   │────>   opencode.db      │<──── discord-log    │  │
│  │   (chat)     │    │   (SQLite)         │    │ .ps1           │  │
│  │              │    │                    │    │                │  │
│  └──────────────┘    └────────────────────┘    └───────┬────────┘  │
│                                                         │          │
│                                                         │ HTTPS    │
└─────────────────────────────────────────────────────────┼──────────┘
                                                           │
                                                           ▼
                                              ┌──────────────────────┐
                                              │                      │
                                              │   Discord Webhook    │
                                              │   #opencode-logs     │
                                              │                      │
                                              └──────────────────────┘
```

**Every message you send in OpenCode** is written to a local SQLite database.
This script watches that database and forwards new messages to your Discord
channel in real-time — with zero latency overhead on your chat experience.

---

##   Features at a Glance

```
 ⏱ Live Watch Mode        │  Streams messages to Discord every 60s
 📦 Session Export         │  Dump entire conversations with one command
 🚀 Auto-Start             │  Wraps opencode — start chatting, it logs
 ✂️ Smart Chunking         │  Handles Discord's 2000-char limit
 💓 Heartbeat              │  Periodic "I'm alive" with session count
 🛡️ Rate-Limit Safe        │  300ms spacing, respects Discord limits
 🧩 Zero Dependencies      │  Pure PowerShell + built-in sqlite3
 ⚙️ Configurable            │  JSON file / CLI args / env vars
```

---

##   Quick Start (3 Steps)

### Step 1 ─ Clone & Install

```powershell
# Grab the project
git clone https://github.com/sarthhkkk/opencode-discord-logger.git
cd opencode-discord-logger

# Run the installer — it copies files, creates config, and sets up a wrapper
powershell -ExecutionPolicy Bypass -File src\discord-log.ps1 -Install
```

### Step 2 ─ Paste Your Webhook URL

Edit the config file at:
```
%USERPROFILE%\.opencode-discord-logger\config.json
```

```json
{
  "webhookUrl": "https://discord.com/api/webhooks/1234567890/ABC-DEF_GHI",
  "intervalSeconds": 60,
  "heartbeatMins": 15,
  "includeReasoning": false
}
```

>   **Where do I get a webhook URL?**
> Open Discord → Server Settings → Integrations → Webhooks → New Webhook.
> Copy the URL and paste it into `config.json`.

**Alternative:** Set the `OPENCODE_DISCORD_WEBHOOK` environment variable instead.

### Step 3 ─ Wire It Into OpenCode

Add this to your PowerShell profile (`notepad $PROFILE`):

```powershell
function global:opencode {
    & "$env:USERPROFILE\.opencode-discord-logger\opencode-wrapper.ps1" $args
}
```

**That's it.** Now every time you run `opencode`:

```
┌──────────────────────────────────────────────────────────────────┐
│  1. Logger starts in background (watch mode)                     │
│  2. OpenCode launches normally                                   │
│  3. Every message is streamed to Discord in real-time            │
│  4. When you exit, the session summary is posted                 │
└──────────────────────────────────────────────────────────────────┘
```

---

##   Command Reference

```
┌─────────────────────────────────────────────────────────────────────┐
│  ██████╗ ██████╗ ███╗   ███╗███╗   ███╗ █████╗ ███╗   ██╗██████╗  │
│  ██╔════╝██╔═══██╗████╗ ████║████╗ ████║██╔══██╗████╗  ██║██╔══██╗ │
│  ██║     ██║   ██║██╔████╔██║██╔████╔██║███████║██╔██╗ ██║██║  ██║ │
│  ██║     ██║   ██║██║╚██╔╝██║██║╚██╔╝██║██╔══██║██║╚██╗██║██║  ██║ │
│  ╚██████╗╚██████╔╝██║ ╚═╝ ██║██║ ╚═╝ ██║██║  ██║██║ ╚████║██████╔╝ │
│   ╚═════╝ ╚═════╝ ╚═╝     ╚═╝╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═════╝  │
└─────────────────────────────────────────────────────────────────────┘
```

###   Export Modes

```powershell
# Export the most recent session
.\src\discord-log.ps1 -LastSession

# Export a specific session by ID
.\src\discord-log.ps1 -SessionId "ses_abc123def456"

# Include AI reasoning tokens (chain-of-thought)
.\src\discord-log.ps1 -LastSession -IncludeReasoning
```

###   Live Mode

```powershell
# Start watch mode — runs forever, polls every 60s
.\src\discord-log.ps1 -Watch

# Or launch hidden (for startup / background)
powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File src\discord-log.ps1 -Watch
```

###   Setup Commands

```powershell
# First-time install
.\src\discord-log.ps1 -Install

# Uninstall everything
.\src\discord-log.ps1 -Uninstall

# Quick notification (used by the wrapper)
.\src\discord-log.ps1 -Onboard

# Version info
.\src\discord-log.ps1 -Version
```

---

## ⚙️  Configuration Deep Dive

### Config Precedence (last wins)

```
 1.  Script defaults
 2.  ../config/config.json          (relative to script)
 3.  ~/.config/opencode/config.json  (global opencode config)
 4.  ~/.opencode-discord-logger/config.json  (install dir)
 5.  CLI arguments                   (-WebhookUrl, -DbPath)
 6.  Environment variables           (highest priority)
```

### Full Config Reference

```json
{
  "webhookUrl": "https://discord.com/api/webhooks/...",
  "dbPath": "C:\\Users\\you\\.local\\share\\opencode\\opencode.db",
  "logDir": "C:\\Users\\you\\.opencode-discord-logger\\logs",
  "intervalSeconds": 60,
  "heartbeatMins": 15,
  "maxMessagesPerBatch": 10,
  "includeToolResults": true,
  "includeReasoning": false
}
```

| Key                  | Default            | Description                                      |
|----------------------|--------------------|--------------------------------------------------|
| `webhookUrl`         | `""`               | Discord webhook URL **(required)**              |
| `dbPath`             | auto-detect        | Path to `opencode.db`                            |
| `logDir`             | script directory   | Where log + state files are written              |
| `intervalSeconds`    | `60`               | Polling interval for watch mode                  |
| `heartbeatMins`      | `15`               | Heartbeat frequency (`0` = off)                  |
| `maxMessagesPerBatch`| `10`               | Messages per Discord request                     |
| `includeToolResults` | `true`             | Include tool call outputs                        |
| `includeReasoning`   | `false`            | Include AI chain-of-thought tokens               |

### Environment Variables

```
OPENCODE_DISCORD_WEBHOOK      Override webhook URL
OPENCODE_DB_PATH              Override path to opencode.db
```

---

##   Auto-Start at Login

Want the logger running even before you open a terminal? Create a Startup shortcut:

```powershell
$wshell   = New-Object -ComObject WScript.Shell
$shortcut = $wshell.CreateShortcut(
    "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\OpenCodeDiscordLog.lnk"
)
$shortcut.TargetPath = "powershell.exe"
$shortcut.Arguments  = "-WindowStyle Hidden -ExecutionPolicy Bypass -File " +
    '"' + "$env:USERPROFILE\.opencode-discord-logger\scripts\discord-log.ps1" + '" -Watch'
$shortcut.Save()
```

Now the logger starts automatically every time you log into Windows.

---

##   Database Locations

The script auto-detects opencode.db. Here's where it looks:

| OS         | Path                                                       |
|------------|------------------------------------------------------------|
| Windows    | `%USERPROFILE%\.local\share\opencode\opencode.db`          |
| Windows    | `%LOCALAPPDATA%\share\opencode\opencode.db`                |
| Linux/macOS| `$XDG_DATA_HOME/opencode/opencode.db`                      |
| Linux/macOS| `~/.local/share/opencode/opencode.db`                      |

If yours is elsewhere, set `dbPath` in config or the `OPENCODE_DB_PATH` env var.

---

##   What Shows Up in Discord

```
┌──────────────────────────────────────────────────────────────────────┐
│  🆕 New session: Implement login feature [14:32:15]                  │
│                                                                      │
│  👤 user at 14:32:20                                                 │
│  Can you add a login page with email and password?                   │
│                                                                      │
│  🤖 assistant at 14:32:25                                           │
│  I'll create a login component with form validation:                 │
│                                                                      │
│  > Tool: generate_file(path="src/components/Login.tsx")              │
│  > Result: Created Login.tsx with email/password fields              │
│                                                                      │
│  👤 user at 14:33:10                                                 │
│  Looks good, but add a "Forgot Password" link                        │
│                                                                      │
│  🤖 assistant at 14:33:15                                           │
│  Added the forgot password link below the submit button.             │
└──────────────────────────────────────────────────────────────────────┘
```

**Every message includes:**
- Role indicator (  user /   assistant)
- Timestamp (HH:mm:ss)
- Full message content
- Tool calls and results (prefixed with `>`)

**Session boundaries:**
-  :new: New session announcement
-  ➡️ Session ended summary (title, date, duration)

---

##   Troubleshooting

```

  ╔══════════════════════════════════════════════════════════════╗
  ║   PRO TIP: All errors are logged to discord-log.log         ║
  ║   Check that file first when something isn't working.       ║
  ╚══════════════════════════════════════════════════════════════╝

```

### "No webhook URL" ────

**Fix:** Set it in config.json, `webhook.txt`, or `OPENCODE_DISCORD_WEBHOOK` env var.

### "Cannot find opencode DB" ────

**Fix:** Pass `-DbPath "C:\path\to\opencode.db"` or set `OPENCODE_DB_PATH`.

### 429 Too Many Requests ────

**Why:** Discord rate-limiting. Happens if you export a very long session.
**Fix:** Wait 30 seconds and retry. The script includes 300ms delays between sends.

### Script Parsing Errors ────

**Why:** PowerShell 5.1 has quirks with UTF-8 and non-ASCII characters.
**Fix:** Save the script as **UTF-8 without BOM**. Replace em dashes (`—`) and smart quotes with ASCII equivalents.

### Messages Not Appearing ────

```
  1. Is the webhook URL correct?    →  Test it with curl
  2. Any errors in discord-log.log? →  Check the file
  3. Is opencode writing to the DB? →  Run: sqlite3 opencode.db "SELECT COUNT(*) FROM message"
```

---

##   Project Structure

```
opencode-discord-logger/
│
├── src/
│   └── discord-log.ps1          #   Main script (415 lines, self-contained)
│
├── config/
│   └── config.json              # ⚙️ Example configuration
│
├── opencode-plugin.json         #   Plugin manifest for OpenCode
├── LICENSE                      # ⚖️ MIT License
└── README.md                    #   This file
```

---

##   Roadmap

```
   Done         In Progress      Planned
   ─────────────────────────────────────────────────
   ✅ Watch mode                 ❐ Linux/macOS support
   ✅ Session export             ❐ Discord embeds
   ✅ Config system              ❐ Session stats
   ✅ Auto-install               ❐ GitHub Actions CI
   ✅ Plugin integration         
```

---

##   Contributing

PRs welcome! If you'd like to add a feature or fix a bug:

```
  1. Fork the repo
  2. Create a feature branch (git checkout -b feat/awesome)
  3. Commit your changes (git commit -m 'Add awesome feature')
  4. Push to the branch (git push origin feat/awesome)
  5. Open a Pull Request
```

---

##   License

MIT — see [LICENSE](LICENSE).

Built for [OpenCode](https://opencode.ai).
