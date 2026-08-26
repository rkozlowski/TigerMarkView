namespace TigerMarkView.Core.Exporting;

/// <summary>
/// The named paper sizes the GUI and CLI offer. Arbitrary physical dimensions remain expressible by
/// constructing <see cref="PdfPageSetup"/> directly; this enum does not need a <c>Custom</c> member
/// whose actual dimensions would have to live elsewhere.
/// </summary>
public enum PdfPaperSize
{
    A3,
    A4,
    A5,
    Letter,
    Legal,
}
