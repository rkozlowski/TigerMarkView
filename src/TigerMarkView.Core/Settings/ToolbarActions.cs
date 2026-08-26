namespace TigerMarkView.Core.Settings;

/// <summary>
/// Which of the toolbar's <em>optional</em> commands are on it — the Open Recent dropdown beside Open,
/// and Export to PDF. Both are off unless the reader turns them on under
/// <c>View &gt; Toolbar Buttons</c>.
/// </summary>
/// <remarks>
/// <para>
/// Off by default, and <see langword="default"/> is that state, exactly as
/// <c>MarkdownRenderingOptions</c> is: a settings file written before these existed omits them and
/// lands on the toolbar this application has always shown. Every one of these commands is already
/// reachable from the menu bar and from the hamburger mirror, so a hidden button costs a reader
/// nothing but a click — which is why the compact toolbar stays the default rather than being added to
/// everyone's chrome.
/// </para>
/// <para>
/// Unlike <see cref="CommandSurfaces"/> this carries <em>no</em> invariant: any combination is legal,
/// including none, because neither button is the last way to reach its command. It is a value
/// type all the same so the toolbar's one derived layout rule — <see cref="PublishGroupVisible"/>,
/// which decides whether the separator in front of Export earns its place — lives somewhere it
/// can be unit tested, next to the rest of the settings shape rather than inside an Avalonia window.
/// </para>
/// </remarks>
public readonly record struct ToolbarActions(bool OpenRecent, bool ExportPdf)
{
    /// <summary>The compact toolbar: neither optional command showing.</summary>
    public static ToolbarActions Default => default;

    /// <summary>
    /// Whether the publishing group exists at all, and therefore whether the separator that
    /// introduces it should be drawn. Without this a toolbar with Export to PDF hidden would end in a
    /// divider with nothing after it.
    /// </summary>
    public bool PublishGroupVisible => ExportPdf;

    /// <summary>Shows or hides the Open Recent dropdown that sits beside the Open button.</summary>
    public ToolbarActions WithOpenRecent(bool visible) => this with { OpenRecent = visible };

    /// <inheritdoc cref="WithOpenRecent"/>
    public ToolbarActions WithExportPdf(bool visible) => this with { ExportPdf = visible };
}
