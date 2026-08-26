using TigerMarkView.Core.Exporting;
using TigerMarkView.Core.Rendering;

namespace TigerMarkView.Core.Tests.Rendering;

/// <summary>
/// The page setup has to survive the trip into the generated document, because the <c>@page</c> rule
/// is the only thing that governs the printable area — the print engine's own margins are zeroed.
/// These tests read the emitted CSS rather than the model, so a setting that stops being written out
/// fails here even though the model still holds it.
/// </summary>
public class PrintPageRuleTests
{
    [Theory]
    [InlineData(PdfPaperSize.A3, PdfOrientation.Portrait, "size: 297mm 420mm;")]
    [InlineData(PdfPaperSize.A3, PdfOrientation.Landscape, "size: 420mm 297mm;")]
    [InlineData(PdfPaperSize.A4, PdfOrientation.Portrait, "size: 210mm 297mm;")]
    [InlineData(PdfPaperSize.A4, PdfOrientation.Landscape, "size: 297mm 210mm;")]
    [InlineData(PdfPaperSize.A5, PdfOrientation.Portrait, "size: 148mm 210mm;")]
    [InlineData(PdfPaperSize.Letter, PdfOrientation.Portrait, "size: 215.9mm 279.4mm;")]
    [InlineData(PdfPaperSize.Legal, PdfOrientation.Portrait, "size: 215.9mm 355.6mm;")]
    public void ThePaperAndOrientationReachThePageRule(
        PdfPaperSize paper,
        PdfOrientation orientation,
        string expected)
    {
        Assert.Contains(expected, Render(paper, orientation, PdfMarginPreset.Normal, pageNumbers: false));
    }

    [Theory]
    [InlineData(PdfMarginPreset.Narrow, "margin: 12mm 10mm 12mm 10mm;")]
    [InlineData(PdfMarginPreset.Normal, "margin: 18mm 16mm 18mm 16mm;")]
    [InlineData(PdfMarginPreset.Wide, "margin: 25mm 25mm 25mm 25mm;")]
    public void TheMarginPresetReachesThePageRule(PdfMarginPreset preset, string expected)
    {
        Assert.Contains(expected, Render(PdfPaperSize.A4, PdfOrientation.Portrait, preset, pageNumbers: false));
    }

    /// <summary>
    /// Page numbering is a CSS margin box, so "on" is the presence of one rule and "off" is its
    /// complete absence — there is no empty footer left behind taking up space.
    /// </summary>
    [Fact]
    public void PageNumbersAddABottomCentreCounterAndNothingElse()
    {
        var numbered = Render(PdfPaperSize.A4, PdfOrientation.Portrait, PdfMarginPreset.Normal, pageNumbers: true);

        Assert.Contains("@bottom-center", numbered);
        Assert.Contains("content: counter(page);", numbered);
    }

    [Fact]
    public void PageNumbersOffLeavesNoFooterRuleAtAll()
    {
        var plain = Render(PdfPaperSize.A4, PdfOrientation.Portrait, PdfMarginPreset.Normal, pageNumbers: false);

        Assert.DoesNotContain("@bottom-center", plain);
        Assert.DoesNotContain("counter(page)", plain);
    }

    /// <summary>
    /// The one interaction between two of these settings, and it is deterministic: Narrow's 12 mm
    /// bottom margin is widened to the page-number band, so a number never lands on the text.
    /// </summary>
    [Fact]
    public void NarrowMarginsAreWidenedAtTheFootWhenPagesAreNumbered()
    {
        Assert.Contains(
            "margin: 12mm 10mm 14mm 10mm;",
            Render(PdfPaperSize.A4, PdfOrientation.Portrait, PdfMarginPreset.Narrow, pageNumbers: true));

        // The presets that already clear the band are left exactly as chosen.
        Assert.Contains(
            "margin: 18mm 16mm 18mm 16mm;",
            Render(PdfPaperSize.A4, PdfOrientation.Portrait, PdfMarginPreset.Normal, pageNumbers: true));
    }

    /// <summary>
    /// Letter is 215.9 mm wide, so a machine with a decimal comma would otherwise emit
    /// <c>215,9mm</c> — a syntax error the stylesheet silently drops, taking the page size with it.
    /// </summary>
    [Fact]
    public void PhysicalLengthsAreWrittenWithADecimalPointWhateverTheCulture()
    {
        var previous = Thread.CurrentThread.CurrentCulture;
        Thread.CurrentThread.CurrentCulture = new System.Globalization.CultureInfo("pl-PL");

        try
        {
            Assert.Contains(
                "size: 215.9mm 279.4mm;",
                Render(PdfPaperSize.Letter, PdfOrientation.Portrait, PdfMarginPreset.Normal, false));
        }
        finally
        {
            Thread.CurrentThread.CurrentCulture = previous;
        }
    }

    /// <summary>
    /// Only the page box varies. Everything inside <c>@media print</c> — the typography, the
    /// pagination rules, the light palette a Dark viewer still exports — is the same stylesheet
    /// whatever paper was chosen.
    /// </summary>
    [Fact]
    public void ChangingThePageSetupDoesNotChangeAnyPrintRule()
    {
        static string PrintSection(string html) =>
            html[html.IndexOf("@media print", StringComparison.Ordinal)..];

        var a5 = Render(PdfPaperSize.A5, PdfOrientation.Landscape, PdfMarginPreset.Wide, pageNumbers: true);
        var a4 = Render(PdfPaperSize.A4, PdfOrientation.Portrait, PdfMarginPreset.Normal, pageNumbers: false);

        Assert.Equal(PrintSection(a4), PrintSection(a5));
    }

    /// <summary>
    /// A rendered document carries the setup it was rendered for, so an export can print the paper the
    /// HTML was laid out on rather than whatever the preferences say by then.
    /// </summary>
    [Fact]
    public void ARenderedDocumentRemembersItsPageSetupAndCanBeRelaidOutWithoutReadingTheFile()
    {
        var path = Path.Combine(Path.GetTempPath(), $"tmv-page-setup-{Guid.NewGuid():N}.md");
        File.WriteAllText(path, "# Hello");

        try
        {
            var a4 = RenderedDocument.Load(path, MarkdownTheme.Light, PdfPageSetup.Default);
            Assert.Equal(PdfPageSetup.Default, a4.PageSetup);
            Assert.Contains("size: 210mm 297mm;", a4.Html);

            var a5 = PdfPageSetup.For(PdfPaperSize.A5, PdfOrientation.Landscape, PdfMarginPreset.Wide, true);

            // Changed underneath, to prove the re-render comes from the retained Markdown.
            File.WriteAllText(path, "# A newer version nobody has read");
            var relaid = a4.WithPageSetup(a5);

            Assert.Equal(a5, relaid.PageSetup);
            Assert.Contains("size: 210mm 148mm;", relaid.Html);
            Assert.Contains("Hello", relaid.Html);
            Assert.DoesNotContain("newer version", relaid.Html);

            // Same version, same theme, same everything else.
            Assert.Equal(a4.Markdown, relaid.Markdown);
            Assert.Equal(a4.Theme, relaid.Theme);
            Assert.Equal(a4.SourceTimestampUtc, relaid.SourceTimestampUtc);
        }
        finally
        {
            File.Delete(path);
        }
    }

    private static string Render(
        PdfPaperSize paper,
        PdfOrientation orientation,
        PdfMarginPreset margins,
        bool pageNumbers) =>
        MarkdownRenderer.ToHtmlDocument(
            "# Hello",
            "Doc",
            pageSetup: PdfPageSetup.For(paper, orientation, margins, pageNumbers));
}
