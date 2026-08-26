using TigerMarkView.Core.Exporting;

namespace TigerMarkView.Core.Rendering;

public static class MarkdownDocumentLoader
{
    /// <summary>
    /// Reads the Markdown file at <paramref name="markdownFilePath"/> and renders it to a full
    /// HTML document, with a &lt;base href&gt; pointing at the file's own directory so relative
    /// local images/links resolve correctly. Throws on any read failure — callers render
    /// <see cref="MarkdownRenderer.ToErrorDocument"/> instead of letting the exception surface.
    /// </summary>
    public static string LoadHtmlDocument(
        string markdownFilePath,
        MarkdownTheme theme = MarkdownTheme.Light,
        PdfPageSetup? pageSetup = null,
        MarkdownRenderingOptions renderingOptions = default)
    {
        var fullPath = Path.GetFullPath(markdownFilePath);
        var markdown = File.ReadAllText(fullPath);

        return RenderHtmlDocument(fullPath, markdown, theme, pageSetup, renderingOptions);
    }

    /// <summary>
    /// Renders already-read Markdown as if it had come from <paramref name="markdownFilePath"/>, so
    /// the base href and title match. Touches no files, which is what lets a theme change re-render
    /// the version currently on screen without re-reading (and thereby silently adopting) a newer
    /// version from disk — see <see cref="RenderedDocument.WithTheme"/>. Toggling a rendering option
    /// travels the same road, for the same reason.
    /// </summary>
    public static string RenderHtmlDocument(
        string markdownFilePath,
        string markdown,
        MarkdownTheme theme,
        PdfPageSetup? pageSetup = null,
        MarkdownRenderingOptions renderingOptions = default)
    {
        var fullPath = Path.GetFullPath(markdownFilePath);
        var directory = Path.GetDirectoryName(fullPath) ?? Directory.GetCurrentDirectory();
        var baseHref = new Uri(directory + Path.DirectorySeparatorChar).AbsoluteUri;
        var title = Path.GetFileName(fullPath);

        return MarkdownRenderer.ToHtmlDocument(markdown, title, baseHref, theme, pageSetup, renderingOptions);
    }
}
