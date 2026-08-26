namespace TigerMarkView.Core.Settings;

/// <summary>
/// Ordering/deduplication rules for the recent-files list. Pure list manipulation — no filesystem
/// access, no history database: entries are kept exactly as opened and are never probed for
/// existence here, so a temporarily unavailable network path does not silently vanish from the menu.
/// </summary>
public static class RecentFilesList
{
    public const int DefaultMaximum = 10;

    /// <summary>Windows paths are case-insensitive; comparing otherwise would let one file appear twice.</summary>
    private static readonly StringComparer PathComparer = StringComparer.OrdinalIgnoreCase;

    /// <summary>
    /// Returns <paramref name="existing"/> with <paramref name="path"/> moved (or added) to the front
    /// and the list trimmed to <paramref name="maximum"/> entries.
    /// </summary>
    public static List<string> Add(IEnumerable<string>? existing, string path, int maximum = DefaultMaximum)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);

        var result = new List<string> { path };
        result.AddRange(existing ?? []);

        return Normalize(result, maximum);
    }

    /// <summary>
    /// Drops blank entries and later duplicates (keeping the earliest, i.e. most recent, occurrence)
    /// and trims to <paramref name="maximum"/>. Also used when loading settings, where the file may
    /// have been hand-edited into a shape the app never writes.
    /// </summary>
    public static List<string> Normalize(IEnumerable<string?>? entries, int maximum = DefaultMaximum)
    {
        var result = new List<string>();
        if (entries is null || maximum <= 0)
        {
            return result;
        }

        var seen = new HashSet<string>(PathComparer);

        foreach (var entry in entries)
        {
            if (string.IsNullOrWhiteSpace(entry) || !seen.Add(entry))
            {
                continue;
            }

            result.Add(entry);
            if (result.Count == maximum)
            {
                break;
            }
        }

        return result;
    }
}
