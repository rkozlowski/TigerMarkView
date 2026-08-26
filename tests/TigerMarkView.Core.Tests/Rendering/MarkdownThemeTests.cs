using TigerMarkView.Core.Rendering;

namespace TigerMarkView.Core.Tests.Rendering;

/// <summary>
/// Theme behaviour is asserted through a handful of load-bearing declarations rather than by
/// snapshotting the whole stylesheet: the point is that the right palette is selected and that print
/// styling survives it, not that the CSS is byte-for-byte frozen.
/// </summary>
public class MarkdownThemeTests
{
    [Fact]
    public void LightIsTheDefaultTheme()
    {
        Assert.Equal(MarkdownTheme.Light, default(MarkdownTheme));
        Assert.Equal(
            MarkdownRenderer.ToHtmlDocument("# Hello", "Doc", theme: MarkdownTheme.Light),
            MarkdownRenderer.ToHtmlDocument("# Hello", "Doc"));
    }

    [Fact]
    public void LightThemeSelectsTheLightPalette()
    {
        var html = MarkdownRenderer.ToHtmlDocument("# Hello", "Doc", theme: MarkdownTheme.Light);

        Assert.Contains("color-scheme: light;", html);
        Assert.DoesNotContain("color-scheme: dark;", html);
        Assert.Contains("--page-bg: #ffffff;", html);
        Assert.Contains("--text: #1f2328;", html);
    }

    [Fact]
    public void DarkThemeSelectsTheDarkPalette()
    {
        var html = MarkdownRenderer.ToHtmlDocument("# Hello", "Doc", theme: MarkdownTheme.Dark);

        Assert.Contains("color-scheme: dark;", html);
        Assert.Contains("--page-bg: #0d1117;", html);
        Assert.Contains("--text: #e6edf3;", html);
    }

    /// <summary>
    /// The whole reason the shell is token-based: one structural stylesheet serves both themes, so
    /// every element the theme has to cover is styled through a variable rather than a literal.
    /// </summary>
    [Theory]
    [InlineData("background: var(--page-bg);")]        // page background
    [InlineData("color: var(--text);")]                // body text
    [InlineData("color: var(--heading);")]             // headings
    [InlineData("color: var(--link);")]                // links
    [InlineData("var(--quote-border)")]                // blockquotes
    [InlineData("background: var(--code-bg);")]        // inline code and fenced code blocks
    [InlineData("background: var(--table-header-bg);")] // tables
    [InlineData("hr { border: 0; border-top: 1px solid var(--border);")] // horizontal rules
    public void ScreenStylesAreExpressedThroughThemeTokens(string expectedDeclaration)
    {
        var html = MarkdownRenderer.ToHtmlDocument("# Hello", "Doc", theme: MarkdownTheme.Dark);
        var screenSection = html[..html.IndexOf("@page", StringComparison.Ordinal)];

        Assert.Contains(expectedDeclaration, screenSection);
    }

    [Theory]
    [InlineData(MarkdownTheme.Light)]
    [InlineData(MarkdownTheme.Dark)]
    public void PrintStylesAreEmittedForEveryTheme(MarkdownTheme theme)
    {
        var html = MarkdownRenderer.ToHtmlDocument("# Hello", "Doc", theme: theme);

        Assert.Contains("@page", html);
        Assert.Contains("size: 210mm 297mm;", html);
        Assert.Contains("@media print", html);
        Assert.Contains("break-after: avoid;", html);
    }

    /// <summary>
    /// Exporting a PDF while reading in Dark mode must not produce a dark-background document. The
    /// print block re-declares the light tokens,
    /// so the dark values are overridden for paper.
    /// </summary>
    [Theory]
    [InlineData(MarkdownTheme.Light)]
    [InlineData(MarkdownTheme.Dark)]
    public void PrintStylesForceALightPageWhateverTheViewerTheme(MarkdownTheme theme)
    {
        var html = MarkdownRenderer.ToHtmlDocument("# Hello", "Doc", theme: theme);
        var printSection = html[html.IndexOf("@media print", StringComparison.Ordinal)..];

        Assert.Contains("color-scheme: light;", printSection);
        Assert.Contains("--page-bg: #ffffff;", printSection);
        Assert.Contains("--text: #000000;", printSection);
        Assert.Contains("html, body { background: #fff; }", printSection);

        // The dark palette must not leak past the media query.
        Assert.DoesNotContain("#0d1117", printSection);
        Assert.DoesNotContain("#e6edf3", printSection);
    }

