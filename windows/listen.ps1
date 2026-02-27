#Requires -Version 5.1
<#
.SYNOPSIS
    Speak11 Speech-to-Text for Windows.
.DESCRIPTION
    Sends a recorded audio file to the ElevenLabs Speech-to-Text API and copies
    the transcription to the clipboard.  This is the Windows PowerShell port of
    the macOS listen.sh script.
.PARAMETER AudioFile
    Path to the audio file to transcribe.
.NOTES
    Requirements: PowerShell 5.1+, curl.exe (ships with Windows 10 1803+)
    Setup:       Store your API key in Windows Credential Manager with
                 Target = "speak11-api-key".
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$AudioFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Windows Credential Manager P/Invoke ──────────────────────────────────
# Inline type definition so the script is self-contained.  PowerShell skips
# Add-Type when the type is already loaded (e.g. speak.ps1 ran first).
if (-not ([System.Management.Automation.PSTypeName]'Speak11.CredManager').Type) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;

namespace Speak11 {
    public static class CredManager {
        [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern bool CredReadW(
            string target, int type, int reservedFlag, out IntPtr credential);

        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern bool CredFree(IntPtr buffer);

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct CREDENTIAL {
            public int    Flags;
            public int    Type;
            public string TargetName;
            public string Comment;
            public long   LastWritten;
            public int    CredentialBlobSize;
            public IntPtr CredentialBlob;
            public int    Persist;
            public int    AttributeCount;
            public IntPtr Attributes;
            public string TargetAlias;
            public string UserName;
        }

        /// <summary>
        /// Read a Generic credential from Windows Credential Manager.
        /// Returns the password string, or null if the credential was not found.
        /// </summary>
        public static string Read(string target) {
            IntPtr credPtr;
            // Type 1 = CRED_TYPE_GENERIC
            if (!CredReadW(target, 1, 0, out credPtr))
                return null;
            try {
                CREDENTIAL cred = (CREDENTIAL)Marshal.PtrToStructure(
                    credPtr, typeof(CREDENTIAL));
                if (cred.CredentialBlob == IntPtr.Zero || cred.CredentialBlobSize == 0)
                    return string.Empty;
                return Marshal.PtrToStringUni(
                    cred.CredentialBlob, cred.CredentialBlobSize / 2);
            } finally {
                CredFree(credPtr);
            }
        }
    }
}
'@
}

# ── Helper: show an error dialog and exit ─────────────────────────────────
function Show-ErrorDialog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$Title = 'Speak11',
        [int]$ExitCode = 1
    )
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        $Message, $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    ) | Out-Null
    exit $ExitCode
}

function Show-InfoDialog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$Title = 'Speak11',
        [int]$ExitCode = 0
    )
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        $Message, $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
    exit $ExitCode
}

# ── Configuration ─────────────────────────────────────────────────────────
# Priority: environment variable > config file > Credential Manager > default

# 1. Try environment variable, then Credential Manager
$ApiKey = $env:ELEVENLABS_API_KEY
if (-not $ApiKey) {
    $ApiKey = [Speak11.CredManager]::Read('speak11-api-key')
}

# 2. Load config file (key=value, same format as the macOS version)
$ConfigPath = Join-Path $env:USERPROFILE '.config\speak11\config'
$ConfigValues = @{}
if (Test-Path -LiteralPath $ConfigPath -PathType Leaf) {
    Get-Content -LiteralPath $ConfigPath -ErrorAction SilentlyContinue |
        ForEach-Object {
            $line = $_.Trim()
            # Skip comments and blank lines
            if ($line -and -not $line.StartsWith('#')) {
                $eqIdx = $line.IndexOf('=')
                if ($eqIdx -gt 0) {
                    $key   = $line.Substring(0, $eqIdx).Trim().Trim('"', "'")
                    $value = $line.Substring($eqIdx + 1).Trim().Trim('"', "'")
                    $ConfigValues[$key] = $value
                }
            }
        }
}

