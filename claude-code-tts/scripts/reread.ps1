$ErrorActionPreference = 'SilentlyContinue'

# Find the most recently modified Claude Code transcript across all projects
$projectsDir = Join-Path $env:USERPROFILE '.claude\projects'
if (-not (Test-Path $projectsDir)) { exit 0 }

$latest = Get-ChildItem -Path $projectsDir -Recurse -Filter '*.jsonl' -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $latest) { exit 0 }

# Build a fake Stop-hook payload and pipe it into speak.ps1
$payload = @{
    session_id      = 'reread'
    transcript_path = $latest.FullName
    hook_event_name = 'Stop'
} | ConvertTo-Json -Compress

$speak = Join-Path $PSScriptRoot 'speak.ps1'
$payload | powershell -NoProfile -ExecutionPolicy Bypass -File $speak
