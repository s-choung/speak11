// TrayApp.cs — Main form (hidden window) managing the system tray icon and menus.
// This is the Windows equivalent of the Swift AppDelegate.
// The form is never shown; it exists solely to own the NotifyIcon and receive
// WM_HOTKEY messages from the HotkeyManager.

using System.Diagnostics;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;

// ReSharper disable InconsistentNaming

namespace Speak11Settings;

/// <summary>
/// Hidden form that hosts the system tray icon, context menu,
/// global hotkeys, TTS, and STT functionality.
/// </summary>
internal sealed class TrayApp : Form
{
    // ---------------------------------------------------------------
    // Win32 — SendInput for simulating Ctrl+C / Ctrl+V
    // ---------------------------------------------------------------

    [StructLayout(LayoutKind.Sequential)]
    private struct INPUT
    {
        public uint type;
        public INPUTUNION union;
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct INPUTUNION
    {
        [FieldOffset(0)] public KEYBDINPUT ki;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KEYBDINPUT
    {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    private const uint INPUT_KEYBOARD = 1;
    private const uint KEYEVENTF_KEYUP = 0x0002;
    private const ushort VK_CONTROL = 0x11;
    private const ushort VK_C = 0x43;
    private const ushort VK_V = 0x56;

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DestroyIcon(IntPtr hIcon);

    // ---------------------------------------------------------------
    // Static data — voices, models, steps (matching Swift version)
    // ---------------------------------------------------------------

    private static readonly (string Name, string Id)[] KnownVoices =
    [
        ("Lily \u2014 British, raspy",      "pFZP5JQG7iQjIQuC4Bku"),
        ("Alice \u2014 British, confident", "Xb7hH8MSUJpSbSDYk0k2"),
        ("Rachel \u2014 calm",              "21m00Tcm4TlvDq8ikWAM"),
        ("Adam \u2014 deep",                "pNInz6obpgDQGcFmaJgB"),
        ("Domi \u2014 strong",              "AZnzlk1XvdvUeBnXmlld"),
        ("Josh \u2014 young, deep",         "TxGEqnHWrfWFTfGW9XjX"),
        ("Sam \u2014 raspy",                "yoZ06aMxZJJ28mfd3POQ"),
    ];

    private static readonly (string Name, string Id)[] KnownModels =
    [
        ("v3 \u2014 best quality",          "eleven_v3"),
        ("Flash v2.5 \u2014 fastest",       "eleven_flash_v2_5"),
        ("Turbo v2.5 \u2014 fast, \u00bd cost", "eleven_turbo_v2_5"),
        ("Multilingual v2 \u2014 29 langs", "eleven_multilingual_v2"),
    ];

    private static readonly (string Label, double Value)[] SpeedSteps =
    [
        ("0.7\u00d7", 0.7), ("0.85\u00d7", 0.85), ("1\u00d7", 1.0),
        ("1.1\u00d7", 1.1), ("1.2\u00d7", 1.2),
    ];

    private static readonly (string Label, double Value)[] StabilitySteps =
    [
        ("0.0 \u2014 expressive", 0.0), ("0.25", 0.25),
        ("0.5 \u2014 default", 0.5), ("0.75", 0.75),
        ("1.0 \u2014 steady", 1.0),
    ];

    private static readonly (string Label, double Value)[] SimilaritySteps =
    [
        ("0.0 \u2014 low", 0.0), ("0.25", 0.25), ("0.5", 0.5),
        ("0.75 \u2014 default", 0.75), ("1.0 \u2014 high", 1.0),
    ];

    private static readonly (string Label, double Value)[] StyleSteps =
    [
        ("0.0 \u2014 none (default)", 0.0), ("0.25", 0.25), ("0.5", 0.5),
        ("0.75", 0.75), ("1.0 \u2014 max", 1.0),
    ];

    private static readonly (string Name, string Id)[] SttModels =
    [
        ("Scribe v2 \u2014 latest", "scribe_v2"),
        ("Scribe v1",               "scribe_v1"),
    ];

    private static readonly (string Name, string Code)[] SttLanguages =
    [
        ("Auto-detect", ""),  ("English", "en"), ("Korean", "ko"),
        ("Japanese", "ja"),   ("Chinese", "zh"), ("Spanish", "es"),
        ("French", "fr"),     ("German", "de"),
    ];

    // ---------------------------------------------------------------
    // Instance state
    // ---------------------------------------------------------------

    private Config _config;
    private readonly NotifyIcon _notifyIcon;
    private readonly HotkeyManager _hotkeyManager;
    private readonly AudioRecorder _audioRecorder;

    // Animation state
    private System.Windows.Forms.Timer? _animTimer;
    private double _animPhase;

    // Recording state
    private bool _isRecording;

    // TTS state — track running process to prevent overlapping
    private Process? _ttsProcess;

    // Default (idle) icon, cached
    private readonly Icon _idleIcon;

    // ---------------------------------------------------------------
    // Constructor
    // ---------------------------------------------------------------

    public TrayApp()
    {
        // This form is never shown — it is a hidden message-only window.
        ShowInTaskbar = false;
        WindowState = FormWindowState.Minimized;
        FormBorderStyle = FormBorderStyle.None;
        Opacity = 0;

        _config = Config.Load();
        _idleIcon = CreateWaveformIcon(phase: 0);

        _notifyIcon = new NotifyIcon
        {
            Icon = _idleIcon,
            Text = "Speak11",
            Visible = true,
        };

        _hotkeyManager = new HotkeyManager(Handle);
        _hotkeyManager.TtsHotkeyPressed += OnTtsHotkey;
        _hotkeyManager.SttHotkeyPressed += OnSttHotkey;

        _audioRecorder = new AudioRecorder();

        RebuildMenu();
    }

    // ---------------------------------------------------------------
    // Form lifecycle
    // ---------------------------------------------------------------

    protected override void OnLoad(EventArgs e)
    {
        base.OnLoad(e);

        // Hide the form immediately
        Visible = false;

        // Register global hotkeys
        if (!_hotkeyManager.Register())
        {
            _notifyIcon.ShowBalloonTip(
                3000,
                "Speak11",
                "Could not register global hotkeys (Alt+Shift+/ and Alt+Shift+.).\n" +
                "Another application may have claimed them.",
                ToolTipIcon.Warning);
        }
    }

    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        _hotkeyManager.Dispose();
        _audioRecorder.Dispose();
        _animTimer?.Dispose();
        _notifyIcon.Visible = false;
        _notifyIcon.Dispose();
        _idleIcon.Dispose();
        base.OnFormClosing(e);
    }

    // ---------------------------------------------------------------
    // WndProc — route WM_HOTKEY to HotkeyManager
    // ---------------------------------------------------------------

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == HotkeyManager.WmHotkey)
        {
            if (_hotkeyManager.ProcessMessage(ref m))
                return;
        }
        base.WndProc(ref m);
    }