# 3. Resolve final values with correct priority:
#    env var > config file value > hardcoded default
$SttModelId  = if ($env:ELEVENLABS_STT_MODEL_ID)  { $env:ELEVENLABS_STT_MODEL_ID }
               elseif ($ConfigValues['STT_MODEL_ID'])  { $ConfigValues['STT_MODEL_ID'] }
               else { 'scribe_v2' }

$SttLanguage = if ($env:ELEVENLABS_STT_LANGUAGE)   { $env:ELEVENLABS_STT_LANGUAGE }
               elseif ($ConfigValues.ContainsKey('STT_LANGUAGE')) { $ConfigValues['STT_LANGUAGE'] }
               else { '' }

# ── Preflight checks ─────────────────────────────────────────────────────
if (-not $AudioFile -or -not (Test-Path -LiteralPath $AudioFile -PathType Leaf)) {
    Show-ErrorDialog -Message 'No audio file provided or file not found.'
}

if (-not $ApiKey) {
    Show-ErrorDialog -Message (
        "ElevenLabs API key not found.`n`n" +
        "Store your key in Windows Credential Manager with Target = `"speak11-api-key`", " +
        "or set the ELEVENLABS_API_KEY environment variable."
    )
}

# ── Temp file for the API response ───────────────────────────────────────
$TmpResponse = [System.IO.Path]::GetTempFileName()
# Rename .tmp to .json so downstream tools (and us) can identify the content type
$TmpResponseJson = [System.IO.Path]::ChangeExtension($TmpResponse, '.json')
Rename-Item -LiteralPath $TmpResponse -NewName ([System.IO.Path]::GetFileName($TmpResponseJson)) -Force
$TmpResponse = $TmpResponseJson

try {
    # ── Call ElevenLabs Speech-to-Text API ────────────────────────────
    $curlArgs = @(
        '-s', '-w', '%{http_code}'
        '--max-time', '60'
        '-o', $TmpResponse
        '-X', 'POST'
        'https://api.elevenlabs.io/v1/speech-to-text'
        '-H', "xi-api-key: $ApiKey"
        '-F', "model_id=$SttModelId"
        '-F', "file=@$AudioFile"
    )

    # Only add language_code when explicitly set (empty = auto-detect)
    if ($SttLanguage) {
        $curlArgs += '-F'
        $curlArgs += "language_code=$SttLanguage"
    }

    # Use curl.exe explicitly to avoid PowerShell's Invoke-WebRequest alias
    $HttpCode = & curl.exe @curlArgs 2>$null

    if ($LASTEXITCODE -ne 0) {
        Show-ErrorDialog -Message (
            "curl failed with exit code $LASTEXITCODE.`n`n" +
            "Make sure curl.exe is available (Windows 10 1803+ ships with it)."
        )
    }

    # ── Handle HTTP errors ────────────────────────────────────────────
    if ($HttpCode -ne '200') {
        $SafeError = 'Unknown error'
        if (Test-Path -LiteralPath $TmpResponse -PathType Leaf) {
            $raw = Get-Content -LiteralPath $TmpResponse -Raw -ErrorAction SilentlyContinue
            if ($raw) {
                # Truncate to 300 chars and strip control characters
                if ($raw.Length -gt 300) { $raw = $raw.Substring(0, 300) }
                $SafeError = $raw -replace '[\x00-\x1F]', ''
            }
        }
        Show-ErrorDialog -Message "ElevenLabs STT API error (HTTP $HttpCode):`n`n$SafeError"
    }

    # ── Extract text from JSON response ──────────────────────────────
    $ResponseJson = Get-Content -LiteralPath $TmpResponse -Raw -ErrorAction Stop
    $ResponseObj  = $ResponseJson | ConvertFrom-Json

    $Text = $ResponseObj.text

    if (-not $Text -or -not $Text.Trim()) {
        Show-InfoDialog -Message 'No speech detected in the recording.'
    }

    # ── Copy to clipboard ────────────────────────────────────────────
    Set-Clipboard -Value $Text

} finally {
    # ── Cleanup ──────────────────────────────────────────────────────
    if (Test-Path -LiteralPath $TmpResponse -PathType Leaf) {
        Remove-Item -LiteralPath $TmpResponse -Force -ErrorAction SilentlyContinue
    }
}
