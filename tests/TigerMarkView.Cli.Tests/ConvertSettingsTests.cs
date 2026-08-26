using TigerMarkView.Core.Exporting;

namespace TigerMarkView.Cli.Tests;

/// <summary>
/// What the CLI's four page options mean, which is only ever "what the GUI's four preferences mean":
/// every case here asserts the settings produce the very <see cref="PdfPageSetup"/> that
/// <see cref="PdfPageSetup.For"/> produces for the same choices. There is no table of paper dimensions
/// or margin values in this project to test, and this is the test that says so.
/// </summary>
public class ConvertSettingsTests
{
    private static ConvertSettings Settings(
        PdfPaperSize? paper = null,
        PdfOrientation? orientation = null,
        PdfMarginPreset? margins = null,
        bool? pageNumbers = null)
    {
        var settings = new ConvertSettings { Input = "notes.md" };

        if (paper is { } p)
        {
            settings.Paper = p;
        }

        if (orientation is { } o)
        {
            settings.Orientation = o;
        }

        if (margins is { } m)
        {
            settings.Margins = m;
        }

        if (pageNumbers is { } n)
        {
            settings.PageNumbers = n;
        }

        return settings;
    }

    /// <summary>
    /// `tiger-mark notes.md` must keep producing the PDF it always produced. Both enums have a different
    /// first member (A3, Narrow), so the settings state their defaults explicitly rather than letting
    /// `default` decide — this is the guard on that.
    /// </summary>
    [Fact]
    public void WithNoOptionsThePageSetupIsTheSharedDefault()
    {
        Assert.Equal(PdfPageSetup.Default, Settings().PageSetup);
    }

    [Theory]
    [InlineData(PdfPaperSize.A3, 297, 420)]
    [InlineData(PdfPaperSize.A4, 210, 297)]
    [InlineData(PdfPaperSize.A5, 148, 210)]
    [InlineData(PdfPaperSize.Letter, 215.9, 279.4)]
    [InlineData(PdfPaperSize.Legal, 215.9, 355.6)]
    public void EachPaperSizeIsTheSharedModelsPaper(PdfPaperSize paper, double width, double height)
    {
        var setup = Settings(paper).PageSetup;

        Assert.Equal(width, setup.WidthMillimetres);
        Assert.Equal(height, setup.HeightMillimetres);
        Assert.Equal(PdfPageSetup.For(paper, PdfOrientation.Portrait, PdfMarginPreset.Normal, false), setup);
    }

    /// <summary>Landscape swaps the paper's own dimensions; nothing else about the page changes.</summary>
    [Theory]
    [InlineData(PdfPaperSize.A3)]
    [InlineData(PdfPaperSize.A4)]
    [InlineData(PdfPaperSize.A5)]
    [InlineData(PdfPaperSize.Letter)]
    [InlineData(PdfPaperSize.Legal)]
    public void LandscapeSwapsTheChosenPapersDimensions(PdfPaperSize paper)
    {
        var portrait = Settings(paper).PageSetup;
        var landscape = Settings(paper, PdfOrientation.Landscape).PageSetup;

        Assert.Equal(portrait.HeightMillimetres, landscape.WidthMillimetres);
        Assert.Equal(portrait.WidthMillimetres, landscape.HeightMillimetres);
        Assert.Equal(portrait.Margins, landscape.Margins);
    }

    [Theory]
    [InlineData(PdfMarginPreset.Narrow)]
    [InlineData(PdfMarginPreset.Normal)]
    [InlineData(PdfMarginPreset.Wide)]
    public void EachMarginPresetIsTheSharedModelsPreset(PdfMarginPreset preset)
    {
        Assert.Equal(PdfPageMargins.For(preset), Settings(margins: preset).PageSetup.Margins);
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void PageNumbersAreCarriedIntoThePageSetup(bool pageNumbers)
    {
        Assert.Equal(pageNumbers, Settings(pageNumbers: pageNumbers).PageSetup.ShowPageNumbers);
    }

    /// <summary>
    /// Numbering a page whose bottom margin is too shallow to hold a number widens that margin — one
    /// rule, in Core, and the CLI gets it by using the same model rather than by knowing about it.
    /// </summary>
    [Fact]
    public void NumberingANarrowPageWidensItsBottomMarginExactlyAsTheSharedModelDoes()
    {
        var numbered = Settings(margins: PdfMarginPreset.Narrow, pageNumbers: true).PageSetup;

        Assert.Equal(PdfPageSetup.PageNumberBandMillimetres, numbered.PrintMargins.BottomMillimetres);
        Assert.Equal(PdfPageMargins.For(PdfMarginPreset.Narrow).BottomMillimetres, numbered.Margins.BottomMillimetres);
    }

    /// <summary>The whole combination, against the one translation the GUI's preferences also use.</summary>
    [Fact]
    public void AllFourOptionsTogetherMatchTheSharedTranslation()
    {
        var setup = Settings(PdfPaperSize.Letter, PdfOrientation.Landscape, PdfMarginPreset.Wide, true).PageSetup;

        Assert.Equal(
            PdfPageSetup.For(PdfPaperSize.Letter, PdfOrientation.Landscape, PdfMarginPreset.Wide, true),
            setup);
    }
}
