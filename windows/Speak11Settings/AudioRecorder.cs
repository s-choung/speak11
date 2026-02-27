// AudioRecorder.cs — Audio recording using NAudio (WaveInEvent).
// Records 16-bit, 16 kHz, mono PCM to a temporary WAV file.
// This is the Windows equivalent of the AVAudioRecorder usage in the Swift version.

using NAudio.Wave;

namespace Speak11Settings;

/// <summary>
/// Records audio from the default microphone to a temporary WAV file.
/// Thread-safe: all public methods may be called from any thread.
/// </summary>
internal sealed class AudioRecorder : IDisposable
{
    // ---------------------------------------------------------------
    // Audio format matching the Swift version:
    //   16-bit PCM, 16 kHz sample rate, 1 channel (mono)
    // ---------------------------------------------------------------

    private const int SampleRate = 16000;
    private const int BitsPerSample = 16;
    private const int Channels = 1;

    // ---------------------------------------------------------------
    // State
    // ---------------------------------------------------------------

    private WaveInEvent? _waveIn;
    private WaveFileWriter? _writer;
    private string? _filePath;
    private bool _isRecording;
    private bool _disposed;
    private readonly object _lock = new();

    /// <summary>True if currently recording.</summary>
    public bool IsRecording
    {
        get { lock (_lock) return _isRecording; }
    }

    // ---------------------------------------------------------------
    // Recording control
    // ---------------------------------------------------------------

    /// <summary>
    /// Starts recording from the default microphone.
    /// Throws if the microphone is unavailable.
    /// </summary>
    public void StartRecording()
    {
        lock (_lock)
        {
            if (_isRecording)
                return;

            // Check that at least one recording device is available
            if (WaveInEvent.DeviceCount == 0)
                throw new InvalidOperationException(
                    "No microphone found. Please connect a microphone and try again.");

            // Create temp file
            string tempDir = Path.GetTempPath();
            string fileName = $"speak11_recording_{Guid.NewGuid():N}.wav";
            _filePath = Path.Combine(tempDir, fileName);

            var format = new WaveFormat(SampleRate, BitsPerSample, Channels);

            _waveIn = new WaveInEvent
            {
                WaveFormat = format,
                BufferMilliseconds = 100,
                DeviceNumber = 0,  // default recording device
            };

            _writer = new WaveFileWriter(_filePath, format);

            _waveIn.DataAvailable += OnDataAvailable;
            _waveIn.RecordingStopped += OnRecordingStopped;

            _waveIn.StartRecording();
            _isRecording = true;
        }
    }

    /// <summary>
    /// Stops recording and returns the path to the WAV file.
    /// Returns null if recording was not active.
    /// </summary>
    public string? StopRecording()
    {
        lock (_lock)
        {
            if (!_isRecording)
                return null;

            _isRecording = false;

            try
            {
                _waveIn?.StopRecording();
            }
            catch
            {
                // StopRecording may throw if the device was removed.
            }

            CleanupRecordingResources();
            return _filePath;
        }
    }

    // ---------------------------------------------------------------
    // NAudio callbacks
    // ---------------------------------------------------------------

    private void OnDataAvailable(object? sender, WaveInEventArgs e)
    {
        lock (_lock)
        {
            if (_writer != null && e.BytesRecorded > 0)
            {
                _writer.Write(e.Buffer, 0, e.BytesRecorded);
            }
        }
    }

    private void OnRecordingStopped(object? sender, StoppedEventArgs e)
    {
        lock (_lock)
        {
            CleanupRecordingResources();
        }

        if (e.Exception != null)
        {
            System.Diagnostics.Debug.WriteLine(
                $"Recording stopped with error: {e.Exception.Message}");
        }
    }

    // ---------------------------------------------------------------
    // Cleanup
    // ---------------------------------------------------------------

    private void CleanupRecordingResources()
    {
        if (_writer != null)
        {
            try { _writer.Dispose(); } catch { /* ignore */ }
            _writer = null;
        }

        if (_waveIn != null)
        {
            _waveIn.DataAvailable -= OnDataAvailable;
            _waveIn.RecordingStopped -= OnRecordingStopped;
            try { _waveIn.Dispose(); } catch { /* ignore */ }
            _waveIn = null;
        }
    }

    /// <summary>
    /// Deletes the temporary recording file if it exists.
    /// Call this after the file has been processed.
    /// </summary>
    public static void CleanupFile(string? filePath)
    {
        if (!string.IsNullOrEmpty(filePath))
        {
            try { File.Delete(filePath); } catch { /* ignore */ }
        }
    }

    // ---------------------------------------------------------------
    // IDisposable
    // ---------------------------------------------------------------

    public void Dispose()
    {
        if (_disposed)
            return;

        lock (_lock)
        {
            _isRecording = false;
            CleanupRecordingResources();
            _disposed = true;
        }
    }
}
