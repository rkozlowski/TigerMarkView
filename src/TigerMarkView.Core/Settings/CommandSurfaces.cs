namespace TigerMarkView.Core.Settings;

/// <summary>
/// Which of the surfaces that carry TigerMarkView's commands are showing — the menu bar, the toolbar,
/// and the toolbar's <c>☰</c> menu button — and the rules they must obey: <strong>at least one of the
/// menu bar and the toolbar is always visible</strong>, and <strong>the menu button is always visible
/// while the menu bar is not</strong>.
/// </summary>
/// <remarks>
/// <para>
/// The two rules are one idea counted twice: the full command tree must always be reachable. Hiding
/// both the menu bar and the toolbar would leave a window with no way to open a document, change a
/// mode, or reach Help. Hiding the menu bar and the menu button would leave the toolbar's handful of
/// buttons and nothing else — no Tools, no Help, no way back to the menu bar — which is the same dead
/// end reached one step later. Both are recoverable only by editing the settings file, which is not a
/// state a menu item may put a reader in.
/// </para>
/// <para>
/// The menu button is a command surface for exactly that reason, and is not one of
/// <see cref="ToolbarActions"/>' optional buttons: those three are conveniences whose commands stay on
/// the menu bar regardless, whereas this one can be the last route to every command there is. It is
/// still an ordinary toolbar button whenever the menu bar is showing, which is the case the reader
/// gets to choose about.
/// </para>
/// <para>
/// The status bar is deliberately not part of this. It reports state and offers two optional actions;
/// hiding it costs the reader information, not access to the application.
/// </para>
/// <para>
/// The rules live in Core, next to <see cref="RecentFilesPolicy"/> and for the same reason: the viewer
/// is an Avalonia window and cannot be unit tested, and an invariant is worth pinning down where it can
/// be asserted. The type is a value with normalising factories rather than a set of static checks, so
/// there is no way to hold a combination that breaks them — including one read back from a hand-edited
/// settings file.
/// </para>
/// </remarks>
public readonly record struct CommandSurfaces
{
    private CommandSurfaces(bool menuBarVisible, bool toolbarVisible, bool toolbarMenuButtonVisible)
    {
        MenuBarVisible = menuBarVisible;
        ToolbarVisible = toolbarVisible;
        ToolbarMenuButtonVisible = toolbarMenuButtonVisible;
    }

    /// <summary>Every surface showing — the first-run state.</summary>
    public static CommandSurfaces Default =>
        new(menuBarVisible: true, toolbarVisible: true, toolbarMenuButtonVisible: true);

    /// <summary>
    /// The nearest legal reading of a remembered (or hand-edited) combination.
    /// </summary>
    /// <remarks>
    /// Two combinations need repairing, and each recovers deterministically towards the surface the
    /// reader is least likely to have meant to lose:
    /// <list type="bullet">
    /// <item>
    /// <description>
    /// <em>Neither command surface visible</em> becomes <em>menu bar visible, toolbar hidden</em> —
    /// hiding the toolbar is a choice a reader could legitimately have made, so it is kept, and the
    /// menu bar (the default surface, and the one that reaches every command without a flyout) comes
    /// back to carry the commands.
    /// </description>
    /// </item>
    /// <item>
    /// <description>
    /// <em>Menu bar hidden and menu button hidden</em> becomes <em>menu button visible</em>. The menu
    /// bar is deliberately left hidden: a reader running without one has chosen the compact window,
    /// and restoring the one button that reaches the menu keeps that choice while making it usable.
    /// </description>
    /// </item>
    /// </list>
    /// </remarks>
    public static CommandSurfaces Of(bool menuBarVisible, bool toolbarVisible, bool toolbarMenuButtonVisible)
    {
        if (!menuBarVisible && !toolbarVisible)
        {
            menuBarVisible = true;
            toolbarVisible = false;
        }

        if (!menuBarVisible && !toolbarMenuButtonVisible)
        {
            toolbarMenuButtonVisible = true;
        }

        return new CommandSurfaces(menuBarVisible, toolbarVisible, toolbarMenuButtonVisible);
    }

    public bool MenuBarVisible { get; }

    public bool ToolbarVisible { get; }

    /// <summary>
    /// Whether the toolbar carries the <c>☰</c> menu button. Remembered even while the toolbar itself
    /// is hidden, so showing the toolbar again brings back the toolbar the reader had.
    /// </summary>
    public bool ToolbarMenuButtonVisible { get; }

    /// <summary>
    /// Whether the menu bar may still be hidden — false when doing so would leave no full command
    /// tree behind it, which is what disables <c>View &gt; Menu Bar</c> rather than letting it fail
    /// silently when clicked.
    /// </summary>
    /// <remarks>
    /// The menu button is part of the answer because it is what the menu bar hands over to: a window
    /// with a toolbar but no menu button has nowhere to put the commands the menu bar was showing.
    /// Refusing is the same answer <see cref="WithMenuBar"/> gives, for the reason given there.
    /// </remarks>
    public bool CanHideMenuBar => ToolbarVisible && ToolbarMenuButtonVisible;

    /// <inheritdoc cref="CanHideMenuBar"/>
    public bool CanHideToolbar => MenuBarVisible;

    /// <summary>
    /// Whether the toolbar's menu button may be hidden — false while the menu bar is hidden, since it
    /// is then the only way to reach the full command tree. Disables
    /// <c>View &gt; Toolbar Buttons &gt; Menu</c>, so the item reads as "showing, and not yours to turn
    /// off" rather than as a choice that quietly does nothing.
    /// </summary>
    public bool CanHideToolbarMenuButton => MenuBarVisible;

    /// <summary>
    /// Shows or hides the menu bar, <em>keeping it visible</em> if hiding it would leave the reader
    /// without a full command tree. Refusing the change is the least surprising of the available
    /// answers: the alternative — quietly showing the toolbar, or the menu button, to make room for
    /// the request — moves a piece of chrome the reader did not ask about.
    /// </summary>
    public CommandSurfaces WithMenuBar(bool visible) =>
        visible || CanHideMenuBar ? Of(visible, ToolbarVisible, ToolbarMenuButtonVisible) : this;

    /// <inheritdoc cref="WithMenuBar"/>
    public CommandSurfaces WithToolbar(bool visible) =>
        visible || CanHideToolbar ? Of(MenuBarVisible, visible, ToolbarMenuButtonVisible) : this;

    /// <inheritdoc cref="WithMenuBar"/>
    public CommandSurfaces WithToolbarMenuButton(bool visible) =>
        visible || CanHideToolbarMenuButton ? Of(MenuBarVisible, ToolbarVisible, visible) : this;
}
