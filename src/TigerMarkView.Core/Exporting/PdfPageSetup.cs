namespace TigerMarkView.Core.Exporting;

/// <summary>
/// The physical page: paper size, printable inset, and whatever is printed outside the text area.
/// </summary>
/// <remarks>
/// <para>
/// Deliberately expressed as <em>geometry</em> — millimetres on paper — rather than as the GUI's
/// choices. The desktop application offers a small closed set of presets and translates them here
/// through <see cref="For(PdfPaperSize,PdfOrientation,PdfMarginPreset,bool)"/>; a caller needing
/// precise control can construct this record directly. Neither the stylesheet nor the print engine
/// ever learns that presets exist, so adding one is a change to the translation, not to the model.
/// </para>
/// <para>
/// Orientation is likewise absent by design: <c>For</c> resolves it by swapping width and height, so
/// everything downstream sees one already-correct page box.
/// </para>
/// </remarks>
/// <param name="Margins">
/// The inset the document's <c>@page</c> rule applies. The print engine's own margins are zeroed, so
/// this is the only thing governing the printable area and one stylesheet drives screen and paper
/// alike.
/// </param>
/// <param name="Furniture">
/// The running heads and feet, or <c>null</c> for none. Read through <see cref="HeaderFooter"/>, which
/// is the same answer without the null; the parameter stays nullable so that "nothing outside the text
/// area" is one value rather than two that compare unequal.
/// </param>
public sealed record PdfPageSetup(
    double WidthMillimetres,
    double HeightMillimetres,
    PdfPageMargins Margins,
    PdfHeaderFooter? Furniture = null)
{
    private const double MillimetresPerInch = 25.4;

    /// <summary>
    /// The band a running head or foot needs at the edge of the page. Chosen to hold a line of small
    /// type clear of the text beside it; every margin preset except <see cref="PdfMarginPreset.Narrow"/>
    /// already exceeds it.
    /// </summary>
    public const double MarginBoxBandMillimetres = 14;

    /// <summary>
    /// A4 portrait, <see cref="PdfPageMargins.Normal"/> margins, nothing in the margins — what every
    /// PDF this project produced before page setup became configurable, and what a caller that
    /// expresses no preference still gets.
    /// </summary>
    public static PdfPageSetup Default { get; } =
        For(PdfPaperSize.A4, PdfOrientation.Portrait, PdfMarginPreset.Normal, showPageNumbers: false);

    /// <summary>The running heads and feet; <see cref="PdfHeaderFooter.None"/> when there are none.</summary>
    public PdfHeaderFooter HeaderFooter => Furniture ?? PdfHeaderFooter.None;

    /// <summary>
    /// Whether a page number is printed at the bottom centre of every page.
    /// </summary>
    /// <remarks>
    /// Derived rather than stored, because page numbering has exactly one implementation: the
    /// footer-centre slot holding <see cref="HeaderFooterTemplate.PageNumber"/>. The desktop
    /// application's Page Numbers tick still reads and writes a single boolean, and it still cannot
    /// disagree with what the stylesheet prints.
    /// </remarks>
    public bool ShowPageNumbers => HeaderFooter.ShowsPageNumbers;

    /// <summary>Translates the GUI's four preferences into physical page geometry.</summary>
    public static PdfPageSetup For(
        PdfPaperSize paper,
        PdfOrientation orientation,
        PdfMarginPreset margins,
        bool showPageNumbers) =>
        For(paper, orientation, margins, showPageNumbers ? PdfHeaderFooter.PageNumbers : null);

    /// <summary>
    /// The same translation, for a caller that states its running heads and feet in full rather than
    /// as the page-number shorthand.
    /// </summary>
    public static PdfPageSetup For(
        PdfPaperSize paper,
        PdfOrientation orientation,
        PdfMarginPreset margins,
        PdfHeaderFooter? headerFooter)
    {
        var (width, height) = PortraitDimensions(paper);
        var margin = PdfPageMargins.For(margins);

        // Normalised to null so that "no headers or footers" has one representation: six empty slots
        // and no slots at all describe the same page, and two page setups describing the same page
        // must compare equal.
        var furniture = headerFooter is null || headerFooter.IsEmpty ? null : headerFooter;

        return orientation == PdfOrientation.Landscape
            ? new PdfPageSetup(height, width, margin, furniture)
            : new PdfPageSetup(width, height, margin, furniture);
    }

    /// <summary>
    /// The named papers, upright, in millimetres. ISO sizes are exact by definition; Letter and Legal
    /// are the exact metric equivalents of 8.5 × 11 in and 8.5 × 14 in.
    /// </summary>
    public static (double WidthMillimetres, double HeightMillimetres) PortraitDimensions(PdfPaperSize paper) =>
        paper switch
        {
            PdfPaperSize.A3 => (297, 420),
            PdfPaperSize.A5 => (148, 210),
            PdfPaperSize.Letter => (215.9, 279.4),
            PdfPaperSize.Legal => (215.9, 355.6),
            _ => (210, 297),
        };

    /// <summary>
    /// The margins the stylesheet actually uses. A running head or foot is printed inside the margin
    /// band, so asking for one widens a margin too shallow to hold it — deterministically, and only
    /// ever outwards. Content is therefore never overprinted by a header and never clipped to make
    /// room for one; the page simply gets slightly shorter text.
    /// </summary>
    public PdfPageMargins PrintMargins
    {
        get
        {
            var margins = Margins;
            var furniture = HeaderFooter;

            if (furniture.HasHeader)
            {
                margins = margins with
                {
                    TopMillimetres = Math.Max(margins.TopMillimetres, MarginBoxBandMillimetres),
                };
            }

            if (furniture.HasFooter)
            {
                margins = margins with
                {
                    BottomMillimetres = Math.Max(margins.BottomMillimetres, MarginBoxBandMillimetres),
                };
            }

            return margins;
        }
    }

    /// <summary>
    /// The same page, with its running heads and feet resolved against <paramref name="document"/>.
    /// </summary>
    /// <remarks>
    /// Geometry is untouched — this only fills in what <c>{Title}</c>, <c>{FileName}</c> and the date
    /// placeholders print — so the setup that reaches <see cref="PdfExportRequest"/> still describes
    /// exactly the sheet the HTML was laid out for.
    /// </remarks>
    public PdfPageSetup WithDocument(PdfDocumentFacts document)
    {
        ArgumentNullException.ThrowIfNull(document);

        return Furniture is null ? this : this with { Furniture = Furniture.For(document) };
    }

    /// <remarks>
    /// Converted rather than stored: rounding 297 mm to 11.69 in yields a page box a third of a point
    /// short of A4, which some readers report as a custom size rather than A4.
    /// </remarks>
    public double WidthInches => WidthMillimetres / MillimetresPerInch;

    /// <inheritdoc cref="WidthInches"/>
    public double HeightInches => HeightMillimetres / MillimetresPerInch;
}
