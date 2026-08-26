namespace TigerMarkView.Core.Exporting;

/// <summary>
/// Which way round the chosen paper is used. Applied by swapping the paper's width and height when
/// the page setup is built, so nothing downstream — CSS, print settings, the PDF's MediaBox — has to
/// know an orientation exists; they all see one already-correct page box.
/// </summary>
public enum PdfOrientation
{
    Portrait,
    Landscape,
}
