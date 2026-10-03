using System.Security;
using System.Security.Cryptography;
using System.Text;

namespace TigerMarkView.Core.Settings;

/// <summary>
/// The settings file every running TigerMarkView window shares: read whole, and changed one decision
/// at a time on top of whatever is in it now.
/// </summary>
/// <remarks>
/// <para>
/// Each window is its own process and keeps its own <see cref="ApplicationSettings"/> in memory. If a
/// window wrote that whole object back on every change, the last window to change <em>anything</em>
/// would restore everything else as it was when <em>it</em> started: Clear Recent Files in one window
/// undone by a theme change in another, a recent file opened in one window dropped by the next save
/// from the other. So nothing writes a whole object. <see cref="Update"/> reads the file as it is now,
/// applies only the change the caller made, and writes the result — field-level merge, where the
/// field a window did not touch keeps whatever another window last put there.
/// </para>
/// <para>
/// The read-change-write runs under a named mutex derived from the file's path, so two windows
/// changing settings at the same moment queue rather than interleave, and a reader never meets a file
/// halfway through being replaced. Writes go to a temporary file flushed to disk and then replace the
/// settings in one move, so a crash or power loss leaves either the old file or the new one. If the
/// lock cannot be had within a few seconds the update still runs — it remains a merge, only no longer
/// serialized — because a setting the reader just chose should not be dropped over a stuck window.
/// </para>
/// <para>
/// Platform-neutral: this type knows how the file is changed, never where it lives; the application's
/// <c>SettingsStore</c> owns that. Neither member ever throws for a file problem. Settings are
/// convenience data, and a bad file or a read-only profile must not stop a window from working.
/// </para>
/// </remarks>
public sealed class ApplicationSettingsFile
{
    /// <summary>Suffix given to a file that could not be parsed, so the user can inspect or restore it.</summary>
    public const string InvalidSuffix = ".invalid";

    private static readonly TimeSpan LockTimeout = TimeSpan.FromSeconds(5);

    private readonly string _filePath;
    private readonly string _mutexName;

    public ApplicationSettingsFile(string filePath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(filePath);
        _filePath = Path.GetFullPath(filePath);
        _mutexName = MutexNameFor(_filePath);
    }

    public string FilePath => _filePath;

    /// <summary>
    /// The settings as they are now, or defaults when there are none or they cannot be used. An
    /// unparseable file is moved aside (best effort) so the next update starts from a clean slate
    /// without destroying whatever the user had.
    /// </summary>
    public ApplicationSettings Load()
    {
        using var held = AcquireLock();
        return Read() ?? ApplicationSettings.CreateDefault();
    }

    /// <summary>
    /// Applies <paramref name="change"/> to the settings as they are on disk now and writes the result.
    /// Returns what was written, or <see langword="null"/> when nothing could be — including when the
    /// file exists but cannot be read just now, because writing defaults over it would lose everything
    /// else in it.
    /// </summary>
    /// <param name="change">
    /// The caller's decision, expressed against whatever settings it is handed: set a field, add or
    /// clear recent files. It must not copy state the caller merely remembers.
    /// </param>
    public ApplicationSettings? Update(Action<ApplicationSettings> change)
    {
        ArgumentNullException.ThrowIfNull(change);

        using var held = AcquireLock();

        if (Read() is not { } current)
        {
            return null;
        }

        change(current);
        current.Normalized();

        return Write(current) ? current : null;
    }

    /// <summary>
    /// The current settings, defaults for a missing or unparseable file, and <see langword="null"/>
    /// when an existing file cannot be read.
    /// </summary>
    private ApplicationSettings? Read()
    {
        string json;
        try
        {
            if (!File.Exists(_filePath))
            {
                return ApplicationSettings.CreateDefault();
            }

            json = File.ReadAllText(_filePath);
        }
        catch (Exception exception) when (IsExpectedFileFailure(exception))
        {
            return null;
        }

        if (ApplicationSettingsSerializer.TryDeserialize(json, out var settings))
        {
            return settings;
        }

        QuarantineInvalidFile();
        return settings;
    }

    private bool Write(ApplicationSettings settings)
    {
        // Named for this process, so an update that ran without the lock cannot collide with
        // another window's temporary file.
        var temporaryPath = $"{_filePath}.{Environment.ProcessId}.tmp";
        try
        {
            var bytes = Encoding.UTF8.GetBytes(ApplicationSettingsSerializer.Serialize(settings));

            var directory = Path.GetDirectoryName(_filePath);
            if (!string.IsNullOrEmpty(directory))
            {
                Directory.CreateDirectory(directory);
            }

            using (var stream = new FileStream(temporaryPath, FileMode.Create, FileAccess.Write, FileShare.None))
            {
                stream.Write(bytes);
                stream.Flush(flushToDisk: true);
            }

            File.Move(temporaryPath, _filePath, overwrite: true);
            return true;
        }
        catch (Exception exception) when (IsExpectedFileFailure(exception))
        {
            // Read-only profile, antivirus lock, disk full: the window keeps the settings it has in
            // memory for this session.
            TryDelete(temporaryPath);
            return false;
        }
    }

    private void QuarantineInvalidFile()
    {
        try
        {
            File.Move(_filePath, _filePath + InvalidSuffix, overwrite: true);
        }
        catch (Exception exception) when (IsExpectedFileFailure(exception))
        {
            // Best effort only. If the bad file cannot be moved it is overwritten by the next
            // successful update — acceptable for a file that already cannot be read.
        }
    }

    private HeldLock? AcquireLock()
    {
        Mutex mutex;
        try
        {
            mutex = new Mutex(initiallyOwned: false, _mutexName);
        }
        catch (Exception exception) when (exception is UnauthorizedAccessException or IOException
                                              or WaitHandleCannotBeOpenedException)
        {
            return null;
        }

        bool owned;
        try
        {
            owned = mutex.WaitOne(LockTimeout);
        }
        catch (AbandonedMutexException)
        {
            // A window ended while holding it. The file is still whole — every write is one move —
            // so the lock is simply ours now.
            owned = true;
        }

        if (!owned)
        {
            mutex.Dispose();
            return null;
        }

        return new HeldLock(mutex);
    }

    /// <summary>
    /// One mutex per settings file, named from its full path so that windows using the same file —
    /// and only those — share it.
    /// </summary>
    private static string MutexNameFor(string fullPath)
    {
        var hash = SHA256.HashData(Encoding.UTF8.GetBytes(fullPath.ToUpperInvariant()));
        return @"Local\TigerMarkView.Settings." + Convert.ToHexString(hash, 0, 16);
    }

    private static void TryDelete(string path)
    {
        try
        {
            File.Delete(path);
        }
        catch (Exception exception) when (IsExpectedFileFailure(exception))
        {
            // A stray temporary file is harmless; the next successful write replaces it.
        }
    }

    private static bool IsExpectedFileFailure(Exception exception) => exception
        is IOException
        or UnauthorizedAccessException
        or SecurityException
        or NotSupportedException
        or ArgumentException;

    private sealed class HeldLock(Mutex mutex) : IDisposable
    {
        public void Dispose()
        {
            mutex.ReleaseMutex();
            mutex.Dispose();
        }
    }
}
