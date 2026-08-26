using TigerMarkView.Core.Settings;

namespace TigerMarkView.Core.Tests.Settings;

/// <summary>
/// The toolbar's two optional commands. Unlike <see cref="CommandSurfaces"/> there is no invariant
/// to defend — every combination is legal, since each is reachable from the menu bar regardless — so
/// what these pin down is the default (both off, so the compact toolbar is what a reader gets) and the
/// one derived layout rule the window depends on.
/// </summary>
public class ToolbarActionsTests
{
    [Fact]
    public void EveryOptionalCommandStartsOff()
    {
        var actions = ToolbarActions.Default;

        Assert.False(actions.OpenRecent);
        Assert.False(actions.ExportPdf);
    }

    /// <summary>
    /// <c>default</c> is the compact toolbar, which is what makes the two settings additive: a
    /// settings file that has never heard of them deserializes to exactly this.
    /// </summary>
    [Fact]
    public void TheDefaultValueIsTheCompactToolbar()
    {
        Assert.Equal(ToolbarActions.Default, default(ToolbarActions));
    }

    [Theory]
    [InlineData(true, true)]
    [InlineData(true, false)]
    [InlineData(false, true)]
    [InlineData(false, false)]
    public void EveryCombinationIsKeptExactly(bool openRecent, bool exportPdf)
    {
        var actions = new ToolbarActions(openRecent, exportPdf);

        Assert.Equal(openRecent, actions.OpenRecent);
        Assert.Equal(exportPdf, actions.ExportPdf);
    }

    /// <summary>
    /// The divider that introduces the publishing group belongs to the group: it is drawn when the
    /// command is showing and never on its own, so the toolbar cannot end in a separator with nothing
    /// after it.
    /// </summary>
    [Theory]
    [InlineData(false, false)]
    [InlineData(true, true)]
    public void ThePublishingDividerIsDrawnExactlyWhenExportPdfIsShowing(bool exportPdf, bool expected)
    {
        var actions = new ToolbarActions(OpenRecent: false, exportPdf);

        Assert.Equal(expected, actions.PublishGroupVisible);
    }

    /// <summary>Open Recent lives in the Open group, so it never affects the publishing divider.</summary>
    [Fact]
    public void OpenRecentDoesNotDrawThePublishingDivider()
    {
        Assert.False(ToolbarActions.Default.WithOpenRecent(true).PublishGroupVisible);
    }

    [Fact]
    public void EachCommandIsSwitchedIndependently()
    {
        var actions = ToolbarActions.Default.WithExportPdf(true);

        Assert.True(actions.ExportPdf);
        Assert.False(actions.OpenRecent);

        actions = actions.WithOpenRecent(true).WithExportPdf(false);

        Assert.False(actions.ExportPdf);
        Assert.True(actions.OpenRecent);
    }
}
