using TigerMarkView.Core.Rendering;

namespace TigerMarkView.Core.Navigation;

/// <summary>
/// Decides whether the viewer may open a Markdown document its WebView asked for when that document is
/// not on this computer's local storage.
/// </summary>
/// <remarks>
/// <para>
/// Opening a document on a network share makes Windows connect to that host over SMB, and SMB signs in
/// with the reader's Windows credentials. A document could otherwise collect an NTLM response from any
/// reader who clicks <c>[notes](\\attacker\share\notes.md)</c> — the same exposure
/// <see cref="WebResourcePolicy"/> closes for images, reached through a click instead of a fetch.
/// </para>
/// <para>
/// The rule fails closed, and on purpose does not depend on <see cref="ViewerRequestOrigin"/>. That
/// classifier tells a followed link from a dropped file by finding the requested file among the page's
/// <c>href</c>s, resolved the way <see cref="MarkdownLinkResolver"/> resolves them; a target the browser
/// resolved differently would not be found and would pass for a drop. So while a document is on
/// screen, no request the WebView makes may open a network location, however it is classified —
/// including a relative link in a document that was itself opened from a share, because the document
/// chose that target, not the reader. With no document on screen (the empty or error page, which link
/// to nothing) a request can only be a file the reader dropped, and that may be on a share. Every other
/// explicit open — File &gt; Open, a drop on the window's own chrome, Open Recent, the command line —
/// does not pass through the WebView and is not decided here.
/// </para>
/// <para>
/// "Local" is <see cref="LocalImageStorage.IsLocal"/>, the same classification the request boundary
/// uses, which reads drive mappings and each link target without opening a network target to find out.
/// </para>
/// </remarks>
public static class NetworkLinkPolicy
{
    /// <summary>The status-bar note shown when a request is refused.</summary>
    public const string RefusedMessage =
        "That link leads to a network location, so it was not followed. Use File > Open to open it yourself.";

    /// <summary>
    /// True when the viewer must not open <paramref name="resolvedPath"/>, a Markdown document its
    /// WebView asked for while <paramref name="documentOnScreen"/> said whether a rendered document
    /// (rather than the empty or error page) was showing.
    /// </summary>
    public static bool Refuses(string resolvedPath, bool documentOnScreen) =>
        documentOnScreen && !IsOnLocalStorage(resolvedPath);

    /// <summary>
    /// True only for a fully qualified drive-letter path backed by local storage. A UNC or device path,
    /// a mapped network drive, a link to a share, and anything that does not parse are not.
    /// </summary>
    public static bool IsOnLocalStorage(string path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            return false;
        }

        try
        {
            return LocalImageStorage.IsLocal(new Uri(Path.GetFullPath(path)));
        }
        catch (Exception exception) when (exception is ArgumentException or NotSupportedException
                                              or PathTooLongException or UriFormatException)
        {
            return false;
        }
    }
}
