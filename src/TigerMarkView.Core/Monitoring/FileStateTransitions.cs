namespace TigerMarkView.Core.Monitoring;

/// <summary>
/// Pure state transitions for <see cref="FileViewState"/>. Kept free of FileSystemWatcher/IO so it is
/// callable and testable without any real filesystem — callers pass in already-observed timestamps.
/// </summary>
public static class FileStateTransitions
{
    /// <summary>The watcher observed a (possibly new) mtime for the file on disk.</summary>
    public static FileViewState ObserveDiskTimestamp(FileViewState state, DateTime diskTimestampUtc) =>
        state with { DiskTimestampUtc = diskTimestampUtc, ErrorMessage = null };

    /// <summary>
    /// A reload finished successfully: the rendered version now matches the disk version just read,
    /// so both timestamps converge on <paramref name="versionTimestampUtc"/> and the stale/newer state clears.
    /// </summary>
    public static FileViewState ReloadSucceeded(FileViewState state, DateTime versionTimestampUtc, DateTime reloadTimeUtc) =>
        state with
        {
            RenderedTimestampUtc = versionTimestampUtc,
            DiskTimestampUtc = versionTimestampUtc,
            LastReloadTimestampUtc = reloadTimeUtc,
            ErrorMessage = null,
        };

    /// <summary>
    /// A reload attempt (or a watcher recheck that found the file unavailable) failed. Only the error
    /// message changes — rendered/disk/reload timestamps are left exactly as they were, so a failure
    /// never falsely advances the document's version.
    /// </summary>
    public static FileViewState WithError(FileViewState state, string errorMessage) =>
        state with { ErrorMessage = errorMessage };

    public static FileViewState WithReloadMode(FileViewState state, ReloadMode mode) =>
        state with { ReloadMode = mode };
}
