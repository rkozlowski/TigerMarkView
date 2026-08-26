using TigerMarkView.Core.Navigation;

namespace TigerMarkView.Core.Tests.Navigation;

/// <summary>
/// The Back/Forward semantics, modelled separately from the viewer so they can be asserted without a
/// window. The operations that must <em>not</em> create history (reload, theme change, PDF export) are
/// covered by the fact that they never call <see cref="NavigationHistory.Navigate"/> at all — the last
/// test here pins that down from this side by showing repeated work on one document adds nothing.
/// </summary>
public class NavigationHistoryTests
{
    private const string A = @"C:\docs\a.md";
    private const string B = @"C:\docs\b.md";
    private const string C = @"C:\docs\c.md";
    private const string D = @"C:\docs\d.md";

    [Fact]
    public void AFreshHistoryHasNothingToShowAndNowhereToGo()
    {
        var history = new NavigationHistory();

        Assert.Null(history.Current);
        Assert.False(history.CanGoBack);
        Assert.False(history.CanGoForward);
    }

    [Fact]
    public void TheFirstNavigationBecomesTheInitialEntry()
    {
        var history = new NavigationHistory();

        history.Navigate(A);

        Assert.Equal(A, history.Current!.FilePath);
        Assert.Single(history.Entries);

        // An initial entry is a place to come back to, not somewhere to go back from.
        Assert.False(history.CanGoBack);
        Assert.False(history.CanGoForward);
    }

    [Fact]
    public void BackWalksTheChainInReverse()
    {
        var history = NavigateAll(A, B, C);

        Assert.Equal(C, history.Current!.FilePath);
        Assert.True(history.CanGoBack);

        Assert.Equal(B, history.GoBack()!.FilePath);
        Assert.Equal(A, history.GoBack()!.FilePath);

        Assert.False(history.CanGoBack);
        Assert.Null(history.GoBack());
        Assert.Equal(A, history.Current!.FilePath);
    }

    [Fact]
    public void ForwardRetracesWhatBackUndid()
    {
        var history = NavigateAll(A, B, C);
        history.GoBack();
        history.GoBack();

        Assert.True(history.CanGoForward);
        Assert.Equal(B, history.GoForward()!.FilePath);
        Assert.Equal(C, history.GoForward()!.FilePath);

        Assert.False(history.CanGoForward);
        Assert.Null(history.GoForward());
        Assert.Equal(C, history.Current!.FilePath);
    }

    /// <summary>
    /// The branching rule from the phase brief: A → B → C, Back to B, then open D — C is gone.
    /// </summary>
    [Fact]
    public void NavigatingAfterGoingBackDiscardsTheForwardHistory()
    {
        var history = NavigateAll(A, B, C);
        history.GoBack();

        Assert.Equal(B, history.Current!.FilePath);
        Assert.True(history.CanGoForward);

        history.Navigate(D);

        Assert.Equal(D, history.Current!.FilePath);
        Assert.False(history.CanGoForward);
        Assert.Equal([A, B, D], history.Entries.Select(entry => entry.FilePath));

        // Back still works normally along the new branch.
        Assert.Equal(B, history.GoBack()!.FilePath);
    }

    [Fact]
    public void ReopeningTheCurrentDocumentIsNotANewEntry()
    {
        var history = NavigateAll(A, B);

        history.Navigate(B);

        Assert.Equal(2, history.Entries.Count);
        Assert.Equal(B, history.Current!.FilePath);
    }

    /// <summary>
    /// Re-opening the current document is a reload in all but name, so it must not quietly throw away
    /// a Forward branch the reader can still see in the menu.
    /// </summary>
    [Fact]
    public void ReopeningTheCurrentDocumentKeepsTheForwardHistory()
    {
        var history = NavigateAll(A, B, C);
        history.GoBack();

        history.Navigate(B);

        Assert.True(history.CanGoForward);
        Assert.Equal(C, history.GoForward()!.FilePath);
    }

    [Fact]
    public void PathsAreComparedTheWayWindowsComparesThem()
    {
        var history = NavigateAll(A);

        history.Navigate(@"C:\DOCS\A.MD");

        Assert.Single(history.Entries);
    }

    [Fact]
    public void EachEntryRemembersWhereItsReaderHadScrolledTo()
    {
        var history = new NavigationHistory();
        history.Navigate(A);

        history.RecordScrollPosition(1200);
        history.Navigate(B);
        history.RecordScrollPosition(340);

        // Back lands on A where A was left...
        Assert.Equal(1200d, history.GoBack()!.ScrollY);

        // ...and Forward lands on B where B was left.
        Assert.Equal(340d, history.GoForward()!.ScrollY);
    }

    /// <summary>
    /// A position that could not be read (the page was not ready) must not erase a good one already
    /// recorded — losing the reader's place is worse than restoring a slightly stale one.
    /// </summary>
    [Fact]
    public void AnUnreadablePositionLeavesTheRecordedOneAlone()
    {
        var history = new NavigationHistory();
        history.Navigate(A);
        history.RecordScrollPosition(900);

        history.RecordScrollPosition(null);

        Assert.Equal(900d, history.Current!.ScrollY);
    }

