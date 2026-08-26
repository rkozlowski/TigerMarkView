namespace TigerMarkView.Core.Navigation;

/// <summary>
/// One document in the Back/Forward history.
/// </summary>
/// <remarks>
/// Holds the document's <em>path</em> and the reader's last position in it — never a snapshot of its
/// content. Going Back re-opens the file through the normal pipeline rather than restoring an old
/// rendering, so a historical document is as live (watcher, timestamps, status) as one just opened.
/// </remarks>
public sealed class NavigationEntry(string filePath)
{
    public string FilePath { get; } = filePath;

    /// <summary>
    /// Vertical scroll offset when the reader last left this document, restored on the way back.
    /// Null until the entry has actually been navigated away from.
    /// </summary>
    public double? ScrollY { get; set; }
}
