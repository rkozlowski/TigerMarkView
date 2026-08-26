using System;
using System.IO;
using System.Threading;
using Avalonia.Threading;
using TigerMarkView.Core.Monitoring;

namespace TigerMarkView.Monitoring;

/// <summary>
/// Coordinates a <see cref="FileSystemWatcher"/> for a single open document and applies the pure
/// Core state transitions (<see cref="FileStateTransitions"/>) to keep an up-to-date
/// <see cref="FileViewState"/>. This class owns the noisy-event handling (debouncing, save-by-replace
/// tolerance, missing-file retries, watcher-error recovery) but performs no Markdown rendering or
/// WebView work itself — callers do the actual reload and report the outcome back via
/// <see cref="NotifyReloadSucceeded"/>/<see cref="NotifyReloadFailed"/>.
/// </summary>
public sealed class DocumentWatcher : IDisposable
{
    // Editors commonly emit several Changed/Renamed events per save (write-temp, delete original,
    // rename); coalescing on a short quiet period after the last event avoids reacting to each one.
    private const int DebounceMilliseconds = 300;

    // A save-by-replace sequence can leave the target path briefly missing between the delete and
    // the rename-into-place; retry a couple of times before treating it as a real error.
    private const int MissingFileRetries = 2;
    private const int MissingFileRetryDelayMilliseconds = 150;

    private readonly string _directory;
    private readonly string _fileName;
    private readonly Timer _debounceTimer;
    private FileSystemWatcher? _watcher;
    private volatile bool _disposed;

    public string FilePath { get; }

    public FileViewState State { get; private set; }

    /// <summary>Raised (on the UI thread) whenever <see cref="State"/> changes.</summary>
    public event EventHandler<FileViewState>? StateChanged;

    /// <summary>Raised (on the UI thread) when Automatic mode determines a reload should happen right away.</summary>
    public event EventHandler? ReloadRequested;

    public DocumentWatcher(string filePath, ReloadMode initialMode)
    {
        FilePath = Path.GetFullPath(filePath);
        _directory = Path.GetDirectoryName(FilePath)
            ?? throw new ArgumentException("Path has no containing directory.", nameof(filePath));
        _fileName = Path.GetFileName(FilePath);
        State = FileViewState.Initial(FilePath, initialMode);
        _debounceTimer = new Timer(_ => RecheckFile(), null, Timeout.Infinite, Timeout.Infinite);

        StartWatcher();
    }

    public void SetReloadMode(ReloadMode mode) => UpdateState(FileStateTransitions.WithReloadMode(State, mode));

    /// <summary>Called by the UI after it has successfully read, rendered, and displayed the file.</summary>
    public void NotifyReloadSucceeded(DateTime versionTimestampUtc, DateTime reloadTimeUtc) =>
        UpdateState(FileStateTransitions.ReloadSucceeded(State, versionTimestampUtc, reloadTimeUtc));

    /// <summary>Called by the UI when a reload attempt fails (read error, render error, etc).</summary>
    public void NotifyReloadFailed(string errorMessage) =>
        UpdateState(FileStateTransitions.WithError(State, errorMessage));

    private void StartWatcher()
    {
        _watcher?.Dispose();
        _watcher = null;

        try
        {
            var watcher = new FileSystemWatcher(_directory)
            {
                // Watch every entry in the directory, not just an exact-name filter: rename/replace
                // sequences (temp-file save patterns) need to be seen even when the intermediate name
                // differs from the target file name.
                Filter = "*",
                NotifyFilter = NotifyFilters.LastWrite | NotifyFilters.FileName | NotifyFilters.Size,
            };
            watcher.Changed += OnWatcherEvent;
            watcher.Created += OnWatcherEvent;
            watcher.Renamed += OnWatcherRenamed;
            watcher.Deleted += OnWatcherEvent;
            watcher.Error += OnWatcherError;
            watcher.EnableRaisingEvents = true;
            _watcher = watcher;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ArgumentException)
        {
            UpdateState(FileStateTransitions.WithError(State, $"Cannot monitor folder: {ex.Message}"));
        }
    }

    private void OnWatcherEvent(object sender, FileSystemEventArgs e)
    {
        if (string.Equals(e.Name, _fileName, StringComparison.OrdinalIgnoreCase))
        {
            ScheduleRecheck();
        }
    }

    private void OnWatcherRenamed(object sender, RenamedEventArgs e)
    {
        if (string.Equals(e.Name, _fileName, StringComparison.OrdinalIgnoreCase) ||
            string.Equals(e.OldName, _fileName, StringComparison.OrdinalIgnoreCase))
        {
            ScheduleRecheck();
        }
    }

    private void OnWatcherError(object sender, ErrorEventArgs e)
    {
        // Typically an internal buffer overflow under a burst of events. Rebuild the watcher (it may
        // have stopped raising events) and immediately re-check in case changes were missed.
        if (_disposed)
        {
            return;
        }

        StartWatcher();
        ScheduleRecheck();
    }

    private void ScheduleRecheck()
    {
        if (!_disposed)
        {
            _debounceTimer.Change(DebounceMilliseconds, Timeout.Infinite);
        }
    }

    private void RecheckFile()
    {
        if (_disposed)
        {
            return;
        }

        for (var attempt = 0; attempt <= MissingFileRetries; attempt++)
        {
            try
            {
                if (File.Exists(FilePath))
                {
                    var diskTimestampUtc = File.GetLastWriteTimeUtc(FilePath);
                    if (diskTimestampUtc != State.DiskTimestampUtc || State.HasError)
                    {
                        UpdateState(FileStateTransitions.ObserveDiskTimestamp(State, diskTimestampUtc));
                        RequestReloadIfAutomatic();
                    }

                    return;
                }
            }
            catch (IOException)
            {
                // File is mid-write/replace and momentarily locked — fall through to retry.
            }

            if (attempt < MissingFileRetries)
            {
                Thread.Sleep(MissingFileRetryDelayMilliseconds);
            }
        }

        UpdateState(FileStateTransitions.WithError(State, "File not found."));
    }

    private void RequestReloadIfAutomatic()
    {
        if (ReloadModeAdvisor.Decide(State.ReloadMode) == ReloadDecision.ReloadNow)
        {
            Dispatcher.UIThread.Post(() => ReloadRequested?.Invoke(this, EventArgs.Empty));
        }
    }

    private void UpdateState(FileViewState newState)
    {
        State = newState;
        Dispatcher.UIThread.Post(() => StateChanged?.Invoke(this, State));
    }

    public void Dispose()
    {
        _disposed = true;
        _debounceTimer.Dispose();
        _watcher?.Dispose();
    }
}
