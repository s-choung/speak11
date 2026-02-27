// Config.cs — Port of the Swift Config struct.
// Reads and writes %USERPROFILE%\.config\speak11\config in key=value format.
// Same keys and defaults as the macOS version.

using System.Globalization;

namespace Speak11Settings;

/// <summary>
/// Application configuration stored as a simple key=value text file,
/// compatible with the shell scripts that read the same config.
/// </summary>
internal sealed class Config
{
    // ---------------------------------------------------------------
    // Default values (matching the Swift version)
    // ---------------------------------------------------------------

    public string VoiceId { get; set; } = "pFZP5JQG7iQjIQuC4Bku";
    public string ModelId { get; set; } = "eleven_flash_v2_5";
    public double Stability { get; set; } = 0.5;
    public double SimilarityBoost { get; set; } = 0.75;
    public double Style { get; set; } = 0.0;
    public bool UseSpeakerBoost { get; set; } = true;
    public double Speed { get; set; } = 1.0;
    public string SttModelId { get; set; } = "scribe_v2";
    public string SttLanguage { get; set; } = "";  // empty = auto-detect

    // ---------------------------------------------------------------
    // Paths
    // ---------------------------------------------------------------

    private static readonly string ConfigDir =
        Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            ".config", "speak11");

    private static readonly string ConfigPath =
        Path.Combine(ConfigDir, "config");

    // ---------------------------------------------------------------
    // Load
    // ---------------------------------------------------------------

    /// <summary>
    /// Loads config from disk. Returns a default Config if the file
    /// does not exist or cannot be parsed.
    /// </summary>
    public static Config Load()
    {
        var c = new Config();

        if (!File.Exists(ConfigPath))
            return c;

        string[] lines;
        try
        {
            lines = File.ReadAllLines(ConfigPath);
        }
        catch
        {
            return c;
        }

        foreach (string rawLine in lines)
        {
            string line = rawLine.Trim();
            if (string.IsNullOrEmpty(line) || line.StartsWith('#'))
                continue;

            int eq = line.IndexOf('=');
            if (eq < 0)
                continue;

            string key = line[..eq].Trim();
            string value = line[(eq + 1)..].Trim();

            // Strip surrounding quotes (single or double)
            if (value.Length >= 2 &&
                ((value[0] == '"' && value[^1] == '"') ||
                 (value[0] == '\'' && value[^1] == '\'')))
            {
                value = value[1..^1];
            }

            switch (key)
            {
                case "VOICE_ID":
                    c.VoiceId = value;
                    break;
                case "MODEL_ID":
                    c.ModelId = value;
                    break;
                case "STABILITY":
                    if (double.TryParse(value, CultureInfo.InvariantCulture, out double stab))
                        c.Stability = stab;
                    break;
                case "SIMILARITY_BOOST":
                    if (double.TryParse(value, CultureInfo.InvariantCulture, out double sim))
                        c.SimilarityBoost = sim;
                    break;
                case "STYLE":
                    if (double.TryParse(value, CultureInfo.InvariantCulture, out double sty))
                        c.Style = sty;
                    break;
                case "USE_SPEAKER_BOOST":
                    c.UseSpeakerBoost = value is "true" or "1";
                    break;
                case "SPEED":
                    if (double.TryParse(value, CultureInfo.InvariantCulture, out double spd))
                        c.Speed = spd;
                    break;
                case "STT_MODEL_ID":
                    c.SttModelId = value;
                    break;
                case "STT_LANGUAGE":
                    c.SttLanguage = value;
                    break;
            }
        }

        return c;
    }

    // ---------------------------------------------------------------
    // Save
    // ---------------------------------------------------------------

    /// <summary>
    /// Persists the current configuration to disk.
    /// Creates the config directory if it does not exist.
    /// </summary>
    public void Save()
    {
        try
        {
            Directory.CreateDirectory(ConfigDir);

            string[] lines =
            [
                $"VOICE_ID=\"{VoiceId}\"",
                $"MODEL_ID=\"{ModelId}\"",
                $"STABILITY=\"{Stability.ToString("F2", CultureInfo.InvariantCulture)}\"",
                $"SIMILARITY_BOOST=\"{SimilarityBoost.ToString("F2", CultureInfo.InvariantCulture)}\"",
                $"STYLE=\"{Style.ToString("F2", CultureInfo.InvariantCulture)}\"",
                $"USE_SPEAKER_BOOST=\"{(UseSpeakerBoost ? "true" : "false")}\"",
                $"SPEED=\"{Speed.ToString("F2", CultureInfo.InvariantCulture)}\"",
                $"STT_MODEL_ID=\"{SttModelId}\"",
                $"STT_LANGUAGE=\"{SttLanguage}\"",
            ];

            File.WriteAllText(ConfigPath, string.Join("\n", lines) + "\n");
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"Config.Save failed: {ex.Message}");
        }
    }
}
