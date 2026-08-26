using TigerMarkView.Core.Windowing;

namespace TigerMarkView.Core.Tests.Windowing;

/// <summary>
/// The rule that keeps a restored window reachable. The bug behind it was concrete: a saved window
/// taller than the screen came back with its title bar above the top edge, so it could be neither
/// moved nor closed.
/// </summary>
public class WindowPlacementCalculatorTests
{
    /// <summary>A 1920×1080 display with a 40px taskbar along the bottom.</summary>
    private static readonly ScreenArea Primary = new(0, 0, 1920, 1040);

    /// <summary>A second display arranged to the right, as Windows commonly reports it.</summary>
    private static readonly ScreenArea Secondary = new(1920, 0, 1280, 984);

    private static readonly ScreenArea[] OneScreen = [Primary];
    private static readonly ScreenArea[] TwoScreens = [Primary, Secondary];

    [Fact]
    public void GeometryThatAlreadyFitsIsLeftExactlyAsItIs()
    {
        var fit = WindowPlacementCalculator.Fit(100, 80, 1100, 850, OneScreen);

        Assert.Equal(100, fit.X);
        Assert.Equal(80, fit.Y);
        Assert.Equal(1100, fit.Width);
        Assert.Equal(850, fit.Height);
        Assert.False(fit.Changed);
    }

    [Fact]
    public void AWindowTallerThanTheWorkingAreaIsShortenedAndPulledToTheTop()
    {
        var fit = WindowPlacementCalculator.Fit(100, -200, 1100, 1400, OneScreen);

        Assert.Equal(1040, fit.Height);
        Assert.Equal(0, fit.Y);
        Assert.Equal(100, fit.X);
        Assert.True(fit.Changed);
    }

    [Fact]
    public void AWindowWiderThanTheWorkingAreaIsNarrowed()
    {
        var fit = WindowPlacementCalculator.Fit(0, 0, 2400, 800, OneScreen);

        Assert.Equal(1920, fit.Width);
        Assert.Equal(0, fit.X);
        Assert.True(fit.Changed);
    }

    /// <summary>
    /// The exact reported failure: the title bar must come back on screen, not merely "most of" the
    /// window.
    /// </summary>
    [Fact]
    public void AWindowHangingOffTheTopIsBroughtFullyBackIntoView()
    {
        var fit = WindowPlacementCalculator.Fit(300, -120, 900, 700, OneScreen);

        Assert.Equal(0, fit.Y);
        Assert.Equal(300, fit.X);
        Assert.Equal(700, fit.Height);
        Assert.True(fit.Changed);
    }

    [Fact]
    public void AWindowHangingOffTheLeftIsPushedRight()
    {
        var fit = WindowPlacementCalculator.Fit(-300, 100, 900, 700, OneScreen);

        Assert.Equal(0, fit.X);
        Assert.Equal(100, fit.Y);
        Assert.True(fit.Changed);
    }

    [Fact]
    public void AWindowHangingOffTheRightIsPulledBack()
    {
        var fit = WindowPlacementCalculator.Fit(1500, 100, 900, 700, OneScreen);

        // Right edge lands exactly on the working area's right edge.
        Assert.Equal(1920 - 900, fit.X);
        Assert.Equal(100, fit.Y);
        Assert.True(fit.Changed);
    }

    /// <summary>Bottom clamping is what keeps the window off the taskbar rather than under it.</summary>
    [Fact]
    public void AWindowHangingOverTheTaskbarIsLiftedAboveIt()
    {
        var fit = WindowPlacementCalculator.Fit(100, 900, 900, 700, OneScreen);

        Assert.Equal(1040 - 700, fit.Y);
        Assert.True(fit.Changed);
    }

    [Fact]
    public void AWindowTooBigForTheScreenEndsUpFillingTheWorkingAreaExactly()
    {
        var fit = WindowPlacementCalculator.Fit(-500, -500, 3000, 2000, OneScreen);

        Assert.Equal(0, fit.X);
        Assert.Equal(0, fit.Y);
        Assert.Equal(1920, fit.Width);
        Assert.Equal(1040, fit.Height);
    }

    [Fact]
    public void GeometryOnASecondMonitorStaysOnThatMonitor()
    {
        var fit = WindowPlacementCalculator.Fit(2000, 100, 900, 700, TwoScreens);

        Assert.Equal(2000, fit.X);
        Assert.Equal(100, fit.Y);
        Assert.False(fit.Changed);
    }

    [Fact]
    public void GeometryOverhangingASecondMonitorIsClampedToThatMonitorNotThePrimary()
    {
        var fit = WindowPlacementCalculator.Fit(2900, 500, 900, 700, TwoScreens);

        Assert.Equal(1920 + 1280 - 900, fit.X);
        Assert.Equal(984 - 700, fit.Y);
        Assert.True(fit.Changed);
    }

