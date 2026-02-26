<p align="center">
  <img src="icon.svg" width="96" height="96" alt="Speak11 icon">
</p>

<h1 align="center">Speak11</h1>

<p align="center">
  Select text → press <kbd>⌥</kbd><kbd>⇧</kbd><kbd>/</kbd> → hear it read aloud (TTS).<br>
  Press <kbd>⌥</kbd><kbd>⇧</kbd><kbd>.</kbd> → speak → press again → transcribed text is pasted (STT).<br>
  Uses the <a href="https://elevenlabs.io">ElevenLabs</a> TTS &amp; STT APIs. Requires a free API key.
</p>

<p align="center">
  Forked from <a href="https://github.com/smcantab/speak11">smcantab/speak11</a> by <a href="https://github.com/smcantab">Stefano Martiniani</a>.<br>
  This fork adds speech-to-text (STT) support using ElevenLabs Scribe v2.
</p>

<p align="center">
  <a href="https://unlicense.org"><img src="https://img.shields.io/badge/license-Unlicense-green" alt="License: Unlicense"></a>
  <img src="https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey" alt="macOS 13+">
</p>

---

## Requirements

- macOS Ventura (13) or later
- A free [ElevenLabs account](https://elevenlabs.io) and API key
- `curl` and `afplay` — both ship with macOS, nothing to install

## Installation

1. [Download the repository](../../archive/refs/heads/main.zip) and unzip it
2. Double-click **`install.command`**
3. Click **Continue**, paste your ElevenLabs API key, click **Install**
4. Click **Install** when prompted about the settings app — this adds the menu bar icon and registers `⌥⇧/` (TTS) and `⌥⇧.` (STT) as global hotkeys

> **Getting your API key:** sign in at [elevenlabs.io](https://elevenlabs.io) → click your profile icon → **Profile + API Key** → copy the key.

### First use

Once installed, the **waveform icon** appears in your menu bar. On first launch the app will ask for Accessibility and Microphone permissions — grant both.

- **TTS:** Select any text in any app → press `⌥⇧/` → audio plays. Press again to stop.
- **STT:** Press `⌥⇧.` → mic icon appears, speak → press `⌥⇧.` again → text is transcribed, copied to clipboard, and auto-pasted.

The waveform icon pulses while audio is being generated/played, and switches to a mic icon during recording.

Your API key is stored in your macOS Keychain — never written to a file.

## Settings

Click the **waveform icon** in the menu bar to change:

| Setting | Options |
|---------|---------|
| **Voice** | Popular presets or a custom voice ID |
| **Model** | v3 · Flash v2.5 · Turbo v2.5 · Multilingual v2 |
| **Speed** | 0.7× to 1.2× |
| **Stability** | 0.0 (expressive) to 1.0 (steady) — controls pitch and pacing variation |
| **Similarity** | 0.0 (low) to 1.0 (high) — how closely output matches the original voice |
| **Style** | 0.0 (none) to 1.0 (max) — amplifies the voice's characteristic delivery; adds latency |
| **Speaker Boost** | On / Off — subtle enhancement to voice similarity |
| **STT Language** | Auto-detect · English · Korean · Japanese · Chinese · Spanish · French · German |
| **STT Model** | Scribe v2 (latest) · Scribe v1 |
| **API Key** | Set or update your ElevenLabs API key (stored in Keychain) |

Settings take effect immediately — no restart needed.

### Built-in voices

| Name | Style |
|------|-------|
| Lily | British, raspy |
| Alice | British, confident |
| Rachel | Calm |
| Adam | Deep |
| Domi | Strong |
| Josh | Young, deep |
| Sam | Raspy |

You can also enter any voice ID from the [ElevenLabs Voice Library](https://elevenlabs.io/voice-library) via **Voice → Custom voice ID…** in the menu.

## Uninstall

Double-click **`uninstall.command`** — it removes everything including the Accessibility permission, login item, API key, and app bundle.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `⌥⇧/` or `⌥⇧.` does nothing | Grant Accessibility permission when prompted, or check System Settings → Privacy & Security → Accessibility |
| `⌥⇧.` no audio recorded | Grant Microphone permission: System Settings → Privacy & Security → Microphone |
| Waveform icon not in menu bar | Open `~/Applications/Speak11 Settings.app` manually, or re-run `install.command` |
| HTTP 401 | API key is wrong or expired — run `install.command` again |
| HTTP 429 | Monthly character quota exceeded — check usage at [elevenlabs.io](https://elevenlabs.io) |
| "python3 not found" | Run `xcode-select --install` in Terminal |

## Cost

ElevenLabs' free tier includes a monthly character allowance — usually sufficient for casual read-aloud use. Paid plans start at $5/month. See [elevenlabs.io/pricing](https://elevenlabs.io/pricing).

## License

[Unlicense](LICENSE) — public domain. Originally created by [Stefano Martiniani](https://github.com/smcantab). STT support added by [s-choung](https://github.com/s-choung).

---

<details>
<summary><strong>Advanced</strong></summary>

### Config file

Settings are saved to `~/.config/speak11/config`. You can edit this file directly:

```bash
VOICE_ID="pFZP5JQG7iQjIQuC4Bku"
MODEL_ID="eleven_flash_v2_5"
STABILITY="0.50"
SIMILARITY_BOOST="0.75"
STYLE="0.00"
USE_SPEAKER_BOOST="true"
SPEED="1.00"
STT_MODEL_ID="scribe_v2"
STT_LANGUAGE=""              # empty = auto-detect
```

### Environment variables

Environment variables take highest priority and override both the config file and the settings app:

```bash
export ELEVENLABS_API_KEY="your-api-key"       # overrides Keychain
export ELEVENLABS_VOICE_ID="your-voice-id"
export ELEVENLABS_MODEL_ID="eleven_multilingual_v2"
```

### Voice IDs

| Name | ID |
|------|----|
| Lily | `pFZP5JQG7iQjIQuC4Bku` |
| Alice | `Xb7hH8MSUJpSbSDYk0k2` |
| Rachel | `21m00Tcm4TlvDq8ikWAM` |
| Adam | `pNInz6obpgDQGcFmaJgB` |
| Domi | `AZnzlk1XvdvUeBnXmlld` |
| Josh | `TxGEqnHWrfWFTfGW9XjX` |
| Sam | `yoZ06aMxZJJ28mfd3POQ` |

### Accessibility permission

The global hotkey requires Accessibility access. The app prompts for this on first launch, but if you need to grant it manually:

**System Settings → Privacy & Security → Accessibility** → enable **Speak11 Settings**

The hotkey activates automatically once access is granted.

### Electron apps (Beeper, Slack, VS Code, etc.)

Electron apps intercept keyboard shortcuts before macOS Services sees them. The settings app solves this by registering `⌥⇧/` as a **global hotkey** via CoreGraphics — it works at the system level and cannot be blocked by any app.

The settings app simulates `⌘C` via CGEvent to copy the current selection before calling the TTS script, so the hotkey works everywhere — including apps that don't support macOS Services.

### Optional: Services shortcut

The installer also creates a macOS Services action you can bind to any shortcut. This is optional — `⌥⇧/` already works everywhere — but useful if you prefer a different key combination.

1. System Settings → **Keyboard → Keyboard Shortcuts → Services → Text**
2. Find **Speak Selection** and assign a shortcut — e.g. `⌃⌥S`

> **Speak Selection** not in the list? Log out and back in, or trigger via right-click → **Services**.

### Updating

Pull the latest changes — the symlink means `~/.local/bin/speak.sh` always reflects the current repo file, so no extra steps needed.

To update your API key, run `install.command` again — or update it directly:

```bash
security add-generic-password \
  -a "speak11" \
  -s "speak11-api-key" \
  -w "your-new-key" \
  -U
```

</details>
