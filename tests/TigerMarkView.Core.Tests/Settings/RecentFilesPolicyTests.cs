using TigerMarkView.Core.Navigation;
using TigerMarkView.Core.Settings;

namespace TigerMarkView.Core.Tests.Settings;

/// <summary>
/// What <c>File &gt; Open Recent</c> is a list <em>of</em>.
/// </summary>
/// <remarks>
/// <para>
/// Explicit entry points and browsing navigation have different recent-file policies, so following
/// <c>[B](b.md)</c> does not add B to Open Recent unless the reader explicitly opens it.
/// </para>
/// <para>
/// The viewer itself is an Avalonia window and cannot be unit tested, so the rule it consults lives in
/// Core (<see cref="RecentFilesPolicy"/>) and the scenarios below drive a
/// <see cref="Viewer"/> stand-in that calls it exactly where <c>MainWindow.AttachDocument</c> does.
/// The stand-in is deliberately thin: the point is the routing decision, not a re-implementation of
/// the window.
/// </para>
/// </remarks>
public class RecentFilesPolicyTests
{
    private const string A = @"C:\docs\a.md";
    private const string B = @"C:\docs\b.md";
    private const string C = @"C:\docs\c.md";
    private const string D = @"C:\docs\d.md";
    private const string E = @"C:\docs\e.md";
    private const string F = @"C:\docs\f.md";

    [Theory]
    [InlineData(DocumentOpenOrigin.ExplicitOpen, true)]
    [InlineData(DocumentOpenOrigin.Navigation, false)]
    [InlineData(DocumentOpenOrigin.HistoryTraversal, false)]
    public void OnlyAnExplicitOpenIsRemembered(DocumentOpenOrigin origin, bool expected) =>
        Assert.Equal(expected, RecentFilesPolicy.ShouldRemember(origin));

    // --- the entry points: everything that should reach Open Recent -----------------------------

    [Fact]
    public void FileOpenAddsTheDocument()
    {
        var viewer = new Viewer();

        viewer.Open(A, DocumentOpenOrigin.ExplicitOpen);

        Assert.Equal([A], viewer.Recent);
    }

    /// <summary>A drop is the reader handing the viewer a document, so it is an entry point.</summary>
    [Fact]
    public void DragAndDropAddsTheDocument()
    {
        var viewer = new Viewer();

        viewer.Open(E, DocumentOpenOrigin.ExplicitOpen);

        Assert.Equal([E], viewer.Recent);
    }

    /// <summary>Naming a file on the command line is choosing it just as File &gt; Open is.</summary>
    [Fact]
    public void TheCommandLineDocumentAddsTheDocument()
    {
        var viewer = new Viewer();

        viewer.Open(A, DocumentOpenOrigin.ExplicitOpen);

        Assert.Equal([A], viewer.Recent);
    }

    /// <summary>
    /// Choosing an entry point again is still choosing it, so it moves back to the top — the ordinary
    /// most-recently-used behaviour, unchanged by this pass.
    /// </summary>
    [Fact]
    public void ChoosingAnOpenRecentEntryPromotesItToTheTop()
    {
        var viewer = new Viewer();
        viewer.Open(A, DocumentOpenOrigin.ExplicitOpen);
        viewer.Open(E, DocumentOpenOrigin.ExplicitOpen);

        Assert.Equal([E, A], viewer.Recent);

        viewer.Open(A, DocumentOpenOrigin.ExplicitOpen);

        Assert.Equal([A, E], viewer.Recent);
    }

    // --- the routes that must NOT reach Open Recent ---------------------------------------------

    /// <summary>
    /// The headline case: B joins the session's trail and is reachable with Back, but the reader never
    /// chose it — they clicked a link inside A.
    /// </summary>
    [Fact]
    public void FollowingALocalLinkJoinsTheTrailButNotOpenRecent()
    {
        var viewer = new Viewer();
        viewer.Open(A, DocumentOpenOrigin.ExplicitOpen);

        viewer.Open(B, DocumentOpenOrigin.Navigation);

        Assert.Equal([A], viewer.Recent);
        Assert.Equal([A, B], viewer.Trail);
        Assert.Equal(B, viewer.Current);
    }

