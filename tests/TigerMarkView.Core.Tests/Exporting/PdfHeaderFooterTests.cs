using TigerMarkView.Core.Exporting;

namespace TigerMarkView.Core.Tests.Exporting;

/// <summary>
/// The six slots as a model: what counts as a head, what counts as a foot, how much page each
/// reserves, and the one thing page numbering is — the footer-centre slot with the simplest possible
/// template in it.
/// </summary>
public class PdfHeaderFooterTests
{
    private static PdfPageSetup Page(PdfHeaderFooter headerFooter, PdfMarginPreset margins = PdfMarginPreset.Normal) =>
        PdfPageSetup.For(PdfPaperSize.A4, PdfOrientation.Portrait, margins, headerFooter);

    [Fact]
    public void NothingInAnySlotIsNothingAtAll()
    {
        Assert.True(PdfHeaderFooter.None.IsEmpty);
        Assert.False(PdfHeaderFooter.None.HasHeader);
        Assert.False(PdfHeaderFooter.None.HasFooter);
    }

    /// <summary>Whitespace is not content, and must not reserve a band of margin.</summary>
    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public void ASlotOfWhitespaceIsAnEmptySlot(string? template)
    {
        Assert.True(new PdfHeaderFooter(HeaderLeft: template, FooterRight: template).IsEmpty);
    }

    [Theory]
    [InlineData("left", null, null, true, false)]
    [InlineData(null, "center", null, true, false)]
    [InlineData(null, null, "right", true, false)]
    public void AnyHeadSlotMakesAHeader(string? left, string? center, string? right, bool header, bool footer)
    {
        var furniture = new PdfHeaderFooter(HeaderLeft: left, HeaderCenter: center, HeaderRight: right);

        Assert.Equal(header, furniture.HasHeader);
        Assert.Equal(footer, furniture.HasFooter);
    }

    [Theory]
    [InlineData("left", null, null)]
    [InlineData(null, "center", null)]
    [InlineData(null, null, "right")]
    public void AnyFootSlotMakesAFooter(string? left, string? center, string? right)
    {
        var furniture = new PdfHeaderFooter(FooterLeft: left, FooterCenter: center, FooterRight: right);

        Assert.True(furniture.HasFooter);
        Assert.False(furniture.HasHeader);
    }

    /// <summary>
    /// Page numbering is not a setting beside the six slots; it is one of them, which is why the flag
    /// and the option produce the very same page.
    /// </summary>
    [Fact]
    public void PageNumberingIsTheFooterCentreSlotAndNothingMore()
    {
        Assert.Equal(HeaderFooterTemplate.PageNumber, PdfHeaderFooter.PageNumbers.FooterCenter);
        Assert.True(PdfHeaderFooter.PageNumbers.ShowsPageNumbers);

        Assert.Equal(
            PdfPageSetup.For(PdfPaperSize.A4, PdfOrientation.Portrait, PdfMarginPreset.Normal, showPageNumbers: true),
            Page(new PdfHeaderFooter(FooterCenter: "{Page}")));
    }

    /// <summary>
    /// The desktop application still reads its Page Numbers tick off the page setup as the single
    /// boolean it has always been.
    /// </summary>
    [Fact]
    public void ThePageNumbersFlagCanStillBeReadBackOffAPageSetup()
    {
        Assert.True(Page(PdfHeaderFooter.PageNumbers).ShowPageNumbers);
        Assert.False(Page(PdfHeaderFooter.None).ShowPageNumbers);
        Assert.False(Page(new PdfHeaderFooter(FooterCenter: "Page {Page}")).ShowPageNumbers);
    }

    /// <summary>
    /// Six empty slots and no slots at all describe the same page, so two setups describing the same
    /// page must compare equal — otherwise a plain `tiger-mark notes.md` would stop matching the
    /// shared default.
    /// </summary>
    [Fact]
    public void EmptySlotsAreTheSamePageAsNoSlots()
    {
        Assert.Equal(PdfPageSetup.Default, Page(PdfHeaderFooter.None));
        Assert.Equal(PdfPageSetup.Default, Page(new PdfHeaderFooter(HeaderLeft: "  ")));
        Assert.Null(Page(PdfHeaderFooter.None).Furniture);
    }

