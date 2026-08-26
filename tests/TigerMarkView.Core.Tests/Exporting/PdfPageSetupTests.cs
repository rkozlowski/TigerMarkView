using TigerMarkView.Core.Exporting;

namespace TigerMarkView.Core.Tests.Exporting;

/// <summary>
/// The page-geometry model the GUI's four preferences translate into. These are the numbers a
/// finished PDF is checked against, so they are asserted in millimetres rather than through the
/// menu that happens to choose them.
/// </summary>
public class PdfPageSetupTests
{
    [Theory]
    [InlineData(PdfPaperSize.A3, 297, 420)]
    [InlineData(PdfPaperSize.A4, 210, 297)]
    [InlineData(PdfPaperSize.A5, 148, 210)]
    [InlineData(PdfPaperSize.Letter, 215.9, 279.4)]
    [InlineData(PdfPaperSize.Legal, 215.9, 355.6)]
    public void EachPaperHasItsRealPhysicalSize(PdfPaperSize paper, double widthMm, double heightMm)
    {
        var page = PdfPageSetup.For(paper, PdfOrientation.Portrait, PdfMarginPreset.Normal, showPageNumbers: false);

        Assert.Equal(widthMm, page.WidthMillimetres, 6);
        Assert.Equal(heightMm, page.HeightMillimetres, 6);
    }

    /// <summary>
    /// Landscape is a swap of the same paper, not a second set of dimensions — so nothing downstream
    /// has to know an orientation was ever chosen.
    /// </summary>
    [Theory]
    [InlineData(PdfPaperSize.A3)]
    [InlineData(PdfPaperSize.A4)]
    [InlineData(PdfPaperSize.A5)]
    [InlineData(PdfPaperSize.Letter)]
    [InlineData(PdfPaperSize.Legal)]
    public void LandscapeSwapsTheChosenPapersWidthAndHeight(PdfPaperSize paper)
    {
        var portrait = PdfPageSetup.For(paper, PdfOrientation.Portrait, PdfMarginPreset.Normal, false);
        var landscape = PdfPageSetup.For(paper, PdfOrientation.Landscape, PdfMarginPreset.Normal, false);

        Assert.Equal(portrait.HeightMillimetres, landscape.WidthMillimetres, 6);
        Assert.Equal(portrait.WidthMillimetres, landscape.HeightMillimetres, 6);

        // And it really is the wider way round, not merely a different pair of numbers.
        Assert.True(landscape.WidthMillimetres > landscape.HeightMillimetres);
        Assert.True(portrait.HeightMillimetres > portrait.WidthMillimetres);
    }

    [Theory]
    [InlineData(PdfMarginPreset.Narrow, 12, 10)]
    [InlineData(PdfMarginPreset.Normal, 18, 16)]
    [InlineData(PdfMarginPreset.Wide, 25, 25)]
    public void EachMarginPresetHasItsDocumentedPhysicalValue(
        PdfMarginPreset preset,
        double verticalMm,
        double horizontalMm)
    {
        var margins = PdfPageMargins.For(preset);

        Assert.Equal(verticalMm, margins.TopMillimetres);
        Assert.Equal(verticalMm, margins.BottomMillimetres);
        Assert.Equal(horizontalMm, margins.LeftMillimetres);
        Assert.Equal(horizontalMm, margins.RightMillimetres);
    }

    /// <summary>
    /// The presets have to be visibly different or they are three names for one layout. Expressed as
    /// printable width on A4, which is what a reader actually sees.
    /// </summary>
    [Fact]
    public void ThePresetsProduceMaterallyDifferentAndStillUsableTextColumns()
    {
        double PrintableWidth(PdfMarginPreset preset)
        {
            var page = PdfPageSetup.For(PdfPaperSize.A4, PdfOrientation.Portrait, preset, false);
            return page.WidthMillimetres - page.PrintMargins.LeftMillimetres - page.PrintMargins.RightMillimetres;
        }

        var narrow = PrintableWidth(PdfMarginPreset.Narrow);
        var normal = PrintableWidth(PdfMarginPreset.Normal);
        var wide = PrintableWidth(PdfMarginPreset.Wide);

        Assert.Equal(190, narrow);
        Assert.Equal(178, normal);
        Assert.Equal(160, wide);

        // Each step is a change a reader would notice...
        Assert.True(narrow - normal >= 10);
        Assert.True(normal - wide >= 10);

        // ...and even the tightest paper at the widest margins still leaves a usable column.
        var smallestColumn = PdfPageSetup.For(PdfPaperSize.A5, PdfOrientation.Portrait, PdfMarginPreset.Wide, false);
        Assert.True(
            smallestColumn.WidthMillimetres - (2 * 25) >= 90,
            "A5 with Wide margins must still leave a readable column.");
    }

    /// <summary>
    /// Page numbers are printed in the bottom margin band, so the band has to exist. Only Narrow is
    /// too shallow, and it is widened rather than the content being clipped to make room.
    /// </summary>
    [Theory]
    [InlineData(PdfMarginPreset.Narrow, 14)]
    [InlineData(PdfMarginPreset.Normal, 18)]
    [InlineData(PdfMarginPreset.Wide, 25)]
    public void PageNumbersReserveABottomBandWithoutEverShrinkingTheMargin(
        PdfMarginPreset preset,
        double expectedBottomMm)
    {
        var numbered = PdfPageSetup.For(PdfPaperSize.A4, PdfOrientation.Portrait, preset, showPageNumbers: true);

        Assert.Equal(expectedBottomMm, numbered.PrintMargins.BottomMillimetres);
        Assert.True(numbered.PrintMargins.BottomMillimetres >= numbered.Margins.BottomMillimetres);

        // Nothing but the bottom moves.
        Assert.Equal(numbered.Margins.TopMillimetres, numbered.PrintMargins.TopMillimetres);
        Assert.Equal(numbered.Margins.LeftMillimetres, numbered.PrintMargins.LeftMillimetres);
        Assert.Equal(numbered.Margins.RightMillimetres, numbered.PrintMargins.RightMillimetres);
    }

    [Theory]
    [InlineData(PdfMarginPreset.Narrow)]
    [InlineData(PdfMarginPreset.Normal)]
    [InlineData(PdfMarginPreset.Wide)]
    public void WithoutPageNumbersTheChosenMarginsAreUsedExactly(PdfMarginPreset preset)
    {
        var page = PdfPageSetup.For(PdfPaperSize.A4, PdfOrientation.Portrait, preset, showPageNumbers: false);

        Assert.Equal(page.Margins, page.PrintMargins);
    }

    /// <summary>
    /// What a caller that expresses no preference gets, and what the CLI therefore still produces.
    /// </summary>
    [Fact]
    public void TheDefaultIsA4PortraitWithNormalMarginsAndNoPageNumbers()
    {
        var page = PdfPageSetup.Default;

        Assert.Equal(210, page.WidthMillimetres, 6);
        Assert.Equal(297, page.HeightMillimetres, 6);
        Assert.Equal(PdfPageMargins.Normal, page.Margins);
        Assert.False(page.ShowPageNumbers);
    }

    /// <summary>
    /// Inches are a conversion for the print engine, never a stored value: rounding 297 mm to 11.69 in
    /// yields a page box a third of a point short of A4, which some readers report as a custom size.
    /// </summary>
    [Fact]
    public void InchesAreConvertedAtFullPrecision()
    {
        Assert.Equal(210.0, PdfPageSetup.Default.WidthInches * 25.4, 9);
        Assert.Equal(297.0, PdfPageSetup.Default.HeightInches * 25.4, 9);
    }
}
