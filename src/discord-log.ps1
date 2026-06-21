param(
    [string]$ConfigPath = "",
    [string]$WebhookUrl = "",
    [string]$DbPath = "",
    [switch]$Watch,
    [switch]$LastSession,
    [string]$SessionId = "",
    [switch]$IncludeReasoning,
    [switch]$Onboard,
    [switch]$Install,
    [switch]$Uninstall,
    [switch]$Version
)

$ScriptVersion = "1.0.0"

if ($Version) { Write-Host "OpenCode Discord Logger v$ScriptVersion"; exit }

# --- CONFIG LOADING ---
$PossibleConfigs = @(
    $ConfigPath,
    [System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($MyInvocation.MyCommand.Path), "..", "config", "config.json"),
    [System.IO.Path]::Combine($env:USERPROFILE, ".config", "opencode", "config.json"),
    [System.IO.Path]::Combine($env:USERPROFILE, ".opencode-discord-logger", "config.json")
)

$Config = @{
    webhookUrl = ""
    dbPath = ""
    logDir = ""
    intervalSeconds = 60
    heartbeatMins = 15
    maxMessagesPerBatch = 10
    includeToolResults = $true
    includeReasoning = $false
}

foreach ($p in $PossibleConfigs) {
    if ($p -and (Test-Path $p)) {
        try {
            $loaded = Get-Content $p -Raw | ConvertFrom-Json
            foreach ($prop in $loaded.PSObject.Properties) {
                if ($Config.ContainsKey($prop.Name)) { $Config[$prop.Name] = $prop.Value }
            }
        } catch { Write-Warning "Failed to load config $p : $_" }
    }
}

# CLI args override config
if ($WebhookUrl) { $Config.webhookUrl = $WebhookUrl }
if ($DbPath) { $Config.dbPath = $DbPath }
if ($IncludeReasoning) { $Config.includeReasoning = $true }

# Env vars override
if ($env:OPENCODE_DISCORD_WEBHOOK) { $Config.webhookUrl = $env:OPENCODE_DISCORD_WEBHOOK }
if ($env:OPENCODE_DB_PATH) { $Config.dbPath = $env:OPENCODE_DB_PATH }

# --- PATH RESOLUTION ---
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Find opencode DB
if (-not $Config.dbPath) {
    $PossibleDb = @(
        "$env:USERPROFILE\.local\share\opencode\opencode.db",
        "$env:LOCALAPPDATA\share\opencode\opencode.db",
        "$env:APPDATA\opencode\opencode.db",
        "$env:XDG_DATA_HOME\opencode\opencode.db"
    )
    foreach ($p in $PossibleDb) { if (Test-Path $p) { $Config.dbPath = $p; break } }
}
if (-not $Config.dbPath) { Write-Error "Cannot find opencode DB. Set dbPath in config or OPENCODE_DB_PATH env var."; exit 1 }

$LogDir = if ($Config.logDir) { $Config.logDir } else { $ScriptDir }
$LogFile = "$LogDir\discord-log.log"
$StateFile = "$LogDir\discord-state.json"
$PidFile = "$LogDir\discord-watch.pid"

# --- WEBHOOK ---
if (-not $Config.webhookUrl) {
    $hookFile = "$ScriptDir\webhook.txt"
    if (Test-Path $hookFile) { $Config.webhookUrl = (Get-Content $hookFile -Raw).Trim() }
}
if (-not $Config.webhookUrl) { Write-Error "No webhook URL. Set --WebhookUrl, config.json, webhook.txt, or OPENCODE_DISCORD_WEBHOOK env var."; exit 1 }