    // ---------------------------------------------------------------
    // Menu construction
    // ---------------------------------------------------------------

    private void RebuildMenu()
    {
        var menu = new ContextMenuStrip();

        // --- TTS settings ---
        menu.Items.Add(BuildSubmenu("Voice", BuildVoiceItems()));
        menu.Items.Add(BuildSubmenu("Model", BuildModelItems()));
        menu.Items.Add(BuildSubmenu("Speed", BuildSpeedItems()));
        menu.Items.Add(BuildSubmenu("Stability", BuildStabilityItems()));
        menu.Items.Add(BuildSubmenu("Similarity", BuildSimilarityItems()));
        menu.Items.Add(BuildSubmenu("Style", BuildStyleItems()));

        // Speaker Boost toggle
        var boostItem = new ToolStripMenuItem("Speaker Boost")
        {
            Checked = _config.UseSpeakerBoost,
            CheckOnClick = false,
        };
        boostItem.Click += (_, _) =>
        {
            _config.UseSpeakerBoost = !_config.UseSpeakerBoost;
            _config.Save();
            RebuildMenu();
        };
        menu.Items.Add(boostItem);

        menu.Items.Add(new ToolStripSeparator());

        // --- STT settings ---
        var sttHeader = new ToolStripMenuItem("Speech-to-Text") { Enabled = false };
        menu.Items.Add(sttHeader);
        menu.Items.Add(BuildSubmenu("STT Language", BuildSttLanguageItems()));
        menu.Items.Add(BuildSubmenu("STT Model", BuildSttModelItems()));

        menu.Items.Add(new ToolStripSeparator());

        // --- API Key ---
        bool hasKey = CredentialManager.HasApiKey();
        string keyLabel = hasKey ? "API Key \u2713" : "API Key \u2717  (click to set)";
        var keyItem = new ToolStripMenuItem(keyLabel);
        keyItem.Click += (_, _) => ShowApiKeyDialog();
        menu.Items.Add(keyItem);

        menu.Items.Add(new ToolStripSeparator());

        // --- Quit ---
        var quitItem = new ToolStripMenuItem("Quit");
        quitItem.Click += (_, _) => Application.Exit();
        menu.Items.Add(quitItem);

        // Swap the menu
        var old = _notifyIcon.ContextMenuStrip;
        _notifyIcon.ContextMenuStrip = menu;
        old?.Dispose();
    }

