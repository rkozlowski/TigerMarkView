using TigerMarkView.Core.Exporting;
using TigerMarkView.Core.Rendering;

namespace TigerMarkView.Core.Tests.Rendering;

/// <summary>
/// Running heads and feet as they actually reach a PDF: <c>@page</c> margin boxes in the generated
/// document's own stylesheet. These read the emitted CSS rather than the model, so a slot that stops
/// being written out fails here even though the page setup still holds it.
/// </summary>
public class PrintMarginBoxTests
{
    private static readonly PdfDocumentFacts Document = new(
        "Quarterly Review",
        "quarterly-review",
        "quarterly-review.md",
        @"C:\Reports\quarterly-review.md",
        new DateTimeOffset(2026, 8, 30, 14, 25, 30, TimeSpan.FromHours(2)));

    private static string Render(PdfHeaderFooter headerFooter, PdfMarginPreset margins = PdfMarginPreset.Normal)
    {
        var page = PdfPageSetup
            .For(PdfPaperSize.A4, PdfOrientation.Portrait, margins, headerFooter)
            .WithDocument(Document);

        return MarkdownRenderer.ToHtmlDocument("# Hello", "Doc", pageSetup: page);
    }

    /// <summary>The page rule only: everything after it is the fixed print stylesheet.</summary>
    private static string PageRule(string html)
    {
        var start = html.IndexOf("@page", StringComparison.Ordinal);
        var end = html.IndexOf("@media print", StringComparison.Ordinal);

        return html[start..end];
    }

    [Theory]
    [InlineData("HeaderLeft", "@top-left")]
    [InlineData("HeaderCenter", "@top-center")]
    [InlineData("HeaderRight", "@top-right")]
    [InlineData("FooterLeft", "@bottom-left")]
    [InlineData("FooterCenter", "@bottom-center")]
    [InlineData("FooterRight", "@bottom-right")]
    public void EachSlotIsWrittenAsItsOwnMarginBox(string slot, string box)
    {
        var furniture = slot switch
        {
            "HeaderLeft" => new PdfHeaderFooter(HeaderLeft: "{Title}"),
            "HeaderCenter" => new PdfHeaderFooter(HeaderCenter: "{Title}"),
            "HeaderRight" => new PdfHeaderFooter(HeaderRight: "{Title}"),
            "FooterLeft" => new PdfHeaderFooter(FooterLeft: "{Title}"),
            "FooterCenter" => new PdfHeaderFooter(FooterCenter: "{Title}"),
            _ => new PdfHeaderFooter(FooterRight: "{Title}"),
        };

        var rule = PageRule(Render(furniture));

        Assert.Contains(box + " {", rule);
        Assert.Contains("content: \"Quarterly Review\";", rule);
    }

    /// <summary>Six independent slots, printed in one pass, each with its own text.</summary>
    [Fact]
    public void AllSixSlotsCanBeFilledAtOnce()
    {
        var rule = PageRule(Render(new PdfHeaderFooter(
            HeaderLeft: "HL",
            HeaderCenter: "HC",
            HeaderRight: "HR",
            FooterLeft: "FL",
            FooterCenter: "FC",
            FooterRight: "FR")));

        foreach (var (box, text) in new[]
        {
            ("@top-left", "HL"),
            ("@top-center", "HC"),
            ("@top-right", "HR"),
            ("@bottom-left", "FL"),
            ("@bottom-center", "FC"),
            ("@bottom-right", "FR"),
        })
        {
            var boxStart = rule.IndexOf(box + " {", StringComparison.Ordinal);

            Assert.True(boxStart >= 0, $"{box} was not written");
            Assert.Contains($"content: \"{text}\";", rule[boxStart..]);
        }
    }

    /// <summary>
    /// A slot with nothing in it writes no box at all — not an empty one — so a document with no
    /// running heads has exactly the stylesheet it had before templates existed.
    /// </summary>
    [Fact]
    public void EmptySlotsLeaveNoMarginBoxBehind()
    {
        var rule = PageRule(Render(PdfHeaderFooter.None));

        foreach (var box in new[] { "@top-left", "@top-center", "@top-right", "@bottom-left", "@bottom-center", "@bottom-right" })
        {
            Assert.DoesNotContain(box, rule);
        }
    }

    [Fact]
    public void OnlyTheFilledSlotsAreWritten()
    {
        var rule = PageRule(Render(new PdfHeaderFooter(HeaderRight: "{Date}", FooterCenter: "{Page}")));

        Assert.Contains("@top-right", rule);
        Assert.Contains("@bottom-center", rule);
        Assert.DoesNotContain("@top-left", rule);
        Assert.DoesNotContain("@top-center", rule);
        Assert.DoesNotContain("@bottom-left", rule);
        Assert.DoesNotContain("@bottom-right", rule);
    }

