// CredentialManager.cs — Windows Credential Manager wrapper using P/Invoke.
// Stores and retrieves the ElevenLabs API key securely.

using System.Runtime.InteropServices;
using System.Text;

namespace Speak11Settings;

/// <summary>
/// Reads and writes the ElevenLabs API key via the Windows Credential Manager
/// (advapi32.dll). This is the Windows equivalent of macOS Keychain.
/// </summary>
internal static class CredentialManager
{
    private const string TargetName = "speak11-api-key";
    private const int CredTypeGeneric = 1;        // CRED_TYPE_GENERIC
    private const int CredPersistLocalMachine = 2; // CRED_PERSIST_LOCAL_MACHINE

    // ---------------------------------------------------------------
    // P/Invoke declarations
    // ---------------------------------------------------------------

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct CREDENTIAL
    {
        public uint Flags;
        public uint Type;
        public string TargetName;
        public string Comment;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
        public uint CredentialBlobSize;
        public IntPtr CredentialBlob;
        public uint Persist;
        public uint AttributeCount;
        public IntPtr Attributes;
        public string TargetAlias;
        public string UserName;
    }

    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool CredRead(
        string target,
        uint type,
        uint reservedFlag,
        out IntPtr credentialPtr);

    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool CredWrite(
        ref CREDENTIAL credential,
        uint flags);

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool CredDelete(
        string target,
        uint type,
        uint flags);

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern void CredFree(IntPtr buffer);

    // ---------------------------------------------------------------
    // Public API
    // ---------------------------------------------------------------

    /// <summary>
    /// Retrieves the API key from Credential Manager.
    /// Returns null if no credential is stored.
    /// </summary>
    public static string? GetApiKey()
    {
        if (!CredRead(TargetName, CredTypeGeneric, 0, out IntPtr credPtr))
            return null;

        try
        {
            var cred = Marshal.PtrToStructure<CREDENTIAL>(credPtr);
            if (cred.CredentialBlob == IntPtr.Zero || cred.CredentialBlobSize == 0)
                return null;

            return Marshal.PtrToStringUni(cred.CredentialBlob,
                (int)(cred.CredentialBlobSize / 2));
        }
        finally
        {
            CredFree(credPtr);
        }
    }

    /// <summary>
    /// Stores the API key in Credential Manager.
    /// Overwrites any existing credential with the same target name.
    /// </summary>
    public static void SetApiKey(string key)
    {
        byte[] blob = Encoding.Unicode.GetBytes(key);

        var cred = new CREDENTIAL
        {
            Type = CredTypeGeneric,
            TargetName = TargetName,
            CredentialBlobSize = (uint)blob.Length,
            CredentialBlob = Marshal.AllocHGlobal(blob.Length),
            Persist = CredPersistLocalMachine,
            UserName = "speak11",
            Comment = "ElevenLabs API key for Speak11",
        };

        try
        {
            Marshal.Copy(blob, 0, cred.CredentialBlob, blob.Length);

            if (!CredWrite(ref cred, 0))
            {
                int error = Marshal.GetLastWin32Error();
                throw new InvalidOperationException(
                    $"CredWrite failed with error code {error}.");
            }
        }
        finally
        {
            Marshal.FreeHGlobal(cred.CredentialBlob);
        }
    }

    /// <summary>
    /// Deletes the stored API key from Credential Manager.
    /// No-op if the credential does not exist.
    /// </summary>
    public static void DeleteApiKey()
    {
        CredDelete(TargetName, CredTypeGeneric, 0);
    }

    /// <summary>
    /// Returns true if an API key is stored in Credential Manager.
    /// </summary>
    public static bool HasApiKey()
    {
        if (!CredRead(TargetName, CredTypeGeneric, 0, out IntPtr credPtr))
            return false;

        CredFree(credPtr);
        return true;
    }
}
