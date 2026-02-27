#Requires -Version 5.1
<#
.SYNOPSIS
    install.ps1 — Speak11 installer for Windows
    Run this script to set up Speak11 on your system.

.DESCRIPTION
    Windows PowerShell port of install.command (macOS).
    Stores the ElevenLabs API key in Windows Credential Manager,
    copies scripts to %LOCALAPPDATA%\Speak11\, optionally builds and
    installs the settings tray app, creates a Start Menu shortcut,
    and writes the default configuration file.

.NOTES
    Requirements: PowerShell 5.1+, Windows 10+
    Run: Right-click > Run with PowerShell, or execute from a terminal.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Paths ─────────────────────────────────────────────────────────
$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Definition
$InstallDir  = Join-Path $env:LOCALAPPDATA 'Speak11'
$ConfigDir   = Join-Path $env:USERPROFILE '.config\speak11'
$ConfigFile  = Join-Path $ConfigDir 'config'
$StartMenu   = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
$ShortcutPath = Join-Path $StartMenu 'Speak11 Settings.lnk'
$SettingsExe = Join-Path $InstallDir 'Speak11Settings.exe'
$SettingsProjectDir = Join-Path $ScriptDir 'Speak11Settings'
$RunKey      = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'

# ── Credential Manager P/Invoke ──────────────────────────────────
if (-not ([System.Management.Automation.PSTypeName]'CredManager').Type) {
    Add-Type -TypeDefinition @"
    using System;
    using System.Runtime.InteropServices;
    using System.Text;
    public class CredManager {
        [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        private static extern bool CredRead(string target, int type, int flags, out IntPtr cred);
        [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        private static extern bool CredWrite(ref CREDENTIAL cred, int flags);
        [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        private static extern bool CredDelete(string target, int type, int flags);
        [DllImport("advapi32.dll")]
        private static extern void CredFree(IntPtr cred);

        [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
        private struct CREDENTIAL {
            public int Flags; public int Type; public string TargetName; public string Comment;
            public long LastWritten; public int CredentialBlobSize; public IntPtr CredentialBlob;
            public int Persist; public int AttributeCount; public IntPtr Attributes;
            public string TargetAlias; public string UserName;
        }

        public static string Get(string target) {
            IntPtr ptr;
            if (!CredRead(target, 1, 0, out ptr)) return null;
            var cred = Marshal.PtrToStructure<CREDENTIAL>(ptr);
            string pass = Marshal.PtrToStringUni(cred.CredentialBlob, cred.CredentialBlobSize / 2);
            CredFree(ptr);
            return pass;
        }

        public static void Set(string target, string user, string pass) {
            var bytes = Encoding.Unicode.GetBytes(pass);
            var cred = new CREDENTIAL {
                Type = 1, TargetName = target, UserName = user,
                CredentialBlobSize = bytes.Length,
                CredentialBlob = Marshal.AllocHGlobal(bytes.Length),
                Persist = 2
            };
            Marshal.Copy(bytes, 0, cred.CredentialBlob, bytes.Length);
            CredWrite(ref cred, 0);
            Marshal.FreeHGlobal(cred.CredentialBlob);
        }

        public static void Delete(string target) { CredDelete(target, 1, 0); }
    }
"@
}

# ── GUI helpers ───────────────────────────────────────────────────
Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue

function Show-MessageBox {
    param(
        [string]$Message,
        [string]$Title = 'Speak11',
        [System.Windows.Forms.MessageBoxButtons]$Buttons = 'OK',
        [System.Windows.Forms.MessageBoxIcon]$Icon = 'Information'
    )
    return [System.Windows.Forms.MessageBox]::Show($Message, $Title, $Buttons, $Icon)
}

function Show-ApiKeyPrompt {
    <#
    .SYNOPSIS
        Shows a form with a masked text field for the API key.
    #>
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Speak11'
    $form.Size = New-Object System.Drawing.Size(460, 200)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.TopMost = $true

    $label = New-Object System.Windows.Forms.Label
    $label.Text = 'Paste your ElevenLabs API key:'
    $label.Location = New-Object System.Drawing.Point(20, 20)
    $label.AutoSize = $true
    $form.Controls.Add($label)

    $textBox = New-Object System.Windows.Forms.TextBox
    $textBox.Location = New-Object System.Drawing.Point(20, 50)
    $textBox.Size = New-Object System.Drawing.Size(400, 26)
    $textBox.UseSystemPasswordChar = $true
    $textBox.Font = New-Object System.Drawing.Font('Consolas', 10)
    $form.Controls.Add($textBox)

    $linkLabel = New-Object System.Windows.Forms.LinkLabel
    $linkLabel.Text = 'Get a free API key at elevenlabs.io'
    $linkLabel.Location = New-Object System.Drawing.Point(20, 85)
    $linkLabel.AutoSize = $true
    $linkLabel.add_LinkClicked({
        Start-Process 'https://elevenlabs.io/app/developers/api-keys'
    })
    $form.Controls.Add($linkLabel)

    $installBtn = New-Object System.Windows.Forms.Button
    $installBtn.Text = 'Install'
    $installBtn.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $installBtn.Location = New-Object System.Drawing.Point(320, 120)
    $installBtn.Size = New-Object System.Drawing.Size(100, 30)
    $form.AcceptButton = $installBtn
    $form.Controls.Add($installBtn)

    $cancelBtn = New-Object System.Windows.Forms.Button
    $cancelBtn.Text = 'Cancel'
    $cancelBtn.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $cancelBtn.Location = New-Object System.Drawing.Point(210, 120)
    $cancelBtn.Size = New-Object System.Drawing.Size(100, 30)
    $form.CancelButton = $cancelBtn
    $form.Controls.Add($cancelBtn)

    $result = $form.ShowDialog()
    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        return $textBox.Text.Trim()
    }
    return $null
}

# ── Progress helpers ──────────────────────────────────────────────
$script:StepNumber = 0

function Write-Header {
    Clear-Host
    Write-Host ''
    Write-Host '  Speak11' -ForegroundColor White -NoNewline
    Write-Host ' — Installing' -ForegroundColor DarkGray
    Write-Host '  ─────────────────────────' -ForegroundColor DarkGray
    Write-Host ''
}

function Write-Step {
    param([string]$Message)
    $script:StepNumber++
    Write-Host "  $([char]0x2713) " -ForegroundColor Green -NoNewline
    Write-Host " $Message"
}

function Write-Busy {
    param([string]$Message)
    Write-Host "  * " -ForegroundColor Cyan -NoNewline
    Write-Host " $Message" -NoNewline
}

function Write-BusyDone {
    param([string]$Message)
    Write-Host "`r  $([char]0x2713) " -ForegroundColor Green -NoNewline
    Write-Host " $Message       "
}

function Write-Fail {
    param([string]$Message)
    Write-Host "`r  X " -ForegroundColor Red -NoNewline
    Write-Host " $Message       "
}

# ══════════════════════════════════════════════════════════════════
#  MAIN
# ══════════════════════════════════════════════════════════════════

# ── Welcome dialog ────────────────────────────────────────────────
$welcomeMsg = @"
Welcome to Speak11!

This installer will:
  - Store your API key securely in Credential Manager
  - Install the speak and listen scripts
  - Optionally build and install the settings tray app
  - Create a Start Menu shortcut
  - Write a default configuration file

You will need a free ElevenLabs API key.
Get one at elevenlabs.io/app/developers/api-keys
"@
$welcomeResult = Show-MessageBox -Message $welcomeMsg -Title 'Speak11' `
    -Buttons OKCancel -Icon Information
if ($welcomeResult -eq [System.Windows.Forms.DialogResult]::Cancel) {
    exit 0
}

# ── Prompt for API key ────────────────────────────────────────────
$ApiKey = Show-ApiKeyPrompt
if (-not $ApiKey) {
    Show-MessageBox -Message 'No API key entered. Installation cancelled.' `
        -Title 'Speak11' -Icon Warning | Out-Null
    exit 1
}

# ── Ask about settings app before starting work ──────────────────
$settingsResult = Show-MessageBox `
    -Message ("Install the Speak11 Settings tray app?`n`n" +
              "Adds a waveform icon to your system tray to change voice, model, and speed without editing any files.") `
    -Title 'Speak11' -Buttons YesNo -Icon Question

# ── Show progress in console ─────────────────────────────────────
Write-Header

# ── Step 1: Store API key in Credential Manager ──────────────────
[CredManager]::Set('speak11-api-key', 'speak11', $ApiKey)
Write-Step 'API key stored in Credential Manager'

# ── Step 2: Copy scripts to install directory ─────────────────────
if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

$speakSrc  = Join-Path $ScriptDir 'speak.ps1'
$listenSrc = Join-Path $ScriptDir 'listen.ps1'

if (Test-Path $speakSrc)  { Copy-Item -LiteralPath $speakSrc  -Destination $InstallDir -Force }
if (Test-Path $listenSrc) { Copy-Item -LiteralPath $listenSrc -Destination $InstallDir -Force }
Write-Step "Scripts copied to $InstallDir"

# ── Step 3: Build and install settings app ────────────────────────
$settingsInstalled = $false

if ($settingsResult -eq [System.Windows.Forms.DialogResult]::Yes) {
    $csprojFile = Join-Path $SettingsProjectDir 'Speak11Settings.csproj'

    if (Test-Path $csprojFile) {
        # Try to build with dotnet SDK
        $dotnetCmd = Get-Command 'dotnet' -ErrorAction SilentlyContinue

        if ($dotnetCmd) {
            Write-Busy 'Building settings app (this may take a moment)...'

            $buildOutput = Join-Path $SettingsProjectDir 'bin\Release\net8.0-windows'
            $buildResult = & dotnet build $csprojFile -c Release --nologo -v q 2>&1
            $buildExitCode = $LASTEXITCODE

            if ($buildExitCode -eq 0 -and (Test-Path (Join-Path $buildOutput 'Speak11Settings.exe'))) {
                Write-BusyDone 'Settings app compiled'

                # Copy entire build output to install directory
                $buildFiles = Get-ChildItem -Path $buildOutput -File
                foreach ($file in $buildFiles) {
                    Copy-Item -LiteralPath $file.FullName -Destination $InstallDir -Force
                }
                $settingsInstalled = $true
                Write-Step "Settings app installed to $InstallDir"
            } else {
                Write-Fail 'Compilation failed'
                Write-Host ''
                Write-Host '    Build output:' -ForegroundColor DarkGray
                $buildResult | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
                Write-Host ''

                # Fall through to try pre-built binary
                $dotnetCmd = $null
            }
        }

        if (-not $dotnetCmd -and -not $settingsInstalled) {
            # Try to find a pre-built binary in common locations
            $preBuildPaths = @(
                (Join-Path $SettingsProjectDir 'bin\Release\net8.0-windows\Speak11Settings.exe'),
                (Join-Path $SettingsProjectDir 'bin\Debug\net8.0-windows\Speak11Settings.exe'),
                (Join-Path $ScriptDir 'Speak11Settings.exe')
            )

            $preBuiltExe = $null
            foreach ($path in $preBuildPaths) {
                if (Test-Path $path) {
                    $preBuiltExe = $path
                    break
                }
            }

            if ($preBuiltExe) {
                # Copy the pre-built binary and its dependencies
                $preBuiltDir = Split-Path -Parent $preBuiltExe
                $preBuiltFiles = Get-ChildItem -Path $preBuiltDir -File
                foreach ($file in $preBuiltFiles) {
                    Copy-Item -LiteralPath $file.FullName -Destination $InstallDir -Force
                }
                $settingsInstalled = $true
                Write-Step 'Pre-built settings app installed'
            } else {
                Write-Fail 'Settings app not installed (dotnet SDK not found, no pre-built binary available)'
                Write-Host ''
                Write-Host '    To install the settings app later, install the .NET 8 SDK and re-run this script.' -ForegroundColor DarkGray
                Write-Host '    https://dotnet.microsoft.com/download' -ForegroundColor DarkGray
                Write-Host ''
            }
        }
    } else {
        Write-Fail 'Settings app project not found'
    }
}

# ── Step 4: Create Start Menu shortcut ────────────────────────────
if ($settingsInstalled -and (Test-Path $SettingsExe)) {
    try {
        $WshShell = New-Object -ComObject WScript.Shell
        $shortcut = $WshShell.CreateShortcut($ShortcutPath)
        $shortcut.TargetPath = $SettingsExe
        $shortcut.WorkingDirectory = $InstallDir
        $shortcut.Description = 'Speak11 Settings — ElevenLabs TTS configuration'
        $shortcut.Save()
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($WshShell) | Out-Null
        Write-Step 'Start Menu shortcut created'
    } catch {
        Write-Fail "Could not create Start Menu shortcut: $_"
    }
}

# ── Step 5: Optionally add to startup ────────────────────────────
if ($settingsInstalled -and (Test-Path $SettingsExe)) {
    $startupResult = Show-MessageBox `
        -Message 'Launch Speak11 Settings automatically at login?' `
        -Title 'Speak11' -Buttons YesNo -Icon Question

    if ($startupResult -eq [System.Windows.Forms.DialogResult]::Yes) {
        try {
            Set-ItemProperty -Path $RunKey -Name 'Speak11Settings' -Value "`"$SettingsExe`"" -Force
            Write-Step 'Added to startup (runs at login)'
        } catch {
            Write-Fail "Could not add to startup: $_"
        }
    }
}

# ── Step 6: Create default config ────────────────────────────────
if (-not (Test-Path $ConfigDir)) {
    New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
}

if (-not (Test-Path $ConfigFile)) {
    $defaultConfig = @'
VOICE_ID="pFZP5JQG7iQjIQuC4Bku"
MODEL_ID="eleven_flash_v2_5"
STABILITY="0.50"
SIMILARITY_BOOST="0.75"
STYLE="0.00"
USE_SPEAKER_BOOST="true"
SPEED="1.00"
STT_MODEL_ID="scribe_v2"
STT_LANGUAGE=""
'@
    Set-Content -Path $ConfigFile -Value $defaultConfig -Encoding UTF8 -Force
    Write-Step 'Default config created'
} else {
    Write-Step 'Existing config preserved'
}

# ── Done ──────────────────────────────────────────────────────────
Write-Host ''
Write-Host '  Installation complete.' -ForegroundColor Green
Write-Host ''

# Launch the settings app if it was installed
if ($settingsInstalled -and (Test-Path $SettingsExe)) {
    Start-Process -FilePath $SettingsExe -ErrorAction SilentlyContinue
}

# Completion message
if ($settingsInstalled) {
    $doneMsg = @"
Speak11 is installed!

The system tray icon lets you change voice, model, and speed.

Scripts are installed at:
  $InstallDir

To use from the command line:
  powershell -File "$InstallDir\speak.ps1"
  powershell -File "$InstallDir\listen.ps1" <audio_file>

Configure a global hotkey in the settings tray app, or use AutoHotkey / PowerToys to bind keys to the scripts.
"@
} else {
    $doneMsg = @"
Speak11 is installed!

Scripts are installed at:
  $InstallDir

To use from the command line:
  powershell -File "$InstallDir\speak.ps1"
  powershell -File "$InstallDir\listen.ps1" <audio_file>

Use AutoHotkey or PowerToys to bind a global hotkey to the scripts.
"@
}

Show-MessageBox -Message $doneMsg -Title 'Speak11' -Icon Information | Out-Null
