namespace TigerMarkView.Core.Exporting;

/// <summary>
/// The three margin choices the GUI offers. Deliberately presets rather than four numeric boxes:
/// margins are the setting a reader is least able to judge in the abstract and most likely to get
/// wrong, and three named answers cover what a reading-and-review tool actually needs.
/// </summary>
/// <remarks>
/// The physical values live in <see cref="PdfPageMargins.For"/>, in one place, in millimetres.
/// </remarks>
public enum PdfMarginPreset
{
    Narrow,
    Normal,
    Wide,
}
