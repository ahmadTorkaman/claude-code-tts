$ErrorActionPreference = 'SilentlyContinue'

# ---------- read Claude Code Stop-hook payload from stdin ----------
$inputJson = [Console]::In.ReadToEnd()
if (-not $inputJson) { exit 0 }
try { $data = $inputJson | ConvertFrom-Json } catch { exit 0 }
$transcript = $data.transcript_path
if (-not $transcript -or -not (Test-Path $transcript)) { exit 0 }

# ---------- extract last assistant text message from the transcript ----------
$lines = Get-Content -LiteralPath $transcript
$text = $null
for ($i = $lines.Count - 1; $i -ge 0; $i--) {
    $line = $lines[$i]
    if (-not $line) { continue }
    try { $obj = $line | ConvertFrom-Json } catch { continue }
    if ($obj.type -ne 'assistant') { continue }
    if (-not $obj.message.content) { continue }
    $parts = @()
    foreach ($block in $obj.message.content) {
        if ($block.type -eq 'text' -and $block.text) { $parts += $block.text }
    }
    if ($parts.Count -gt 0) {
        $text = [string]::Join("`n`n", $parts)
        break
    }
}
if (-not $text) { exit 0 }

# ---------- smart preprocessing so speech sounds like prose, not markdown ----------
function Clean-ForSpeech([string]$t) {
    # Drop fenced code blocks — replaced with a short pause marker
    $t = [regex]::Replace($t, '(?s)```.*?```', '. ')
    # Short inline code → spoken as-is; long inline code → dropped
    $t = [regex]::Replace($t, '`([^`]{1,30})`', '$1')
    $t = [regex]::Replace($t, '`[^`]*`', ' ')
    # Markdown links [text](url) → just the text
    $t = [regex]::Replace($t, '\[([^\]]+)\]\([^\)]+\)', '$1')
    # Bare URLs → "a link"
    $t = [regex]::Replace($t, 'https?://\S+', 'a link')
    # File paths with common extensions → "a file"
    $t = [regex]::Replace($t, '(?<![\w/])[\w./\\-]+\.(ps1|js|ts|tsx|jsx|py|md|json|yaml|yml|html|css|txt|log|sh|rs|go|java|c|cpp|h)\b', 'a file')
    # Heading markers — drop, let the paragraph break do the pause work
    $t = [regex]::Replace($t, '(?m)^#{1,6}\s+', '')
    # Bullet markers → sentence break
    $t = [regex]::Replace($t, '(?m)^\s*[-*•]\s+', '. ')
    # Numbered list markers → sentence break
    $t = [regex]::Replace($t, '(?m)^\s*\d+\.\s+', '. ')
    # Blockquote markers
    $t = [regex]::Replace($t, '(?m)^>\s*', '')
    # Horizontal rules
    $t = [regex]::Replace($t, '(?m)^(\s*[-*_]){3,}\s*$', '. ')
    # Table pipes/separators
    $t = [regex]::Replace($t, '\|', ' ')
    $t = [regex]::Replace($t, '(?m)^\s*:?-+:?\s*$', '')
    # Bold/italic/underscore emphasis markers
    $t = [regex]::Replace($t, '(\*\*|__|\*|_)', '')
    # Paragraph breaks → explicit sentence pause
    $t = [regex]::Replace($t, "`r?`n`r?`n+", '. ')
    # Remaining line breaks → space
    $t = [regex]::Replace($t, "`r?`n", ' ')
    # Collapse whitespace
    $t = [regex]::Replace($t, '\s+', ' ').Trim()
    # Collapse repeated sentence terminators created by the substitutions
    $t = [regex]::Replace($t, '(\s*[.!?]\s*){2,}', '. ')
    return $t.Trim()
}
$text = Clean-ForSpeech $text
if (-not $text) { exit 0 }

