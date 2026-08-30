using TigerMarkView.Core.Rendering;

namespace TigerMarkView.Core.Tests.Rendering;

/// <summary>
/// How a table is laid out on paper, which must be how it is laid out on screen. A PDF of a document
/// is a picture of the document the reader reviewed; a table whose columns were sized by their content
/// in the viewer and divided evenly in the export is a different table.
/// </summary>
/// <remarks>
/// The regression these guard against is <c>table-layout: fixed</c> in the print rules. It reads as the
/// cautious choice and is not: with no column widths in the markup to go on, fixed layout gives every
/// column the same width, so a Yes/No column is handed as much of the page as a paragraph of prose.
/// What actually keeps a wide table inside the page box is the cells' own wrapping.
/// </remarks>
public class PrintTableLayoutTests
{
    private static string PrintRules()
    {
        var html = MarkdownRenderer.ToHtmlDocument("# Hello", "Doc");

        return html[html.IndexOf("@media print", StringComparison.Ordinal)..];
    }

    private static string ScreenRules()
    {
        var html = MarkdownRenderer.ToHtmlDocument("# Hello", "Doc");

        return html[..html.IndexOf("@page", StringComparison.Ordinal)];
    }

    [Fact]
    public void PrintedColumnsAreSizedByTheirContent()
    {
        Assert.Contains("table-layout: auto;", PrintRules());
        Assert.DoesNotContain("table-layout: fixed;", PrintRules());
    }

    /// <summary>
    /// The screen has no <c>table-layout</c> declaration at all, which is automatic layout by default;
    /// print states the same thing explicitly because it is overriding nothing but a past mistake.
    /// </summary>
    [Fact]
    public void TheScreenAndThePageAgreeOnHowATableIsLaidOut()
    {
        Assert.DoesNotContain("table-layout", ScreenRules());
        Assert.Contains("table-layout: auto;", PrintRules());
    }

    /// <summary>
    /// A cell may break a word that will not fit the column it ended up in, but its column is still
    /// measured by that word. The distinction is the whole column layout: `overflow-wrap: anywhere`
    /// would let a cell be measured as one character wide, so every narrow column would collapse to its
    /// minimum and the column holding the longest sentence would take the rest of the page.
    /// </summary>
    [Fact]
    public void ACellBreaksALongWordWithoutBeingMeasuredAsOneCharacterWide()
    {
        Assert.Contains("th, td { padding: 4px 7px; overflow-wrap: break-word; }", PrintRules());
        Assert.DoesNotContain("th, td { padding: 4px 7px; overflow-wrap: anywhere; }", PrintRules());
    }

    /// <summary>
    /// Inline code lands in table cells constantly, so it is measured the same way. A code block is
    /// not a cell and still breaks anywhere, which is what stops a long listing line being clipped.
    /// </summary>
    [Fact]
    public void InlineCodeIsMeasuredLikeTheCellItSitsIn()
    {
        Assert.Contains("code { font-size: 9pt; background: #f2f4f6; color: #000; overflow-wrap: break-word; }", PrintRules());
        Assert.Contains("white-space: pre-wrap;", PrintRules());
    }

    /// <summary>
    /// The table still fills the measure, as it does on screen; content-driven columns share out what
    /// is left over, they do not shrink the table to its contents.
    /// </summary>
    [Fact]
    public void ATablePrintsAcrossTheFullTextWidth()
    {
        Assert.Contains("table-layout: auto;\n    width: 100%;", PrintRules().ReplaceLineEndings("\n"));
    }

    /// <summary>Long tables still break across pages, with their header repeated.</summary>
    [Fact]
    public void ATableStillPaginates()
    {
        Assert.Contains("thead { display: table-header-group; }", PrintRules());
        Assert.Contains("tr { break-inside: avoid; page-break-inside: avoid; }", PrintRules());
    }
}