    // ---------------------------------------------------------------
    // Voice submenu
    // ---------------------------------------------------------------

    private ToolStripItem[] BuildVoiceItems()
    {
        bool isCustom = !Array.Exists(KnownVoices, v => v.Id == _config.VoiceId);
        var items = new List<ToolStripItem>();

        foreach (var (name, id) in KnownVoices)
        {
            var mi = new ToolStripMenuItem(name)
            {
                Checked = id == _config.VoiceId,
                Tag = id,
            };
            mi.Click += (s, _) =>
            {
                _config.VoiceId = (string)((ToolStripMenuItem)s!).Tag!;
                _config.Save();
                RebuildMenu();
            };
            items.Add(mi);
        }

        items.Add(new ToolStripSeparator());

        string customLabel = isCustom ? $"Custom: {_config.VoiceId}" : "Custom voice ID\u2026";
        var customItem = new ToolStripMenuItem(customLabel) { Checked = isCustom };
        customItem.Click += (_, _) => ShowCustomVoiceDialog();
        items.Add(customItem);

        return items.ToArray();
    }

    // ---------------------------------------------------------------
    // Model submenu
    // ---------------------------------------------------------------

    private ToolStripItem[] BuildModelItems()
    {
        return KnownModels.Select(m =>
        {
            var mi = new ToolStripMenuItem(m.Name)
            {
                Checked = m.Id == _config.ModelId,
                Tag = m.Id,
            };
            mi.Click += (s, _) =>
            {
                _config.ModelId = (string)((ToolStripMenuItem)s!).Tag!;
                _config.Save();
                RebuildMenu();
            };
            return (ToolStripItem)mi;
        }).ToArray();
    }

    // ---------------------------------------------------------------
    // Numeric step submenus (Speed, Stability, Similarity, Style)
    // ---------------------------------------------------------------

    private ToolStripItem[] BuildSpeedItems() =>
        BuildDoubleStepItems(SpeedSteps, _config.Speed, v =>
        {
            _config.Speed = v;
            _config.Save();
            RebuildMenu();
        });

    private ToolStripItem[] BuildStabilityItems()
    {
        var hint = new ToolStripMenuItem("Lower = expressive \u00b7 Higher = steady") { Enabled = false };
        var sep = new ToolStripSeparator();
        var steps = BuildDoubleStepItems(StabilitySteps, _config.Stability, v =>
        {
            _config.Stability = v;
            _config.Save();
            RebuildMenu();
        });
        return [hint, sep, .. steps];
    }

    private ToolStripItem[] BuildSimilarityItems()
    {
        var hint = new ToolStripMenuItem("How closely output matches the original voice") { Enabled = false };
        var sep = new ToolStripSeparator();
        var steps = BuildDoubleStepItems(SimilaritySteps, _config.SimilarityBoost, v =>
        {
            _config.SimilarityBoost = v;
            _config.Save();
            RebuildMenu();
        });
        return [hint, sep, .. steps];
    }

