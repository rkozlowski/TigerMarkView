using TigerMarkView.Core.Exporting;

namespace TigerMarkView.Cli.Tests;

/// <summary>
/// The six header and footer options as bound values: which slot each lands in, what
/// <c>--page-numbers</c> means beside them, and which templates are refused before anything is read or
/// written.
/// </summary>
/// <remarks>
/// The template language itself is Core's and is tested there. What is asserted here is only this
/// project's own part: the mapping from option to slot, the shorthand, and the fact that a malformed
/// template is a command-line error rather than a conversion that fails halfway.
/// </remarks>
public class ConvertSettingsHeaderFooterTests
{
    private static ConvertSettings Settings() => new() { Input = "notes.md" };

    [Fact]
    public void EachOptionFillsItsOwnSlot()
    {
        var settings = Settings();
        settings.HeaderLeft = "HL";
        settings.HeaderCenter = "HC";
        settings.HeaderRight = "HR";
        settings.FooterLeft = "FL";
        settings.FooterCenter = "FC";
        settings.FooterRight = "FR";

        var furniture = settings.HeaderFooter;

        Assert.Equal("HL", furniture.HeaderLeft);
        Assert.Equal("HC", furniture.HeaderCenter);
        Assert.Equal("HR", furniture.HeaderRight);
        Assert.Equal("FL", furniture.FooterLeft);
        Assert.Equal("FC", furniture.FooterCenter);
        Assert.Equal("FR", furniture.FooterRight);
    }

    /// <summary>
    /// The flag is shorthand for one template and nothing more, which is what keeps every PDF the old
    /// command line produced exactly as it was.
    /// </summary>
    [Fact]
    public void PageNumbersIsShorthandForTheFooterCentreTemplate()
    {
        var settings = Settings();
        settings.PageNumbers = true;

        Assert.Equal(HeaderFooterTemplate.PageNumber, settings.HeaderFooter.FooterCenter);
        Assert.Equal(
            PdfPageSetup.For(PdfPaperSize.A4, PdfOrientation.Portrait, PdfMarginPreset.Normal, showPageNumbers: true),
            settings.PageSetup);
    }

    /// <summary>An explicit centre footer is the more specific instruction, so the flag defers to it.</summary>
    [Fact]
    public void AnExplicitFooterCentreWinsOverTheShorthand()
    {
        var settings = Settings();
        settings.PageNumbers = true;
        settings.FooterCenter = "Page {Page} of {TotalPages}";

        Assert.Equal("Page {Page} of {TotalPages}", settings.HeaderFooter.FooterCenter);
    }

    /// <summary>The rest of the page is untouched by what is printed in its margins.</summary>
    [Fact]
    public void TemplatesReachThePageSetupWithoutDisturbingItsGeometry()
    {
        var settings = Settings();
        settings.Paper = PdfPaperSize.Letter;
        settings.Orientation = PdfOrientation.Landscape;
        settings.HeaderRight = "{Date}";

        var setup = settings.PageSetup;
        var plain = PdfPageSetup.For(
            PdfPaperSize.Letter, PdfOrientation.Landscape, PdfMarginPreset.Normal, showPageNumbers: false);

        Assert.Equal(plain.WidthMillimetres, setup.WidthMillimetres);
        Assert.Equal(plain.HeightMillimetres, setup.HeightMillimetres);
        Assert.Equal(plain.Margins, setup.Margins);
        Assert.Equal("{Date}", setup.HeaderFooter.HeaderRight);
    }

    /// <summary>With no header or footer options the page is the one the tool always produced.</summary>
    [Fact]
    public void NoTemplatesAtAllIsTheSharedDefaultPage()
    {
        Assert.Equal(PdfPageSetup.Default, Settings().PageSetup);
        Assert.True(Settings().HeaderFooter.IsEmpty);
    }

    [Fact]
    public void AUsableTemplateValidates()
    {
        var settings = Settings();
        settings.HeaderLeft = "{Title}";
        settings.FooterRight = "{Date:dd MMM yyyy} — page {Page}/{TotalPages}";

        Assert.True(settings.Validate().IsValid);
    }

    /// <summary>
    /// A mistyped placeholder is a mistyped command line: it is refused up front, by name, rather than
    /// printed as text or silently dropped from the page.
    /// </summary>
    [Fact]
    public void AMalformedTemplateFailsValidationAndSaysWhichSlot()
    {
        var settings = Settings();
        settings.FooterLeft = "{Autor}";

        var result = settings.Validate();

        Assert.False(result.IsValid);
        Assert.Contains("footer-left", result.ErrorMessage);
    }

    [Fact]
    public void TheTimestampedFallbackIsOffUnlessAskedFor()
    {
        Assert.False(Settings().TimestampedFallback);
    }
}
