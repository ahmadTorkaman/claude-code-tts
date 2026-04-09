# claude-code-tts

Text-to-speech for [Claude Code](https://claude.com/claude-code) on Windows. Every time Claude finishes a turn in your terminal, its response is read out loud — stripped of code blocks, file paths, and markdown noise, using the best voice your machine has installed.

Comes with two global hotkeys: **Ctrl+Alt+S** to shush mid-sentence, **Ctrl+Alt+R** to re-read the last message.

## Why

Claude Code's responses are often long enough that reading them takes real eye-time. If you're bouncing between the terminal and another window — waiting on a build, watching logs, reading docs — it's nice to just *hear* what Claude said.

This is a tiny, dependency-free hook: three PowerShell scripts, one settings merge, two Start Menu shortcuts. No Python, no Node, no network calls. Uses Windows' built-in speech engines.

## Requirements

- Windows 10 or Windows 11
- [Claude Code](https://claude.com/claude-code) installed
- Windows PowerShell (5.1, ships with Windows)

## Install

```powershell
git clone https://github.com/YOUR-USERNAME/claude-code-tts.git
cd claude-code-tts
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

The installer will:

1. Copy `speak.ps1`, `shush.ps1`, and `reread.ps1` to `~/.claude/scripts/`
2. Register a `Stop` hook in `~/.claude/settings.json` (preserves any existing config)
3. Install `/shush` and `/reread` slash commands to `~/.claude/commands/`
4. Create Start Menu shortcuts with global hotkeys **Ctrl+Alt+S** and **Ctrl+Alt+R**

After installing, **restart any running Claude Code sessions**. The first time the hook fires, Claude Code will prompt you to approve the command — accept it via `/hooks`.

## Uninstall

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
```

## How it works

- **`speak.ps1`** is registered as a Claude Code `Stop` hook. When a turn ends, Claude Code pipes a JSON payload into the script containing the path to the session transcript. The script:
  1. Reads the last assistant message from the transcript.
  2. Strips fenced code blocks, inline code, markdown links, URLs, file paths, bullet markers, headings, and emphasis, while preserving paragraph breaks as natural pauses.
  3. Tries the modern `Windows.Media.SpeechSynthesis` WinRT API first, which can use **Neural/Natural voices** if you have them installed. Falls back to legacy SAPI if WinRT fails.
  4. Spawns the actual speaker as a hidden background process and saves its PID to a lockfile so it can be killed later.

- **`shush.ps1`** reads the lockfile and kills the background speaker. Also sweeps any stray speech processes as a safety net.

- **`reread.ps1`** finds the most recently modified `.jsonl` transcript under `~/.claude/projects/`, synthesizes a fake hook payload, and pipes it into `speak.ps1`. Because `speak.ps1` always kills the previous speaker before starting, hitting Ctrl+Alt+R mid-sentence also acts as a restart.

- **Hotkeys** are ordinary Windows `.lnk` files in the Start Menu folder with the `Hotkey` property set. Windows takes care of the global key capture — no background daemon, no AutoHotkey, no elevated permissions.

## Getting better voices

The default Windows voices (David, Zira) sound robotic. The **Natural** voices sound genuinely good — closer to what you'd hear from a phone assistant or an audiobook app.

To install them:

1. Open **Settings → Time & Language → Speech**
2. Under "Manage voices", click **Add voices**
3. Look for voices ending in **"(Natural)"** — e.g. *Microsoft Aria (Natural)*, *Microsoft Jenny (Natural)*, *Microsoft Guy (Natural)*
4. Install one or more

`speak.ps1` automatically prefers Natural voices over regular ones, so once installed you don't need to reconfigure anything.

## Customizing

### Change the voice

Edit `~/.claude/scripts/speak.ps1`, find the block that begins `# Voice preference`, and hardcode a voice name:

```powershell
$voice = $synth.AllVoices | Where-Object { $_.DisplayName -like '*Jenny*' } | Select-Object -First 1
```

### Change the speech rate

In the SAPI fallback section, change `$s.Rate = 0` (valid range: -10 slowest, +10 fastest). For the WinRT path, use `$synth.Options.SpeakingRate = 1.2` (1.0 is normal).

### Change the hotkeys

Right-click the `.lnk` files in `%APPDATA%\Microsoft\Windows\Start Menu\Programs\` (*Shush Claude*, *Reread Claude*) → Properties → change the "Shortcut key" field.

Or edit `install.ps1` and re-run it.

### Scope the hook to a single project

If you only want TTS on one project, move the `hooks` block out of `~/.claude/settings.json` and into `<project>/.claude/settings.local.json`.

## Files

```
claude-code-tts/
├── README.md
├── LICENSE
├── install.ps1
├── uninstall.ps1
└── scripts/
    ├── speak.ps1    # the Stop-hook reader
    ├── shush.ps1    # stops speech
    └── reread.ps1   # re-reads the last message
```

## License

MIT — see [LICENSE](LICENSE).