# ---------- kill any previous speaker (so new turn supersedes old) ----------
$lockfile = Join-Path $PSScriptRoot 'speak.pid'
if (Test-Path $lockfile) {
    $oldpid = Get-Content -LiteralPath $lockfile -ErrorAction SilentlyContinue
    if ($oldpid) { Stop-Process -Id $oldpid -Force -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $lockfile -ErrorAction SilentlyContinue
}

# ---------- spawn a hidden background speaker child ----------
$tmpfile = Join-Path $env:TEMP ("claude_speak_" + [guid]::NewGuid().ToString() + ".txt")
Set-Content -LiteralPath $tmpfile -Value $text -Encoding UTF8

$childScript = @"
`$ErrorActionPreference = 'SilentlyContinue'
`$text = Get-Content -Raw -Encoding UTF8 -LiteralPath '$tmpfile'
`$spoken = `$false

# ---- Preferred path: WinRT Windows.Media.SpeechSynthesis (can use Neural/Natural voices) ----
try {
    [Windows.Media.SpeechSynthesis.SpeechSynthesizer,Windows.Media.SpeechSynthesis,ContentType=WindowsRuntime] | Out-Null
    [Windows.Storage.Streams.DataReader,Windows.Storage.Streams,ContentType=WindowsRuntime] | Out-Null
    Add-Type -AssemblyName System.Runtime.WindowsRuntime -ErrorAction Stop

    function Invoke-Await(`$op, [Type]`$t) {
        `$asTaskGeneric = [System.WindowsRuntimeSystemExtensions].GetMethods() |
            Where-Object {
                `$_.Name -eq 'AsTask' -and
                `$_.GetParameters().Count -eq 1 -and
                `$_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation``1'
            } | Select-Object -First 1
        `$g = `$asTaskGeneric.MakeGenericMethod(`$t)
        `$task = `$g.Invoke(`$null, @(`$op))
        `$task.Wait() | Out-Null
        `$task.Result
    }

    `$synth = New-Object Windows.Media.SpeechSynthesis.SpeechSynthesizer

    # Voice preference: Natural > Online > first English > whatever
    `$voice = `$synth.AllVoices | Where-Object { `$_.DisplayName -match 'Natural' } | Select-Object -First 1
    if (-not `$voice) { `$voice = `$synth.AllVoices | Where-Object { `$_.DisplayName -match 'Online' } | Select-Object -First 1 }
    if (-not `$voice) { `$voice = `$synth.AllVoices | Where-Object { `$_.Language -like 'en*' } | Select-Object -First 1 }
    if (`$voice) { `$synth.Voice = `$voice }

    `$stream = Invoke-Await `$synth.SynthesizeTextToStreamAsync(`$text) ([Windows.Media.SpeechSynthesis.SpeechSynthesisStream])
    `$size = `$stream.Size
    `$inputStream = `$stream.GetInputStreamAt(0)
    `$reader = New-Object Windows.Storage.Streams.DataReader `$inputStream
    Invoke-Await `$reader.LoadAsync([uint32]`$size) ([uint32]) | Out-Null
    `$buffer = New-Object byte[] `$size
    `$reader.ReadBytes(`$buffer)

    `$wavPath = Join-Path `$env:TEMP ("claude_speak_" + [guid]::NewGuid().ToString() + ".wav")
    [System.IO.File]::WriteAllBytes(`$wavPath, `$buffer)

    `$player = New-Object System.Media.SoundPlayer `$wavPath
    `$player.PlaySync()
    Remove-Item -LiteralPath `$wavPath -ErrorAction SilentlyContinue
    `$spoken = `$true
} catch { }

# ---- Fallback: legacy SAPI ----
if (-not `$spoken) {
    try {
        Add-Type -AssemblyName System.Speech
        `$s = New-Object System.Speech.Synthesis.SpeechSynthesizer
        try {
            `$best = `$s.GetInstalledVoices() | Where-Object { `$_.Enabled -and `$_.VoiceInfo.Culture.Name -like 'en*' } | Select-Object -First 1
            if (`$best) { `$s.SelectVoice(`$best.VoiceInfo.Name) }
        } catch { }
        `$s.Rate = 0
        `$s.Speak(`$text)
    } catch { }
}

Remove-Item -LiteralPath '$tmpfile' -ErrorAction SilentlyContinue
"@

$proc = Start-Process -FilePath 'powershell' `
    -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-Command',$childScript `
    -WindowStyle Hidden -PassThru
if ($proc) { $proc.Id | Set-Content -LiteralPath $lockfile }
exit 0
