using AngleSharp.Html.Parser;

namespace TigerMarkView.Core.Navigation;

/// <summary>
/// Decides whether a local Markdown file the viewer's WebView asked to open was a link the reader
/// followed out of the page on screen, or a file the reader brought from outside it.
/// </summary>
/// <remarks>
/// <para>
/// The WebView reports both the same way. A click on <c>[B](b.md)</c> and a file dragged from
/// Explorer onto the document area each arrive as a request to show a <c>file:</c> URL — WebView2
/// delivers an external file drop as a new-window request, and older runtimes navigated in place —
/// and neither event says which of the two happened. The two must still be told apart, because
/// <see cref="DocumentOpenOrigin.Navigation"/> never enters Open Recent and
/// <see cref="DocumentOpenOrigin.ExplicitOpen"/> always does.
/// </para>
/// <para>
/// A followed link can only come from an <c>href</c> in the page being shown: the document is
/// sanitized and runs no script, so the page has no other way to ask for a navigation. A request for
/// a file that page does not link to is therefore the reader's own — a drop — and so is every
/// request while the empty or error page is shown, which link to nothing. When a dropped file happens
/// to be one the page also links to, the request is indistinguishable from following that link and
/// is treated as one; that keeps the stricter rule — a link never enters Open Recent — exact.
/// </para>
/// </remarks>
public static class ViewerRequestOrigin
{
    /// <summary>
    /// The origin of a request for <paramref name="requestedPath"/> made while the page generated from
    /// <paramref name="displayedHtml"/> for <paramref name="displayedDocumentPath"/> was on screen.
    /// </summary>
    /// <param name="requestedPath">The absolute local path of the requested Markdown file.</param>
    /// <param name="displayedDocumentPath">The document on screen, or <c>null</c> when none is.</param>
    /// <param name="displayedHtml">The page generated for it, or <c>null</c> when none is shown.</param>
    public static DocumentOpenOrigin Classify(string requestedPath, string? displayedDocumentPath, string? displayedHtml)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(requestedPath);

        if (displayedDocumentPath is null || displayedHtml is null)
        {
            return DocumentOpenOrigin.ExplicitOpen;
        }

        return LocalMarkdownLinkTargets(displayedDocumentPath, displayedHtml).Contains(Normalize(requestedPath))
            ? DocumentOpenOrigin.Navigation
            : DocumentOpenOrigin.ExplicitOpen;
    }

    /// <summary>
    /// Every local Markdown file the page links to, as full paths, resolved exactly as the viewer
    /// resolves a followed link (<see cref="MarkdownLinkResolver"/>). Every <c>href</c> counts, not
    /// only those of <c>a</c> elements, so nothing the page could navigate to is missed.
    /// </summary>
    public static IReadOnlySet<string> LocalMarkdownLinkTargets(string documentPath, string html)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(documentPath);
        ArgumentNullException.ThrowIfNull(html);

        var targets = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var page = new HtmlParser().ParseDocument(html);

        foreach (var element in page.All)
        {
            // <base href> is the folder hrefs are resolved against, not a link.
            if (element.LocalName == "base")
            {
                continue;
            }

            foreach (var attribute in element.Attributes)
            {
                if (attribute.LocalName == "href"
                    && MarkdownLinkResolver.TryResolveLocalMarkdown(documentPath, attribute.Value, out var target))
                {
                    targets.Add(Normalize(target));
                }
            }
        }

        return targets;
    }

    private static string Normalize(string path) => Path.GetFullPath(path);
}