    /// <summary>
    /// The paging placeholders have to survive into the stylesheet unresolved: nothing before the print
    /// engine knows what page this is or how many there are.
    /// </summary>
    [Fact]
    public void PagingPlaceholdersReachTheStylesheetAsCounters()
    {
        var rule = PageRule(Render(new PdfHeaderFooter(FooterCenter: "Page {Page} of {TotalPages}")));

        Assert.Contains("content: \"Page \" counter(page) \" of \" counter(pages);", rule);
    }

    /// <summary>Everything else is resolved once, before the first page, and printed as text.</summary>
    [Fact]
    public void DocumentPlaceholdersReachTheStylesheetAlreadyResolved()
    {
        var rule = PageRule(Render(new PdfHeaderFooter(HeaderLeft: "{FileNameWithExt} — {Date}")));

        Assert.Contains("content: \"quarterly-review.md — 2026-08-30\";", rule);
    }

    /// <summary>
    /// The margin the head or foot is printed in has to be deep enough to hold it, and that is decided
    /// where the page rule is written, not by hoping.
    /// </summary>
    [Fact]
    public void ARunningHeadWidensAMarginTooShallowToHoldIt()
    {
        Assert.Contains(
            "margin: 14mm 10mm 12mm 10mm;",
            Render(new PdfHeaderFooter(HeaderLeft: "{Title}"), PdfMarginPreset.Narrow));

        Assert.Contains(
            "margin: 14mm 10mm 14mm 10mm;",
            Render(new PdfHeaderFooter(HeaderLeft: "{Title}", FooterRight: "{Page}"), PdfMarginPreset.Narrow));

        // A preset that already clears the band is left exactly as chosen.
        Assert.Contains(
            "margin: 18mm 16mm 18mm 16mm;",
            Render(new PdfHeaderFooter(HeaderLeft: "{Title}"), PdfMarginPreset.Normal));
    }

    /// <summary>
    /// <c>--page-numbers</c> and a footer-centre template are the same thing, so they must produce the
    /// same stylesheet — byte for byte, page box included.
    /// </summary>
    [Fact]
    public void ThePageNumberShorthandRendersExactlyAsItsTemplateDoes()
    {
        var shorthand = MarkdownRenderer.ToHtmlDocument(
            "# Hello",
            "Doc",
            pageSetup: PdfPageSetup.For(
                PdfPaperSize.A4, PdfOrientation.Portrait, PdfMarginPreset.Narrow, showPageNumbers: true));

        var template = MarkdownRenderer.ToHtmlDocument(
            "# Hello",
            "Doc",
            pageSetup: PdfPageSetup.For(
                PdfPaperSize.A4,
                PdfOrientation.Portrait,
                PdfMarginPreset.Narrow,
                new PdfHeaderFooter(FooterCenter: HeaderFooterTemplate.PageNumber)));

        Assert.Equal(PageRule(shorthand), PageRule(template));
        Assert.Contains("content: counter(page);", PageRule(shorthand));
    }

    /// <summary>
    /// Running heads change the page box and nothing else. The typography, the pagination rules and the
    /// light palette a Dark viewer still exports are one stylesheet, whatever is printed in the margins.
    /// </summary>
    [Fact]
    public void RunningHeadsChangeNoPrintRule()
    {
        static string PrintSection(string html) =>
            html[html.IndexOf("@media print", StringComparison.Ordinal)..];

        var plain = Render(PdfHeaderFooter.None);
        var dressed = Render(new PdfHeaderFooter(HeaderLeft: "{Title}", FooterCenter: "{Page}"));

        Assert.Equal(PrintSection(plain), PrintSection(dressed));
    }

    /// <summary>
    /// A margin box sits outside the document tree and inherits none of its custom properties, so its
    /// typography is stated literally — and identically for all six, because the furniture of a page
    /// should read as one voice.
    /// </summary>
    [Fact]
    public void EveryMarginBoxIsTypesetIdentically()
    {
        var rule = PageRule(Render(new PdfHeaderFooter(HeaderLeft: "a", FooterRight: "b")));

        Assert.Equal(2, Occurrences(rule, "font-size: 9pt;"));
        Assert.Equal(2, Occurrences(rule, "color: #57606a;"));

        static int Occurrences(string text, string value)
        {
            var count = 0;

            for (var index = text.IndexOf(value, StringComparison.Ordinal); index >= 0;
                 index = text.IndexOf(value, index + value.Length, StringComparison.Ordinal))
            {
                count++;
            }

            return count;
        }
    }
}
