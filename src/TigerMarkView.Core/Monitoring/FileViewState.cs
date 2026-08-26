namespace TigerMarkView.Core.Monitoring;

/// <summary>
/// Immutable snapshot of a monitored document's freshness. Three timestamps are tracked
/// separately and must never be collapsed into one value:
/// <list type="bullet">
/// <item><see cref="RenderedTimestampUtc"/> — mtime of the version currently rendered/displayed.</item>
/// <item><see cref="DiskTimestampUtc"/> — mtime of the file currently on disk.</item>
/// <item><see cref="LastReloadTimestampUtc"/> — wall-clock time TigerMarkView last successfully reloaded.</item>
/// </list>
/// All timestamps are UTC; convert to local time only for display.
/// </summary>
public sealed record FileViewState(
    string FilePath,
    DateTime? RenderedTimestampUtc,
    DateTime? DiskTimestampUtc,
    DateTime? LastReloadTimestampUtc,
    ReloadMode ReloadMode,
    string? ErrorMessage = null)
{
    /// <summary>README: green "recently reloaded" state lasts approximately five minutes.</summary>
    public static readonly TimeSpan DefaultRecentReloadWindow = TimeSpan.FromMinutes(5);

    public static FileViewState Initial(string filePath, ReloadMode reloadMode) =>
        new(filePath, RenderedTimestampUtc: null, DiskTimestampUtc: null, LastReloadTimestampUtc: null, reloadMode);

    public bool HasError => ErrorMessage is not null;

    public bool IsNewerOnDisk =>
        DiskTimestampUtc is { } disk && RenderedTimestampUtc is { } rendered && disk > rendered;

    /// <summary>Applies the README state priority: Error &gt; NewerOnDisk &gt; RecentlyReloaded &gt; Neutral.</summary>
    public DocumentStatusLevel GetStatusLevel(DateTime nowUtc, TimeSpan? recentReloadWindow = null)
    {
        if (HasError)
        {
            return DocumentStatusLevel.Error;
        }

        if (IsNewerOnDisk)
        {
            return DocumentStatusLevel.NewerOnDisk;
        }

        var window = recentReloadWindow ?? DefaultRecentReloadWindow;
        if (LastReloadTimestampUtc is { } lastReload && nowUtc >= lastReload && nowUtc - lastReload <= window)
        {
            return DocumentStatusLevel.RecentlyReloaded;
        }

        return DocumentStatusLevel.Neutral;
    }
}
