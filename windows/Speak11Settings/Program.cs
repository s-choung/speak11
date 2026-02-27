// Program.cs — Entry point for Speak11 Settings (Windows system tray app)
// Ensures single-instance via a named mutex.

namespace Speak11Settings;

internal static class Program
{
    private const string MutexName = "Global\\Speak11Settings_SingleInstance";

    [STAThread]
    static void Main()
    {
        using var mutex = new Mutex(true, MutexName, out bool createdNew);
        if (!createdNew)
        {
            // Another instance is already running — exit silently.
            MessageBox.Show(
                "Speak11 Settings is already running.\nCheck the system tray.",
                "Speak11",
                MessageBoxButtons.OK,
                MessageBoxIcon.Information);
            return;
        }

        ApplicationConfiguration.Initialize();
        Application.Run(new TrayApp());
    }
}
