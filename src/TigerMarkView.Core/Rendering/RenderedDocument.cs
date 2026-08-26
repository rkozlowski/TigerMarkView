using TigerMarkView.Core.Exporting;

namespace TigerMarkView.Core.Rendering;

/// <summary>
/// A snapshot of one successfully rendered document: the Markdown source path, the Markdown text it
/// was rendered from, the exact HTML that was produced, the theme and page setup that HTML was
/// produced with, and the mtime of the file version all of that came from.
/// </summary>
/// <remarks>
/// Holding the HTML (rather than re-reading the file on demand) is what makes PDF export reproduce
/// <em>what the user is looking at</em>. In Manual/Confirm mode the file on disk may already be newer
/// than the rendered view; exporting would otherwise silently publish content the reviewer has never
/// seen. The Markdown text is retained for the same reason: <see cref="WithTheme"/> must be able to
/// restyle the viewed version without going to disk.
/// </remarks>
/// <param name="PageSetup">
/// The paper the retained <paramref name="Html"/>'s <c>@page</c> rule describes. Carried with the
/// document so an export can hand the print engine the very setup the HTML was laid out for, rather
/// than whatever the preferences happen to say by the time the export runs.
/// </param>
/// <param name="RenderingOptions">
/// The optional rendering behaviours the retained <paramref name="Html"/> was produced with. Carried
/// for the same reason as the other two: what is on screen, and what an export would publish, is
/// whatever these said at render time — not whatever the menu says now.
/// </param>
public sealed record RenderedDocument(
    string FilePath,
    string Markdown,
    string Html,
    DateTime SourceTimestampUtc,
    MarkdownTheme Theme,
    PdfPageSetup PageSetup,
    MarkdownRenderingOptions RenderingOptions)
{
    /// <summary>
    /// Reads and renders <paramref name="markdownFilePath"/>. The mtime is captured <em>before</em>
    /// the read, so a version written during the read is never mistaken for the one just rendered.
    /// Throws on any read failure — callers show <see cref="MarkdownRenderer.ToErrorDocument"/>.
    /// </summary>
    public static RenderedDocument Load(
        string markdownFilePath,
        MarkdownTheme theme = MarkdownTheme.Light,
        PdfPageSetup? pageSetup = null,
        MarkdownRenderingOptions renderingOptions = default)
    {
        var setup = pageSetup ?? PdfPageSetup.Default;
        var fullPath = Path.GetFullPath(markdownFilePath);
        var timestampUtc = File.GetLastWriteTimeUtc(fullPath);
        var markdown = File.ReadAllText(fullPath);
        var html = MarkdownDocumentLoader.RenderHtmlDocument(fullPath, markdown, theme, setup, renderingOptions);

        return new RenderedDocument(fullPath, markdown, html, timestampUtc, theme, setup, renderingOptions);
    }

    /// <summary>
    /// Re-renders the <em>same</em> document version under a different theme. No file is read, so the
    /// viewed version — and therefore what PDF export would publish — is unchanged by a theme switch.
    /// </summary>
    public RenderedDocument WithTheme(MarkdownTheme theme) => WithPresentation(theme, RenderingOptions);

    /// <summary>
    /// Re-renders the same document version with different rendering options. No file is read, so
    /// turning emoji shortcodes or syntax highlighting on or off restyles what the reader has already
    /// read rather than quietly promoting the view to a newer version on disk.
    /// </summary>
    public RenderedDocument WithRenderingOptions(MarkdownRenderingOptions renderingOptions) =>
        WithPresentation(Theme, renderingOptions);

    /// <summary>
    /// Both of the above at once, in one re-render. The viewer's refresh path uses this so a change to
    /// either one costs a single pass over the retained Markdown rather than two.
    /// </summary>
    public RenderedDocument WithPresentation(MarkdownTheme theme, MarkdownRenderingOptions renderingOptions) =>
        theme == Theme && renderingOptions == RenderingOptions
            ? this
            : Rerender(theme, PageSetup, renderingOptions);

    /// <summary>
    /// Re-renders the same document version for different paper. No file is read, for exactly the
    /// reason <see cref="WithTheme"/> does not: changing a PDF preference must not quietly promote
    /// the reader's view to a newer version on disk. Only the <c>@page</c> rule differs, which has no
    /// effect on screen — so this updates what an export would produce without disturbing what the
    /// reader is looking at.
    /// </summary>
    public RenderedDocument WithPageSetup(PdfPageSetup pageSetup) =>
        pageSetup == PageSetup ? this : Rerender(Theme, pageSetup, RenderingOptions);

    private RenderedDocument Rerender(
        MarkdownTheme theme,
        PdfPageSetup pageSetup,
        MarkdownRenderingOptions renderingOptions) => this with
    {
        Html = MarkdownDocumentLoader.RenderHtmlDocument(FilePath, Markdown, theme, pageSetup, renderingOptions),
        Theme = theme,
        PageSetup = pageSetup,
        RenderingOptions = renderingOptions,
    };
}
