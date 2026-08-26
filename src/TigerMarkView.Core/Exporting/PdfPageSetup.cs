namespace TigerMarkView.Core.Exporting;

/// <summary>
/// The physical page: paper size, printable inset, and whether pages are numbered.
/// </summary>
/// <remarks>
/// <para>
/// Deliberately expressed as <em>geometry</em> — millimetres on paper — rather than as the GUI's
/// choices. The desktop application offers a small closed set of presets and translates them here
/// through <see cref="For"/>; a caller needing precise control can construct this record directly.
/// Neither the stylesheet nor the print engine
/// ever learns that presets exist, so adding one is a change to the translation, not to the model.
/// </para>
/// <para>
/// Orientation is likewise absent by design: <see cref="For"/> resolves it by swapping width and
/// height, so everything downstream sees one already-correct page box.
/// </para>
/// </remarks>
/// <param name="Margins">
/// The inset the document's <c>@page</c> rule applies. The print engine's own margins are zeroed, so
/// this is the only thing governing the printable area and one stylesheet drives screen and paper
/// alike.
/// </param>
/// <param name="ShowPageNumbers">
/// Whether a page number is printed at the bottom centre of every page. See <see cref="PrintMargins"/>
/// for how it interacts with <paramref name="Margins"/>.
/// </param>
public sealed record PdfPageSetup(
    double WidthMillimetres,
    double HeightMillimetres,
    PdfPageMargins Margins,
    bool ShowPageNumbers = false)
{
    private const double MillimetresPerInch = 25.4;

    /// <summary>
    /// The band a page number needs at the foot of the page. Chosen to hold the number clear of the
    /// text above it; every preset except <see cref="PdfMarginPreset.Narrow"/> already exceeds it.
    /// </summary>
    public const double PageNumberBandMillimetres = 14;

    /// <summary>
    /// A4 portrait, <see cref="PdfPageMargins.Normal"/> margins, no page numbers — what every PDF this
    /// project produced before page setup became configurable, and what a caller that expresses no
    /// preference still gets.
    /// </summary>
    public static PdfPageSetup Default { get; } =
        For(PdfPaperSize.A4, PdfOrientation.Portrait, PdfMarginPreset.Normal, showPageNumbers: false);

    /// <summary>Translates the GUI's four preferences into physical page geometry.</summary>
    public static PdfPageSetup For(
        PdfPaperSize paper,
        PdfOrientation orientation,
        PdfMarginPreset margins,
        bool showPageNumbers)
    {
        var (width, height) = PortraitDimensions(paper);
        var margin = PdfPageMargins.For(margins);

        return orientation == PdfOrientation.Landscape
            ? new PdfPageSetup(height, width, margin, showPageNumbers)
            : new PdfPageSetup(width, height, margin, showPageNumbers);
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
    /// The margins the stylesheet actually uses. A page number is printed inside the bottom margin
    /// band, so switching numbering on widens a bottom margin too small to hold one — deterministically,
    /// and only ever outwards. Content is therefore never overprinted by a number and never clipped to
    /// make room for one; the page simply gets slightly shorter text.
    /// </summary>
    public PdfPageMargins PrintMargins => ShowPageNumbers
        ? Margins with { BottomMillimetres = Math.Max(Margins.BottomMillimetres, PageNumberBandMillimetres) }
        : Margins;

    /// <remarks>
    /// Converted rather than stored: rounding 297 mm to 11.69 in yields a page box a third of a point
    /// short of A4, which some readers report as a custom size rather than A4.
    /// </remarks>
    public double WidthInches => WidthMillimetres / MillimetresPerInch;

    /// <inheritdoc cref="WidthInches"/>
    public double HeightInches => HeightMillimetres / MillimetresPerInch;
}
