using TigerMarkView.Core.Exporting;

namespace TigerMarkView.Core.Printing;

/// <summary>
/// A page setup read back as the named media and orientation a printer speaks in, so the Windows print
/// dialog can open showing the page the reader is actually printing.
/// </summary>
/// <remarks>
/// <para>
/// <strong>This is a description of a finished document, never an instruction to lay one out.</strong>
/// <see cref="PdfPageSetup"/> deliberately carries no paper name and no orientation — it is millimetres,
/// and everything that lays a page out reads it that way. By the time this type is asked anything the
/// PDF has already been written: the sheet is fixed, and all that is left is telling the print dialog
/// what it is looking at. Nothing in the rendering or export path may consult it.
/// </para>
/// <para>
/// The table it matches against is <see cref="PdfPageSetup.PortraitDimensions"/>' own, read backwards,
/// which is the whole reason this lives in Core beside it: a second copy of five paper sizes is exactly
/// the kind of duplication that goes quietly out of step. A page that is not one of the named sizes —
/// which today only a directly constructed <see cref="PdfPageSetup"/> can be — simply has no name, and
/// the printer's own media choice is left alone rather than being forced to something approximate.
/// </para>
/// </remarks>
/// <param name="Paper">
/// The named paper the page matches, or <see langword="null"/> when it matches none of them.
/// </param>
/// <param name="Orientation">
/// Which way round the page is, derived from the dimensions rather than remembered — a landscape page
/// is one wider than it is tall, whoever built it and whether or not they thought in orientations.
/// </param>
public readonly record struct PrinterPageDefaults(PdfPaperSize? Paper, PdfOrientation Orientation)
{
    /// <summary>
    /// How far a page may sit from a named size and still be called it. Generous enough to absorb the
    /// rounding of a page built from inches, far tighter than the gap between any two named sizes.
    /// </summary>
    private const double ToleranceMillimetres = 0.5;

    /// <summary>Reads <paramref name="page"/> as a printer would describe it.</summary>
    public static PrinterPageDefaults For(PdfPageSetup page)
    {
        ArgumentNullException.ThrowIfNull(page);

        var landscape = page.WidthMillimetres > page.HeightMillimetres;

        // Named sizes are tabulated upright, so a landscape page is matched by its own upright form —
        // A4 landscape is A4 paper turned round, not a sixth paper size.
        var width = landscape ? page.HeightMillimetres : page.WidthMillimetres;
        var height = landscape ? page.WidthMillimetres : page.HeightMillimetres;

        return new PrinterPageDefaults(
            MatchNamedPaper(width, height),
            landscape ? PdfOrientation.Landscape : PdfOrientation.Portrait);
    }

    private static PdfPaperSize? MatchNamedPaper(double widthMillimetres, double heightMillimetres)
    {
        foreach (var paper in Enum.GetValues<PdfPaperSize>())
        {
            var (width, height) = PdfPageSetup.PortraitDimensions(paper);

            if (Math.Abs(width - widthMillimetres) <= ToleranceMillimetres &&
                Math.Abs(height - heightMillimetres) <= ToleranceMillimetres)
            {
                return paper;
            }
        }

        return null;
    }
}
