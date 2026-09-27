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
/// the author wrote down. Executable code could also put data in an allowed image URL: the sanitizer
/// and CSP must prevent that code from running. Deciding by destination instead would mean either blocking every remote image
/// or trusting whichever host a document names.
/// </para>
/// <para>
/// Local files may be loaded as the page itself and as images, which is how the generated preview and
/// its relative images arrive. Top-level navigation to the web is not this policy's business: the hosts
/// intercept a followed link before any request is made and hand it to the system browser.
/// </para>
/// <para>
/// A <c>file:</c> URL is not necessarily local. One that names a host — <c>file://server/share/x.png</c>,
/// which is what <c>\\server\share\x.png</c> and <c>//server/share/x.png</c> resolve to — makes Windows
/// open an SMB connection to that host, and SMB authenticates with the reader's Windows credentials. A
/// document could use that to collect an NTLM response from every reader just by naming an image, so a
/// network file is refused like any other non-image network request, even as an image. See
/// <see cref="IsLocalFile"/> for how "local" is decided.
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
            WebResourceKind.Image => IsWebScheme(uri) || IsDataScheme(uri) || IsLocalFile(uri),
            WebResourceKind.Document => IsLocalFile(uri),
            _ => false,
        };
    }

    /// <summary>
    /// True only for a <c>file:</c> URL that names a file on a drive-letter volume of this machine.
    /// </summary>
    /// <remarks>
    /// <para>
    /// An allowlist of the one shape a local file has, rather than a list of network shapes, because
    /// the same share can be spelled many ways and URL and path semantics disagree about several of
    /// them. <c>System.Uri</c> reports <c>file:///%5C%5Cserver%5Cshare</c> as host-less and not UNC,
    /// for example, yet its local path <c>///server/share</c> is one Windows opens as a share. So the
    /// test is on what Windows would be handed: no host, not UNC, and a decoded local path that is
    /// fully qualified on a drive letter. Everything else — a host (including <c>localhost</c> and IP
    /// addresses), a leading slash pair, a <c>\\?\</c> or <c>\\.\</c> device path, a URL that does not
    /// parse — is refused.
    /// </para>
    /// <para>
    /// This platform-neutral check establishes only the path's shape. The Windows request boundary
    /// also checks DOS-device mappings and reparse targets so network storage cannot pass as local.
    /// </para>
    /// </remarks>
    public static bool IsLocalFile(Uri uri)
    {
        ArgumentNullException.ThrowIfNull(uri);

        if (!uri.IsAbsoluteUri || !uri.IsFile || uri.IsUnc || uri.Host.Length != 0)
        {
            return false;
        }

        string path;
        try
        {
            path = uri.LocalPath;
        }
        catch (InvalidOperationException)
        {
            return false;
        }

        return path.Length >= 3
            && char.IsAsciiLetter(path[0])
            && path[1] == ':'
            && path[2] == '\\';
    }

    /// <summary>
    /// True when a reference written in a document would resolve to a file on another host.
    /// </summary>
    /// <remarks>
    /// <para>
    /// Used by the sanitizer on raw attribute values, before any base URL has been applied, so it has to
    /// read a reference the way the browser's URL parser will: surrounding control characters and
    /// spaces are dropped, tabs and line breaks vanish wherever they are, a backslash is a slash, and a
    /// percent-encoded character is judged by what it decodes to. A reference is then a network file
    /// when it is a <c>file:</c> URL or scheme-relative (it inherits the page's <c>file:</c> scheme), and
    /// what follows its leading slashes is a host rather than a drive letter.
    /// </para>
    /// <para>
    /// Deliberately conservative: <c>///server/share</c> is treated as a network reference although a
    /// browser may read it as a root path. It can only drop a reference that names no drive, which no
    /// working local image does. The request boundary applies <see cref="IsLocalFile"/> to whatever the
    /// engine finally resolves, so this is the early layer, not the only one.
    /// </para>
    /// </remarks>
    internal static bool IsNetworkFileReference(string reference)
    {
        ArgumentNullException.ThrowIfNull(reference);

        // An absolute reference to a drive backed by network storage is removed before the browser
        // sees it, so nothing about it depends on the request callback running first. The request
        // boundary rechecks storage at use time, and is the only check a relative reference gets.
        var text = Normalize(reference);
        if (Uri.TryCreate(text, UriKind.Absolute, out var absolute)
            && IsLocalFile(absolute) && !LocalImageStorage.IsLocal(absolute))
        {
            return true;
        }

        if (text.StartsWith("file:", StringComparison.OrdinalIgnoreCase))
        {
            text = text["file:".Length..];
        }
        else if (HasScheme(text))
        {
            return false;
        }

        var slashes = 0;
        while (slashes < text.Length && text[slashes] == '/')
        {
            slashes++;
        }

        // Chromium recognizes a drive after leading slashes (and the legacy C| spelling), whereas
        // System.Uri rejects these scheme-less forms. Classify their browser meaning before use.
        if (StartsWithDriveLetter(text.AsSpan(slashes)))
        {
            var drivePath = text[slashes..];
            drivePath = drivePath[0] + ":" + drivePath[2..];
            return !Uri.TryCreate("file:///" + drivePath, UriKind.Absolute, out var driveUri)
                || !LocalImageStorage.IsLocal(driveUri);
        }

        // Zero or one slash is a relative or root-relative path, resolved on the document's own drive.
        return slashes >= 2;
    }

    private static string Normalize(string reference)
    {
        string decoded;
        try
        {
            decoded = Uri.UnescapeDataString(reference);
        }
        catch (UriFormatException)
        {
            decoded = reference;
        }

        var builder = new System.Text.StringBuilder(decoded.Length);
        foreach (var character in decoded.Trim(ControlOrSpace))
        {
            if (character is '\t' or '\r' or '\n')
            {
                continue;
            }

            builder.Append(character == '\\' ? '/' : character);
        }

        return builder.ToString();
    }

    private static readonly char[] ControlOrSpace =
        Enumerable.Range(0, 0x21).Select(code => (char)code).ToArray();

    private static bool HasScheme(string text)
    {
        var colon = text.IndexOf(':');
        if (colon <= 0 || !char.IsAsciiLetter(text[0]))
        {
            return false;
        }

        for (var i = 1; i < colon; i++)
        {
            if (!char.IsAsciiLetterOrDigit(text[i]) && text[i] is not ('+' or '-' or '.'))
            {
                return false;
            }
        }

        return true;
    }

    /// <summary><c>C:</c> or <c>C|</c>, at the end or before a slash — the URL spelling of a drive.</summary>
    private static bool StartsWithDriveLetter(ReadOnlySpan<char> text) =>
        text.Length >= 2
        && char.IsAsciiLetter(text[0])
        && text[1] is ':' or '|'
        && (text.Length == 2 || text[2] == '/');

    private static bool IsWebScheme(Uri uri) =>
        uri.Scheme == Uri.UriSchemeHttp || uri.Scheme == Uri.UriSchemeHttps;

    private static bool IsDataScheme(Uri uri) =>
        string.Equals(uri.Scheme, "data", StringComparison.OrdinalIgnoreCase);
}
