#Requires -Version 5.1
<#
.SYNOPSIS
    uninstall.ps1 — Speak11 uninstaller for Windows
    Completely removes Speak11 from your system.

.DESCRIPTION
    Windows PowerShell port of uninstall.command (macOS).
    Stops the settings app, removes scripts, shortcuts, startup entries,
    configuration files, and the API key from Credential Manager.

.NOTES
    Requirements: PowerShell 5.1+, Windows 10+
    Run: Right-click > Run with PowerShell, or execute from a terminal.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Paths ─────────────────────────────────────────────────────────
$InstallDir   = Join-Path $env:LOCALAPPDATA 'Speak11'
$ConfigDir    = Join-Path $env:USERPROFILE '.config\speak11'
$StartMenu    = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
$ShortcutPath = Join-Path $StartMenu 'Speak11 Settings.lnk'
$RunKey       = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$RunValueName = 'Speak11Settings'

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

function Show-MessageBox {
    param(
        [string]$Message,
        [string]$Title = 'Speak11',
        [System.Windows.Forms.MessageBoxButtons]$Buttons = 'OK',
        [System.Windows.Forms.MessageBoxIcon]$Icon = 'Information'
    )
    return [System.Windows.Forms.MessageBox]::Show($Message, $Title, $Buttons, $Icon)
}

# ── Progress helpers ──────────────────────────────────────────────
function Write-Step {
    param([string]$Message)
    Write-Host "  $([char]0x2713) " -ForegroundColor Green -NoNewline
    Write-Host " $Message"
}

function Write-Skip {
    param([string]$Message)
    Write-Host "  - " -ForegroundColor DarkGray -NoNewline
    Write-Host " $Message" -ForegroundColor DarkGray
}

# ══════════════════════════════════════════════════════════════════
#  MAIN
# ══════════════════════════════════════════════════════════════════

# ── Confirmation dialog ───────────────────────────────────────────
$confirmMsg = @"
This will completely remove Speak11:

  - Stop the Speak11 Settings tray app
  - Remove from startup
  - Remove the Start Menu shortcut
  - Remove scripts and app files
  - Remove settings and config
  - Remove the API key from Credential Manager

Continue?
"@
$confirmResult = Show-MessageBox -Message $confirmMsg -Title 'Speak11 — Uninstall' `
    -Buttons OKCancel -Icon Warning
if ($confirmResult -ne [System.Windows.Forms.DialogResult]::OK) {
    exit 0
}

# ── Show progress in console ─────────────────────────────────────
Clear-Host
Write-Host ''
Write-Host '  Speak11' -ForegroundColor White -NoNewline
Write-Host ' — Uninstalling' -ForegroundColor DarkGray
Write-Host '  ───────────────────────────' -ForegroundColor DarkGray
Write-Host ''

# ── Step 1: Stop Speak11Settings if running ───────────────────────
$procs = Get-Process -Name 'Speak11Settings' -ErrorAction SilentlyContinue
if ($procs) {
    $procs | Stop-Process -Force -ErrorAction SilentlyContinue
    # Give the process a moment to fully exit
    Start-Sleep -Milliseconds 500
    Write-Step 'Speak11 Settings stopped'
} else {
    Write-Skip 'Speak11 Settings was not running'
}

# ── Step 2: Remove from startup registry ──────────────────────────
try {
    $currentValue = Get-ItemProperty -Path $RunKey -Name $RunValueName -ErrorAction SilentlyContinue
    if ($currentValue) {
        Remove-ItemProperty -Path $RunKey -Name $RunValueName -Force -ErrorAction Stop
        Write-Step 'Removed from startup'
    } else {
        Write-Skip 'No startup entry found'
    }
} catch {
    Write-Skip "Startup entry: $_"
}

# ── Step 3: Remove Start Menu shortcut ────────────────────────────
if (Test-Path $ShortcutPath) {
    Remove-Item -LiteralPath $ShortcutPath -Force -ErrorAction SilentlyContinue
    Write-Step 'Start Menu shortcut removed'
} else {
    Write-Skip 'No Start Menu shortcut found'
}

# ── Step 4: Remove install directory ──────────────────────────────
if (Test-Path $InstallDir) {
    # Retry removal a few times in case a file is briefly locked
    $removed = $false
    for ($i = 0; $i -lt 3; $i++) {
        try {
            Remove-Item -LiteralPath $InstallDir -Recurse -Force -ErrorAction Stop
            $removed = $true
            break
        } catch {
            Start-Sleep -Milliseconds 500
        }
    }
    if ($removed) {
        Write-Step "Removed $InstallDir"
    } else {
        Write-Host "  ! " -ForegroundColor Yellow -NoNewline
        Write-Host " Could not fully remove $InstallDir (some files may be locked)"
    }
} else {
    Write-Skip 'Install directory not found'
}

# ── Step 5: Remove config directory ───────────────────────────────
if (Test-Path $ConfigDir) {
    Remove-Item -LiteralPath $ConfigDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Step "Removed $ConfigDir"
} else {
    Write-Skip 'Config directory not found'
}

# ── Step 6: Remove API key from Credential Manager ───────────────
try {
    [CredManager]::Delete('speak11-api-key')
    Write-Step 'API key removed from Credential Manager'
} catch {
    Write-Skip 'No API key found in Credential Manager'
}

# ── Done ──────────────────────────────────────────────────────────
Write-Host ''
Write-Host '  Speak11 has been removed.' -ForegroundColor Green
Write-Host ''

Show-MessageBox -Message 'Speak11 has been removed.' -Title 'Speak11' -Icon Information | Out-Null