    /// <summary>
    /// Wide images must not force the page to scroll sideways. The constraint has to stay in the
    /// <em>screen</em> stylesheet (print has its own copy), and it has to be
    /// <c>max-width</c> so images narrower than the column keep their natural size.
    /// </summary>
    [Theory]
    [InlineData(MarkdownTheme.Light)]
    [InlineData(MarkdownTheme.Dark)]
    public void ImagesAreConstrainedToTheContentWidthOnScreen(MarkdownTheme theme)
    {
        var html = MarkdownRenderer.ToHtmlDocument("![wide](wide.png)", "Doc", theme: theme);
        var screenSection = html[..html.IndexOf("@page", StringComparison.Ordinal)];

        Assert.Contains("img { max-width: 100%; height: auto; }", screenSection);
    }

    /// <summary>
    /// The reading column adapts to the window instead of sitting at a fixed 800px, so a maximized
    /// window is not mostly margin. Print overrides it back to <c>none</c> — the page box, not the
    /// viewport, governs paper.
    /// </summary>
    [Fact]
    public void TheReadingColumnIsResponsiveOnScreenAndUnconstrainedInPrint()
    {
        var html = MarkdownRenderer.ToHtmlDocument("# Hello", "Doc");
        var printIndex = html.IndexOf("@media print", StringComparison.Ordinal);

        Assert.Contains("max-width: clamp(", html[..printIndex]);
        Assert.Contains("max-width: none;", html[printIndex..]);
    }

    /// <summary>
    /// The <c>&lt;base href&gt;</c> that makes relative images work also redirects fragment-only
    /// links away from the page, so the shell ships a click handler to keep them in it.
    /// </summary>
    [Fact]
    public void InDocumentAnchorsAreHandledInThePage()
    {
        var html = MarkdownRenderer.ToHtmlDocument("[Tables](#tables)\n\n## Tables", "Doc");

        Assert.Contains("<script>", html);
        Assert.Contains("event.preventDefault();", html);
        Assert.Contains("scrollIntoView()", html);

        // The link itself is untouched: the Markdown source is never rewritten.
        Assert.Contains("""href="#tables""", html);
    }

    /// <summary>
    /// The empty viewer is a themed surface like any other, and — the point of it being here — it is
    /// produced from a theme alone. No document, no file, no rendered state is involved, which is what
    /// lets the viewer follow a theme switch made with nothing open.
    /// </summary>
    [Fact]
    public void TheEmptyViewerPageFollowsTheSelectedThemeWithoutADocument()
    {
        var light = MarkdownRenderer.ToEmptyDocument(MarkdownTheme.Light);
        var dark = MarkdownRenderer.ToEmptyDocument(MarkdownTheme.Dark);

        Assert.Contains("color-scheme: light;", light);
        Assert.Contains("--page-bg: #ffffff;", light);

        Assert.Contains("color-scheme: dark;", dark);
        Assert.Contains("--page-bg: #0d1117;", dark);

        Assert.NotEqual(light, dark);
    }

    /// <summary>
    /// Blank on purpose: the empty state exists to carry a background colour, not to become a welcome
    /// screen nobody asked for. The one thing its body does hold is the help-shortcut script, which
    /// renders nothing and is plumbing rather than content — so the assertion is that nothing
    /// <em>visible</em> survives taking the scripts out.
    /// </summary>
    [Theory]
    [InlineData(MarkdownTheme.Light)]
    [InlineData(MarkdownTheme.Dark)]
    public void TheEmptyViewerPageCarriesNoVisibleContentOfItsOwn(MarkdownTheme theme)
    {
        var html = MarkdownRenderer.ToEmptyDocument(theme);

        var bodyStart = html.IndexOf("<body>", StringComparison.Ordinal) + "<body>".Length;
        var bodyEnd = html.IndexOf("</body>", StringComparison.Ordinal);
        var body = html[bodyStart..bodyEnd];

        var withoutScripts = System.Text.RegularExpressions.Regex.Replace(
            body, "<script>.*?</script>", "", System.Text.RegularExpressions.RegexOptions.Singleline);

        Assert.True(
            string.IsNullOrWhiteSpace(withoutScripts),
            $"The empty viewer has grown content of its own: {withoutScripts}");
    }

    [Fact]
    public void TheErrorPageFollowsTheSelectedTheme()
    {
        var dark = MarkdownRenderer.ToErrorDocument("C:\\missing.md", "File not found", MarkdownTheme.Dark);
        var light = MarkdownRenderer.ToErrorDocument("C:\\missing.md", "File not found", MarkdownTheme.Light);

        Assert.Contains("color-scheme: dark;", dark);
        Assert.Contains("color-scheme: light;", light);
        Assert.Contains("File not found", dark);
    }
}
