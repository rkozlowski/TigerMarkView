namespace TigerMarkView.Core.Navigation;

/// <summary>
/// Why a document is being shown. Every route into the viewer's one opening path carries this, because
/// the two lists TigerMarkView keeps about documents answer different questions and must not be fed
/// from the same signal.
/// </summary>
/// <remarks>
/// <para>
/// <strong>Open Recent</strong> is a persisted list of <em>entry points</em> — places the reader
/// deliberately went to from outside the document being read. <strong>Navigation history</strong> is
/// the session's browsing trail, including everywhere a link happened to lead. Following
/// <c>[B](b.md)</c> therefore must not put B in Open Recent unless the reader explicitly opens it.
/// </para>
/// <para>
/// Deliberately an enum rather than a pair of <c>addToRecent</c>/<c>addToHistory</c> flags. The call
/// sites state <em>what happened</em>, and the policy for each list is decided in one place
/// (<see cref="Settings.RecentFilesPolicy"/>), so a fourth route cannot quietly pick the wrong
/// combination of booleans.
/// </para>
/// </remarks>
public enum DocumentOpenOrigin
{
    /// <summary>
    /// The reader named this document from outside it: File &gt; Open, a drop, the command-line
    /// argument, or an Open Recent entry. The only origin that belongs in Open Recent.
    /// </summary>
    ExplicitOpen,

    /// <summary>
    /// Reached from within the document being read — a click on a local Markdown link. A genuine
    /// navigation, so it joins the history trail, but it is not an entry point.
    /// </summary>
    Navigation,

    /// <summary>
    /// Movement along the trail that already exists: Back, Forward, or a pick from the history list.
    /// Adds nothing to either list — the cursor moves over entries that are already there.
    /// </summary>
    HistoryTraversal,
}
