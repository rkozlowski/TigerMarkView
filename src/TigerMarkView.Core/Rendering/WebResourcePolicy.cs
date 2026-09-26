namespace TigerMarkView.Core.Rendering;

/// <summary>What a rendered page is asking the engine to fetch, as far as the policy cares.</summary>
public enum WebResourceKind
{
    /// <summary>A page: the rendered document itself, or anything that would load in a frame.</summary>
    Document,

    /// <summary>A picture, including a CSS background image.</summary>
    Image,

    /// <summary>Anything else: script, stylesheet, font, media, fetch/XHR, beacon, WebSocket, worker.</summary>
    Other,
}

/// <summary>
/// Which requests a WebView showing a rendered document may make: the host-side third layer
/// <see cref="DocumentHtmlSanitizer"/> describes, and one policy for the viewer, Help, and PDF export.
/// </summary>
/// <remarks>
/// <para>
/// The rule is by kind, not by address. A remote image is ordinary Markdown and is allowed from anywhere;
/// every other network request is refused, whatever its destination. That is what stops content that
/// somehow runs from reading the document and sending it out through <c>fetch</c>, a beacon, a
/// WebSocket, a frame, or a stylesheet — the channels that carry data a page computed rather than a URL
/// the author wrote down. Deciding by destination instead would mean either blocking every remote image
/// or trusting whichever host a document names.
/// </para>
/// <para>
/// Local files may be loaded as the page itself and as images, which is how the generated preview and
/// its relative images arrive. Top-level navigation to the web is not this policy's business: the hosts
/// intercept a followed link before any request is made and hand it to the system browser.
/// </para>
/// </remarks>
public static class WebResourcePolicy
{
    /// <summary>
    /// True when a rendered page may request <paramref name="uri"/> as a <paramref name="kind"/>.
    /// </summary>
    public static bool Allows(Uri uri, WebResourceKind kind)
    {
        ArgumentNullException.ThrowIfNull(uri);

        if (!uri.IsAbsoluteUri)
        {
            return false;
        }

        return kind switch
        {
            WebResourceKind.Image => IsWebScheme(uri) || IsLocalScheme(uri),
            WebResourceKind.Document => uri.IsFile,
            _ => false,
        };
    }

    private static bool IsWebScheme(Uri uri) =>
        uri.Scheme == Uri.UriSchemeHttp || uri.Scheme == Uri.UriSchemeHttps;

    private static bool IsLocalScheme(Uri uri) =>
        uri.IsFile || string.Equals(uri.Scheme, "data", StringComparison.OrdinalIgnoreCase);
}
