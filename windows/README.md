# Speak11 for Windows

Text-to-speech and speech-to-text for Windows using the [ElevenLabs](https://elevenlabs.io) API.
Select text in any app, press a hotkey, hear it spoken.

## Install

1. Install [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0)
2. Get a free [ElevenLabs API key](https://elevenlabs.io/app/developers/api-keys)
3. Run `install.ps1` in PowerShell:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
.\install.ps1
```

## Hotkeys

| Hotkey | Action |
|---|---|
| `Alt+Shift+/` | Speak selected text (press again to stop) |
| `Alt+Shift+.` | Record → transcribe → paste |

## Settings

Right-click the tray icon to change voice, model, speed, and more.

## Manual Build

```powershell
cd Speak11Settings
dotnet build -c Release
```

## Uninstall

```powershell
.\uninstall.ps1
```
