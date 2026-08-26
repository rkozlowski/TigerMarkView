namespace TigerMarkView.Core.Navigation;

/// <summary>
/// The messages the rendered page can post back to the viewer, and the parser for them.
/// </summary>
/// <remarks>
/// The page needs a way to ask for Back/Forward because the WebView is a native child window that
/// keeps its own keyboard input — see <c>DocumentShell.NavigationShortcutScript</c>. Keeping the
/// vocabulary and the parsing here (rather than as string literals in the window) means the script and
/// its handler cannot drift apart unnoticed, and the parsing is testable.
/// </remarks>
public static class ViewerMessages
{
    public const string BackCommand = "tigermarkview:navigate:back";

    public const string ForwardCommand = "tigermarkview:navigate:forward";

    /// <summary>
    /// F1 pressed inside the document, asking the host to open the bundled help.
    /// </summary>
    /// <remarks>
    /// Here for exactly the reason Back and Forward are: the WebView keeps its own keyboard input, so a
    /// shortcut handled only on the Avalonia side would work everywhere except in the document — which
    /// is where the reader almost always is. Not a navigation command, because Help is not a document
    /// the viewer navigates to; it opens a window of its own and leaves the reading session alone.
    /// </remarks>
    public const string HelpCommand = "tigermarkview:help";

    /// <summary>
    /// Ctrl+P pressed inside the document after the page has cancelled Chromium's print preview.
    /// </summary>
    /// <remarks>
    /// Here for the reason F1 is, and for one more that is specific to this key: the WebView keeps its
    /// own keyboard input, and Chromium's <em>own</em> Ctrl+P handler would open Edge's print preview
    /// over the document. The page script therefore cancels the key and posts this marker to the host.
    /// Printing is not part of the shipped UI, so the host deliberately performs no command.
    /// </remarks>
    public const string PrintCommand = "tigermarkview:print";

    /// <summary>
    /// Interprets a message posted by the page. Returns null for anything unrecognised — the viewer
    /// must ignore messages it does not understand rather than act on a guess.
    /// </summary>
    /// <remarks>
    /// Tolerates the message arriving JSON-encoded (<c>"…"</c> with quotes), because a WebView host may
    /// surface a posted string either way depending on which underlying accessor it uses.
    /// </remarks>
    public static ViewerNavigationCommand? ParseNavigationCommand(string? message) => Unquote(message) switch
    {
        BackCommand => ViewerNavigationCommand.Back,
        ForwardCommand => ViewerNavigationCommand.Forward,
        _ => null,
    };

    /// <summary>
    /// Whether the page asked for the bundled help. Separate from
    /// <see cref="ParseNavigationCommand"/> rather than folded into its enum, because the caller does
    /// something categorically different with it — no history, no document, no viewer state.
    /// </summary>
    public static bool IsHelpCommand(string? message) =>
        string.Equals(Unquote(message), HelpCommand, StringComparison.Ordinal);

    /// <summary>
    /// Whether the page reported that it suppressed Chromium's Ctrl+P behaviour.
    /// </summary>
    public static bool IsPrintCommand(string? message) =>
        string.Equals(Unquote(message), PrintCommand, StringComparison.Ordinal);

    private static string? Unquote(string? message)
    {
        if (message is null)
        {
            return null;
        }

        var trimmed = message.Trim();

        return trimmed.Length >= 2 && trimmed.StartsWith('"') && trimmed.EndsWith('"')
            ? trimmed[1..^1]
            : trimmed;
    }
}

public enum ViewerNavigationCommand
{
    Back,
    Forward,
}
