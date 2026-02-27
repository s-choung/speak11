#Requires -Version 5.1
<#
.SYNOPSIS
    speak.ps1 — Speak11 for Windows
    Select text in any app, press your hotkey, hear it spoken.

.DESCRIPTION
    Windows PowerShell port of speak.sh (macOS).
    Uses ElevenLabs TTS streaming API to speak selected text aloud.

.NOTES
    Requirements: curl (built into Windows 10+), PowerShell 5.1+
    Setup: Store your API key with install.ps1 or set ELEVENLABS_API_KEY.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Credential Manager via P/Invoke ──────────────────────────────
# Read the API key from Windows Credential Manager (analogous to macOS Keychain).
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class Speak11CredManager {
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredRead(
        string target, int type, int flags, out IntPtr credential);

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern void CredFree(IntPtr credential);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct CREDENTIAL {
        public int Flags;
        public int Type;
        public string TargetName;
        public string Comment;
        public long LastWritten;
        public int CredentialBlobSize;
        public IntPtr CredentialBlob;
        public int Persist;
        public int AttributeCount;
        public IntPtr Attributes;
        public string TargetAlias;
        public string UserName;
    }

    /// <summary>
    /// Retrieve a generic credential's password by target name.
    /// Returns null if the credential does not exist.
    /// </summary>
    public static string Get(string target) {
        IntPtr ptr;
        if (!CredRead(target, 1 /* CRED_TYPE_GENERIC */, 0, out ptr))
            return null;
        try {
            var cred = Marshal.PtrToStructure<CREDENTIAL>(ptr);
            if (cred.CredentialBlobSize == 0 || cred.CredentialBlob == IntPtr.Zero)
                return null;
            return Marshal.PtrToStringUni(cred.CredentialBlob, cred.CredentialBlobSize / 2);
        } finally {
            CredFree(ptr);
        }
    }
}
"@ -ErrorAction SilentlyContinue   # Suppress if already loaded in same session

# ── Configuration ────────────────────────────────────────────────
# Get your API key from: https://elevenlabs.io/app/developers/api-keys
if ($env:ELEVENLABS_API_KEY) {
    $ApiKey = $env:ELEVENLABS_API_KEY
} else {
    $ApiKey = [Speak11CredManager]::Get("speak11-api-key")
}

# Load settings written by the settings app.
# Priority: environment variable > config file > hardcoded default.
$ConfigPath = Join-Path $env:USERPROFILE ".config\speak11\config"
$ConfigValues = @{}
if (Test-Path $ConfigPath) {
    Get-Content $ConfigPath | ForEach-Object {
        $line = $_.Trim()
        # Skip blank lines and comments
        if ($line -and -not $line.StartsWith('#')) {
            # Parse KEY=VALUE (with optional quotes around the value)
            if ($line -match '^([A-Za-z_][A-Za-z0-9_]*)=(.*)$') {
                $key = $Matches[1]
                $val = $Matches[2].Trim('"', "'", ' ')
                $ConfigValues[$key] = $val
            }
        }
    }
}

# Helper: resolve a setting by precedence (env var > config file > default).
function Get-Setting {
    param(
        [string]$EnvName,
        [string]$ConfigName,
        [string]$Default
    )
    $envVal = [Environment]::GetEnvironmentVariable($EnvName)
    if ($envVal) { return $envVal }
    if ($ConfigValues.ContainsKey($ConfigName) -and $ConfigValues[$ConfigName]) {
        return $ConfigValues[$ConfigName]
    }
    return $Default
}

# Voice ID — edit via the settings app, or override with an env var.
# Browse voices at: https://elevenlabs.io/voice-library
$VoiceId         = Get-Setting 'ELEVENLABS_VOICE_ID' 'VOICE_ID'         'pFZP5JQG7iQjIQuC4Bku'
# Model — Flash v2.5 for lowest latency, Multilingual v2 for best quality
$ModelId         = Get-Setting 'ELEVENLABS_MODEL_ID' 'MODEL_ID'         'eleven_flash_v2_5'
# Voice settings — edit via the settings app or set env vars directly
$Stability       = Get-Setting 'STABILITY'           'STABILITY'        '0.5'
$SimilarityBoost = Get-Setting 'SIMILARITY_BOOST'    'SIMILARITY_BOOST' '0.75'
$Style           = Get-Setting 'STYLE'               'STYLE'            '0.0'
$UseSpeakerBoost = Get-Setting 'USE_SPEAKER_BOOST'   'USE_SPEAKER_BOOST' 'true'
$Speed           = Get-Setting 'SPEED'               'SPEED'            '1.0'

# ── Helper: show an error dialog ─────────────────────────────────
function Show-ErrorDialog {
    param([string]$Message)
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
    [System.Windows.Forms.MessageBox]::Show(
        $Message, "Speak11",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    ) | Out-Null
}

# ── Toggle: stop playback if already running ─────────────────────
$PidFile = Join-Path $env:TEMP "elevenlabs_tts.pid"
if (Test-Path $PidFile) {
    $oldPid = Get-Content $PidFile -ErrorAction SilentlyContinue
    if ($oldPid) {
        $proc = Get-Process -Id ([int]$oldPid) -ErrorAction SilentlyContinue
        if ($proc -and -not $proc.HasExited) {
            Stop-Process -Id ([int]$oldPid) -Force -ErrorAction SilentlyContinue
            Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
            exit 0
        }
    }
    # Stale PID, clean up and continue
    Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
}

# ── Read selected text ───────────────────────────────────────────
# Three cases:
#   1. Interactive (no pipeline): read clipboard as-is
#   2. Piped input: use that
#   3. Hotkey invocation (stdin is empty): simulate Ctrl+C to copy the
#      current selection, then read the clipboard.
$Text = $null

