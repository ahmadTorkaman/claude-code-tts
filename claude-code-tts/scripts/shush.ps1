$ErrorActionPreference = 'SilentlyContinue'
$lockfile = Join-Path $PSScriptRoot 'speak.pid'
if (Test-Path $lockfile) {
    $pidVal = Get-Content -LiteralPath $lockfile
    if ($pidVal) { Stop-Process -Id $pidVal -Force -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $lockfile -ErrorAction SilentlyContinue
}
# Sweep any stray speech child processes started by speak.ps1
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like '*SpeechSynthesis*' -or $_.CommandLine -like '*System.Speech*' -or $_.CommandLine -like '*claude_speak_*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Write-Output 'shushed'