    /// <summary>
    /// A head or foot is printed inside the margin, so a margin too shallow to hold one is widened —
    /// deterministically, only outwards, and only on the edge that has something on it.
    /// </summary>
    [Theory]
    [InlineData(PdfMarginPreset.Narrow, 14)]
    [InlineData(PdfMarginPreset.Normal, 18)]
    [InlineData(PdfMarginPreset.Wide, 25)]
    public void AHeaderReservesABandAtTheTopWithoutEverShrinkingTheMargin(
        PdfMarginPreset preset,
        double expectedTopMm)
    {
        var page = Page(new PdfHeaderFooter(HeaderRight: "{Page}"), preset);

        Assert.Equal(expectedTopMm, page.PrintMargins.TopMillimetres);
        Assert.Equal(page.Margins.BottomMillimetres, page.PrintMargins.BottomMillimetres);
    }

    [Theory]
    [InlineData(PdfMarginPreset.Narrow, 14)]
    [InlineData(PdfMarginPreset.Normal, 18)]
    [InlineData(PdfMarginPreset.Wide, 25)]
    public void AFooterReservesABandAtTheFootWithoutEverShrinkingTheMargin(
        PdfMarginPreset preset,
        double expectedBottomMm)
    {
        var page = Page(new PdfHeaderFooter(FooterLeft: "{Title}"), preset);

        Assert.Equal(expectedBottomMm, page.PrintMargins.BottomMillimetres);
        Assert.Equal(page.Margins.TopMillimetres, page.PrintMargins.TopMillimetres);
    }

    [Fact]
    public void HeadAndFootTogetherReserveBothBandsAndNothingSideways()
    {
        var page = Page(
            new PdfHeaderFooter(HeaderCenter: "{Title}", FooterCenter: "{Page}"),
            PdfMarginPreset.Narrow);

        Assert.Equal(PdfPageSetup.MarginBoxBandMillimetres, page.PrintMargins.TopMillimetres);
        Assert.Equal(PdfPageSetup.MarginBoxBandMillimetres, page.PrintMargins.BottomMillimetres);
        Assert.Equal(page.Margins.LeftMillimetres, page.PrintMargins.LeftMillimetres);
        Assert.Equal(page.Margins.RightMillimetres, page.PrintMargins.RightMillimetres);
    }

    /// <summary>Resolving a document fills in what is printed and changes no geometry.</summary>
    [Fact]
    public void ResolvingADocumentLeavesThePageItselfAlone()
    {
        var facts = new PdfDocumentFacts("T", "f", "f.md", @"C:\f.md", DateTimeOffset.UnixEpoch);
        var page = Page(new PdfHeaderFooter(HeaderLeft: "{Title}"));

        var resolved = page.WithDocument(facts);

        Assert.Same(facts, resolved.HeaderFooter.Document);
        Assert.Equal(page.WidthMillimetres, resolved.WidthMillimetres);
        Assert.Equal(page.HeightMillimetres, resolved.HeightMillimetres);
        Assert.Equal(page.PrintMargins, resolved.PrintMargins);
    }

    /// <summary>A page with nothing in its margins has nothing to resolve.</summary>
    [Fact]
    public void ResolvingADocumentOnAPlainPageChangesNothing()
    {
        var facts = new PdfDocumentFacts("T", "f", "f.md", @"C:\f.md", DateTimeOffset.UnixEpoch);

        Assert.Same(PdfPageSetup.Default, PdfPageSetup.Default.WithDocument(facts));
    }

    /// <summary>Every slot is reported by name, because "one of them is wrong" is not actionable.</summary>
    [Theory]
    [InlineData("header-left")]
    [InlineData("header-center")]
    [InlineData("header-right")]
    [InlineData("footer-left")]
    [InlineData("footer-center")]
    [InlineData("footer-right")]
    public void AMalformedSlotIsReportedByName(string slot)
    {
        var bad = "{Nope}";

        var furniture = slot switch
        {
            "header-left" => new PdfHeaderFooter(HeaderLeft: bad),
            "header-center" => new PdfHeaderFooter(HeaderCenter: bad),
            "header-right" => new PdfHeaderFooter(HeaderRight: bad),
            "footer-left" => new PdfHeaderFooter(FooterLeft: bad),
            "footer-center" => new PdfHeaderFooter(FooterCenter: bad),
            _ => new PdfHeaderFooter(FooterRight: bad),
        };

        var error = furniture.Validate();

        Assert.NotNull(error);
        Assert.Contains(slot, error);
    }

    [Fact]
    public void UsableSlotsValidateWithoutAnError()
    {
        Assert.Null(new PdfHeaderFooter(
            HeaderLeft: "{Title}",
            HeaderRight: "{Date:yyyy}",
            FooterCenter: "Page {Page} of {TotalPages}").Validate());
    }
}