    /// <summary>
    /// A window straddling two displays belongs to whichever is showing more of it — the same answer a
    /// user would give looking at the screen.
    /// </summary>
    [Fact]
    public void AStraddlingWindowIsAssignedToTheMonitorShowingMostOfIt()
    {
        var fit = WindowPlacementCalculator.Fit(1820, 100, 400, 700, TwoScreens);

        // 300 of the 400px width is on the secondary display, so it is clamped into that one.
        Assert.Equal(1920, fit.X);
        Assert.True(fit.Changed);
    }

    /// <summary>
    /// The monitor the geometry was saved on has been unplugged. Reinstating those coordinates would
    /// strand the window; the size is still worth keeping, so only the position is given up and the
    /// window manager places the window instead.
    /// </summary>
    [Fact]
    public void PositionSavedOnAMonitorThatIsGoneIsAbandonedButTheSizeSurvives()
    {
        var fit = WindowPlacementCalculator.Fit(-9000, -7000, 980, 720, OneScreen);

        Assert.Null(fit.X);
        Assert.Null(fit.Y);
        Assert.False(fit.HasPosition);
        Assert.Equal(980, fit.Width);
        Assert.Equal(720, fit.Height);
        Assert.True(fit.Changed);
    }

    [Fact]
    public void ASizeFromAMissingMonitorIsStillClampedToTheFallbackMonitor()
    {
        var fit = WindowPlacementCalculator.Fit(-9000, -7000, 3000, 2000, OneScreen);

        Assert.Null(fit.X);
        Assert.Equal(1920, fit.Width);
        Assert.Equal(1040, fit.Height);
    }

    /// <summary>First run: nothing was saved, so only the default size needs to fit.</summary>
    [Fact]
    public void WithNoSavedPositionOnlyTheSizeIsFitted()
    {
        var small = new ScreenArea[] { new(0, 0, 1024, 728) };

        var fit = WindowPlacementCalculator.Fit(null, null, 1100, 850, small);

        Assert.Null(fit.X);
        Assert.Null(fit.Y);
        Assert.Equal(1024, fit.Width);
        Assert.Equal(728, fit.Height);
        Assert.True(fit.Changed);
    }

    [Fact]
    public void ADefaultSizeThatAlreadyFitsIsNotTouched()
    {
        var fit = WindowPlacementCalculator.Fit(null, null, 1100, 850, OneScreen);

        Assert.Equal(1100, fit.Width);
        Assert.Equal(850, fit.Height);
        Assert.False(fit.Changed);
    }

    /// <summary>
    /// A screen list that is empty (headless, or the platform could not report displays) must not
    /// invent constraints — placement falls back to the platform's own behaviour.
    /// </summary>
    [Fact]
    public void WithNoScreenInformationNothingIsClamped()
    {
        var fit = WindowPlacementCalculator.Fit(-9000, -7000, 3000, 2000, []);

        Assert.Equal(-9000, fit.X);
        Assert.Equal(-7000, fit.Y);
        Assert.Equal(3000, fit.Width);
        Assert.Equal(2000, fit.Height);
        Assert.False(fit.Changed);
    }

    [Fact]
    public void DegenerateScreenEntriesAreIgnoredRatherThanUsed()
    {
        ScreenArea[] areas = [new(0, 0, 0, 0), Primary];

        var fit = WindowPlacementCalculator.Fit(100, 900, 900, 700, areas);

        Assert.Equal(1040 - 700, fit.Y);
    }

    /// <summary>
    /// A window exactly as large as the working area leaves no room to move: the clamp range collapses
    /// to a point, which must produce that point rather than an exception.
    /// </summary>
    [Fact]
    public void AWindowExactlyFillingTheWorkingAreaIsPinnedToItsOrigin()
    {
        var fit = WindowPlacementCalculator.Fit(500, 500, 1920, 1040, OneScreen);

        Assert.Equal(0, fit.X);
        Assert.Equal(0, fit.Y);
        Assert.Equal(1920, fit.Width);
        Assert.Equal(1040, fit.Height);
    }

    [Fact]
    public void AScreenWithANonZeroOriginIsRespected()
    {
        ScreenArea[] offset = [new(-1920, -200, 1920, 1040)];

        var fit = WindowPlacementCalculator.Fit(-5000, -5000, 800, 600, offset);

        // No overlap at all with the only monitor, so the position is dropped, not clamped into it.
        Assert.Null(fit.X);

        // Overlapping that monitor, but hanging off its top edge: clamped to the monitor's own origin,
        // which is negative here rather than zero.
        var overhanging = WindowPlacementCalculator.Fit(-1900, -500, 800, 600, offset);
        Assert.Equal(-1900, overhanging.X);
        Assert.Equal(-200, overhanging.Y);
    }
}
