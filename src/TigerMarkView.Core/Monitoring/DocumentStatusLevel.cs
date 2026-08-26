namespace TigerMarkView.Core.Monitoring;

/// <summary>
/// Status-bar indicator level. Ordinal order matches display priority, but
/// <see cref="FileViewState.GetStatusLevel"/> is what actually applies the
/// Error &gt; NewerOnDisk &gt; RecentlyReloaded &gt; Neutral priority rule.
/// </summary>
public enum DocumentStatusLevel
{
    Neutral,
    RecentlyReloaded,
    NewerOnDisk,
    Error,
}
