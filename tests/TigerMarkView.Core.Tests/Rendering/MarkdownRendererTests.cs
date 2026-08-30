using TigerMarkView.Core.Rendering;

namespace TigerMarkView.Core.Tests.Rendering;

public class MarkdownRendererTests
{
    [Fact]
    public void RendersHeadings()
    {
        var html = MarkdownRenderer.ToHtmlFragment("# Title\n\n## Subtitle");

        Assert.Contains("<h1", html);
        Assert.Contains(">Title</h1>", html);
        Assert.Contains("<h2", html);
        Assert.Contains(">Subtitle</h2>", html);
    }

    [Fact]
    public void RendersGfmTables()
    {
        const string markdown = """
            | Mode   | Behavior       |
            |--------|----------------|
            | Manual | Status bar     |
            """;

        var html = MarkdownRenderer.ToHtmlFragment(markdown);

        Assert.Contains("<table>", html);
        Assert.Contains("<th>Mode</th>", html);
        Assert.Contains("<td>Manual</td>", html);
    }

    [Fact]
    public void RendersFencedCodeBlocksWithLanguageClass()
    {
        const string markdown = """
            ```csharp
            var x = 1;
            ```
            """;

        var html = MarkdownRenderer.ToHtmlFragment(markdown);

        Assert.Contains("<pre>", html);
        Assert.Contains("language-csharp", html);
        Assert.Contains("var x = 1;", html);
    }

    [Fact]
    public void RendersGfmAutolinks()
    {
        var html = MarkdownRenderer.ToHtmlFragment("See https://example.com for details.");

        Assert.Contains("<a href=\"https://example.com\"", html);
    }

    [Fact]
    public void RendersTaskLists()
    {
        const string markdown = """
            - [x] Done
            - [ ] Not done
            """;

        var html = MarkdownRenderer.ToHtmlFragment(markdown);

        Assert.Contains("type=\"checkbox\"", html);
        Assert.Contains("checked=\"checked\"", html);
    }

    [Fact]
    public void ToHtmlDocumentWrapsFragmentWithTitleAndCss()
    {
        var doc = MarkdownRenderer.ToHtmlDocument("# Hello", "My Doc");

        Assert.Contains("<title>My Doc</title>", doc);
        Assert.Contains("<h1", doc);
        Assert.Contains("font-family", doc);
    }

    [Fact]
    public void ToHtmlDocumentEmitsBaseHrefWhenProvided()
    {
        var doc = MarkdownRenderer.ToHtmlDocument("# Hello", "My Doc", "file:///C:/docs/");

        Assert.Contains("""<base href="file:///C:/docs/" />""", doc);
    }

    /// <summary>
    /// The same generated HTML has to drive both the on-screen viewer and PDF export, so the print
    /// rules travel inside the document rather than being injected by the exporter.
    /// </summary>
    [Fact]
    public void ToHtmlDocumentIncludesPrintStylesAlongsideScreenStyles()
    {
        var doc = MarkdownRenderer.ToHtmlDocument("# Hello", "My Doc");

        Assert.Contains("@page", doc);

        // The page box is now written from the page setup, so the default document states A4's
        // physical size rather than the CSS keyword.
        Assert.Contains("size: 210mm 297mm;", doc);
        Assert.Contains("@media print", doc);

        // Screen styling is still present and unscoped — print CSS is layered on, not swapped in.
        Assert.Contains("line-height: 1.6;", doc);
    }

    [Theory]
    [InlineData("break-after: avoid;")]      // headings not stranded at a page foot
    [InlineData("display: table-header-group;")] // table headers repeat across pages
    [InlineData("table-layout: auto;")]      // table columns sized by their content, as on screen
    [InlineData("overflow-wrap: break-word;")] // and cells break a word too long for their column
    [InlineData("white-space: pre-wrap;")]   // long code lines wrap instead of clipping
    [InlineData("max-width: 100%;")]         // images constrained to the content width
    public void PrintStylesCoverThePaginationRulesPhase6Requires(string expectedRule)
    {
        var doc = MarkdownRenderer.ToHtmlDocument("# Hello", "My Doc");
        var printSection = doc[doc.IndexOf("@media print", StringComparison.Ordinal)..];

        Assert.Contains(expectedRule, printSection);
    }

    [Fact]
    public void ToErrorDocumentEscapesAndIncludesMessage()
    {
        var doc = MarkdownRenderer.ToErrorDocument("C:\\missing<>.md", "File not found");

        Assert.Contains("File not found", doc);
        Assert.Contains("missing&lt;&gt;.md", doc);
    }
}
