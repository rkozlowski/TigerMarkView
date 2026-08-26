using TigerMarkView.Core.Printing;

namespace TigerMarkView.Core.Tests.Printing;

/// <summary>
/// When a finished print may pull TigerMarkView back to the front. The rule has to be right in both
/// directions: a reader who never left must not be abandoned behind the window a printer driver put
/// up, and a reader who deliberately walked to another application must not be interrupted.
/// </summary>
public class PrintActivationTests
{
    [Fact]
    public void ForegroundIsTakenBackWhenThePrintStartedInTigerMarkViewAndSomethingElseNowHasIt()
    {
        Assert.True(PrintActivation.ShouldRestoreForeground(ownedForegroundBefore: true, ownsForegroundNow: false));
    }

    /// <summary>
    /// The condition that keeps this from being focus stealing: the reader was somewhere else when
    /// they set the print going — a background print must stay in the background.
    /// </summary>
    [Fact]
    public void ForegroundIsNeverTakenWhenTigerMarkViewDidNotHaveItToBeginWith()
    {
        Assert.False(PrintActivation.ShouldRestoreForeground(ownedForegroundBefore: false, ownsForegroundNow: false));
        Assert.False(PrintActivation.ShouldRestoreForeground(ownedForegroundBefore: false, ownsForegroundNow: true));
    }

    /// <summary>
    /// Windows restores activation to the owner by itself when the print dialog is simply cancelled.
    /// Nothing is done in that case — an <c>Activate</c> on a window that is already active is a
    /// pointless flicker at best.
    /// </summary>
    [Fact]
    public void NothingIsDoneWhenWindowsAlreadyRestoredTheForeground()
    {
        Assert.False(PrintActivation.ShouldRestoreForeground(ownedForegroundBefore: true, ownsForegroundNow: true));
    }
}
