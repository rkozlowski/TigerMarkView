namespace TigerMarkView.Core.Exporting;

/// <summary>
/// The printable area's inset from the paper edge, in millimetres.
/// </summary>
/// <remarks>
/// <para>
/// Millimetres, not pixels: this is physical paper geometry, and a pixel has no size until something
/// decides a resolution. The <c>@page</c> rule these values become is the only thing that governs the
/// printable area — the print engine's own margins are zeroed (see <see cref="PdfPageSetup"/>).
/// </para>
/// <para>
/// The three preset values are the whole margin vocabulary of the GUI.
/// <see cref="PdfMarginPreset.Normal"/> is 18 mm vertically and 16 mm horizontally.
/// </para>
/// </remarks>
public sealed record PdfPageMargins(
    double TopMillimetres,
    double RightMillimetres,
    double BottomMillimetres,
    double LeftMillimetres)
{
    /// <summary>
    /// A symmetric margin, the shape all three presets happen to have. Kept as a constructor rather
    /// than repeated four-argument literals so a preset reads as the two numbers it actually is.
    /// </summary>
    public PdfPageMargins(double verticalMillimetres, double horizontalMillimetres)
        : this(verticalMillimetres, horizontalMillimetres, verticalMillimetres, horizontalMillimetres)
    {
    }

    /// <summary>
    /// The physical value of each preset, in one place. Anything that needs to know what "Normal"
    /// means asks here; nothing else states a margin number.
    /// </summary>
    public static PdfPageMargins For(PdfMarginPreset preset) => preset switch
    {
        PdfMarginPreset.Narrow => new PdfPageMargins(12, 10),
        PdfMarginPreset.Wide => new PdfPageMargins(25, 25),
        _ => Normal,
    };

    /// <summary>The default Normal margin preset.</summary>
    public static PdfPageMargins Normal { get; } = new(18, 16);
}