if ([Console]::IsInputRedirected) {
    # Reading from pipeline / stdin
    $Text = @($input) -join "`n"
    if (-not ($Text -and $Text.Trim())) {
        # stdin was empty — simulate Ctrl+C to grab the selection
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        [System.Windows.Forms.SendKeys]::SendWait("^c")
        Start-Sleep -Milliseconds 200
        $Text = Get-Clipboard -ErrorAction SilentlyContinue
    }
} else {
    $Text = Get-Clipboard -ErrorAction SilentlyContinue
}

# Exit silently if nothing was selected
if (-not ($Text -and $Text.Trim())) {
    exit 0
}

# ── Preflight checks ─────────────────────────────────────────────
if (-not $ApiKey) {
    Show-ErrorDialog ("ElevenLabs API key not found.`n`n" +
        "Run install.ps1 to store your key, or set the ELEVENLABS_API_KEY environment variable.")
    exit 1
}

# ── Temp file for audio ──────────────────────────────────────────
$TmpFile = Join-Path $env:TEMP ("elevenlabs_tts_{0}.mp3" -f [System.IO.Path]::GetRandomFileName())
$PlayProcess = $null

# ── Cleanup on exit ──────────────────────────────────────────────
# Register a script-block that runs when the PowerShell process exits.
$CleanupBlock = {
    Remove-Item $TmpFile -Force -ErrorAction SilentlyContinue
    Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
}
Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action $CleanupBlock -ErrorAction SilentlyContinue | Out-Null

# Also wrap the main body in try/finally for robust cleanup.
try {

# ── Escape text for JSON ─────────────────────────────────────────
# PowerShell's ConvertTo-Json handles all Unicode, control chars, etc.
$JsonText = $Text | ConvertTo-Json
if (-not $JsonText) {
    Show-ErrorDialog "Failed to encode the selected text as JSON."
    exit 1
}

# ── Build the request body ───────────────────────────────────────
# Construct as a PowerShell object and convert, ensuring proper JSON types.
$UseSpeakerBoostBool = ($UseSpeakerBoost -eq 'true')
$RequestBody = @{
    text           = $Text
    model_id       = $ModelId
    voice_settings = @{
        stability         = [double]$Stability
        similarity_boost  = [double]$SimilarityBoost
        style             = [double]$Style
        use_speaker_boost = $UseSpeakerBoostBool
        speed             = [double]$Speed
    }
} | ConvertTo-Json -Depth 4 -Compress

# ── Call ElevenLabs streaming API ─────────────────────────────────
$ApiUrl = "https://api.elevenlabs.io/v1/text-to-speech/$VoiceId/stream"

# Use curl (available on Windows 10+) for streaming download, consistent
# with the macOS version. Invoke-WebRequest buffers the full response
# and does not support streaming to file as cleanly.
$curlArgs = @(
    '-s',
    '-w', '%{http_code}',
    '--max-time', '30',
    '-o', $TmpFile,
    '-X', 'POST',
    $ApiUrl,
    '-H', "xi-api-key: $ApiKey",
    '-H', 'Content-Type: application/json',
    '-d', $RequestBody
)

$HttpCode = & curl.exe @curlArgs 2>$null
if ($LASTEXITCODE -ne 0 -and -not $HttpCode) {
    Show-ErrorDialog "Failed to contact ElevenLabs API. Check your internet connection."
    exit 1
}

# ── Handle errors ─────────────────────────────────────────────────
if ($HttpCode -ne '200') {
    $errorBody = ''
    if (Test-Path $TmpFile) {
        $errorBody = Get-Content $TmpFile -Raw -ErrorAction SilentlyContinue
        if ($errorBody.Length -gt 300) {
            $errorBody = $errorBody.Substring(0, 300)
        }
        # Strip control characters for safe display
        $errorBody = $errorBody -replace '[\x00-\x1F]', ''
    }
    if (-not $errorBody) { $errorBody = 'Unknown error' }
    Show-ErrorDialog "ElevenLabs API error (HTTP $HttpCode):`n`n$errorBody"
    exit 1
}

# Verify the response actually contains audio data before trying to play it
if (-not (Test-Path $TmpFile) -or (Get-Item $TmpFile).Length -eq 0) {
    Show-ErrorDialog "ElevenLabs returned an empty audio response."
    exit 1
}

# ── Play audio ────────────────────────────────────────────────────
# Use WPF MediaPlayer which supports MP3 natively.
Add-Type -AssemblyName PresentationCore

$player = New-Object System.Windows.Media.MediaPlayer

# We need a dispatcher frame to wait for async media events.
$mediaOpened = $false
$mediaEnded  = $false
$mediaFailed = $false

$player.add_MediaOpened({  $script:mediaOpened = $true })
$player.add_MediaEnded({   $script:mediaEnded  = $true })
$player.add_MediaFailed({  $script:mediaFailed = $true })

$resolvedPath = (Resolve-Path $TmpFile).Path
$player.Open([Uri]::new($resolvedPath))

# Write a PID file so a second invocation can stop playback.
# Use the current PowerShell process ID.
$currentPid = $PID
Set-Content -Path $PidFile -Value $currentPid -Force

$player.Play()

# Poll until playback completes, fails, or we're asked to stop.
# MediaPlayer is async; we spin-wait with short sleeps.
while (-not $mediaEnded -and -not $mediaFailed) {
    # If our PID file was removed, another instance asked us to stop
    if (-not (Test-Path $PidFile)) {
        $player.Stop()
        $player.Close()
        break
    }
    Start-Sleep -Milliseconds 100
}

$player.Close()

} finally {
    # ── Cleanup ───────────────────────────────────────────────────
    Remove-Item $TmpFile -Force -ErrorAction SilentlyContinue
    Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
}