    private ToolStripItem[] BuildStyleItems()
    {
        var hint = new ToolStripMenuItem("Amplifies characteristic delivery \u00b7 adds latency") { Enabled = false };
        var sep = new ToolStripSeparator();
        var steps = BuildDoubleStepItems(StyleSteps, _config.Style, v =>
        {
            _config.Style = v;
            _config.Save();
            RebuildMenu();
        });
        return [hint, sep, .. steps];
    }

    private static ToolStripItem[] BuildDoubleStepItems(
        (string Label, double Value)[] steps,
        double currentValue,
        Action<double> onPick)
    {
        return steps.Select(s =>
        {
            var mi = new ToolStripMenuItem(s.Label)
            {
                Checked = Math.Abs(s.Value - currentValue) < 0.01,
                Tag = s.Value,
            };
            mi.Click += (sender, _) =>
            {
                double val = (double)((ToolStripMenuItem)sender!).Tag!;
                onPick(val);
            };
            return (ToolStripItem)mi;
        }).ToArray();
    }

    // ---------------------------------------------------------------
    // STT submenus
    // ---------------------------------------------------------------

    private ToolStripItem[] BuildSttLanguageItems()
    {
        return SttLanguages.Select(lang =>
        {
            var mi = new ToolStripMenuItem(lang.Name)
            {
                Checked = lang.Code == _config.SttLanguage,
                Tag = lang.Code,
            };
            mi.Click += (s, _) =>
            {
                _config.SttLanguage = (string)((ToolStripMenuItem)s!).Tag!;
                _config.Save();
                RebuildMenu();
            };
            return (ToolStripItem)mi;
        }).ToArray();
    }

    private ToolStripItem[] BuildSttModelItems()
    {
        return SttModels.Select(m =>
        {
            var mi = new ToolStripMenuItem(m.Name)
            {
                Checked = m.Id == _config.SttModelId,
                Tag = m.Id,
            };
            mi.Click += (s, _) =>
            {
                _config.SttModelId = (string)((ToolStripMenuItem)s!).Tag!;
                _config.Save();
                RebuildMenu();
            };
            return (ToolStripItem)mi;
        }).ToArray();
    }

    // ---------------------------------------------------------------
    // Helper: build a submenu from child items
    // ---------------------------------------------------------------

    private static ToolStripMenuItem BuildSubmenu(string title, ToolStripItem[] children)
    {
        var parent = new ToolStripMenuItem(title);
        parent.DropDownItems.AddRange(children);
        return parent;
    }

    // ---------------------------------------------------------------
    // TTS hotkey handler
    // ---------------------------------------------------------------

    private async void OnTtsHotkey(object? sender, EventArgs e)
    {
        // Toggle: if TTS is already running, stop it (same as macOS speak.sh PID toggle)
        if (_ttsProcess != null && !_ttsProcess.HasExited)
        {
            try { _ttsProcess.Kill(); } catch { }
            _ttsProcess = null;
            SetSpeaking(false);
            return;
        }

        // 1. Simulate Ctrl+C to copy selected text
        SimulateCtrlC();

        // 2. Wait for clipboard to be populated
        await Task.Delay(200);

        // 3. Find speak.ps1
        string? scriptPath = FindScript("speak.ps1");
        if (scriptPath == null)
        {
            _notifyIcon.ShowBalloonTip(
                3000, "Speak11",
                "speak.ps1 not found.\nPlace it next to Speak11Settings.exe or in %LOCALAPPDATA%\\Speak11\\.",
                ToolTipIcon.Error);
            return;
        }

        // 4. Start speaking animation
        SetSpeaking(true);

        // 5. Run speak.ps1 as a background process
        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = "powershell.exe",
                Arguments = $"-NoProfile -ExecutionPolicy Bypass -File \"{scriptPath}\"",
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardInput = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
            };

