// HotkeyManager.cs — Global hotkey registration using Win32 RegisterHotKey.
// Registers Alt+Shift+/ (TTS) and Alt+Shift+. (STT) as system-wide hotkeys.

using System.Runtime.InteropServices;

namespace Speak11Settings;

/// <summary>
/// Manages global hotkey registration and dispatches events when they fire.
/// Must be attached to a window (Form) that can receive WM_HOTKEY messages.
/// </summary>
internal sealed class HotkeyManager : IDisposable
{
    // ---------------------------------------------------------------
    // Win32 constants
    // ---------------------------------------------------------------

    private const int WM_HOTKEY = 0x0312;

    // Modifier keys for RegisterHotKey
    private const uint MOD_ALT   = 0x0001;
    private const uint MOD_SHIFT = 0x0004;

    // Virtual key codes
    private const uint VK_OEM_2      = 0xBF;  // Forward slash / question mark
    private const uint VK_OEM_PERIOD = 0xBE;  // Period / greater-than

    // Hotkey IDs (arbitrary, must be unique within the application)
    private const int HOTKEY_ID_TTS = 9001;
    private const int HOTKEY_ID_STT = 9002;

    // ---------------------------------------------------------------
    // P/Invoke
    // ---------------------------------------------------------------

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    // ---------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------

    /// <summary>Fired when Alt+Shift+/ is pressed (TTS hotkey).</summary>
    public event EventHandler? TtsHotkeyPressed;

    /// <summary>Fired when Alt+Shift+. is pressed (STT hotkey).</summary>
    public event EventHandler? SttHotkeyPressed;

    // ---------------------------------------------------------------
    // State
    // ---------------------------------------------------------------

    private readonly IntPtr _windowHandle;
    private bool _registered;
    private bool _disposed;

    // ---------------------------------------------------------------
    // Constructor
    // ---------------------------------------------------------------

    /// <summary>
    /// Creates a HotkeyManager bound to the given window handle.
    /// The window's WndProc must call <see cref="ProcessMessage"/> for
    /// WM_HOTKEY messages.
    /// </summary>
    public HotkeyManager(IntPtr windowHandle)
    {
        _windowHandle = windowHandle;
    }

    // ---------------------------------------------------------------
    // Registration
    // ---------------------------------------------------------------

    /// <summary>
    /// Registers both global hotkeys. Returns true if both succeeded.
    /// </summary>
    public bool Register()
    {
        if (_registered)
            return true;

        uint modifiers = MOD_ALT | MOD_SHIFT;

        bool ttsOk = RegisterHotKey(_windowHandle, HOTKEY_ID_TTS, modifiers, VK_OEM_2);
        bool sttOk = RegisterHotKey(_windowHandle, HOTKEY_ID_STT, modifiers, VK_OEM_PERIOD);

        _registered = ttsOk && sttOk;

        if (!ttsOk)
        {
            System.Diagnostics.Debug.WriteLine(
                $"Failed to register TTS hotkey (Alt+Shift+/). Error: {Marshal.GetLastWin32Error()}");
        }
        if (!sttOk)
        {
            System.Diagnostics.Debug.WriteLine(
                $"Failed to register STT hotkey (Alt+Shift+.). Error: {Marshal.GetLastWin32Error()}");
        }

        return _registered;
    }

    /// <summary>
    /// Unregisters both global hotkeys.
    /// </summary>
    public void Unregister()
    {
        if (!_registered)
            return;

        UnregisterHotKey(_windowHandle, HOTKEY_ID_TTS);
        UnregisterHotKey(_windowHandle, HOTKEY_ID_STT);
        _registered = false;
    }

    // ---------------------------------------------------------------
    // Message processing
    // ---------------------------------------------------------------

    /// <summary>
    /// Call this from the owning Form's WndProc when m.Msg == WM_HOTKEY.
    /// Returns true if the message was handled.
    /// </summary>
    public bool ProcessMessage(ref Message m)
    {
        if (m.Msg != WM_HOTKEY)
            return false;

        int id = m.WParam.ToInt32();

        switch (id)
        {
            case HOTKEY_ID_TTS:
                TtsHotkeyPressed?.Invoke(this, EventArgs.Empty);
                return true;

            case HOTKEY_ID_STT:
                SttHotkeyPressed?.Invoke(this, EventArgs.Empty);
                return true;

            default:
                return false;
        }
    }

    /// <summary>
    /// The WM_HOTKEY constant, exposed so the Form can check against it.
    /// </summary>
    public static int WmHotkey => WM_HOTKEY;

    // ---------------------------------------------------------------
    // IDisposable
    // ---------------------------------------------------------------

    public void Dispose()
    {
        if (_disposed)
            return;

        Unregister();
        _disposed = true;
    }
}
