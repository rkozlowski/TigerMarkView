using TigerMarkView.Core.Settings;

namespace TigerMarkView.Core.Tests.Settings;

/// <summary>
/// The invariants these tests exist for: a reader must never be able to hide both the menu bar and the
/// toolbar and be left with no way to reach a command, and must never be able to hide the toolbar's
/// menu button while the menu bar — the only other place the full command tree lives — is hidden too.
/// </summary>
public class CommandSurfacesTests
{
    [Fact]
    public void EverySurfaceStartsVisible()
    {
        var surfaces = CommandSurfaces.Default;

        Assert.True(surfaces.MenuBarVisible);
        Assert.True(surfaces.ToolbarVisible);
        Assert.True(surfaces.ToolbarMenuButtonVisible);
    }

    [Theory]
    [InlineData(true, true, true)]
    [InlineData(true, true, false)]
    [InlineData(true, false, true)]
    [InlineData(true, false, false)]
    [InlineData(false, true, true)]
    public void ALegalCombinationIsKeptExactly(bool menuBar, bool toolbar, bool menuButton)
    {
        var surfaces = CommandSurfaces.Of(menuBar, toolbar, menuButton);

        Assert.Equal(menuBar, surfaces.MenuBarVisible);
        Assert.Equal(toolbar, surfaces.ToolbarVisible);
        Assert.Equal(menuButton, surfaces.ToolbarMenuButtonVisible);
    }

    /// <summary>
    /// One of the two combinations that cannot be honoured — a hand-edited or corrupt settings file —
    /// recovers to the menu bar, keeping the toolbar hidden as asked.
    /// </summary>
    [Fact]
    public void HidingBothCommandSurfacesRecoversToTheMenuBarAlone()
    {
        var surfaces = CommandSurfaces.Of(
            menuBarVisible: false, toolbarVisible: false, toolbarMenuButtonVisible: true);

        Assert.True(surfaces.MenuBarVisible);
        Assert.False(surfaces.ToolbarVisible);
    }

    /// <summary>
    /// The other one: a compact window (no menu bar) whose toolbar has no menu button on it either —
    /// the state a settings file could claim, and a window with no route to Tools, Help, or the menu
    /// bar itself. The menu button comes back and the reader's compact window is left compact.
    /// </summary>
    [Fact]
    public void ACompactWindowWithNoMenuButtonRecoversByShowingTheMenuButton()
    {
        var surfaces = CommandSurfaces.Of(
            menuBarVisible: false, toolbarVisible: true, toolbarMenuButtonVisible: false);

        Assert.False(surfaces.MenuBarVisible);
        Assert.True(surfaces.ToolbarVisible);
        Assert.True(surfaces.ToolbarMenuButtonVisible);
    }

    /// <summary>
    /// The menu button is remembered, not forced, while the menu bar is showing — including on a
    /// window whose toolbar is hidden, so bringing the toolbar back brings back the toolbar the reader
    /// had rather than a repaired one.
    /// </summary>
    [Fact]
    public void TheMenuButtonMayBeHiddenWhileTheMenuBarIsShowing()
    {
        var both = CommandSurfaces.Default.WithToolbarMenuButton(false);

        Assert.True(both.CanHideToolbarMenuButton);
        Assert.False(both.ToolbarMenuButtonVisible);

        var toolbarHidden = both.WithToolbar(false);

        Assert.False(toolbarHidden.ToolbarMenuButtonVisible);
    }

    /// <summary>
    /// Hiding the menu bar is what the menu button's invariant guards, from both directions: it cannot
    /// be hidden while the menu button is off, and the menu button cannot be turned off once it is.
    /// </summary>
    [Fact]
    public void TheMenuBarAndTheMenuButtonCannotBothBeHidden()
    {
        var noMenuButton = CommandSurfaces.Default.WithToolbarMenuButton(false);

        Assert.False(noMenuButton.CanHideMenuBar);
        Assert.Equal(noMenuButton, noMenuButton.WithMenuBar(false));

        var compact = CommandSurfaces.Default.WithMenuBar(false);

        Assert.False(compact.CanHideToolbarMenuButton);
        Assert.Equal(compact, compact.WithToolbarMenuButton(false));
    }

    [Fact]
    public void TheLastSurfaceCannotBeHiddenFromEitherDirection()
    {
        var menuBarOnly = CommandSurfaces.Of(
            menuBarVisible: true, toolbarVisible: false, toolbarMenuButtonVisible: true);
        var toolbarOnly = CommandSurfaces.Of(
            menuBarVisible: false, toolbarVisible: true, toolbarMenuButtonVisible: true);

        Assert.False(menuBarOnly.CanHideMenuBar);
        Assert.False(toolbarOnly.CanHideToolbar);

        // Asking anyway is refused rather than obeyed, and leaves the surface showing.
        Assert.Equal(menuBarOnly, menuBarOnly.WithMenuBar(false));
        Assert.Equal(toolbarOnly, toolbarOnly.WithToolbar(false));
    }

    [Fact]
    public void EitherSurfaceCanBeHiddenWhileTheOtherIsShowing()
    {
        var both = CommandSurfaces.Default;

        Assert.True(both.CanHideMenuBar);
        Assert.True(both.CanHideToolbar);
        Assert.True(both.CanHideToolbarMenuButton);

        var toolbarOnly = both.WithMenuBar(false);
        Assert.False(toolbarOnly.MenuBarVisible);
        Assert.True(toolbarOnly.ToolbarVisible);

        var menuBarOnly = both.WithToolbar(false);
        Assert.True(menuBarOnly.MenuBarVisible);
        Assert.False(menuBarOnly.ToolbarVisible);
    }

    /// <summary>
    /// Hiding one surface and then the other must leave the second one showing, whichever order the
    /// reader works in — this is the sequence the View menu makes easy to attempt.
    /// </summary>
    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public void HidingOneSurfaceThenTheOtherAlwaysLeavesOneVisible(bool menuBarFirst)
    {
        var surfaces = CommandSurfaces.Default;

        surfaces = menuBarFirst
            ? surfaces.WithMenuBar(false).WithToolbar(false)
            : surfaces.WithToolbar(false).WithMenuBar(false);

        Assert.True(surfaces.MenuBarVisible || surfaces.ToolbarVisible);
    }

    [Fact]
    public void ShowingASurfaceIsAlwaysAllowed()
    {
        var toolbarOnly = CommandSurfaces.Of(
            menuBarVisible: false, toolbarVisible: true, toolbarMenuButtonVisible: true);

        var both = toolbarOnly.WithMenuBar(true);

        Assert.True(both.MenuBarVisible);
        Assert.True(both.ToolbarVisible);

        Assert.True(both.WithToolbarMenuButton(false).WithToolbarMenuButton(true).ToolbarMenuButtonVisible);
    }
}