    [Fact]
    public void BackAndForwardLeaveOpenRecentAlone()
    {
        var viewer = new Viewer();
        viewer.Open(A, DocumentOpenOrigin.ExplicitOpen);
        viewer.Open(B, DocumentOpenOrigin.Navigation);
        viewer.Open(C, DocumentOpenOrigin.Navigation);

        viewer.Back();
        viewer.Back();
        viewer.Forward();

        Assert.Equal([A], viewer.Recent);
        Assert.Equal(B, viewer.Current);
    }

    [Fact]
    public void PickingFromTheHistoryListLeavesOpenRecentAlone()
    {
        var viewer = new Viewer();
        viewer.Open(A, DocumentOpenOrigin.ExplicitOpen);
        viewer.Open(B, DocumentOpenOrigin.Navigation);
        viewer.Open(C, DocumentOpenOrigin.Navigation);
        viewer.Open(D, DocumentOpenOrigin.Navigation);

        viewer.PickFromHistory(1);

        Assert.Equal([A], viewer.Recent);
        Assert.Equal(B, viewer.Current);

        // And the pick was a cursor move, so the rest of the trail is still ahead.
        Assert.Equal([A, B, C, D], viewer.Trail);
    }

    // --- the whole story, and what survives a restart --------------------------------------------

    /// <summary>
    /// The brief's end-to-end scenario: open A explicitly, wander to B/C/D by link, drop E, follow a
    /// link to F. Open Recent should hold exactly the two documents the reader chose, and the trail
    /// should hold everywhere they went.
    /// </summary>
    [Fact]
    public void OnlyChosenDocumentsAccumulateWhileTheTrailKeepsEverywhereVisited()
    {
        var viewer = new Viewer();

        viewer.Open(A, DocumentOpenOrigin.ExplicitOpen);
        viewer.Open(B, DocumentOpenOrigin.Navigation);
        viewer.Open(C, DocumentOpenOrigin.Navigation);
        viewer.Open(D, DocumentOpenOrigin.Navigation);
        viewer.Open(E, DocumentOpenOrigin.ExplicitOpen);
        viewer.Open(F, DocumentOpenOrigin.Navigation);

        Assert.Equal([E, A], viewer.Recent);
        Assert.Equal([A, B, C, D, E, F], viewer.Trail);
    }

    /// <summary>
    /// Open Recent is the persisted list, so the distinction has to survive a round trip through the
    /// settings file — the navigation trail is session-only and is not written at all.
    /// </summary>
    [Fact]
    public void OnlyExplicitOpensSurviveARestart()
    {
        var viewer = new Viewer();
        viewer.Open(A, DocumentOpenOrigin.ExplicitOpen);
        viewer.Open(B, DocumentOpenOrigin.Navigation);
        viewer.Open(E, DocumentOpenOrigin.ExplicitOpen);
        viewer.Open(F, DocumentOpenOrigin.Navigation);

        var reloaded = ApplicationSettingsSerializer.Deserialize(
            ApplicationSettingsSerializer.Serialize(viewer.Settings));

        Assert.Equal([E, A], reloaded.RecentFiles);
    }

    /// <summary>
    /// The two lists the viewer keeps, driven the way <c>MainWindow</c> drives them: every route calls
    /// <see cref="Open"/> with the origin that describes it, and the recent list is written only when
    /// <see cref="RecentFilesPolicy"/> says so — the same question <c>AttachDocument</c> asks for every
    /// route, traversals included.
    /// </summary>
    private sealed class Viewer
    {
        private readonly NavigationHistory _history = new();

        public ApplicationSettings Settings { get; } = ApplicationSettings.CreateDefault();

        public IReadOnlyList<string> Recent => Settings.RecentFiles;

        public IEnumerable<string> Trail => _history.Entries.Select(entry => entry.FilePath);

        public string? Current => _history.Current?.FilePath;

        public void Open(string path, DocumentOpenOrigin origin)
        {
            _history.Navigate(path);
            Attach(path, origin);
        }

        public void Back() => Traverse(_history.GoBack());

        public void Forward() => Traverse(_history.GoForward());

        public void PickFromHistory(int index) => Traverse(_history.GoTo(index));

        private void Traverse(NavigationEntry? entry)
        {
            if (entry is not null)
            {
                Attach(entry.FilePath, DocumentOpenOrigin.HistoryTraversal);
            }
        }

        private void Attach(string path, DocumentOpenOrigin origin)
        {
            if (RecentFilesPolicy.ShouldRemember(origin))
            {
                Settings.AddRecentFile(path);
            }
        }
    }
}
