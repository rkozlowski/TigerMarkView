using System.Security.Cryptography;
using System.Text;

namespace TigerMarkView.Core.Rendering;

/// <summary>
/// The Content Security Policy every generated page carries: the second of the three layers
/// <see cref="DocumentHtmlSanitizer"/> describes.
/// </summary>
/// <remarks>
/// <para>
/// Script is allowed by exact hash rather than by <c>'unsafe-inline'</c> or a nonce: the only script a
/// page may run is the one shell block TigerMarkView wrote, so any script a document smuggled past the
/// sanitizer — inline, in an event handler, or behind a <c>javascript:</c> URL — is refused by the
/// engine. A hash is also deterministic, which a per-render nonce is not, so a re-render of the same
/// document produces the same page.
/// </para>
/// <para>
/// Images may come from local files, inline <c>data:</c>, and the web: a remote picture in a README is
/// ordinary Markdown and stays working. Everything else a page could use to issue a request is closed —
/// fetch, XHR, WebSocket, beacons (<c>connect-src</c>), frames, plugins, media, fonts, form submission,
/// and a document-supplied <c>&lt;base&gt;</c> — through <c>default-src 'none'</c> and the directives
/// that do not fall back to it.
/// </para>
/// <para>
/// This layer cannot tell a local file from one on a network share: CSP sources for <c>file:</c> are
/// scheme-only, so <c>img-src file:</c> admits <c>file://server/share/x.png</c> too. Network files are
/// kept out by the other two layers — the sanitizer drops them from the markup, and
/// <see cref="WebResourcePolicy"/> refuses them at the engine, including references that only become
/// network files once resolved against the document's base.
/// </para>
/// <para>
/// Style elements are pinned by hash to the shell's own stylesheet, while <c>style</c> attributes stay
/// permitted: raw HTML sizes and aligns things with them and Markdig writes them for table alignment.
/// The split matters because a stylesheet can do what an attribute cannot — select on attribute values
/// (the <c>&lt;base href&gt;</c> holds the document's local path, and so the reader's user name) and
/// report each match through a background-image URL, which is a data-bearing request made of nothing
/// but images.
/// </para>
/// <para>
/// Delivered as a <c>&lt;meta&gt;</c> element because the pages are local files with no response
/// headers. That is enough for every directive used here; the ones a <c>&lt;meta&gt;</c> policy cannot
/// carry (<c>frame-ancestors</c>, <c>sandbox</c>, reporting) are not needed.
/// </para>
/// </remarks>
internal static class DocumentContentSecurityPolicy
{
    /// <summary>
    /// The policy for a page whose only script element contains exactly <paramref name="script"/> and
    /// whose only style element contains exactly <paramref name="style"/>.
    /// </summary>
    public static string For(string script, string style) =>
        "default-src 'none'; " +
        $"script-src '{Hash(script)}'; " +
        $"style-src-elem '{Hash(style)}'; " +
        "style-src-attr 'unsafe-inline'; " +
        "img-src file: data: http: https:; " +
        "base-uri file:; " +
        "form-action 'none'";

    /// <summary>The <c>&lt;meta&gt;</c> element that delivers <see cref="For"/>.</summary>
    public static string MetaElement(string script, string style) =>
        $"""<meta http-equiv="Content-Security-Policy" content="{For(script, style)}" />""";

    /// <summary>
    /// The CSP hash source for an element's text, in the form <c>sha256-&lt;base64&gt;</c>.
    /// </summary>
    /// <remarks>
    /// The engine hashes the element's text after parsing, and HTML parsing turns every CR LF into LF.
    /// <see cref="DocumentShell.Block"/> therefore emits LF-only text, and this hashes the same, so a
    /// checkout with Windows line endings cannot produce a page that blocks its own script or styles.
    /// </remarks>
    public static string Hash(string elementText) =>
        "sha256-" + Convert.ToBase64String(SHA256.HashData(Encoding.UTF8.GetBytes(elementText)));
}