# --- LOGGING ---
function Write-Log {
    param([string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts - $Message" | Out-File -FilePath $LogFile -Append -Encoding utf8
}

# --- DISCORD API ---
$ColorUser = 5793266       # Blue   0x5865F2
$ColorAssistant = 5763719  # Green  0x57F287
$ColorTool = 16704596      # Gold   0xFEE75C
$ColorSession = 10181046   # Purple 0x9B59B6
$ColorHeartbeat = 49151    # Teal   0x00BFFF
$ColorError = 15548997     # Red    0xED4245

$IconUser = "https://cdn.discordapp.com/embed/avatars/0.png"
$IconAssistant = "https://cdn.discordapp.com/embed/avatars/1.png"

function Send-Discord {
    param([string]$Content, [string]$Username = "OpenCode Chat")
    if (-not $Content -or $Content.Trim().Length -eq 0) { return $false }
    $safe = $Content -replace '[\x00-\x08\x0B\x0C\x0E-\x1F]', ''
    $body = @{ content = $safe; username = $Username } | ConvertTo-Json -Depth 3
    try {
        $jsonBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
        Invoke-RestMethod -Uri $Config.webhookUrl -Method Post -Body $jsonBytes -ContentType "application/json" -ErrorAction Stop | Out-Null
        Start-Sleep -Milliseconds 300
        return $true
    } catch {
        Write-Log "Discord send failed: $($_.Exception.Message.Substring(0,[Math]::Min(100,"$($_.Exception.Message)".Length)))"
        return $false
    }
}

function Send-Embed {
    param($Embed, [string]$Username = "OpenCode Chat")
    if (-not $Embed) { return $false }
    $body = @{ embeds = @($Embed); username = $Username } | ConvertTo-Json -Depth 5
    try {
        $jsonBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
        Invoke-RestMethod -Uri $Config.webhookUrl -Method Post -Body $jsonBytes -ContentType "application/json" -ErrorAction Stop | Out-Null
        Start-Sleep -Milliseconds 350
        return $true
    } catch {
        Write-Log "Embed send failed: $($_.Exception.Message.Substring(0,[Math]::Min(100,"$($_.Exception.Message)".Length)))"
        return $false
    }
}

function New-MessageEmbed {
    param([string]$Role, [string]$Content, [long]$Epoch, [string]$PartType = "text")
    if (-not $Content -or $Content.Trim().Length -eq 0) { return $null }
    $dt = (Get-Date '1970-01-01Z').AddMilliseconds($Epoch)
    $ts = $dt.ToString("HH:mm:ss")
    $iso = $dt.ToString("yyyy-MM-ddTHH:mm:ssZ")

    $isUser = ($Role -eq "user")
    $color = if ($PartType -eq "tool" -or $PartType -eq "tool-result") { $ColorTool } elseif ($isUser) { $ColorUser } else { $ColorAssistant }
    $emoji = if ($isUser) { ":bust_in_silhouette:" } else { ":robot:" }
    $icon = if ($isUser) { $IconUser } else { $IconAssistant }
    $desc = if ($PartType -eq "tool" -or $PartType -eq "tool-result") { "> $($Content.Trim())" } else { $Content.Trim() }

    $embed = @{
        author = @{ name = "$emoji  $Role"; icon_url = $icon }
        description = $desc
        color = $color
        footer = @{ text = $ts }
        timestamp = $iso
    }
    if ($desc.Length -gt 4000) { $embed.description = $desc.Substring(0, 3997) + "..." }
    return $embed
}

function New-SessionEmbed {
    param([string]$Title, [string]$Description, [string]$Footer = "", [int]$Color = $ColorSession)
    $embed = @{ color = $Color }
    if ($Title) { $embed.title = $Title }
    if ($Description) { $embed.description = $Description }
    if ($Footer) { $embed.footer = @{ text = $Footer } }
    return $embed
}

function Send-EmbedChunked {
    param([string]$Title, [string]$Body, [string]$Footer = "", [int]$Color = $ColorSession)
    $maxDesc = 4000
    $totalLen = $Body.Length
    $partNum = 0
    $totalParts = [Math]::Ceiling($totalLen / $maxDesc)

    while ($Body.Length -gt 0) {
        $partNum++
        $chunk = if ($Body.Length -gt $maxDesc) {
            $splitAt = $Body.LastIndexOf("`n", $maxDesc)
            if ($splitAt -le 0) { $splitAt = $maxDesc }
            $c = $Body.Substring(0, $splitAt)
            $Body = $Body.Substring($splitAt).TrimStart()
            $c
        } else {
            $c = $Body
            $Body = ""
            $c
        }
        $pTitle = if ($totalParts -gt 1) { "$Title (Part $partNum/$totalParts)" } else { $Title }
        $pFooter = if ($totalParts -gt 1) { "Page $partNum/$totalParts | $Footer" } else { $Footer }
        $embed = New-SessionEmbed -Title $pTitle -Description $chunk -Footer $pFooter -Color $Color
        Send-Embed -Embed $embed
    }
}

# --- PERSISTENT STATE ---
function Get-State {
    if (Test-Path $StateFile) {
        try { return Get-Content $StateFile -Raw | ConvertFrom-Json } catch {}
    }
    return @{ lastTime = 0; sessions = @{} }
}

function Save-State {
    param($State)
    $json = $State | ConvertTo-Json -Compress -Depth 5
    [System.IO.File]::WriteAllText($StateFile, $json, [System.Text.Encoding]::UTF8)
}

# --- MESSAGE RETRIEVAL ---
function Get-Messages {
    param([string]$Sid, [bool]$Reasoning = $false)
    $includeTypes = "'text', 'tool', 'tool-result', 'ask', 'say'"
    if ($Reasoning -or $Config.includeReasoning) { $includeTypes += ", 'reasoning'" }
    $sep = [char]1
    $q = "SELECT m.time_created, json_extract(m.data, '$.role') as role, " +
         "json_extract(p.data, '$.type') as part_type, " +
         "replace(json_extract(p.data, '$.text'), char(10), ' ') as part_text " +
         "FROM message m " +
         "JOIN part p ON p.message_id = m.id " +
         "WHERE m.session_id = ? " +
         "AND json_extract(p.data, '$.type') IN ($includeTypes)"
    $q = $q -replace '\?', "'$Sid'"
    $raw = sqlite3 $Config.dbPath -separator $sep $q 2>$null
    $result = @()
    foreach ($line in $raw) {
        $fields = $line -split $sep
        if ($fields.Count -ge 4) {
            $result += [PSCustomObject]@{
                epoch = if ($fields[0] -as [long]) { [long]$fields[0] } else { 0 }
                role = $fields[1]
                partType = $fields[2]
                text = $fields[3]
            }
        }
    }
    return $result
}

# --- FORMATTING ---
function Format-Messages {
    param($Messages)
    $lines = [System.Collections.Generic.List[string]]::new()
    $lastRole = ""
    foreach ($r in $Messages) {
        if (-not $r.text -or -not $r.text.Trim()) { continue }
        $dt = (Get-Date '1970-01-01Z').AddMilliseconds($r.epoch)
        $ts = $dt.ToString("HH:mm:ss")
        if ($r.role -ne $lastRole) {
            $lastRole = $r.role
            $emoji = if ($r.role -eq "user") { ":bust_in_silhouette:" } else { ":robot:" }
            $lines.Add("")
            $lines.Add("**$emoji $($r.role)** _at $ts_")
        }
        if ($r.partType -eq "tool" -or $r.partType -eq "tool-result") {
            $lines.Add(">>> $($r.text.Trim())")
        } else {
            $lines.Add($r.text.Trim())
        }
    }
    return $lines -join "`n"
}

# --- EXPORT ---
function Export-Session {
    param([string]$Sid, [bool]$Reasoning = $false)
    Write-Log "Exporting session $Sid..."
    $title = sqlite3 $Config.dbPath "SELECT title FROM session WHERE id='$Sid'"
    $epoch = sqlite3 $Config.dbPath "SELECT time_created FROM session WHERE id='$Sid'"
    $created = if ($epoch) { (Get-Date '1970-01-01Z').AddMilliseconds([long]$epoch).ToString("yyyy-MM-dd HH:mm") } else { "unknown" }
    $msgs = Get-Messages -Sid $Sid -Reasoning ($Reasoning -or $Config.includeReasoning)
    $body = Format-Messages -Messages $msgs
    $header = "**Date:** $created  **Messages:** $($msgs.Count)"
    Send-EmbedChunked -Title "Session: $title" -Body "$header`n$body" -Footer $created -Color $ColorSession
    Write-Log "Session $Sid exported"
}

# --- WATCH MODE ---
function Watch-Live {
    Write-Log "=== Watch mode started ==="
    Write-Log "DB: $($Config.dbPath)"
    [System.IO.File]::WriteAllText($PidFile, [System.Diagnostics.Process]::GetCurrentProcess().Id.ToString())

    Send-Embed -Embed (New-SessionEmbed -Title "OpenCode Logger Active" -Description "Watching for new sessions..." -Color $ColorHeartbeat)

    $state = Get-State
    $lastTime = [long]$state.lastTime
    if ($lastTime -eq 0) { $lastTime = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() }
    $knownSessions = @{}
    if ($state.sessions) {
        foreach ($s in $state.sessions.PSObject.Properties) { $knownSessions[$s.Name] = $s.Value }
    }
    $saveCounter = 0
    $heartbeatCounter = 0

    $watchQuery = "SELECT m.session_id, m.time_created, json_extract(m.data, '$.role') as role, " +
                  "json_extract(p.data, '$.type') as part_type, " +
                  "replace(json_extract(p.data, '$.text'), char(10), ' ') as part_text " +
                  "FROM message m " +
                  "JOIN part p ON p.message_id = m.id " +
                  "WHERE m.time_created > %LASTTIME% " +
                  "AND json_extract(p.data, '$.type') IN ('text', 'tool', 'tool-result') " +
                  "ORDER BY m.time_created ASC, p.time_created ASC"

    while ($true) {
        try {
            $sep = [char]1
            $q = $watchQuery -replace '%LASTTIME%', $lastTime
            $rows = sqlite3 $Config.dbPath -separator $sep $q 2>$null

            if ($rows -and $rows.Count -gt 0) {
                $newSessions = @{}
                $sessionMessages = @{}

                foreach ($row in $rows) {
                    $f = $row -split $sep
                    if ($f.Count -lt 5) { continue }
                    $sid = $f[0]; $t = [long]$f[1]
                    $role = $f[2]; $type = $f[3]; $text = $f[4]
                    if ($t -le $lastTime -or (-not $text)) { continue }
                    $lastTime = [Math]::Max($lastTime, $t)
                    $newSessions[$sid] = $true
                    if (-not $sessionMessages[$sid]) { $sessionMessages[$sid] = @() }
                    $sessionMessages[$sid] += [PSCustomObject]@{ epoch = $t; role = $role; partType = $type; text = $text }
                }

                foreach ($sid in $newSessions.Keys) {
                    $msgs = $sessionMessages[$sid] | Sort-Object epoch
                    $firstMsg = $msgs[0]

                    if (-not $knownSessions.ContainsKey($sid)) {
                        $title = sqlite3 $Config.dbPath "SELECT title FROM session WHERE id='$sid'"
                        $dt = (Get-Date '1970-01-01Z').AddMilliseconds($firstMsg.epoch)
                        $ts = $dt.ToString("HH:mm:ss")
                        $shortTitle = if ($title.Length -gt 80) { $title.Substring(0, 77) + "..." } else { $title }
                        Send-Embed -Embed (New-SessionEmbed -Title ":new: New Session" -Description "**$shortTitle**" -Footer $ts -Color $ColorSession)
                        $knownSessions[$sid] = $firstMsg.epoch
                    }

                    foreach ($m in $msgs) {
                        $embed = New-MessageEmbed -Role $m.role -Content $m.text -Epoch $m.epoch -PartType $m.partType
                        if ($embed) { Send-Embed -Embed $embed }
                    }
                }
            }

            $heartbeatCounter++
            if ($heartbeatCounter -ge ($Config.heartbeatMins * 60)) {
                $heartbeatCounter = 0
                $cutoff = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() - 300000
                $activeCount = sqlite3 $Config.dbPath "SELECT COUNT(DISTINCT session_id) FROM message WHERE time_created > $cutoff" 2>$null
                if ($activeCount) { Send-Embed -Embed (New-SessionEmbed -Title ":heartbeat: Logger Active" -Description "$activeCount active sessions in last 5 min" -Color $ColorHeartbeat) }
            }

            $saveCounter++
            if ($saveCounter -ge 30 -or ($rows -and $rows.Count -gt 0)) {
                $state.lastTime = $lastTime
                $state.sessions = $knownSessions
                Save-State -State $state
                $saveCounter = 0
            }
        } catch {
            Write-Log "Watch error: $_"
        }
        Start-Sleep -Seconds $Config.intervalSeconds
    }
}

# --- ONBOARD ---
function Onboard-Logger {
    Write-Log "=== Onboard (opencode wrapper) ==="
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $lookback = 5000
    $q = "SELECT id FROM session WHERE time_created > ($now - $lookback) ORDER BY time_created DESC LIMIT 1"
    $sid = sqlite3 $Config.dbPath $q
    if (-not $sid) {
        $sid = sqlite3 $Config.dbPath "SELECT id FROM session ORDER BY time_created DESC LIMIT 1"
    }
    if ($sid) {
        $title = sqlite3 $Config.dbPath "SELECT title FROM session WHERE id='$sid'"
        $created = sqlite3 $Config.dbPath "SELECT datetime(time_created/1000,'unixepoch','localtime') FROM session WHERE id='$sid'"
        Send-Embed -Embed (New-SessionEmbed -Title ":arrow_forward: Session Ended" -Description "**$title**" -Footer $created -Color $ColorSession)
    }
}

# --- INSTALL ---
function Install-Logger {
    $installDir = "$env:USERPROFILE\.opencode-discord-logger"
    Write-Host "Installing OpenCode Discord Logger to $installDir"
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
    New-Item -ItemType Directory -Path "$installDir\scripts" -Force | Out-Null

    Copy-Item $MyInvocation.MyCommand.Path "$installDir\scripts\discord-log.ps1" -Force

    $configDest = "$installDir\config.json"
    if (-not (Test-Path $configDest)) {
        $defaultConfig = @{
            webhookUrl = "YOUR_DISCORD_WEBHOOK_URL"
            dbPath = ""
            logDir = ""
            intervalSeconds = 60
            heartbeatMins = 15
            maxMessagesPerBatch = 10
            includeToolResults = $true
            includeReasoning = $false
        } | ConvertTo-Json
        [System.IO.File]::WriteAllText($configDest, $defaultConfig, [System.Text.Encoding]::UTF8)
        Write-Host "Config created: $configDest"
        Write-Host "IMPORTANT: Edit the webhookUrl in $configDest before using."
    }

    # Create wrapper
    $wrapperPath = "$installDir\opencode-wrapper.ps1"
@"
param(`$args)
`$ScriptDir = Split-Path -Parent `$MyInvocation.MyCommand.Path
`$Logger = "`$ScriptDir\scripts\discord-log.ps1"
`$PidFile = "`$ScriptDir\discord-watch.pid"
`$WatchRunning = `$false
if (Test-Path `$PidFile) {
    `$pid = (Get-Content `$PidFile -Raw).Trim()
    if (`$pid -as [int]) { `$WatchRunning = [bool](Get-Process -Id `$pid -ErrorAction SilentlyContinue) }
}
if (-not `$WatchRunning) {
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-ExecutionPolicy Bypass -File `"`$Logger`" -Watch"
    Start-Sleep -Seconds 3
}
& "opencode.exe" `$args
powershell.exe -ExecutionPolicy Bypass -File "`$Logger" -Onboard
"@ | Out-File -FilePath $wrapperPath -Encoding utf8

    Write-Host "Wrapper created: $wrapperPath"
    Write-Host ""
    Write-Host "To complete setup:"
    Write-Host "  1. Edit $configDest with your webhook URL"
    Write-Host "  2. Add to PowerShell profile:"
    Write-Host "     function global:opencode { & '$wrapperPath' `$args }"
    Write-Host "  3. Or use the wrapper directly: & '$wrapperPath'"
    Write-Host "Install complete."
}

# --- UNINSTALL ---
function Uninstall-Logger {
    $installDir = "$env:USERPROFILE\.opencode-discord-logger"
    if (Test-Path $installDir) {
        Remove-Item -Recurse -Force $installDir
        Write-Host "Removed $installDir"
    }
    $configDir = "$env:USERPROFILE\.config\opencode\scripts"
    if (Test-Path "$configDir\discord-log.ps1") {
        Write-Host "Found old installation at $configDir"
        $answer = Read-Host "Remove old files? (y/N)"
        if ($answer -eq 'y') {
            Remove-Item "$configDir\discord-log.ps1" -Force
            Remove-Item "$configDir\webhook.txt" -Force -ErrorAction SilentlyContinue
            Remove-Item "$configDir\discord-state.json" -Force -ErrorAction SilentlyContinue
            Remove-Item "$configDir\discord-watch.pid" -Force -ErrorAction SilentlyContinue
        }
    }
    Write-Host "Uninstall complete."
}

# --- MAIN DISPATCH ---
if ($Install) { Install-Logger; exit }
if ($Uninstall) { Uninstall-Logger; exit }
if ($Watch) { Watch-Live; exit }
if ($Onboard) { Onboard-Logger; exit }
if ($LastSession -or -not $SessionId) {
    if (-not $SessionId) {
        $SessionId = sqlite3 $Config.dbPath "SELECT id FROM session ORDER BY time_created DESC LIMIT 1"
    }
    if ($SessionId) {
        Export-Session -Sid $SessionId -Reasoning $IncludeReasoning
    } else {
        Write-Warning "No sessions found in DB."
    }
    exit
}