    [Fact]
    public void ANewEntryHasNoRememberedPosition()
    {
        var history = NavigateAll(A);

        Assert.Null(history.Current!.ScrollY);
    }

    [Fact]
    public void TheOldestEntriesAreDroppedOnceCapacityIsReached()
    {
        var history = new NavigationHistory(capacity: 3);

        history.Navigate(A);
        history.Navigate(B);
        history.Navigate(C);
        history.Navigate(D);

        Assert.Equal([B, C, D], history.Entries.Select(entry => entry.FilePath));
        Assert.Equal(D, history.Current!.FilePath);

        // The index must have moved with the trim, not been left pointing at the wrong document.
        Assert.Equal(C, history.GoBack()!.FilePath);
        Assert.Equal(B, history.GoBack()!.FilePath);
        Assert.False(history.CanGoBack);
    }

    /// <summary>
    /// The rule the history list depends on: picking an old entry <em>moves the cursor</em>. With
    /// A → B → C → D and D current, choosing B must leave the trail intact and C and D still ahead —
    /// not append a second B and throw the Forward branch away, which is what calling Navigate would.
    /// </summary>
    [Fact]
    public void SelectingAnEarlierEntryMovesTheCursorWithoutAppending()
    {
        var history = NavigateAll(A, B, C, D);

        var entry = history.GoTo(1);

        Assert.Equal(B, entry!.FilePath);
        Assert.Equal(B, history.Current!.FilePath);
        Assert.Equal(1, history.CurrentIndex);

        // Nothing was added, and nothing ahead was discarded.
        Assert.Equal([A, B, C, D], history.Entries.Select(e => e.FilePath));

        Assert.True(history.CanGoBack);
        Assert.True(history.CanGoForward);

        // Forward retraces the branch that is still there.
        Assert.Equal(C, history.GoForward()!.FilePath);
        Assert.Equal(D, history.GoForward()!.FilePath);
        Assert.False(history.CanGoForward);
    }

    [Fact]
    public void SelectingTheFirstEntryLeavesNothingBehindItAndEverythingAhead()
    {
        var history = NavigateAll(A, B, C, D);

        Assert.Equal(A, history.GoTo(0)!.FilePath);

        Assert.Equal(0, history.CurrentIndex);
        Assert.False(history.CanGoBack);
        Assert.True(history.CanGoForward);
        Assert.Equal(4, history.Entries.Count);
    }

    [Fact]
    public void SelectingTheLastEntryLeavesNothingAhead()
    {
        var history = NavigateAll(A, B, C, D);
        history.GoTo(0);

        Assert.Equal(D, history.GoTo(3)!.FilePath);

        Assert.Equal(3, history.CurrentIndex);
        Assert.True(history.CanGoBack);
        Assert.False(history.CanGoForward);
    }

    [Fact]
    public void SelectingTheCurrentEntryChangesNothing()
    {
        var history = NavigateAll(A, B, C, D);

        Assert.Equal(D, history.GoTo(3)!.FilePath);

        Assert.Equal(3, history.CurrentIndex);
        Assert.Equal([A, B, C, D], history.Entries.Select(e => e.FilePath));
        Assert.True(history.CanGoBack);
        Assert.False(history.CanGoForward);
    }

    /// <summary>
    /// A history list can outlive the trail it was drawn from — capacity trimming, or a branch
    /// discarded by a navigation in between. An out-of-range pick leaves the reader where they are
    /// rather than throwing at them.
    /// </summary>
    [Theory]
    [InlineData(-1)]
    [InlineData(4)]
    [InlineData(int.MaxValue)]
    public void SelectingAnEntryThatIsNotThereLeavesTheCursorAlone(int index)
    {
        var history = NavigateAll(A, B, C, D);

        Assert.Null(history.GoTo(index));

        Assert.Equal(D, history.Current!.FilePath);
        Assert.Equal(3, history.CurrentIndex);
        Assert.Equal(4, history.Entries.Count);
    }

    [Fact]
    public void SelectingAnEntryRestoresWhereItsReaderHadScrolledTo()
    {
        var history = new NavigationHistory();
        history.Navigate(A);
        history.RecordScrollPosition(1500);
        history.Navigate(B);
        history.RecordScrollPosition(250);
        history.Navigate(C);

        // The position travels with the entry, so a history pick lands where Back would have.
        Assert.Equal(1500d, history.GoTo(0)!.ScrollY);
        Assert.Equal(250d, history.GoTo(1)!.ScrollY);
    }

    [Fact]
    public void AnEmptyHistoryHasNoCurrentIndexAndNothingToSelect()
    {
        var history = new NavigationHistory();

        Assert.Equal(-1, history.CurrentIndex);
        Assert.Null(history.GoTo(0));
    }

    [Fact]
    public void ANonPathIsRejectedRatherThanStored()
    {
        var history = new NavigationHistory();

        Assert.Throws<ArgumentException>(() => history.Navigate("   "));
        Assert.Throws<ArgumentNullException>(() => history.Navigate(null!));
    }

    private static NavigationHistory NavigateAll(params string[] paths)
    {
        var history = new NavigationHistory();
        foreach (var path in paths)
        {
            history.Navigate(path);
        }

        return history;
    }
}
