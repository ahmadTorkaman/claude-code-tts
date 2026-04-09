# claude-code-tts uninstaller
$ErrorActionPreference = 'SilentlyContinue'

$claudeDir   = Join-Path $env:USERPROFILE '.claude'
$scriptsDir  = Join-Path $claudeDir 'scripts'
$commandsDir = Join-Path $claudeDir 'commands'
$settings    = Join-Path $claudeDir 'settings.json'

Write-Host "Uninstalling claude-code-tts..." -ForegroundColor Cyan

# Scripts
Remove-Item (Join-Path $scriptsDir 'speak.ps1')  -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $scriptsDir 'shush.ps1')  -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $scriptsDir 'reread.ps1') -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $scriptsDir 'speak.pid')  -Force -ErrorAction SilentlyContinue

# Slash commands
Remove-Item (Join-Path $commandsDir 'shush.md')  -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $commandsDir 'reread.md') -Force -ErrorAction SilentlyContinue

# Stop hook from settings.json
if (Test-Path $settings) {
    try {
        $json = Get-Content -Raw -LiteralPath $settings | ConvertFrom-Json
        if ($json.hooks -and $json.hooks.Stop) {
            $json.hooks.PSObject.Properties.Remove('Stop')
            $json | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $settings -Encoding UTF8
            Write-Host "  Stop hook removed from settings.json" -ForegroundColor Green
        }
    } catch { }
}

# Start Menu shortcuts
$startMenu = [Environment]::GetFolderPath('Programs')
Remove-Item (Join-Path $startMenu 'Shush Claude.lnk')  -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $startMenu 'Reread Claude.lnk') -Force -ErrorAction SilentlyContinue

Write-Host "Done." -ForegroundColor Cyan
