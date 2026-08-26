using TigerMarkView.Core.Exporting;
using TigerMarkView.Core.Printing;

namespace TigerMarkView.Core.Tests.Printing;

/// <summary>
/// Reading a finished page back as the paper and orientation a printer speaks in, so the Windows print
/// dialog opens on the page the reader is actually printing. Everything here is a <em>description</em>
/// of an already-laid-out PDF; nothing in the rendering or export path consults it.
/// </summary>
public class PrinterPageDefaultsTests
{
    [Theory]
    [InlineData(PdfPaperSize.A3)]
    [InlineData(PdfPaperSize.A4)]
    [InlineData(PdfPaperSize.A5)]
    [InlineData(PdfPaperSize.Letter)]
    [InlineData(PdfPaperSize.Legal)]
    public void EveryNamedPaperIsRecognisedUpright(PdfPaperSize paper)
    {
        var setup = PdfPageSetup.For(paper, PdfOrientation.Portrait, PdfMarginPreset.Normal, showPageNumbers: false);

        var defaults = PrinterPageDefaults.For(setup);

        Assert.Equal(paper, defaults.Paper);
        Assert.Equal(PdfOrientation.Portrait, defaults.Orientation);
    }

    /// <summary>
    /// A landscape page is the same paper turned round, not a sixth paper size — which is the whole
    /// point of matching against the upright table rather than against the page as it stands.
    /// </summary>
    [Theory]
    [InlineData(PdfPaperSize.A3)]
    [InlineData(PdfPaperSize.A4)]
    [InlineData(PdfPaperSize.A5)]
    [InlineData(PdfPaperSize.Letter)]
    [InlineData(PdfPaperSize.Legal)]
    public void EveryNamedPaperIsRecognisedLandscapeToo(PdfPaperSize paper)
    {
        var setup = PdfPageSetup.For(paper, PdfOrientation.Landscape, PdfMarginPreset.Normal, showPageNumbers: false);

        var defaults = PrinterPageDefaults.For(setup);

        Assert.Equal(paper, defaults.Paper);
        Assert.Equal(PdfOrientation.Landscape, defaults.Orientation);
    }

    /// <summary>
    /// The two answers the print dialog is opened on, stated the way the GUI states them: whatever the
    /// document's configured PDF page setup is what the dialog shows.
    /// </summary>
    [Theory]
    [InlineData(PdfOrientation.Portrait)]
    [InlineData(PdfOrientation.Landscape)]
    public void TheOrientationIsTheOneTheDocumentWasLaidOutFor(PdfOrientation orientation)
    {
        var setup = PdfPageSetup.For(PdfPaperSize.A5, orientation, PdfMarginPreset.Narrow, showPageNumbers: true);

        Assert.Equal(orientation, PrinterPageDefaults.For(setup).Orientation);
    }

    /// <summary>
    /// Orientation is derived from the page, not remembered from a preference, so a directly built
    /// setup is read correctly without having stated an orientation at all.
    /// </summary>
    [Fact]
    public void ADirectlyBuiltPageIsReadFromItsDimensions()
    {
        var wide = new PdfPageSetup(300, 200, PdfPageMargins.For(PdfMarginPreset.Normal));
        var tall = new PdfPageSetup(200, 300, PdfPageMargins.For(PdfMarginPreset.Normal));

        Assert.Equal(PdfOrientation.Landscape, PrinterPageDefaults.For(wide).Orientation);
        Assert.Equal(PdfOrientation.Portrait, PrinterPageDefaults.For(tall).Orientation);
    }

    /// <summary>
    /// A square page is not landscape. Nothing produces one today; the point is that the rule is
    /// "wider than it is tall", with no ambiguous middle.
    /// </summary>
    [Fact]
    public void ASquarePageIsPortrait()
    {
        var square = new PdfPageSetup(200, 200, PdfPageMargins.For(PdfMarginPreset.Normal));

        Assert.Equal(PdfOrientation.Portrait, PrinterPageDefaults.For(square).Orientation);
    }

    /// <summary>
    /// A page of no named size has no name, and the caller leaves the printer's own media alone rather
    /// than forcing it to something approximate.
    /// </summary>
    [Fact]
    public void AnUnnamedPageSizeIsNotGuessedAt()
    {
        var custom = new PdfPageSetup(180, 240, PdfPageMargins.For(PdfMarginPreset.Normal));

        Assert.Null(PrinterPageDefaults.For(custom).Paper);
        Assert.Equal(PdfOrientation.Portrait, PrinterPageDefaults.For(custom).Orientation);
    }

    /// <summary>
    /// The tolerance absorbs rounding, not a different paper: a page a fifth of a millimetre off A4 is
    /// still A4, and A5 — the nearest named size to it — is never mistaken for it.
    /// </summary>
    [Fact]
    public void ASlightlyRoundedPageStillNamesItsPaper()
    {
        var nearlyA4 = new PdfPageSetup(209.8, 297.2, PdfPageMargins.For(PdfMarginPreset.Normal));

        Assert.Equal(PdfPaperSize.A4, PrinterPageDefaults.For(nearlyA4).Paper);
    }

    [Fact]
    public void MarginsAndPageNumbersDoNotAffectTheAnswer()
    {
        var plain = PdfPageSetup.For(PdfPaperSize.Letter, PdfOrientation.Landscape, PdfMarginPreset.Wide, false);
        var numbered = PdfPageSetup.For(PdfPaperSize.Letter, PdfOrientation.Landscape, PdfMarginPreset.Narrow, true);

        Assert.Equal(PrinterPageDefaults.For(plain), PrinterPageDefaults.For(numbered));
    }

    /// <summary>
    /// The page a caller expressing no preference gets, read back: A4 upright. This is the pairing the
    /// print dialog opens on for the overwhelming majority of documents.
    /// </summary>
    [Fact]
    public void TheDefaultPageIsA4Portrait()
    {
        var defaults = PrinterPageDefaults.For(PdfPageSetup.Default);

        Assert.Equal(PdfPaperSize.A4, defaults.Paper);
        Assert.Equal(PdfOrientation.Portrait, defaults.Orientation);
    }
}
