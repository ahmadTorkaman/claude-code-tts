# claude-code-tts installer for Windows
# Copies scripts to ~/.claude/scripts, registers the Stop hook in ~/.claude/settings.json,
# creates /shush and /reread slash commands, and installs Start Menu shortcuts with hotkeys.

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

$claudeDir   = Join-Path $env:USERPROFILE '.claude'
$scriptsDir  = Join-Path $claudeDir 'scripts'
$commandsDir = Join-Path $claudeDir 'commands'
$settings    = Join-Path $claudeDir 'settings.json'

Write-Host "Installing claude-code-tts to $claudeDir ..." -ForegroundColor Cyan

# 1. copy scripts
New-Item -ItemType Directory -Force -Path $scriptsDir  | Out-Null
New-Item -ItemType Directory -Force -Path $commandsDir | Out-Null
Copy-Item (Join-Path $repoRoot 'scripts\speak.ps1')  (Join-Path $scriptsDir 'speak.ps1')  -Force
Copy-Item (Join-Path $repoRoot 'scripts\shush.ps1')  (Join-Path $scriptsDir 'shush.ps1')  -Force
Copy-Item (Join-Path $repoRoot 'scripts\reread.ps1') (Join-Path $scriptsDir 'reread.ps1') -Force
Write-Host "  scripts copied" -ForegroundColor Green

# 2. merge Stop hook into settings.json (preserve anything already there)
$hookCommand = "powershell -NoProfile -ExecutionPolicy Bypass -File '$scriptsDir\speak.ps1'".Replace('\', '/')

if (Test-Path $settings) {
    $json = Get-Content -Raw -LiteralPath $settings | ConvertFrom-Json
} else {
    $json = [PSCustomObject]@{}
}

if (-not $json.PSObject.Properties['hooks']) {
    $json | Add-Member -NotePropertyName 'hooks' -NotePropertyValue ([PSCustomObject]@{})
}
$stopEntry = [PSCustomObject]@{
    matcher = ''
    hooks   = @(
        [PSCustomObject]@{
            type    = 'command'
            command = $hookCommand
        }
    )
}
$json.hooks | Add-Member -NotePropertyName 'Stop' -NotePropertyValue @($stopEntry) -Force

$json | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $settings -Encoding UTF8
Write-Host "  Stop hook registered in settings.json" -ForegroundColor Green

# 3. slash commands
$shushCmd = @"
---
description: Stop the text-to-speech reader mid-sentence
allowed-tools: Bash(powershell:*)
---

Run this command and then reply with only the word "shushed" on a single line:

``````
powershell -NoProfile -ExecutionPolicy Bypass -File "$scriptsDir\shush.ps1"
``````
"@
$shushCmd | Set-Content -LiteralPath (Join-Path $commandsDir 'shush.md') -Encoding UTF8

$rereadCmd = @"
---
description: Re-read the last Claude Code message aloud
allowed-tools: Bash(powershell:*)
---

Run this command and then reply with only the word "rereading" on a single line:

``````
powershell -NoProfile -ExecutionPolicy Bypass -File "$scriptsDir\reread.ps1"
``````
"@
$rereadCmd | Set-Content -LiteralPath (Join-Path $commandsDir 'reread.md') -Encoding UTF8
Write-Host "  /shush and /reread slash commands installed" -ForegroundColor Green

# 4. Start Menu shortcuts with global hotkeys
$startMenu = [Environment]::GetFolderPath('Programs')
$ws = New-Object -ComObject WScript.Shell

function New-HotkeyShortcut($name, $target, $hotkey, $description) {
    $lnkPath = Join-Path $startMenu "$name.lnk"
    $lnk = $ws.CreateShortcut($lnkPath)
    $lnk.TargetPath = 'powershell.exe'
    $lnk.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$target`""
    $lnk.WindowStyle = 7
    $lnk.Hotkey = $hotkey
    $lnk.Description = $description
    $lnk.Save()
    Write-Host "  $name -> $hotkey" -ForegroundColor Green
}

New-HotkeyShortcut 'Shush Claude'  (Join-Path $scriptsDir 'shush.ps1')  'CTRL+ALT+S' 'Stop Claude Code text-to-speech'
New-HotkeyShortcut 'Reread Claude' (Join-Path $scriptsDir 'reread.ps1') 'CTRL+ALT+R' 'Re-read last Claude Code message aloud'

Write-Host ""
Write-Host "Done." -ForegroundColor Cyan
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Restart any running Claude Code sessions."
Write-Host "  2. Run /hooks inside Claude Code and approve the new Stop hook the first time it fires."
Write-Host "  3. Hotkeys: Ctrl+Alt+S to shush, Ctrl+Alt+R to re-read."
Write-Host "  4. (Optional) Install 'Natural' voices from Settings > Time & Language > Speech"
Write-Host "     for dramatically better quality. Aria Natural / Guy Natural / Jenny Natural."
