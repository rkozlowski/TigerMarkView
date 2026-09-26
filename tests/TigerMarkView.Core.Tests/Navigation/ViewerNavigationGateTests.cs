using TigerMarkView.Core.Navigation;

namespace TigerMarkView.Core.Tests.Navigation;

/// <summary>
/// Nothing is shown in a document WebView without its request boundary: requests wait for it, and a
/// boundary that cannot be installed closes the view for good rather than letting documents through
/// unprotected.
/// </summary>
public class ViewerNavigationGateTests
{
    private static readonly Uri First = new("file:///C:/Temp/TigerMarkView/preview.html?t=1");
    private static readonly Uri Second = new("file:///C:/Temp/TigerMarkView/preview.html?t=2");

    [Fact]
    public void ARequestBeforeTheBoundaryIsHeldAndReleasedOnceItIsInstalled()
    {
        var gate = new ViewerNavigationGate();

        Assert.Null(gate.Request(First));
        Assert.Equal(ViewerBoundaryState.Pending, gate.State);

        Assert.Equal(First, gate.BoundaryInstalled());
        Assert.Equal(ViewerBoundaryState.Protected, gate.State);
    }

    [Fact]
    public void OnlyTheLatestHeldRequestIsReleased()
    {
        var gate = new ViewerNavigationGate();

        gate.Request(First);
        gate.Request(Second);

        Assert.Equal(Second, gate.BoundaryInstalled());
    }

    [Fact]
    public void RequestsGoStraightThroughOnceProtected()
    {
        var gate = new ViewerNavigationGate();
        gate.BoundaryInstalled();

        Assert.Equal(First, gate.Request(First));
    }

    [Fact]
    public void AFailedBoundaryRefusesTheHeldRequestAndEveryLaterOne()
    {
        var gate = new ViewerNavigationGate();
        gate.Request(First);

        gate.BoundaryUnavailable("The viewer engine is not Microsoft Edge WebView2.");

        Assert.Equal(ViewerBoundaryState.Unavailable, gate.State);
        Assert.Equal("The viewer engine is not Microsoft Edge WebView2.", gate.UnavailableReason);
        Assert.Null(gate.Request(Second));
    }

    /// <summary>
    /// A re-created engine that fails closes a view that was protected until then: documents already
    /// shown were protected, the next one would not be.
    /// </summary>
    [Fact]
    public void AFailureAfterProtectionStillClosesTheView()
    {
        var gate = new ViewerNavigationGate();
        gate.BoundaryInstalled();

        gate.BoundaryUnavailable("Installing the request filter failed.");

        Assert.Null(gate.Request(First));
    }

    /// <summary>Closed stays closed: a later success does not reopen a view the reader was told was off.</summary>
    [Fact]
    public void ALaterSuccessDoesNotReopenAClosedView()
    {
        var gate = new ViewerNavigationGate();
        gate.BoundaryUnavailable("Installing the request filter failed.");

        Assert.Null(gate.BoundaryInstalled());
        Assert.Equal(ViewerBoundaryState.Unavailable, gate.State);
        Assert.Null(gate.Request(First));
    }
}