            _ttsProcess = Process.Start(psi);
            if (_ttsProcess != null)
            {
                _ttsProcess.EnableRaisingEvents = true;
                _ttsProcess.Exited += (_, _) =>
                {
                    BeginInvoke(() => SetSpeaking(false));
                    _ttsProcess = null;
                };
            }
            else
            {
                SetSpeaking(false);
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"TTS launch failed: {ex.Message}");
            SetSpeaking(false);
        }
    }

    // ---------------------------------------------------------------
    // STT hotkey handler
    // ---------------------------------------------------------------

    private async void OnSttHotkey(object? sender, EventArgs e)
    {
        if (_isRecording)
        {
            // --- Stop recording and transcribe ---
            _isRecording = false;
            string? audioFile = _audioRecorder.StopRecording();

            if (string.IsNullOrEmpty(audioFile))
            {
                SetRecordingIcon(false);
                return;
            }

            // Show transcribing animation
            SetSpeaking(true);

            // Find listen.ps1
            string? scriptPath = FindScript("listen.ps1");
            if (scriptPath == null)
            {
                SetSpeaking(false);
                AudioRecorder.CleanupFile(audioFile);
                _notifyIcon.ShowBalloonTip(
                    3000, "Speak11",
                    "listen.ps1 not found.\nPlace it next to Speak11Settings.exe or in %LOCALAPPDATA%\\Speak11\\.",
                    ToolTipIcon.Error);
                return;
            }

            try
            {
                var psi = new ProcessStartInfo
                {
                    FileName = "powershell.exe",
                    Arguments = $"-NoProfile -ExecutionPolicy Bypass -File \"{scriptPath}\" \"{audioFile}\"",
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardInput = true,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                };

                var process = Process.Start(psi);
                if (process != null)
                {
                    await process.WaitForExitAsync();
                    bool success = process.ExitCode == 0;

                    AudioRecorder.CleanupFile(audioFile);

                    BeginInvoke(() =>
                    {
                        SetSpeaking(false);
                        if (success)
                        {
                            // Simulate Ctrl+V to paste the transcribed text
                            SimulateCtrlV();
                        }
                    });
                }
                else
                {
                    AudioRecorder.CleanupFile(audioFile);
                    SetSpeaking(false);
                }
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"STT launch failed: {ex.Message}");
                AudioRecorder.CleanupFile(audioFile);
                SetSpeaking(false);
            }
        }
        else
        {
            // --- Start recording ---
            try
            {
                _audioRecorder.StartRecording();
                _isRecording = true;
                SetRecordingIcon(true);
            }
            catch (Exception ex)
            {
                _notifyIcon.ShowBalloonTip(
                    3000, "Speak11",
                    $"Failed to start recording: {ex.Message}",
                    ToolTipIcon.Error);
            }
        }
    }

    // ---------------------------------------------------------------
    // Script discovery
    // ---------------------------------------------------------------

    /// <summary>
    /// Searches for the given script name in:
    ///   1. Same directory as the executable
    ///   2. %LOCALAPPDATA%\Speak11\
    /// Returns the full path if found, null otherwise.
    /// </summary>
    private static string? FindScript(string scriptName)
    {
        // 1. Next to the executable
        string exeDir = AppContext.BaseDirectory;
        string candidate = Path.Combine(exeDir, scriptName);
        if (File.Exists(candidate))
            return candidate;

        // 2. %LOCALAPPDATA%\Speak11\
        string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        candidate = Path.Combine(localAppData, "Speak11", scriptName);
        if (File.Exists(candidate))
            return candidate;

        return null;
    }

    // ---------------------------------------------------------------
    // Keyboard simulation via SendInput
    // ---------------------------------------------------------------

    private static void SimulateCtrlC()
    {
        SendKeyCombo(VK_CONTROL, VK_C);
    }

    private static void SimulateCtrlV()
    {
        SendKeyCombo(VK_CONTROL, VK_V);
    }

    private static void SendKeyCombo(ushort modifier, ushort key)
    {
        var inputs = new INPUT[4];
        int size = Marshal.SizeOf<INPUT>();

        // Modifier down
        inputs[0].type = INPUT_KEYBOARD;
        inputs[0].union.ki.wVk = modifier;

        // Key down
        inputs[1].type = INPUT_KEYBOARD;
        inputs[1].union.ki.wVk = key;

        // Key up
        inputs[2].type = INPUT_KEYBOARD;
        inputs[2].union.ki.wVk = key;
        inputs[2].union.ki.dwFlags = KEYEVENTF_KEYUP;

        // Modifier up
        inputs[3].type = INPUT_KEYBOARD;
        inputs[3].union.ki.wVk = modifier;
        inputs[3].union.ki.dwFlags = KEYEVENTF_KEYUP;

        SendInput((uint)inputs.Length, inputs, size);
    }

    // ---------------------------------------------------------------
    // Tray icon — speaking animation
    // ---------------------------------------------------------------

    /// <summary>
    /// Starts or stops the waveform speaking animation on the tray icon.
    /// </summary>
    private void SetSpeaking(bool active)
    {
        // Always stop any existing animation first (prevents leaked timers
        // when the hotkey fires while a previous process is still running).
        _animTimer?.Stop();
        _animTimer?.Dispose();
        _animTimer = null;

        if (active)
        {
            _animPhase = 0;
            UpdateTrayIcon(CreateWaveformIcon(0));

            _animTimer = new System.Windows.Forms.Timer { Interval = 100 };
            _animTimer.Tick += (_, _) =>
            {
                _animPhase += 0.5;
                UpdateTrayIcon(CreateWaveformIcon(_animPhase));
            };
            _animTimer.Start();
        }
        else
        {
            UpdateTrayIcon(_idleIcon);
        }
    }

    /// <summary>
    /// Shows a microphone icon when recording, reverts to idle when not.
    /// </summary>
    private void SetRecordingIcon(bool recording)
    {
        _animTimer?.Stop();
        _animTimer?.Dispose();
        _animTimer = null;

        if (recording)
        {
            UpdateTrayIcon(CreateMicIcon());
        }
        else
        {
            UpdateTrayIcon(_idleIcon);
        }
    }

    private void UpdateTrayIcon(Icon icon)
    {
        var old = _notifyIcon.Icon;
        _notifyIcon.Icon = icon;

        // Dispose the previous icon if it is not the cached idle icon
        if (old != null && old != _idleIcon && old != icon)
        {
            old.Dispose();
        }
    }

    // ---------------------------------------------------------------
    // Icon drawing — waveform bars (matches Swift sin-wave logic)
    // ---------------------------------------------------------------

    /// <summary>
    /// Draws a waveform icon with animated bars, matching the macOS version.
    /// </summary>
    private static Icon CreateWaveformIcon(double phase)
    {
        const int size = 16;
        const int barCount = 5;
        const float barWidth = 2f;
        const float gap = 1.5f;
        float totalW = barCount * barWidth + (barCount - 1) * gap;
        float startX = (size - totalW) / 2f;

        using var bmp = new Bitmap(size, size);
        using var g = Graphics.FromImage(bmp);
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.Clear(Color.Transparent);

        using var brush = new SolidBrush(Color.White);

        for (int i = 0; i < barCount; i++)
        {
            double t = phase + i * 0.8;
            double norm = (Math.Sin(t) + 1.0) / 2.0;  // 0..1
            float minH = 3f;
            float maxH = 13f;
            float barH = minH + (float)(norm * (maxH - minH));
            float x = startX + i * (barWidth + gap);
            float y = (size - barH) / 2f;
            var rect = new RectangleF(x, y, barWidth, barH);
            g.FillRectangle(brush, rect);
        }

        IntPtr hIcon = bmp.GetHicon();
        var icon = (Icon)Icon.FromHandle(hIcon).Clone();
        DestroyIcon(hIcon);
        return icon;
    }

    /// <summary>
    /// Draws a simple microphone icon for recording state.
    /// </summary>
    private static Icon CreateMicIcon()
    {
        const int size = 16;

        using var bmp = new Bitmap(size, size);
        using var g = Graphics.FromImage(bmp);
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.Clear(Color.Transparent);

        using var brush = new SolidBrush(Color.Red);
        using var pen = new Pen(Color.Red, 1.5f);

        // Mic head (rounded rectangle / ellipse)
        g.FillEllipse(brush, 5f, 1f, 6f, 8f);

        // Mic arc
        g.DrawArc(pen, 3f, 4f, 10f, 8f, 0f, 180f);

        // Stand
        g.DrawLine(pen, 8f, 12f, 8f, 14f);
        g.DrawLine(pen, 5f, 14f, 11f, 14f);

        IntPtr hIcon = bmp.GetHicon();
        var icon = (Icon)Icon.FromHandle(hIcon).Clone();
        DestroyIcon(hIcon);
        return icon;
    }

    // ---------------------------------------------------------------
    // API Key dialog
    // ---------------------------------------------------------------

    private void ShowApiKeyDialog()
    {
        using var dialog = new Form
        {
            Text = "ElevenLabs API Key",
            Size = new Size(420, 180),
            FormBorderStyle = FormBorderStyle.FixedDialog,
            StartPosition = FormStartPosition.CenterScreen,
            MaximizeBox = false,
            MinimizeBox = false,
            TopMost = true,
        };

        var label = new Label
        {
            Text = "Paste your API key from elevenlabs.io/app/developers/api-keys.\n" +
                   "It will be stored securely in Windows Credential Manager.",
            Location = new Point(12, 12),
            Size = new Size(380, 40),
        };

        var textBox = new TextBox
        {
            Location = new Point(12, 58),
            Size = new Size(380, 24),
            UseSystemPasswordChar = true,
            PlaceholderText = "sk_...",
        };

        var saveBtn = new Button
        {
            Text = "Save",
            DialogResult = DialogResult.OK,
            Location = new Point(216, 95),
            Size = new Size(85, 30),
        };

        var cancelBtn = new Button
        {
            Text = "Cancel",
            DialogResult = DialogResult.Cancel,
            Location = new Point(307, 95),
            Size = new Size(85, 30),
        };

        dialog.Controls.AddRange([label, textBox, saveBtn, cancelBtn]);
        dialog.AcceptButton = saveBtn;
        dialog.CancelButton = cancelBtn;

        if (dialog.ShowDialog() == DialogResult.OK)
        {
            string key = textBox.Text.Trim();
            if (!string.IsNullOrEmpty(key))
            {
                try
                {
                    CredentialManager.SetApiKey(key);
                }
                catch (Exception ex)
                {
                    MessageBox.Show(
                        $"Failed to store API key: {ex.Message}",
                        "Speak11",
                        MessageBoxButtons.OK,
                        MessageBoxIcon.Error);
                }
                RebuildMenu();
            }
        }
    }

    // ---------------------------------------------------------------
    // Custom voice dialog
    // ---------------------------------------------------------------

    private void ShowCustomVoiceDialog()
    {
        using var dialog = new Form
        {
            Text = "Custom Voice ID",
            Size = new Size(420, 170),
            FormBorderStyle = FormBorderStyle.FixedDialog,
            StartPosition = FormStartPosition.CenterScreen,
            MaximizeBox = false,
            MinimizeBox = false,
            TopMost = true,
        };

        var label = new Label
        {
            Text = "Enter a voice ID from elevenlabs.io/voice-library",
            Location = new Point(12, 12),
            Size = new Size(380, 20),
        };

        var textBox = new TextBox
        {
            Location = new Point(12, 40),
            Size = new Size(380, 24),
            Text = _config.VoiceId,
            PlaceholderText = "e.g. pFZP5JQG7iQjIQuC4Bku",
        };

        var saveBtn = new Button
        {
            Text = "Save",
            DialogResult = DialogResult.OK,
            Location = new Point(216, 80),
            Size = new Size(85, 30),
        };

        var cancelBtn = new Button
        {
            Text = "Cancel",
            DialogResult = DialogResult.Cancel,
            Location = new Point(307, 80),
            Size = new Size(85, 30),
        };

        dialog.Controls.AddRange([label, textBox, saveBtn, cancelBtn]);
        dialog.AcceptButton = saveBtn;
        dialog.CancelButton = cancelBtn;

        if (dialog.ShowDialog() == DialogResult.OK)
        {
            string val = textBox.Text.Trim();
            if (!string.IsNullOrEmpty(val))
            {
                _config.VoiceId = val;
                _config.Save();
                RebuildMenu();
            }
        }
    }
}
