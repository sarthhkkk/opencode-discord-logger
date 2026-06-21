# OpenCode Discord Logger

> Automatically log every OpenCode chat session to a Discord channel via webhook.

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-blue)](https://github.com/PowerShell/PowerShell)
[![Platform](https://img.shields.io/badge/platform-Windows-lightgrey)](https://github.com/sarthhkkk/opencode-discord-logger)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

## Features

- **Live Watch Mode** — polls OpenCode's SQLite DB every 60s, streams new messages to Discord in real-time
- **Session Export** — dump an entire session (past or current) to Discord with one command
- **Auto-Start** — PowerShell profile wrapper launches the logger before opencode starts; Startup folder shortcut for watch mode
- **Chunked Messages** — Discord's 2000-char limit is handled automatically; long conversations are split
- **Heartbeat** — periodic "I'm alive" message with active session count
- **Rate-Limit Safe** — 300ms delay between sends, respects Discord's webhook rate limits
- **Zero Dependencies** — pure PowerShell 5.1 + `sqlite3.exe` (ships with Windows, bundled with Git for Windows)
- **Configurable** — JSON config file, CLI args, and environment variable support

## How It Works

OpenCode stores chat history in a local SQLite database (`opencode.db`).
This script reads that database directly and sends formatted messages to a Discord webhook.

```
OpenCode ──writes──> opencode.db ──read by──> discord-log.ps1 ──sends──> Discord webhook
```

## Quick Start

### 1. Install

```powershell
# Clone or download
git clone https://github.com/sarthhkkk/opencode-discord-logger.git
cd opencode-discord-logger

# Run install (copies files, creates config, sets up wrapper)
powershell -ExecutionPolicy Bypass -File src\discord-log.ps1 -Install
```

### 2. Configure

Edit `$env:USERPROFILE\.opencode-discord-logger\config.json`:

```json
{
  "webhookUrl": "https://discord.com/api/webhooks/your-id/your-token",
  "intervalSeconds": 60,
  "heartbeatMins": 15,
  "includeReasoning": false
}
```

You can also set the `OPENCODE_DISCORD_WEBHOOK` environment variable instead.

### 3. Hook into OpenCode

Add to your PowerShell profile (`notepad $PROFILE`):

```powershell
function global:opencode {
    & "$env:USERPROFILE\.opencode-discord-logger\opencode-wrapper.ps1" $args
}
```

Now every time you run `opencode` in PowerShell, the logger will:
- Start watch mode in the background (if not already running)
- Launch the real opencode
- Export the session to Discord when you exit

## Usage

```powershell
# Export the most recent session
.\src\discord-log.ps1 -LastSession

# Export a specific session
.\src\discord-log.ps1 -SessionId "ses_abc123..."

# Start live watch mode (runs forever)
.\src\discord-log.ps1 -Watch

# Onboard: called by wrapper when opencode exits
.\src\discord-log.ps1 -Onboard

# Show version
.\src\discord-log.ps1 -Version
```

### All Parameters

| Parameter | Description |
|-----------|-------------|
| `-Watch` | Live polling mode. Checks for new messages every N seconds. |
| `-LastSession` | Export the most recent session to Discord. |
| `-SessionId <id>` | Export a specific session by ID. |
| `-Onboard` | Quick notification when opencode session ends (for wrapper). |
| `-IncludeReasoning` | Include AI reasoning tokens in export. |
| `-ConfigPath <path>` | Path to config JSON file. |
| `-WebhookUrl <url>` | Override webhook URL (takes priority over config). |
| `-DbPath <path>` | Override path to opencode.db. |
| `-Install` | Install the logger to `~/.opencode-discord-logger`. |
| `-Uninstall` | Remove all logger files. |
| `-Version` | Show script version. |

## Configuration

The logger looks for config in this order (last wins):

1. **Default config** embedded in the script
2. **`../config/config.json`** (relative to the script)
3. **`~/.config/opencode/config.json`**
4. **`~/.opencode-discord-logger/config.json`**
5. **CLI arguments** (`-WebhookUrl`, `-DbPath`)
6. **Environment variables** (`OPENCODE_DISCORD_WEBHOOK`, `OPENCODE_DB_PATH`)

### Config File Reference

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

| Key | Default | Description |
|-----|---------|-------------|
| `webhookUrl` | `""` | Discord webhook URL (required). |
| `dbPath` | auto-detect | Path to `opencode.db`. Auto-detects common locations. |
| `logDir` | script directory | Where to write `discord-log.log` and state files. |
| `intervalSeconds` | `60` | Polling interval for watch mode. |
| `heartbeatMins` | `15` | How often to send heartbeat "I'm alive" message (0 = disabled). |
| `maxMessagesPerBatch` | `10` | Max messages per Discord embed. |
| `includeToolResults` | `true` | Include tool call outputs in exports. |
| `includeReasoning` | `false` | Include AI reasoning tokens. |

## Advanced Setup

### Auto-Start Watch Mode at Login

Create a shortcut in the Startup folder:

```powershell
$wshell = New-Object -ComObject WScript.Shell
$shortcut = $wshell.CreateShortcut("$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\OpenCodeDiscordLog.lnk")
$shortcut.TargetPath = "powershell.exe"
$shortcut.Arguments = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$env:USERPROFILE\.opencode-discord-logger\scripts\discord-log.ps1`" -Watch"
$shortcut.Save()
```

### Environment Variables

| Variable | Description |
|----------|-------------|
| `OPENCODE_DISCORD_WEBHOOK` | Override webhook URL |
| `OPENCODE_DB_PATH` | Override path to opencode.db |

## What Gets Logged

Each message shows:
- **Role** (user / assistant) with emoji
- **Timestamp** (HH:mm:ss)
- **Content** (text, tool calls, tool results)

New sessions get a :new: announcement. Session title and creation date are included in exports.

## Finding the Database

OpenCode stores chat history at one of these locations:

| OS | Typical Path |
|----|-------------|
| Windows | `%USERPROFILE%\.local\share\opencode\opencode.db` |
| Windows | `%LOCALAPPDATA%\share\opencode\opencode.db` |
| Linux/macOS | `$XDG_DATA_HOME/opencode/opencode.db` or `~/.local/share/opencode/opencode.db` |

The script auto-detects the DB; you only need to configure it manually if it's in a non-standard location.

## Troubleshooting

### "No webhook URL"
Set one via config file, `webhook.txt` in the script directory, or the `OPENCODE_DISCORD_WEBHOOK` env var.

### "Cannot find opencode DB"
Pass `-DbPath` explicitly or set `OPENCODE_DB_PATH`. The script prints its auto-detection candidates on error.

### 429 Too Many Requests
Too many messages sent too fast. The script includes a 300ms delay between sends and respects Discord's rate limits. If you see this during export of a very long session, just wait and retry.

### Script Parsing Errors
If you copy the script and PowerShell reports parser errors, check for:
- Non-ASCII characters (em dashes, smart quotes) — replace with ASCII equivalents
- UTF-8 BOM — save as UTF-8 without BOM

### Messages Not Appearing
- Verify the webhook URL is correct
- Check `discord-log.log` for errors
- Ensure `opencode.exe` is actually creating messages in the DB

## Project Structure

```
opencode-discord-logger/
├── src/
│   └── discord-log.ps1    # Main logger script (415 lines, self-contained)
├── config/
│   └── config.json         # Example configuration
├── docs/                   # (future) Additional documentation
├── LICENSE                 # MIT
└── README.md               # This file
```

## Roadmap

- [x] Basic watch mode
- [x] Session export
- [x] Config file support
- [x] Auto-install with wrapper
- [x] OpenCode plugin integration
- [ ] Linux/macOS support (requires sqlite3 CLI)
- [ ] Discord embed formatting (embeds instead of plain text)
- [ ] Session summary stats (token count, duration)
- [ ] GitHub Actions CI

## License

MIT — see [LICENSE](LICENSE).

Built for [OpenCode](https://opencode.ai).
